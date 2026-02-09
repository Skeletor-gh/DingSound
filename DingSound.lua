local ADDON_NAME = ...

local DEFAULT_DB = {
    enabled = true,
    selectedSound = nil,
}

-- Minimum time (seconds) between level-up sound plays.
-- This prevents overlapping sounds when multiple level-up events fire quickly.
local LEVEL_UP_SOUND_BUFFER_SECONDS = 2.0
local nextPlayableTime = 0

-- WoW does not allow directory scans at runtime, so this table is the addon-maintained
-- catalog of files stored under: Interface/AddOns/DingSound/Sounds/
-- Add file names here (for example: "levelup.mp3", "horn.ogg").
local SOUND_FILES = {
    "FF7_victory.mp3"	-- Final Fantasy 7 Fanfare
}

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

    for _, fileName in ipairs(SOUND_FILES) do
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

local function EnsureDefaults()
    DingSoundDB = DingSoundDB or {}

    if DingSoundDB.enabled == nil then
        DingSoundDB.enabled = DEFAULT_DB.enabled
    end

    if DingSoundDB.selectedSound == nil then
        DingSoundDB.selectedSound = DEFAULT_DB.selectedSound
    end
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

    local didPlay = PlaySoundFile(path, "Master")
    if didPlay then
        nextPlayableTime = now + LEVEL_UP_SOUND_BUFFER_SECONDS
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

    local dropdownLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    dropdownLabel:SetPoint("TOPLEFT", enabledCheck, "BOTTOMLEFT", 2, -24)
    dropdownLabel:SetText("Level-up sound")

    local dropdown = CreateFrame("Frame", "DingSoundSoundDropdown", panel, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", dropdownLabel, "BOTTOMLEFT", -16, -6)

    local soundOptions = BuildSoundOptions()

    UIDropDownMenu_SetWidth(dropdown, 250)
    UIDropDownMenu_Initialize(dropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()

        info.text = "None"
        info.value = nil
        info.checked = DingSoundDB.selectedSound == nil
        info.func = function()
            DingSoundDB.selectedSound = nil
            UIDropDownMenu_SetSelectedValue(dropdown, nil)
            UIDropDownMenu_SetText(dropdown, "None")
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
            end
            UIDropDownMenu_AddButton(item, level)
        end
    end)

    if #soundOptions == 0 then
        UIDropDownMenu_SetText(dropdown, "No sounds found in SOUND_FILES")
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

    local helpText = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    helpText:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 16, -10)
    helpText:SetJustifyH("LEFT")
    helpText:SetText("Put audio files in Interface/AddOns/DingSound/Sounds/ and list each filename in SOUND_FILES inside DingSound.lua.")

    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LEVEL_UP")

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        EnsureDefaults()
        CreateSettingsPanel()
    elseif event == "PLAYER_LEVEL_UP" then
        PlayLevelUpSound()
    end
end)
