-- A small stand-in for the WoW Forever client: enough API to load an addon
-- outside the game and drive it with fake game events from busted specs.
--
-- Usage in a spec:
--   local M = require("wow_mock")
--   local ns = M.NewSession("addons/MyAddon", "MyAddon")
--   M.Fire("SOME_EVENT", ...)
--   M.Advance(1) -- seconds; runs due C_Timer callbacks
--
-- It runs on Lua 5.1 to 5.4 and LuaJIT. The addons themselves must stay
-- Lua 5.1 (what WoW uses); CI runs the specs on Lua 5.1.

local M = {}

local loadstring = loadstring or load -- luacheck: ignore 113

-- Plays the part of a Midnight-era "secret" value. Using it the wrong way errors.
M.SECRET = setmetatable({}, {
    __index = function() error("a secret value was indexed", 2) end,
    __newindex = function() error("a secret value was changed", 2) end,
    __concat = function() error("a secret value was concatenated", 2) end,
    __lt = function() error("a secret value was compared", 2) end,
    __le = function() error("a secret value was compared", 2) end,
    __tostring = function() return "<secret>" end,
})

-- Widget methods the mock has heard of. Any other method name still works (as a
-- no-op) but is recorded in M.unknownMethods, which catches misspelled API calls.
local KNOWN_METHODS = {}
for name in ([[
    RegisterEvent UnregisterEvent SetScript GetScript Show Hide IsShown SetShown
    CreateTexture CreateFontString CreateAnimationGroup CreateAnimation SetText GetText
    SetPoint ClearAllPoints GetPoint SetAllPoints SetSize SetWidth SetHeight SetTextColor
    SetFrameStrata SetClampedToScreen SetMovable EnableMouse EnableMouseWheel RegisterForDrag
    RegisterForClicks StartMoving StopMovingOrSizing SetBackdrop SetBackdropColor
    SetBackdropBorderColor SetColorTexture SetTexture SetAlpha SetFromAlpha SetToAlpha
    SetDuration Play Stop SetJustifyH SetWordWrap SetSpacing LockHighlight UnlockHighlight
    SetOwner AddLine AddDoubleLine AddMessage
]]):gmatch("%S+") do
    KNOWN_METHODS[name] = true
end
M.unknownMethods = {}

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------

local Widget = {}

function Widget:RegisterEvent(event)
    if M.unknownEvents[event] then
        error("Attempt to register unknown event \"" .. event .. "\"", 2)
    end
    M.events[event] = M.events[event] or {}
    M.events[event][self] = true
end
function Widget:UnregisterEvent(event)
    if M.events[event] then
        M.events[event][self] = nil
    end
end
function Widget:SetScript(name, fn) self.scripts[name] = fn end
function Widget:GetScript(name) return self.scripts[name] end
function Widget:Show() self.shown = true end
function Widget:Hide() self.shown = false end
function Widget:IsShown() return self.shown end
function Widget:SetShown(v) self.shown = v and true or false end
function Widget:SetText(text) self.text = text end
function Widget:GetText() return self.text end
function Widget:SetTextColor(r, g, b) self.color = { r, g, b } end
function Widget:SetPoint(...) if not self.point then self.point = { ... } end end
function Widget:ClearAllPoints() self.point = nil end
function Widget:GetPoint()
    local p = self.point or { "CENTER" }
    if type(p[2]) == "table" then
        return p[1], p[2], p[3], p[4], p[5]
    end
    return p[1], nil, p[1], p[2] or 0, p[3] or 0
end
function Widget:CreateTexture() return M.NewWidget("Texture") end
function Widget:CreateFontString() return M.NewWidget("FontString") end
function Widget:CreateAnimationGroup() return M.NewWidget("AnimationGroup") end
function Widget:CreateAnimation() return M.NewWidget("Animation") end
-- Test helper, not WoW API: runs the OnClick script like a mouse click would.
function Widget:Click(button)
    if self.scripts.OnClick then self.scripts.OnClick(self, button or "LeftButton") end
end

local WidgetMeta = {
    __index = function(_, key)
        local method = Widget[key]
        if method then
            return method
        end
        if type(key) == "string" and key:match("^%u") then
            if not KNOWN_METHODS[key] then
                M.unknownMethods[key] = true
            end
            return function() end
        end
        return nil
    end,
}

function M.NewWidget(kind)
    return setmetatable({ kind = kind, scripts = {}, shown = true }, WidgetMeta)
end

---------------------------------------------------------------------------
-- Client state and controls for the specs
---------------------------------------------------------------------------

function M.Reset()
    M.events = {}
    M.timers = {}
    M.chat = {}
    M.sounds = 0
    M.players = {}   -- guid -> { name, unitName, class, race, level }
    M.units = {}     -- unit token -> guid
    M.zone = "Badlands"
    M.instanceType = "none"
    M.unknownEvents = {}
    M.now = 1000                                                        -- GetTime()
    M.clock = os.time({ year = 2026, month = 11, day = 27, hour = 20 }) -- time()
end
M.Reset()

local function RunDue(limit)
    while true do
        local nextTimer, index
        for i, t in ipairs(M.timers) do
            if t.at <= limit and (not nextTimer or t.at < nextTimer.at) then
                nextTimer, index = t, i
            end
        end
        if not nextTimer then
            return
        end
        table.remove(M.timers, index)
        if nextTimer.every and not nextTimer.cancelled then
            nextTimer.at = nextTimer.at + nextTimer.every
            table.insert(M.timers, nextTimer)
        end
        if not nextTimer.cancelled then
            nextTimer.fn()
        end
    end
end

-- Moves both clocks forward and runs every timer that comes due.
function M.Advance(seconds)
    local target = M.now + seconds
    while M.now < target do
        local dt = math.min(0.05, target - M.now)
        M.now = M.now + dt
        M.clock = M.clock + dt
        RunDue(M.now)
    end
end

function M.Fire(event, ...)
    local frames = {}
    for frame in pairs(M.events[event] or {}) do
        frames[#frames + 1] = frame
    end
    for _, frame in ipairs(frames) do
        local handler = frame.scripts.OnEvent
        if handler then
            handler(frame, event, ...)
        end
    end
end

function M.ChatText()
    return table.concat(M.chat, "\n")
end

---------------------------------------------------------------------------
-- WoW API
---------------------------------------------------------------------------

local api = {}

api.issecretvalue = function(value) return rawequal(value, M.SECRET) end
api.GetTime = function() return M.now end
api.time = function(t) if t then return os.time(t) end return math.floor(M.clock) end
api.date = function(fmt, t) return os.date(fmt, t or math.floor(M.clock)) end
api.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
api.tinsert = table.insert

api.C_Timer = {
    After = function(delay, fn)
        table.insert(M.timers, { at = M.now + delay, fn = fn })
    end,
    NewTicker = function(interval, fn)
        local ticker = { at = M.now + interval, every = interval, fn = fn }
        function ticker:Cancel() self.cancelled = true end
        table.insert(M.timers, ticker)
        return ticker
    end,
}
api.C_AddOns = { GetAddOnMetadata = function(_, field) if field == "Version" then return "test" end end }

api.CreateFrame = function(kind, name, _, template)
    local frame = M.NewWidget(kind)
    frame.template = template
    if name then
        _G[name] = frame
    end
    return frame
end
api.UIParent = M.NewWidget("Frame")
api.GameTooltip = M.NewWidget("GameTooltip")
api.DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) table.insert(M.chat, message) end }
api.UISpecialFrames = {}
api.SlashCmdList = {}
api.BackdropTemplateMixin = {}

local function player(guid) return guid and M.players[guid] end
local function unitPlayer(unit) return player(M.units[unit]) end

api.UnitGUID = function(unit) return M.units[unit] end
api.GetPlayerInfoByGUID = function(guid)
    local p = player(guid)
    if not p then return nil end
    return p.class and p.class:lower(), p.class, p.race, p.race, 2, p.name, "", p.level
end
api.GetUnitName = function(unit) local p = unitPlayer(unit) return p and (p.unitName or p.name) end
-- Forever's UnitName often returns only the first word of "First Last".
api.UnitName = function(unit)
    local p = unitPlayer(unit)
    local name = p and (p.unitName or p.name)
    if type(name) == "string" then return (name:match("^(%S+)")), nil end
    return name
end
api.UnitLevel = function(unit) local p = unitPlayer(unit) return p and p.level end
api.UnitClass = function(unit) local p = unitPlayer(unit) if p then return p.class, p.class end end
api.UnitRace = function(unit) local p = unitPlayer(unit) if p then return p.race, p.race end end
api.IsInInstance = function() return M.instanceType ~= "none", M.instanceType end
api.GetRealZoneText = function() return M.zone end
api.GetZoneText = function() return M.zone end
api.PlaySound = function() M.sounds = M.sounds + 1 end
api.SOUNDKIT = { RAID_WARNING = 8959 }
api.RAID_CLASS_COLORS = {
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
    MAGE = { r = 0.25, g = 0.78, b = 0.92 }, ROGUE = { r = 1, g = 0.96, b = 0.41 },
}
api.LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Warrior", PALADIN = "Paladin", MAGE = "Mage", ROGUE = "Rogue" }

-- enUS templates as the game defines them.
api.COMBATLOG_HONORGAIN = "%s dies, honorable kill Rank: %s (Estimated Honor Points: %d)"
api.COMBATLOG_HONORGAIN_NO_RANK = "%s dies, honorable kill (Estimated Honor Points: %d)"
api.COMBATLOG_DISHONORGAIN = "%s dies, dishonorable kill."

function M.InstallAPI()
    for key, value in pairs(api) do
        _G[key] = value
    end
end

---------------------------------------------------------------------------
-- Loading an addon and saving its data like the client does
---------------------------------------------------------------------------

local function Serialize(value)
    local kind = type(value)
    if kind == "string" then
        return ("%q"):format(value)
    elseif kind == "number" or kind == "boolean" then
        return tostring(value)
    elseif kind == "table" then
        local parts = {}
        for k, v in pairs(value) do
            local kk = type(k)
            if kk ~= "string" and kk ~= "number" then
                error("saved data has a key of type " .. kk)
            end
            parts[#parts + 1] = "[" .. Serialize(k) .. "] = " .. Serialize(v)
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    error("saved data has a value of type " .. kind)
end
M.Serialize = Serialize

-- Starts a fresh client session: loads the files listed in the addon's .toc and
-- fires the login events. With keepSaved, the saved variables are written out
-- and read back the way the game does between sessions. setup() runs after the
-- client state is reset and before the addon loads.
function M.NewSession(dir, addonName, keepSaved, setup)
    local saved, files = {}, {}
    local toc = assert(io.open(dir .. "/" .. addonName .. ".toc", "rb"))
    for line in toc:read("*a"):gmatch("[^\r\n]+") do
        local vars = line:match("^##%s*SavedVariables[%w]*:%s*(.+)$")
        if vars then
            for var in vars:gmatch("[^,%s]+") do
                saved[#saved + 1] = var
            end
        elseif not line:match("^%s*#") and line:match("%S") then
            files[#files + 1] = (line:match("^%s*(.-)%s*$"):gsub("\\", "/"))
        end
    end
    toc:close()

    local carried = {}
    for _, var in ipairs(saved) do
        local value = rawget(_G, var)
        if keepSaved and value ~= nil then
            carried[var] = assert(loadstring("return " .. Serialize(value)))()
        end
        _G[var] = nil
    end

    M.Reset()
    M.InstallAPI()
    if setup then
        setup()
    end
    local ns = {}
    for _, file in ipairs(files) do
        local chunk = assert(loadfile(dir .. "/" .. file))
        chunk(addonName, ns)
    end
    for var, value in pairs(carried) do
        _G[var] = value
    end
    M.Fire("ADDON_LOADED", addonName)
    M.Fire("PLAYER_LOGIN")
    M.Fire("PLAYER_ENTERING_WORLD")
    return ns
end

return M
