-- Kirilicos Žudikai: its page in the game's Options window (Blizzard's Settings API).

local S = dofile("spec/KirilicosZudikai/support.lua")
local M = S.M

local KZ

local function session(keepSaved, extra)
    KZ = S.session(keepSaved, extra)
    return KZ
end

local function control(page, key)
    for _, c in ipairs(page.controls) do
        if c.setting.key == key then
            return c
        end
    end
end

describe("Options page", function()
    it("adds a page with a row for every setting and a kill list button", function()
        session()
        assert.are.equal(1, #M.settingsCategories)
        local page = M.settingsCategories[1]
        assert.are.equal("Kirilicos Žudikai", page.name)
        local keys = {}
        for _, c in ipairs(page.controls) do
            keys[#keys + 1] = c.setting.key
        end
        table.sort(keys)
        local expected = {}
        for key in pairs(KZ.ACCOUNT_DEFAULTS) do
            expected[#expected + 1] = key
        end
        table.sort(expected)
        assert.are.same(expected, keys)
        local button
        for _, initializer in ipairs(page.layout.initializers) do
            if initializer.button then
                button = initializer
            end
        end
        assert.truthy(button)
        assert.is_false(button.searchTags)
        button.onClick()
        assert.is_true(_G.KirilicosZudikaiWindow.shown)
    end)

    it("uses a slider in minutes for the alert time", function()
        session()
        local slider = control(M.settingsCategories[1], "alertCooldown")
        assert.are.equal("slider", slider.kind)
        assert.are.equal(1, slider.options.min)
        assert.are.equal(30, slider.options.max)
        assert.are.equal(5, slider.setting:GetValue())
    end)

    it("passes a change on the page to the addon", function()
        session()
        KZ.settingObjects.hud:SetValue(false)
        assert.is_false(_G.KirilicosZudikaiDB.hud)
        assert.is_false(_G.KirilicosZudikaiHUD.shown)
    end)

    it("shows a slash command change on the page", function()
        session()
        SlashCmdList.KIRILICOSZUDIKAI("sound")
        assert.is_false(KZ.settingObjects.sound:GetValue())
    end)

    it("opens with /kz settings, but not in combat", function()
        session()
        local id = M.settingsCategories[1]:GetID()
        SlashCmdList.KIRILICOSZUDIKAI("settings")
        assert.are.equal(id, M.openedCategory)
        M.openedCategory = nil
        M.inCombat = true
        SlashCmdList.KIRILICOSZUDIKAI("settings")
        assert.is_nil(M.openedCategory)
        S.contains(M.ChatText(), "after combat")
    end)

    it("opens from the Settings button in the kill list", function()
        session()
        SlashCmdList.KIRILICOSZUDIKAI("")
        local window = _G.KirilicosZudikaiWindow
        window.settingsButton:Click()
        assert.is_false(window.shown)
        assert.are.equal(M.settingsCategories[1]:GetID(), M.openedCategory)
    end)

    it("keeps settings across a reload", function()
        session()
        KZ.settingObjects.skull:SetValue(false)
        KZ.settingObjects.alertCooldown:SetValue(12)
        session(true)
        assert.is_false(KZ.settings.skull)
        assert.are.equal(12, KZ.settings.alertCooldown)
        assert.is_false(KZ.settingObjects.skull:GetValue())
    end)

    it("still works on a client without the Settings API", function()
        session(false, function()
            _G.Settings = nil
        end)
        assert.are.equal(0, #M.settingsCategories)
        SlashCmdList.KIRILICOSZUDIKAI("settings")
        S.contains(M.ChatText(), "no Options page")
        SlashCmdList.KIRILICOSZUDIKAI("hud")
        assert.is_false(KZ.settings.hud)
    end)
end)
