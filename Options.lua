DingSound = DingSound or {}

local function AddFooter(panel)
    local versionText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    versionText:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 16)
    versionText:SetText(string.format("v%s", DingSound.GetAddonVersion()))

    local authorText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    authorText:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 16, 16)
    authorText:SetText(string.format("author: %s", DingSound.GetAddonAuthor()))
end

local function FormatDuckoutLabel(prefix, value)
    if value <= 0 then
        return string.format("%s: Disabled", prefix)
    end

    return string.format("%s: %.1fs", prefix, value)
end

local function CreateInfoPanel()
    local panel = CreateFrame("Frame", nil, UIParent)
    panel.name = "DingSound"

    local background = panel:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(panel)
    background:SetTexture("Interface\\AddOns\\DingSound\\Assets\\dingsound")
    background:SetAlpha(0.3)

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("DingSound")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetText("DingSound plays custom audio files whenever your character levels up or earns an achievement.")

    local features = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    features:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -18)
    features:SetJustifyH("LEFT")
    features:SetText(
        "Features:\n"
        .. "• PLAYER_LEVEL_UP and ACHIEVEMENT_EARNED support\n"
        .. "• Independent sound selection for each feature\n"
        .. "• Playback buffers to prevent overlap\n"
        .. "• Built-in options for feature toggles and duckout controls"
    )

    local addSounds = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    addSounds:SetPoint("TOPLEFT", features, "BOTTOMLEFT", 0, -18)
    addSounds:SetJustifyH("LEFT")
    addSounds:SetText(
        "Adding your own sounds:\n"
        .. "1. Put files in Interface/AddOns/DingSound/Sounds/\n"
        .. "2. Add file names to DingSound_SoundList.lua"
    )

    AddFooter(panel)

    return Settings.RegisterCanvasLayoutCategory(panel, panel.name)
end

local function CreateMainOptionsPanel(parentCategory)
    local panel = CreateFrame("Frame", nil, UIParent)
    panel.name = "Main Options"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Main Options")

    local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetJustifyH("LEFT")
    desc:SetText("Enable or disable each DingSound feature.\nWhen enabled, the corresponding Blizzard default sound is muted.")

    local levelEnabledCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    levelEnabledCheck:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", -2, -16)
    levelEnabledCheck.text = levelEnabledCheck:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    levelEnabledCheck.text:SetPoint("LEFT", levelEnabledCheck, "RIGHT", 2, 0)
    levelEnabledCheck.text:SetText("Enable Level Up Sound")
    levelEnabledCheck:SetChecked(DingSoundDB.levelUp.enabled)
    levelEnabledCheck:SetScript("OnClick", function(self)
        local isChecked = self:GetChecked() and true or false
        DingSoundDB.levelUp.enabled = isChecked
        DingSound.ApplyLevelUpMute()
        DingSound.PlayCheckboxClickSound(isChecked)
        DingSound.AnnounceOptionChange("Level up sound", isChecked)
    end)

    local achievementEnabledCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    achievementEnabledCheck:SetPoint("TOPLEFT", levelEnabledCheck, "BOTTOMLEFT", 0, -12)
    achievementEnabledCheck.text = achievementEnabledCheck:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    achievementEnabledCheck.text:SetPoint("LEFT", achievementEnabledCheck, "RIGHT", 2, 0)
    achievementEnabledCheck.text:SetText("Enable Achievement Sound")
    achievementEnabledCheck:SetChecked(DingSoundDB.achievement.enabled)
    achievementEnabledCheck:SetScript("OnClick", function(self)
        local isChecked = self:GetChecked() and true or false
        DingSoundDB.achievement.enabled = isChecked
        DingSound.ApplyAchievementMute()
        DingSound.PlayCheckboxClickSound(isChecked)
        DingSound.AnnounceOptionChange("Achievement sound", isChecked)
    end)

    AddFooter(panel)

    Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, panel.name, panel.name)
end

local function InitializeSoundDropdown(dropdown, currentValue, soundOptions, onSelect)
    UIDropDownMenu_SetWidth(dropdown, 250)

    UIDropDownMenu_Initialize(dropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        info.text = "None"
        info.value = nil
        info.checked = currentValue() == nil
        info.func = function()
            onSelect(nil, "None")
        end
        UIDropDownMenu_AddButton(info, level)

        for _, option in ipairs(soundOptions) do
            local item = UIDropDownMenu_CreateInfo()
            item.text = option.text
            item.value = option.value
            item.checked = currentValue() == option.value
            item.func = function()
                onSelect(option.value, option.text)
            end
            UIDropDownMenu_AddButton(item, level)
        end
    end)

    if #soundOptions == 0 then
        UIDropDownMenu_SetText(dropdown, "No sounds found in DingSound_SoundList.lua")
        return
    end

    local selected = currentValue()
    if selected then
        for _, option in ipairs(soundOptions) do
            if option.value == selected then
                UIDropDownMenu_SetSelectedValue(dropdown, selected)
                UIDropDownMenu_SetText(dropdown, option.text)
                return
            end
        end
    end

    UIDropDownMenu_SetText(dropdown, "None")
end

local function CreateMainSoundSection(panel, anchor, titleText, featureKey, sliderName)
    local sectionTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    sectionTitle:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -24)
    sectionTitle:SetText(titleText)

    local soundOptions = DingSound.GetSoundOptions()

    local dropdown = CreateFrame("Frame", nil, panel, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", sectionTitle, "BOTTOMLEFT", -16, -6)

    local previewButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    previewButton:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 16, -8)
    previewButton:SetSize(120, 22)
    previewButton:SetText("Play selected")

    local function updatePreviewState()
        if DingSoundDB[featureKey].selectedSound then
            previewButton:Enable()
        else
            previewButton:Disable()
        end
    end

    previewButton:SetScript("OnClick", function()
        DingSound.PreviewFeatureSound(featureKey)
    end)

    InitializeSoundDropdown(
        dropdown,
        function() return DingSoundDB[featureKey].selectedSound end,
        soundOptions,
        function(value, label)
            DingSoundDB[featureKey].selectedSound = value
            UIDropDownMenu_SetSelectedValue(dropdown, value)
            UIDropDownMenu_SetText(dropdown, label)
            updatePreviewState()
        end
    )

    updatePreviewState()

    local slider = CreateFrame("Slider", sliderName, panel, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", previewButton, "BOTTOMLEFT", 4, -18)
    slider:SetMinMaxValues(0, 3)
    slider:SetValueStep(0.5)
    slider:SetObeyStepOnDrag(true)
    slider:SetWidth(230)

    _G[slider:GetName() .. "Low"]:SetText("0s (disabled)")
    _G[slider:GetName() .. "High"]:SetText("3s")

    local labelPrefix = featureKey == "levelUp" and "Level-up duckout duration" or "Achievement duckout duration"

    local function setDuckoutDuration(value)
        local normalized = math.max(0, math.min(3, math.floor((value * 2) + 0.5) / 2))
        DingSoundDB[featureKey].duckoutDuration = normalized
        if math.abs((slider:GetValue() or 0) - normalized) > 0.001 then
            slider:SetValue(normalized)
            return
        end
        _G[slider:GetName() .. "Text"]:SetText(FormatDuckoutLabel(labelPrefix, normalized))
    end

    slider:SetScript("OnValueChanged", function(self, value)
        setDuckoutDuration(value)
    end)

    setDuckoutDuration(tonumber(DingSoundDB[featureKey].duckoutDuration) or 1.5)

    return slider
end

local function CreateCustomSoundsPanel(parentCategory)
    local panel = CreateFrame("Frame", nil, UIParent)
    panel.name = "Custom Sounds"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Custom Sounds")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetText("Select custom sounds and duckout duration for each feature.")

    local levelSlider = CreateMainSoundSection(panel, subtitle, "Level-up sound", "levelUp", "DingSoundLevelDuckoutDurationSlider")

    local achievementSlider = CreateMainSoundSection(panel, levelSlider, "Achievement sound", "achievement", "DingSoundAchievementDuckoutDurationSlider")

    local helpText = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    helpText:SetPoint("TOPLEFT", achievementSlider, "BOTTOMLEFT", -4, -22)
    helpText:SetJustifyH("LEFT")
    helpText:SetText("To add more custom sounds: put files in Interface/AddOns/DingSound/Sounds/ and list each filename in DingSound_SoundList.lua.")

    AddFooter(panel)

    Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, panel.name, panel.name)
end

function DingSound.CreateSettingsPanels()
    local infoCategory = CreateInfoPanel()
    CreateMainOptionsPanel(infoCategory)
    CreateCustomSoundsPanel(infoCategory)
    Settings.RegisterAddOnCategory(infoCategory)
end
