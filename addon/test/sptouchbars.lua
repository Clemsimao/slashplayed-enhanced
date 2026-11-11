-- Behavioral harness, Lua 5.1. Restricted snippets run with a small environment, and ordinary
-- callbacks cannot mutate protected frames in combat. This isn't a substitute for a live client.
local path = assert(arg[1], "usage: lua sptouchbars.lua <SPTouchBars.lua>")
local retail = arg[2] == "retail"
WOW_PROJECT_MAINLINE, WOW_PROJECT_ID = 1, retail and 1 or 5
local frames, controls, drivers = {}, {}, {}
local combat, secure, cursor, mouse, cx, cy = false, false, nil, false, 0, 0
local ctrl, alt, shift = false, false, false
local casts, timingMode = {}, "duration"
local interactions, interactionMode = {}, "talk"
local savedInteractMode, temporaryInteractMode = "1", nil
local hardTargetSelected = false
local nextInteraction, openQuest
local questCalls, gossipAvailable, gossipActive, legacyAvailable, legacyActive = {}, {}, {}, {}, {}
local currentQuest, choices, npcGUID = 0, 0, "npc-1"
Enum = { SoftTargetEnableFlags = { Any = 3, Gamepad = 1 } }

local specialUI = false
local secretValue = setmetatable({ secret = true }, {
    __tostring = function() error("stringified a secret") end,
    __add = function() error("arithmetic on a secret") end,
    __lt = function() error("compared a secret") end,
})
function issecretvalue(value) return type(value) == "table" and value.secret == true end
local function check(ok, message) assert(ok, message) end
C_CVar = {
    GetCVar = function(name)
        check(name == "SoftTargetInteract", "only change nearby interaction mode")
        return temporaryInteractMode or savedInteractMode
    end,
    SetTempCVar = function(name, value)
        check(not combat and name == "SoftTargetInteract" and value == "3", "enable nearby touch interaction outside combat")
        temporaryInteractMode = value
    end,
    RemoveTempCVar = function(name)
        check(not combat and name == "SoftTargetInteract", "restore user's interaction mode outside combat")
        temporaryInteractMode = nil
    end,
}
local function guarded(frame)
    assert(not (combat and frame.protected and not secure), "insecure mutation in combat: " .. (frame.name or "unnamed"))
end
local Frame = {}
Frame.__index = Frame
local function invoke(frame, event, ...)
    local fn = frame.scripts[event]
    if fn then
        local before = secure
        secure = false
        local ok, message = pcall(fn, frame, ...)
        secure = before
        assert(ok, message)
    end
end
local function snippet(frame, body, extra)
    local env = { self = frame, tonumber = tonumber }
    for key, value in pairs(extra or {}) do env[key] = value end
    local fn = assert(loadstring(body))
    setfenv(fn, env)
    local before = secure
    secure = true
    local ok, message = pcall(fn)
    secure = before
    assert(ok, message)
end
local function visual()
    local object = { shown = true }
    function object:SetText(value) self.text = value end
    function object:SetTexture(value) self.texture = value end
    function object:GetTexture() return self.texture end
    function object:SetAlpha(value) self.alpha = value end
    function object:SetBlendMode(value) self.blend = value end
    function object:SetColorTexture(...) self.color = {...} end
    function object:AddMaskTexture(mask) self.mask = mask end
    function object:SetVertexColor(...) self.color = {...} end
    function object:SetShown(value) self.shown = value end
    function object:Hide() self.shown = false end
    function object:Show() self.shown = true end
    for _, name in ipairs({ "SetSize", "SetAllPoints", "SetTexCoord", "SetDrawLayer", "SetThickness", "SetStartPoint", "SetEndPoint", "SetShadowColor", "SetShadowOffset", "SetTextColor", "SetFontObject" }) do
        object[name] = function() end
    end
    function object:SetPoint(...) self.anchor = {...} end
    return object
end
function Frame:SetAttribute(name, value)
    guarded(self)
    local changed = self.attributes[name] ~= value
    self.attributes[name] = value
    if changed then
        invoke(self, "OnAttributeChanged", name, value)
        if name:sub(1, 6) == "state-" then
            local body = self.attributes["_onstate-" .. name:sub(7)]
            if body then snippet(self, body, { newstate = value }) end
        end
    end
end
function Frame:GetAttribute(name) return self.attributes[name] end
function SecureHandlerSetFrameRef(owner, name, frame) guarded(owner); owner.refs[name] = frame end
function Frame:GetFrameRef(name) return self.refs[name] end
function Frame:RunAttribute(name) snippet(self, assert(self.attributes[name])) end
function Frame:Execute(body) guarded(self); snippet(self, body) end
function Frame:SetScript(event, fn) self.scripts[event] = fn end
function Frame:HookScript(event, fn)
    local previous = self.scripts[event]
    self.scripts[event] = function(...) if previous then previous(...) end; fn(...) end
end
function Frame:SetSize(w, h) guarded(self); self.w, self.h = w, h end
function Frame:GetWidth() return self.w end
function Frame:GetHeight() return self.h end
function Frame:GetEffectiveScale() return 1 end
function Frame:SetScale(value) guarded(self); self.scale = value end
function Frame:ClearAllPoints() guarded(self); self.anchor = nil end
function Frame:SetPoint(point, relative, relativePoint, x, y)
    guarded(self)
    if point == "TOPLEFT" and type(relative) == "number" then self.topY = relativePoint end
    if relative == UIParent and relativePoint == "BOTTOMLEFT" then self.x, self.y = x, y
    elseif type(relative) == "table" and relativePoint == "CENTER" then self.anchor = { relative, x, y } end
end
function Frame:GetCenter()
    if self.anchor then
        local x, y = self.anchor[1]:GetCenter()
        return x + self.anchor[2], y + self.anchor[3]
    end
    return self.x, self.y
end
function Frame:GetName() return self.name end
function Frame:IsEnabled() return self.enabled ~= false end
function Frame:SetMinMaxValues(lo, hi) self.lo, self.hi = lo, hi end
function Frame:SetValueStep(step) self.step = step end
function Frame:SetValue(value)
    value = math.max(self.lo or value, math.min(self.hi or value, value))
    local changed = self.value ~= value
    self.value = value
    if changed then invoke(self, "OnValueChanged", value) end
end
function Frame:GetValue() return self.value end
function Frame:Click(button, down) invoke(self, "OnClick", button or "LeftButton", down or false) end
function Frame:GetParent() return self.parent end
function Frame:SetParent(parent) guarded(self); self.parent = parent end
function Frame:SetShown(value) guarded(self); self.shown = value end
function Frame:Show() self:SetShown(true) end
function Frame:Hide() self:SetShown(false) end
function Frame:IsShown() return self.shown and (not self.parent or self.parent:IsShown()) end
function Frame:SetID(value) guarded(self); self.id = value end
function Frame:SetText(value) self.text = value; if self.fontString then self.fontString:SetText(value) end end
function Frame:SetFontString(font) self.fontString = font end
function Frame:SetEnabled(value) self.enabled = value end
function Frame:RegisterEvent(event) self.events[event] = true end
function Frame:CreateTexture() return visual() end
function Frame:CreateLine() return visual() end
function Frame:CreateMaskTexture() return visual() end
function Frame:CreateFontString() return visual() end
function Frame:GetFrameLevel() return 1 end
function Frame:SetCooldownFromDurationObject(value) self.durationObject = value end
function Frame:SetCooldown(start, duration, rate)
    assert(not issecretvalue(start) and not issecretvalue(duration) and not issecretvalue(rate), "secret cooldown number")
    self.timing = { start, duration, rate }
end
function Frame:Clear() self.durationObject, self.timing = nil, nil end
for _, name in ipairs({ "SetAllPoints", "EnableMouse", "SetClampedToScreen", "RegisterForClicks",
    "SetSwipeTexture", "SetDrawEdge", "SetHideCountdownNumbers", "SetDrawSwipe", "SetFrameLevel",
    "SetFrameStrata", "SetMovable", "RegisterForDrag", "SetBackdrop", "SetBackdropColor",
    "SetBackdropBorderColor", "SetHitRectInsets", "SetObeyStepOnDrag", "StartMoving", "StopMovingOrSizing" }) do
    Frame[name] = function() end
end
function CreateFrame(kind, name, parent, template)
    local frame = setmetatable({ name = name, parent = parent, template = template or "",
        shown = true, scripts = {}, attributes = {}, refs = {}, events = {}, id = 0 }, Frame)
    frame.protected = frame.template:find("Secure") ~= nil or (parent and parent.protected)
    -- The last inherited OnLoad replaces earlier ones. UIPanelButtonTemplate has its own
    -- initializer, so a preceding SecureHandlerClickTemplate doesn't add helper methods.
    local secureOnLoad = false
    for inherited in frame.template:gmatch("[^, ]+") do
        if inherited:find("SecureHandler") then secureOnLoad = true
        elseif inherited == "UIPanelButtonTemplate" then secureOnLoad = false end
    end
    if secureOnLoad then frame.SetFrameRef = SecureHandlerSetFrameRef end
    if frame.template:find("SecureActionButtonTemplate") then
        frame.scripts.OnClick = function(self, _, down)
            local actionType = self.attributes["*type1"] or self.attributes.type
            if down and self.attributes.useOnKeyDown and actionType then
                casts[#casts + 1] = { kind = actionType, value = self.attributes[actionType] or self.attributes.macrotext }
                if actionType == "macro" and self.attributes.macrotext then
                    for name, button, edge in self.attributes.macrotext:gmatch("/click (%S+) (%S+) (%S+)") do
                        local target = _G[name]
                        if target then invoke(target, "OnClick", button, edge == "1") end
                    end
                elseif actionType == "click" then
                    self.attributes.clickbutton:Click("LeftButton")
                end
            end
        end
    elseif frame.template:find("SecureHandlerClickTemplate") then
        frame.scripts.OnClick = function(self) snippet(self, self.attributes._onclick) end
    end
    frames[#frames + 1] = frame
    controls[#controls + 1] = frame
    if name then _G[name] = frame end
    return frame
end
UIParent = CreateFrame("Frame")
UIParent.w, UIParent.h = 1366, 768
SlashCmdList = {}
Settings = {
    RegisterCanvasLayoutCategory = function(frame, name) return { frame = frame, name = name } end,
    RegisterAddOnCategory = function(category) Settings.category = category end,
    RegisterCanvasLayoutSubcategory = function(parent, frame, name)
        parent.children = parent.children or {}
        parent.children[#parent.children + 1] = { frame = frame, name = name }
    end,
}
local mapToggles = 0
function ToggleWorldMap() mapToggles = mapToggles + 1 end
Minimap = CreateFrame("Frame", "Minimap", UIParent)
function Minimap:GetLeft() return 1200 end
function Minimap:GetBottom() return 580 end
SettingsPanel = CreateFrame("Frame", "SettingsPanel", UIParent)
local native = CreateFrame("Button", "GamepadMainActionBarFramePageUnitTopCenteredAnchorTopBarActionButton5", UIParent)
native:SetScript("OnClick", function(self, _, down)
    if down then self.pressed = true
    elseif self.pressed then
        self.pressed = false
        if hardTargetSelected or C_CVar.GetCVar("SoftTargetInteract") == "3" then
            interactions[#interactions + 1] = interactionMode
            if nextInteraction then local callback = nextInteraction; nextInteraction = nil; callback() end
        end
    end
end)
native.SpecialActionIcon = visual()
native.SpecialActionIcon:SetTexture("Interface\\Cursor\\LootAll")
local nativeAvailable = true
GamepadMainActionBarFrame = { GetActionBars = function()
    if nativeAvailable then return { topBar = { Right = { ActionButton1 = native } } } end
end }
C_AddOns = { LoadAddOn = function(name)
    check(name == "Blizzard_GamepadActionBars" or name == "Blizzard_ColorPickerFrame", "only load native control UI")
end }
ColorPickerFrame = {
    SetupColorPickerAndShow = function(self, info) self.info = info; self.r, self.g, self.b, self.a = info.r, info.g, info.b, info.opacity end,
    GetColorRGB = function(self) return self.r, self.g, self.b end,
    GetColorAlpha = function(self) return self.a end,
    Hide = function(self) self.shown = false end,
}
QuestFrame = CreateFrame("Frame", "QuestFrame", UIParent)
for _, name in ipairs({ "QuestFrameDetailPanel", "QuestFrameGreetingPanel", "QuestFrameProgressPanel", "QuestFrameRewardPanel" }) do
    CreateFrame("Frame", name, QuestFrame):Hide()
end
CreateFrame("Button", "QuestFrameAcceptButton", QuestFrameDetailPanel)
CreateFrame("Button", "QuestFrameCompleteButton", QuestFrameProgressPanel)
CreateFrame("Button", "QuestFrameCompleteQuestButton", QuestFrameRewardPanel)
CreateFrame("Button", "QuestFrameGreetingGoodbyeButton", QuestFrameGreetingPanel)
QuestFrame:Hide()
GossipFrame = CreateFrame("Frame", "GossipFrame", UIParent)
GossipFrame:Hide()
QuestInfoFrame = { itemChoice = 0 }
function UnitGUID(unit)
    if (unit == "npc" or unit == "questnpc") and (QuestFrame:IsShown() or GossipFrame:IsShown()) then return npcGUID end
end
function GetNumQuestChoices() return choices end
function GetNumActiveQuests() return #legacyActive end
function GetNumAvailableQuests() return #legacyAvailable end
function GetActiveTitle(i) return "Quest " .. legacyActive[i].id, legacyActive[i].complete end
function GetActiveQuestID(i) return legacyActive[i].id end
function GetAvailableQuestInfo(i) return false, 0, false, false, legacyAvailable[i].id end
function SelectAvailableQuest(i)
    questCalls[#questCalls + 1] = { "legacy-offer", legacyAvailable[i].id }
    openQuest("detail", legacyAvailable[i].id)
end
function SelectActiveQuest(i)
    questCalls[#questCalls + 1] = { "legacy-active", legacyActive[i].id }
    openQuest("progress", legacyActive[i].id)
end
C_GossipInfo = {
    GetAvailableQuests = function() return gossipAvailable end,
    GetActiveQuests = function() return gossipActive end,
    SelectAvailableQuest = function(id) questCalls[#questCalls + 1] = { "gossip-offer", id }; openQuest("detail", id) end,
    SelectActiveQuest = function(id) questCalls[#questCalls + 1] = { "gossip-active", id }; openQuest("progress", id) end,
}

function InCombatLockdown() return combat end
function GetCursorInfo() if cursor then return unpack(cursor) end end
function ClearCursor() cursor = nil end
function GetCursorPosition() return cx, cy end
function IsMouseButtonDown() return mouse end
function PlaceAction() error("private assignments must never write native action slots") end
function PickupAction() error("private assignments must never remove native actions") end
function GetActionInfo() error("private assignments must not mirror native action slots") end
GameTooltip = { SetOwner = function() end, SetAction = function() end, Show = function() end, Hide = function() end }
C_Spell = {
    GetSpellCooldownDuration = function() return timingMode == "duration" and { duration = true } or nil end,
    GetSpellChargeDuration = function() return nil end,
    GetSpellTexture = function(id) return "spell-" .. id end,
    GetSpellCooldown = function()
        return { startTime = secretValue, duration = secretValue, modRate = secretValue, isEnabled = secretValue }
    end,
    GetSpellCharges = function() return { currentCharges = secretValue } end,
    IsSpellUsable = function() return secretValue, secretValue end,
    IsSpellInRange = function() return secretValue end,
}
C_Item = {
    GetItemIconByID = function(id) return "item-" .. id end,
    GetItemCount = function() return 4 end,
    GetItemInfoInstant = function() return 6948 end,
}
C_Container = { GetItemCooldown = function() return 0, 0, 1 end }
C_MountJournal = { GetMountInfoByID = function() return "Test mount", 458 end }
function GetMacroIndexByName(name) return name == "Test macro" and 1 or 0 end
function GetMacroInfo(index) if index == 1 then return "Test macro", "macro-icon" end end
function GetMacroSpell() return 2000 end
function GetMacroItem() return nil end
-- Native bars, plus controls that must never be captured by the normal-bar container.
for _, name in ipairs({ "MainActionBar", "MultiBarBottomLeft", "MultiBar7", "PetActionBar", "StanceBar",
                        "OverrideActionBar", "PossessActionBar", "ExtraActionBarFrame", "VehicleLeaveButton" }) do
    CreateFrame("Frame", name, UIParent, "SecureFrameTemplate")
end
local function updateDriver(frame, state, expression)
    local value
    if state == "combat" then value = combat and "1" or "0"
    elseif state == "layer" then
        value = ctrl and expression:find("[mod:ctrl]4", 1, true) and "4"
            or alt and expression:find("[mod:alt]3", 1, true) and "3"
            or shift and expression:find("[mod:shift]2", 1, true) and "2" or "0"
    else
        value = frame.name == "SPTouchBarsDefaultBars" and (specialUI and "show" or "hide") or "show"
    end
    local before = secure; secure = true
    frame:SetAttribute("state-" .. state, value)
    if state == "visibility" then frame:SetShown(value == "show") end
    secure = before
end
function RegisterStateDriver(frame, state, expression)
    guarded(frame)
    drivers[frame] = drivers[frame] or {}
    drivers[frame][state] = expression
    updateDriver(frame, state, expression)
end
local function updateDrivers()
    for frame, states in pairs(drivers) do
        for state, expression in pairs(states) do updateDriver(frame, state, expression) end
    end
end
local function event(name)
    for _, frame in ipairs(frames) do if frame.events[name] then invoke(frame, "OnEvent", name) end end
end
local function click(frame)
    if not frame:IsEnabled() then return end
    invoke(frame, "OnMouseDown", "LeftButton")
    invoke(frame, "PreClick", "LeftButton", true)
    if frame.template:find("SecureActionButtonTemplate") then invoke(frame, "OnClick", "LeftButton", true) end
    invoke(frame, "OnMouseUp", "LeftButton")
    invoke(frame, "OnClick", "LeftButton", false)
end
local function control(text, topY, parentName)
    for _, frame in ipairs(controls) do
        local current = not frame.parent or not frame.parent.name or _G[frame.parent.name] == frame.parent
        if current and frame.text == text and (not topY or frame.topY == topY) and (not parentName or frame.parent.name == parentName) then return frame end
    end
    error("missing control: " .. text)
end
local function tick()
    for _, frame in ipairs(frames) do if frame:IsShown() then invoke(frame, "OnUpdate", 0.2) end end
end

openQuest = function(stage, id, numChoices)
    GossipFrame:Hide()
    QuestFrame:Show()
    for _, name in ipairs({ "QuestFrameDetailPanel", "QuestFrameGreetingPanel", "QuestFrameProgressPanel", "QuestFrameRewardPanel" }) do _G[name]:Hide() end
    local panels = { detail = QuestFrameDetailPanel, greeting = QuestFrameGreetingPanel,
        progress = QuestFrameProgressPanel, reward = QuestFrameRewardPanel }
    panels[stage]:Show()
    currentQuest, choices, QuestInfoFrame.itemChoice = id or 0, numChoices or 0, 0
    local eventsByStage = { detail = "QUEST_DETAIL", greeting = "QUEST_GREETING", progress = "QUEST_PROGRESS", reward = "QUEST_COMPLETE" }
    event(eventsByStage[stage]); tick()
end
QuestFrameAcceptButton:SetScript("OnClick", function()
    questCalls[#questCalls + 1] = { "accept", currentQuest }
    for _, frame in ipairs(frames) do if frame.events.QUEST_ACCEPTED then invoke(frame, "OnEvent", "QUEST_ACCEPTED", currentQuest) end end
    QuestFrame:Hide(); event("QUEST_FINISHED")
end)
QuestFrameCompleteButton:SetScript("OnClick", function()
    questCalls[#questCalls + 1] = { "continue", currentQuest }
    openQuest("reward", currentQuest, choices)
end)
QuestFrameCompleteQuestButton:SetScript("OnClick", function()
    questCalls[#questCalls + 1] = { "turnin", currentQuest, QuestInfoFrame.itemChoice }
    for _, frame in ipairs(frames) do if frame.events.QUEST_TURNED_IN then invoke(frame, "OnEvent", "QUEST_TURNED_IN", currentQuest) end end
    QuestFrame:Hide(); event("QUEST_FINISHED")
end)
QuestFrameGreetingGoodbyeButton:SetScript("OnClick", function() QuestFrame:Hide() end)
local function gossip()
    QuestFrame:Hide(); GossipFrame:Show(); event("GOSSIP_SHOW"); tick()
end

-- An existing mirror-mode layout must migrate without importing anything from native slots.
if retail then
    -- Retail deliberately has no Forever gamepad controls. Loading or touching one is a regression.
    GamepadMainActionBarFrame, _G[native.name] = nil, nil
    C_AddOns.LoadAddOn = function(name)
        check(name == "Blizzard_ColorPickerFrame", "Retail must not load the Forever gamepad addon")
    end
    C_PlayerInteractionManager = { InteractUnit = function() error("Retail's protected interaction API must never be called by addon code") end }
    SPTouchBarsDB = { bindings = { [1] = { kind = "spell", value = 1001 }, [61] = { kind = "item", value = 6948 } } }
    dofile(path); event("PLAYER_LOGIN")
    check(SPTouchBarsSpell1:GetAttribute("spell") == 1001 and SPTouchBarsUtility1:GetAttribute("item") == "item:6948",
          "Retail loads saved spell and item assignments without gamepad UI")
    check(SPTouchBarsInteract.caption.text == "Interact key" and not SPTouchBarsInteract:GetAttribute("type"),
          "Retail explicitly requires a native interaction binding outside quest windows")
    check(temporaryInteractMode == nil and savedInteractMode == "1", "Retail leaves native interaction settings alone")
    click(SPTouchBarsSpell1); check(casts[#casts].kind == "spell" and casts[#casts].value == 1001, "Retail secure spell casting")
    click(SPTouchBarsUtility1); check(casts[#casts].kind == "item", "Retail secure item use")
    click(SPTouchBarsTarget); check(casts[#casts].value == "/targetenemy [mod:shift] 1; 0", "Retail target cycling")
    click(SPTouchBarsMap); check(mapToggles == 1, "Retail world map")
    tick(); check(SPTouchBarsSpell1.cooldown.durationObject, "Retail duration-object cooldown")
    timingMode = "secret"; tick()
    check(not SPTouchBarsSpell1.cooldown.durationObject and SPTouchBarsSpell1.count.text == secretValue,
          "Retail secret timings and counts do not enter Lua arithmetic")
    click(control("Edit layout"))
    cursor = { "spell", 7, "spell", 2002 }; invoke(SPTouchBarsSpell1, "OnReceiveDrag")
    check(SPTouchBarsDB.bindings[1].value == 2002 and not cursor, "Retail private spellbook assignment")
    click(control("Done"))
    openQuest("detail", 101)
    check(SPTouchBarsInteract:GetAttribute("type") == "click" and not SPTouchBarsInteract:GetAttribute("macrotext"),
          "Retail quests use a click delegate rather than chained /click macros")
    click(SPTouchBarsInteract); check(questCalls[#questCalls][1] == "accept", "Retail quest acceptance needs one physical press")
    tick(); openQuest("reward", 102, 2)
    local before = #questCalls
    click(SPTouchBarsInteract); check(#questCalls == before, "Retail waits for manual reward choice")
    QuestInfoFrame.itemChoice = 2
    click(SPTouchBarsInteract); check(questCalls[#questCalls][1] == "turnin" and questCalls[#questCalls][3] == 2,
          "Retail turns in the player's chosen reward")
    tick(); openQuest("detail", 103)
    combat = true; updateDrivers(); event("PLAYER_REGEN_DISABLED")
    check(not SPTouchBarsInteract:GetAttribute("type"), "Retail quest delegation disables securely in combat")
    click(SPTouchBarsSpell1); check(casts[#casts].value == 2002, "Retail assigned spells still cast in combat")
    combat = false; updateDrivers(); event("PLAYER_REGEN_ENABLED")
    QuestFrame:Hide(); tick()
    check(not SPTouchBarsInteract:GetAttribute("type"), "Retail never retains quest action after the window closes")
    event("PLAYER_LOGOUT"); dofile(path); event("PLAYER_LOGIN")
    check(SPTouchBarsDB.bindings[1].value == 2002, "Retail assignments survive reload")
    print("PASS: Retail startup, secure assignments, cooldowns, targeting, quests, combat, and reload")
    return
end
SPTouchBarsDB = { count = 6, utilityCount = 8, spells = {}, utility = {}, version = 1 }
dofile(path)
event("PLAYER_LOGIN")
check(SPTouchBarsEdit == nil and Settings.category.frame == SPTouchBarsOptions, "editor lives in native settings, no HUD Edit button")
check(SPTouchBarsSwitch.SetFrameRef ~= nil and SPTouchBarsSwitch.w == SPTouchBarsSwitch.h,
      "circular switch uses only the secure template")
check(SPTouchBarsInteract:GetAttribute("binding") == nil and SPTouchBarsTarget:GetAttribute("binding") == nil,
      "pre-made controls are independent of action assignments")
check(SPTouchBarsTarget.icon.mask ~= nil and SPTouchBarsInteract.icon.mask ~= nil,
      "standalone controls have full masked icon faces like spell circles")
check(SPTouchBarsTarget.icon.anchor[2] == -6 and SPTouchBarsInteract.icon.anchor[2] == -6,
      "standalone icon faces fill the same button inset")
check(SPTouchBarsTarget.caption.anchor[1] == "BOTTOM" and SPTouchBarsInteract.caption.anchor[3] == "BOTTOM",
      "standalone captions stay inside their buttons")
check(SPTouchBarsDB.utilityLayout.spacing == 10, "existing layouts keep default utility spacing")
check(math.abs(SPTouchBarsMap.x - 1170) < 0.001 and math.abs(SPTouchBarsMap.y - 604) < 0.001,
      "map starts just outside the minimap")
check(SPTouchBarsInteract.icon.texture == "Interface\\Cursor\\LootAll", "interact copies Blizzard's live icon")
check(savedInteractMode == "1" and temporaryInteractMode == "3", "gamepad-only default enables nearby interaction for touch without overwriting saved setting")

check(SPTouchBarsSpell1.w == 100 and SPTouchBarsSpell6.w == 68, "large primary and smaller circles")
check(not SPTouchBarsSpell1.shown and not SPTouchBarsUtility8.shown and not SPTouchBarsUtility9.shown,
      "empty configured slots and excess buttons are hidden by default")
check(SPTouchBarsDB.version == 5 and next(SPTouchBarsDB.bindings) == nil, "old profiles start with private empty assignments")
check(SPTouchBarsSpell1:GetAttribute("action") == nil and SPTouchBarsUtility1:GetAttribute("action") == nil,
      "neither group references a native action slot")
click(SPTouchBarsSpell1)
check(#casts == 0 and not SPTouchBarsSpell1.shown, "empty buttons are inert and hidden during play")
check(MainActionBar:GetParent() == SPTouchBarsDefaultBars and not MainActionBar:IsShown(), "normal bars hidden")
for _, name in ipairs({ "PetActionBar", "StanceBar", "OverrideActionBar", "PossessActionBar", "ExtraActionBarFrame", "VehicleLeaveButton" }) do
    check(_G[name]:GetParent() == UIParent and _G[name]:IsShown(), name .. " stays available")
end

click(control("Edit layout"))
check(not SettingsPanel.shown and SPTouchBarsEditor.shown, "settings opens editor and closes settings panel")
check(SPTouchBarsInteract:GetAttribute("type") == nil and SPTouchBarsTarget:GetAttribute("type") == nil, "editing disables pre-made controls")
check(SPTouchBarsSpell1:GetAttribute("type") == nil, "editing disables casting")
local function drop(button, payload)
    cursor = payload
    invoke(button, "OnReceiveDrag")
    check(cursor == nil, "accepted cursor cleared")
end
-- The cursor's book index is deliberately different from its fourth-value spell ID.
drop(SPTouchBarsSpell1, { "spell", 7, "spell", 1001 })
check(SPTouchBarsDB.bindings[1].value == 1001 and SPTouchBarsSpell1.icon.texture == "spell-1001", "spellbook drop uses actual spell ID")
click(control("+"))
check(SPTouchBarsSpell7.shown, "add a spell button")
mouse, cx, cy = true, SPTouchBarsSpell1.x, SPTouchBarsSpell1.y
invoke(SPTouchBarsSpell1, "OnMouseDown", "LeftButton")
cx, cy = 900, 400; tick()
mouse = false; invoke(SPTouchBarsSpell1, "OnMouseUp", "LeftButton")
check(math.abs(SPTouchBarsDB.spells[1].x - 900 / 1366) < 0.001, "individual position saved")
click(SPTouchBarsEditorSpells:IsShown() and SPTouchBarsEditorSelectedSizeIncrease or SPTouchBarsEditorUtility:IsShown() and SPTouchBarsEditorUtilitySizeIncrease or SPTouchBarsEditorControlSizeIncrease)
check(SPTouchBarsSpell1.w == 104 and SPTouchBarsSpell2.w == 68, "only selected button resized")
check(SPTouchBarsSpell1.active.shown and not SPTouchBarsSpell2.active.shown, "selection highlights only selected spell")
tick()
check(SPTouchBarsSpell1.active.shown, "periodic icon updates retain selection")
local ux, uy = SPTouchBarsUtility1:GetCenter()
local vx, vy = SPTouchBarsUtility8:GetCenter()
mouse, cx, cy = true, ux, uy
invoke(SPTouchBarsUtility1, "OnMouseDown", "LeftButton")
cx, cy = cx + 60, cy + 120; tick()
mouse = false; invoke(SPTouchBarsUtility1, "OnMouseUp", "LeftButton")
local nx, ny = SPTouchBarsUtility1:GetCenter()
local mx, my = SPTouchBarsUtility8:GetCenter()
check(math.abs(nx - ux - 60) < 0.001 and math.abs(ny - uy - 120) < 0.001 and math.abs(mx - vx - 60) < 0.001 and math.abs(my - vy - 120) < 0.001, "dragging one utility moves the complete group")
check(SPTouchBarsUtility1.active.shown and SPTouchBarsUtility8.active.shown and not SPTouchBarsSpell1.active.shown,
      "selected utility group is visibly highlighted")
click(SPTouchBarsEditorSpells:IsShown() and SPTouchBarsEditorSelectedSizeIncrease or SPTouchBarsEditorUtility:IsShown() and SPTouchBarsEditorUtilitySizeIncrease or SPTouchBarsEditorControlSizeIncrease)
check(SPTouchBarsUtility1.w == 56 and SPTouchBarsUtility8.w == 56, "selected utility resize applies to every icon")
click(SPTouchBarsEditorUtilitySizeIncrease)
click(SPTouchBarsEditorUtilityRowsIncrease)
check(SPTouchBarsDB.utilityLayout.rows == 2 and SPTouchBarsUtility1.w == 60, "utility grid controls rows and shared size")
local _, top = SPTouchBarsUtility1:GetCenter()
local _, bottom = SPTouchBarsUtility5:GetCenter()
check(top > bottom, "second row is below the first")
local spellX = SPTouchBarsDB.spells[1].x
click(SPTouchBarsEditorUtilitySpacingIncrease); click(SPTouchBarsEditorUtilitySpacingIncrease)
local ax, ay = SPTouchBarsUtility1:GetCenter()
local bx, by = SPTouchBarsUtility2:GetCenter()
local _, rowY = SPTouchBarsUtility5:GetCenter()
check(SPTouchBarsDB.utilityLayout.spacing == 14 and math.abs(bx - ax - 74) < 0.001
      and math.abs(ay - rowY - 74) < 0.001, "spacing changes both grid axes by the requested gap")
check(SPTouchBarsUtility1.w == 60 and SPTouchBarsDB.bindings[1].value == 1001 and SPTouchBarsDB.spells[1].x == spellX,
      "spacing preserves icon size, spell position, and private assignments")
click(SPTouchBarsEditorUtilitySpacingDecrease)
check(SPTouchBarsDB.utilityLayout.spacing == 12, "spacing decreases independently")
click(SPTouchBarsEditorUtilitySpacingIncrease)
mouse, cx, cy = true, SPTouchBarsTarget:GetCenter()
invoke(SPTouchBarsTarget, "OnMouseDown", "LeftButton")
cx, cy = 700, 300; tick()
mouse = false; invoke(SPTouchBarsTarget, "OnMouseUp", "LeftButton")
click(SPTouchBarsEditorSpells:IsShown() and SPTouchBarsEditorSelectedSizeIncrease or SPTouchBarsEditorUtility:IsShown() and SPTouchBarsEditorUtilitySizeIncrease or SPTouchBarsEditorControlSizeIncrease)
check(SPTouchBarsTarget.w == 68 and SPTouchBarsInteract.w == 64 and SPTouchBarsTarget.x == 700,
      "standalone target control moves and resizes independently")
check(SPTouchBarsTarget.active.shown and not SPTouchBarsUtility1.active.shown, "selection moves to target control")
click(SPTouchBarsEditorClear)
click(control("Interact: on"))
check(not SPTouchBarsInteract.shown and SPTouchBarsTarget.shown, "Interact toggles independently")
check(C_CVar.GetCVar("SoftTargetInteract") == "1", "hiding Interact restores the user's saved mode")
click(control("Interact: off"))
click(control("Target: on"))
check(SPTouchBarsInteract.shown and not SPTouchBarsTarget.shown, "Target toggles independently")
click(control("Target: off"))
click(control("Layer: Set 1"))
drop(SPTouchBarsSpell1, { "spell", 8, "spell", 1002 })
check(SPTouchBarsDB.bindings[13].value == 1002, "touch-only preview assigns the Shift layer")
click(control("Layer: Shift"))
drop(SPTouchBarsSpell1, { "spell", 9, "spell", 1003 })
click(control("Layer: Alt"))
drop(SPTouchBarsSpell1, { "spell", 10, "spell", 1004 })
click(control("Layer: Ctrl"))
drop(SPTouchBarsSpell1, { "spell", 11, "spell", 1005 })
drop(SPTouchBarsUtility1, { "item", 6948 })
drop(SPTouchBarsUtility2, { "mount", 1 })
drop(SPTouchBarsUtility3, { "macro", 1 })
check(SPTouchBarsDB.bindings[61].kind == "item" and SPTouchBarsDB.bindings[62].value == 458,
      "utility stores private item and mount assignments")
check(SPTouchBarsDB.bindings[63].kind == "macro" and SPTouchBarsDB.bindings[63].value == "Test macro",
      "macros persist by name")
drop(SPTouchBarsUtility8, { "item", 1111 })
click(SPTouchBarsEditorUtilityCountDecrease)
check(SPTouchBarsDB.utilityCount == 7 and not SPTouchBarsUtility8.shown, "utility count control hides excess icons")
click(SPTouchBarsEditorUtilityCountIncrease)
check(SPTouchBarsUtility8.shown and SPTouchBarsDB.bindings[68].value == 1111, "raising utility count restores assignments")
click(control("Default bars: hidden"))
check(MainActionBar:GetParent() == UIParent and MainActionBar:IsShown(), "show restores original native parent")
click(control("Default bars: shown"))
check(not MainActionBar:IsShown() and PetActionBar:IsShown(), "hiding normal bars leaves pet visible")
click(control("Done"))
click(SPTouchBarsTarget)
check(casts[#casts].value == "/targetenemy [mod:shift] 1; 0", "target executes a pre-made cycle macro")
click(SPTouchBarsInteract)
check(#interactions == 1 and interactions[1] == "talk" and not native.pressed, "macro completes one native interaction tap")
interactionMode = "loot"
native.SpecialActionIcon:SetTexture("loot-icon")
tick()
check(SPTouchBarsInteract.icon.texture == "loot-icon", "interact icon follows a changed native action")
click(SPTouchBarsInteract)
check(#interactions == 2 and interactions[2] == "loot" and not native.pressed, "same pre-made control delegates corpse looting")
check(casts[#casts].value:find("LeftButton 1\n/click", 1, true) and casts[#casts].value:find("LeftButton 0", 1, true),
      "Interact sends a complete native down/up click pair")
-- Reproduce the reported regression: manual target works in gamepad-only mode, proximity does not.
click(control("Nearby interaction: on"))
local beforeInteraction = #interactions
click(SPTouchBarsInteract)
check(#interactions == beforeInteraction, "gamepad-only mode cannot detect a nearby NPC from a mouse tap")
hardTargetSelected = true
click(SPTouchBarsInteract)
check(#interactions == beforeInteraction + 1, "manual selection works even without nearby detection")
hardTargetSelected = false
click(control("Nearby interaction: off"))
interactionMode = "talk"
click(SPTouchBarsInteract)
check(#interactions == beforeInteraction + 2 and interactions[#interactions] == "talk", "nearby NPC works without manual selection")
interactionMode = "loot"
click(SPTouchBarsInteract)
check(#interactions == beforeInteraction + 3 and interactions[#interactions] == "loot", "nearby corpse works without manual selection")
temporaryInteractMode = "1" -- Native gamepad targeting updates its temporary mode after target changes.
event("PLAYER_TARGET_CHANGED"); tick()
check(temporaryInteractMode == "3", "next-frame update preserves touch detection after native target changes")
casts = {}
click(SPTouchBarsSpell1)
check(#casts == 1 and casts[1].kind == "spell" and casts[1].value == 1001, "one tap casts the private spell")
local function pressFeedback(button)
    local castCount = #casts
    mouse = true
    invoke(button, "OnMouseDown", "LeftButton")
    check(button.pressOverlay.shown and (button.glow[1].color[4] > 0.1), "press shows a visible tint and halo")
    tick()
    check(button.pressOverlay.shown, "icon refresh retains held feedback")
    mouse = false
    invoke(button, "OnMouseUp", "LeftButton")
    check(not button.pressOverlay.shown and #casts == castCount, "release restores appearance without extra actions")
    mouse = true; invoke(button, "OnMouseDown", "LeftButton")
    mouse = false; tick()
    check(not button.pressOverlay.shown, "release outside the button cannot leave a stuck glow")
    mouse = true; invoke(button, "OnMouseDown", "LeftButton")
    invoke(button, "OnHide")
    check(not button.pressOverlay.shown, "hiding a held button clears press feedback")
    mouse = false
end
for _, button in ipairs({ SPTouchBarsSpell1, SPTouchBarsUtility1, SPTouchBarsInteract, SPTouchBarsTarget, SPTouchBarsSwitch }) do
    pressFeedback(button)
end
click(SPTouchBarsUtility1)
check(casts[#casts].kind == "item" and casts[#casts].value == "item:6948", "utility uses secure item attribute")
click(SPTouchBarsUtility3)
check(casts[#casts].kind == "macro" and casts[#casts].value == "Test macro", "normal macros use secure named-macro attribute")
shift = true; updateDrivers()
check(SPTouchBarsSpell1:GetAttribute("spell") == 1002 and SPTouchBarsSpell1.icon.texture == "spell-1002", "Shift cast and icon agree")
alt = true; updateDrivers()
check(SPTouchBarsSpell1:GetAttribute("spell") == 1003, "Alt takes precedence over Shift")
ctrl = true; updateDrivers()
check(SPTouchBarsSpell1:GetAttribute("spell") == 1004, "Ctrl takes precedence")
check(SPTouchBarsUtility1:GetAttribute("item") == "item:6948", "utility ignores modifier layers")
ctrl, alt, shift = false, false, false; updateDrivers()

SlashCmdList.SPTOUCHBARS()
click(control("Ctrl: on"))
check(not SPTouchBarsDB.layers.ctrl and SPTouchBarsDB.layers.alt and SPTouchBarsDB.layers.shift,
      "Ctrl toggle leaves the other layers enabled")
click(control("Done"))
ctrl = true; updateDrivers()
check(SPTouchBarsSpell1:GetAttribute("spell") == 1001, "disabled Ctrl leaves its modifier available to the base macro")
alt = true; updateDrivers()
check(SPTouchBarsSpell1:GetAttribute("spell") == 1003, "disabled Ctrl does not mask enabled Alt")
shift = true; updateDrivers()
check(SPTouchBarsSpell1:GetAttribute("spell") == 1003, "Alt still wins over Shift independently")
ctrl, alt, shift = false, false, false; updateDrivers()
SlashCmdList.SPTOUCHBARS()
click(control("Alt: on")); click(control("Shift: on"))
click(control("Done"))
ctrl, alt, shift = true, true, true; updateDrivers()
check(SPTouchBarsSpell1:GetAttribute("spell") == 1001, "all disabled modifiers keep base assignments")
ctrl, alt, shift = false, false, false; updateDrivers()
SlashCmdList.SPTOUCHBARS()
click(control("Ctrl: off")); click(control("Shift: off"))
click(control("Done"))
alt, shift = true, true; updateDrivers()
check(SPTouchBarsSpell1:GetAttribute("spell") == 1002, "disabled Alt does not mask enabled Shift")
ctrl = true; updateDrivers()
check(SPTouchBarsSpell1:GetAttribute("spell") == 1004, "Ctrl priority survives independent toggles")
ctrl, alt, shift = false, false, false; updateDrivers()
SlashCmdList.SPTOUCHBARS()
click(control("Alt: off"))
-- Enter combat during an edit gesture: snippets, not insecure callbacks, restore the selected spell.
mouse = true; invoke(SPTouchBarsSpell1, "OnMouseDown", "LeftButton")
combat = true; updateDrivers(); event("PLAYER_REGEN_DISABLED"); tick()
check(SPTouchBarsSpell1:GetAttribute("type") == "spell" and not SPTouchBarsEditor.shown, "combat restores private casts")
check(SPTouchBarsSpell1:GetAttribute("spell") == 1001, "combat leaves preview and restores base set")
check(SPTouchBarsUtility1:GetAttribute("type") == "item", "utility restores its own action type in combat")
check(SPTouchBarsTarget:GetAttribute("type") == "macro" and SPTouchBarsInteract:GetAttribute("type") == "macro", "combat securely restores pre-made controls")
check(not SPTouchBarsSpell1.active.shown, "combat removes selection highlight")
pressFeedback(SPTouchBarsSpell1)
pressFeedback(SPTouchBarsTarget)
local oldGap = SPTouchBarsDB.utilityLayout.spacing
click(SPTouchBarsEditorUtilitySpacingIncrease)
check(SPTouchBarsDB.utilityLayout.spacing == oldGap, "combat blocks spacing edits")
local widthBefore = SPTouchBarsUtility1.w
click(SPTouchBarsEditorUtilitySizeIncrease); click(control("Target: on"))
check(SPTouchBarsUtility1.w == widthBefore and SPTouchBarsDB.controls.target.enabled, "combat rejects utility changes and control toggles")
click(SPTouchBarsSwitch)
check(SPTouchBarsSpell1:GetAttribute("spell") == 1005 and SPTouchBarsDB.bank == 5, "secure private set switching in combat")
shift = true; updateDrivers(); click(SPTouchBarsSpell1)
check(casts[#casts].value == 1002 and SPTouchBarsSwitch.stateLabel.text == "S", "combat modifier casts displayed private assignment")
click(SPTouchBarsSwitch)
check(SPTouchBarsSpell1:GetAttribute("spell") == 1002, "set switching keeps held layer")
shift = false; updateDrivers()
check(SPTouchBarsSpell1:GetAttribute("spell") == 1001, "release returns to newly selected base set")
SlashCmdList.SPTOUCHBARS()
check(not SPTouchBarsEditor.shown, "editing blocked in combat")
local countBefore = #casts
cursor = { "spell", 12, "spell", 9999 }; invoke(SPTouchBarsSpell1, "OnReceiveDrag")
check(SPTouchBarsDB.bindings[1].value == 1001 and cursor ~= nil and #casts == countBefore, "combat rejects assignment changes")
cursor = nil
timingMode = "secret"; tick()
check(SPTouchBarsSpell1.cooldown.durationObject == nil, "secret timings clear stale swipe")
check(SPTouchBarsSpell1.count.text == secretValue, "secret count goes directly to widget")
specialUI = true; updateDrivers()
check(MainActionBar:IsShown() and PetActionBar:IsShown(), "special UI can show native main bar while pet remains available")
specialUI = false; updateDrivers()
combat = false; mouse = false; updateDrivers(); event("PLAYER_REGEN_ENABLED")
SlashCmdList.SPTOUCHBARS()
invoke(SPTouchBarsSpell1, "OnMouseDown", "LeftButton"); invoke(SPTouchBarsSpell1, "OnMouseUp", "LeftButton")
click(SPTouchBarsEditorClear)
check(SPTouchBarsDB.bindings[1] == nil and SPTouchBarsDB.bindings[13].value == 1002, "clear affects only selected private layer")
drop(SPTouchBarsSpell1, { "spell", 7, "spell", 1001 })
click(control("Done"))
UIParent.w, UIParent.h = 768, 1366; event("DISPLAY_SIZE_CHANGED")
for i = 1, 12 do
    local button = _G["SPTouchBarsSpell" .. i]
    check(button.x >= button.w / 2 and button.x <= 768 - button.w / 2, "rotation keeps buttons on screen")
end
local gx, gy = SPTouchBarsUtilityGroup:GetCenter()
check(gx >= SPTouchBarsUtilityGroup.w / 2 and gx + SPTouchBarsUtilityGroup.w / 2 <= 768, "rotation clamps whole utility group")
SPTouchBarsDB.utilityCount = 12
SPTouchBarsDB.utilityLayout.rows, SPTouchBarsDB.utilityLayout.spacing = 1, 48
event("DISPLAY_SIZE_CHANGED")
check(SPTouchBarsUtility1.w >= 44, "crowded grid reduces spacing before sacrificing touch target size")
local firstX = SPTouchBarsUtility1:GetCenter()
local lastX = SPTouchBarsUtility12:GetCenter()
check(firstX >= SPTouchBarsUtility1.w / 2 and lastX + SPTouchBarsUtility12.w / 2 <= 768.001,
      "large requested gaps fit the complete bar on a narrower display")
click(SPTouchBarsEditorUtilitySpacingIncrease)
check(SPTouchBarsDB.utilityLayout.spacing == 48, "spacing upper bound is enforced")
SPTouchBarsDB.utilityLayout.spacing = 0
click(SPTouchBarsEditorUtilitySpacingDecrease)
local joinedX = SPTouchBarsUtility1:GetCenter()
local nextX = SPTouchBarsUtility2:GetCenter()
check(SPTouchBarsDB.utilityLayout.spacing == 0 and math.abs(nextX - joinedX - SPTouchBarsUtility1.w) < 0.001,
      "zero spacing joins edges without overlapping touch targets")
SPTouchBarsDB.utilityLayout.rows, SPTouchBarsDB.utilityLayout.spacing = 2, 14
event("DISPLAY_SIZE_CHANGED")
local savedLayout = SPTouchBarsDB.utilityLayout
local targetX = SPTouchBarsDB.controls.target.x
local savedX = SPTouchBarsDB.spells[1].x
SPTouchBarsDB.utilityCount = -10
SPTouchBarsDB.spells[2] = { x = "bad", y = 0/0, size = 1000 }
SPTouchBarsDB.bindings[2] = { kind = "action", value = 12 }
SPTouchBarsDB.bindings[3] = { kind = "spell", value = "invalid" }
SPTouchBarsDB.layers = false
event("PLAYER_LOGOUT")
check(temporaryInteractMode == nil, "logout/reload releases our temporary interaction mode")
dofile(path); event("PLAYER_LOGIN")
check(SPTouchBarsDB.spells[1].x == savedX and SPTouchBarsDB.bindings[1].value == 1001, "saved layout and private assignments survive reload")
check(SPTouchBarsDB.utilityLayout == savedLayout and SPTouchBarsDB.utilityLayout.rows == 2
    and SPTouchBarsDB.utilityLayout.size == 60 and SPTouchBarsDB.utilityLayout.spacing == 14
    and SPTouchBarsDB.controls.target.x == targetX,
    "shared utility geometry and independent controls persist across reload")
check(SPTouchBarsDB.utilityCount == 0 and SPTouchBarsDB.spells[2].size == 140, "profile geometry validated")
check(SPTouchBarsDB.bindings[2] == nil and SPTouchBarsDB.bindings[3] == nil, "unsafe or invalid bindings rejected")
check(not SPTouchBarsDB.layers.ctrl and not SPTouchBarsDB.layers.alt and not SPTouchBarsDB.layers.shift,
      "legacy layers-off setting migrates all three modifiers as disabled")
-- Native UI missing: report the unavailable control rather than enabling an inert macro.
nativeAvailable = false
_G[native.name] = nil
event("DISPLAY_SIZE_CHANGED")
check(SPTouchBarsInteract:GetAttribute("type") == nil and SPTouchBarsInteract.caption.text == "Unavailable", "missing native interact is explicit")
check(temporaryInteractMode == nil and savedInteractMode == "1", "missing native UI releases nearby override")
-- Do not undo a separately enabled native setting, or a mode changed by another owner.
savedInteractMode = "3"
nativeAvailable = true; _G[native.name] = native
event("DISPLAY_SIZE_CHANGED")
check(temporaryInteractMode == nil, "already enabled native interaction needs no owned override")
click(control("Nearby interaction: on"))
check(savedInteractMode == "3" and temporaryInteractMode == nil, "nearby toggle leaves an already enabled native preference intact")
click(control("Nearby interaction: off"))
savedInteractMode = "1"; event("DISPLAY_SIZE_CHANGED")
temporaryInteractMode = "0" -- Another system has taken over, e.g. native combat suppression.
click(control("Nearby interaction: on"))
check(temporaryInteractMode == "0", "release does not remove another system's newer override")
-- Quest presses are contextual; no dialogue event accepts anything by itself.
hardTargetSelected = true
npcGUID = "npc-quest-tests"
local start = #questCalls
nextInteraction = function() openQuest("detail", 101) end
click(SPTouchBarsInteract)
check(#questCalls == start and SPTouchBarsInteract.caption.text == "Accept", "opening an NPC offer does not accept it on the same press")
tick(); event("QUEST_DETAIL"); tick()
check(#questCalls == start, "events and refreshes never advance quests")
click(SPTouchBarsInteract)
check(#questCalls == start + 1 and questCalls[#questCalls][1] == "accept", "second press accepts the visible offer")
-- Native UI state may change between refresh and the next physical press.
openQuest("detail", 102)
QuestFrameAcceptButton.enabled = false
click(SPTouchBarsInteract)
check(#questCalls == start + 1, "disabled native Accept is never clicked")
QuestFrameAcceptButton.enabled = true
click(SPTouchBarsInteract)
check(#questCalls == start + 2, "native Accept becomes usable when enabled")
-- Gossip available quests appear above active turn-ins. Process eligible rows in that order.
gossipAvailable = { { questID = 201 }, { questID = 202 } }
gossipActive = { { questID = 299, isComplete = false }, { questID = 203, isComplete = true } }
gossip(); click(SPTouchBarsInteract)
check(questCalls[#questCalls][1] == "gossip-offer" and questCalls[#questCalls][2] == 201, "gossip selects the top available quest")
click(SPTouchBarsInteract); gossip(); click(SPTouchBarsInteract)
check(questCalls[#questCalls][2] == 202 and questCalls[#questCalls][1] == "gossip-offer", "handled top quest is skipped when server list has not refreshed")
click(SPTouchBarsInteract); gossip(); click(SPTouchBarsInteract)
check(questCalls[#questCalls][1] == "gossip-active" and questCalls[#questCalls][2] == 203, "gossip reaches the next completed turn-in, skipping incomplete quests")
local before = #questCalls
choices = 2
click(SPTouchBarsInteract)
check(#questCalls == before + 1 and questCalls[#questCalls][1] == "continue" and QuestFrameRewardPanel:IsShown(), "Continue opens rewards without also turning in")
click(SPTouchBarsInteract)
check(#questCalls == before + 1 and SPTouchBarsInteract.caption.text == "Reward", "multiple rewards require manual selection")
QuestInfoFrame.itemChoice = 2
tick()
check(SPTouchBarsInteract.caption.text == "Turn in", "manual reward selection unlocks the turn-in step")
click(SPTouchBarsInteract)
check(questCalls[#questCalls][1] == "turnin" and questCalls[#questCalls][3] == 2, "turn-in uses the manually selected reward")
gossipActive = { { questID = 201, isComplete = true } }
gossip(); click(SPTouchBarsInteract)
check(questCalls[#questCalls][1] == "gossip-active" and questCalls[#questCalls][2] == 201,
      "a quest accepted earlier with this NPC remains eligible for a later completed turn-in")
click(SPTouchBarsInteract); click(SPTouchBarsInteract)

-- Classic greeting order is the opposite: completed active quests first, then offers.
npcGUID = "npc-classic-tests"
legacyActive = { { id = 301, complete = false }, { id = 302, complete = true } }
legacyAvailable = { { id = 303 }, { id = 304 } }
openQuest("greeting")
click(SPTouchBarsInteract)
check(questCalls[#questCalls][1] == "legacy-active" and questCalls[#questCalls][2] == 302, "classic greeting follows its displayed active-first order")
click(SPTouchBarsInteract); click(SPTouchBarsInteract)
openQuest("greeting"); click(SPTouchBarsInteract)
check(questCalls[#questCalls][1] == "legacy-offer" and questCalls[#questCalls][2] == 303, "classic greeting advances to available quests after turn-ins")
-- Use native confirmation buttons, and never click an obscured quest behind a confirmation.
local confirmation = CreateFrame("Frame", nil, UIParent)
QuestFrame.dialog = confirmation
before = #questCalls
click(SPTouchBarsInteract)
check(#questCalls == before and SPTouchBarsInteract.caption.text == "Confirm", "native confirmation is left to the player")
confirmation:Hide(); QuestFrame.dialog = nil
click(control("Quest steps: on"))
click(SPTouchBarsInteract)
check(#questCalls == before, "quest-step option can restore world-only Interact")
click(control("Quest steps: off"))
SlashCmdList.SPTOUCHBARS()
click(SPTouchBarsInteract)
check(#questCalls == before, "editing never advances a quest")
click(control("Done"))
combat = true; updateDrivers(); event("PLAYER_REGEN_DISABLED")
click(SPTouchBarsInteract)
check(#questCalls == before and SPTouchBarsInteract:GetAttribute("type") == nil, "combat securely blocks quest-step payloads")
combat = false; updateDrivers(); event("PLAYER_REGEN_ENABLED")
QuestFrame:Hide(); GossipFrame:Hide(); tick()
hardTargetSelected = false
check(SPTouchBarsInteract:GetAttribute("macrotext"):find(native:GetName(), 1, true), "closing dialogue restores the world Interact macro")
-- Native colour picker: live RGB and alpha preview, cancel, slider, reset, and persistence.
click(control("Outline colour"))
ColorPickerFrame.r, ColorPickerFrame.g, ColorPickerFrame.b, ColorPickerFrame.a = 1, 0.25, 0.5, 0.4
ColorPickerFrame.info.swatchFunc()
check(SPTouchBarsDB.appearance.spells.outlineColor.r == 1 and SPTouchBarsDB.appearance.spells.outlineAlpha == 0.4, "native wheel previews chosen colour and alpha")
check(SPTouchBarsTarget.rim.color[1] == 0.7 and SPTouchBarsInteract.rim.color[4] == 0.4,
      "custom outlines cover both standalone and action buttons")
click(control("Outline colour"))
ColorPickerFrame.r, ColorPickerFrame.a = 0.1, 0.2
ColorPickerFrame.info.opacityFunc()
ColorPickerFrame.info.cancelFunc()
check(SPTouchBarsDB.appearance.spells.outlineColor.r == 1 and SPTouchBarsDB.appearance.spells.outlineAlpha == 0.4, "Cancel restores the complete prior appearance")
SPTouchBarsSpellsOutlineOpacity:SetValue(0)
check(SPTouchBarsSpell1.rim.color[4] == 0 and SPTouchBarsTarget.glow[1].color[4] == 0 and SPTouchBarsSpell1.icon.alpha == 1,
      "transparent outlines leave spell icons visible")
SPTouchBarsSpellsOutlineOpacity:SetValue(65)
check(SPTouchBarsDB.appearance.spells.outlineAlpha == 0.65, "opacity slider saves its selected percentage")
combat = true; updateDrivers(); event("PLAYER_REGEN_DISABLED")
SPTouchBarsSpellsOutlineOpacity:SetValue(50)
check(SPTouchBarsDB.appearance.spells.outlineAlpha == 0.5, "appearance preview only changes combat-safe textures")
combat = false; updateDrivers(); event("PLAYER_REGEN_ENABLED")
event("PLAYER_LOGOUT"); dofile(path); event("PLAYER_LOGIN")
check(SPTouchBarsDB.appearance.spells.outlineColor.r == 1 and SPTouchBarsDB.appearance.spells.outlineAlpha == 0.5, "outline RGB and opacity survive reload")
click(control("Reset appearance"))
check(SPTouchBarsDB.appearance.spells.outlineColor == nil and SPTouchBarsDB.appearance.spells.outlineAlpha == 1, "appearance reset restores defaults")
-- Appearance groups must not share state or textures.
local utilityPage, spellPage = "SPTouchBarsUtilityOptions", "SPTouchBarsSpellsOptions"
local function option(text, parent) return control(text, nil, parent) end
click(option("Outline colour", utilityPage))
ColorPickerFrame.r, ColorPickerFrame.g, ColorPickerFrame.b, ColorPickerFrame.a = 0.2, 0.8, 0.4, 0.7
ColorPickerFrame.info.swatchFunc()
check(SPTouchBarsDB.appearance.utility.outlineColor.g == 0.8 and SPTouchBarsDB.appearance.spells.outlineColor == nil,
      "utility colour is independent from spell and control appearance")
SPTouchBarsUtilityGlow:SetValue(0)
check(SPTouchBarsUtility1.glow[1].color[4] == 0 and SPTouchBarsUtility1.rim.color[4] == 0.7
      and SPTouchBarsSpell1.glow[1].color[4] > 0, "utility glow can be removed without changing outlines or spell glow")
SPTouchBarsUtilityOutlineOpacity:SetValue(20)
check(SPTouchBarsUtility1.rim.color[4] == 0.2 and SPTouchBarsSpell1.rim.color[4] == 1,
      "utility outline opacity is independent")
click(option("Reset appearance", utilityPage))
check(SPTouchBarsDB.appearance.utility.glow == 1 and SPTouchBarsDB.appearance.utility.outlineColor == nil,
      "reset affects just the selected group")
-- Restore a regular layout after the earlier malformed-profile and rotation checks.
UIParent.w, UIParent.h = 1366, 768
SPTouchBarsDB.utilityCount = 8
event("DISPLAY_SIZE_CHANGED")
-- Secure visibility follows the actual assignment in each set/modifier, including combat.
ctrl, alt, shift = false, false, false; updateDrivers()
local savedBank = SPTouchBarsHeader:GetAttribute("bank")
if savedBank ~= 1 then click(SPTouchBarsSwitch) end
check(SPTouchBarsSpell1.shown and not SPTouchBarsSpell12.shown, "assigned base slot shown; empty excess slot hidden")
click(option("Hide empty: on", spellPage))
check(SPTouchBarsSpell2.shown, "empty slots may be shown during play")
click(option("Hide empty: off", spellPage))
click(option("Bar: on", utilityPage))
check(not SPTouchBarsUtility1.shown and not SPTouchBarsUtility8.shown and SPTouchBarsSpell1.shown,
      "whole utility bar can be hidden independently without losing assignments")
click(control("Edit layout"))
check(SPTouchBarsUtility1.shown and SPTouchBarsUtility8.shown and SPTouchBarsSpell2.shown,
      "editing reveals hidden bars and empty configured slots")
local preserved = SPTouchBarsDB.bindings[61].value
click(control("Done"))
check(not SPTouchBarsUtility1.shown and SPTouchBarsDB.bindings[61].value == preserved,
      "leaving editor hides disabled bar and preserves assignments")
click(option("Bar: off", utilityPage))
-- Use a high, otherwise empty slot to test transitions without changing existing assignments.
local oldCount = SPTouchBarsDB.count
SPTouchBarsDB.count = 12
SPTouchBarsDB.bindings[12] = { kind = "spell", value = 1012 }
SPTouchBarsDB.bindings[24], SPTouchBarsDB.bindings[60] = nil, nil
SPTouchBarsDB.layers.shift = true
event("DISPLAY_SIZE_CHANGED")
check(SPTouchBarsSpell12.shown, "assigned high slot is visible")
combat = true; updateDrivers(); event("PLAYER_REGEN_DISABLED")
shift = true; updateDrivers()
check(not SPTouchBarsSpell12.shown, "empty Shift-layer button securely hides during combat")
shift = false; updateDrivers()
check(SPTouchBarsSpell12.shown, "returning to assigned base layer securely reveals button")
click(SPTouchBarsSwitch)
check(not SPTouchBarsSpell12.shown, "empty alternate-set button securely hides during combat")
click(SPTouchBarsSwitch)
check(SPTouchBarsSpell12.shown, "switching back restores assigned slot")
combat = false; updateDrivers(); event("PLAYER_REGEN_ENABLED")
SPTouchBarsDB.count = oldCount
SPTouchBarsDB.bindings[12] = nil; event("DISPLAY_SIZE_CHANGED")
-- Map uses a native world-map toggle, and shares normal move/resize/persistence behavior.
check(SPTouchBarsMap.shown and SPTouchBarsMap.icon.mask and SPTouchBarsMap.w == 44,
      "map is a full circular touch button near the minimap")

local beforeMap = mapToggles
click(SPTouchBarsMap); click(SPTouchBarsMap)
check(mapToggles == beforeMap + 2, "map toggles open and closed once per press")
click(control("Edit layout")); click(SPTouchBarsMap)
check(mapToggles == beforeMap + 2 and SPTouchBarsMap.active.shown, "editing selects Map without opening it")
mouse, cx, cy = true, SPTouchBarsMap.x, SPTouchBarsMap.y
invoke(SPTouchBarsMap, "OnMouseDown", "LeftButton")
cx, cy = 1000, 620; tick()
mouse = false; invoke(SPTouchBarsMap, "OnMouseUp", "LeftButton")
click(SPTouchBarsEditorSpells:IsShown() and SPTouchBarsEditorSelectedSizeIncrease or SPTouchBarsEditorUtility:IsShown() and SPTouchBarsEditorUtilitySizeIncrease or SPTouchBarsEditorControlSizeIncrease); click(control("Done"))
check(SPTouchBarsMap.x == 1000 and SPTouchBarsMap.w == 48, "map moves and resizes independently")
click(control("Map: on"))
check(not SPTouchBarsMap.shown and SPTouchBarsInteract.shown, "map has its own visibility switch")
click(control("Map: off"))
combat = true; updateDrivers(); event("PLAYER_REGEN_DISABLED")
click(SPTouchBarsMap)
check(mapToggles == beforeMap + 3, "map still delegates to native UI during combat")
combat = false; updateDrivers(); event("PLAYER_REGEN_ENABLED")
check(SPTouchBarsSwitch.translucent and SPTouchBarsSwitch.face.color[4] == 0.12
      and SPTouchBarsSwitch.rim.color[4] == SPTouchBarsDB.appearance.spells.outlineAlpha,
      "cycle arrows use a light translucent face and the configured outline opacity")
click(control("Set arrows: on")); check(not SPTouchBarsSwitch.shown, "set arrows may be hidden independently")
click(control("Set arrows: off"))
-- Migrate v4's global appearance without sharing colour tables or losing user settings.
SPTouchBarsDB.appearance = nil
SPTouchBarsDB.outlineColor = { r = 0.9, g = 0.6, b = 0.2 }
SPTouchBarsDB.outlineAlpha = 0.35
SPTouchBarsDB.visibility.utility.enabled = false
local mapX = SPTouchBarsDB.controls.map.x
event("PLAYER_LOGOUT"); dofile(path); event("PLAYER_LOGIN")
check(SPTouchBarsDB.appearance.spells.outlineAlpha == 0.35 and SPTouchBarsDB.appearance.utility.outlineColor.r == 0.9
      and SPTouchBarsDB.appearance.spells.outlineColor ~= SPTouchBarsDB.appearance.utility.outlineColor,
      "legacy appearance is copied into two independent groups")
check(not SPTouchBarsUtility1.shown and SPTouchBarsDB.controls.map.x == mapX and SPTouchBarsMap.w == 48,
      "bar visibility and map layout survive reload")
-- The native inspector exposes one focused page at a time, and selection drives its context.
click(control("Edit layout"))
click(SPTouchBarsTabspells)
check(SPTouchBarsEditorSpells:IsShown() and not SPTouchBarsEditorUtility:IsShown()
      and SPTouchBarsEditor.w == 320 and SPTouchBarsEditor.h == 420, "compact spell inspector replaces the tall editor")
check(SPTouchBarsEditorDone.fontString and SPTouchBarsEditorDone.template == "BackdropTemplate",
      "editor uses native font strings and matte frames instead of red panel buttons")
local beforeSpellSize, beforeUtilitySize = SPTouchBarsDB.spells[1].size, SPTouchBarsDB.utilityLayout.size
local beforeUtilityGlow, beforeVisibility = SPTouchBarsDB.appearance.utility.glow, SPTouchBarsDB.visibility.utility.enabled
local beforeAssignment = SPTouchBarsDB.bindings[1].value
local otherSize = SPTouchBarsDB.spells[2].size
check(not SPTouchBarsEditorSelectedSize:IsShown() and not SPTouchBarsEditorSelectedSizeIncrease:IsShown(),
      "no selection shows a prompt instead of a misleading size control")
click(SPTouchBarsSpell1)
check(SPTouchBarsEditorSelectedSize:IsShown(), "selecting a button reveals its size control")
SPTouchBarsEditorSelectedSize:SetValue(112)
check(SPTouchBarsDB.spells[1].size == 112 and SPTouchBarsDB.spells[2].size == otherSize,
      "native size slider changes only the inspected spell")
click(SPTouchBarsUtility1)
check(SPTouchBarsEditorUtility:IsShown() and not SPTouchBarsEditorSpells:IsShown()
      and SPTouchBarsEditor.h == 500, "selecting a utility icon switches to the shared grid inspector")
SPTouchBarsEditorUtilitySize:SetValue(88)
check(SPTouchBarsDB.utilityLayout.size == 88 and SPTouchBarsUtility1.w == SPTouchBarsUtility8.w,
      "native utility slider resizes the complete grid")
click(SPTouchBarsEditorAppearanceSPTouchBarsEditorUtility)
check(SPTouchBarsEditorAppearance:IsShown() and not SPTouchBarsEditorUtility:IsShown(),
      "appearance replaces the body instead of adding a long stack")
SPTouchBarsEditorGlow:SetValue(0)
check(SPTouchBarsDB.appearance.utility.glow == 0 and SPTouchBarsDB.appearance.spells.glow == 1,
      "inspector appearance controls edit the selected group")
click(SPTouchBarsEditorColor)
ColorPickerFrame.r, ColorPickerFrame.g, ColorPickerFrame.b, ColorPickerFrame.a = 0.4, 0.7, 0.2, 0.6
ColorPickerFrame.info.swatchFunc()
check(SPTouchBarsEditorOutline:GetValue() == 60, "native colour picker keeps the inspector opacity in sync")
click(SPTouchBarsEditorAppearanceBack)
click(SPTouchBarsEditorVisibilitySPTouchBarsEditorUtility)
if SPTouchBarsDB.visibility.utility.enabled then click(SPTouchBarsEditorBarEnabled) end
check(SPTouchBarsUtility1.shown, "disabled bar remains available for editing")
local castsBeforePreview = #casts
click(SPTouchBarsPreview)
check(not SPTouchBarsUtility1.shown and not SPTouchBarsSpell2.shown and SPTouchBarsSpell1.shown,
      "play preview respects disabled bars and hides empty slots")
click(SPTouchBarsSpell1)
check(#casts == castsBeforePreview and SPTouchBarsSpell1:GetAttribute("type") == nil,
      "preview remains a safe editing mode and never casts")
check(not SPTouchBarsSpell1.active.shown and SPTouchBarsSpell1.slotLabel.text == "",
      "preview removes editing highlights and slot numbers")
click(SPTouchBarsPreview)
check(SPTouchBarsUtility1.shown and SPTouchBarsSpell2.shown, "leaving preview reveals all configured slots")
click(SPTouchBarsEditorMore)
click(SPTouchBarsEditorClear)
check(SPTouchBarsDB.bindings[1] == nil, "clear slot remains accessible under More")
click(SPTouchBarsEditorUndo)
check(SPTouchBarsDB.bindings[1].value == beforeAssignment and SPTouchBarsDB.spells[1].size == beforeSpellSize
      and SPTouchBarsDB.utilityLayout.size == beforeUtilitySize and SPTouchBarsDB.appearance.utility.glow == beforeUtilityGlow
      and SPTouchBarsDB.visibility.utility.enabled == beforeVisibility,
      "Undo restores assignments, layout, appearance, and visibility from this editing session")
click(SPTouchBarsMap)
check(SPTouchBarsEditorControls:IsShown() and not SPTouchBarsEditorSpells:IsShown(),
      "selecting a standalone control opens its own inspector")
local targetSize = SPTouchBarsDB.controls.target.size
SPTouchBarsEditorControlSize:SetValue(80)
check(SPTouchBarsDB.controls.map.size == 80 and SPTouchBarsDB.controls.target.size == targetSize,
      "control size slider changes just the inspected control")
click(SPTouchBarsEditorSelecttarget)
check(SPTouchBarsTarget.active.shown and not SPTouchBarsMap.active.shown,
      "control list selects the corresponding HUD button")
click(SPTouchBarsEditorMore); click(SPTouchBarsEditorMoreBack)
check(SPTouchBarsEditorControls:IsShown(), "Back restores the current selection context")
local previousW, previousH = UIParent.w, UIParent.h
UIParent.w, UIParent.h = 600, 480; event("DISPLAY_SIZE_CHANGED")
check(SPTouchBarsEditor.h * SPTouchBarsEditor.scale <= 448.001
      and SPTouchBarsEditor.w * SPTouchBarsEditor.scale <= 568.001, "inspector fits smaller displays")
UIParent.w, UIParent.h = previousW, previousH; event("DISPLAY_SIZE_CHANGED")
click(SPTouchBarsPreview)
combat = true; updateDrivers(); event("PLAYER_REGEN_DISABLED")
check(not SPTouchBarsEditor.shown and SPTouchBarsSpell1:GetAttribute("type") == "spell",
      "entering combat exits preview and securely restores assigned actions")
local mapSize = SPTouchBarsDB.controls.map.size
SPTouchBarsEditorControlSize:SetValue(100)
check(SPTouchBarsDB.controls.map.size == mapSize, "combat blocks native inspector slider changes")
combat = false; updateDrivers(); event("PLAYER_REGEN_ENABLED")
click(control("Edit layout"))
local sessionSize = SPTouchBarsDB.spells[1].size
click(SPTouchBarsTabspells); click(SPTouchBarsSpell1); SPTouchBarsEditorSelectedSize:SetValue(120)
click(SPTouchBarsEditorUndo)
check(SPTouchBarsDB.spells[1].size == sessionSize, "reopening the editor creates a fresh Undo baseline")
click(SPTouchBarsEditorDone)
print("SPTouchBars: ok (native selection inspector, sliders, safe preview, session Undo, independent appearance/glow, secure empty-slot and bar visibility, map control, transparent arrows, quest steps, manual rewards, press feedback, modifier layers, utility spacing, private assignments, native/pet bars, combat, persistence)")
