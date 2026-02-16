local ADDON_NAME = ...

DingSound = DingSound or {}

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
local ADDON_AUTHOR = "skeletor-gh"

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

local DEFAULT_LEVEL_UP_SOUND_PATHS = {
    569593,
}

local DEFAULT_ACHIEVEMENT_SOUND_PATHS = {
    543587,
    569143,
}

local DEFAULT_ACHIEVEMENT_SOUNDKIT_KEYS = {
    "UI_ACHIEVEMENT_TOAST",
    "UI_ACHIEVEMENT_MENU_OPEN",
}

local achievementSoundKitIdSet = {}
local shouldSuppressAchievementSoundKit = false

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
        if shouldSuppressAchievementSoundKit and type(soundKitID) == "number" and achievementSoundKitIdSet[soundKitID] then
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
    local shouldMute = DingSoundDB and DingSoundDB.levelUp and DingSoundDB.levelUp.enabled
    if isPetBattleMuteOverrideActive then
        shouldMute = false
    end

    SetDefaultLevelUpMuted(shouldMute)
end

local function ApplyDefaultAchievementMuteSetting()
    local shouldMute = DingSoundDB and DingSoundDB.achievement and DingSoundDB.achievement.enabled
    shouldSuppressAchievementSoundKit = shouldMute and true or false
    SetDefaultAchievementMuted(shouldMute)
end

function DingSound.PlayCheckboxClickSound(isChecked)
    local soundKitId = nil
    if type(SOUNDKIT) == "table" then
        soundKitId = isChecked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF
    end

    if soundKitId then
        PlaySound(soundKitId, "SFX")
        return
    end

    PlaySound(856, "SFX")
end

local function SetPetBattleMuteOverride(active)
    if not DingSoundDB or not DingSoundDB.levelUp then
        return
    end

    if active and DingSoundDB.levelUp.enabled then
        isPetBattleMuteOverrideActive = true
        ApplyDefaultLevelUpMuteSetting()
    elseif not active then
        isPetBattleMuteOverrideActive = false
        ApplyDefaultLevelUpMuteSetting()
    end
end

local function MigrateLegacySettings()
    if DingSoundDB.enabled ~= nil and DingSoundDB.levelUp == nil then
        DingSoundDB.levelUp = {
            enabled = DingSoundDB.enabled,
            selectedSound = DingSoundDB.selectedSound,
            muteDefault = true,
            duckoutDuration = DingSoundDB.duckoutDuration,
        }
    end

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

    DingSoundDB.levelUp.muteDefault = true

    if DingSoundDB.levelUp.duckoutDuration == nil then
        DingSoundDB.levelUp.duckoutDuration = DEFAULT_DB.levelUp.duckoutDuration
    end

    if DingSoundDB.achievement.enabled == nil then
        DingSoundDB.achievement.enabled = DEFAULT_DB.achievement.enabled
    end

    if DingSoundDB.achievement.selectedSound == nil then
        DingSoundDB.achievement.selectedSound = DEFAULT_DB.achievement.selectedSound
    end

    DingSoundDB.achievement.muteDefault = true

    if DingSoundDB.achievement.duckoutDuration == nil then
        DingSoundDB.achievement.duckoutDuration = DEFAULT_DB.achievement.duckoutDuration
    end

    ApplyDefaultLevelUpMuteSetting()
    ApplyDefaultAchievementMuteSetting()
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

function DingSound.GetAddonVersion()
    return ADDON_VERSION
end

function DingSound.GetAddonAuthor()
    return ADDON_AUTHOR
end

function DingSound.GetSoundOptions()
    return BuildSoundOptions()
end

function DingSound.ApplyLevelUpMute()
    ApplyDefaultLevelUpMuteSetting()
end

function DingSound.ApplyAchievementMute()
    ApplyDefaultAchievementMuteSetting()
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
        if DingSound.CreateSettingsPanels then
            DingSound.CreateSettingsPanels()
        end
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
