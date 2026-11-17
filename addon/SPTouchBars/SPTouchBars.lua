-- Assignments belong to this addon, never to WoW's action slots. Secure snippets select
-- preloaded spell, item, or named-macro attributes when modifiers or sets change in combat.
local ADDON = ...
local MAX_BUTTONS, UTILITY_FIRST = 12, 61
local MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local db, header, utility, utilityGroup, panel, switch, controlsHeader
local extras, refreshSettings = {}, nil
local ownsNearbyInteract, pendingNearbyInteract = false, false
local updateInteractAction
local handledQuests, questNPC = {}, nil
local spells, tools = {}, {}
local editing, selected, refreshPanel, editPage = false, nil, nil, 1
local initialized, pendingInit = false, false
local apply, defaultBarsContainer, openOutlinePicker
local previewing, editSnapshot = false, nil
-- A physical pad takes over from the touch bars. The app hides its own touch controls itself; the
-- bars follow on the pad's first button press and return when a pad disconnects.
local padMode = false
local VISIBILITY = "[petbattle][vehicleui][possessbar][overridebar]hide;show"
local function isSelected(button)
    return editing and not previewing and selected and (selected == button or selected.kind == "utility" and button.kind == "utility")
end
local function configFor(button)
    if button.kind == "utility" then return db.utilityLayout end
    return db[button.kind][button.index]
end
local defaultBarParents = {}

local function say(message) print("|cff68d5cfSPTouchBars:|r " .. message) end
local function secret(value) return issecretvalue and issecretvalue(value) end
local function readable(value) return not secret(value) end
local function clamp(value, lo, hi) return math.max(lo, math.min(hi, value)) end
local function number(value, fallback, lo, hi)
    if type(value) ~= "number" or value ~= value then return fallback end
    return clamp(value, lo, hi)
end
local function defaults()
    return { count = 6, utilityCount = 8, bank = 1, layers = true,
             spells = {}, utility = {}, bindings = {}, hideDefaultBars = true, version = 5 }
end
local function defaultSpell(i)
    local offsets = { {0, 0}, {0, 140}, {-100, 100}, {-140, 0}, {-100, -100},
                      {0, -140}, {-240, 180}, {-240, 90}, {-240, 0}, {-240, -90},
                      {-240, -180}, {-330, 0} }
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    return { x = 0.9 + offsets[i][1] / w, y = 0.5 + offsets[i][2] / h,
             size = i == 1 and 100 or 68 }
end
local function defaultUtility(i)
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    return { x = 0.5 + (i - (db.utilityCount + 1) / 2) * 62 / w, y = 44 / h, size = 52 }
end
local function defaultControl(key)
    local positions = { interact = {0.72, 0.3}, target = {0.8, 0.22}, switch = {0.94, 0.79}, map = {0.82, 0.86} }
    local config = { x = positions[key][1], y = positions[key][2],
                     size = key == "map" and 44 or key == "switch" and 56 or 64, enabled = true }
    if key == "map" and Minimap and Minimap:GetLeft() and Minimap:GetBottom() then
        local scale = Minimap:GetEffectiveScale() / UIParent:GetEffectiveScale()
        config.x = (Minimap:GetLeft() * scale - 30) / UIParent:GetWidth()
        config.y = (Minimap:GetBottom() * scale + 24) / UIParent:GetHeight()
    end
    return config
end
local function loadSettings()
    if type(SPTouchBarsDB) ~= "table" then SPTouchBarsDB = defaults() end
    db = SPTouchBarsDB
    db.count = math.floor(number(db.count, 6, 1, MAX_BUTTONS))
    db.utilityCount = math.floor(number(db.utilityCount, 8, 0, MAX_BUTTONS))
    db.bank = db.bank == 5 and 5 or 1
    -- Migrate the old all-or-nothing switch without changing anyone's enabled layers.
    if type(db.layers) ~= "table" then
        local enabled = db.layers ~= false
        db.layers = { ctrl = enabled, alt = enabled, shift = enabled }
    end
    for _, key in ipairs({ "ctrl", "alt", "shift" }) do db.layers[key] = db.layers[key] ~= false end
    db.hideDefaultBars = db.hideDefaultBars ~= false
    db.nearbyInteract = db.nearbyInteract ~= false
    db.questInteract = db.questInteract ~= false
    db.padAuto = db.padAuto ~= false
    if type(db.appearance) ~= "table" then db.appearance = {} end
    if type(db.visibility) ~= "table" then db.visibility = {} end
    for _, group in ipairs({ "spells", "utility" }) do
        local style = db.appearance[group]
        if type(style) ~= "table" then
            style = { outlineAlpha = db.outlineAlpha }
            -- Copy legacy colours separately so editing one group cannot change the other.
            if type(db.outlineColor) == "table" then
                style.outlineColor = { r = db.outlineColor.r, g = db.outlineColor.g, b = db.outlineColor.b }
            end
        end
        style.outlineAlpha = number(style.outlineAlpha, 1, 0, 1)
        style.glow = number(style.glow, 1, 0, 1)
        if type(style.outlineColor) == "table" then
            for _, key in ipairs({ "r", "g", "b" }) do
                style.outlineColor[key] = number(style.outlineColor[key], 0.65, 0, 1)
            end
        else style.outlineColor = nil end
        db.appearance[group] = style
        local visibility = type(db.visibility[group]) == "table" and db.visibility[group] or {}
        visibility.enabled = visibility.enabled ~= false
        visibility.hideEmpty = visibility.hideEmpty ~= false
        db.visibility[group] = visibility
    end
    db.outlineColor, db.outlineAlpha = nil, nil
    -- Earlier versions mirrored native slots. Keep their layout, but begin with empty private
    -- assignments rather than importing or changing anything on the player's original bars.
    if type(db.bindings) ~= "table" then db.bindings = {} end
    db.version = 5
    for key, entry in pairs(db.bindings) do
        if type(key) ~= "number" or key < 1 or key > 72 or key % 1 ~= 0 or type(entry) ~= "table"
            or not ((entry.kind == "spell" or entry.kind == "item") and type(entry.value) == "number"
                    and entry.value > 0 and entry.value % 1 == 0
                or entry.kind == "macro" and type(entry.value) == "string" and #entry.value > 0) then
            db.bindings[key] = nil
        end
    end
    if type(db.spells) ~= "table" then db.spells = {} end
    if type(db.utility) ~= "table" then db.utility = {} end
    for i = 1, MAX_BUTTONS do
        for _, kind in ipairs({ "spells", "utility" }) do
            local fallback = kind == "spells" and defaultSpell(i) or defaultUtility(i)
            local config = db[kind][i]
            if type(config) ~= "table" then config = fallback end
            config.x = number(config.x, fallback.x, 0, 1)
            config.y = number(config.y, fallback.y, 0, 1)
            config.size = number(config.size, fallback.size, 44, 140)
            db[kind][i] = config
        end
    end
    -- Collapse the old individually positioned utility icons into a shared grid, preserving its center.
    if type(db.utilityLayout) ~= "table" then
        local x, y, count = 0, 0, math.max(db.utilityCount, 1)
        for i = 1, count do x = x + db.utility[i].x; y = y + db.utility[i].y end
        db.utilityLayout = { x = x / count, y = y / count, size = db.utility[1].size, rows = 1 }
    end
    local layout = db.utilityLayout
    layout.x = number(layout.x, 0.5, 0, 1)
    layout.y = number(layout.y, 44 / UIParent:GetHeight(), 0, 1)
    layout.size = number(layout.size, 52, 44, 140)
    layout.rows = math.floor(number(layout.rows, 1, 1, MAX_BUTTONS))
    layout.spacing = number(layout.spacing, 10, 0, 48)
    if type(db.controls) ~= "table" then db.controls = {} end
    for _, key in ipairs({ "interact", "target", "switch", "map" }) do
        local fallback = defaultControl(key)
        local config = type(db.controls[key]) == "table" and db.controls[key] or fallback
        config.x = number(config.x, fallback.x, 0, 1)
        config.y = number(config.y, fallback.y, 0, 1)
        config.size = number(config.size, fallback.size, 44, 140)
        config.enabled = config.enabled ~= false
        db.controls[key] = config
    end
end

local function binding(button) return db.bindings[button:GetAttribute("binding")] end
local function content(entry)
    if not entry then return end
    if entry.kind == "spell" then return entry.value, nil, C_Spell.GetSpellTexture(entry.value) end
    if entry.kind == "item" then return nil, entry.value, C_Item.GetItemIconByID(entry.value) end
    local index = GetMacroIndexByName(entry.value)
    if index == 0 then return nil, nil, entry.icon end
    local _, icon = GetMacroInfo(index)
    local spell = GetMacroSpell(index)
    if readable(spell) and spell then return spell, nil, icon end
    local _, link = GetMacroItem(index)
    local item = link and C_Item.GetItemInfoInstant(link)
    return nil, item, icon
end
local function readableCooldown(widget, info)
    if info and readable(info.startTime) and readable(info.duration)
        and readable(info.modRate) and readable(info.isEnabled)
        and info.isEnabled ~= false and info.isEnabled ~= 0 then
        widget:SetCooldown(info.startTime or 0, info.duration or 0, info.modRate or 1)
    else widget:Clear() end
end
local function cooldown(button, spell, item)
    button.chargeCooldown:Clear()
    if spell then
        local duration = C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(spell)
        if duration then button.cooldown:SetCooldownFromDurationObject(duration)
        else readableCooldown(button.cooldown, C_Spell.GetSpellCooldown(spell)) end
        local charge = C_Spell.GetSpellChargeDuration and C_Spell.GetSpellChargeDuration(spell)
        if charge then button.chargeCooldown:SetCooldownFromDurationObject(charge) end
    elseif item then
        local start, length, enabled = C_Container.GetItemCooldown(item)
        readableCooldown(button.cooldown, { startTime = start, duration = length, isEnabled = enabled })
    else button.cooldown:Clear() end
end
local function updateButton(button)
    local entry = binding(button)
    local spell, item, texture = content(entry)
    if readable(texture) then
        button.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
        button.icon:SetAlpha(texture and 1 or 0)
    end
    local usable, mana, range = true, false, nil
    if spell then
        usable, mana = C_Spell.IsSpellUsable(spell)
        if C_Spell.IsSpellInRange then range = C_Spell.IsSpellInRange(spell, "target") end
    end
    if readable(range) and range == false then
        button.icon:SetVertexColor(1, 0.35, 0.3)
    elseif readable(usable) and readable(mana) then
        if usable then button.icon:SetVertexColor(1, 1, 1)
        elseif mana then button.icon:SetVertexColor(0.5, 0.65, 1)
        else button.icon:SetVertexColor(0.5, 0.5, 0.5) end
    else
        button.icon:SetVertexColor(1, 1, 1)
    end
    local count
    if item then count = C_Item.GetItemCount(item, false, true)
    elseif spell then
        local charges = C_Spell.GetSpellCharges(spell)
        if charges then count = charges.currentCharges end
    end
    if readable(count) and (count == nil or count == 1) then button.count:SetText("")
    else button.count:SetText(count) end -- Secret counts go directly to the widget sink.
    button.active:SetShown(isSelected(button) and true or false)
    cooldown(button, spell, item)
    button.slotLabel:SetText(editing and not previewing and button.index or (not entry and "+" or ""))
end
local function refresh()
    if not initialized then return end
    for _, group in ipairs({ spells, tools }) do
        for _, button in ipairs(group) do
            if button:IsShown() then updateButton(button) end
        end
    end
end

local function cursorBinding()
    local kind, value, subtype, extra = GetCursorInfo()
    if kind == "spell" then
        -- The spellbook cursor's second value is an index, not the castable spell ID.
        local id = extra
        if not id and C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
            local info = C_SpellBook.GetSpellBookItemInfo(value, Enum.SpellBookSpellBank.Player)
            id = info and info.spellID
        end
        if id then return { kind = "spell", value = id } end
    elseif kind == "item" then return { kind = "item", value = value }
    elseif kind == "macro" then
        local name, icon = GetMacroInfo(value)
        if name then return { kind = "macro", value = name, icon = icon } end
    elseif kind == "mount" and C_MountJournal then
        local _, id = C_MountJournal.GetMountInfoByID(value)
        if id then return { kind = "spell", value = id } end
    elseif kind == "action" then
        -- Copying from a native action cursor never places or swaps an action back into a WoW slot.
        local actionType, id = GetActionInfo(value)
        if actionType == "spell" or actionType == "item" then return { kind = actionType, value = id }
        elseif actionType == "macro" then
            local name, icon = GetMacroInfo(id)
            if name then return { kind = "macro", value = name, icon = icon } end
        end
    end
end
local function receive(button)
    if not editing or InCombatLockdown() or not GetCursorInfo() then return end
    local entry = cursorBinding()
    if not entry then say("Drag an individual spell, item, mount, or macro onto this button."); return end
    db.bindings[button:GetAttribute("binding")] = entry
    selected = button
    ClearCursor()
    apply()
end

local function preload(button)
    for page = 1, 6 do
        local entry = db.bindings[(page - 1) * MAX_BUTTONS + button.index]
        button:SetAttribute("binding-type-" .. page, entry and entry.kind)
        for _, kind in ipairs({ "spell", "item", "macro" }) do
            local value
            if entry and entry.kind == kind then value = kind == "item" and ("item:" .. entry.value) or entry.value end
            button:SetAttribute("binding-" .. kind .. "-" .. page, value)
        end
    end
end

local function updateDefaultBars()
    if not defaultBarsContainer then
        defaultBarsContainer = CreateFrame("Frame", "SPTouchBarsDefaultBars", UIParent, "SecureHandlerStateTemplate")
        defaultBarsContainer:SetAllPoints(UIParent)
        defaultBarsContainer:EnableMouse(false)
        RegisterStateDriver(defaultBarsContainer, "visibility", "[vehicleui][possessbar][overridebar]show;hide")
    end
    -- Only normal player bars. PetActionBar, StanceBar, OverrideActionBar, PossessActionBar,
    -- ExtraActionBarFrame, and VehicleLeaveButton retain their native parents and visibility rules.
    for _, name in ipairs({ "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight",
                            "MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7" }) do
        local bar = _G[name]
        if bar then
            if db.hideDefaultBars and not padMode then
                if not defaultBarParents[bar] then defaultBarParents[bar] = bar:GetParent() end
                if bar:GetParent() ~= defaultBarsContainer then bar:SetParent(defaultBarsContainer) end
            elseif defaultBarParents[bar] then
                bar:SetParent(defaultBarParents[bar])
                defaultBarParents[bar] = nil
            end
        end
    end
end

local function circle(parent, layer, inset, r, g, b, a)
    local texture = parent:CreateTexture(nil, layer)
    texture:SetPoint("TOPLEFT", inset, -inset)
    texture:SetPoint("BOTTOMRIGHT", -inset, inset)
    texture:SetTexture(MASK)
    texture:SetVertexColor(r, g, b, a or 1)
    return texture
end
-- Shared button shell: a soft halo, two bevels, and a separate press wash. Only textures
-- change on input, so feedback cannot resize or mutate secure action frames during combat.
local function paintButton(button)
    local chosen = isSelected(button)
    local pressed = button.pressed and not editing
    local r, g, b = 0.32, 0.65, 0.7
    if button.accent then r, g, b = unpack(button.accent) end
    local style = db.appearance[button.kind == "utility" and "utility" or "spells"]
    if style.outlineColor then r, g, b = style.outlineColor.r, style.outlineColor.g, style.outlineColor.b end
    local alpha = style.outlineAlpha
    local intensity = 1
    if chosen then r, g, b, intensity = 0.1, 1, 0.85, 3
    elseif pressed then r, g, b, intensity = 1, 0.83, 0.36, 4
    elseif editing and not previewing then r, g, b, intensity = 0.95, 0.69, 0.25, 1.5 end
    button.rim:SetVertexColor(r * 0.7, g * 0.7, b * 0.7, alpha)
    button.bevel:SetVertexColor(math.min(1, r + 0.2), math.min(1, g + 0.2), math.min(1, b + 0.2), alpha)
    for i, glow in ipairs(button.glow) do
        glow:SetVertexColor(r, g, b, (0.025 + i * 0.02) * intensity * alpha * style.glow)
    end
    if button.translucent then button.face:SetVertexColor(0.2, 0.48, 0.52, 0.12) end
    if button.arrowGlyph then
        -- Keep the glyph legible independently of the translucent shell.
        local ar, ag, ab = 0.82, 0.93, 0.94
        if chosen or pressed or editing and not previewing then ar, ag, ab = r, g, b end
        button.arrowGlyph:SetVertexColor(ar, ag, ab, 1)
        if button.stateLabel then button.stateLabel:SetTextColor(ar, ag, ab, 1) end
    end
    button.active:SetShown(chosen and true or false)
    button.pressOverlay:SetShown(pressed and true or false)
end
local function skinButton(button, square)
    local function surface(layer, inset, r, g, b, a)
        local texture = circle(button, layer, inset, r, g, b, a)
        if square then texture:SetTexture("Interface\\Buttons\\WHITE8X8") end
        return texture
    end
    button.glow = {}
    for i, inset in ipairs({ -8, -5, -2 }) do
        local glow = surface("BACKGROUND", inset, 0.32, 0.65, 0.7, 0.025 + i * 0.02)
        glow:SetBlendMode("ADD")
        glow:SetDrawLayer("BACKGROUND", i - 4)
        button.glow[i] = glow
    end
    button.rim = surface("BACKGROUND", 0, 0.23, 0.46, 0.49)
    button.bevel = surface("BORDER", 1, 0.5, 0.66, 0.7)
    button.face = surface("BORDER", 3, 0.035, 0.065, 0.08)
    button.face:SetDrawLayer("BORDER", 1)
    button.active = surface("OVERLAY", 0, 0.1, 1, 0.85, 0.22)
    button.active:Hide()
    button.pressOverlay = surface("OVERLAY", 3, 1, 0.85, 0.48, 0.28)
    button.pressOverlay:SetDrawLayer("OVERLAY", 1)
    button.pressOverlay:Hide()
end
local function maskIcon(button)
    local mask = button:CreateMaskTexture()
    mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(button.icon)
    button.icon:AddMaskTexture(mask)
end
local function stopMoving(button)
    button.moving = false
end
local function position(button)
    local config = configFor(button)
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local half = config.size / 2 + 4
    local x, y = clamp(config.x * w, half, w - half), clamp(config.y * h, half, h - half)
    button:ClearAllPoints()
    button:SetSize(config.size, config.size)
    button:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    if button.arrowArt then button.arrowArt:SetScale(config.size / 56) end
    -- Save clamping, too, so resizing never leaves the stored position beyond the screen.
    config.x, config.y = x / w, y / h
end
local function layoutUtility()
    local config = db.utilityLayout
    local count = math.max(db.utilityCount, 1)
    local rows = math.min(config.rows, count)
    local columns = math.ceil(count / rows)
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    -- Reduce spacing only when needed to retain useful touch targets on a smaller display.
    local gap = math.min(config.spacing,
        math.max(0, (w - 8 - columns * 44) / math.max(columns - 1, 1)),
        math.max(0, (h - 8 - rows * 44) / math.max(rows - 1, 1)))
    -- Fit the complete grid on smaller/rotated displays without losing the requested size.
    local size = math.min(config.size, (w - 8 - gap * (columns - 1)) / columns,
                          (h - 8 - gap * (rows - 1)) / rows)
    local width, height = columns * (size + gap) - gap, rows * (size + gap) - gap
    local x = clamp(config.x * w, width / 2 + 4, w - width / 2 - 4)
    local y = clamp(config.y * h, height / 2 + 4, h - height / 2 - 4)
    config.x, config.y = x / w, y / h
    utilityGroup:ClearAllPoints()
    utilityGroup:SetSize(width, height)
    utilityGroup:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    for i, button in ipairs(tools) do
        button:ClearAllPoints()
        button:SetSize(size, size)
        local column, row = (i - 1) % columns, math.floor((i - 1) / columns)
        button:SetPoint("CENTER", utilityGroup, "CENTER",
            -width / 2 + size / 2 + column * (size + gap), height / 2 - size / 2 - row * (size + gap))
    end
end
local function selectionVisuals()
    for _, group in ipairs({ spells, tools, extras }) do
        for _, button in ipairs(group) do paintButton(button) end
    end
end
local function makeEditable(button)
    button:SetScript("OnMouseDown", function(self, mouse)
        if not editing or InCombatLockdown() or mouse ~= "LeftButton" then return end
        selected = self
        selectionVisuals()
        if refreshPanel then refreshPanel() end
        if not GetCursorInfo() then
            local x, y = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            local anchor = self.kind == "utility" and utilityGroup or self
            local bx, by = anchor:GetCenter()
            self.dragX, self.dragY = bx - x / scale, by - y / scale
            self.moving = true
        end
    end)
    button:SetScript("OnMouseUp", function(self) stopMoving(self) end)
    button:SetScript("OnUpdate", function(self)
        if self.pressed and not IsMouseButtonDown("LeftButton") then
            self.pressed = false
            paintButton(self)
        end
        if not self.moving then return end
        if InCombatLockdown() or not editing or not IsMouseButtonDown("LeftButton") then stopMoving(self); return end
        local x, y = GetCursorPosition()
        local scale, config = UIParent:GetEffectiveScale(), configFor(self)
        config.x = (x / scale + self.dragX) / UIParent:GetWidth()
        config.y = (y / scale + self.dragY) / UIParent:GetHeight()
        if self.kind == "utility" then layoutUtility() else position(self) end
    end)
    button:HookScript("OnMouseDown", function(self, mouse)
        if mouse == "LeftButton" then self.pressed = true; paintButton(self) end
    end)
    button:HookScript("OnMouseUp", function(self, mouse)
        if mouse == "LeftButton" then self.pressed = false; paintButton(self) end
    end)
    button:HookScript("OnHide", function(self)
        self.pressed = false
        stopMoving(self)
        paintButton(self)
    end)
end
local function createButton(parent, kind, index)
    local name = "SPTouchBars" .. (kind == "spells" and "Spell" or "Utility") .. index
    local button = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
    button.kind, button.index = kind, index
    button:SetID(0)
    button:SetClampedToScreen(true)
    button:RegisterForClicks("AnyDown", "AnyUp")
    -- Fix the activation edge per button; a user's ActionButtonUseKeyDown CVar cannot suppress taps.
    button:SetAttribute("useOnKeyDown", true)
    button:SetAttribute("binding", (kind == "spells" and 0 or UTILITY_FIRST - 1) + index)
    skinButton(button, kind == "utility")
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 6, -6)
    button.icon:SetPoint("BOTTOMRIGHT", -6, 6)
    button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    if kind == "spells" then maskIcon(button) end
    for _, field in ipairs({ "cooldown", "chargeCooldown" }) do
        local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        cd:SetAllPoints(button.icon)
        if kind == "spells" then cd:SetSwipeTexture(MASK) end
        cd:SetDrawEdge(false)
        cd:SetHideCountdownNumbers(field == "chargeCooldown")
        cd:EnableMouse(false)
        button[field] = cd
    end
    button.chargeCooldown:SetDrawSwipe(false)
    button.chargeCooldown:SetDrawEdge(true)
    local textFrame = CreateFrame("Frame", nil, button)
    textFrame:SetAllPoints()
    textFrame:SetFrameLevel(button.chargeCooldown:GetFrameLevel() + 2)
    button.count = textFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
    button.count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -8, 8)
    button.slotLabel = textFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    button.slotLabel:SetPoint("CENTER")
    button:SetScript("OnAttributeChanged", function(self, attribute)
        if attribute == "binding" and initialized then updateButton(self) end
    end)
    makeEditable(button)
    button:SetScript("OnReceiveDrag", function(self)
        receive(self)
    end)
    -- Keep the template's secure OnClick; the hook only handles dropping a spell while editing.
    button:HookScript("OnClick", function(self, _, down)
        if not down and editing and not InCombatLockdown() and GetCursorInfo() then
            receive(self)
        end
    end)
    button:SetScript("OnEnter", function(self)
        if editing or not db.tooltips then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        local spell, item = content(binding(self))
        if spell then GameTooltip:SetSpellByID(spell)
        elseif item then GameTooltip:SetItemByID(item)
        else GameTooltip:Hide(); return end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return button
end

-- The native Forever gamepad Interact owns talk/loot/attack selection. A macro supplies a
-- complete down/up pair to the same native control used by ConsolePort's Forever extension.
local INTERACT_BUTTON = "GamepadMainActionBarFramePageUnitTopCenteredAnchorTopBarActionButton5"
local TARGET_MACRO = "/targetenemy [mod:shift] 1; 0"
local function nativeInteract()
    local frame = GamepadMainActionBarFrame
    if frame and frame.GetActionBars then
        local bars = frame:GetActionBars()
        if bars and bars.topBar and bars.topBar.Right then return bars.topBar.Right.ActionButton1 end
    end
    return _G[INTERACT_BUTTON]
end
-- Enable the same soft-interact mode as WoW's Enable Interact Key checkbox. The default
-- Gamepad flag excludes mouse-style taps on both desktop and Slashplayed. Keep this temporary:
-- hiding/disabling our control or reloading restores the user's saved game setting.
local function releaseNearbyInteraction()
    if InCombatLockdown() then return end
    local any = tostring(Enum.SoftTargetEnableFlags.Any)
    if ownsNearbyInteract and C_CVar.GetCVar("SoftTargetInteract") == any then
        C_CVar.RemoveTempCVar("SoftTargetInteract")
    end
    ownsNearbyInteract = false
end
local function updateNearbyInteraction()
    if InCombatLockdown() then return end
    if padMode or not db.nearbyInteract or not db.controls.interact.enabled or not nativeInteract() then
        releaseNearbyInteraction()
        return
    end
    local any = tostring(Enum.SoftTargetEnableFlags.Any)
    if C_CVar.GetCVar("SoftTargetInteract") ~= any then
        C_CVar.SetTempCVar("SoftTargetInteract", any)
        ownsNearbyInteract = C_CVar.GetCVar("SoftTargetInteract") == any
    end
end
local function shown(frame) return frame and frame:IsShown() end
local function ready(button) return shown(button) and button:IsEnabled() end
local function syncQuestNPC()
    local guid = UnitGUID("npc") or UnitGUID("questnpc")
    if readable(guid) and guid and guid ~= questNPC then handledQuests, questNPC = {}, guid end
end
-- Read the current UI on each press. Events only refresh the caption/payload; they never
-- select, accept, or turn in anything. Every action needs another physical press.
local function questAction()
    if not db.questInteract then return end
    if not shown(QuestFrame) and not shown(GossipFrame) then return end
    syncQuestNPC()
    if shown(QuestFrame) then
        if QuestFrame.dialog and shown(QuestFrame.dialog) then return { caption = "Confirm" } end
        if shown(QuestFrameDetailPanel) then
            return { caption = ready(QuestFrameAcceptButton) and "Accept" or "Wait", button = QuestFrameAcceptButton }
        elseif shown(QuestFrameProgressPanel) then
            return { caption = ready(QuestFrameCompleteButton) and "Continue" or "Not ready", button = QuestFrameCompleteButton }
        elseif shown(QuestFrameRewardPanel) then
            local choices, choice = GetNumQuestChoices(), QuestInfoFrame and QuestInfoFrame.itemChoice or 0
            if choices > 1 and (not choice or choice < 1 or choice > choices) then return { caption = "Reward" } end
            return { caption = "Turn in", button = QuestFrameCompleteQuestButton }
        elseif shown(QuestFrameGreetingPanel) then
            -- The classic greeting lists active quests above available quests.
            for i = 1, GetNumActiveQuests() do
                local _, complete = GetActiveTitle(i)
                local id = GetActiveQuestID(i)
                if complete and handledQuests[id] ~= "turned" then
                    return { caption = "Quest", select = SelectActiveQuest, value = i }
                end
            end
            for i = 1, GetNumAvailableQuests() do
                local _, _, _, _, id = GetAvailableQuestInfo(i)
                if not handledQuests[id] then return { caption = "Quest", select = SelectAvailableQuest, value = i } end
            end
            return { caption = "Done", button = QuestFrameGreetingGoodbyeButton, done = true }
        end
        return { caption = "Wait" }
    end
    if GossipFrame.dialog and shown(GossipFrame.dialog) then return { caption = "Confirm" } end
    -- The gossip UI lists available quests above active quests. Skip incomplete turn-ins,
    -- and skip quests already handled with this NPC (including immediately reoffered repeatables).
    for _, quest in ipairs(C_GossipInfo.GetAvailableQuests()) do
        if not handledQuests[quest.questID] then
            return { caption = "Quest", select = C_GossipInfo.SelectAvailableQuest, value = quest.questID }
        end
    end
    for _, quest in ipairs(C_GossipInfo.GetActiveQuests()) do
        if quest.isComplete and handledQuests[quest.questID] ~= "turned" then
            return { caption = "Quest", select = C_GossipInfo.SelectActiveQuest, value = quest.questID }
        end
    end
    -- Leave non-quest dialogue (shops, travel, confirmations) to its native buttons.
    return { caption = "Choose" }
end
local function questStep(_, mouse, down)
    if down or mouse ~= "LeftButton" or editing or InCombatLockdown() or not db.controls.interact.enabled then return end
    local action = questAction()
    if not action then return end
    if action.select then action.select(action.value)
    elseif ready(action.button) then
        action.button:Click("LeftButton")
        if action.done then handledQuests, questNPC = {}, nil end
    elseif action.caption == "Reward" then say("Choose a quest reward, then press Interact to turn it in.") end
end
updateInteractAction = function()
    if not extras[1] or InCombatLockdown() then return end
    local button, native, action = extras[1], nativeInteract(), questAction()
    local payload
    if action then payload = "/click SPTouchBarsQuestStep LeftButton 0"
    elseif native then payload = "/click " .. native:GetName() .. " LeftButton 1\n/click " .. native:GetName() .. " LeftButton 0" end
    local changed = button:GetAttribute("questmode") ~= (action ~= nil)
        or button:GetAttribute("available") ~= (payload ~= nil) or button:GetAttribute("macrotext") ~= payload
    if changed then
        button:SetAttribute("questmode", action ~= nil)
        button:SetAttribute("available", payload ~= nil)
        button:SetAttribute("macrotext", payload)
    end
    button.caption:SetText(action and action.caption or native and "Interact" or "Unavailable")
    return changed
end
local function updateInteractIcon()
    local button = extras[1]
    if not button then return end
    local action = questAction()
    if action then
        button.caption:SetText(action.caption)
        button.icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
        return
    end
    local source = nativeInteract()
    local icon = source and source.SpecialActionIcon
    if icon then
        local texture = icon:GetTexture()
        if readable(texture) and texture then button.icon:SetTexture(texture) end
    end
end
local function roundControl(name, parent, key, template)
    local button = CreateFrame("Button", name, parent, template)
    button.kind, button.index = "controls", key
    skinButton(button)
    makeEditable(button)
    return button
end
local function createExtraControls()
    if C_AddOns and C_AddOns.LoadAddOn then C_AddOns.LoadAddOn("Blizzard_GamepadActionBars") end
    for i, key in ipairs({ "interact", "target" }) do
        local button = roundControl("SPTouchBars" .. (i == 1 and "Interact" or "Target"), controlsHeader, key, "SecureActionButtonTemplate")
        button:RegisterForClicks("AnyDown", "AnyUp")
        button:SetAttribute("useOnKeyDown", true)
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetPoint("TOPLEFT", 6, -6)
        button.icon:SetPoint("BOTTOMRIGHT", -6, 6)
        button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        maskIcon(button)
        button.accent = i == 1 and { 0.2, 0.85, 0.74 } or { 0.95, 0.55, 0.23 }
        if i == 1 then button.face:SetVertexColor(0.045, 0.21, 0.23) end
        button.icon:SetTexture(i == 1 and "Interface\\Cursor\\Interact" or "Interface\\Icons\\Ability_Hunter_SniperShot")
        button.caption = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        button.caption:SetPoint("BOTTOM", button, "BOTTOM", 0, 8)
        button.caption:SetShadowColor(0, 0, 0, 1)
        button.caption:SetShadowOffset(1, -1)
        button.caption:SetText(i == 1 and "Interact" or "Target")
        extras[i] = button
        controlsHeader:SetFrameRef("button" .. i, button)
    end
    local questButton = CreateFrame("Button", "SPTouchBarsQuestStep", UIParent)
    questButton:Hide()
    questButton:SetScript("OnClick", questStep)
    extras[1]:SetScript("PreClick", function()
        if updateInteractAction() then controlsHeader:Execute([[ self:RunAttribute("update-page") ]]) end
    end)
    controlsHeader:SetAttribute("update-page", [[
        for i = 1, 2 do
            local button = self:GetFrameRef("button" .. i)
            local kind = "macro"
            if self:GetAttribute("editing") then kind = nil end
            if not button:GetAttribute("available") then kind = nil end
            if self:GetAttribute("state-combat") == "1" and button:GetAttribute("questmode") then kind = nil end
            button:SetAttribute("type", kind)
            button:SetAttribute("*type1", kind)
        end
    ]])
end
local function drawCycleArrows(button)
    local art = CreateFrame("Frame", nil, button)
    art:SetSize(56, 56)
    art:SetPoint("CENTER", button, "CENTER", 0, 0)
    art:EnableMouse(false)
    button.arrowArt = art
    -- One antialiased texture from our SVG, not overlapping line primitives. Keep
    -- the hit target independent of the artwork and the middle free for the set.
    local function glyph(layer, x, y)
        local texture = art:CreateTexture(nil, layer)
        texture:SetTexture("Interface\\AddOns\\SPTouchBars\\SPTouchBars")
        texture:SetTexCoord(0, 0.25, 0, 1)
        texture:SetSize(56, 56)
        texture:SetPoint("CENTER", art, "CENTER", x, y)
        return texture
    end
    button.arrowShadow = glyph("BACKGROUND", 0, -0.75)
    button.arrowShadow:SetVertexColor(0, 0, 0, 0.65)
    button.arrowGlyph = glyph("ARTWORK", 0, 0)
end

-- These are private assignment keys, not action slots. All secure payloads are preloaded out of
-- combat. Ctrl wins over Alt, then Shift; the utility header always uses its own sixth bank.
local PAGE_SNIPPET = [[
    local page = tonumber(self:GetAttribute("state-layer")) or 0
    if page == 0 then page = self:GetAttribute("bank") or 1 end
    if self:GetAttribute("editing") then page = self:GetAttribute("editpage") or page end
    self:SetAttribute("activepage", page)
    for i = 1, 12 do
        local button = self:GetFrameRef("button" .. i)
        local kind = button:GetAttribute("binding-type-" .. page)
        local visible = button:GetAttribute("configured") and
            (self:GetAttribute("editing") and not self:GetAttribute("preview") or self:GetAttribute("bar-enabled") and
                (not self:GetAttribute("hide-empty") or kind))
        if visible then button:Show() else button:Hide() end
        if self:GetAttribute("editing") then kind = nil end
        button:SetAttribute("type", kind)
        button:SetAttribute("*type1", kind)
        button:SetAttribute("spell", button:GetAttribute("binding-spell-" .. page))
        button:SetAttribute("item", button:GetAttribute("binding-item-" .. page))
        button:SetAttribute("macro", button:GetAttribute("binding-macro-" .. page))
        button:SetAttribute("binding", (page - 1) * 12 + i)
    end
]]
local COMBAT_SNIPPET = [[
    if newstate == "1" then
        self:SetAttribute("editing", false)
        self:RunAttribute("update-page")
    end
]]
local function driver()
    local conditions = {}
    if db.layers.ctrl then conditions[#conditions + 1] = "[mod:ctrl]4" end
    if db.layers.alt then conditions[#conditions + 1] = "[mod:alt]3" end
    if db.layers.shift then conditions[#conditions + 1] = "[mod:shift]2" end
    conditions[#conditions + 1] = "0"
    RegisterStateDriver(header, "layer", table.concat(conditions, ";"))
end
local setEditing
apply = function()
    if InCombatLockdown() then return end
    header:SetAttribute("editing", editing)
    header:SetAttribute("editpage", editPage)
    utility:SetAttribute("editing", editing)
    header:SetAttribute("preview", previewing)
    utility:SetAttribute("preview", previewing)
    for _, group in ipairs({ { header, "spells" }, { utility, "utility" } }) do
        group[1]:SetAttribute("bar-enabled", db.visibility[group[2]].enabled)
        group[1]:SetAttribute("hide-empty", db.visibility[group[2]].hideEmpty)
    end
    for _, group in ipairs({ spells, tools }) do
        for i, button in ipairs(group) do
            if button.kind == "spells" then position(button) end
            button:SetAttribute("configured", i <= (button.kind == "spells" and db.count or db.utilityCount))
            preload(button)
        end
    end
    layoutUtility()
    for _, button in ipairs(extras) do
        position(button)
        button:SetShown(db.controls[button.index].enabled)
    end
    updateInteractAction()
    updateNearbyInteraction()
    extras[2]:SetAttribute("available", true)
    extras[2]:SetAttribute("macrotext", TARGET_MACRO)
    controlsHeader:SetAttribute("editing", editing)
    controlsHeader:Execute([[ self:RunAttribute("update-page") ]])
    selectionVisuals()
    driver()
    header:Execute([[ self:RunAttribute("update-page") ]])
    utility:Execute([[ self:RunAttribute("update-page") ]])
    refresh()
    if refreshPanel then refreshPanel() end
    updateDefaultBars()
    updateInteractIcon()
    if refreshSettings then refreshSettings() end
    -- The editor stays reachable with a pad connected.
    local visibility = padMode and not editing and "hide" or VISIBILITY
    for _, frame in ipairs({ header, utility, controlsHeader }) do RegisterStateDriver(frame, "visibility", visibility) end
end
-- The touch joystick is a left stick only, so a held button is always a physical pad's. Only the
-- real buttons are read (d-pad, face, stick clicks, shoulders, triggers: the first 16), never a
-- stick direction reported as a button.
local function padButtonDown()
    if not (C_GamePad and C_GamePad.GetAllDeviceIDs and C_GamePad.GetDeviceMappedState) then return false end
    local ok, ids = pcall(C_GamePad.GetAllDeviceIDs)
    if not ok or type(ids) ~= "table" then return false end
    for _, id in ipairs(ids) do
        local read, state = pcall(C_GamePad.GetDeviceMappedState, id)
        local buttons = read and type(state) == "table" and state.buttons
        if type(buttons) == "table" then
            for i = 1, math.min(#buttons, 16) do
                if readable(buttons[i]) and buttons[i] == true then return true end
            end
        end
    end
    return false
end
local function setPadMode(on)
    on = on and db.padAuto and true or false
    if on == padMode then return end
    padMode = on
    say(on and "Controller in use: touch bars hidden. /sptouch pad turns this off." or "Touch bars shown.")
    if not InCombatLockdown() then apply() end  -- else PLAYER_REGEN_ENABLED applies it
end
local function control(parent, label, x, y, width, callback)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 44)
    button:SetPoint("TOPLEFT", x, y)
    button:SetText(label)
    button:SetScript("OnClick", function() if not InCombatLockdown() then callback() end end)
    return button
end
local function label(parent, text, x, y)
    local font = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    font:SetPoint("TOPLEFT", x, y)
    font:SetText(text)
    return font
end
-- Ordinary WoW widgets only; action frames keep their secure templates and scripts.
local function editorButton(parent, name, text, x, y, width, callback, primary)
    local button = CreateFrame("Button", name, parent, "BackdropTemplate")
    button:SetSize(width, 36)
    button:SetPoint("TOPLEFT", x, y)
    button:SetHitRectInsets(0, 0, -4, -4)
    button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    button.Text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    button.Text:SetPoint("CENTER")
    button:SetFontString(button.Text)
    button:SetText(text)
    local function paint(hover)
        local accent = primary or button.chosen
        button:SetBackdropColor(accent and 0.32 or hover and 0.17 or 0.105,
            accent and 0.27 or hover and 0.20 or 0.135, accent and 0.17 or hover and 0.20 or 0.135, 1)
        button:SetBackdropBorderColor(accent and 0.78 or 0.27, accent and 0.65 or 0.32, accent and 0.39 or 0.31)
        button.Text:SetTextColor(accent and 1 or 0.86, accent and 0.88 or 0.89, accent and 0.61 or 0.85)
    end
    button.paint = paint
    button:SetScript("OnEnter", function() paint(true) end)
    button:SetScript("OnLeave", function() paint(false) end)
    button:SetScript("OnClick", function() if not InCombatLockdown() then callback() end end)
    paint(false)
    return button
end
local function copySettings(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, entry in pairs(value) do result[key] = copySettings(entry) end
    return result
end
local function resetPositions()
    for i = 1, 12 do db.spells[i] = defaultSpell(i) end
    db.utilityLayout = { x = 0.5, y = 44 / UIParent:GetHeight(), size = 52, rows = 1, spacing = 10 }
    for _, key in ipairs({ "interact", "target", "switch", "map" }) do
        local enabled = db.controls[key].enabled
        db.controls[key] = defaultControl(key)
        db.controls[key].enabled = enabled
    end
    apply()
end
local function createPanel()
    panel = CreateFrame("Frame", "SPTouchBarsEditor", UIParent, "BackdropTemplate")
    panel:SetPoint("TOPLEFT", 24, -100)
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) if not InCombatLockdown() then self:StartMoving() end end)
    panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    panel:SetBackdropColor(0.055, 0.075, 0.075, 1)
    panel:SetBackdropBorderColor(0.43, 0.40, 0.30)
    local title = label(panel, "Touch bars", 16, -16)
    title:SetFontObject("GameFontNormalLarge")
    local selectionLabel = label(panel, "", 16, -42)
    selectionLabel:SetTextColor(0.70, 0.76, 0.71)
    local previewButton = editorButton(panel, "SPTouchBarsPreview", "Preview", 224, -10, 80, function()
        previewing = not previewing; apply()
    end)
    local body = CreateFrame("Frame", "SPTouchBarsEditorBody", panel)
    body:SetPoint("TOPLEFT", 0, -116)
    body:SetSize(320, 380)
    local pages, updates, tabs = {}, {}, {}
    local section, group, syncing = "layout", "spells", false
    local function chooseGroup(kind)
        group, section = kind, "layout"
        if kind == "utility" then selected = tools[1]
        elseif not selected or selected.kind ~= kind then selected = nil end
        selectionVisuals(); refreshPanel()
    end
    for i, info in ipairs({ {"spells", "Spells"}, {"utility", "Utility"}, {"controls", "Controls"} }) do
        local key = info[1]
        tabs[key] = editorButton(panel, "SPTouchBarsTab" .. key, info[2], 16 + (i - 1) * 98, -68, 92, function() chooseGroup(key) end)
    end
    local function page(key, height)
        local frame = CreateFrame("Frame", "SPTouchBarsEditor" .. key .. (key == "More" and "Page" or ""), body)
        frame:SetAllPoints(body)
        frame.height = height
        pages[key] = frame
        return frame
    end
    local function button(parent, name, text, x, y, width, callback)
        return editorButton(parent, "SPTouchBarsEditor" .. name, text, x, -y, width, callback)
    end
    local function counter(parent, name, text, y, get, change, lo, hi)
        local caption = label(parent, "", 16, -y - 10)
        button(parent, name .. "Decrease", "-", 216, y, 40, function() change(clamp(get() - 1, lo, hi())); apply() end)
        button(parent, name .. "Increase", "+", 264, y, 40, function() change(clamp(get() + 1, lo, hi())); apply() end)
        updates[#updates + 1] = function() caption:SetText(text .. ": " .. get()) end
    end
    local function range(parent, name, text, y, lo, hi, step, get, change, suffix)
        local caption = label(parent, "", 16, -y)
        local slider = CreateFrame("Slider", "SPTouchBarsEditor" .. name, parent, "MinimalSliderTemplate")
        slider:SetSize(192, 20)
        slider:SetPoint("TOPLEFT", 64, -y - 32)
        slider:SetHitRectInsets(0, 0, -12, -12)
        slider:SetMinMaxValues(lo, hi)
        slider:SetValueStep(step)
        slider:SetObeyStepOnDrag(true)
        local function changed(value)
            if syncing then return end
            if get() == nil or InCombatLockdown() then refreshPanel(); return end
            change(clamp(math.floor(value / step + 0.5) * step, lo, hi))
            apply()
        end
        slider:SetScript("OnValueChanged", function(_, value) changed(value) end)
        local decrease = button(parent, name .. "Decrease", "-", 16, y + 20, 40, function()
            local value = get(); if value then changed(value - step) end
        end)
        local increase = button(parent, name .. "Increase", "+", 264, y + 20, 40, function()
            local value = get(); if value then changed(value + step) end
        end)
        updates[#updates + 1] = function()
            local value = get()
            local available = value ~= nil
            caption:SetText(available and (text .. ": " .. math.floor(value + 0.5) .. (suffix or ""))
                or "Select a button to resize")
            slider:SetShown(available)
            decrease:SetShown(available)
            increase:SetShown(available)
            if available then slider:SetValue(value) end
        end
        return slider
    end
    local function toggle(parent, name, text, y, get, change)
        local caption = label(parent, text, 16, -y - 10)
        local widget = button(parent, name, "", 244, y, 60, function() change(not get()); apply() end)
        updates[#updates + 1] = function()
            widget:SetText(get() and "On" or "Off")
            widget.chosen = get(); widget.paint(false)
        end
        return caption
    end
    local function navigate(target) section = target; refreshPanel() end
    local function links(parent, y)
        button(parent, "Appearance" .. parent:GetName(), "Border & glow", 16, y, 140, function() navigate("appearance") end)
        button(parent, "Visibility" .. parent:GetName(), "Visibility", 164, y, 140, function() navigate("visibility") end)
    end
    local spellsPage = page("Spells", 244)
    label(spellsPage, "Editing layer", 16, -10)
    local pageButton = button(spellsPage, "Layer", "", 126, 0, 178, function() editPage = editPage % 5 + 1; apply() end)
    counter(spellsPage, "SpellCount", "Spell buttons", 44, function() return db.count end,
        function(value) db.count = value end, 1, function() return 12 end)
    range(spellsPage, "SelectedSize", "Button size", 96, 44, 140, 4,
        function() return selected and selected.kind == "spells" and configFor(selected).size or nil end,
        function(value) if selected then configFor(selected).size = value end end)
    links(spellsPage, 164)
    label(spellsPage, "Drop a spell, item, or macro onto a circle.\nDrag the highlighted circle to move it.", 16, -212)
    local utilityPage = page("Utility", 324)
    counter(utilityPage, "UtilityCount", "Utility buttons", 0, function() return db.utilityCount end,
        function(value) db.utilityCount = value end, 0, function() return 12 end)
    counter(utilityPage, "UtilityRows", "Rows", 44,
        function() return math.min(db.utilityLayout.rows, math.max(db.utilityCount, 1)) end,
        function(value) db.utilityLayout.rows = value end, 1, function() return math.max(db.utilityCount, 1) end)
    range(utilityPage, "UtilitySize", "Icon size", 96, 44, 140, 4,
        function() return db.utilityLayout.size end, function(value) db.utilityLayout.size = value end)
    range(utilityPage, "UtilitySpacing", "Spacing", 164, 0, 48, 2,
        function() return db.utilityLayout.spacing end, function(value) db.utilityLayout.spacing = value end)
    links(utilityPage, 232)
    label(utilityPage, "Drag any utility icon to move the whole bar.\nSize and spacing apply to the entire grid.", 16, -280)
    local controlsPage = page("Controls", 348)
    local controlButtons = {}
    for i, info in ipairs({ {"map", "Map", 4}, {"interact", "Interact", 1}, {"target", "Target", 2}, {"switch", "Set arrows", 3} }) do
        local key, index = info[1], info[3]
        controlButtons[key] = button(controlsPage, "Select" .. key, info[2], 16, (i - 1) * 44, 220, function()
            selected = extras[index]; selectionVisuals(); refreshPanel()
        end)
        toggle(controlsPage, "Enable" .. key, "", (i - 1) * 44,
            function() return db.controls[key].enabled end, function(value) db.controls[key].enabled = value end)
    end
    range(controlsPage, "ControlSize", "Selected control size", 192, 44, 140, 4,
        function() return selected and selected.kind == "controls" and configFor(selected).size or nil end,
        function(value) if selected then configFor(selected).size = value end end)
    button(controlsPage, "ControlAppearance", "Border & glow", 16, 260, 288, function() navigate("appearance") end)
    label(controlsPage, "Tap a name to select, or toggle On / Off.\nDrag the selected control in the game.", 16, -308)
    local appearance = page("Appearance", 368)
    button(appearance, "AppearanceBack", "< Back to layout", 16, 0, 288, function() navigate("layout") end)
    local appearanceLabel = label(appearance, "", 16, -52)
    local colorButton = button(appearance, "Color", "Outline colour", 16, 76, 288, function()
        openOutlinePicker(group == "utility" and "utility" or "spells")
    end)
    local swatch = colorButton:CreateTexture(nil, "OVERLAY")
    swatch:SetSize(20, 20); swatch:SetPoint("RIGHT", -12, 0)
    local function style() return db.appearance[group == "utility" and "utility" or "spells"] end
    range(appearance, "Outline", "Outline opacity", 128, 0, 100, 1,
        function() return style().outlineAlpha * 100 end, function(value) style().outlineAlpha = value / 100 end, "%")
    range(appearance, "Glow", "Glow strength", 196, 0, 100, 1,
        function() return style().glow * 100 end, function(value) style().glow = value / 100 end, "%")
    button(appearance, "ResetAppearance", "Reset this appearance", 16, 272, 288, function()
        local config = style(); config.outlineColor, config.outlineAlpha, config.glow = nil, 1, 1; apply()
    end)
    label(appearance, "Spell and utility styles are independent.\nIcons stay visible at 0% outline opacity.", 16, -320)
    local visibility = page("Visibility", 200)
    button(visibility, "VisibilityBack", "< Back to layout", 16, 0, 288, function() navigate("layout") end)
    local function visibleGroup() return db.visibility[group == "utility" and "utility" or "spells"] end
    toggle(visibility, "BarEnabled", "Show this bar", 48, function() return visibleGroup().enabled end,
        function(value) visibleGroup().enabled = value end)
    toggle(visibility, "HideEmpty", "Hide empty in play", 92, function() return visibleGroup().hideEmpty end,
        function(value) visibleGroup().hideEmpty = value end)
    label(visibility, "Edit layout reveals your configured slots.\nPreview shows how they look during play.", 16, -148)
    local more = page("More", 344)
    button(more, "MoreBack", "< Back to layout", 16, 0, 288, function() navigate("layout") end)
    local layerButtons = {}
    for i, key in ipairs({ "ctrl", "alt", "shift" }) do
        local modifier = key
        layerButtons[key] = button(more, "Layer" .. key, "", 16 + (i - 1) * 98, 52, 92, function()
            db.layers[modifier] = not db.layers[modifier]; apply()
        end)
    end
    local defaultBarsButton = button(more, "DefaultBars", "", 16, 100, 288, function()
        db.hideDefaultBars = not db.hideDefaultBars; apply()
    end)
    button(more, "CenterUtility", "Center utility bar", 16, 144, 288, function()
        db.utilityLayout.x, db.utilityLayout.y = 0.5, 0; apply()
    end)
    local clearButton = button(more, "Clear", "Clear selected slot", 16, 188, 288, function()
        if selected and selected.kind ~= "controls" then db.bindings[selected:GetAttribute("binding")] = nil; apply() end
    end)
    button(more, "ResetPositions", "Reset positions", 16, 232, 288, resetPositions)
    label(more, "Undo restores this editing session, including\nassignments. Done keeps your changes.", 16, -280)
    local undo = editorButton(panel, "SPTouchBarsEditorUndo", "Undo", 16, 0, 80, function()
        if not editSnapshot then return end
        if ColorPickerFrame then ColorPickerFrame:Hide() end
        db = copySettings(editSnapshot); SPTouchBarsDB = db
        header:SetAttribute("bank", db.bank)
        editPage, previewing, selected, section = db.bank, false, nil, "layout"
        chooseGroup(group); apply()
    end)
    local moreButton = editorButton(panel, "SPTouchBarsEditorMore", "More...", 112, 0, 88, function() navigate("more") end)
    local done = editorButton(panel, "SPTouchBarsEditorDone", "Done", 216, 0, 88, function() setEditing(false) end, true)
    refreshPanel = function()
        local nextGroup = selected and selected.kind == "controls" and "controls" or selected and selected.kind or group
        if nextGroup ~= group then group, section = nextGroup, "layout" end
        local names = { interact = "Interact", target = "Target", switch = "Set arrows", map = "Map" }
        local name = group == "utility" and "Utility bar" or group == "controls" and names[selected and selected.index] or selected and ("Spell " .. selected.index)
        selectionLabel:SetText(name and (name .. " selected") or "Tap a control to select")
        previewButton:SetText(previewing and "Edit" or "Preview")
        previewButton.chosen = previewing; previewButton.paint(false)
        local active = pages[section == "layout" and (group == "spells" and "Spells" or group == "utility" and "Utility" or "Controls")
            or section == "appearance" and "Appearance" or section == "visibility" and "Visibility" or "More"]
        for _, page in pairs(pages) do page:SetShown(page == active) end
        for key, tab in pairs(tabs) do tab.chosen = key == group; tab.paint(false) end
        for key, widget in pairs(controlButtons) do widget.chosen = selected and selected.index == key; widget.paint(false) end
        local layerNames = { "Set 1", "Shift", "Alt", "Ctrl", "Set 2" }
        pageButton:SetText("Layer: " .. layerNames[editPage])
        defaultBarsButton:SetText(db.hideDefaultBars and "Default bars: hidden" or "Default bars: shown")
        for key, widget in pairs(layerButtons) do
            local text = key == "ctrl" and "Ctrl" or key == "alt" and "Alt" or "Shift"
            widget:SetText(text .. (db.layers[key] and ": on" or ": off"))
            widget.chosen = db.layers[key]; widget.paint(false)
        end
        clearButton:SetEnabled(selected and selected.kind ~= "controls" and true or false)
        appearanceLabel:SetText(group == "utility" and "Utility bar appearance" or "Spell and touch-control appearance")
        local color = style().outlineColor or { r = 0.32, g = 0.65, b = 0.7 }
        swatch:SetColorTexture(color.r, color.g, color.b, style().outlineAlpha)
        syncing = true
        for _, update in ipairs(updates) do update() end
        syncing = false
        local height = active.height + 176
        body:SetSize(320, active.height)
        panel:SetSize(320, height)
        panel:SetScale(math.min(1, (UIParent:GetHeight() - 32) / height, (UIParent:GetWidth() - 32) / 320))
        for _, widget in ipairs({ undo, moreButton, done }) do
            widget:ClearAllPoints(); widget:SetPoint("TOPLEFT", widget == undo and 16 or widget == moreButton and 112 or 216, -height + 52)
        end
    end
    panel:Hide()
end
setEditing = function(value)
    if InCombatLockdown() then say("Finish combat before editing."); return end
    for _, group in ipairs({ spells, tools, extras }) do for _, button in ipairs(group) do stopMoving(button) end end
    if value and not editing then editSnapshot = copySettings(db); selected = nil end
    editing, previewing = value, false
    if editing then
        editPage = header:GetAttribute("activepage") or db.bank
    end
    GameTooltip:Hide()
    panel:SetShown(editing)
    apply()
end
openOutlinePicker = function(group)
    if not ColorPickerFrame then C_AddOns.LoadAddOn("Blizzard_ColorPickerFrame") end
    local style = db.appearance[group]
    local oldColor = style.outlineColor
    local oldAlpha = style.outlineAlpha
    local color = oldColor or { r = 0.32, g = 0.65, b = 0.7 }
    local function changed()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        style.outlineColor = { r = r, g = g, b = b }
        style.outlineAlpha = clamp(ColorPickerFrame:GetColorAlpha(), 0, 1)
        selectionVisuals()
        if refreshPanel then refreshPanel() end
        if refreshSettings then refreshSettings() end
    end
    ColorPickerFrame:SetupColorPickerAndShow({
        r = color.r, g = color.g, b = color.b, opacity = oldAlpha, hasOpacity = true,
        swatchFunc = changed, opacityFunc = changed,
        cancelFunc = function()
            style.outlineColor, style.outlineAlpha = oldColor, oldAlpha
            selectionVisuals()
            if refreshPanel then refreshPanel() end
            if refreshSettings then refreshSettings() end
        end,
    })
end
local function createSettings()
    local frame = CreateFrame("Frame", "SPTouchBarsOptions", UIParent)
    frame:Hide()
    label(frame, "SPTouchBars", 20, -20)
    label(frame, "Arrange your touch controls, spell circles, and utility bar.", 20, -54)
    control(frame, "Edit layout", 20, -90, 220, function()
        if SettingsPanel then SettingsPanel:Hide() end
        if GameMenuFrame then GameMenuFrame:Hide() end
        setEditing(true)
    end)
    local interact = control(frame, "", 20, -150, 220, function()
        db.controls.interact.enabled = not db.controls.interact.enabled; apply()
    end)
    local target = control(frame, "", 250, -150, 220, function()
        db.controls.target.enabled = not db.controls.target.enabled; apply()
    end)
    local nearby = control(frame, "", 20, -210, 450, function()
        db.nearbyInteract = not db.nearbyInteract; apply()
    end)
    local modifiers = {}
    for i, key in ipairs({ "ctrl", "alt", "shift" }) do
        local modifier = key
        modifiers[key] = control(frame, "", 20 + (i - 1) * 154, -270, 142, function()
            db.layers[modifier] = not db.layers[modifier]; apply()
        end)
    end
    local questToggle = control(frame, "", 20, -330, 450, function()
        db.questInteract = not db.questInteract; apply()
    end)
    local map = control(frame, "", 20, -390, 220, function()
        db.controls.map.enabled = not db.controls.map.enabled; apply()
    end)
    local cycle = control(frame, "", 250, -390, 220, function()
        db.controls.switch.enabled = not db.controls.switch.enabled; apply()
    end)
    label(frame, "Open Spell buttons or Utility bar in the settings sidebar for appearance\n"
        .. "and visibility. Empty slots reappear in Edit layout for assignments.\n"
        .. "Drag and resize the Map and set arrows there, too.\n\n"
        .. "Quest steps require one press each. Select reward choices manually.", 20, -460)
    local category = Settings.RegisterCanvasLayoutCategory(frame, "SPTouchBars")
    Settings.RegisterAddOnCategory(category)
    local styleRefreshers = {}
    local function appearancePage(group, title, suffix)
        local page = CreateFrame("Frame", "SPTouchBars" .. suffix .. "Options", UIParent)
        page:Hide()
        label(page, title, 20, -20)
        label(page, group == "utility" and "Appearance and visibility for the bottom utility grid."
            or "Appearance for spell circles, Interact, Target, and Map.", 20, -54)
        local enabled = control(page, "", 20, -90, 220, function()
            db.visibility[group].enabled = not db.visibility[group].enabled; apply()
        end)
        local empty = control(page, "", 250, -90, 220, function()
            db.visibility[group].hideEmpty = not db.visibility[group].hideEmpty; apply()
        end)
        local colorButton = control(page, "Outline colour", 20, -150, 220, function() openOutlinePicker(group) end)
        local swatch = colorButton:CreateTexture(nil, "OVERLAY")
        swatch:SetSize(20, 20)
        swatch:SetPoint("RIGHT", -12, 0)
        control(page, "Reset appearance", 250, -150, 220, function()
            local style = db.appearance[group]
            style.outlineColor, style.outlineAlpha, style.glow = nil, 1, 1
            selectionVisuals(); refreshSettings()
        end)
        local updates = {}
        local function slider(key, titleText, y, name)
            local caption = label(page, "", 20, y)
            local widget = CreateFrame("Slider", "SPTouchBars" .. suffix .. name, page, "MinimalSliderTemplate")
            widget:SetSize(450, 20)
            widget:SetPoint("TOPLEFT", 20, y - 30)
            widget:SetHitRectInsets(0, 0, -12, -12)
            widget:SetMinMaxValues(0, 100)
            widget:SetValueStep(1)
            widget:SetObeyStepOnDrag(true)
            local syncing = false
            widget:SetScript("OnValueChanged", function(_, value)
                if syncing then return end
                db.appearance[group][key] = clamp(value / 100, 0, 1)
                selectionVisuals()
                caption:SetText(titleText .. ": " .. math.floor(value + 0.5) .. "%")
            end)
            updates[#updates + 1] = function()
                local value = db.appearance[group][key] * 100
                caption:SetText(titleText .. ": " .. math.floor(value + 0.5) .. "%")
                syncing = true; widget:SetValue(value); syncing = false
            end
        end
        slider("outlineAlpha", "Outline opacity", -220, "OutlineOpacity")
        slider("glow", "Glow intensity", -310, "Glow")
        label(page, "Opacity changes the outline; glow controls the halo strength.\n"
            .. "Icons stay visible at 0%. Press and selection feedback remain available.\n"
            .. "Hidden slots keep their positions and assignments.\n"
            .. "Edit layout reveals the configured slots, even when the bar is off.", 20, -410)
        styleRefreshers[#styleRefreshers + 1] = function()
            enabled:SetText(db.visibility[group].enabled and "Bar: on" or "Bar: off")
            empty:SetText(db.visibility[group].hideEmpty and "Hide empty: on" or "Hide empty: off")
            local style = db.appearance[group]
            local color = style.outlineColor or { r = 0.32, g = 0.65, b = 0.7 }
            swatch:SetColorTexture(color.r, color.g, color.b, style.outlineAlpha)
            for _, update in ipairs(updates) do update() end
        end
        Settings.RegisterCanvasLayoutSubcategory(category, page, title)
    end
    appearancePage("spells", "Spell buttons", "Spells")
    appearancePage("utility", "Utility bar", "Utility")
    refreshSettings = function()
        interact:SetText(db.controls.interact.enabled and "Interact: on" or "Interact: off")
        target:SetText(db.controls.target.enabled and "Target: on" or "Target: off")
        nearby:SetText(db.nearbyInteract and "Nearby interaction: on" or "Nearby interaction: off")
        questToggle:SetText(db.questInteract and "Quest steps: on" or "Quest steps: off")
        map:SetText(db.controls.map.enabled and "Map: on" or "Map: off")
        cycle:SetText(db.controls.switch.enabled and "Set arrows: on" or "Set arrows: off")
        for _, update in ipairs(styleRefreshers) do update() end
        for key, button in pairs(modifiers) do
            local name = key == "ctrl" and "Ctrl" or key == "alt" and "Alt" or "Shift"
            button:SetText(name .. (db.layers[key] and ": on" or ": off"))
        end
    end

end
local function initialize()
    if initialized then return end
    if InCombatLockdown() then pendingInit = true; return end
    loadSettings()
    header = CreateFrame("Frame", "SPTouchBarsHeader", UIParent, "SecureHandlerStateTemplate")
    header:SetAllPoints(UIParent)
    header:EnableMouse(false)
    utility = CreateFrame("Frame", "SPTouchBarsUtilityHeader", UIParent, "SecureHandlerStateTemplate")
    utility:SetAllPoints(UIParent)
    utility:EnableMouse(false)
    utilityGroup = CreateFrame("Frame", "SPTouchBarsUtilityGroup", utility)
    utilityGroup:EnableMouse(false)
    controlsHeader = CreateFrame("Frame", "SPTouchBarsControlsHeader", UIParent, "SecureHandlerStateTemplate")
    controlsHeader:SetAllPoints(UIParent)
    controlsHeader:EnableMouse(false)
    createExtraControls()
    for i = 1, 12 do
        spells[i] = createButton(header, "spells", i)
        tools[i] = createButton(utilityGroup, "utility", i)
        header:SetFrameRef("button" .. i, spells[i])
        utility:SetFrameRef("button" .. i, tools[i])
    end
    switch = roundControl("SPTouchBarsSwitch", header, "switch", "SecureHandlerClickTemplate")
    extras[3] = switch
    switch.translucent = true
    -- Hollow artwork, not the filled discs used behind opaque spell icons.
    for _, texture in ipairs({switch.rim, switch.bevel}) do
        texture:SetTexture("Interface\\AddOns\\SPTouchBars\\SPTouchBars")
        texture:SetTexCoord(0.25, 0.5, 0, 1)
    end
    for _, texture in ipairs(switch.glow) do
        texture:SetTexture("Interface\\AddOns\\SPTouchBars\\SPTouchBars")
        texture:SetTexCoord(0.5, 0.75, 0, 1)
    end
    drawCycleArrows(switch)
    switch.stateLabel = switch.arrowArt:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    switch.stateLabel:SetPoint("CENTER", switch.arrowArt, "CENTER", 0, 0)
    switch.stateLabel:SetShadowColor(0, 0, 0, 1)
    switch.stateLabel:SetShadowOffset(1, -1)
    local map = roundControl("SPTouchBarsMap", controlsHeader, "map")
    extras[4] = map
    map.icon = map:CreateTexture(nil, "ARTWORK")
    map.icon:SetPoint("TOPLEFT", 6, -6)
    map.icon:SetPoint("BOTTOMRIGHT", -6, 6)
    map.icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
    maskIcon(map)
    map:RegisterForClicks("LeftButtonUp")
    map:SetScript("OnClick", function()
        if not editing then ToggleWorldMap() end
    end)
    switch:RegisterForClicks("LeftButtonUp")
    SecureHandlerSetFrameRef(switch, "header", header)
    switch:SetAttribute("_onclick", [[
        local header = self:GetFrameRef("header")
        if header:GetAttribute("editing") then return end
        local bank = header:GetAttribute("bank") == 5 and 1 or 5
        header:SetAttribute("bank", bank)
        header:RunAttribute("update-page")
    ]])
    header:SetAttribute("bank", db.bank)
    header:SetAttribute("update-page", PAGE_SNIPPET)
    utility:SetAttribute("bank", 6)
    utility:SetAttribute("update-page", PAGE_SNIPPET)
    header:SetAttribute("_onstate-layer", [[ self:RunAttribute("update-page") ]])
    header:SetAttribute("_onstate-combat", COMBAT_SNIPPET)
    utility:SetAttribute("_onstate-combat", COMBAT_SNIPPET)
    header:HookScript("OnAttributeChanged", function(_, name, value)
        if name == "bank" then db.bank = value end
        if name == "activepage" then
            switch.stateLabel:SetText(value == 2 and "S" or value == 3 and "A" or value == 4 and "C"
                or value == 5 and "2" or "1")
        end
    end)
    -- Special contexts use the native controls, including any main-bar replacement pages.
    RegisterStateDriver(header, "visibility", VISIBILITY)
    RegisterStateDriver(utility, "visibility", VISIBILITY)
    RegisterStateDriver(controlsHeader, "visibility", VISIBILITY)
    controlsHeader:SetAttribute("_onstate-combat", COMBAT_SNIPPET)
    createPanel()
    createSettings()
    initialized = true
    RegisterStateDriver(header, "combat", "[combat]1;0")
    RegisterStateDriver(utility, "combat", "[combat]1;0")
    RegisterStateDriver(controlsHeader, "combat", "[combat]1;0")
    apply()
    say("Ready. Settings > AddOns > SPTouchBars, or /sptouch, to edit your layout.")
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
for _, event in ipairs({ "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_FINISHED",
                         "QUEST_ACCEPTED", "QUEST_TURNED_IN", "GOSSIP_SHOW", "GOSSIP_CLOSED", "GOSSIP_OPTIONS_REFRESHED" }) do
    events:RegisterEvent(event)
end
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("PLAYER_LOGOUT")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("UI_SCALE_CHANGED")
events:RegisterEvent("DISPLAY_SIZE_CHANGED")
pcall(events.RegisterEvent, events, "GAME_PAD_DISCONNECTED")  -- not on every client
events:SetScript("OnEvent", function(_, event, name, questID)
    if event == "ADDON_LOADED" and name ~= "Blizzard_GamepadActionBars" then return end
    if event == "QUEST_ACCEPTED" and (questID or name) then handledQuests[questID or name] = "accepted"
    elseif event == "QUEST_TURNED_IN" and name then handledQuests[name] = "turned" end
    if event:match("^QUEST_") or event:match("^GOSSIP_") then return end -- Next-frame UI sampling handles native event order.
    if event == "PLAYER_TARGET_CHANGED" then
        -- The native gamepad handler may change its temporary flag during this event. Reapply
        -- touch input mode on the next frame, out of combat, after all native handlers finish.
        pendingNearbyInteract = true
        return
    elseif event == "PLAYER_LOGOUT" then
        releaseNearbyInteraction()
        return
    elseif event == "GAME_PAD_DISCONNECTED" then
        if initialized then setPadMode(false) end
        return
    elseif event == "PLAYER_LOGIN" then initialize()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingInit then pendingInit = false; initialize() end
        if initialized then apply() end
    elseif event == "PLAYER_REGEN_DISABLED" and initialized then
        -- Protected click attributes are restored by the secure combat state driver, not this event.
        editing, previewing = false, false
        for _, group in ipairs({ spells, tools, extras }) do
            for _, button in ipairs(group) do
                stopMoving(button)
                button.rim:SetVertexColor(0.32, 0.43, 0.47)
            end
        end
        panel:StopMovingOrSizing()
        panel:Hide()
        selectionVisuals()
    elseif initialized and not InCombatLockdown() then apply() end
end)
local elapsedSinceRefresh = 0
events:SetScript("OnUpdate", function(_, elapsed)
    if pendingNearbyInteract and initialized and not InCombatLockdown() then
        pendingNearbyInteract = false
        updateNearbyInteraction()
    end
    elapsedSinceRefresh = elapsedSinceRefresh + elapsed
    if elapsedSinceRefresh >= 0.1 then
        elapsedSinceRefresh = 0
        if initialized and not InCombatLockdown() then
            if updateInteractAction() then controlsHeader:Execute([[ self:RunAttribute("update-page") ]]) end
        end
        refresh(); updateInteractIcon()
        if initialized and db.padAuto and not padMode and padButtonDown() then setPadMode(true) end
    end
end)
SLASH_SPTOUCHBARS1 = "/sptouch"
SLASH_SPTOUCHBARS2 = "/sptouchbars"
SlashCmdList.SPTOUCHBARS = function(message)
    if initialized and message and message:lower():match("^%s*status%s*$") then
        say("Nearby interaction mode: " .. (C_CVar.GetCVar("SoftTargetInteract") or "unavailable")
            .. "; native Interact: " .. (nativeInteract() and "ready" or "missing"))
        return
    end
    if initialized and message and message:lower():match("^%s*pad%s*$") then
        db.padAuto = not db.padAuto
        if not db.padAuto then setPadMode(false) end
        say("Hiding the touch bars while a controller is in use: " .. (db.padAuto and "on" or "off"))
        return
    end
    if initialized then setEditing(not editing)
    else say("Startup did not finish. Enable Lua errors with /console scriptErrors 1, then /reload.") end
end
