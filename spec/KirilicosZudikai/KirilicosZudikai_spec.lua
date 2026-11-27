-- Kirilicos Žudikai, driven through the fake WoW client (spec/helpers/wow_mock.lua).
-- Run from the repo root: busted spec/KirilicosZudikai

local M = require("wow_mock")

local DIR, ADDON = "addons/KirilicosZudikai", "KirilicosZudikai"
local ME = "Player-1-0000000A"
local V1 = "Player-2-00000001"
local V2 = "Player-3-00000002"
local MATE = "Player-1-0000000B"

local KZ

local function session(keepSaved, extra)
    KZ = M.NewSession(DIR, ADDON, keepSaved, function()
        M.units.player = ME
        M.players[ME] = { name = "Test Paladin", class = "PALADIN", race = "Undead", level = 45 }
        if extra then
            extra()
        end
    end)
    return KZ
end

local function addPlayer(guid, name, class, level)
    M.players[guid] = { name = name, class = class or "WARRIOR", race = "Human", level = level or 40 }
end

local function killingBlow(victim, attacker)
    M.Fire("PARTY_KILL", attacker or ME, victim)
end

local function honorLine(name, template)
    M.Fire("CHAT_MSG_COMBAT_HONOR_GAIN", (template or COMBATLOG_HONORGAIN):format(name, "Private", 12))
end

local function assertContains(text, piece)
    assert(tostring(text):find(piece, 1, true), ("%q not found in:\n%s"):format(piece, tostring(text)))
end

describe("Kirilicos Žudikai", function()
    describe("killing blows and assists", function()
        it("counts a killing blow on a Cyrillic player", function()
            session()
            addPlayer(V1, "Борис Бородач", "WARRIOR", 40)
            killingBlow(V1)
            M.Advance(1)
            local db = KZ.char
            assert.are.equal(1, db.total)
            assert.are.equal(1, db.killingBlows)
            assert.are.equal(1, db.day)
            assert.are.equal(1, db.victims["Борис Бородач"].n)
            assert.are.equal(40, db.log[1].level)
            assertContains(M.ChatText(), "Борис Бородач")
            assertContains(M.ChatText(), "killing blow")
            assert.are.equal(1, M.sounds)
            assertContains(_G.KirilicosZudikaiHUD.count.text, "1 kill ")
        end)

        it("counts a killing blow and its honor line once", function()
            session()
            addPlayer(V1, "Борис Бородач")
            killingBlow(V1)
            M.Advance(0.1)
            honorLine("Борис Бородач")
            M.Advance(2)
            assert.are.equal(1, KZ.char.total)
            assert.are.equal(1, KZ.char.killingBlows)
            assert.are.equal(1, #M.chat)
        end)

        it("turns an assist into a killing blow when the honor line comes first", function()
            session()
            addPlayer(V1, "Борис Бородач")
            honorLine("Борис Бородач")
            M.Advance(0.2)
            killingBlow(V1)
            M.Advance(2)
            assert.are.equal(1, KZ.char.total)
            assert.are.equal(1, KZ.char.killingBlows)
            assert.are.equal(1, KZ.char.victims["Борис Бородач"].kb)
            assertContains(M.ChatText(), "killing blow")
        end)

        it("counts an honor line alone as an assist", function()
            session()
            honorLine("Ёж Ёжиков")
            M.Advance(1)
            assert.are.equal(1, KZ.char.total)
            assert.are.equal(0, KZ.char.killingBlows)
            assert.is_nil(KZ.char.log[1].kb)
            assertContains(M.ChatText(), "assist")
        end)

        it("does not count a party member's killing blow alone, but counts honor credit as an assist", function()
            session()
            addPlayer(V1, "Борис Бородач")
            killingBlow(V1, MATE)
            M.Advance(1)
            assert.are.equal(0, KZ.char.total)
            honorLine("Борис Бородач")
            M.Advance(1)
            assert.are.equal(1, KZ.char.total)
            assert.are.equal(0, KZ.char.killingBlows)
        end)

        it("ignores NPC kills", function()
            session()
            killingBlow("Creature-0-1-2-3-1234-0000ABCD")
            M.Advance(1)
            assert.are.equal(0, KZ.char.total)
            assert.are.equal(0, KZ.stats.myKills)
        end)

        it("counts the same player again later", function()
            session()
            addPlayer(V1, "Борис Бородач")
            killingBlow(V1)
            M.Advance(30)
            killingBlow(V1)
            M.Advance(1)
            assert.are.equal(2, KZ.char.total)
            assert.are.equal(2, KZ.char.victims["Борис Бородач"].n)
            assertContains(M.ChatText(), "2nd time")
        end)

        it("counts two Cyrillic players dying together as two", function()
            session()
            addPlayer(V1, "Борис Бородач")
            addPlayer(V2, "Глеб Грибов")
            killingBlow(V1)
            honorLine("Глеб Грибов")
            honorLine("Борис Бородач")
            M.Advance(2)
            assert.are.equal(2, KZ.char.total)
            assert.are.equal(1, KZ.char.killingBlows)
        end)

        it("marks battleground kills", function()
            session()
            M.instanceType = "pvp"
            M.zone = "Warsong Gulch"
            honorLine("Борис Бородач")
            M.Advance(1)
            assert.is_true(KZ.char.log[1].bg)
            assert.are.equal("Warsong Gulch", KZ.char.log[1].zone)
        end)
    end)

    describe("names", function()
        it("counts Ukrainian letters as Cyrillic", function()
            session()
            honorLine("Їжак Ґудзик")
            M.Advance(1)
            assert.are.equal(1, KZ.char.total)
        end)

        it("does not count Latin names, accented or not", function()
            session()
            addPlayer(V1, "Zoë Ångström")
            killingBlow(V1)
            honorLine("Mary Smith")
            M.Advance(1)
            assert.are.equal(0, KZ.char.total)
            assert.are.equal(0, #M.chat)
        end)

        it("falls back to the nameplate when the GUID lookup hides the name", function()
            session()
            M.players[V1] = { name = M.SECRET, unitName = "Борис Бородач", class = "MAGE", race = "Gnome", level = 33 }
            M.units.nameplate1 = V1
            M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
            killingBlow(V1)
            M.Advance(1)
            assert.are.equal(1, KZ.char.total)
            assert.are.equal("Борис Бородач", KZ.char.log[1].name)
        end)

        it("still counts a name that becomes readable a moment later", function()
            session()
            addPlayer(V1, nil)
            killingBlow(V1)
            M.Advance(0.1)
            assert.are.equal(0, KZ.char.total)
            M.players[V1].name = "Борис Бородач"
            M.Advance(3)
            assert.are.equal(1, KZ.char.total)
        end)

        it("reports a name that never becomes readable instead of counting it", function()
            session()
            addPlayer(V1, nil)
            killingBlow(V1)
            M.Advance(5)
            assert.are.equal(0, KZ.char.total)
            assert.are.equal(1, KZ.stats.namesUnread)
        end)

        it("merges a first-name-only honor line with the full-name killing blow", function()
            session()
            addPlayer(V1, "Борис Бородач")
            honorLine("Борис")
            killingBlow(V1)
            M.Advance(2)
            assert.are.equal(1, KZ.char.total)
            assert.are.equal(1, KZ.char.killingBlows)
        end)

        it("counts a Latin first name with a Cyrillic last name once the full name is known", function()
            session()
            addPlayer(V1, "Mary Бородач")
            honorLine("Mary")
            killingBlow(V1)
            M.Advance(2)
            assert.are.equal(1, KZ.char.total)
            assert.are.equal("Mary Бородач", KZ.char.log[1].name)
        end)

        it("drops a realm suffix", function()
            session()
            honorLine("Борис Бородач-Testrealm")
            M.Advance(1)
            assert.are.equal("Борис Бородач", KZ.char.log[1].name)
        end)
    end)

    describe("honor lines", function()
        it("reads the no-rank template", function()
            session()
            M.Fire("CHAT_MSG_COMBAT_HONOR_GAIN", COMBATLOG_HONORGAIN_NO_RANK:format("Ёж Ёжиков", 12))
            M.Advance(1)
            assert.are.equal(1, KZ.char.total)
        end)

        it("reads a linked, coloured name", function()
            session()
            M.Fire("CHAT_MSG_COMBAT_HONOR_GAIN",
                "|cffff0000|Hplayer:Борис Бородач|h[Борис Бородач]|h|r dies, honorable kill Rank: Private (Estimated Honor Points: 12)")
            M.Advance(1)
            assert.are.equal("Борис Бородач", KZ.char.log[1] and KZ.char.log[1].name)
        end)

        it("does not treat a dishonorable kill as a kill", function()
            session()
            M.Fire("CHAT_MSG_COMBAT_HONOR_GAIN", COMBATLOG_DISHONORGAIN:format("Тест Тестов"))
            M.Advance(1)
            assert.are.equal(0, KZ.char.total)
            assert.are.equal(1, KZ.stats.honorUnread)
        end)

        it("turns format strings with positions and widths into patterns", function()
            session()
            local pattern, capture = KZ.FormatToPattern("%2$s tötet %1$s (%3$d, %4$.1f%%)")
            assert.are.equal(2, capture)
            local caps = { ("Rang tötet Борис Бородач (5, 2.5%)"):match(pattern) }
            assert.are.equal("Борис Бородач", caps[capture])
            assert.is_nil(KZ.FormatToPattern("No name here: %d"))
        end)
    end)

    describe("hidden values and missing API", function()
        it("skips a secret attacker, victim or message without errors", function()
            session()
            addPlayer(V1, "Борис Бородач")
            M.Fire("PARTY_KILL", M.SECRET, V1)
            M.Fire("PARTY_KILL", ME, M.SECRET)
            M.Fire("CHAT_MSG_COMBAT_HONOR_GAIN", M.SECRET)
            M.Advance(1)
            assert.are.equal(0, KZ.char.total)
            assert.are.equal(3, KZ.stats.hidden)
        end)

        it("still loads and counts assists on a client without PARTY_KILL", function()
            session(false, function()
                M.unknownEvents.PARTY_KILL = true
            end)
            assert.is_false(KZ.registered.PARTY_KILL)
            honorLine("Борис Бородач")
            M.Advance(1)
            assert.are.equal(1, KZ.char.total)
            SlashCmdList.KIRILICOSZUDIKAI("status")
            assertContains(M.ChatText(), "not available")
        end)
    end)

    describe("saved data", function()
        it("survives a reload, and the saved data is plain", function()
            session()
            addPlayer(V1, "Борис Бородач")
            killingBlow(V1)
            M.Advance(1)
            KZ.settings.sound = false
            session(true)
            assert.are.equal(1, KZ.char.total)
            assert.are.equal(1, KZ.char.victims["Борис Бородач"].kb)
            assert.is_false(KZ.settings.sound)
        end)

        it("resets today and this week when the date moves on", function()
            session()
            honorLine("Борис Бородач")
            M.Advance(1)
            assert.are.equal(1, KZ.char.day)
            M.clock = M.clock + 86400
            M.Advance(61)
            assert.are.equal(0, KZ.char.day)
            assert.are.equal(1, KZ.char.week) -- Friday to Saturday: same week
            assert.are.equal(1, KZ.char.total)
            M.clock = M.clock + 3 * 86400
            M.Advance(61)
            assert.are.equal(0, KZ.char.week) -- Monday starts a new week
        end)

        it("keeps the newest 500 kills in the log", function()
            session()
            for i = 1, 510 do
                KZ.Credit(false, nil, "Игрок " .. i, {})
                M.Advance(11)
            end
            assert.are.equal(510, KZ.char.total)
            assert.are.equal(500, #KZ.char.log)
            assert.are.equal("Игрок 11", KZ.char.log[1].name)
        end)
    end)

    describe("commands and window", function()
        it("passes its own /kz test and saves nothing", function()
            session()
            SlashCmdList.KIRILICOSZUDIKAI("test")
            assertContains(M.ChatText(), "0 failed")
            assert.are.equal(0, KZ.char.total)
        end)

        it("runs every slash command", function()
            session()
            honorLine("Борис Бородач")
            M.Advance(1)
            for _, cmd in ipairs({ "", "", "hud", "hud", "sound", "sound", "chat", "chat", "status", "help", "reset" }) do
                SlashCmdList.KIRILICOSZUDIKAI(cmd)
            end
            assert.are.equal(1, KZ.char.total) -- plain "reset" does not delete
            assertContains(M.ChatText(), "Saved: 1 kill (")
            SlashCmdList.KIRILICOSZUDIKAI("reset confirm")
            assert.are.equal(0, KZ.char.total)
            assert.are.equal(0, KZ.CountVictims())
        end)

        it("lists players and recent kills, and scrolls", function()
            session()
            for i = 1, 20 do
                honorLine("Игрок Номер" .. i)
                M.Advance(11)
            end
            honorLine("Игрок Номер1")
            M.Advance(1)
            SlashCmdList.KIRILICOSZUDIKAI("")
            local window = _G.KirilicosZudikaiWindow
            assert.is_true(window.shown)
            assert.are.equal("1-14 of 20   (scroll with the mouse wheel)", window.footer.text)
            assertContains(window.summary.text, "Kills: |cffffffff21|r")
            window.scripts.OnMouseWheel(window, -1)
            assert.are.equal("4-17 of 20   (scroll with the mouse wheel)", window.footer.text)
            window.recentTab:Click()
            assert.are.equal("1-14 of 21   (scroll with the mouse wheel)", window.footer.text)
            window.victimsTab:Click()
            SlashCmdList.KIRILICOSZUDIKAI("")
            assert.is_false(window.shown)
        end)

        it("only calls widget methods the fake client knows (catches misspelled API)", function()
            local unknown = {}
            for name in pairs(M.unknownMethods) do
                unknown[#unknown + 1] = name
            end
            table.sort(unknown)
            assert.are.equal("", table.concat(unknown, ", "))
        end)
    end)
end)
