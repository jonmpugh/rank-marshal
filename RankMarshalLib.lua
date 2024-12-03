-- ╔═══════════╗
-- ║ Constants ║
-- ╚═══════════╝

local WASTED_HONOR = "This red section of the bar is wasted honor.\nConsider reaching the next milestone before the next reset"
local DEBUG_PRINTS = false

-- Update interval (sec) for next reset countdown frame updates
local UPDATE_INTERVAL = 1

-- ╔═══════════╗
-- ║ Variables ║
-- ╚═══════════╝

RankMarshal_SavedVars = {}
local currentRank = UnitPVPRank("player") - 4
local currentProgress = GetPVPRankProgress()
local milestones = {}
local persistent_next_rank = nil
local persistent_hk_reached = false
local update_exp = 0

local loading_complete = false
local debugTextColor = CreateColor(0, .45, .9)
local function DebugPrint(str)
    if DEBUG_PRINTS then
        print(debugTextColor:WrapTextInColorCode("RankMarshal: ") .. str)
    end
end

local rankUpTextColor = CreateColor(1.0, 0.82, 0)
local factionGroup, factionName = UnitFactionGroup("player");

-- ╔══════════════════════════╗
-- ║ Rank Milestone Functions ║
-- ╚══════════════════════════╝

---@class Milestone
---@field honor integer?
---@field rank number?
---@field rankText string?
local Milestone = { honor = nil, rank = nil, rankText = nil }

function Milestone:new(honorNeeded, rank, rankProgress)
    local o = {}
    setmetatable(o, self)
    self.__index = self

    o.honor = honorNeeded
    o.rank = rank + rankProgress
    o.rankText, _ = GetPVPRankInfo(o.rank + 4)

    return o
end

local function UpdateMilestones()
    DebugPrint("UpdateMilestones")

    local rank = UnitPVPRank("player") - 4
    local progress = GetPVPRankProgress()

    if RankMarshalDebugFrame:IsShown() then
        rank = tonumber(RankMarshalDebugFrameRankEditBox:GetText())
        progress = tonumber(RankMarshalDebugFramePercentEditBox:GetText()) * .01
    end

    if rank < 1 then
        rank = 1
    end

    local rank_options = Ranker:ChooseYourOwnAdventure(rank, 0, progress)

    -- Remove second milestone for decay prevention hop
    table.remove(rank_options, 2)
    milestones = {}
    for key = 1, #rank_options do
        local child = rank_options[key]
        milestones[#milestones + 1] = Milestone:new(child.honorNeed, child.rank, child.rankProgress)
    end

    -- Remove all milestones with duplicate rank (will happen if over SoD limit)
    local last_rank = nil

    for index, milestone in ipairs(milestones) do
        if milestone ~= nil then
            if milestone.rank == last_rank then
                table.remove(milestones, index)
            else
                last_rank = milestone.rank
            end
        end
    end
end

-- ╔═════════════════════╗
-- ║ UI Update Functions ║
-- ╚═════════════════════╝

local function UpdateChunk(statusBarChunk, milestoneFrame, minValue, maxValue, currentHonor, maxHonor, rankVal)
    local milestoneTick = _G[milestoneFrame:GetName() .. "Tick"]
    local milestoneTickNumber = _G[milestoneFrame:GetName() .. "TickNumber"]
    local milestoneTooltip = _G[milestoneFrame:GetName() .. "Tooltip"]
    local milestoneTooltipText1 = _G[milestoneFrame:GetName() .. "TooltipText1"]
    local milestoneTooltipText2 = _G[milestoneFrame:GetName() .. "TooltipText2"]

    if minValue == nil or maxValue == nil then
        statusBarChunk:Hide()
        milestoneFrame:Hide()
        return
    else
        statusBarChunk:Show()
        milestoneFrame:Show()
    end

    statusBarChunk:SetMinMaxValues(minValue, maxValue)
    statusBarChunk:SetWidth((maxValue - minValue) * (RankMarshalProgressBar:GetWidth() - 10) / maxHonor)
    if currentHonor > maxValue then
        statusBarChunk:SetValue(maxValue)
        statusBarChunk:SetStatusBarColor(0, .45, .9)
        statusBarChunk:SetScript("OnEnter", nil)
        milestoneTickNumber:Hide()
    else
        statusBarChunk:SetValue(currentHonor)
        statusBarChunk:SetStatusBarColor(1, 0, 0)
        if currentHonor > minValue then
            -- Show remaining honor number to the left of tick
            milestoneTickNumber:Show()
            milestoneTickNumber:SetText(currentHonor - maxValue)

            statusBarChunk:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                GameTooltip:AddLine(WASTED_HONOR)
                GameTooltip:Show()
            end)
        else
            milestoneTickNumber:Hide()
            statusBarChunk:SetScript("OnEnter", nil)
        end
    end

    milestoneTick:SetPoint("CENTER", statusBarChunk, "RIGHT", 0, 0)

    milestoneTick:SetScript("OnEnter", function(self)
        milestoneTooltipText1:SetText(maxValue .. " Honor")
        milestoneTooltipText2:SetText("Reaching this milestone will grant:" .. "\n"
            .. "Rank " .. floor(tonumber(rankVal)) .. " and " .. string.format("%.2f", tonumber(rankVal) % 1 * 100) .. "%")
        milestoneTooltip:Show()
    end)
end

---- Update chunks
---@param currentHonor integer
---@param milestone1 Milestone
---@param milestone2 Milestone
---@param milestone3 Milestone
---@param milestone4 Milestone
local function UpdateChunks(currentHonor, milestone1, milestone2, milestone3, milestone4)
    DebugPrint("UpdateChunks")

    local maxHonor = 1
    if milestone4 ~= nil then
        maxHonor = milestone4.honor
    elseif milestone3 ~= nil then
        maxHonor = milestone3.honor
    elseif milestone2 ~= nil then
        maxHonor = milestone2.honor
    elseif milestone1 ~= nil then
        maxHonor = milestone1.honor
    else
        return
    end

    if milestone1 ~= nil and milestone1.honor ~= 0 then
        UpdateChunk(RankMarshalProgressBarChunk1, Milestone1, 0, milestone1.honor, currentHonor, maxHonor, milestone1.rank)
    else
        -- Setting the width to 0 causes later chunks to not render
        RankMarshalProgressBarChunk1:SetWidth(.01)
        RankMarshalProgressBarChunk1:Hide()
        Milestone1:Hide()
    end

    if milestone1 ~= nil and milestone2 ~= nil then
        UpdateChunk(RankMarshalProgressBarChunk2, Milestone2, milestone1.honor, milestone2.honor, currentHonor, maxHonor, milestone2.rank)
    else
        RankMarshalProgressBarChunk2:SetWidth(0)
    end

    if milestone2 ~= nil and milestone3 ~= nil then
        UpdateChunk(RankMarshalProgressBarChunk3, Milestone3, milestone2.honor, milestone3.honor, currentHonor, maxHonor, milestone3.rank)
    else
        RankMarshalProgressBarChunk3:SetWidth(0)
    end

    if milestone3 ~= nil and milestone4 ~= nil then
        UpdateChunk(RankMarshalProgressBarChunk4, Milestone4, milestone3.honor, milestone4.honor, currentHonor, maxHonor, milestone4.rank)
    else
        RankMarshalProgressBarChunk4:SetWidth(0)
    end

    if currentHonor > maxHonor then
        RankMarshalProgressBarChunk1:SetStatusBarColor(0, 1, 0)
        RankMarshalProgressBarChunk2:SetStatusBarColor(0, 1, 0)
        RankMarshalProgressBarChunk3:SetStatusBarColor(0, 1, 0)
        RankMarshalProgressBarChunk4:SetStatusBarColor(0, 1, 0)
    end
end

local function UpdateProgressBar()
    DebugPrint("UpdateProgressBar")
    local _, honor = GetPVPThisWeekStats()

    if RankMarshalDebugFrame:IsShown() then
        honor = tonumber(RankMarshalDebugFrameHonorEditBox:GetText())
    end

    UpdateChunks(honor, milestones[1], milestones[2], milestones[3], milestones[4])
end

local function UpdateCurrentRank()
    DebugPrint("UpdateCurrentRank")
    currentRank = UnitPVPRank("player") - 4
    local rank = currentRank
    currentProgress = GetPVPRankProgress()
    local progress = currentProgress

    if RankMarshalDebugFrame:IsShown() then
        rank = tonumber(RankMarshalDebugFrameRankEditBox:GetText())
        progress = tonumber(RankMarshalDebugFramePercentEditBox:GetText()) * .01
    end

    local rankName, rankNum = GetPVPRankInfo(rank + 4)

    if rankName == nil then
        rankName = "Unranked"
        if (factionGroup == "Alliance") then
            CurrentRankPaneRankIcon:SetTexture("Interface\\PVPFrame\\PVP-Currency-Alliance")
        else
            CurrentRankPaneRankIcon:SetTexture("Interface\\PVPFrame\\PVP-Currency-Horde")
        end
    else
        CurrentRankPaneRankIcon:SetTexture(format("%s%02d", "Interface\\PvPRankBadges\\PvPRank", floor(rank)));
    end

    CurrentRankPaneRankText:SetText(rankName)
    CurrentRankPaneRankTitleText:SetText("Current Rank:")
    CurrentRankPaneRankSubText:SetText("Rank " ..
        rankNum .. " and " .. tonumber(string.format("%.2f", progress * 100)) .. "%")
end

local function UpdateNextRank(force)
    DebugPrint("UpdateNextRank")
    local rank = currentRank
    local progress = currentProgress
    local hks, honor = GetPVPThisWeekStats()

    if RankMarshalDebugFrame:IsShown() then
        rank = tonumber(RankMarshalDebugFrameRankEditBox:GetText())
        progress = tonumber(RankMarshalDebugFramePercentEditBox:GetText()) * .01
        honor = tonumber(RankMarshalDebugFrameHonorEditBox:GetText())
        hks = tonumber(RankMarshalDebugFrameHKsEditBox:GetText())
    end

    local nextRank = rank + progress
    for i = #milestones, 1, -1 do
        if honor > milestones[i].honor then
            nextRank = milestones[i].rank
            break
        end
    end

    -- Only update the Next Rank pane if the rank has changed or the player doesn't have 15 HKs yet
    if force or persistent_next_rank ~= nextRank or not persistent_hk_reached then
        if rank == 14 or (rank >= rankerObjective) then
            NextRankPaneRankTitleText:Hide()
            NextRankPaneRankText:SetText(nil)
            NextRankPaneRankSubText:SetText(nil)
            NextRankPaneRankIcon:SetTexture(nil)
            NextRankPaneHKWarningText:Hide()
            NextRankPaneMissionComplete:Show()
            RankMarshalProgressBar:Hide()
            -- Show a warning if the player would rank up if they had 15 HKs
        elseif (rank + progress) ~= nextRank and hks < 15 then
            NextRankPaneRankText:SetText(nil)
            NextRankPaneRankSubText:SetText(nil)
            NextRankPaneRankIcon:SetTexture(nil)
            NextRankPaneHKWarningText:Show()
        else
            if NextRankPaneMissionComplete:IsShown() then
                NextRankPaneRankTitleText:Show()
                NextRankPaneMissionComplete:Hide()
            end

            if not RankMarshalProgressBar:IsShown() then
                RankMarshalProgressBar:Show()
            end

            local rankName, rankNum = GetPVPRankInfo(nextRank + 4)
            if rankName == nil then
                rankName = "Unranked"
                if (factionGroup == "Alliance") then
                    NextRankPaneRankIcon:SetTexture("Interface\\PVPFrame\\PVP-Currency-Alliance")
                else
                    NextRankPaneRankIcon:SetTexture("Interface\\PVPFrame\\PVP-Currency-Horde")
                end
            else
                NextRankPaneRankIcon:SetTexture(format("%s%02d", "Interface\\PvPRankBadges\\PvPRank", floor(nextRank)));
            end

            NextRankPaneRankText:SetText(rankName)
            NextRankPaneHKWarningText:Hide()
            NextRankPaneRankSubText:SetText("Rank " ..
                rankNum .. " and " .. tonumber(string.format("%.2f", (nextRank % 1) * 100)) .. "%")

            persistent_hk_reached = true
            if persistent_next_rank ~= nil and persistent_next_rank ~= nextRank then
                -- Print message on rank up if enabled
                if Settings.RANK_MARSHAL_RANK_MSG_ENABLED:GetValue() then
                    print(rankUpTextColor:WrapTextInColorCode(
                        "Congratulations " .. rankName .. "! After the reset you will be rank " ..
                        rankNum .. " and " .. tonumber(string.format("%.2f", (nextRank % 1) * 100)) .. "%")
                    )
                end
                -- Play sound on rank up if enabled
                if Settings.RANK_MARSHAL_RANK_SOUND_ENABLED:GetValue() then
                    PlaySound(Settings.RANK_MARSHAL_RANK_SOUND_OPTION:GetValue(), "Master")
                end
            end
            persistent_next_rank = nextRank
        end
    end
end

local function UpdateNextReset()
    DebugPrint("UpdateNextReset")
    local nextReset = C_DateAndTime.GetSecondsUntilWeeklyReset()

    local d = {
        days = floor(nextReset / (24 * 60 * 60)),
        hours = floor(nextReset / (60 * 60)) % 24,
        mins = floor(nextReset / 60) % 60,
        secs = nextReset % 60
    }
    local dayStr = d["days"] .. " day" .. (d["days"] == 1 and "" or "s")
    local hourStr = d["hours"] .. " hour" .. (d["hours"] == 1 and "" or "s")
    local minStr = d["mins"] .. " min" .. (d["mins"] == 1 and "" or "s")
    local secStr = d["secs"] .. " sec" .. (d["secs"] == 1 and "" or "s")

    NextResetCountdownText:SetText(dayStr .. ", " .. hourStr .. ", " .. minStr .. ", " .. secStr)
end

local function UpdateStats(updateAll)
    DebugPrint("UpdateStats")

    -- Today's stats
    local todayHKs, todayDKs = GetPVPSessionStats()
    --FullStatsPaneHonorTodayValue:SetText()
    FullStatsPaneHKTodayValue:SetText(todayHKs)
    FullStatsPaneDKTodayValue:SetText(todayDKs)

    -- Yesterday's stats
    if (updateAll) then
        local yesterdayHKs, yesterdayDKs, yesterdayHonor = GetPVPYesterdayStats()
        --FullStatsPaneHonorYesterdayValue:SetText(yesterdayHonor)
        FullStatsPaneHKYesterdayValue:SetText(yesterdayHKs)
        FullStatsPaneDKYesterdayValue:SetText(yesterdayDKs)
    end

    -- This week's stats
    local thisWeekHKs, thisWeekHonor = GetPVPThisWeekStats()
    FullStatsPaneHonorThisweekValue:SetText(thisWeekHonor)
    FullStatsPaneHKThisweekValue:SetText(thisWeekHKs)
    --FullStatsPaneDKThisweekValue:SetText()

    -- Last week's stats
    if (updateAll) then
        local lastWeekHKs, lastWeekDKs, lastWeekHonor = GetPVPLastWeekStats()
        FullStatsPaneHonorLastweekValue:SetText(lastWeekHonor)
        FullStatsPaneHKLastweekValue:SetText(lastWeekHKs)
        FullStatsPaneDKLastweekValue:SetText(lastWeekDKs)
    end

    -- Lifetime stats
    local lifetimeHKs, lifetimeDKs = GetPVPLifetimeStats()
    --FullStatsPaneHonorLifetimeValue:SetText()
    FullStatsPaneHKLifetimeValue:SetText(lifetimeHKs)
    FullStatsPaneDKLifetimeValue:SetText(lifetimeDKs)

    local yellow = { FullStatsPaneHonorYesterdayValue, FullStatsPaneHonorThisweekValue, FullStatsPaneHonorLastweekValue, FullStatsPaneHKTodayValue,
        FullStatsPaneHKYesterdayValue, FullStatsPaneHKThisweekValue, FullStatsPaneHKLastweekValue, FullStatsPaneHKLifetimeValue }

    local red = { FullStatsPaneDKTodayValue, FullStatsPaneDKYesterdayValue, FullStatsPaneDKLastweekValue, FullStatsPaneDKLifetimeValue }

    -- Set honor and HK values to yellow if 0, otherwise green
    for i, v in ipairs(yellow) do
        if v:GetText() == "0" then
            v:SetTextColor(1.0, 0.82, 0)
        else
            v:SetTextColor(0.1, 1.0, 0.1)
        end
    end

    -- Set DK values to green if 0, otherwise red
    for i, v in ipairs(red) do
        if v:GetText() == "0" then
            v:SetTextColor(0.1, 1.0, 0.1)
        else
            v:SetTextColor(1.0, 0.1, 0.1)
        end
    end
end

function RankMarshal_DebugUpdate()
    UpdateMilestones()
    UpdateProgressBar()
    UpdateCurrentRank()
    UpdateNextRank()
end

local function HookRankerObjectiveSetValue()
    DebugPrint("HookRankerObjectiveSetValue")
    local old_RankerObjective_SetValue = RankerObjective.SetValue;
    function RankerObjective:SetValue(...)
        local result = old_RankerObjective_SetValue(self, ...)
        UpdateMilestones()
        UpdateProgressBar()
        --UpdateCurrentRank()
        UpdateNextRank(true)
        return result
    end
end

-- ╔════════════════════════╗
-- ║ Frame Script Functions ║
-- ╚════════════════════════╝

function RankMarshal_HideHonorFrame()
    DebugPrint("RankMarshal_HideHonorFrame")
    local counter = 0
    -- Hide all textures on the HonorFrame except the first 4, these are the background
    for _, child in ipairs({ HonorFrame:GetRegions() }) do
        if child:GetObjectType() == "Texture" then
            if counter >= 4 then
                child:Hide()
            end
            counter = counter + 1
        end
    end

    HonorFrameCurrentHK:Hide()
    HonorFrameCurrentDK:Hide()
    HonorFrameYesterdayHK:Hide()
    HonorFrameYesterdayContribution:Hide()
    HonorFrameThisWeekHK:Hide()
    HonorFrameThisWeekContribution:Hide()
    HonorFrameLastWeekHK:Hide()
    HonorFrameLastWeekContribution:Hide()
    HonorFrameLifeTimeHK:Hide()
    HonorFrameLifeTimeDK:Hide()
    HonorFrameLifeTimeRank:Hide()
    HonorFrameRankButton:Hide()

    HonorFrameCurrentPVPTitle:Hide()
    HonorFrameCurrentPVPRank:Hide()
    HonorFrameCurrentSessionTitle:Hide()
    HonorFrameYesterdayTitle:Hide()
    HonorFrameThisWeekTitle:Hide()
    HonorFrameLastWeekTitle:Hide()
    HonorFrameLifeTimeTitle:Hide()
    HonorFramePvPIcon:Hide()
    -- HonorFrame calls Show() this so set size to make it invisible
    HonorFramePvPIcon:SetSize(.01, .01)
end

function RankMarshal_RankMarshalFrameOnEvent(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "RankMarshal" then
            if RankMsgEnabled == nil then
                RankMsgEnabled = Settings.RANK_MARSHAL_RANK_MSG_ENABLED:GetDefaultValue()
            end
            if RankSoundEnabled == nil then
                RankSoundEnabled = Settings.RANK_MARSHAL_RANK_SOUND_ENABLED:GetDefaultValue()
            end
            if RankSoundOption == nil then
                RankSoundOption = Settings.RANK_MARSHAL_RANK_SOUND_OPTION:GetDefaultValue()
            end
            if DebugEnabled == nil then
                DebugEnabled = Settings.RANK_MARSHAL_DEBUGGING:GetDefaultValue()
            end
            Settings.RANK_MARSHAL_RANK_MSG_ENABLED:SetValue(RankMsgEnabled)
            Settings.RANK_MARSHAL_RANK_SOUND_ENABLED:SetValue(RankSoundEnabled)
            Settings.RANK_MARSHAL_RANK_SOUND_OPTION:SetValue(RankSoundOption)
            Settings.RANK_MARSHAL_DEBUGGING:SetValue(DebugEnabled)
            loading_complete = true
        end
    elseif event == "PLAYER_LOGOUT" then
        -- Save the value on logout
        RankMsgEnabled = Settings.RANK_MARSHAL_RANK_MSG_ENABLED:GetValue()
        RankSoundEnabled = Settings.RANK_MARSHAL_RANK_SOUND_ENABLED:GetValue()
        RankSoundOption = Settings.RANK_MARSHAL_RANK_SOUND_OPTION:GetValue()
        DebugEnabled = Settings.RANK_MARSHAL_DEBUGGING:GetValue()
    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateMilestones()
        UpdateProgressBar()
        UpdateCurrentRank()
        UpdateNextRank()
        UpdateStats(true)

        if RankerObjective ~= nil and RankerObjective.SetValue ~= nil then
            HookRankerObjectiveSetValue()
        else
            C_Timer.After(5, HookRankerObjectiveSetValue)
        end
    elseif event == "PLAYER_PVP_KILLS_CHANGED" then
        if (GetTime() > update_exp) then
            UpdateProgressBar()
            UpdateStats()
            UpdateNextRank()
            update_exp = GetTime() + .01
        end
    elseif event == "PLAYER_PVP_RANK_CHANGED" then
        UpdateMilestones()
        UpdateProgressBar()
        UpdateCurrentRank()
        UpdateNextRank()
        UpdateStats(true)
    end
end

function RankMarshal_RankMarshalFrameOnShow(self, event, arg1)
    UpdateNextReset()
end

function RankMarshal_NextResetPaneOnUpdate(self, elapsed)
    self.TimeSinceLastUpdate = self.TimeSinceLastUpdate + elapsed
    if self.TimeSinceLastUpdate > UPDATE_INTERVAL then
        UpdateNextReset()
        self.TimeSinceLastUpdate = 0
    end
end

StaticPopupDialogs["RankMarshalExportDialog"] = {
    text = "Copy the link below to share your progress:",
    button1 = "Close",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3, -- avoid some UI taint, see http://www.wowace.com/announcements/how-to-avoid-some-ui-taint/
    OnLoad = function(self)
        self.editBox:SetAutoFocus(true);
    end,
    hasEditBox = true
}

function RankMarshal_OpenExportDialog()
    local dialog   = StaticPopup_Show("RankMarshalExportDialog")
    local rank     = UnitPVPRank("Player") - 4
    local progress = GetPVPRankProgress()
    local _, honor = GetPVPThisWeekStats()
    local level    = UnitLevel("Player")

    dialog.editBox:SetText("https://soffe.github.io/ClassicEraHonorCalculator/calculator/" ..
        tostring(rank) .. "/" .. tostring(progress) .. "/" .. tostring(honor) .. "/" .. tostring(level) .. "")
    dialog.editBox:HighlightText()
end

-- ╔════════════════════════╗
-- ║ Settings Configuration ║
-- ╚════════════════════════╝

function RankMarshal_ConfigureSettings()
    -- Configure the settings categories
    local category, layout = Settings.RegisterVerticalLayoutCategory("Rank Marshal")
    Settings.RANK_MARSHAL_CATEGORY = category
    local settingsCategory, settingsLayout = Settings.RegisterVerticalLayoutSubcategory(category, "Settings")
    Settings.RANK_MARSHAL_SETTINGS_CATEGORY = settingsCategory

    -- Add the help frames
    do
        local data = { settings = nil };
        local initializer = Settings.CreatePanelInitializer("RankMarshalHelpOverviewTemplate", data);
        layout:AddInitializer(initializer);
        initializer = Settings.CreatePanelInitializer("RankMarshalHelpProgressBarTemplate", data);
        layout:AddInitializer(initializer);
        initializer = Settings.CreatePanelInitializer("RankMarshalHelpRankPanesTemplate", data);
        layout:AddInitializer(initializer);
        initializer = Settings.CreatePanelInitializer("RankMarshalHelpStatsPaneTemplate", data);
        layout:AddInitializer(initializer);
    end

    -- Add the rank message setting
    do
        local name = "Print message on rank up"
        local variable = "RankMarshal_rankmessage"
        local variableKey = "rankmessage"
        local variableTbl = RankMarshal_SavedVars
        local defaultValue = true

        Settings.RANK_MARSHAL_RANK_MSG_ENABLED = Settings.RegisterAddOnSetting(category, variable, variableKey, variableTbl, type(defaultValue), name,
            defaultValue)
        Settings.CreateCheckbox(settingsCategory, Settings.RANK_MARSHAL_RANK_MSG_ENABLED,
            "Prints a message to the chat window when you reach a new rank milestone")
    end

    -- Add the rank up sound setting
    do
        local name = "Play sound"
        local variable = "RankMarshal_playsound"
        local variableKey = "playsound"
        local variableTbl = RankMarshal_SavedVars
        local defaultValue = false
        Settings.RANK_MARSHAL_RANK_SOUND_ENABLED = Settings.RegisterAddOnSetting(settingsCategory, variable, variableKey, variableTbl, type(defaultValue), name,
            defaultValue)

        local name = "Sound to play"
        local variable = "RankMarshal_soundtoplay"
        local variableKey = "soundtoplay"
        local variableTbl = RankMarshal_SavedVars
        local defaultValue = SOUNDKIT.HARDCORE_DUEL
        Settings.RANK_MARSHAL_RANK_SOUND_OPTION = Settings.RegisterAddOnSetting(settingsCategory, variable, variableKey, variableTbl, type(defaultValue), name,
            defaultValue)

        local function GetOptionData(options)
            local container = Settings.CreateControlTextContainer();
            container:Add(SOUNDKIT.HARDCORE_DUEL, "Mak'gora", "The sound that plays when a hardcore duel is initiated");
            container:Add(SOUNDKIT.READY_CHECK, "Ready Check", "The sound that plays when a ready check is started");
            container:Add(SOUNDKIT.PVP_THROUGH_QUEUE, "PvP Queue Ready", "The sound that plays when a battleground queue pops");
            container:Add(SOUNDKIT.MURLOC_AGGRO, "Murloc", "RWLRWLRWLRWL");
            return container:GetData()
        end

        local function SoundFileSettingChanged(setting, value)
            if loading_complete and Settings.RANK_MARSHAL_RANK_SOUND_ENABLED:GetValue() then
                PlaySound(value, "Master")
            end
        end

        local function SoundEnabledSettingChanged(setting, value)
            if loading_complete and value then
                PlaySound(RankMarshal_SavedVars["soundtoplay"], "Master")
            end
        end

        Settings.RANK_MARSHAL_RANK_SOUND_ENABLED:SetValueChangedCallback(SoundEnabledSettingChanged)
        Settings.RANK_MARSHAL_RANK_SOUND_OPTION:SetValueChangedCallback(SoundFileSettingChanged)

        local initializer = CreateSettingsCheckboxDropdownInitializer(
            Settings.RANK_MARSHAL_RANK_SOUND_ENABLED, "Play sound on rank up", "Plays a sound when you reach a new rank milestone",
            Settings.RANK_MARSHAL_RANK_SOUND_OPTION, GetOptionData, "Sound to play on rank up", nil);

        settingsLayout:AddInitializer(initializer);
    end

    -- Add the debug setting
    do
        local function DebugSettingChanged(setting, value)
            if value then
                RankMarshalDebugFrame:Show()
            elseif loading_complete then
                RankMarshalDebugFrame:Hide()
                UpdateMilestones()
                UpdateProgressBar()
                UpdateCurrentRank()
                UpdateNextRank()
            end
        end

        local name = "Enable Debugging"
        local variable = "RankMarshal_debug"
        local variableKey = "debug"
        local variableTbl = RankMarshal_SavedVars
        local defaultValue = false
        Settings.RANK_MARSHAL_DEBUGGING = Settings.RegisterAddOnSetting(settingsCategory, variable, variableKey, variableTbl, type(defaultValue), name,
            defaultValue)
        Settings.RANK_MARSHAL_DEBUGGING:SetValueChangedCallback(DebugSettingChanged)
        Settings.CreateCheckbox(settingsCategory, Settings.RANK_MARSHAL_DEBUGGING, "Enables debugging, intended for developers only")
    end

    Settings.RegisterAddOnCategory(category)
end
