-- Kirilicos Žudikai: the guild leaderboard.
--
-- Each player sends only their own numbers to the guild as one short addon message,
-- the way other Forever addons share data (GearQuestForever, ForeverDungeonJournal,
-- OpenMap). Nobody passes on anyone else's numbers, so a broken or modified client can
-- only get its own row wrong.
--
-- Messages use the prefix "KZudikai" on the GUILD channel, with fields separated by ":".
--   S:1:<kills>:<killing blows>:<this week>:<week start YYYY-MM-DD>:<different players>:<version>
--   Q:1   asks guildmates to send their numbers (after login, and when the Guild tab opens)
-- The game allows 10 addon messages at once, then 1 a second. This file sends at most
-- one message every SEND_GAP seconds.

local _, KZ = ...
local Plain, PlainString, Call = KZ.Plain, KZ.PlainString, KZ.Call

local PREFIX = "KZudikai"
local PROTOCOL = 1
local SEND_GAP = 1.5               -- seconds between our own messages
local LOGIN_DELAY = 10             -- lets the guild roster load first
local CHANGE_DELAY = 30            -- kills close together go out as one update
local REPLY_MIN, REPLY_MAX = 1, 6  -- random wait before answering, so replies spread out
local REPLY_SKIP = 20              -- our numbers went out this recently: a request needs no answer
local REQUEST_COOLDOWN = 60        -- at most one request a minute
local RETRY_DELAY = 30             -- the game would not send (busy or locked): try again after this
local FORGET_AFTER = 90 * 24 * 3600 -- guildmates not heard from in 90 days leave the board
local MAX_COUNT = 10000000

KZ.guildStats = { sent = 0, received = 0, ignored = 0, failed = 0 }

local pending = {}      -- "stats" / "request" -> GetTime() when it is due
local ticking = false
local lastSendAt = -math.huge
local lastSent = {}     -- kind -> GetTime() it last went out
local lastText          -- the last text we sent, to recognise it coming back

local function Longer(a, b)
    if a and b then
        return (#b > #a) and b or a
    end
    return a or b
end

-- Our own full name ("First Last"), as guildmates' messages show it.
local function MyName()
    local guid = PlainString(Call(UnitGUID, "player"))
    local name = guid and KZ.LookupGUID(guid).name
    return Longer(name, KZ.CleanName(Call(GetUnitName, "player", false)))
end

-- The guild's name, or nil outside a guild. Right after login the game may not know it
-- yet, so the last name seen on this character stands in.
local function CurrentGuild()
    local name = PlainString(Call(GetGuildInfo, "player"))
    if name then
        KZ.char.guild = name
        return name
    end
    if Plain(Call(IsInGuild)) then
        return KZ.char.guild
    end
    return nil
end

local function GuildData(guild)
    local all = KZ.settings.guilds
    if type(all) ~= "table" then
        all = {}
        KZ.settings.guilds = all
    end
    local data = all[guild]
    if type(data) ~= "table" then
        data = {}
        all[guild] = data
    end
    if type(data.members) ~= "table" then
        data.members = {}
    end
    return data
end

local function CleanVersion(version)
    version = tostring(version or ""):gsub("[^%w%.%-]", "")
    if version == "" then
        return "?"
    end
    return version:sub(1, 20)
end

local function MyNumbers()
    local db = KZ.char
    KZ.RollPeriods()
    return {
        total = db.total,
        kb = db.killingBlows,
        week = db.week,
        weekKey = db.weekKey,
        victims = KZ.CountVictims(),
        version = CleanVersion(KZ.version),
    }
end

-- Keeps this character's numbers in the guild's table, so your other characters in the
-- same guild show them even though nobody can send them while you play someone else.
local function SaveOwnRow()
    local guild, me = CurrentGuild(), MyName()
    if not guild or not me then
        return
    end
    local row = MyNumbers()
    row.seen = time()
    GuildData(guild).members[me] = row
end

local function StatsText()
    local n = MyNumbers()
    return ("S:%d:%d:%d:%d:%s:%d:%s"):format(PROTOCOL, n.total, n.kb, n.week, n.weekKey or "", n.victims, n.version)
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------

local RESULT = Enum and Enum.SendAddonMessageResult or {}
local TRY_AGAIN = {
    [RESULT.AddonMessageThrottle or 3] = true,
    [RESULT.ChannelThrottle or 8] = true,
    [RESULT.AddOnMessageLockdown or 11] = true,
}

-- Sends one message now. Returns false when it should be tried again later.
local function SendNow(kind)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) or not CurrentGuild() then
        return true
    end
    if kind == "stats" and not KZ.settings.guildShare then
        return true
    end
    if Plain(Call(C_ChatInfo.InChatMessagingLockdown)) then
        return false
    end
    local text = (kind == "stats") and StatsText() or ("Q:%d"):format(PROTOCOL)
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, text, "GUILD")
    result = Plain(result)
    if ok and (result == nil or result == true or result == (RESULT.Success or 0)) then
        KZ.guildStats.sent = KZ.guildStats.sent + 1
        lastSent[kind] = GetTime()
        lastText = text
        if kind == "stats" then
            SaveOwnRow()
        end
        return true
    end
    KZ.guildStats.failed = KZ.guildStats.failed + 1
    KZ.guildStats.lastError = ok and tostring(result) or "error"
    return not (ok and TRY_AGAIN[result])
end

local Pump

local function Arm()
    local now, nextAt = GetTime(), nil
    for _, due in pairs(pending) do
        local at = math.max(due, lastSendAt + SEND_GAP)
        if not nextAt or at < nextAt then
            nextAt = at
        end
    end
    if nextAt and not ticking and C_Timer and C_Timer.After then
        ticking = true
        C_Timer.After(math.max(0.05, nextAt - now), Pump)
    end
end

-- Sends the earliest due message (one per call), then waits for the next.
Pump = function()
    ticking = false
    local now = GetTime()
    if now - lastSendAt >= SEND_GAP then
        local kind, earliest
        for k, due in pairs(pending) do
            if due <= now and (not earliest or due < earliest) then
                kind, earliest = k, due
            end
        end
        if kind then
            pending[kind] = nil
            lastSendAt = now
            if not SendNow(kind) then
                pending[kind] = now + RETRY_DELAY
            end
        end
    end
    Arm()
end

-- Plans a message. An already planned one keeps its earlier time.
local function Queue(kind, delay)
    local due = GetTime() + (delay or 0)
    if not pending[kind] or due < pending[kind] then
        pending[kind] = due
    end
    Arm()
end

-- Asks guildmates for their numbers (the Guild tab calls this), at most once a minute.
function KZ.RequestGuildStats()
    if lastSent.request and GetTime() - lastSent.request < REQUEST_COOLDOWN then
        return
    end
    Queue("request", 0)
end

KZ.OnStatsChanged = function()
    SaveOwnRow()
    if KZ.settings.guildShare then
        Queue("stats", CHANGE_DELAY)
    end
end

KZ.optionChanged.guildShare = function(on)
    if on then
        Queue("stats", 1)
    end
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------

local function ParseStats(rest)
    local total, kb, week, weekKey, victims, version =
        rest:match("^:(%d+):(%d+):(%d+):(%d%d%d%d%-%d%d%-%d%d):(%d+):([%w%.%-]+)$")
    if not total then
        return nil
    end
    total, kb, week, victims = tonumber(total), tonumber(kb), tonumber(week), tonumber(victims)
    if total > MAX_COUNT or kb > total or week > total or victims > total or #version > 20 then
        return nil
    end
    return { total = total, kb = kb, week = week, weekKey = weekKey, victims = victims, version = version }
end

local function Ignore()
    KZ.guildStats.ignored = KZ.guildStats.ignored + 1
end

function KZ.OnAddonMessage(prefix, text, channel, sender)
    if PlainString(prefix) ~= PREFIX then
        return
    end
    text, channel, sender = PlainString(text), PlainString(channel), PlainString(sender)
    local name = KZ.CleanName(sender)
    if not text or not name or channel ~= "GUILD" then
        return Ignore()
    end
    local me = MyName()
    if name == me or (text == lastText and KZ.SameName(name, me)) then
        return -- our own message coming back from the guild channel
    end
    local kind, protocol, rest = text:match("^(%u):(%d+)(.*)$")
    if not kind or tonumber(protocol) ~= PROTOCOL then
        return Ignore()
    end
    if kind == "Q" then
        local sentAt = lastSent.stats
        if KZ.settings.guildShare and not (sentAt and GetTime() - sentAt < REPLY_SKIP) then
            Queue("stats", REPLY_MIN + math.random() * (REPLY_MAX - REPLY_MIN))
        end
    elseif kind == "S" then
        local row = ParseStats(rest)
        local guild = CurrentGuild()
        if not row or not guild then
            return Ignore()
        end
        row.seen = time()
        GuildData(guild).members[name] = row
        KZ.guildStats.received = KZ.guildStats.received + 1
        KZ.Refresh()
    else
        Ignore()
    end
end

---------------------------------------------------------------------------
-- The board
---------------------------------------------------------------------------

-- Rows for the Guild tab, best first, and the guild's name. nil outside a guild.
-- Each row: name, total, kb, week, victims, version, seen (nil for you), rank, me.
function KZ.GuildBoard()
    local guild = CurrentGuild()
    if not guild then
        return nil
    end
    local me, now = MyName(), time()
    local mine = MyNumbers()
    local members = GuildData(guild).members
    local rows = {}
    for name, m in pairs(members) do
        if type(m) ~= "table" or now - (tonumber(m.seen) or 0) > FORGET_AFTER then
            members[name] = nil
        elseif name ~= me then
            rows[#rows + 1] = {
                name = name, total = m.total or 0, kb = m.kb or 0,
                -- a week count from an earlier week is stale
                week = (m.weekKey == mine.weekKey) and (m.week or 0) or 0,
                victims = m.victims or 0, version = m.version, seen = m.seen,
            }
        end
    end
    rows[#rows + 1] = {
        name = me or "You", total = mine.total, kb = mine.kb, week = mine.week,
        victims = mine.victims, version = mine.version, me = true,
    }
    table.sort(rows, function(a, b)
        if a.total ~= b.total then
            return a.total > b.total
        end
        if a.kb ~= b.kb then
            return a.kb > b.kb
        end
        return a.name < b.name
    end)
    for i, row in ipairs(rows) do
        row.rank = i
    end
    return rows, guild
end

function KZ.GuildStatusLines()
    local s, guild = KZ.guildStats, CurrentGuild()
    local line = ("Guild: %s, sharing %s. Messages this session: %d sent, %d received, %d ignored, %d failed%s."):format(
        guild or "none", KZ.settings.guildShare and "on" or "off", s.sent, s.received, s.ignored, s.failed,
        s.lastError and (" (last: " .. s.lastError .. ")") or "")
    return { line }
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

Call(C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)

local frame = CreateFrame("Frame")
pcall(frame.RegisterEvent, frame, "CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, _, ...)
    if KZ.char then
        KZ.OnAddonMessage(...)
    end
end)

table.insert(KZ.loginHooks, function()
    SaveOwnRow()
    Queue("request", LOGIN_DELAY)
    if KZ.settings.guildShare then
        Queue("stats", LOGIN_DELAY + 2)
    end
end)
