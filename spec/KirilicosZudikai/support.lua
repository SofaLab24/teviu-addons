-- Shared set-up for the Kirilicos Žudikai specs (not a spec itself: no "_spec" in the name).
-- Load with: local S = dofile("spec/KirilicosZudikai/support.lua")

local M = require("wow_mock")

local S = {
    M = M,
    DIR = "addons/KirilicosZudikai",
    ADDON = "KirilicosZudikai",
    ME = "Player-1-0000000A",
    V1 = "Player-2-00000001",
    V2 = "Player-3-00000002",
    MATE = "Player-1-0000000B",
}

-- A fresh game session as a Horde paladin in "Test Guild". extra() runs before the addon loads.
function S.session(keepSaved, extra)
    return M.NewSession(S.DIR, S.ADDON, keepSaved, function()
        M.units.player = S.ME
        M.players[S.ME] = { name = "Test Paladin", class = "PALADIN", race = "Undead", level = 45, faction = "Horde" }
        if extra then
            extra()
        end
    end)
end

-- A player the client knows about. opts: faction ("Alliance" by default, false = unknown),
-- enemy (true by default), npc.
function S.addPlayer(guid, name, class, level, opts)
    opts = opts or {}
    local faction = opts.faction
    if faction == nil then
        faction = "Alliance"
    end
    M.players[guid] = {
        name = name, class = class or "WARRIOR", race = "Human", level = level or 40,
        faction = faction or nil, enemy = opts.enemy ~= false, npc = opts.npc,
    }
    return M.players[guid]
end

function S.killingBlow(victim, attacker)
    M.Fire("PARTY_KILL", attacker or S.ME, victim)
end

function S.honorLine(name, template)
    M.Fire("CHAT_MSG_COMBAT_HONOR_GAIN", (template or COMBATLOG_HONORGAIN):format(name, "Private", 12))
end

function S.contains(text, piece)
    assert(tostring(text):find(piece, 1, true), ("%q not found in:\n%s"):format(piece, tostring(text)))
end

return S
