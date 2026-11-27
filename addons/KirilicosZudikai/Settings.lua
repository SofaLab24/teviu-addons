-- Kirilicos Žudikai: its page in the game's Options window (Esc > Options > AddOns).
--
-- Built with Blizzard's Settings API, the way other Forever addons (NodeSight Sparkles,
-- Forever Loot Sparkles, QuestieTrace) build theirs. Each row is stored straight in
-- KirilicosZudikaiDB, the table the slash commands change too, and KZ.SetOption sends
-- slash-command changes through the page so both always agree.

local _, KZ = ...
local Plain, Call = KZ.Plain, KZ.Call

local category

local function Build()
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting
        and Settings.CreateCheckbox and Settings.RegisterAddOnCategory) then
        return
    end
    local page, layout = Settings.RegisterVerticalLayoutCategory(KZ.title)

    local function Register(key, name)
        local default = KZ.ACCOUNT_DEFAULTS[key]
        local setting = Settings.RegisterAddOnSetting(page, "KirilicosZudikai_" .. key, key, KZ.settings,
            type(default), name, default)
        setting:SetValueChangedCallback(function(_, value)
            local onChange = KZ.optionChanged[key]
            if onChange then
                onChange(value)
            end
        end)
        KZ.settingObjects[key] = setting
        return setting
    end

    local function Header(text)
        if layout and CreateSettingsListSectionHeaderInitializer then
            layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
        end
    end

    local function Checkbox(key, name, tooltip)
        Settings.CreateCheckbox(page, Register(key, name), tooltip)
    end

    local function Slider(key, name, minValue, maxValue, tooltip)
        if not (Settings.CreateSliderOptions and Settings.CreateSlider) then
            return
        end
        local options = Settings.CreateSliderOptions(minValue, maxValue, 1)
        if options.SetLabelFormatter and MinimalSliderWithSteppersMixin then
            options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
        end
        Settings.CreateSlider(page, Register(key, name), options, tooltip)
    end

    Header("Kills")
    Checkbox("announce", "Chat line on each kill",
        "A chat line names the player, says killing blow or assist, and shows your totals.")
    Checkbox("sound", "Kill sound", "Plays a sound when a kill is counted.")
    Checkbox("hud", "On-screen counter",
        "The small counter with your total and today's kills. Drag it to move it; click it for the kill list.")

    Header("Nearby Cyrillic enemies")
    Checkbox("alert", "Alert when one appears",
        "Centre-screen text and a chat line when an enemy-faction player with a Cyrillic name gets a nameplate near you. Needs enemy nameplates switched on (V key).")
    Checkbox("alertSound", "Alert sound", "Plays a sound with each alert.")
    Checkbox("alertInBattlegrounds", "Alerts in battlegrounds",
        "Off: no alert text or sound in battlegrounds and arenas, where nearly every enemy would trigger one. Skulls still show.")
    Slider("alertCooldown", "Alert the same player again after (minutes)", 1, 30,
        "Nameplates come and go as you move, so each player alerts at most once in this time.")
    Checkbox("skull", "Skull above their nameplate",
        "A raid-skull icon over their nameplate. Only you see it, and it is not the group's raid marker.")

    Header("Guild")
    Checkbox("guildShare", "Share my kill stats with my guild",
        "Sends your totals to guildmates who use Kirilicos Žudikai, for the Guild tab. Off: no more updates go out; guildmates keep the last numbers they got.")

    if layout and CreateSettingsButtonInitializer then
        -- Search tags off (the last false): addon code adding them taints the Options search.
        layout:AddInitializer(CreateSettingsButtonInitializer("Kill list", "Open", function()
            KZ.ToggleWindow()
        end, "Opens the kill list window (/kz).", false))
    end

    Settings.RegisterAddOnCategory(page)
    category = page
end

-- Opens this addon's Options page (/kz settings, and the button in the kill list).
function KZ.OpenSettings()
    if not category then
        KZ.Print("this game version has no Options page for addons. Use the /kz commands instead.")
        return
    end
    if Plain(Call(InCombatLockdown)) then
        KZ.Print("the Options page opens after combat.")
        return
    end
    local id = (category.GetID and category:GetID()) or category.ID
    if not pcall(Settings.OpenToCategory, id) then
        KZ.Print("could not open the Options page. Find it under Esc > Options > AddOns.")
    end
end

table.insert(KZ.loginHooks, Build)
