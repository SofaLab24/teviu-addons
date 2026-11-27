-- luacheck settings: run `luacheck .` from the repo root.
-- The addons run on WoW's Lua 5.1, so that is the standard library allowed.

std = "lua51"
max_line_length = false
codes = true
exclude_files = { ".luarocks/**", ".release/**", "dist/**" }
ignore = {
    "212/self", -- unused implicit self in methods
}

-- WoW API the addons read. Add names here when an addon starts using more of it.
read_globals = {
    "BackdropTemplateMixin",
    "C_AddOns",
    "C_ChatInfo",
    "C_NamePlate",
    "C_Timer",
    "CreateFrame",
    "CreateSettingsButtonInitializer",
    "CreateSettingsListSectionHeaderInitializer",
    "date",
    "DEFAULT_CHAT_FRAME",
    "Enum",
    "GameTooltip",
    "GetAddOnMetadata",
    "GetGuildInfo",
    "GetPlayerInfoByGUID",
    "GetRealZoneText",
    "GetTime",
    "GetUnitName",
    "GetZoneText",
    "InCombatLockdown",
    "issecretvalue",
    "IsInGuild",
    "IsInInstance",
    "LOCALIZED_CLASS_NAMES_MALE",
    "MinimalSliderWithSteppersMixin",
    "PlaySound",
    "RAID_CLASS_COLORS",
    "RaidNotice_AddMessage",
    "RaidWarningFrame",
    "Settings",
    "SOUNDKIT",
    "time",
    "tinsert",
    "UIParent",
    "UISpecialFrames",
    "UnitClass",
    "UnitFactionGroup",
    "UnitGUID",
    "UnitIsEnemy",
    "UnitIsPlayer",
    "UnitLevel",
    "UnitName",
    "UnitRace",
    "wipe",
}

-- WoW globals the addons write to.
globals = {
    "SlashCmdList",
}

-- Each addon may create only its own globals (saved variables, slash commands, its table).
files["addons/KirilicosZudikai/**/*.lua"] = {
    globals = {
        "KirilicosZudikai",
        "KirilicosZudikaiDB",
        "KirilicosZudikaiCharDB",
        "SLASH_KIRILICOSZUDIKAI1",
        "SLASH_KIRILICOSZUDIKAI2",
    },
}

files["spec/**/*.lua"] = {
    std = "+busted",
    read_globals = {
        "COMBATLOG_HONORGAIN",
        "COMBATLOG_HONORGAIN_NO_RANK",
        "COMBATLOG_DISHONORGAIN",
    },
}
