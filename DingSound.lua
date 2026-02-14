local ADDON_NAME = ...
local ADDON_VERSION = GetAddOnMetadata(ADDON_NAME, "Version") or "dev"

local DEFAULT_DB = {
    enabled = true,
    selectedSound = nil,
    muteDefaultLevelUp = true,
    duckoutDuration = 1.5,
}

-- Minimum time (seconds) between level-up sound plays.
-- This prevents overlapping sounds when multiple level-up events fire quickly.
local LEVEL_UP_SOUND_BUFFER_SECONDS = 2.0
local nextPlayableTime = 0
local isPetBattleMuteOverrideActive = false
local activeLevelUpSoundHandle = nil
local activeVolumeRestoreTimer = nil
local duckedVolumeSnapshot = nil

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
    activeLevelUpSoundHandle = nil
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
            SetCVar(cvarName, tostring(reducedValue))
        end
    end

    if not next(duckedVolumeSnapshot) then
        duckedVolumeSnapshot = nil
    end
end

local function GetSoundDurationSeconds(soundPath)
    if not C_Sound or not C_Sound.GetSoundFileDuration then
        return nil
    end

    local duration = C_Sound.GetSoundFileDuration(soundPath)
    if not duration or duration <= 0 then
        return nil
    end

    -- Some clients report milliseconds and others may report seconds.
    -- Treat large values as milliseconds.
    if duration > 30 then
        return duration / 1000
    end

    return duration
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

local function ApplyDefaultLevelUpMuteSetting()
    local shouldMute = DingSoundDB and DingSoundDB.muteDefaultLevelUp
    if isPetBattleMuteOverrideActive then
        shouldMute = false
    end

    SetDefaultLevelUpMuted(shouldMute)
end

local function SetPetBattleMuteOverride(active)
    if not DingSoundDB then
        return
    end

    if active and DingSoundDB.muteDefaultLevelUp then
        isPetBattleMuteOverrideActive = true
        ApplyDefaultLevelUpMuteSetting()
    elseif not active then
        isPetBattleMuteOverrideActive = false
        ApplyDefaultLevelUpMuteSetting()
    end
end

local function EnsureDefaults()
    DingSoundDB = DingSoundDB or {}

    if DingSoundDB.enabled == nil then
        DingSoundDB.enabled = DEFAULT_DB.enabled
    end

    if DingSoundDB.selectedSound == nil then
        DingSoundDB.selectedSound = DEFAULT_DB.selectedSound
    end

    if DingSoundDB.muteDefaultLevelUp == nil then
        DingSoundDB.muteDefaultLevelUp = DEFAULT_DB.muteDefaultLevelUp
    end

    if DingSoundDB.duckoutDuration == nil then
        DingSoundDB.duckoutDuration = DEFAULT_DB.duckoutDuration
    end

    ApplyDefaultLevelUpMuteSetting()
end

local function GetCurrentSelection(options)
    local current = DingSoundDB.selectedSound
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
    if not DingSoundDB or not DingSoundDB.enabled then
        return
    end

    local path = DingSoundDB.selectedSound
    if not path then
        return
    end

    local now = GetTime()
    if now < nextPlayableTime then
        return
    end

    local duckoutDuration = tonumber(DingSoundDB.duckoutDuration) or 0

    if duckedVolumeSnapshot then
        RestoreDuckedVolumes()
    end

    if duckoutDuration > 0 then
        DuckNonMasterVolumes(0.10)
    end

    local didPlay, soundHandle = PlaySoundFile(path, "Master")
    if didPlay then
        nextPlayableTime = now + LEVEL_UP_SOUND_BUFFER_SECONDS
        activeLevelUpSoundHandle = soundHandle

        if duckoutDuration > 0 then
            local durationSeconds = math.min(duckoutDuration, GetSoundDurationSeconds(path) or duckoutDuration)
            ScheduleVolumeRestore(durationSeconds)
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

    local versionText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    versionText:SetPoint("LEFT", title, "RIGHT", 8, -1)
    versionText:SetText(string.format("v%s", ADDON_VERSION))

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetText("Play a custom sound when your character levels up.")

    local enabledCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    enabledCheck:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", -2, -14)
    enabledCheck.text = enabledCheck:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    enabledCheck.text:SetPoint("LEFT", enabledCheck, "RIGHT", 2, 0)
    enabledCheck.text:SetText("Enable DingSound")
    enabledCheck:SetChecked(DingSoundDB.enabled)
    enabledCheck:SetScript("OnClick", function(self)
        DingSoundDB.enabled = self:GetChecked() and true or false
    end)

    local muteDefaultCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    muteDefaultCheck:SetPoint("TOPLEFT", enabledCheck, "BOTTOMLEFT", 0, -8)
    muteDefaultCheck.text = muteDefaultCheck:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    muteDefaultCheck.text:SetPoint("LEFT", muteDefaultCheck, "RIGHT", 2, 0)
    muteDefaultCheck.text:SetText("Mute WoW default level-up sound")
    muteDefaultCheck:SetChecked(DingSoundDB.muteDefaultLevelUp)
    if false then
        muteDefaultCheck:Disable()
        muteDefaultCheck.text:SetText("Mute WoW default level-up sound (not available on this client)")
    end
    muteDefaultCheck:SetScript("OnClick", function(self)
        DingSoundDB.muteDefaultLevelUp = self:GetChecked() and true or false
        ApplyDefaultLevelUpMuteSetting()
    end)

    local dropdownLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    dropdownLabel:SetPoint("TOPLEFT", muteDefaultCheck, "BOTTOMLEFT", 2, -24)
    dropdownLabel:SetText("Level-up sound")

    local dropdown = CreateFrame("Frame", "DingSoundSoundDropdown", panel, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", dropdownLabel, "BOTTOMLEFT", -16, -6)

    local soundOptions = BuildSoundOptions()

    UIDropDownMenu_SetWidth(dropdown, 250)

    local previewButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    previewButton:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 16, -10)
    previewButton:SetSize(120, 22)
    previewButton:SetText("Play selected")
    previewButton:SetScript("OnClick", function()
        local selectedPath = DingSoundDB.selectedSound
        if not selectedPath then
            print("No sound selected")
            return
        end

        PlaySoundFile(selectedPath, "Master")
    end)

    local function UpdatePreviewButtonState()
        if DingSoundDB.selectedSound then
            previewButton:Enable()
        else
            previewButton:Disable()
        end
    end

    UIDropDownMenu_Initialize(dropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()

        info.text = "None"
        info.value = nil
        info.checked = DingSoundDB.selectedSound == nil
        info.func = function()
            DingSoundDB.selectedSound = nil
            UIDropDownMenu_SetSelectedValue(dropdown, nil)
            UIDropDownMenu_SetText(dropdown, "None")
            UpdatePreviewButtonState()
        end
        UIDropDownMenu_AddButton(info, level)

        for _, option in ipairs(soundOptions) do
            local item = UIDropDownMenu_CreateInfo()
            item.text = option.text
            item.value = option.value
            item.checked = DingSoundDB.selectedSound == option.value
            item.func = function()
                DingSoundDB.selectedSound = option.value
                UIDropDownMenu_SetSelectedValue(dropdown, option.value)
                UIDropDownMenu_SetText(dropdown, option.text)
                UpdatePreviewButtonState()
            end
            UIDropDownMenu_AddButton(item, level)
        end
    end)

    if #soundOptions == 0 then
        UIDropDownMenu_SetText(dropdown, "No sounds found in DingSound_SoundList.lua")
    else
        local selected = GetCurrentSelection(soundOptions)
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

    UpdatePreviewButtonState()

    local helpText = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    helpText:SetPoint("TOPLEFT", previewButton, "BOTTOMLEFT", 0, -58)
    helpText:SetJustifyH("LEFT")
    helpText:SetText("Put audio files in Interface/AddOns/DingSound/Sounds/ and list each filename in DingSound_SoundList.lua.")

    local duckSlider = CreateFrame("Slider", "DingSoundDuckoutDurationSlider", panel, "OptionsSliderTemplate")
    duckSlider:SetPoint("TOPLEFT", previewButton, "BOTTOMLEFT", 4, -18)
    duckSlider:SetMinMaxValues(0, 3)
    duckSlider:SetValueStep(0.5)
    duckSlider:SetObeyStepOnDrag(true)
    duckSlider:SetWidth(230)

    _G[duckSlider:GetName() .. "Low"]:SetText("0s (disabled)")
    _G[duckSlider:GetName() .. "High"]:SetText("3s")
    _G[duckSlider:GetName() .. "Text"]:SetText("Duckout duration")

    local function FormatDuckoutLabel(value)
        if value <= 0 then
            return "Duckout duration: Disabled"
        end

        return string.format("Duckout duration: %.1fs", value)
    end

    local function SetDuckoutDuration(value)
        local normalized = math.max(0, math.min(3, math.floor((value * 2) + 0.5) / 2))
        DingSoundDB.duckoutDuration = normalized
        if math.abs((duckSlider:GetValue() or 0) - normalized) > 0.001 then
            duckSlider:SetValue(normalized)
            return
        end
        _G[duckSlider:GetName() .. "Text"]:SetText(FormatDuckoutLabel(normalized))
    end

    duckSlider:SetScript("OnValueChanged", function(self, value)
        SetDuckoutDuration(value)
    end)

    SetDuckoutDuration(tonumber(DingSoundDB.duckoutDuration) or DEFAULT_DB.duckoutDuration)

    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("PET_BATTLE_OPENING_START")
frame:RegisterEvent("PET_BATTLE_OVER")
frame:RegisterEvent("PET_BATTLE_CLOSE")
frame:RegisterEvent("SOUNDKIT_FINISHED")

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        EnsureDefaults()
        CreateSettingsPanel()
        print(string.format("\124cFF9910E8 DingSound v%s Loaded!", ADDON_VERSION))
    elseif event == "PLAYER_LEVEL_UP" then
        PlayLevelUpSound()
    elseif event == "PET_BATTLE_OPENING_START" then
        SetPetBattleMuteOverride(true)
    elseif event == "PET_BATTLE_OVER" or event == "PET_BATTLE_CLOSE" then
        SetPetBattleMuteOverride(false)
    elseif event == "SOUNDKIT_FINISHED" and activeLevelUpSoundHandle and arg1 == activeLevelUpSoundHandle then
        RestoreDuckedVolumes()
    end
end)
