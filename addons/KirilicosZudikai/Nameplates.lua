-- Kirilicos Žudikai: alert and skull for nearby Cyrillic-named enemy players.
--
-- When an enemy-faction player's nameplate appears and their full name contains
-- Cyrillic letters:
--   * a raid-skull icon is drawn above the nameplate. It is the addon's own icon: since
--     12.0 SetRaidTarget is protected, so addons can't set the real raid marker. Only you
--     see it, and any number of players can have one.
--   * an alert (centre-screen text, chat line, sound) shows at most once per player per
--     few minutes, because nameplates come and go as you move.
-- The icon is a small frame placed on the nameplate, the way Questie's Forever version
-- attaches its nameplate icons. Nameplates the game keeps from addons are left alone.

local _, KZ = ...
local Plain, PlainString, Call = KZ.Plain, KZ.PlainString, KZ.Call

local SKULL_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
local SKULL_SIZE = 26
local ALERT_COLOR = { r = 1, g = 0.25, b = 0.25 }

local skulls = {}     -- nameplate unit token -> skull frame
local spare = {}      -- skull frames not in use
local alertedAt = {}  -- player GUID (or name) -> GetTime() of the last alert
local alertCount = 0

KZ.plateStats = { matched = 0, alerts = 0, forbidden = 0, hidden = 0 }

local function Faction(unit)
    return PlainString(Call(UnitFactionGroup, unit))
end

-- For an enemy-faction player with a Cyrillic name: name, GUID, details. Otherwise nil.
function KZ.CyrillicEnemy(unit)
    if not Plain(Call(UnitIsPlayer, unit)) then
        return nil
    end
    local mine, theirs = Faction("player"), Faction(unit)
    if mine and theirs then
        if mine == theirs then
            return nil
        end
    elseif not Plain(Call(UnitIsEnemy, "player", unit)) then
        return nil
    end
    KZ.RememberUnit(unit)
    local guid = PlainString(Call(UnitGUID, unit))
    local info = guid and KZ.LookupGUID(guid) or {}
    local name = info.name or KZ.CleanName(Call(GetUnitName, unit, false))
    if not name then
        KZ.plateStats.hidden = KZ.plateStats.hidden + 1
        return nil
    end
    if not KZ.IsCyrillic(name) then
        return nil
    end
    return name, guid, info
end

---------------------------------------------------------------------------
-- Skulls
---------------------------------------------------------------------------

local function NewSkull()
    local skull = CreateFrame("Frame")
    skull:SetSize(SKULL_SIZE, SKULL_SIZE)
    skull:EnableMouse(false)
    local icon = skull:CreateTexture(nil, "OVERLAY")
    icon:SetAllPoints()
    icon:SetTexture(SKULL_TEXTURE)
    skull.icon = icon
    return skull
end

local function HideSkull(unit)
    local skull = skulls[unit]
    if not skull then
        return
    end
    skulls[unit] = nil
    skull:Hide()
    skull:ClearAllPoints()
    skull:SetParent(nil)
    spare[#spare + 1] = skull
end

local function ShowSkull(unit)
    local plate = Call(C_NamePlate and C_NamePlate.GetNamePlateForUnit, unit)
    if not plate then
        return
    end
    local ok, forbidden = pcall(plate.IsForbidden, plate)
    if not ok or forbidden then
        KZ.plateStats.forbidden = KZ.plateStats.forbidden + 1
        return
    end
    local skull = skulls[unit] or table.remove(spare) or NewSkull()
    skull:SetParent(plate)
    skull:SetFrameStrata("HIGH")
    skull:ClearAllPoints()
    skull:SetPoint("BOTTOM", plate, "TOP", 0, 0)
    skull:Show()
    skulls[unit] = skull
end

-- The skull on a nameplate, if any (for the tests and for checking in game).
function KZ.SkullFor(unit)
    return skulls[unit]
end

---------------------------------------------------------------------------
-- Alerts
---------------------------------------------------------------------------

local function InBattleground()
    local _, kind = Call(IsInInstance)
    kind = PlainString(kind)
    return kind == "pvp" or kind == "arena"
end

local function Details(info)
    local parts = {}
    if info.level then
        parts[#parts + 1] = tostring(info.level)
    end
    if info.class then
        parts[#parts + 1] = KZ.ClassName(info.class)
    end
    if #parts == 0 then
        return ""
    end
    return ", " .. table.concat(parts, " ")
end

local function ShowAlert(name, info, isTest)
    local who = KZ.ColorName(name, info.class) .. Details(info)
    local note = isTest and "  |cff888888(test)|r" or ""
    KZ.Print("Cyrillic enemy nearby: " .. who .. note)
    if RaidNotice_AddMessage and RaidWarningFrame then
        pcall(RaidNotice_AddMessage, RaidWarningFrame, "Cyrillic enemy: " .. who .. note, ALERT_COLOR)
    end
    if KZ.settings.alertSound then
        KZ.PlaySoundKit("RAID_BOSS_EMOTE_WARNING", "RAID_WARNING")
    end
end

-- What an alert looks like (/kz test). Nothing is remembered.
function KZ.PreviewAlert(name, info)
    if KZ.settings.alert then
        ShowAlert(name, info, true)
    end
end

local function ForgetOldAlerts(now, cooldown)
    for key, at in pairs(alertedAt) do
        if now - at >= cooldown then
            alertedAt[key] = nil
            alertCount = alertCount - 1
        end
    end
end

local function MaybeAlert(name, guid, info)
    local key = guid or name
    local now = GetTime()
    local cooldown = (tonumber(KZ.settings.alertCooldown) or 5) * 60
    local last = alertedAt[key]
    if last and now - last < cooldown then
        return
    end
    if not last then
        alertCount = alertCount + 1
        if alertCount > 500 then
            ForgetOldAlerts(now, cooldown)
        end
    end
    alertedAt[key] = now
    if InBattleground() and not KZ.settings.alertInBattlegrounds then
        return
    end
    KZ.plateStats.alerts = KZ.plateStats.alerts + 1
    ShowAlert(name, info)
end

---------------------------------------------------------------------------
-- Nameplates coming and going
---------------------------------------------------------------------------

-- quiet: only the skull, no alert (used when skulls are switched back on).
local function OnPlateAdded(unit, quiet)
    if not KZ.char or type(unit) ~= "string" then
        return
    end
    HideSkull(unit) -- nameplates are reused for other units
    local s = KZ.settings
    if not s.skull and (quiet or not s.alert) then
        return
    end
    local name, guid, info = KZ.CyrillicEnemy(unit)
    if not name then
        return
    end
    KZ.plateStats.matched = KZ.plateStats.matched + 1
    if s.skull then
        ShowSkull(unit)
    end
    if s.alert and not quiet then
        MaybeAlert(name, guid, info)
    end
end

local function HideAllSkulls()
    local units = {}
    for unit in pairs(skulls) do
        units[#units + 1] = unit
    end
    for _, unit in ipairs(units) do
        HideSkull(unit)
    end
end

-- Puts skulls on the nameplates already showing, or takes them all off.
function KZ.RefreshSkulls()
    HideAllSkulls()
    if not KZ.settings.skull or not (C_NamePlate and C_NamePlate.GetNamePlates) then
        return
    end
    for _, plate in ipairs(Call(C_NamePlate.GetNamePlates) or {}) do
        local ok, unit = pcall(function()
            return plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        end)
        unit = ok and PlainString(unit)
        if unit then
            OnPlateAdded(unit, true)
        end
    end
end

KZ.optionChanged.skull = KZ.RefreshSkulls

function KZ.NameplateStatusLines()
    local s, p = KZ.settings, KZ.plateStats
    return { ("Nearby enemies: alerts %s, skulls %s. This session: %d Cyrillic enemies seen, %d alerts, %d nameplates the game kept from addons, %d names hidden."):format(
        s.alert and "on" or "off", s.skull and "on" or "off", p.matched, p.alerts, p.forbidden, p.hidden) }
end

local frame = CreateFrame("Frame")
for _, event in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_ENTERING_WORLD" }) do
    pcall(frame.RegisterEvent, frame, event)
end
frame:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_ENTERING_WORLD" then
        HideAllSkulls() -- a loading screen resets the nameplates
        return
    end
    unit = PlainString(unit) -- a secret token can't be used as a table key
    if not unit then
        return
    end
    if event == "NAME_PLATE_UNIT_ADDED" then
        OnPlateAdded(unit)
    else
        HideSkull(unit)
    end
end)
