-- Kirilicos Žudikai: counts your kills of players whose names contain Cyrillic letters.
--
-- Built for WoW Forever (Interface 16001). Forever closes the combat log to
-- addons, so a kill is read from two other game signals:
--   * PARTY_KILL (attackerGUID, victimGUID): a killing blow. It counts when the
--     attacker is you and the victim is a player.
--   * CHAT_MSG_COMBAT_HONOR_GAIN ("X dies, honorable kill ..."): the game gave
--     you honorable-kill credit, so you took part in the kill (an assist).
-- One death that produces both signals counts once, as a killing blow.

local ADDON_NAME, KZ = ...
_G.KirilicosZudikai = KZ

KZ.name = ADDON_NAME
KZ.title = "Kirilicos Žudikai"
local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
KZ.version = (GetMeta and GetMeta(ADDON_NAME, "Version")) or "?"

-- UI.lua replaces these. They exist here so the core never calls a missing function.
KZ.Refresh = function() end
KZ.Flash = function() end

local MERGE_WINDOW = 10            -- seconds: both signals for one death arrive within this
local LOG_LIMIT = 500              -- newest kills kept in the saved log
local NAME_RETRY = { 0.3, 1, 2.5 } -- waits for a victim name that is not readable yet
local CACHE_LIFE = 15 * 60         -- seconds a seen player's name and level are remembered
local ANNOUNCE_DELAY = 0.6         -- lets the second signal of a death arrive before the chat line

KZ.stats = {
    partyKills = 0,  -- kill events seen (anyone's killing blow)
    myKills = 0,     -- of those, your killing blows on players
    honorLines = 0,  -- honorable-kill chat lines seen
    honorRead = 0,   -- lines whose victim name was read
    honorUnread = 0, -- lines that matched no known template
    namesUnread = 0, -- killing blows whose victim name never became readable
    hidden = 0,      -- events whose values the game kept secret
    counted = 0,     -- kills counted this session
}
KZ.registered = {}

---------------------------------------------------------------------------
-- Safe reading of game values
---------------------------------------------------------------------------

local issecretvalue = issecretvalue

-- Forever can hand addons "secret" values that must not be compared or
-- tested. Anything secret is treated as unknown.
local function Plain(value)
    if issecretvalue then
        local ok, secret = pcall(issecretvalue, value)
        if not ok or secret then
            return nil
        end
    end
    return value
end

local function PlainString(value)
    value = Plain(value)
    if type(value) ~= "string" then
        return nil
    end
    value = value:match("^%s*(.-)%s*$")
    if value == "" then
        return nil
    end
    return value
end

local function PlainNumber(value)
    value = Plain(value)
    if type(value) ~= "number" then
        return nil
    end
    return value
end

local function pass(ok, ...)
    if ok then
        return ...
    end
end

-- Calls a game function without letting an error or a missing API stop us.
local function Call(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    return pass(pcall(fn, ...))
end

---------------------------------------------------------------------------
-- Names
---------------------------------------------------------------------------

-- UTF-8 lead and continuation bytes of U+0400..U+04FF (all Cyrillic letters,
-- including Russian, Ukrainian, Belarusian, Bulgarian and Serbian).
local CYRILLIC = "[\208-\211][\128-\191]"

function KZ.IsCyrillic(name)
    return type(name) == "string" and name:find(CYRILLIC) ~= nil
end

-- Removes colour codes, hyperlinks, brackets and a "-Realm" suffix.
-- Forever names are "First Last", so the space is part of the name.
function KZ.CleanName(name)
    name = PlainString(name)
    if not name then
        return nil
    end
    name = name:gsub("|c%x%x%x%x%x%x%x%x", "")
    name = name:gsub("|r", "")
    name = name:gsub("|H.-|h(.-)|h", "%1")
    name = name:gsub("|", "")
    name = name:match("^%[(.*)%]$") or name
    name = name:gsub("%-[^%s%-]+$", "")
    name = name:match("^%s*(.-)%s*$")
    if name == "" then
        return nil
    end
    return name
end

local function Longer(a, b)
    if a and b then
        return (#b > #a) and b or a
    end
    return a or b
end

-- True for the same person. One source may give only the first name.
local function SameName(a, b)
    if not a or not b then
        return false
    end
    if a == b then
        return true
    end
    local la, lb = a:lower(), b:lower()
    if la == lb then
        return true
    end
    if not la:find(" ", 1, true) and la == lb:match("^(%S+)") then
        return true
    end
    if not lb:find(" ", 1, true) and lb == la:match("^(%S+)") then
        return true
    end
    return false
end
KZ.SameName = SameName

---------------------------------------------------------------------------
-- Players seen nearby (target, mouseover, nameplates)
-- A backup for the name and level when the GUID lookup comes back empty.
---------------------------------------------------------------------------

local seen = {}
local seenCount = 0

local function PruneSeen(now)
    for guid, row in pairs(seen) do
        if now - row.t > CACHE_LIFE then
            seen[guid] = nil
            seenCount = seenCount - 1
        end
    end
end

local function RememberUnit(unit)
    if type(unit) ~= "string" then
        return
    end
    local guid = PlainString(Call(UnitGUID, unit))
    if not guid or not guid:find("^Player%-") then
        return
    end
    local name = KZ.CleanName(Call(GetUnitName, unit, false))
    name = Longer(name, KZ.CleanName(Call(UnitName, unit)))
    if not name then
        return
    end
    local now = GetTime()
    local row = seen[guid]
    if not row then
        row = {}
        seen[guid] = row
        seenCount = seenCount + 1
        if seenCount > 400 then
            PruneSeen(now)
        end
    end
    row.name = Longer(name, row.name)
    row.t = now
    local level = PlainNumber(Call(UnitLevel, unit))
    if level and level > 0 then
        row.level = level
    end
    local _, class = Call(UnitClass, unit)
    row.class = PlainString(class) or row.class
    row.race = PlainString(Call(UnitRace, unit)) or row.race
end

local function GuidForName(name)
    local best, bestTime
    for guid, row in pairs(seen) do
        if SameName(row.name, name) and (not bestTime or row.t > bestTime) then
            best, bestTime = guid, row.t
        end
    end
    return best
end

-- Name, class, race and level of a player GUID.
function KZ.LookupGUID(guid)
    local info = {}
    -- localizedClass, englishClass, localizedRace, englishRace, sex, name, realm, level (Forever)
    local _, class, race, _, _, name, _, level = Call(GetPlayerInfoByGUID, guid)
    info.name = KZ.CleanName(name)
    info.class = PlainString(class)
    info.race = PlainString(race)
    level = PlainNumber(level)
    if level and level > 0 then
        info.level = level
    end
    local row = seen[guid]
    if row then
        info.name = Longer(info.name, row.name)
        info.class = info.class or row.class
        info.race = info.race or row.race
        info.level = info.level or row.level
    end
    return info
end

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------

local ACCOUNT_DEFAULTS = { announce = true, sound = true, hud = true }
local CHAR_COUNTERS = { "total", "killingBlows", "day", "week" }

local function InitData()
    if type(KirilicosZudikaiDB) ~= "table" then
        KirilicosZudikaiDB = {}
    end
    for key, value in pairs(ACCOUNT_DEFAULTS) do
        if KirilicosZudikaiDB[key] == nil then
            KirilicosZudikaiDB[key] = value
        end
    end
    KZ.settings = KirilicosZudikaiDB

    if type(KirilicosZudikaiCharDB) ~= "table" then
        KirilicosZudikaiCharDB = {}
    end
    local db = KirilicosZudikaiCharDB
    for _, key in ipairs(CHAR_COUNTERS) do
        if type(db[key]) ~= "number" then
            db[key] = 0
        end
    end
    if type(db.victims) ~= "table" then
        db.victims = {}
    end
    if type(db.log) ~= "table" then
        db.log = {}
    end
    db.schema = 1
    KZ.char = db
    KZ.RollPeriods()
end

local function DayKey(t)
    return date("%Y-%m-%d", t)
end

-- The Monday that starts the week of t.
local function WeekKey(t)
    local back = (tonumber(date("%w", t)) + 6) % 7
    return date("%Y-%m-%d", t - back * 86400)
end

-- Starts a new "today" or "this week" count when the date has moved on.
function KZ.RollPeriods()
    local db = KZ.char
    if not db then
        return
    end
    local now = time()
    local day, week = DayKey(now), WeekKey(now)
    if db.dayKey ~= day then
        db.dayKey, db.day = day, 0
    end
    if db.weekKey ~= week then
        db.weekKey, db.week = week, 0
    end
end

function KZ.CountVictims()
    local n = 0
    for _ in pairs(KZ.char and KZ.char.victims or {}) do
        n = n + 1
    end
    return n
end

local function Where()
    local zone = PlainString(Call(GetRealZoneText)) or PlainString(Call(GetZoneText)) or "Unknown"
    local _, kind = Call(IsInInstance)
    return zone, PlainString(kind)
end

local function Record(name, killingBlow, info)
    local db = KZ.char
    KZ.RollPeriods()
    local now = time()
    local zone, kind = Where()
    db.total = db.total + 1
    db.day = db.day + 1
    db.week = db.week + 1
    if killingBlow then
        db.killingBlows = db.killingBlows + 1
    end
    local victim = db.victims[name]
    if not victim then
        victim = { n = 0, kb = 0, first = now }
        db.victims[name] = victim
    end
    victim.n = victim.n + 1
    if killingBlow then
        victim.kb = victim.kb + 1
    end
    victim.last = now
    victim.zone = zone
    victim.class = info.class or victim.class
    victim.race = info.race or victim.race
    victim.level = info.level or victim.level
    local entry = {
        t = now,
        name = name,
        zone = zone,
        kb = killingBlow or nil,
        bg = (kind == "pvp" or kind == "arena") or nil,
        level = info.level,
        class = info.class,
        race = info.race,
    }
    local log = db.log
    log[#log + 1] = entry
    while #log > LOG_LIMIT do
        table.remove(log, 1)
    end
    KZ.stats.counted = KZ.stats.counted + 1
    return entry, victim
end

-- A kill first counted as an assist turned out to be your killing blow.
local function UpgradeToKillingBlow(entry)
    if entry.kb then
        return
    end
    local db = KZ.char
    entry.kb = true
    db.killingBlows = db.killingBlows + 1
    local victim = db.victims[entry.name]
    if victim then
        victim.kb = (victim.kb or 0) + 1
    end
end

function KZ.ResetCharacter()
    KirilicosZudikaiCharDB = {}
    InitData()
    KZ.Refresh()
end

---------------------------------------------------------------------------
-- Counting a kill
---------------------------------------------------------------------------

-- Deaths reported in the last few seconds, so a killing blow and the honor
-- line for the same death are counted once.
local recent = {}

local function FindRecent(guid, name, now)
    for i = #recent, 1, -1 do
        if now - recent[i].t > MERGE_WINDOW then
            table.remove(recent, i)
        end
    end
    for i = #recent, 1, -1 do
        local e = recent[i]
        if (guid and e.guid == guid) or (name and SameName(e.name, name)) then
            return e
        end
    end
end

local function Ordinal(n)
    local tens = n % 100
    if tens >= 11 and tens <= 13 then
        return n .. "th"
    end
    local last = n % 10
    if last == 1 then
        return n .. "st"
    elseif last == 2 then
        return n .. "nd"
    elseif last == 3 then
        return n .. "rd"
    end
    return n .. "th"
end

-- "1 kill", "2 kills"
function KZ.Plural(n, word)
    return n .. " " .. word .. (n == 1 and "" or "s")
end

function KZ.ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then
        return c.r, c.g, c.b
    end
    return 1, 1, 1
end

function KZ.ColorName(name, class)
    local r, g, b = KZ.ClassColor(class)
    return ("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), name)
end

function KZ.Print(message)
    local chat = DEFAULT_CHAT_FRAME
    if chat then
        chat:AddMessage("|cffcc3333" .. KZ.title .. "|r: " .. tostring(message))
    end
end

function KZ.PlayKillSound()
    local kit = (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959
    pcall(PlaySound, kit, "Master")
end

function KZ.Announce(entry, victim, isTest)
    local db = KZ.char
    if KZ.settings.announce then
        local how = entry.kb and "killing blow" or "assist"
        local again = (victim.n > 1) and (", " .. Ordinal(victim.n) .. " time") or ""
        local level = entry.level and (" (" .. entry.level .. ")") or ""
        local note = isTest and "  |cff888888(test, not saved)|r" or ""
        KZ.Print(("%s%s - %s%s. Total %d, today %d.%s"):format(
            KZ.ColorName(entry.name, entry.class), level, how, again, db.total, db.day, note))
    end
    if KZ.settings.sound then
        KZ.PlayKillSound()
    end
    KZ.Flash()
end

local function CountIfCyrillic(e, info)
    if e.entry or not KZ.IsCyrillic(e.name) then
        return
    end
    local entry, victim = Record(e.name, e.kb, info or {})
    e.entry = entry
    KZ.Refresh()
    if C_Timer and C_Timer.After then
        C_Timer.After(ANNOUNCE_DELAY, function()
            KZ.Announce(entry, victim)
        end)
    else
        KZ.Announce(entry, victim)
    end
end

-- killingBlow: true for your killing blow, false for honorable-kill credit.
function KZ.Credit(killingBlow, guid, name, info)
    if not KZ.char or not name then
        return
    end
    local e = FindRecent(guid, name, GetTime())
    if e then
        e.guid = e.guid or guid
        e.name = Longer(e.name, name)
        if killingBlow and not e.kb then
            e.kb = true
            if e.entry then
                UpgradeToKillingBlow(e.entry)
                KZ.Refresh()
            end
        end
        CountIfCyrillic(e, info)
        return
    end
    e = { t = GetTime(), guid = guid, name = name, kb = killingBlow and true or false }
    recent[#recent + 1] = e
    CountIfCyrillic(e, info)
end

---------------------------------------------------------------------------
-- Signal 1: your killing blow (PARTY_KILL)
---------------------------------------------------------------------------

local playerGUID

local function MyGUID()
    if not playerGUID then
        playerGUID = PlainString(Call(UnitGUID, "player"))
    end
    return playerGUID
end

local function CreditKillingBlow(guid, attempt)
    local info = KZ.LookupGUID(guid)
    if info.name then
        KZ.Credit(true, guid, info.name, info)
    elseif NAME_RETRY[attempt] and C_Timer and C_Timer.After then
        C_Timer.After(NAME_RETRY[attempt], function()
            CreditKillingBlow(guid, attempt + 1)
        end)
    else
        KZ.stats.namesUnread = KZ.stats.namesUnread + 1
    end
end

function KZ.OnPartyKill(attacker, victim)
    KZ.stats.partyKills = KZ.stats.partyKills + 1
    attacker, victim = PlainString(attacker), PlainString(victim)
    if not attacker or not victim then
        KZ.stats.hidden = KZ.stats.hidden + 1
        return
    end
    if attacker ~= MyGUID() or not victim:find("^Player%-") then
        return
    end
    KZ.stats.myKills = KZ.stats.myKills + 1
    CreditKillingBlow(victim, 1)
end

---------------------------------------------------------------------------
-- Signal 2: honorable-kill credit (assist)
---------------------------------------------------------------------------

local HONOR_TEMPLATES = {
    "COMBATLOG_HONORGAIN",
    "COMBATLOG_HONORGAIN_NO_RANK",
    "COMBATLOG_HONORGAIN_EXHAUSTION1",
    "COMBATLOG_HONORGAIN_EXHAUSTION2",
}
KZ.HONOR_TEMPLATES = HONOR_TEMPLATES
local honorPatterns

-- Turns a game format string such as
--   "%s dies, honorable kill Rank: %s (Estimated Honor Points: %d)"
-- into a Lua pattern, and says which capture holds argument 1 (the name).
function KZ.FormatToPattern(fmt)
    local out, captures, nameCapture, nextArg = {}, 0, nil, 0
    local i, len = 1, #fmt
    while i <= len do
        local ch = fmt:sub(i, i)
        if ch == "%" then
            local rest = fmt:sub(i)
            if rest:sub(2, 2) == "%" then
                out[#out + 1] = "%%"
                i = i + 2
            else
                local whole, pos, conv = rest:match("^(%%(%d+)%$[%-%+ #0]*%d*%.?%d*([sdif]))")
                if not whole then
                    whole, conv = rest:match("^(%%[%-%+ #0]*%d*%.?%d*([sdif]))")
                end
                if whole then
                    nextArg = nextArg + 1
                    captures = captures + 1
                    if conv == "s" and (tonumber(pos) or nextArg) == 1 then
                        nameCapture = captures
                    end
                    if conv == "s" then
                        out[#out + 1] = "(.-)"
                    elseif conv == "f" then
                        out[#out + 1] = "(%-?[%d%.,]+)"
                    else
                        out[#out + 1] = "(%-?%d+)"
                    end
                    i = i + #whole
                else
                    out[#out + 1] = "%%"
                    i = i + 1
                end
            end
        else
            if ch:find("^[%^%$%(%)%.%[%]%*%+%-%?]$") then
                out[#out + 1] = "%" .. ch
            else
                out[#out + 1] = ch
            end
            i = i + 1
        end
    end
    if not nameCapture then
        return nil
    end
    return "^" .. table.concat(out) .. "$", nameCapture
end

local function BuildHonorPatterns()
    honorPatterns = {}
    for _, key in ipairs(HONOR_TEMPLATES) do
        local fmt = PlainString(_G[key])
        local pattern, capture
        if fmt then
            pattern, capture = KZ.FormatToPattern(fmt)
        end
        if pattern then
            honorPatterns[#honorPatterns + 1] = { key = key, pattern = pattern, capture = capture }
        end
    end
end

function KZ.HonorPatternCount()
    if not honorPatterns then
        BuildHonorPatterns()
    end
    return #honorPatterns
end

local function StripCodes(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("|H.-|h(.-)|h", "%1")
    return text
end

-- The victim's name from an honorable-kill line, or nil.
function KZ.ParseHonor(message)
    message = PlainString(message)
    if not message then
        return nil
    end
    if not honorPatterns then
        BuildHonorPatterns()
    end
    local text = StripCodes(message)
    for _, p in ipairs(honorPatterns) do
        local caps = { text:match(p.pattern) }
        local name = KZ.CleanName(caps[p.capture])
        if name then
            return name
        end
    end
    -- English fallback in case the game's templates are missing.
    return KZ.CleanName(text:match("^(.-) dies, honorable kill"))
end

function KZ.OnHonorLine(message)
    KZ.stats.honorLines = KZ.stats.honorLines + 1
    if not PlainString(message) then
        KZ.stats.hidden = KZ.stats.hidden + 1
        return
    end
    local name = KZ.ParseHonor(message)
    if not name then
        KZ.stats.honorUnread = KZ.stats.honorUnread + 1
        KZ.stats.lastUnreadLine = PlainString(message)
        return
    end
    KZ.stats.honorRead = KZ.stats.honorRead + 1
    local guid = GuidForName(name)
    local info = guid and KZ.LookupGUID(guid) or {}
    if info.name and SameName(info.name, name) then
        name = Longer(name, info.name)
    end
    KZ.Credit(false, guid, name, info)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
KZ.frame = frame

local function Listen(event)
    KZ.registered[event] = pcall(frame.RegisterEvent, frame, event) and true or false
end

Listen("ADDON_LOADED")
Listen("PLAYER_LOGIN")
Listen("PLAYER_ENTERING_WORLD")
Listen("PARTY_KILL")
Listen("CHAT_MSG_COMBAT_HONOR_GAIN")
Listen("NAME_PLATE_UNIT_ADDED")
Listen("PLAYER_TARGET_CHANGED")
Listen("UPDATE_MOUSEOVER_UNIT")

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... == ADDON_NAME then
            InitData()
            frame:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_LOGIN" then
        playerGUID = nil
        MyGUID()
        if KZ.InitUI then
            KZ.InitUI()
        end
        if C_Timer and C_Timer.NewTicker then
            -- Keeps "today" and "this week" right across midnight.
            C_Timer.NewTicker(60, function()
                KZ.Refresh()
            end)
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        playerGUID = nil
        MyGUID()
    elseif not KZ.char then
        return
    elseif event == "PARTY_KILL" then
        KZ.OnPartyKill(...)
    elseif event == "CHAT_MSG_COMBAT_HONOR_GAIN" then
        KZ.OnHonorLine(...)
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        RememberUnit(...)
    elseif event == "PLAYER_TARGET_CHANGED" then
        RememberUnit("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        RememberUnit("mouseover")
    end
end)

---------------------------------------------------------------------------
-- Status and self-test
---------------------------------------------------------------------------

local function OnOff(value)
    return value and "|cff44ff44on|r" or "|cffff4444off|r"
end

local function Listening(event)
    return KZ.registered[event] and "listening" or "|cffff4444not available|r"
end

function KZ.PrintStatus()
    local s, db = KZ.stats, KZ.char
    KZ.Print(("version %s. Chat line %s, sound %s, counter %s."):format(
        KZ.version, OnOff(KZ.settings.announce), OnOff(KZ.settings.sound), OnOff(KZ.settings.hud)))
    KZ.Print(("Saved: %s (%d killing blows, %d assists) of %s."):format(
        KZ.Plural(db.total, "kill"), db.killingBlows, db.total - db.killingBlows,
        KZ.Plural(KZ.CountVictims(), "different player")))
    KZ.Print(("Game signals: kill event %s, honor line %s, %d honor templates loaded."):format(
        Listening("PARTY_KILL"), Listening("CHAT_MSG_COMBAT_HONOR_GAIN"), KZ.HonorPatternCount()))
    KZ.Print(("This session: %d kill events (%d your killing blows on players), %d honor lines (%d read, %d not understood)."):format(
        s.partyKills, s.myKills, s.honorLines, s.honorRead, s.honorUnread))
    KZ.Print(("Counted this session: %d. Victim names never readable: %d. Hidden game values: %d."):format(
        s.counted, s.namesUnread, s.hidden))
    if s.lastUnreadLine then
        KZ.Print("Last honor line not understood: " .. s.lastUnreadLine)
    end
end

-- Fills a format string with sample values, the name as argument 1.
function KZ.SampleLine(fmt, name)
    local first = true
    local line = fmt:gsub("%%%%", "\1")
    line = line:gsub("%%(%d*)%$?[%-%+ #0]*%d*%.?%d*([sdif])", function(pos, conv)
        if conv == "s" then
            if pos == "1" or (pos == "" and first) then
                first = false
                return name
            end
            return "Private"
        end
        return "12"
    end)
    return (line:gsub("\1", "%%"))
end

function KZ.RunTest()
    local passed, failed = 0, 0
    local function check(label, got, want)
        if got == want then
            passed = passed + 1
        else
            failed = failed + 1
            KZ.Print(("|cffff4444FAIL|r %s: got %s, expected %s"):format(label, tostring(got), tostring(want)))
        end
    end
    check("Борис Бородач", KZ.IsCyrillic("Борис Бородач"), true)
    check("Ёж Ёжиков", KZ.IsCyrillic("Ёж Ёжиков"), true)
    check("Mary Бородач", KZ.IsCyrillic("Mary Бородач"), true)
    check("Їжак Ґудзик", KZ.IsCyrillic("Їжак Ґудзик"), true)
    check("Test Paladin", KZ.IsCyrillic("Test Paladin"), false)
    check("Zoë Ångström", KZ.IsCyrillic("Zoë Ångström"), false)
    local sample = "Тестовый Игрок"
    for _, key in ipairs(HONOR_TEMPLATES) do
        local fmt = PlainString(_G[key])
        if fmt then
            check(key, KZ.ParseHonor(KZ.SampleLine(fmt, sample)), sample)
        end
    end
    check("linked name", KZ.ParseHonor("|Hplayer:Борис Бородач|h[Борис Бородач]|h dies, honorable kill Rank: Private (Estimated Honor Points: 12)"), "Борис Бородач")
    KZ.Print(("Self-test: %d passed, %d failed. A sample kill follows:"):format(passed, failed))
    KZ.Announce({ name = sample, kb = true, class = "WARRIOR", level = 42 }, { n = 1 }, true)
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local function Help()
    KZ.Print("commands:")
    KZ.Print("  /kz - open or close the kill list")
    KZ.Print("  /kz hud - show or hide the on-screen counter")
    KZ.Print("  /kz sound - turn the kill sound on or off")
    KZ.Print("  /kz chat - turn the chat line on or off")
    KZ.Print("  /kz status - counts and what the game reported this session")
    KZ.Print("  /kz test - self-check and a sample kill (nothing is saved)")
    KZ.Print("  /kz reset confirm - delete this character's kills")
end

SLASH_KIRILICOSZUDIKAI1 = "/kz"
SLASH_KIRILICOSZUDIKAI2 = "/kirilicos"
SlashCmdList.KIRILICOSZUDIKAI = function(input)
    if not KZ.char then
        return
    end
    local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    if cmd == "" then
        if KZ.ToggleWindow then
            KZ.ToggleWindow()
        end
    elseif cmd == "hud" then
        KZ.settings.hud = not KZ.settings.hud
        if KZ.ApplyHUD then
            KZ.ApplyHUD()
        end
        KZ.Print("on-screen counter " .. OnOff(KZ.settings.hud))
    elseif cmd == "sound" then
        KZ.settings.sound = not KZ.settings.sound
        KZ.Print("kill sound " .. OnOff(KZ.settings.sound))
    elseif cmd == "chat" then
        KZ.settings.announce = not KZ.settings.announce
        KZ.Print("chat line " .. OnOff(KZ.settings.announce))
    elseif cmd == "status" then
        KZ.PrintStatus()
    elseif cmd == "test" then
        KZ.RunTest()
    elseif cmd == "reset" then
        if (rest or ""):lower() == "confirm" then
            KZ.ResetCharacter()
            KZ.Print("this character's kills were deleted.")
        else
            KZ.Print("this deletes all kills of this character. Type /kz reset confirm to do it.")
        end
    else
        Help()
    end
end
