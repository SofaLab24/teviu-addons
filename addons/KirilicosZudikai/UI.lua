-- Kirilicos Žudikai: the on-screen counter and the kill list window.
-- Text uses the game's own font objects (GameFont*), which include
-- Cyrillic letters. A raw font file could show them as boxes.

local _, KZ = ...

local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local ROWS = 14
local ROW_HEIGHT = 18
local HUD_DEFAULT = { "TOP", "TOP", 0, -80 }

local hud, window
local rows = {}
local list = {}
local view = "victims"
local offset = 0

local function ShortDate(t)
    return t and date("%b %d %H:%M", t) or ""
end

local function LongDate(t)
    return t and date("%Y-%m-%d %H:%M", t) or "?"
end

local function ClassName(class)
    return (class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class
end

-- "Level 42 Undead Warrior", leaving out what is unknown.
local function Describe(level, race, class)
    local parts = {}
    if level then
        parts[#parts + 1] = "Level " .. level
    end
    if race then
        parts[#parts + 1] = race
    end
    if class then
        parts[#parts + 1] = ClassName(class)
    end
    if #parts == 0 then
        return nil
    end
    return table.concat(parts, " ")
end

local function SetBackdrop(frame, info, r, g, b, a, br, bg, bb)
    if frame.SetBackdrop then
        frame:SetBackdrop(info)
        frame:SetBackdropColor(r, g, b, a)
        if br then
            frame:SetBackdropBorderColor(br, bg, bb, 1)
        end
    end
end

local function SavePoint(frame, key)
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    if point then
        KZ.settings[key] = { point, relativePoint, x, y }
    end
end

local function RestorePoint(frame, key, default)
    local p = KZ.settings[key]
    if type(p) ~= "table" or not p[1] then
        p = default
    end
    frame:ClearAllPoints()
    frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

---------------------------------------------------------------------------
-- On-screen counter
---------------------------------------------------------------------------

local function HudTooltip(self)
    local db = KZ.char
    if not db then
        return
    end
    KZ.RollPeriods()
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(KZ.title)
    GameTooltip:AddDoubleLine("Kills", db.total, 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("Killing blows", db.killingBlows, 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Assists", db.total - db.killingBlows, 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Today", db.day, 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("This week", db.week, 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Different players", KZ.CountVictims(), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddLine("Click: open the kill list. Drag: move.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function CreateHUD()
    hud = CreateFrame("Button", "KirilicosZudikaiHUD", UIParent, BACKDROP_TEMPLATE)
    hud:SetSize(150, 36)
    hud:SetFrameStrata("MEDIUM")
    hud:SetClampedToScreen(true)
    hud:SetMovable(true)
    hud:EnableMouse(true)
    hud:RegisterForDrag("LeftButton")
    hud:RegisterForClicks("LeftButtonUp")
    SetBackdrop(hud, {
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    }, 0.05, 0.05, 0.05, 0.8, 0.7, 0.15, 0.15)

    -- A red glow that fades out when a kill is counted.
    local glow = hud:CreateTexture(nil, "ARTWORK", nil, -1)
    glow:SetPoint("TOPLEFT", 3, -3)
    glow:SetPoint("BOTTOMRIGHT", -3, 3)
    glow:SetColorTexture(0.9, 0.1, 0.1, 0.6)
    glow:SetAlpha(0)
    local pulse = glow:CreateAnimationGroup()
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetDuration(1.5)
    hud.pulse = pulse

    local icon = hud:CreateTexture(nil, "ARTWORK")
    icon:SetSize(22, 22)
    icon:SetPoint("LEFT", 8, 0)
    icon:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")

    local label = hud:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", icon, "TOPRIGHT", 6, 2)
    label:SetText(KZ.title)

    local count = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    count:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 6, -2)
    hud.count = count

    hud:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    hud:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePoint(self, "hudPoint")
    end)
    hud:SetScript("OnClick", function()
        KZ.ToggleWindow()
    end)
    hud:SetScript("OnEnter", HudTooltip)
    hud:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

function KZ.ApplyHUD()
    if not hud then
        return
    end
    if KZ.settings.hud then
        hud:Show()
    else
        hud:Hide()
    end
end
KZ.optionChanged.hud = KZ.ApplyHUD

function KZ.Flash()
    if hud and hud:IsShown() then
        hud.pulse:Stop()
        hud.pulse:Play()
    end
end

---------------------------------------------------------------------------
-- Kill list window
---------------------------------------------------------------------------

-- "just now", "12 min ago", "3 h ago", "2 days ago"
local function Ago(t)
    local seconds = time() - (t or time())
    if seconds < 120 then
        return "just now"
    elseif seconds < 3600 then
        return math.floor(seconds / 60) .. " min ago"
    elseif seconds < 86400 then
        return math.floor(seconds / 3600) .. " h ago"
    end
    return KZ.Plural(math.floor(seconds / 86400), "day") .. " ago"
end

local function GuildTooltip(row)
    GameTooltip:AddLine(row.name .. (row.me and " (you)" or ""), 1, 1, 1)
    GameTooltip:AddDoubleLine("Kills", row.total, 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Killing blows", row.kb, 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Assists", row.total - row.kb, 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("This week", row.week, 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Different players", row.victims, 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Addon version", row.version or "?", 0.8, 0.8, 0.8, 1, 1, 1)
    if not row.me then
        GameTooltip:AddDoubleLine("Last update", Ago(row.seen), 0.8, 0.8, 0.8, 1, 1, 1)
    end
end

local function RowTooltip(self)
    local item = self.item
    if not item then
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if item.guild then
        GuildTooltip(item.guild)
    elseif item.victim then
        local v = item.victim
        GameTooltip:AddLine(item.name, KZ.ClassColor(v.class))
        local who = Describe(v.level, v.race, v.class)
        if who then
            GameTooltip:AddLine(who, 0.8, 0.8, 0.8)
        end
        GameTooltip:AddDoubleLine("Kills", v.n, 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("Killing blows", v.kb or 0, 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("Assists", v.n - (v.kb or 0), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("First kill", LongDate(v.first), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("Last kill", LongDate(v.last), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("Last zone", v.zone or "?", 0.8, 0.8, 0.8, 1, 1, 1)
    else
        local e = item.entry
        GameTooltip:AddLine(e.name, KZ.ClassColor(e.class))
        local who = Describe(e.level, e.race, e.class)
        if who then
            GameTooltip:AddLine(who, 0.8, 0.8, 0.8)
        end
        GameTooltip:AddDoubleLine("How", e.kb and "Killing blow" or "Assist (honorable kill)", 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("When", LongDate(e.t), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("Where", (e.zone or "?") .. (e.bg and " (battleground)" or ""), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    GameTooltip:Show()
end

local function CreateRow(index)
    local row = CreateFrame("Button", nil, window)
    row:SetSize(360, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 20, -136 - (index - 1) * ROW_HEIGHT)
    if index % 2 == 0 then
        local stripe = row:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints()
        stripe:SetColorTexture(1, 1, 1, 0.04)
    end
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.10)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", 4, 0)
    row.name:SetWidth(150)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.count:SetPoint("LEFT", 158, 0)
    row.count:SetWidth(46)
    row.count:SetJustifyH("LEFT")

    row.info = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.info:SetPoint("LEFT", 206, 0)
    row.info:SetWidth(152)
    row.info:SetJustifyH("LEFT")
    row.info:SetWordWrap(false)

    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    return row
end

-- Fills `list` for the current tab. For the Guild tab, returns the guild's name
-- (nil when you are not in a guild).
local function BuildList()
    wipe(list)
    local db = KZ.char
    if view == "guild" then
        local board, guild = KZ.GuildBoard()
        for _, row in ipairs(board or {}) do
            list[#list + 1] = { guild = row }
        end
        return guild
    elseif view == "victims" then
        for name, victim in pairs(db.victims) do
            list[#list + 1] = { name = name, victim = victim }
        end
        table.sort(list, function(a, b)
            if a.victim.n ~= b.victim.n then
                return a.victim.n > b.victim.n
            end
            return (a.victim.last or 0) > (b.victim.last or 0)
        end)
    else
        for i = #db.log, 1, -1 do
            list[#list + 1] = { entry = db.log[i] }
        end
    end
end

local function Render()
    local db = KZ.char
    if not window or not db then
        return
    end
    window.summary:SetText(("Kills: |cffffffff%d|r   (killing blows %d, assists %d)\nToday: %d    This week: %d    Different players: %d"):format(
        db.total, db.killingBlows, db.total - db.killingBlows, db.day, db.week, KZ.CountVictims()))

    for name, tab in pairs(window.tabs) do
        if name == view then
            tab:LockHighlight()
        else
            tab:UnlockHighlight()
        end
    end
    window.head1:SetText(view == "guild" and "Guildmate" or "Player")
    window.head2:SetText(view == "recent" and "How" or "Kills")
    window.head3:SetText((view == "victims" and "Last kill") or (view == "recent" and "When and where")
        or "This week, last update")

    local guild = BuildList()
    local maxOffset = math.max(0, #list - ROWS)
    if offset > maxOffset then
        offset = maxOffset
    end
    for i = 1, ROWS do
        local row, item = rows[i], list[offset + i]
        row.item = item
        if item then
            if item.guild then
                local g = item.guild
                row.name:SetText(g.rank .. ". " .. g.name .. (g.me and " (you)" or ""))
                if g.me then
                    row.name:SetTextColor(0.4, 1, 0.4)
                else
                    row.name:SetTextColor(1, 1, 1)
                end
                row.count:SetText(g.total)
                row.info:SetText(("week %d, %s"):format(g.week, g.me and "now" or Ago(g.seen)))
            elseif item.victim then
                local v = item.victim
                row.name:SetText(item.name)
                row.name:SetTextColor(KZ.ClassColor(v.class))
                row.count:SetText(v.n)
                row.info:SetText(ShortDate(v.last) .. "  " .. (v.zone or ""))
            else
                local e = item.entry
                row.name:SetText(e.name)
                row.name:SetTextColor(KZ.ClassColor(e.class))
                row.count:SetText(e.kb and "KB" or "assist")
                row.info:SetText(ShortDate(e.t) .. "  " .. (e.zone or ""))
            end
            row:Show()
        else
            row:Hide()
        end
    end

    if view == "guild" and not guild then
        window.footer:SetText("You are not in a guild.")
    elseif view == "guild" and #list <= 1 then
        window.footer:SetText("No guildmates with Kirilicos Žudikai 1.2+ heard from yet.")
    elseif #list == 0 then
        window.footer:SetText("No kills yet.")
    else
        window.footer:SetText(("%d-%d of %d   (scroll with the mouse wheel)"):format(
            offset + 1, math.min(offset + ROWS, #list), #list))
    end
end

local function ShowView(name)
    view = name
    offset = 0
    if name == "guild" then
        KZ.RequestGuildStats()
    end
    Render()
end

local function CreateTab(label, x, name)
    local tab = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    tab:SetSize(112, 22)
    tab:SetPoint("TOPLEFT", x, -94)
    tab:SetText(label)
    tab:SetScript("OnClick", function()
        ShowView(name)
    end)
    window.tabs[name] = tab
    return tab
end

local function CreateHeader(x)
    local head = window:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    head:SetPoint("TOPLEFT", 24 + x, -122)
    return head
end

local function CreateWindow()
    window = CreateFrame("Frame", "KirilicosZudikaiWindow", UIParent, BACKDROP_TEMPLATE)
    window:SetSize(400, 450)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    -- The dialog background texture is see-through on Forever, so the inside
    -- is a plain dark fill, like the counter's.
    SetBackdrop(window, {
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    }, 0.06, 0.06, 0.06, 0.95)
    window:Hide()
    tinsert(UISpecialFrames, "KirilicosZudikaiWindow") -- Escape closes it

    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)

    local settings = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    settings:SetSize(76, 20)
    settings:SetPoint("TOPLEFT", 16, -16)
    settings:SetText("Settings")
    settings:SetScript("OnClick", function()
        window:Hide()
        KZ.OpenSettings()
    end)
    window.settingsButton = settings

    local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18)
    title:SetText(KZ.title)

    window.summary = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    window.summary:SetPoint("TOPLEFT", 24, -48)
    window.summary:SetWidth(352)
    window.summary:SetJustifyH("LEFT")
    window.summary:SetSpacing(4)

    window.tabs = {}
    window.victimsTab = CreateTab("Players", 22, "victims")
    window.recentTab = CreateTab("Recent kills", 140, "recent")
    window.guildTab = CreateTab("Guild", 258, "guild")

    window.head1 = CreateHeader(0)
    window.head2 = CreateHeader(158)
    window.head3 = CreateHeader(206)

    for i = 1, ROWS do
        rows[i] = CreateRow(i)
    end

    window.footer = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    window.footer:SetPoint("BOTTOM", 0, 22)

    window:EnableMouseWheel(true)
    window:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta * 3)
        Render()
    end)
end

function KZ.ToggleWindow()
    if not KZ.char then
        return
    end
    if not window then
        CreateWindow()
    end
    if window:IsShown() then
        window:Hide()
    else
        offset = 0
        KZ.RollPeriods()
        Render()
        window:Show()
    end
end

-- Opens the kill list on the Guild tab (/kz guild).
function KZ.ShowGuildTab()
    if not KZ.char then
        return
    end
    if not window then
        CreateWindow()
    end
    KZ.RollPeriods()
    ShowView("guild")
    window:Show()
end

---------------------------------------------------------------------------
-- Refresh and start-up
---------------------------------------------------------------------------

function KZ.Refresh()
    local db = KZ.char
    if not db then
        return
    end
    KZ.RollPeriods()
    if hud then
        hud.count:SetText(("%s  |cffaaaaaatoday %d|r"):format(KZ.Plural(db.total, "kill"), db.day))
    end
    if window and window:IsShown() then
        Render()
    end
end

function KZ.InitUI()
    if not KZ.char or hud then
        return
    end
    CreateHUD()
    RestorePoint(hud, "hudPoint", HUD_DEFAULT)
    KZ.ApplyHUD()
    KZ.Refresh()
end
