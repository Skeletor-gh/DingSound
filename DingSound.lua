local ADDON_NAME = ...

local function GetAddonMetadataCompat(addonName, field)
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata(addonName, field)
    end

    if GetAddOnMetadata then
        return GetAddOnMetadata(addonName, field)
    end

    return nil
end

local ADDON_VERSION = GetAddonMetadataCompat(ADDON_NAME, "Version") or "dev"

local DEFAULT_DB = {
    levelUp = {
        enabled = true,
        selectedSound = nil,
        muteDefault = true,
        duckoutDuration = 1.5,
    },
    achievement = {
        enabled = true,
        selectedSound = nil,
        muteDefault = true,
        duckoutDuration = 1.5,
    },
}

-- Minimum time (seconds) between level-up / achievement sound plays.
-- This prevents overlapping sounds when multiple events fire quickly.
local LEVEL_UP_SOUND_BUFFER_SECONDS = 2.0
local ACHIEVEMENT_SOUND_BUFFER_SECONDS = 2.0
local DUCKOUT_REDUCTION_PERCENTAGE = 0.30
local DUCKOUT_MINIMUM_VOLUME = 0.05
local nextLevelUpPlayableTime = 0
local nextAchievementPlayableTime = 0
local isPetBattleMuteOverrideActive = false
local activeVolumeRestoreTimer = nil
local duckedVolumeSnapshot = nil
local isPlaySoundWrapped = false
local originalPlaySound = nil

local DUCKED_SOUND_CVARS = {
    "Sound_AmbienceVolume",
    "Sound_DialogVolume",
    "Sound_MusicVolume",
    "Sound_SFXVolume",
}

-- Common Blizzard level-up sounds. Muting these suppresses the default level-up ding
-- while DingSound's custom audio plays.
local DEFAULT_LEVEL_UP_SOUND_PATHS = {
    569593 -- Sound\\Interface\\LevelUp2.ogg,
}

-- Blizzard's achievement toast uses SOUNDKIT entries on most clients.
-- We suppress those via a PlaySound wrapper (for broad compatibility), and
-- we also keep a file-ID mute list for clients where the sound is file-driven.
local DEFAULT_ACHIEVEMENT_SOUND_PATHS = {
    543587,
	569143
}

local DEFAULT_ACHIEVEMENT_SOUNDKIT_KEYS = {
    "UI_ACHIEVEMENT_TOAST",
    "UI_ACHIEVEMENT_MENU_OPEN",
}

local achievementSoundKitIdSet = {}

local function ClampVolume(value)
    if value < 0 then
        return 0
    end

    if value > 1 then
        return 1
    end

    return value
end

local function ClearVolumeRestoreTimer()
    if activeVolumeRestoreTimer and activeVolumeRestoreTimer.Cancel then
        activeVolumeRestoreTimer:Cancel()
    end

    activeVolumeRestoreTimer = nil
end

local function RestoreDuckedVolumes()
    if not duckedVolumeSnapshot then
        return
    end

    for cvarName, originalValue in pairs(duckedVolumeSnapshot) do
        SetCVar(cvarName, tostring(originalValue))
    end

    duckedVolumeSnapshot = nil
    ClearVolumeRestoreTimer()
end

local function DuckNonMasterVolumes(percentage)
    local multiplier = 1 - (percentage or 0)
    duckedVolumeSnapshot = {}

    for _, cvarName in ipairs(DUCKED_SOUND_CVARS) do
        local currentValue = tonumber(GetCVar(cvarName))
        if currentValue then
            duckedVolumeSnapshot[cvarName] = currentValue

            local reducedValue = ClampVolume(currentValue * multiplier)
            if reducedValue <= 0 then
                reducedValue = DUCKOUT_MINIMUM_VOLUME
            end
            SetCVar(cvarName, tostring(reducedValue))
        end
    end

    if not next(duckedVolumeSnapshot) then
        duckedVolumeSnapshot = nil
    end
end

local function ScheduleVolumeRestore(delaySeconds)
    ClearVolumeRestoreTimer()

    activeVolumeRestoreTimer = C_Timer.NewTimer(delaySeconds, function()
        RestoreDuckedVolumes()
    end)
end

local function NormalizePath(fileName)
    if not fileName or fileName == "" then
        return nil
    end

    if fileName:find("\\") or fileName:find("/") then
        return fileName
    end

    return string.format("Interface\\AddOns\\%s\\Sounds\\%s", ADDON_NAME, fileName)
end

local function BuildSoundOptions()
    local options = {}

    if type(DingSoundSoundList) ~= "table" then
        return options
    end

    for _, fileName in ipairs(DingSoundSoundList) do
        local path = NormalizePath(fileName)
        if path then
            options[#options + 1] = {
                text = fileName,
                value = path,
            }
        end
    end

    table.sort(options, function(a, b)
        return a.text:lower() < b.text:lower()
    end)

    return options
end

local function SetDefaultLevelUpMuted(shouldMute)
    if shouldMute == nil then
        return
    end

    for _, soundPath in ipairs(DEFAULT_LEVEL_UP_SOUND_PATHS) do
        if shouldMute then
            MuteSoundFile(soundPath)
        else
            UnmuteSoundFile(soundPath)
        end
    end
end

local function SetDefaultAchievementMuted(shouldMute)
    if shouldMute == nil then
        return
    end

    for _, soundPath in ipairs(DEFAULT_ACHIEVEMENT_SOUND_PATHS) do
        if shouldMute then
            MuteSoundFile(soundPath)
        else
            UnmuteSoundFile(soundPath)
        end
    end
end

local function InitializeAchievementSoundKitIds()
    wipe(achievementSoundKitIdSet)

    if type(SOUNDKIT) ~= "table" then
        return
    end

    for _, soundKitKey in ipairs(DEFAULT_ACHIEVEMENT_SOUNDKIT_KEYS) do
        local soundKitId = SOUNDKIT[soundKitKey]
        if type(soundKitId) == "number" then
            achievementSoundKitIdSet[soundKitId] = true
        end
    end
end

local function InstallPlaySoundWrapper()
    if isPlaySoundWrapped or type(PlaySound) ~= "function" then
        return
    end

    originalPlaySound = PlaySound
    PlaySound = function(soundKitID, channel, forceNoDuplicates, runFinishCallback)
        if DingSoundDB
            and DingSoundDB.achievement
            and DingSoundDB.achievement.muteDefault
            and type(soundKitID) == "number"
            and achievementSoundKitIdSet[soundKitID]
        then
            if type(runFinishCallback) == "function" then
                runFinishCallback()
            end
            return true
        end

        return originalPlaySound(soundKitID, channel, forceNoDuplicates, runFinishCallback)
    end

    isPlaySoundWrapped = true
end

local function ApplyDefaultLevelUpMuteSetting()
    local shouldMute = DingSoundDB and DingSoundDB.levelUp and DingSoundDB.levelUp.muteDefault
    if isPetBattleMuteOverrideActive then
        shouldMute = false
    end

    SetDefaultLevelUpMuted(shouldMute)
end

local function ApplyDefaultAchievementMuteSetting()
    local shouldMute = DingSoundDB and DingSoundDB.achievement and DingSoundDB.achievement.muteDefault
    SetDefaultAchievementMuted(shouldMute)
end

local function SetPetBattleMuteOverride(active)
    if not DingSoundDB or not DingSoundDB.levelUp then
        return
    end

    if active and DingSoundDB.levelUp.muteDefault then
        isPetBattleMuteOverrideActive = true
        ApplyDefaultLevelUpMuteSetting()
    elseif not active then
        isPetBattleMuteOverrideActive = false
        ApplyDefaultLevelUpMuteSetting()
    end
end

local function MigrateLegacySettings()
    -- Preserve existing user settings from earlier addon versions.
    if DingSoundDB.enabled ~= nil and DingSoundDB.levelUp == nil then
        DingSoundDB.levelUp = {
            enabled = DingSoundDB.enabled,
            selectedSound = DingSoundDB.selectedSound,
            muteDefault = DingSoundDB.muteDefaultLevelUp,
            duckoutDuration = DingSoundDB.duckoutDuration,
        }
    end

    -- Remove legacy top-level keys once migration has happened.
    DingSoundDB.enabled = nil
    DingSoundDB.selectedSound = nil
    DingSoundDB.muteDefaultLevelUp = nil
    DingSoundDB.duckoutDuration = nil
end

local function EnsureDefaults()
    DingSoundDB = DingSoundDB or {}

    MigrateLegacySettings()

    DingSoundDB.levelUp = DingSoundDB.levelUp or {}
    DingSoundDB.achievement = DingSoundDB.achievement or {}

    if DingSoundDB.levelUp.enabled == nil then
        DingSoundDB.levelUp.enabled = DEFAULT_DB.levelUp.enabled
    end

    if DingSoundDB.levelUp.selectedSound == nil then
        DingSoundDB.levelUp.selectedSound = DEFAULT_DB.levelUp.selectedSound
    end

    if DingSoundDB.levelUp.muteDefault == nil then
        DingSoundDB.levelUp.muteDefault = DEFAULT_DB.levelUp.muteDefault
    end

    if DingSoundDB.levelUp.duckoutDuration == nil then
        DingSoundDB.levelUp.duckoutDuration = DEFAULT_DB.levelUp.duckoutDuration
    end

    if DingSoundDB.achievement.enabled == nil then
        DingSoundDB.achievement.enabled = DEFAULT_DB.achievement.enabled
    end

    if DingSoundDB.achievement.selectedSound == nil then
        DingSoundDB.achievement.selectedSound = DEFAULT_DB.achievement.selectedSound
    end

    if DingSoundDB.achievement.muteDefault == nil then
        DingSoundDB.achievement.muteDefault = DEFAULT_DB.achievement.muteDefault
    end

    if DingSoundDB.achievement.duckoutDuration == nil then
        DingSoundDB.achievement.duckoutDuration = DEFAULT_DB.achievement.duckoutDuration
    end

    ApplyDefaultLevelUpMuteSetting()
    ApplyDefaultAchievementMuteSetting()
end

local function GetCurrentSelection(options, selectedValue)
    local current = selectedValue
    if not current then
        return nil
    end

    for _, option in ipairs(options) do
        if option.value == current then
            return current
        end
    end

    return nil
end

local function PlayLevelUpSound()
    if not DingSoundDB or not DingSoundDB.levelUp or not DingSoundDB.levelUp.enabled then
        return
    end

    local path = DingSoundDB.levelUp.selectedSound
    if not path then
        return
    end

    local now = GetTime()
    if now < nextLevelUpPlayableTime then
        return
    end

    local duckoutDuration = tonumber(DingSoundDB.levelUp.duckoutDuration) or 0

    if duckedVolumeSnapshot then
        RestoreDuckedVolumes()
    end

    if duckoutDuration > 0 then
        DuckNonMasterVolumes(DUCKOUT_REDUCTION_PERCENTAGE)
    end

    local didPlay = PlaySoundFile(path, "Master")
    if didPlay then
        nextLevelUpPlayableTime = now + LEVEL_UP_SOUND_BUFFER_SECONDS
        if duckoutDuration > 0 then
            ScheduleVolumeRestore(duckoutDuration)
        end
    else
        RestoreDuckedVolumes()
    end
end

local function PlayAchievementSound()
    if not DingSoundDB or not DingSoundDB.achievement or not DingSoundDB.achievement.enabled then
        return
    end

    local path = DingSoundDB.achievement.selectedSound
    if not path then
        return
    end

    local now = GetTime()
    if now < nextAchievementPlayableTime then
        return
    end

    local duckoutDuration = tonumber(DingSoundDB.achievement.duckoutDuration) or 0

    if duckedVolumeSnapshot then
        RestoreDuckedVolumes()
    end

    if duckoutDuration > 0 then
        DuckNonMasterVolumes(DUCKOUT_REDUCTION_PERCENTAGE)
    end

    local didPlay = PlaySoundFile(path, "Master")
    if didPlay then
        nextAchievementPlayableTime = now + ACHIEVEMENT_SOUND_BUFFER_SECONDS
        if duckoutDuration > 0 then
            ScheduleVolumeRestore(duckoutDuration)
        end
    else
        RestoreDuckedVolumes()
    end
end

local function CreateSettingsPanel()
    local panel = CreateFrame("Frame", nil, UIParent)
    panel.name = "DingSound"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("DingSound")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetText("Customize level-up and achievement sounds.")

    local soundOptions = BuildSoundOptions()

    local levelSectionTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    levelSectionTitle:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -12)
    levelSectionTitle:SetText("Level-Up Customization")

    local enabledCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    enabledCheck:SetPoint("TOPLEFT", levelSectionTitle, "BOTTOMLEFT", -2, -8)
    enabledCheck.text = enabledCheck:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    enabledCheck.text:SetPoint("LEFT", enabledCheck, "RIGHT", 2, 0)
    enabledCheck.text:SetText("Enable DingSound")
    enabledCheck:SetChecked(DingSoundDB.levelUp.enabled)
    enabledCheck:SetScript("OnClick", function(self)
        DingSoundDB.levelUp.enabled = self:GetChecked() and true or false
    end)

    local muteDefaultCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    muteDefaultCheck:SetPoint("TOPLEFT", enabledCheck, "BOTTOMLEFT", 0, -8)
    muteDefaultCheck.text = muteDefaultCheck:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    muteDefaultCheck.text:SetPoint("LEFT", muteDefaultCheck, "RIGHT", 2, 0)
    muteDefaultCheck.text:SetText("Mute WoW default level-up sound")
    muteDefaultCheck:SetChecked(DingSoundDB.levelUp.muteDefault)
    muteDefaultCheck:SetScript("OnClick", function(self)
        DingSoundDB.levelUp.muteDefault = self:GetChecked() and true or false
        ApplyDefaultLevelUpMuteSetting()
    end)

    local dropdownLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    dropdownLabel:SetPoint("TOPLEFT", muteDefaultCheck, "BOTTOMLEFT", 2, -24)
    dropdownLabel:SetText("Level-up sound")

    local dropdown = CreateFrame("Frame", "DingSoundSoundDropdown", panel, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", dropdownLabel, "BOTTOMLEFT", -16, -6)
    UIDropDownMenu_SetWidth(dropdown, 250)

    local previewButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    previewButton:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 16, -10)
    previewButton:SetSize(120, 22)
    previewButton:SetText("Play selected")
    previewButton:SetScript("OnClick", function()
        local selectedPath = DingSoundDB.levelUp.selectedSound
        if not selectedPath then
            print("No sound selected")
            return
        end

        PlaySoundFile(selectedPath, "Master")
    end)

    local function UpdateLevelPreviewButtonState()
        if DingSoundDB.levelUp.selectedSound then
            previewButton:Enable()
        else
            previewButton:Disable()
        end
    end

    UIDropDownMenu_Initialize(dropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()

        info.text = "None"
        info.value = nil
        info.checked = DingSoundDB.levelUp.selectedSound == nil
        info.func = function()
            DingSoundDB.levelUp.selectedSound = nil
            UIDropDownMenu_SetSelectedValue(dropdown, nil)
            UIDropDownMenu_SetText(dropdown, "None")
            UpdateLevelPreviewButtonState()
        end
        UIDropDownMenu_AddButton(info, level)

        for _, option in ipairs(soundOptions) do
            local item = UIDropDownMenu_CreateInfo()
            item.text = option.text
            item.value = option.value
            item.checked = DingSoundDB.levelUp.selectedSound == option.value
            item.func = function()
                DingSoundDB.levelUp.selectedSound = option.value
                UIDropDownMenu_SetSelectedValue(dropdown, option.value)
                UIDropDownMenu_SetText(dropdown, option.text)
                UpdateLevelPreviewButtonState()
            end
            UIDropDownMenu_AddButton(item, level)
        end
    end)

    if #soundOptions == 0 then
        UIDropDownMenu_SetText(dropdown, "No sounds found in DingSound_SoundList.lua")
    else
        local selected = GetCurrentSelection(soundOptions, DingSoundDB.levelUp.selectedSound)
        if selected then
            UIDropDownMenu_SetSelectedValue(dropdown, selected)
            for _, option in ipairs(soundOptions) do
                if option.value == selected then
                    UIDropDownMenu_SetText(dropdown, option.text)
                    break
                end
            end
        else
            UIDropDownMenu_SetText(dropdown, "None")
        end
    end

    UpdateLevelPreviewButtonState()

    local function FormatDuckoutLabel(prefix, value)
        if value <= 0 then
            return string.format("%s: Disabled", prefix)
        end

        return string.format("%s: %.1fs", prefix, value)
    end

    local duckSlider = CreateFrame("Slider", "DingSoundDuckoutDurationSlider", panel, "OptionsSliderTemplate")
    duckSlider:SetPoint("TOPLEFT", previewButton, "BOTTOMLEFT", 4, -18)
    duckSlider:SetMinMaxValues(0, 3)
    duckSlider:SetValueStep(0.5)
    duckSlider:SetObeyStepOnDrag(true)
    duckSlider:SetWidth(230)

    _G[duckSlider:GetName() .. "Low"]:SetText("0s (disabled)")
    _G[duckSlider:GetName() .. "High"]:SetText("3s")
    _G[duckSlider:GetName() .. "Text"]:SetText("Duckout duration")

    local function SetLevelDuckoutDuration(value)
        local normalized = math.max(0, math.min(3, math.floor((value * 2) + 0.5) / 2))
        DingSoundDB.levelUp.duckoutDuration = normalized
        if math.abs((duckSlider:GetValue() or 0) - normalized) > 0.001 then
            duckSlider:SetValue(normalized)
            return
        end
        _G[duckSlider:GetName() .. "Text"]:SetText(FormatDuckoutLabel("Duckout duration", normalized))
    end

    duckSlider:SetScript("OnValueChanged", function(self, value)
        SetLevelDuckoutDuration(value)
    end)

    SetLevelDuckoutDuration(tonumber(DingSoundDB.levelUp.duckoutDuration) or DEFAULT_DB.levelUp.duckoutDuration)

    local helpText = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    helpText:SetPoint("TOPLEFT", duckSlider, "BOTTOMLEFT", -4, -22)
    helpText:SetJustifyH("LEFT")
    helpText:SetText("Put audio files in Interface/AddOns/DingSound/Sounds/ and list each filename in DingSound_SoundList.lua.")

    local achievementSectionTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    achievementSectionTitle:SetPoint("TOPLEFT", helpText, "BOTTOMLEFT", 0, -28)
    achievementSectionTitle:SetText("Achievement Customization")

    local achievementEnabledCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    achievementEnabledCheck:SetPoint("TOPLEFT", achievementSectionTitle, "BOTTOMLEFT", -2, -8)
    achievementEnabledCheck.text = achievementEnabledCheck:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    achievementEnabledCheck.text:SetPoint("LEFT", achievementEnabledCheck, "RIGHT", 2, 0)
    achievementEnabledCheck.text:SetText("Enable custom achievement sound")
    achievementEnabledCheck:SetChecked(DingSoundDB.achievement.enabled)
    achievementEnabledCheck:SetScript("OnClick", function(self)
        DingSoundDB.achievement.enabled = self:GetChecked() and true or false
    end)

    local achievementMuteDefaultCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    achievementMuteDefaultCheck:SetPoint("TOPLEFT", achievementEnabledCheck, "BOTTOMLEFT", 0, -8)
    achievementMuteDefaultCheck.text = achievementMuteDefaultCheck:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    achievementMuteDefaultCheck.text:SetPoint("LEFT", achievementMuteDefaultCheck, "RIGHT", 2, 0)
    achievementMuteDefaultCheck.text:SetText("Mute WoW default achievement sound")
    achievementMuteDefaultCheck:SetChecked(DingSoundDB.achievement.muteDefault)
    achievementMuteDefaultCheck:SetScript("OnClick", function(self)
        DingSoundDB.achievement.muteDefault = self:GetChecked() and true or false
        ApplyDefaultAchievementMuteSetting()
    end)

    local achievementDropdownLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    achievementDropdownLabel:SetPoint("TOPLEFT", achievementMuteDefaultCheck, "BOTTOMLEFT", 2, -24)
    achievementDropdownLabel:SetText("Achievement sound")

    local achievementDropdown = CreateFrame("Frame", "DingSoundAchievementSoundDropdown", panel, "UIDropDownMenuTemplate")
    achievementDropdown:SetPoint("TOPLEFT", achievementDropdownLabel, "BOTTOMLEFT", -16, -6)
    UIDropDownMenu_SetWidth(achievementDropdown, 250)

    local achievementPreviewButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    achievementPreviewButton:SetPoint("TOPLEFT", achievementDropdown, "BOTTOMLEFT", 16, -10)
    achievementPreviewButton:SetSize(120, 22)
    achievementPreviewButton:SetText("Play selected")
    achievementPreviewButton:SetScript("OnClick", function()
        local selectedPath = DingSoundDB.achievement.selectedSound
        if not selectedPath then
            print("No sound selected")
            return
        end

        PlaySoundFile(selectedPath, "Master")
    end)

    local function UpdateAchievementPreviewButtonState()
        if DingSoundDB.achievement.selectedSound then
            achievementPreviewButton:Enable()
        else
            achievementPreviewButton:Disable()
        end
    end

    UIDropDownMenu_Initialize(achievementDropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()

        info.text = "None"
        info.value = nil
        info.checked = DingSoundDB.achievement.selectedSound == nil
        info.func = function()
            DingSoundDB.achievement.selectedSound = nil
            UIDropDownMenu_SetSelectedValue(achievementDropdown, nil)
            UIDropDownMenu_SetText(achievementDropdown, "None")
            UpdateAchievementPreviewButtonState()
        end
        UIDropDownMenu_AddButton(info, level)

        for _, option in ipairs(soundOptions) do
            local item = UIDropDownMenu_CreateInfo()
            item.text = option.text
            item.value = option.value
            item.checked = DingSoundDB.achievement.selectedSound == option.value
            item.func = function()
                DingSoundDB.achievement.selectedSound = option.value
                UIDropDownMenu_SetSelectedValue(achievementDropdown, option.value)
                UIDropDownMenu_SetText(achievementDropdown, option.text)
                UpdateAchievementPreviewButtonState()
            end
            UIDropDownMenu_AddButton(item, level)
        end
    end)

    if #soundOptions == 0 then
        UIDropDownMenu_SetText(achievementDropdown, "No sounds found in DingSound_SoundList.lua")
    else
        local selected = GetCurrentSelection(soundOptions, DingSoundDB.achievement.selectedSound)
        if selected then
            UIDropDownMenu_SetSelectedValue(achievementDropdown, selected)
            for _, option in ipairs(soundOptions) do
                if option.value == selected then
                    UIDropDownMenu_SetText(achievementDropdown, option.text)
                    break
                end
            end
        else
            UIDropDownMenu_SetText(achievementDropdown, "None")
        end
    end

    UpdateAchievementPreviewButtonState()

    local achievementDuckSlider = CreateFrame("Slider", "DingSoundAchievementDuckoutDurationSlider", panel, "OptionsSliderTemplate")
    achievementDuckSlider:SetPoint("TOPLEFT", achievementPreviewButton, "BOTTOMLEFT", 4, -18)
    achievementDuckSlider:SetMinMaxValues(0, 3)
    achievementDuckSlider:SetValueStep(0.5)
    achievementDuckSlider:SetObeyStepOnDrag(true)
    achievementDuckSlider:SetWidth(230)

    _G[achievementDuckSlider:GetName() .. "Low"]:SetText("0s (disabled)")
    _G[achievementDuckSlider:GetName() .. "High"]:SetText("3s")
    _G[achievementDuckSlider:GetName() .. "Text"]:SetText("Achievement duckout duration")

    local function SetAchievementDuckoutDuration(value)
        local normalized = math.max(0, math.min(3, math.floor((value * 2) + 0.5) / 2))
        DingSoundDB.achievement.duckoutDuration = normalized
        if math.abs((achievementDuckSlider:GetValue() or 0) - normalized) > 0.001 then
            achievementDuckSlider:SetValue(normalized)
            return
        end
        _G[achievementDuckSlider:GetName() .. "Text"]:SetText(FormatDuckoutLabel("Achievement duckout duration", normalized))
    end

    achievementDuckSlider:SetScript("OnValueChanged", function(self, value)
        SetAchievementDuckoutDuration(value)
    end)

    SetAchievementDuckoutDuration(tonumber(DingSoundDB.achievement.duckoutDuration) or DEFAULT_DB.achievement.duckoutDuration)

    local versionText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    versionText:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 16)
    versionText:SetText(string.format("v%s", ADDON_VERSION))

    local authorText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    authorText:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 16, 16)
    authorText:SetText("author: skeletor-gh")

    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("ACHIEVEMENT_EARNED")
frame:RegisterEvent("PET_BATTLE_OPENING_START")
frame:RegisterEvent("PET_BATTLE_OVER")
frame:RegisterEvent("PET_BATTLE_CLOSE")

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        InitializeAchievementSoundKitIds()
        InstallPlaySoundWrapper()
        EnsureDefaults()
        CreateSettingsPanel()
        print(string.format("\124cFF9910E8 DingSound v%s Loaded!", ADDON_VERSION))
    elseif event == "PLAYER_LEVEL_UP" then
        PlayLevelUpSound()
    elseif event == "ACHIEVEMENT_EARNED" then
        PlayAchievementSound()
    elseif event == "PET_BATTLE_OPENING_START" then
        SetPetBattleMuteOverride(true)
    elseif event == "PET_BATTLE_OVER" or event == "PET_BATTLE_CLOSE" then
        SetPetBattleMuteOverride(false)
    end
end)
