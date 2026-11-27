-- Kirilicos Žudikai: the guild leaderboard (addon messages on the GUILD channel).

local S = dofile("spec/KirilicosZudikai/support.lua")
local M = S.M
local PREFIX = "KZudikai"

local KZ

local function session(keepSaved, extra)
    KZ = S.session(keepSaved, extra)
    return KZ
end

local function incoming(text, sender, channel, prefix)
    M.Fire("CHAT_MSG_ADDON", prefix or PREFIX, text, channel or "GUILD", sender or "Глеб Грибов-Testrealm")
end

local function sent()
    return M.SentTexts(PREFIX)
end

local function statsLine(total, kb, week, victims, weekKey)
    return ("S:1:%d:%d:%d:%s:%d:1.2.0"):format(total, kb, week, weekKey or KZ.char.weekKey, victims)
end

describe("guild leaderboard", function()
    it("registers its message prefix", function()
        session()
        assert.is_true(M.prefixes[PREFIX])
    end)

    it("asks for guildmates' numbers and sends its own shortly after login", function()
        session()
        M.Advance(9)
        assert.are.equal(0, #sent())
        M.Advance(5)
        assert.are.same({ "Q:1", ("S:1:0:0:0:%s:0:test"):format(KZ.char.weekKey) }, sent())
        assert.are.equal("GUILD", M.sent[1].chatType)
        assert.is_true(M.sent[2].at - M.sent[1].at >= 1.5)
    end)

    it("sends one update for several kills close together", function()
        session()
        M.Advance(15)
        local before = #sent()
        S.addPlayer(S.V1, "Борис Бородач")
        S.killingBlow(S.V1)
        M.Advance(5)
        S.honorLine("Глеб Грибов")
        M.Advance(5)
        assert.are.equal(before, #sent())
        M.Advance(30)
        local texts = sent()
        assert.are.equal(before + 1, #texts)
        assert.are.equal(("S:1:2:1:2:%s:2:test"):format(KZ.char.weekKey), texts[#texts])
    end)

    it("answers a request, but not twice in a row", function()
        session()
        M.Advance(40)
        local before = #sent()
        incoming("Q:1")
        M.Advance(7)
        assert.are.equal(before + 1, #sent())
        incoming("Q:1")
        M.Advance(7)
        assert.are.equal(before + 1, #sent())
    end)

    it("does not answer a request right after sending its numbers", function()
        session()
        M.Advance(13)
        local before = #sent()
        incoming("Q:1")
        M.Advance(7)
        assert.are.equal(before, #sent())
    end)

    it("puts guildmates on the board, best first, with you included", function()
        session()
        incoming(statsLine(17, 9, 4, 12), "Глеб Грибов-Testrealm")
        incoming(statsLine(5, 2, 1, 4), "Mary Smith-Testrealm")
        local rows, guild = KZ.GuildBoard()
        assert.are.equal("Test Guild", guild)
        assert.are.same({ "Глеб Грибов", "Mary Smith", "Test Paladin" }, { rows[1].name, rows[2].name, rows[3].name })
        assert.are.equal(17, rows[1].total)
        assert.are.equal(9, rows[1].kb)
        assert.are.equal(4, rows[1].week)
        assert.are.equal(12, rows[1].victims)
        assert.are.equal(1, rows[1].rank)
        assert.is_true(rows[3].me)
        assert.are.equal(2, KZ.guildStats.received)
    end)

    it("counts an earlier week's numbers as 0 this week", function()
        session()
        incoming(statsLine(17, 9, 4, 12, "2026-11-16"))
        local rows = KZ.GuildBoard()
        assert.are.equal(17, rows[1].total)
        assert.are.equal(0, rows[1].week)
    end)

    it("ignores broken, foreign and hidden messages", function()
        session()
        local good = statsLine(17, 9, 4, 12)
        incoming(good, nil, nil, "OtherAddon") -- another addon's prefix: not ours at all
        incoming(good, nil, "WHISPER")
        incoming(good, M.SECRET)
        incoming(M.SECRET)
        incoming(statsLine(17, 99, 4, 12)) -- more killing blows than kills
        incoming(("S:1:abc:9:4:%s:12:1.2.0"):format(KZ.char.weekKey))
        incoming(("S:2:17:9:4:%s:12:1.2.0"):format(KZ.char.weekKey)) -- a newer protocol
        incoming("X:1")
        assert.are.equal(1, #KZ.GuildBoard())
        assert.are.equal(7, KZ.guildStats.ignored)
        assert.are.equal(0, KZ.guildStats.received)
    end)

    it("ignores its own message coming back from the guild channel", function()
        session()
        M.Advance(15)
        local texts = sent()
        incoming(texts[#texts], "Test Paladin-Testrealm")
        incoming("Q:1", "Test Paladin-Testrealm")
        M.Advance(10)
        assert.are.equal(1, #KZ.GuildBoard())
        assert.are.equal(#texts, #sent())
    end)

    it("sends nothing and shows no board outside a guild", function()
        session(false, function()
            M.guildName = nil
        end)
        M.Advance(20)
        assert.are.equal(0, #M.sent)
        assert.is_nil(KZ.GuildBoard())
        SlashCmdList.KIRILICOSZUDIKAI("guild")
        assert.are.equal("You are not in a guild.", _G.KirilicosZudikaiWindow.footer.text)
    end)

    it("waits while the game blocks addon messages", function()
        session(false, function()
            M.lockdown = true
        end)
        M.Advance(20)
        assert.are.equal(0, #sent())
        M.lockdown = false
        M.Advance(31)
        assert.are.equal(2, #sent())
    end)

    it("tries again when the game throttles a message", function()
        session(false, function()
            M.sendResults = { 3 } -- AddonMessageThrottle for the first message
        end)
        M.Advance(15)
        assert.are.equal(1, KZ.guildStats.failed)
        assert.are.same({ ("S:1:0:0:0:%s:0:test"):format(KZ.char.weekKey) }, sent())
        M.Advance(30)
        assert.are.equal("Q:1", sent()[2])
    end)

    it("stops sharing when switched off, but still shows guildmates", function()
        session()
        KZ.SetOption("guildShare", false)
        M.Advance(15)
        assert.are.same({ "Q:1" }, sent())
        incoming("Q:1")
        M.Advance(10)
        assert.are.same({ "Q:1" }, sent())
        incoming(statsLine(17, 9, 4, 12))
        assert.are.equal(2, #KZ.GuildBoard())
    end)

    it("shares again right away when switched back on", function()
        session()
        KZ.SetOption("guildShare", false)
        M.Advance(15)
        KZ.SetOption("guildShare", true)
        M.Advance(3)
        local texts = sent()
        assert.are.equal(("S:1:0:0:0:%s:0:test"):format(KZ.char.weekKey), texts[#texts])
    end)

    it("shows your other characters in the same guild", function()
        session()
        S.addPlayer(S.V1, "Борис Бородач")
        S.killingBlow(S.V1)
        M.Advance(40)
        _G.KirilicosZudikaiCharDB = nil -- log in another character on the same account
        session(true, function()
            M.players[S.ME].name = "Alt Character"
        end)
        local rows = KZ.GuildBoard()
        assert.are.equal(2, #rows)
        assert.are.equal("Test Paladin", rows[1].name)
        assert.are.equal(1, rows[1].total)
        assert.are.equal("Alt Character", rows[2].name)
        assert.is_true(rows[2].me)
    end)

    it("forgets guildmates not heard from in 90 days", function()
        session()
        KZ.settings.guilds = { ["Test Guild"] = { members = {
            ["Old Timer"] = { total = 3, kb = 1, week = 0, weekKey = "2026-08-03", victims = 2, version = "1.2.0",
                seen = time() - 91 * 86400 },
        } } }
        assert.are.equal(1, #KZ.GuildBoard())
        assert.is_nil(KZ.settings.guilds["Test Guild"].members["Old Timer"])
    end)

    it("shows the board on the Guild tab and asks for fresh numbers", function()
        session()
        M.Advance(75) -- past the one-request-a-minute limit
        incoming(statsLine(17, 9, 4, 12))
        local before = #sent()
        SlashCmdList.KIRILICOSZUDIKAI("guild")
        local window = _G.KirilicosZudikaiWindow
        assert.is_true(window.shown)
        assert.are.equal("1-2 of 2   (scroll with the mouse wheel)", window.footer.text)
        M.Advance(2)
        assert.are.equal("Q:1", sent()[before + 1])
    end)

    it("says so when no guildmate has the addon yet", function()
        session()
        SlashCmdList.KIRILICOSZUDIKAI("guild")
        assert.are.equal("No guildmates with Kirilicos Žudikai 1.2+ heard from yet.", _G.KirilicosZudikaiWindow.footer.text)
    end)
end)
