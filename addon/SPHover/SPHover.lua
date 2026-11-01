-- SPHover: tells the visionOS shim where the clickable UI is, so it can put the system's look
-- highlight over it (visionOS never tells an app where the user looks, so the game can't draw its
-- own hover state from gaze).
--
-- Addons have no channel out of the game that works without a click, so the rects go out as pixels:
-- a strip a few physical pixels tall along the bottom of the screen, N_BLOCKS colored blocks across
-- its width, 3 bits per block (red, green, blue: each fully on or off). The shim reads the bottom of
-- every presented frame, samples the block centers and hides the strip. Wire format
-- (shims/appkit/sphoverstrip.h decodes it):
--   strip frame, FRAME_BYTES bytes: 'V' 'W' seq chunk count payload[PAYLOAD_BYTES] fletcher16 (hi, lo)
--   message (the chunks' payloads in order): rect count (2 bytes), then per rect x, y, w, h as 12-bit
--   fractions of the screen (origin bottom left), packed into 6 bytes.
-- A message repeats, one chunk per frame, until the rects change; seq then moves on.

local N_BLOCKS = 320
local FRAME_BYTES = 120  -- N_BLOCKS * 3 / 8
local PAYLOAD_BYTES = FRAME_BYTES - 7
local STRIP_PIXELS = 3
local SCAN_INTERVAL = 0.2
local MAX_RECTS = 400
local CLICKABLE = { Button = true, CheckButton = true, EditBox = true, Slider = true }

local floor, max, min = math.floor, math.max, math.min

local strip = CreateFrame("Frame", "SPHoverStrip", UIParent)
strip:SetFrameStrata("TOOLTIP")
strip:SetFrameLevel(9000)
strip:EnableMouse(false)
strip:SetPoint("BOTTOMLEFT")
strip:SetPoint("BOTTOMRIGHT")

local blocks = {}
for i = 1, N_BLOCKS do
    local t = strip:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(0, 0, 0, 1)
    blocks[i] = t
end

local laidOutWidth, laidOutHeight
local function layout()
    local _, physH = GetPhysicalScreenSize()
    local height = STRIP_PIXELS * 768 / physH / UIParent:GetEffectiveScale()
    local width = strip:GetWidth()
    if width == laidOutWidth and height == laidOutHeight then return end
    laidOutWidth, laidOutHeight = width, height
    strip:SetHeight(height)
    for i = 1, N_BLOCKS do
        local t = blocks[i]
        t:ClearAllPoints()
        t:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", width * (i - 1) / N_BLOCKS, 0)
        t:SetSize(width / N_BLOCKS, height)
    end
end

-- ---- finding the clickable rects

local function isForbidden(f)
    return f.IsForbidden and f:IsForbidden()
end

-- The frame's rect in screen units, clipped to its scrolling or clipping ancestors (a list's rows
-- scrolled out of view are still "visible").
local function screenRect(f)
    local l, b, w, h = f:GetRect()
    if not l then return end
    local s = f:GetEffectiveScale()
    l, b = l * s, b * s
    local r, t = l + w * s, b + h * s
    local p = f:GetParent()
    while p and not isForbidden(p) do
        if p:GetObjectType() == "ScrollFrame" or (p.DoesClipChildren and p:DoesClipChildren()) then
            local pl, pb, pw, ph = p:GetRect()
            if pl then
                local ps = p:GetEffectiveScale()
                l, b = max(l, pl * ps), max(b, pb * ps)
                r, t = min(r, (pl + pw) * ps), min(t, (pb + ph) * ps)
            end
        end
        p = p:GetParent()
    end
    return l, b, r, t
end

local function mouseEnabled(f)
    if f.IsMouseClickEnabled then return f:IsMouseClickEnabled() or f:IsMouseMotionEnabled() end
    return f:IsMouseEnabled()
end

local function quantize(v)
    return floor(max(0, min(1, v)) * 4095 + 0.5)
end

-- The message for the current UI, as a string of bytes.
local function scan()
    local sw = UIParent:GetWidth() * UIParent:GetEffectiveScale()
    local sh = UIParent:GetHeight() * UIParent:GetEffectiveScale()
    local out, n = {}, 0
    local f = EnumerateFrames()
    while f and n < MAX_RECTS do
        if not isForbidden(f) and CLICKABLE[f:GetObjectType()] and f:IsVisible() and mouseEnabled(f)
            and f:GetEffectiveAlpha() > 0.05 then
            local l, b, r, t = screenRect(f)
            if l then
                l, b, r, t = max(l, 0), max(b, 0), min(r, sw), min(t, sh)
                -- Skip slivers and anything nearly screen-sized (a backdrop, not a button).
                if r - l >= 4 and t - b >= 4 and (r - l) * (t - b) < sw * sh / 4 then
                    local x, y = quantize(l / sw), quantize(b / sh)
                    local w, h = quantize((r - l) / sw), quantize((t - b) / sh)
                    n = n + 1
                    out[n] = string.char(floor(x / 16), x % 16 * 16 + floor(y / 256), y % 256,
                                         floor(w / 16), w % 16 * 16 + floor(h / 256), h % 256)
                end
            end
        end
        f = EnumerateFrames(f)
    end
    return string.char(floor(n / 256), n % 256) .. table.concat(out)
end

-- ---- sending

local message, seq, chunks, chunkIndex = nil, 0, {}, 0

local function fletcher16(bytes, n)
    local s1, s2 = 0, 0
    for i = 1, n do
        s1 = (s1 + bytes[i]) % 255
        s2 = (s2 + s1) % 255
    end
    return s2, s1
end

local function buildChunks(msg)
    chunks = {}
    local count = max(1, math.ceil(#msg / PAYLOAD_BYTES))
    for c = 1, count do
        local bytes = { 86, 87, seq, c - 1, count }  -- 'V' 'W'
        local part = msg:sub((c - 1) * PAYLOAD_BYTES + 1, c * PAYLOAD_BYTES)
        for i = 1, PAYLOAD_BYTES do
            bytes[5 + i] = part:byte(i) or 0
        end
        bytes[FRAME_BYTES - 1], bytes[FRAME_BYTES] = fletcher16(bytes, FRAME_BYTES - 2)
        chunks[c] = bytes
    end
    chunkIndex = 0
end

local function showChunk(bytes)
    local bit = 0  -- index into the frame's bits, most significant first
    local function nextBit()
        local byte = bytes[floor(bit / 8) + 1]
        local v = floor(byte / 2 ^ (7 - bit % 8)) % 2
        bit = bit + 1
        return v
    end
    for i = 1, N_BLOCKS do
        local r, g, b = nextBit(), nextBit(), nextBit()
        blocks[i]:SetColorTexture(r, g, b, 1)
    end
end

local sinceScan = SCAN_INTERVAL
strip:SetScript("OnUpdate", function(self, elapsed)
    sinceScan = sinceScan + elapsed
    if sinceScan >= SCAN_INTERVAL then
        sinceScan = 0
        layout()
        local ok, msg = pcall(scan)
        if ok and msg ~= message then
            message = msg
            seq = (seq + 1) % 256
            buildChunks(msg)
        end
    end
    if #chunks > 1 or chunkIndex == 0 then
        chunkIndex = chunkIndex % #chunks + 1
        showChunk(chunks[chunkIndex])
    end
end)

SPHover = { scan = scan, chunks = function() return chunks end, N_BLOCKS = N_BLOCKS }
