PTSettingsGui = {}
PTUtil.SetEnvironment(PTSettingsGui, PuppeteerSettings)
local util = PTUtil
local colorize = util.Colorize
local compost = AceLibrary("Compost-2.0")
local GetOption = PuppeteerSettings.GetOption
local SetOption = PuppeteerSettings.SetOption
local GetSelectedProfile = PuppeteerSettings.GetSelectedProfile

TabFrame = PTGuiLib.Get("tab_frame"):Hide()



-- Helper function to refresh a specific frame group by recreating frames
function RefreshFrameGroup(frameName)
    if not Puppeteer.UnitFrameGroups then
        return
    end
    local group = Puppeteer.UnitFrameGroups[frameName]
    if not group then
        return
    end

    -- Recreate all frames for this group (similar to profile hotswapping)
    group.profile = GetSelectedProfile(frameName)
    local oldUIs = group.uis
    group.uis = {}
    group:ResetFrameLevel()

    for unit, ui in pairs(oldUIs) do
        ui:GetRootContainer():SetParent(nil)
        ui:GetRootContainer():Hide()
        local newUI = PTUnitFrame:New(unit, ui.isCustomUnit)
        util.RemoveElement(Puppeteer.AllUnitFrames, ui)
        table.insert(Puppeteer.AllUnitFrames, newUI)
        local unitUIs = Puppeteer.GetUnitFrames(unit)
        util.RemoveElement(unitUIs, ui)
        table.insert(unitUIs, newUI)
        group:AddUI(newUI, true)
        if ui.guidUnit then
            newUI.guidUnit = ui.guidUnit
        elseif unit ~= "target" then
            newUI:Hide()
        end
        -- Preserve test UI state when recreating frames
        if Puppeteer.TestUI then
            newUI.fakeStats = newUI.GenerateFakeStats()
            newUI:Show()
        end
    end

    -- Size and update all elements for the newly created frames
    for _, ui in pairs(group.uis) do
        ui:SizeElements()
        ui:UpdateAll() -- Populate health/power/name text with current data
    end

    Puppeteer.CheckGroup()
    group:UpdateUIPositions()
    group:ApplyProfile()
end

-- Helper function to refresh all frame groups
function RefreshAllFrameGroups()
    if not Puppeteer.UnitFrameGroups then
        return
    end
    for name, group in pairs(Puppeteer.UnitFrameGroups) do
        RefreshFrameGroup(name)
    end
end

function Init()
    TabFrame:SetPoint("CENTER")
        :SetSize(500, 575)
        :SetSimpleBackground(PTGuiComponent.BACKGROUND_DIALOG)
        :SetSpecial()

    if PTOptions.Debug2 then
        TabFrame:Show()
    end

    local title = PTGuiLib.Get("title", TabFrame)
    title:SetPoint("TOP", TabFrame, "TOP", 0, 22)
    title:SetHeight(38)
    title:SetWidth(170)
    title:SetText("Puppeteer Settings")



    local closeButton = CreateFrame("Button", nil, TabFrame:GetHandle(), "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", TabFrame:GetHandle(), "TOPRIGHT", 0, 0)
    closeButton:SetScript("OnClick", function()
        TabFrame:Hide()
    end)

    CreateTab_Bindings()
    CreateTab_Options()
    CreateTab_Customize()
    CreateTab_Profiles()
    CreateTab_About()

    -- Track if profile was switched during this session
    local profileWasSwitched = false

    -- Initialize dirty tracker when settings window is shown
    TabFrame:GetHandle():SetScript("OnShow", function()
        profileWasSwitched = false
        if PTDirtyTracker then
            PTDirtyTracker.Initialize()
        end
    end)

    -- Show reload reminder when closing if profile was switched
    TabFrame:GetHandle():SetScript("OnHide", function()
        if profileWasSwitched then
            local dialog
            dialog = PTGuiLib.Get("simple_dialog", UIParent)
                :SetPoint("CENTER", UIParent, "CENTER")
                :SetTitle("Reload UI")
                :SetText("Profile changes require a UI reload to take full effect.\n\nReload now?")
                :AddButton("Reload UI", function()
                    ReloadUI()
                end)
                :AddButton("Later", function()
                    dialog:Dispose()
                end)
            dialog:Show()
            profileWasSwitched = false
        end
    end)

    -- Expose function to mark profile as switched
    MarkProfileSwitched = function()
        profileWasSwitched = true
    end
end

OverlayStack = {}
OverlayBlockInputs = {}
function AddOverlayFrame(overlayFrame)
    table.insert(OverlayStack, overlayFrame)
    local block = PTGuiLib.Get("puppeteer_input_block", TabFrame)
    block:SetScript("OnMouseDown", TabFrame:GetScript("OnMouseDown"), true)
    block:SetScript("OnMouseUp", TabFrame:GetScript("OnMouseUp"), true)
    table.insert(OverlayBlockInputs, block)
    block:SetFrameLevel(overlayFrame:GetFrameLevel() + (table.getn(OverlayStack) * 200) - 100)
    overlayFrame:SetFrameLevel(overlayFrame:GetFrameLevel() + (table.getn(OverlayStack) * 200))
    PTUtil.FixFrameLevels(overlayFrame:GetHandle())
end

function PopOverlayFrame()
    local index = table.getn(OverlayStack)
    table.remove(OverlayStack, index)
    local block = table.remove(OverlayBlockInputs, index)
    block:Dispose()
end

EditedBindings = {}
BindingsContext = { Target = "Friendly", Modifier = "None" }
function CreateTab_Bindings()
    local container = TabFrame:CreateTab("Bindings")

    -- Profile context label
    local profileLabel = CreateLabel(container, "")
        :SetPoint("TOPRIGHT", container, "TOPRIGHT", -20, -10)
    local function UpdateProfileLabel()
        local profileName = PTProfileData.GetCurrentCharacterProfile()
        profileLabel:SetText(colorize("Profile: " .. profileName, 0.7, 0.7, 0.7))
    end
    UpdateProfileLabel()

    local selectLoadoutLabel = CreateLabel(container, "Select Loadout")
        :SetPoint("TOPLEFT", container, "TOPLEFT", 30, -40)
    local selectLoadoutDropdown = CreateDropdown(container, 130)
        :SetPoint("LEFT", selectLoadoutLabel, "RIGHT", 5, 0)
        :SetDynamicOptions(function(addOption, level, args)
            for _, name in ipairs(Puppeteer.GetBindingLoadoutNames()) do
                addOption("text", name,
                    "checked", Puppeteer.GetSelectedBindingsLoadoutName() == name,
                    "func", args.func)
            end
        end, {
            func = function(self)
                local loadoutName = self.text
                if Puppeteer.LoadoutEquals(Puppeteer.GetBindings(), EditedBindings) then
                    Puppeteer.SetSelectedBindingsLoadout(loadoutName)
                else
                    local dialog
                    dialog = PTGuiLib.Get("simple_dialog", TabFrame)
                        :SetPoint("CENTER", TabFrame, "CENTER")
                        :SetTitle("Unsaved Changes")
                        :SetText("You have unsaved changes to your bindings. What would you like to do?")
                        :AddButton("Save changes & switch", function()
                            SaveBindings()
                            Puppeteer.SetSelectedBindingsLoadout(loadoutName)
                            PopOverlayFrame()
                            dialog:Dispose()
                        end)
                        :AddButton("Discard changes & switch", function()
                            Puppeteer.SetSelectedBindingsLoadout(loadoutName)
                            PopOverlayFrame()
                            dialog:Dispose()
                        end)
                        :AddButton("Carry changes over", function()
                            local editedBindings = EditedBindings
                            Puppeteer.SetSelectedBindingsLoadout(loadoutName)
                            EditedBindings = editedBindings
                            UpdateBindingsInterface()
                            PopOverlayFrame()
                            dialog:Dispose()
                        end)
                        :AddButton("Cancel", function()
                            PopOverlayFrame()
                            dialog:Dispose()
                        end)
                    AddOverlayFrame(dialog)
                    PlaySound("igMainMenuOpen")
                end
            end
        })
        :SetTextUpdater(function(self)
            self:SetText(Puppeteer.GetSelectedBindingsLoadoutName())
        end)
    LoadoutsDropdown = selectLoadoutDropdown
    local newLoadout = PTGuiLib.Get("button", container)
        :SetPoint("LEFT", selectLoadoutDropdown, "RIGHT", 5, 0)
        :SetSize(60, 22)
        :SetText("New")
        :OnClick(function(self)
            if util.GetTableSize(Puppeteer.GetBindingLoadouts()) >= 20 then
                DEFAULT_CHAT_FRAME:AddMessage("You cannot create any more loadouts!")
                return
            end

            if Puppeteer.LoadoutEquals(Puppeteer.GetBindings(), EditedBindings) then
                PromptNewLoadout()
            else
                local dialog
                dialog = PTGuiLib.Get("simple_dialog", TabFrame)
                    :SetPoint("CENTER", TabFrame, "CENTER")
                    :SetTitle("Unsaved Changes")
                    :SetText("You have unsaved changes to your bindings. What would you like to do?")
                    :AddButton("Save changes", function()
                        SaveBindings()
                        PopOverlayFrame()
                        dialog:Dispose()
                        PromptNewLoadout()
                    end)
                    :AddButton("Discard changes", function()
                        LoadBindings()
                        PopOverlayFrame()
                        dialog:Dispose()
                        PromptNewLoadout()
                    end)
                    :AddButton("Cancel", function()
                        PopOverlayFrame()
                        dialog:Dispose()
                    end)
                AddOverlayFrame(dialog)
                PlaySound("igMainMenuOpen")
            end
        end)
    local deleteLoadout = PTGuiLib.Get("button", container)
        :SetPoint("LEFT", newLoadout, "RIGHT", 5, 0)
        :SetSize(60, 22)
        :SetText("Delete")
        :OnClick(function()
            local loadouts = Puppeteer.GetBindingLoadouts()
            local currentLoadoutName = Puppeteer.GetSelectedBindingsLoadoutName()
            local anotherLoadoutName
            for k, v in pairs(loadouts) do
                if k ~= Puppeteer.GetSelectedBindingsLoadoutName() then
                    anotherLoadoutName = k
                    break
                end
            end
            if not anotherLoadoutName then
                DEFAULT_CHAT_FRAME:AddMessage("Cannot delete the only loadout")
                return
            end
            local dialog = PTGuiLib.Get("simple_dialog", TabFrame)
                :SetPoint("CENTER", TabFrame, "CENTER", 0, 40)
            dialog:SetTitle("Confirm Delete")
            dialog:SetText("Are you sure you want to delete binding loadout '" .. currentLoadoutName .. "'?")
            dialog:AddButton("Yes, delete loadout", function()
                dialog:Dispose()
                PopOverlayFrame()
                Puppeteer.SetSelectedBindingsLoadout(anotherLoadoutName)
                loadouts[currentLoadoutName] = nil
            end)
            dialog:AddButton("No, keep loadout", function()
                dialog:Dispose()
                PopOverlayFrame()
            end)
            dialog:PlayOpenSound()
            AddOverlayFrame(dialog)
        end)

    local bindingsForLabel = CreateLabel(container, "Bindings For")
        :SetPoint("TOPLEFT", container, "TOPLEFT", 40, -95)

    local bindingsForDropdown = CreateDropdown(container, 100)
        :SetPoint("LEFT", bindingsForLabel, "RIGHT", 5, 0)
        :SetDynamicOptions(function(addOption, level, args)
            if not EditedBindings.UseFriendlyForHostile then
                for _, option in ipairs(args.options) do
                    addOption("text", option,
                        "dropdownText", option,
                        "initFunc", args.initFunc,
                        "func", args.func)
                end
            end
        end, {
            options = { "Friendly", "Hostile" },
            initFunc = function(self, gui)
                self.checked = self.text == gui:GetText()
            end,
            func = function(self)
                SetTargetContext(self.text)
                UpdateBindingsInterface()
            end
        })
        :SetTextUpdater(function(self)
            self:SetText(EditedBindings.UseFriendlyForHostile and "All Targets" or BindingsContext.Target)
        end)
    BindingsForDropdown = bindingsForDropdown

    local useSame = CreateLabel(container, "Universal Bindings")
        :SetPoint("LEFT", bindingsForDropdown, "RIGHT", 10, 0)
        :ApplyTooltip("Use the same bindings for both friendly and hostile targets")
    local universalBindingsCheckbox = CreateCheckbox(container, 20, 20)
        :SetPoint("LEFT", useSame, "RIGHT", 5, 0)
        :ApplyTooltip("Use the same bindings for both friendly and hostile targets")
        :OnClick(function(self)
            EditedBindings.UseFriendlyForHostile = self:GetChecked() == 1
            SetTargetContext("Friendly")
            UpdateBindingsInterface()
        end)
    UniversalBindingsCheckbox = universalBindingsCheckbox

    local keyLabel = CreateLabel(container, "Key Modifier")
        :SetPoint("TOPLEFT", container, "TOPLEFT", 95, -125)

    local keyDropdown = CreateDropdown(container, 150)
        :SetPoint("LEFT", keyLabel, "RIGHT", 5, 0)
        :SetSimpleOptions(util.GetKeyModifiers(), function(modifier)
            return {
                text = modifier,
                initFunc = function(self, gui)
                    self.checked = self.text == gui:GetText()
                end,
                func = function(self, gui)
                    gui:SetText(self.text)
                    SetModifierContext(self.text)
                    UpdateBindingsInterface()
                end
            }
        end, "None")

    local interface = PTGuiLib.Get("puppeteer_spell_bind_interface", container)
        :SetPoint("TOPLEFT", container, "TOPLEFT", 5, -160)
        :SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -5, 80)

    SpellBindInterface = interface

    LoadBindings()


    local addButton = PTGuiLib.Get("button", container)
        :SetPoint("BOTTOM", container, "BOTTOM", 0, 20)
        :SetSize(200, 25)
        :SetText("Add or Remove Buttons")
        :ApplyTooltip("Edit what buttons you can bind spells to")
        :OnClick(function()
            local editor = PTGuiLib.Get("puppeteer_button_editor", TabFrame)
                :SetPoint("CENTER", TabFrame, "CENTER")
            AddOverlayFrame(editor)
        end)

    local discardButton = PTGuiLib.Get("button", container)
        :SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 10, 50)
        :SetSize(125, 25)
        :SetText("Discard Changes")
        :OnClick(function()
            LoadBindings()
        end)
    local saveAndCloseButton = PTGuiLib.Get("button", container)
        :SetPoint("BOTTOM", container, "BOTTOM", 0, 50)
        :SetSize(125, 25)
        :SetText("Save & Close")
        :OnClick(function()
            SaveBindings()
            TabFrame:Hide()
        end)
    local saveButton = PTGuiLib.Get("button", container)
        :SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -10, 50)
        :SetSize(125, 25)
        :SetText("Save Changes")
        :OnClick(function()
            SaveBindings()
        end)
end

function PromptNewLoadout()
    local newLoadout = PTGuiLib.Get("puppeteer_new_loadout", TabFrame)
        :SetPoint("CENTER", TabFrame, "CENTER")
    AddOverlayFrame(newLoadout)
    PlaySound("igMainMenuOpen")
end

function SetTargetContext(friendlyOrHostile)
    BindingsContext.Target = friendlyOrHostile
    BindingsForDropdown:UpdateText()
end

function SetModifierContext(modifier)
    BindingsContext.Modifier = modifier
end

function SetBindingsContext(friendlyOrHostile, modifier)
    SetTargetContext(friendlyOrHostile)
    SetModifierContext(modifier)
end

function GetBindingsContext()
    local targetBindings = EditedBindings.Bindings[BindingsContext.Target]
    if not targetBindings then
        targetBindings = {}
        EditedBindings.Bindings[BindingsContext.Target] = targetBindings
    end
    local bindings = EditedBindings.Bindings[BindingsContext.Target][BindingsContext.Modifier]
    if not bindings then
        bindings = {}
        EditedBindings.Bindings[BindingsContext.Target][BindingsContext.Modifier] = bindings
    end
    return bindings
end

function UpdateBindingsInterface()
    local bindings = GetBindingsContext()
    for _, button in ipairs(PTOptions.Buttons) do
        if not bindings[button] then
            bindings[button] = {}
        end
    end
    SpellBindInterface:SetBindings(bindings)
end

function ReloadBindingLines()
    SpellBindInterface:ClearSpellLines()
    for _, button in ipairs(PTOptions.Buttons) do
        SpellBindInterface:AddSpellLine(button, PTOptions.ButtonInfo[button].Name or button)
    end
end

function LoadBindings()
    ReloadBindingLines()
    LoadoutsDropdown:UpdateText()
    EditedBindings = util.CloneTable(Puppeteer.GetBindings(), true)
    UniversalBindingsCheckbox:SetChecked(EditedBindings.UseFriendlyForHostile)
    if EditedBindings.UseFriendlyForHostile then
        SetTargetContext("Friendly")
    end
    BindingsForDropdown:UpdateText()
    UpdateBindingsInterface()
end

function SaveBindings()
    Puppeteer.GetBindingLoadouts()[Puppeteer.GetSelectedBindingsLoadoutName()] = Puppeteer.PruneLoadout(EditedBindings)
    LoadBindings()
end

function CreateTab_Options()
    local container = TabFrame:CreateTab("Options")

    -- Profile context label
    local profileLabel = CreateLabel(container, "")
        :SetPoint("TOPRIGHT", container, "TOPRIGHT", -20, -10)
    local function UpdateProfileLabel()
        local profileName = PTProfileData.GetCurrentCharacterProfile()
        profileLabel:SetText(colorize("Profile: " .. profileName, 0.7, 0.7, 0.7))
    end
    UpdateProfileLabel()

    local tabPanel = PTGuiLib.Get("tab_panel", container)
    tabPanel:SetPoint("TOPLEFT", container, "TOPLEFT", 5, -28 - 50)
    tabPanel:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -5, 5)
    tabPanel:SetSimpleBackground()
    container.TabPanel = tabPanel

    CreateTab_Options_Casting(tabPanel)
    CreateTab_Options_SpellsTooltip(tabPanel)
    CreateTab_Options_Other(tabPanel)
    CreateTab_Options_Advanced(tabPanel)
    CreateTab_Options_Mods(tabPanel)
end

function CreateTab_Options_Casting(panel)
    local container = panel:CreateTab("Casting")
    local layout = NewLabeledColumnLayout(container, { 150, 310 }, -20, 10)
    local factory = NewComponentFactory(container, layout)
    container.factory = factory

    factory:dropdown("Cast When (Mouse)", "What mouse button state to start casting spells at", "CastWhen",
        { "Mouse Up", "Mouse Down" }, function()
            for _, ui in ipairs(Puppeteer.AllUnitFrames) do
                ui:RegisterClicks()
            end
        end)
    factory:dropdown("Cast When (Keys)", "What key state to start casting spells at", "CastWhenKey",
        { "Key Up", "Key Down" })
    local resSpell = Puppeteer.ResurrectionSpells[util.GetClass("player")]
    local autoResInfo = not resSpell and "This does nothing for your class" or
        { "Replaces your bound spells with " .. resSpell ..
        " when clicking on a dead ally", "All other types of binds, such as Actions, will not be replaced" }
    factory:checkbox("Auto Resurrect", autoResInfo, "AutoResurrect")
    factory:checkbox("PVP Flag Protection",
        { "Stops you from casting spells on PVP flagged players if you're not flagged",
            "Attempting to cast will prompt you to make an exception",
            "Only stops you from using Spell bindings" }, "PVPFlagProtection")
    factory:checkbox("Target While Casting", { "Target the unit while most bindings run",
        "Note that these binding types override this rule:",
        "Spell - Always targets unless using SuperWoW",
        "Action - Never targets unless specified by action",
        "Item - Always targets",
        "Multi - Never targets" }, "TargetWhileCasting")
    factory:checkbox("Target After Casting", { "Target the unit after most bindings run",
        "Note that these binding types override this rule:",
        "Multi - Never targets" }, "TargetAfterCasting")
end

function CreateTab_Options_SpellsTooltip(panel)
    local container = panel:CreateTab("Spells Tooltip")
    local layout = NewLabeledColumnLayout(container, { 150, 310 }, -20, 10)
    local factory = NewComponentFactory(container, layout)
    container.factory = factory
    factory:checkbox("Enable Spells Tooltip", { "Show the spells tooltip when hovering over unit frames" },
        "SpellsTooltip.Enabled")
    factory:checkbox("Show % Mana Cost", { "Show the percent mana cost in the spells tooltip",
        "Does nothing for non-mana users" }, "SpellsTooltip.ShowManaPercentCost")
    layout:column(2):levelAt(1)
    factory:checkbox("Show # Mana Cost", { "Show the number mana cost in the spells tooltip",
        "Does nothing for non-mana users" }, "SpellsTooltip.ShowManaCost")
    layout:column(1)
    factory:slider("Hide Casts Above", "Hide cast count if above this threshold", "SpellsTooltip.HideCastsAbove", 0, 50)
    factory:slider("Critical Casts Level", "Show yellow text at this threshold", "SpellsTooltip.CriticalCastsLevel", 0,
        50)
    factory:checkbox("Shortened Keys", "Shortens keys to 1 letter", "SpellsTooltip.AbbreviatedKeys")
    layout:column(2):levelAt(1)
    factory:checkbox("Colored Keys", "Color code the keys as opposed to all being white", "SpellsTooltip.ColoredKeys")
    layout:column(1)
    factory:checkbox("Show Power Bar", "Show a power bar in the spells tooltip", "SpellsTooltip.ShowPowerBar", function()
        if PTOptions.SpellsTooltip.ShowPowerBar then
            Puppeteer.SpellsTooltipPowerBar:Show()
        else
            Puppeteer.SpellsTooltipPowerBar:Hide()
        end
    end)
    factory:dropdown("Show Power As", "What type of information to show for power amounts", "SpellsTooltip.ShowPowerAs",
        { "Power", "Power/Max Power", "Power %" })
    factory:dropdown("Attach To", "What the tooltip should be attached to", "SpellsTooltip.AttachTo",
        { "Button", "Frame", "Group", "Screen" })
    layout:offset(0, 10)
    factory:dropdown("Anchor", "Where the tooltip should be anchored", "SpellsTooltip.Anchor",
        { "Top Left", "Top Right", "Bottom Left", "Bottom Right" })
    factory:checkbox("Show Item Count",
        { "Show the amount of your bound items", colorize("Warning: This causes lag!", 1, 0.4, 0.4) },
        "SpellsTooltip.ShowItemCount")
end

function CreateTab_Options_Other(panel)
    local container = panel:CreateTab("Other")
    local layout = NewLabeledColumnLayout(container, { 150, 220, 300 }, -20, 10)
    local factory = NewComponentFactory(container, layout)
    container.factory = factory
    factory:checkbox("Always Show Target", "Always show the target frame, regardless of whether you have a target or not",
        "AlwaysShowTargetFrame", function() Puppeteer.CheckTarget() end)
    layout:offset(0, 10)
    factory:label("Show Targets:")
    layout:column(2):levelAt(1)
    factory:checkbox("Friendly",
        { "Show the Target frame when targeting friendlies", "No effect if Always Show Target is checked" },
        "ShowTargets.Friendly", function() Puppeteer.CheckTarget() end)
    layout:column(3):levelAt(2)
    factory:checkbox("Hostile",
        { "Show the Target frame when targeting hostiles", "No effect if Always Show Target is checked" },
        "ShowTargets.Hostile", function() Puppeteer.CheckTarget() end)
    layout:column(1)
    factory:label("Hide Party Frames:")
    layout:column(2):levelAt(1)
    factory:checkbox("In Party",
        { "Hide default party frames while in party", "This may cause issues with other addons" },
        "DisablePartyFrames.InParty", function() Puppeteer.CheckPartyFramesEnabled() end)
    layout:column(3):levelAt(2)
    factory:checkbox("In Raid", { "Hide default party frames while in raid", "This may cause issues with other addons" },
        "DisablePartyFrames.InRaid", function() Puppeteer.CheckPartyFramesEnabled() end)
    layout:column(1)
    factory:checkbox("Hide While Solo", "If enabled, all Puppeteer frames will be hidden when not in a party or raid",
        "HideWhileSolo", function() Puppeteer.CheckGroup() end)
    local dragAllCheckbox = factory:checkbox("Drag All Frames", { "If enabled, all frames will be moved when dragging",
        "Use the inverse key to move a single frame; Opposite effect if disabled" }, "FrameDrag.MoveAll")
    layout:ignoreNext()
    local inverseDropdown = factory:dropdown("Inverse Key",
        { "This key will be used to do the opposite of the default drag operation" },
        "FrameDrag.AltMoveKey", { "Shift", "Control", "Alt" })
    inverseDropdown:SetWidth(80)
    inverseDropdown:SetPoint("LEFT", dragAllCheckbox, "RIGHT", 90, 0)
    factory:checkbox("Show Heal Predictions",
        { "See predictions on incoming healing", "Improved predictions if using SuperWoW" },
        "UseHealPredictions", function() Puppeteer.UpdateAllIncomingHealing() end)

    factory:checkbox("(TWoW) LFT Auto Role", { "Automatically assign roles when joining LFT groups",
            "This functionality was tested for 1.18.0 and may break in future updates" }, "LFTAutoRole",
        function() Puppeteer.SetLFTAutoRoleEnabled(PTOptions.LFTAutoRole) end)
end

function CreateTab_Options_Advanced(panel)
    local container = panel:CreateTab("Advanced")
    local layout = NewLabeledColumnLayout(container, { 150, 220, 300 }, 0, 10)
    local factory = NewComponentFactory(container, layout)
    container.factory = factory

    local TEXT_WIDTH = 370

    local experimentsLabel = CreateLabel(container, "Experiments")
        :SetPoint("TOP", container, "TOP", 0, -20)
        :SetFontSize(14)
    local experimentsInfo = CreateLabel(container,
            "Features which are not complete and/or need more testing. Use at your own risk.")
        :SetWidth(TEXT_WIDTH)
        :SetPoint("TOP", experimentsLabel, "BOTTOM", 0, -5)
    layout:offset(0, -70)
    factory:checkbox("(TWoW) Auto Role", { "If enabled, the Role Action menu shows auto role detection options",
            colorize("Using this functionality WILL cause errors and other unexpected behavior", 1, 0.4, 0.4) },
        "Global.Experiments.AutoRole",
        Puppeteer.InitRoleDropdown)

    local scriptsLabel = CreateLabel(container, "Load & Postload Scripts")
        :SetPoint("TOP", container, "TOP", 0, -105)
        :SetFontSize(14)

    local loadScriptInfo = CreateLabel(container,
            "The Load Script runs after profiles are initialized, but before UIs are created, " ..
            "making it good for editing profile attributes. GetProfile and CreateProfile are defined locals.")
        :SetWidth(TEXT_WIDTH)
        :SetPoint("TOP", scriptsLabel, "BOTTOM", 0, -10)
    local loadScriptButton = PTGuiLib.Get("button", container)
        :SetPoint("TOP", loadScriptInfo, "BOTTOM", 0, -5)
        :SetSize(150, 20)
        :SetText("Edit Load Script")
        :OnClick(function()
            local editor
            editor = PTGuiLib.Get("puppeteer_load_script_editor", TabFrame)
                :SetPoint("CENTER", TabFrame, "CENTER")
                :SetTitle("Edit Load Script")
            editor:GetEditbox():SetText(PTOptions.Scripts.OnLoad or "")
            editor:SetCallback(function(save, data)
                if save then
                    PTOptions.Scripts.OnLoad = data
                end
                editor:Dispose()
                PopOverlayFrame()
            end)
            editor:GetEditbox():SetFocus()
            AddOverlayFrame(editor)
        end)
    local postLoadScriptInfo = CreateLabel(container, "The Postload Script runs after everything is initialized. " ..
            "GetProfile and CreateProfile are defined locals.")
        :SetWidth(TEXT_WIDTH)
        :SetPoint("TOP", loadScriptButton, "BOTTOM", 0, -10)
    local postLoadScriptButton = PTGuiLib.Get("button", container)
        :SetPoint("TOP", postLoadScriptInfo, "BOTTOM", 0, -5)
        :SetSize(150, 20)
        :SetText("Edit Postload Script")
        :OnClick(function()
            local editor
            editor = PTGuiLib.Get("puppeteer_load_script_editor", TabFrame)
                :SetPoint("CENTER", TabFrame, "CENTER")
                :SetTitle("Edit Postload Script")
            editor:GetEditbox():SetText(PTOptions.Scripts.OnPostLoad or "")
            editor:SetCallback(function(save, data)
                if save then
                    PTOptions.Scripts.OnPostLoad = data
                end
                editor:Dispose()
                PopOverlayFrame()
            end)
            editor:GetEditbox():SetFocus()
            AddOverlayFrame(editor)
        end)
    local reloadInfo = CreateLabel(container, "A reload or relog is required for any script changes to take effect.")
        :SetWidth(TEXT_WIDTH)
        :SetPoint("TOP", postLoadScriptButton, "BOTTOM", 0, -20)
    local reloadButton = PTGuiLib.Get("button", container)
        :SetPoint("TOP", reloadInfo, "BOTTOM", 0, -5)
        :SetSize(120, 20)
        :SetText("Reload UI")
        :OnClick(function()
            ReloadUI()
        end)
end

function CreateTab_Options_Mods(panel)
    local container, scrollFrame = panel:CreateTab("Mods", true)
    local layout = NewLabeledColumnLayout(container, { 150, 310 }, -20, 10)
    local factory = NewComponentFactory(container, layout)
    container.factory = factory

    local TEXT_WIDTH = 370

    local generalInfo = CreateLabel(container,
            "Some client mods enhance your experience with Puppeteer by enabling additional functionality.")
        :SetWidth(TEXT_WIDTH)
        :SetPoint("TOP", container, "TOP", 0, -10)

    local superWowDetected = util.IsSuperWowPresent()
    local unitXPDetected = util.IsUnitXPSP3Present()
    local nampowerDetected = util.IsNampowerPresent()

    local detectedTexts = {
        [true] = colorize("Mod Detected", 0.2, 1, 0.2),
        [false] = colorize("Mod Not Detected", 1, 0.2, 0.2)
    }
    local superWowLabel = CreateLabel(container, "SuperWoW")
        :SetPoint("TOP", generalInfo, "BOTTOM", 0, -20)
        :SetFontSize(14)
    local superWowDetectedLabel = CreateLabel(container, detectedTexts[superWowDetected])
        :SetPoint("TOP", superWowLabel, "BOTTOM", 0, -5)
        :SetFontSize(10)
        :SetFontFlags("OUTLINE")
    local superWowInfo = CreateLabel(container, "SuperWoW provides the following enhancements:\n\n" ..
            "• Enables tracking of many class buff and debuff timers\n" ..
            "• Enhances spell casting by directly casting on targets rather than split-second target switching tricks\n" ..
            "• Allows you to see accurate distance to other friendly players and NPCs\n" ..
            "• Mousing over unit frames properly sets your mouseover target\n" ..
            "• Shows incoming healing from players that do not have HealComm and predicts more accurate numbers\n" ..
            "• Add players/mobs to a separate Focus frame (By using the Focus action bind)")
        :SetJustifyH("LEFT")
        :SetWidth(TEXT_WIDTH)
        :SetPoint("TOP", superWowDetectedLabel, "BOTTOM", 0, -10)
    local superWowLink = CreateLinkEditbox(container, "https://github.com/balakethelock/SuperWoW")
        :SetPoint("TOP", superWowInfo, "BOTTOM", 0, -5)
        :SetSize(300, 20)
    local superWowLinkLabel = CreateLabel(container, "Link:")
        :SetPoint("RIGHT", superWowLink, "LEFT", -5, 0)

    layout:ignoreNext()
    local setMouseoverCheckbox = factory:checkbox("Set Mouseover", { "Requires SuperWoW Mod To Work",
            "If enabled, hovering over frames will set your mouseover target" }, "SetMouseover")
        :SetPoint("TOP", superWowLink, "BOTTOM", 0, -10)
    if not superWowDetected then
        setMouseoverCheckbox:Disable()
    end

    -- UnitXP SP3

    local unitXPLabel = CreateLabel(container, "UnitXP SP3")
        :SetPoint("TOP", setMouseoverCheckbox, "BOTTOM", 0, -20)
        :SetFontSize(14)
    local unitXPDetectedLabel = CreateLabel(container, detectedTexts[unitXPDetected])
        :SetPoint("TOP", unitXPLabel, "BOTTOM", 0, -5)
        :SetFontSize(10)
        :SetFontFlags("OUTLINE")

    local unitXPInfo = CreateLabel(container, "UnitXP SP3 provides the following enhancements:\n\n" ..
            "• Displays when units are out of line-of-sight\n" ..
            "• Allows you to see more accurate distance than SuperWoW and also see distance to enemies")
        :SetJustifyH("LEFT")
        :SetWidth(TEXT_WIDTH)
        :SetPoint("TOP", unitXPDetectedLabel, "BOTTOM", 0, -10)
    local unitXPLink = CreateLinkEditbox(container, "https://github.com/jrc13245/UnitXP_SP3")
        :SetPoint("TOP", unitXPInfo, "BOTTOM", 0, -5)
        :SetSize(300, 20)
    local unitXPLinkLabel = CreateLabel(container, "Link:")
        :SetPoint("RIGHT", unitXPLink, "LEFT", -5, 0)

    -- Nampower

    local nampowerLabel = CreateLabel(container, "Nampower")
        :SetPoint("TOP", unitXPLink, "BOTTOM", 0, -20)
        :SetFontSize(14)
    local nampowerDetectedLabel = CreateLabel(container, detectedTexts[nampowerDetected])
        :SetPoint("TOP", nampowerLabel, "BOTTOM", 0, -5)
        :SetFontSize(10)
        :SetFontFlags("OUTLINE")

    local nampowerInfo = CreateLabel(container, "Nampower provides the following enhancements:\n\n" ..
            "• Allows you to queue spell casts like in modern versions of WoW, drastically increasing casting efficiency")
        :SetJustifyH("LEFT")
        :SetWidth(TEXT_WIDTH)
        :SetPoint("TOP", nampowerDetectedLabel, "BOTTOM", 0, -10)
    local nampowerLink = CreateLinkEditbox(container, "https://github.com/pepopo978/nampower")
        :SetPoint("TOP", nampowerInfo, "BOTTOM", 0, -5)
        :SetSize(300, 20)
    local nampowerLinkLabel = CreateLabel(container, "Link:")
        :SetPoint("RIGHT", nampowerLink, "LEFT", -5, 0)



    scrollFrame:UpdateScrollRange()
end

function CreateTab_Customize()
    local container = TabFrame:CreateTab("Customize")

    -- Profile context label
    local profileLabel = CreateLabel(container, "")
        :SetPoint("TOPRIGHT", container, "TOPRIGHT", -20, -10)
    local function UpdateProfileLabel()
        local profileName = PTProfileData.GetCurrentCharacterProfile()
        profileLabel:SetText(colorize("Profile: " .. profileName, 0.7, 0.7, 0.7))
    end
    UpdateProfileLabel()

    local frameStyleContainer = PTGuiLib.Get("container", container)
        :SetSimpleBackground()
        :SetPoint("TOPLEFT", container, "TOPLEFT", 5, -26)
        :SetPoint("BOTTOMRIGHT", container, "TOPRIGHT", -5, -155)
    local layout = NewLabeledColumnLayout(frameStyleContainer, { 100, 340, 175 }, -25, 5)

    local frameSettingsText = CreateLabel(frameStyleContainer, "Frame Group Settings")
        :SetPoint("TOP", frameStyleContainer, "TOP", 0, -5)
        :SetFontSize(14)


    local preferredFrameOrder = { "Party", "Pets", "Raid", "Raid Pets", "Target", "Focus" }
    local frameDropdown = CreateLabeledDropdown(frameStyleContainer, "Configure Frame",
            "The frame to edit the attributes of")
        :SetWidth(150)
        :SetDynamicOptions(function(addOption, level, args)
            for _, name in ipairs(preferredFrameOrder) do
                if Puppeteer.UnitFrameGroups[name] then
                    addOption("text", name,
                        "dropdownText", name,
                        "initFunc", args.initFunc,
                        "func", args.func)
                end
            end
            for name, group in pairs(Puppeteer.UnitFrameGroups) do
                if not util.ArrayContains(preferredFrameOrder, name) then
                    addOption("text", name,
                        "dropdownText", name,
                        "initFunc", args.initFunc,
                        "func", args.func)
                end
            end
        end, {
            initFunc = function(self, gui)
                self.checked = self.text == gui:GetText()
            end,
            func = function(self, gui)
                StyleDropdown:UpdateText()
                AnchorDropdown:UpdateText()
                UpdateFrameOptions()
                if ShowCategorySection then
                    ShowCategorySection(currentCategory) -- Refresh current category with new frame
                end
            end
        })
        :SetText("Party")
    FrameDropdown = frameDropdown
    layout:column(3):layoutComponent(frameDropdown)

    local GetSelectedProfileName = PuppeteerSettings.GetSelectedProfileName
    local styleDropdown = CreateLabeledDropdown(frameStyleContainer, "Choose Style", "The style of the frame")
        :SetWidth(150)
        :SetDynamicOptions(function(addOption, level, args)
            local profiles = PTProfileManager.GetProfileNames()
            for _, profile in ipairs(profiles) do
                addOption("text", profile,
                    "checked", GetSelectedProfileName(frameDropdown:GetText()) == profile,
                    "func", args.func)
            end
        end, {
            func = function(self, gui)
                local selectedFrame = frameDropdown:GetText()

                -- Use dirty tracker to update both working copy and live options
                if PTDirtyTracker then
                    PTDirtyTracker.SetChosenProfile(selectedFrame, self.text)
                else
                    PTOptions.ChosenProfiles[selectedFrame] = self.text
                end

                if selectedFrame == "Focus" and not util.IsSuperWowPresent() then
                    return
                end

                -- Here's some probably buggy profile hotswapping
                local group = Puppeteer.UnitFrameGroups[selectedFrame]
                group.profile = GetSelectedProfile(selectedFrame)
                local oldUIs = group.uis
                group.uis = {}
                group:ResetFrameLevel() -- Need to lower frame or the added UIs are somehow under it
                for unit, ui in pairs(oldUIs) do
                    ui:GetRootContainer():SetParent(nil)
                    -- Forget about the old UI, and cause a fat memory leak why not
                    ui:GetRootContainer():Hide()
                    local newUI = PTUnitFrame:New(unit, ui.isCustomUnit)
                    util.RemoveElement(Puppeteer.AllUnitFrames, ui)
                    table.insert(Puppeteer.AllUnitFrames, newUI)
                    local unitUIs = Puppeteer.GetUnitFrames(unit)
                    util.RemoveElement(unitUIs, ui)
                    table.insert(unitUIs, newUI)
                    group:AddUI(newUI, true)
                    if ui.guidUnit then
                        newUI.guidUnit = ui.guidUnit
                    elseif unit ~= "target" then
                        newUI:Hide()
                    end
                end
                Puppeteer.CheckGroup()
                group:UpdateUIPositions()
                group:ApplyProfile()

                gui:UpdateText()
            end
        })
        :SetTextUpdater(function(self)
            self:SetText(GetSelectedProfileName(frameDropdown:GetText()))
        end)
    StyleDropdown = styleDropdown
    layout:column(1):offset(0, -30):layoutComponent(styleDropdown)




    local anchors = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
    local readableAnchorMap = {
        TOPLEFT = "Top Left",
        TOP = "Top",
        TOPRIGHT = "Top Right",
        LEFT = "Left",
        CENTER = "Center",
        RIGHT = "Right",
        BOTTOMLEFT = "Bottom Left",
        BOTTOM = "Bottom",
        BOTTOMRIGHT = "Bottom Right"
    }
    local anchorDropdown = CreateLabeledDropdown(frameStyleContainer, "Anchor",
            { "The point the frame is anchored to, affecting the direction it expands/retracts",
                "Top Left: Expands right and down",
                "Top: Expands equally left & right and down",
                "Top Right: Expands left and down",
                "Left: Expands right and equally up & down",
                "Center: Expands equally in all directions",
                "Right: Expands left and equally up & down",
                "Bottom Left: Expands right and up",
                "Bottom: Expands equally left & right and up",
                "Bottom Right: Expands left and up", })
        :SetWidth(150)
        :SetSimpleOptions(anchors, function(option)
            return {
                initFunc = function(self)
                    self.checked = PuppeteerSettings.GetFramePosition(frameDropdown:GetText()) == option
                end,
                func = function(self, gui)
                    local group = Puppeteer.UnitFrameGroups[frameDropdown:GetText()]
                    util.ConvertAnchor(group:GetContainer(), option)
                    PuppeteerSettings.SaveFramePositions()
                    gui:UpdateText()
                end,
                text = readableAnchorMap[option]
            }
        end)
        :SetTextUpdater(function(self)
            self:SetText(readableAnchorMap[PuppeteerSettings.GetFramePosition(frameDropdown:GetText())])
        end)
    layout:layoutComponent(anchorDropdown)
    AnchorDropdown = anchorDropdown

    local lockFrameCheckbox = CreateLabeledCheckbox(frameStyleContainer, "Lock Frame",
            { "If checked, this frame will not be movable",
                "Note: This setting is also accessible by right-clicking the group title bar" })
        :OnClick(function(self)
            local frameName = frameDropdown:GetText()
            PuppeteerSettings.SetFrameLocked(frameName, self:GetChecked() == 1)
        end)
    layout:column(2):offset(0, -30):layoutComponent(lockFrameCheckbox)
    LockFrameCheckbox = lockFrameCheckbox

    local hideTitleCheckbox = CreateLabeledCheckbox(frameStyleContainer, "Hide Title",
            { "If checked, the title of this frame will be hidden",
                colorize("Note: When you want to move the frame, you need to enable the title!", 1, 0.4, 0.4) })
        :OnClick(function(self)
            local frameName = frameDropdown:GetText()
            PuppeteerSettings.SetTitleHidden(frameName, self:GetChecked() == 1)
        end)
    layout:layoutComponent(hideTitleCheckbox)
    HideTitleCheckbox = hideTitleCheckbox

    local hideFrameCheckbox = CreateLabeledCheckbox(frameStyleContainer, "Hide Frame",
            "If checked, this frame will not be visible")
        :OnClick(function(self)
            local frameName = frameDropdown:GetText()
            PuppeteerSettings.SetFrameHidden(frameName, self:GetChecked() == 1)
            Puppeteer.CheckGroup()
        end)
    layout:layoutComponent(hideFrameCheckbox)
    HideFrameCheckbox = hideFrameCheckbox

    UpdateFrameOptions()

    -- Header container for title and category dropdown
    local categoryHeader = PTGuiLib.Get("container", container)
        :SetSimpleBackground()
        :SetPoint("TOPLEFT", frameStyleContainer, "BOTTOMLEFT", 0, -5)
        :SetPoint("TOPRIGHT", container, "TOPRIGHT", -5, -5)
        :SetHeight(80) -- Height to fit title + subtitle + dropdown

    -- Category-based customization section
    categoryContainer = PTGuiLib.Get("scroll_frame", container)
        :SetSimpleBackground()
        :SetPoint("TOPLEFT", categoryHeader, "BOTTOMLEFT", 0, -5)
        :SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -5, 5)

    local categoryTitle = CreateLabel(categoryHeader, "Profile Customization")
        :SetPoint("TOP", categoryHeader, "TOP", 0, -5)
        :SetFontSize(14)

    local categorySubtitle = CreateLabel(categoryHeader, "")
        :SetPoint("TOP", categoryTitle, "BOTTOM", 0, -3)
        :SetFontSize(10)

    -- Track current category
    local currentCategory = "Dimensions"

    -- Forward declare fontDropdown and fontStyleDropdown for broader scope
    local fontDropdown
    local fontStyleDropdown

    -- Create sections for each category (initially all hidden except Dimensions)
    local dimensionsSection = PTGuiLib.Get("container", categoryContainer)
    local colorsSection = PTGuiLib.Get("container", categoryContainer)
    local texturesSection = PTGuiLib.Get("container", categoryContainer)
    local displaysSection = PTGuiLib.Get("container", categoryContainer)
    local layoutsSection = PTGuiLib.Get("container", categoryContainer)
    local fontsSection = PTGuiLib.Get("container", categoryContainer)

    -- Position all sections in the same place (anchor to scroll frame for proper scrolling)
    for _, section in ipairs({ dimensionsSection, colorsSection, texturesSection, displaysSection, layoutsSection, fontsSection }) do
        section:SetPoint("TOP", categoryContainer, "TOP", 0, -10)
        section:SetPoint("LEFT", categoryContainer, "LEFT", 5, 0)
        section:SetPoint("RIGHT", categoryContainer, "RIGHT", -5, 0)
        -- Remove fixed height to allow natural sizing like SpellBindInterface
    end

    -- Show/hide function for category sections
    function ShowCategorySection(categoryName)
        if categoryName then
            currentCategory = categoryName
            -- Update dropdown text to match selected category
            if categoryDropdown then
                categoryDropdown:SetText(categoryName)
            end
        end

        local selectedFrame = FrameDropdown:GetText()
        local profileName = PuppeteerSettings.GetSelectedProfileName(selectedFrame)
        categorySubtitle:SetText("Editing profile: " .. profileName)

        dimensionsSection:Hide()
        colorsSection:Hide()
        texturesSection:Hide()
        displaysSection:Hide()
        layoutsSection:Hide()
        fontsSection:Hide()

        if currentCategory == "Dimensions" then
            dimensionsSection:Show()
            if UpdateDimensionSliders then UpdateDimensionSliders() end
        elseif currentCategory == "Colors" then
            colorsSection:Show()
            if UpdateColorDropdowns then UpdateColorDropdowns() end
        elseif currentCategory == "Textures" then
            texturesSection:Show()
            if UpdateTextureDropdowns then UpdateTextureDropdowns() end
        elseif currentCategory == "Displays" then
            displaysSection:Show()
            if UpdateDisplaysSection then UpdateDisplaysSection() end
        elseif currentCategory == "Layouts" then
            layoutsSection:Show()
            if UpdateLayoutsSection then UpdateLayoutsSection() end
         elseif currentCategory == "Fonts" then
             fontsSection:Hide() -- Force a redraw
             fontsSection:Show()
             if UpdateFontsSection then UpdateFontsSection() end
         end

          -- Update scroll area to fit the new content
          if categoryContainer then
              categoryContainer:UpdateScrollChildRect()
          end
          if categoryDropdown then
              categoryDropdown:UpdateText()
          end
     end

    -- Category dropdown
    local categoryDropdown = CreateLabeledDropdown(categoryHeader, "Category", "Choose what to customize")
        :SetWidth(150)
        :SetPoint("TOP", categorySubtitle, "BOTTOM", 0, -10)
        :SetDynamicOptions(function(addOption, level, args)
            addOption("text", "Dimensions", "dropdownText", "Dimensions", "func", args.func)
            addOption("text", "Colors", "dropdownText", "Colors", "func", args.func)
            addOption("text", "Textures", "dropdownText", "Textures", "func", args.func)
            addOption("text", "Displays", "dropdownText", "Displays", "func", args.func)
            addOption("text", "Layouts", "dropdownText", "Layouts", "func", args.func)
            addOption("text", "Fonts", "dropdownText", "Fonts", "func", args.func)
        end, {
            func = function(self, gui)
                ShowCategorySection(self.text)
            end
        })
        :SetText(currentCategory)

    -- Build Dimensions section content
    do
        local section = dimensionsSection

        -- Width slider
        local widthSlider = CreateLabeledSlider(section, "Width", "The width of the frame")
            :SetPoint("TOP", section, "TOP", 0, -10)
            :SetMinMaxValues(50, 300)
            :SetValueStep(1)
        widthSlider:GetSlider():SetNumberedText()
        local widthScript = widthSlider:GetSlider():GetScript("OnValueChanged")
        widthSlider:GetSlider():SetScript("OnValueChanged", function(self)
            widthScript()
            local selectedFrame = FrameDropdown:GetText()
            local profileName = PuppeteerSettings.GetSelectedProfileName(selectedFrame)
            if not PTGlobalProfiles.StyleOverrides[profileName] then
                PTGlobalProfiles.StyleOverrides[profileName] = {}
            end
            PTGlobalProfiles.StyleOverrides[profileName].Width = self:GetValue()
            PTProfileManager.ApplyOverrides(profileName)
            local profile = GetSelectedProfile(selectedFrame)
            RefreshFrameGroup(selectedFrame)
            -- Mark as dirty for unsaved changes tracking
            if PTDirtyTracker then PTDirtyTracker.MarkDirty() end
        end)

        -- Health Bar Height slider
        local healthHeightSlider = CreateLabeledSlider(section, "Health Bar Height", "The height of the health bar")
            :SetPoint("TOP", widthSlider, "BOTTOM", 0, -15)
            :SetMinMaxValues(5, 100)
            :SetValueStep(1)
        healthHeightSlider:GetSlider():SetNumberedText()
        local healthHeightScript = healthHeightSlider:GetSlider():GetScript("OnValueChanged")
        healthHeightSlider:GetSlider():SetScript("OnValueChanged", function(self)
            healthHeightScript()
            local selectedFrame = FrameDropdown:GetText()
            local profileName = PuppeteerSettings.GetSelectedProfileName(selectedFrame)
            if not PTGlobalProfiles.StyleOverrides[profileName] then
                PTGlobalProfiles.StyleOverrides[profileName] = {}
            end
            PTGlobalProfiles.StyleOverrides[profileName].HealthBarHeight = self:GetValue()
            PTProfileManager.ApplyOverrides(profileName)
            local profile = GetSelectedProfile(selectedFrame)
            RefreshFrameGroup(selectedFrame)
        end)

        -- Power Bar Height slider
        local powerHeightSlider = CreateLabeledSlider(section, "Power Bar Height", "The height of the power bar")
            :SetPoint("TOP", healthHeightSlider, "BOTTOM", 0, -15)
            :SetMinMaxValues(0, 30)
            :SetValueStep(1)
        powerHeightSlider:GetSlider():SetNumberedText()
        local powerHeightScript = powerHeightSlider:GetSlider():GetScript("OnValueChanged")
        powerHeightSlider:GetSlider():SetScript("OnValueChanged", function(self)
            powerHeightScript()
            local selectedFrame = FrameDropdown:GetText()
            local profileName = PuppeteerSettings.GetSelectedProfileName(selectedFrame)
            if not PTGlobalProfiles.StyleOverrides[profileName] then
                PTGlobalProfiles.StyleOverrides[profileName] = {}
            end
            PTGlobalProfiles.StyleOverrides[profileName].PowerBarHeight = self:GetValue()
            PTProfileManager.ApplyOverrides(profileName)
            local profile = GetSelectedProfile(selectedFrame)
            RefreshFrameGroup(selectedFrame)
        end)

        -- Update function
        function UpdateDimensionSliders()
            local selectedFrame = FrameDropdown:GetText()
            local profile = GetSelectedProfile(selectedFrame)
            widthSlider:SetValue(profile.Width or 150)
            healthHeightSlider:SetValue(profile.HealthBarHeight or 24)
            powerHeightSlider:SetValue(profile.PowerBarHeight or 10)
        end
    end

    -- Build Colors section content
    do
        local section = colorsSection

        -- Name Text Color
        local nameColorDropdown = CreateLabeledDropdown(section, "Name Text Color", "Color of unit names")
            :SetWidth(150)
            :SetPoint("TOP", section, "TOP", 0, -10)
            :SetDynamicOptions(function(addOption, level, args)
                for _, colorName in ipairs(Puppeteer.ColorPaletteOrder) do
                    addOption("text", colorName,
                        "dropdownText", Puppeteer.GetColorPreviewString(colorName, colorName),
                        "initFunc", args.initFunc,
                        "func", args.func)
                end
            end, {
                initFunc = function(self, gui)
                    local selectedFrame = FrameDropdown:GetText()
                    local profile = GetSelectedProfile(selectedFrame)
                    local currentColor = profile.NameText.Color or "Class"
                    self.checked = self.text == currentColor
                end,
                func = function(self, gui)
                    local selectedFrame = FrameDropdown:GetText()
                    local profileName = PuppeteerSettings.GetSelectedProfileName(selectedFrame)
                    if not PTGlobalProfiles.StyleOverrides[profileName] then
                        PTGlobalProfiles.StyleOverrides[profileName] = {}
                    end
                    SetStyleOverride(PTGlobalProfiles.StyleOverrides[profileName], "NameText.Color", self.text)
                    PTProfileManager.ApplyOverrides(profileName)
                    RefreshFrameGroup(selectedFrame)
                    gui:UpdateText()
                end
            })
            :SetTextUpdater(function(self)
                local selectedFrame = FrameDropdown:GetText()
                local profile = GetSelectedProfile(selectedFrame)
                local colorName = profile.NameText.Color or "Class"
                self:SetText(Puppeteer.GetColorPreviewString(colorName, colorName))
            end)

        -- Health Text Color
        local healthColorDropdown = CreateLabeledDropdown(section, "Health Text Color", "Color of health numbers")
            :SetWidth(150)
            :SetPoint("TOP", nameColorDropdown, "BOTTOM", 0, -15)
            :SetDynamicOptions(function(addOption, level, args)
                for _, colorName in ipairs(Puppeteer.ColorPaletteOrder) do
                    addOption("text", colorName,
                        "dropdownText", Puppeteer.GetColorPreviewString(colorName, colorName),
                        "initFunc", args.initFunc,
                        "func", args.func)
                end
            end, {
                initFunc = function(self, gui)
                    local selectedFrame = FrameDropdown:GetText()
                    local profile = GetSelectedProfile(selectedFrame)
                    local currentColor = profile.HealthTexts.Normal.Color or "White"
                    self.checked = self.text == currentColor
                end,
                func = function(self, gui)
                    local selectedFrame = FrameDropdown:GetText()
                    local profileName = PuppeteerSettings.GetSelectedProfileName(selectedFrame)
                    if not PTGlobalProfiles.StyleOverrides[profileName] then
                        PTGlobalProfiles.StyleOverrides[profileName] = {}
                    end
                    SetStyleOverride(PTGlobalProfiles.StyleOverrides[profileName], "HealthTexts.Normal.Color", self.text)
                    SetStyleOverride(PTGlobalProfiles.StyleOverrides[profileName], "HealthTexts.WithMissing.Color",
                        self.text)
                    PTProfileManager.ApplyOverrides(profileName)
                    RefreshFrameGroup(selectedFrame)
                    gui:UpdateText()
                end
            })
            :SetTextUpdater(function(self)
                local selectedFrame = FrameDropdown:GetText()
                local profile = GetSelectedProfile(selectedFrame)
                local colorName = profile.HealthTexts.Normal.Color or "White"
                self:SetText(Puppeteer.GetColorPreviewString(colorName, colorName))
            end)

        -- Missing Health Color
        local missingHealthColorDropdown = CreateLabeledDropdown(section, "Missing Health Color",
                "Color of missing health text")
            :SetWidth(150)
            :SetPoint("TOP", healthColorDropdown, "BOTTOM", 0, -15)
            :SetDynamicOptions(function(addOption, level, args)
                for _, colorName in ipairs(Puppeteer.ColorPaletteOrder) do
                    addOption("text", colorName,
                        "dropdownText", Puppeteer.GetColorPreviewString(colorName, colorName),
                        "initFunc", args.initFunc,
                        "func", args.func)
                end
            end, {
                initFunc = function(self, gui)
                    local selectedFrame = FrameDropdown:GetText()
                    local profile = GetSelectedProfile(selectedFrame)
                    local currentColor = profile.HealthTexts.Missing.Color or "Red"
                    self.checked = self.text == currentColor
                end,
                func = function(self, gui)
                    local selectedFrame = FrameDropdown:GetText()
                    local profileName = PuppeteerSettings.GetSelectedProfileName(selectedFrame)
                    if not PTGlobalProfiles.StyleOverrides[profileName] then
                        PTGlobalProfiles.StyleOverrides[profileName] = {}
                    end
                    SetStyleOverride(PTGlobalProfiles.StyleOverrides[profileName], "HealthTexts.Missing.Color", self
                        .text)
                    PTProfileManager.ApplyOverrides(profileName)
                    RefreshFrameGroup(selectedFrame)
                    gui:UpdateText()
                end
            })
            :SetTextUpdater(function(self)
                local selectedFrame = FrameDropdown:GetText()
                local profile = GetSelectedProfile(selectedFrame)
                local colorName = profile.HealthTexts.Missing.Color or "Red"
                self:SetText(Puppeteer.GetColorPreviewString(colorName, colorName))
            end)

        -- Power Text Color
        local powerColorDropdown = CreateLabeledDropdown(section, "Power Text Color", "Color of power/mana numbers")
            :SetWidth(150)
            :SetPoint("TOP", missingHealthColorDropdown, "BOTTOM", 0, -15)
            :SetDynamicOptions(function(addOption, level, args)
                for _, colorName in ipairs(Puppeteer.ColorPaletteOrder) do
                    addOption("text", colorName,
                        "dropdownText", Puppeteer.GetColorPreviewString(colorName, colorName),
                        "initFunc", args.initFunc,
                        "func", args.func)
                end
            end, {
                initFunc = function(self, gui)
                    local selectedFrame = FrameDropdown:GetText()
                    local profile = GetSelectedProfile(selectedFrame)
                    local currentColor = profile.PowerText.Color or "White"
                    self.checked = self.text == currentColor
                end,
                func = function(self, gui)
                    local selectedFrame = FrameDropdown:GetText()
                    local profileName = PuppeteerSettings.GetSelectedProfileName(selectedFrame)
                    if not PTGlobalProfiles.StyleOverrides[profileName] then
                        PTGlobalProfiles.StyleOverrides[profileName] = {}
                    end
                    SetStyleOverride(PTGlobalProfiles.StyleOverrides[profileName], "PowerText.Color", self.text)
                    PTProfileManager.ApplyOverrides(profileName)
                    RefreshFrameGroup(selectedFrame)
                    gui:UpdateText()
                end
            })
            :SetTextUpdater(function(self)
                local selectedFrame = FrameDropdown:GetText()
                local profile = GetSelectedProfile(selectedFrame)
                local colorName = profile.PowerText.Color or "White"
                self:SetText(Puppeteer.GetColorPreviewString(colorName, colorName))
            end)

        -- Health Bar Color
        local healthBarColorDropdown = CreateLabeledDropdown(section, "Health Bar Color", "How the health bar is colored")
            :SetWidth(150)
            :SetPoint("TOP", powerColorDropdown, "BOTTOM", 0, -15)
            :SetDynamicOptions(function(addOption, level, args)
                local options = { "Green To Red", "Green", "Class" }
                for _, option in ipairs(options) do
                    addOption("text", option,
                        "initFunc", args.initFunc,
                        "func", args.func)
                end
            end, {
                initFunc = function(self, gui)
                    local selectedFrame = FrameDropdown:GetText()
                    local profile = GetSelectedProfile(selectedFrame)
                    self.checked = self.text == (profile.HealthBarColor or "Green To Red")
                end,
                func = function(self, gui)
                    local selectedFrame = FrameDropdown:GetText()
                    local profileName = PuppeteerSettings.GetSelectedProfileName(selectedFrame)
                    if not PTGlobalProfiles.StyleOverrides[profileName] then
                        PTGlobalProfiles.StyleOverrides[profileName] = {}
                    end
                    PTGlobalProfiles.StyleOverrides[profileName].HealthBarColor = self.text
                    PTProfileManager.ApplyOverrides(profileName)
                    RefreshFrameGroup(selectedFrame)
                    gui:UpdateText()
                end
            })
            :SetTextUpdater(function(self)
                local selectedFrame = FrameDropdown:GetText()
                local profile = GetSelectedProfile(selectedFrame)
                self:SetText(profile.HealthBarColor or "Green To Red")
            end)

        -- Show Debuff Colors On
        local showDebuffColorsDropdown = CreateLabeledDropdown(section, "Show Debuff Colors On",
                "Where to show debuff type colors")
            :SetWidth(150)
            :SetPoint("TOP", healthBarColorDropdown, "BOTTOM", 0, -15)
            :SetDynamicOptions(function(addOption, level, args)
                local options = { "Health Bar", "Name", "Health", "Hidden" }
                for _, option in ipairs(options) do
                    addOption("text", option,
                        "initFunc", args.initFunc,
                        "func", args.func)
                end
            end, {
                initFunc = function(self, gui)
                    local selectedFrame = FrameDropdown:GetText()
                    local profile = GetSelectedProfile(selectedFrame)
                    self.checked = self.text == (profile.ShowDebuffColorsOn or "Hidden")
                end,
                func = function(self, gui)
                    local selectedFrame = FrameDropdown:GetText()
                    local profileName = PuppeteerSettings.GetSelectedProfileName(selectedFrame)
                    if not PTGlobalProfiles.StyleOverrides[profileName] then
                        PTGlobalProfiles.StyleOverrides[profileName] = {}
                    end
                    PTGlobalProfiles.StyleOverrides[profileName].ShowDebuffColorsOn = self.text
                    PTProfileManager.ApplyOverrides(profileName)
                    RefreshFrameGroup(selectedFrame)
                    gui:UpdateText()
                end
            })
            :SetTextUpdater(function(self)
                local selectedFrame = FrameDropdown:GetText()
                local profile = GetSelectedProfile(selectedFrame)
                self:SetText(profile.ShowDebuffColorsOn or "Hidden")
            end)

        -- Update function
        function UpdateColorDropdowns()
            nameColorDropdown:UpdateText()
            healthColorDropdown:UpdateText()
            missingHealthColorDropdown:UpdateText()
            powerColorDropdown:UpdateText()
            healthBarColorDropdown:UpdateText()
            showDebuffColorsDropdown:UpdateText()
        end
    end

    -- Build Textures section content
    do
        local section = texturesSection

        -- Health Bar Texture dropdown
        local healthBarTextureDropdown = CreateLabeledDropdown(section, "Health Bar Texture", "Texture for health bars")
            :SetWidth(200)
            :SetPoint("TOP", section, "TOP", 0, -10)
            :SetDynamicOptions(function(addOption, level, args)
                for name, path in pairs(Puppeteer.BarStyles) do
                    addOption("text", name,
                        "dropdownText", name,
                        "initFunc", args.initFunc,
                        "func", args.func)
                end
            end, {
                initFunc = function(self, gui)
                    local selectedFrame = FrameDropdown:GetText()
                    local profile = GetSelectedProfile(selectedFrame)
                    self.checked = self.text == profile.HealthBarStyle
                end,
                func = function(self, gui)
                    local selectedFrame = FrameDropdown:GetText()
                    local profileName = PuppeteerSettings.GetSelectedProfileName(selectedFrame)
                    if not PTGlobalProfiles.StyleOverrides[profileName] then
                        PTGlobalProfiles.StyleOverrides[profileName] = {}
                    end
                    PTGlobalProfiles.StyleOverrides[profileName].HealthBarStyle = self.text
                    PTProfileManager.ApplyOverrides(profileName)
                    RefreshFrameGroup(selectedFrame)
                    gui:UpdateText()
                end
            })
            :SetTextUpdater(function(self)
                local selectedFrame = FrameDropdown:GetText()
                local profile = GetSelectedProfile(selectedFrame)
                self:SetText(profile.HealthBarStyle or "Puppeteer")
            end)

        -- Power Bar Texture dropdown
        local powerBarTextureDropdown = CreateLabeledDropdown(section, "Power Bar Texture", "Texture for power bars")
            :SetWidth(200)
            :SetPoint("TOP", healthBarTextureDropdown, "BOTTOM", 0, -15)
            :SetDynamicOptions(function(addOption, level, args)
                for name, path in pairs(Puppeteer.BarStyles) do
                    addOption("text", name,
                        "dropdownText", name,
                        "initFunc", args.initFunc,
                        "func", args.func)
                end
            end, {
                initFunc = function(self, gui)
                    local selectedFrame = FrameDropdown:GetText()
                    local profile = GetSelectedProfile(selectedFrame)
                    self.checked = self.text == profile.PowerBarStyle
                end,
                func = function(self, gui)
                    local selectedFrame = FrameDropdown:GetText()
                    local profileName = PuppeteerSettings.GetSelectedProfileName(selectedFrame)
                    if not PTGlobalProfiles.StyleOverrides[profileName] then
                        PTGlobalProfiles.StyleOverrides[profileName] = {}
                    end
                    PTGlobalProfiles.StyleOverrides[profileName].PowerBarStyle = self.text
                    PTProfileManager.ApplyOverrides(profileName)
                    RefreshFrameGroup(selectedFrame)
                    gui:UpdateText()
                end
            })
            :SetTextUpdater(function(self)
                local selectedFrame = FrameDropdown:GetText()
                local profile = GetSelectedProfile(selectedFrame)
                self:SetText(profile.PowerBarStyle or "Puppeteer Borderless")
            end)

        -- Update function
        function UpdateTextureDropdowns()
            healthBarTextureDropdown:UpdateText()
            powerBarTextureDropdown:UpdateText()
        end
    end

    -- Build Displays section content
    do
        local section = displaysSection

        -- Helper to create a display dropdown
        local function CreateDisplayDropdown(parent, label, tooltip, property, options, yOffset, defaultValue)
            local dropdown = CreateLabeledDropdown(parent, label, tooltip)
                :SetWidth(200)
                :SetPoint("TOP", parent, "TOP", 0, yOffset)
                :SetDynamicOptions(function(addOption, level, args)
                    for _, option in ipairs(options) do
                        addOption("text", option,
                            "initFunc", args.initFunc,
                            "func", args.func)
                    end
                end, {
                    initFunc = function(self, gui)
                        local selectedFrame = FrameDropdown:GetText()
                        local profile = GetSelectedProfile(selectedFrame)
                        self.checked = self.text == (profile[property] or defaultValue)
                    end,
                    func = function(self, gui)
                        local selectedFrame = FrameDropdown:GetText()
                        local profileName = PuppeteerSettings.GetSelectedProfileName(selectedFrame)
                        if not PTGlobalProfiles.StyleOverrides[profileName] then
                            PTGlobalProfiles.StyleOverrides[profileName] = {}
                        end
                        PTGlobalProfiles.StyleOverrides[profileName][property] = self.text
                        PTProfileManager.ApplyOverrides(profileName)
                        RefreshFrameGroup(selectedFrame)
                        gui:UpdateText()
                    end
                })
                :SetTextUpdater(function(self)
                    local selectedFrame = FrameDropdown:GetText()
                    local profile = GetSelectedProfile(selectedFrame)
                    self:SetText(profile[property] or defaultValue)
                end)
            return dropdown
        end

        -- Health Display
        local healthDisplayDropdown = CreateDisplayDropdown(section, "Health Display",
            "What kind of text is displayed as health",
            "HealthDisplay",
            { "Health", "Health/Max Health", "% Health", "Hidden" },
            -10,
            "Health")

        -- Missing Health Display
        local missingHealthDisplayDropdown = CreateDisplayDropdown(section, "Missing Health Display",
            "What kind of text is displayed as missing health",
            "MissingHealthDisplay",
            { "-Health", "-% Health", "Hidden" },
            -55,
            "-Health")

        -- Power Display
        local powerDisplayDropdown = CreateDisplayDropdown(section, "Power Display",
            "What kind of text is displayed as power",
            "PowerDisplay",
            { "Power", "Power/Max Power", "% Power", "Hidden" },
            -100,
            "Power")

        -- Incoming Heal Display
        local incomingHealDisplayDropdown = CreateDisplayDropdown(section, "Incoming Heal Display",
            "Show incoming heals on units",
            "IncomingHealDisplay",
            { "Overheal", "Heal", "Hidden" },
            -145,
            "Hidden")

        -- Out of Range Opacity
        local outOfRangeOpacityDropdown = CreateDisplayDropdown(section, "Out of Range Opacity",
            "How opaque out of range players appear in %",
            "OutOfRangeOpacity",
            { 0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100 },
            -190,
            50)

        -- Update function
        function UpdateDisplaysSection()
            healthDisplayDropdown:UpdateText()
            missingHealthDisplayDropdown:UpdateText()
            powerDisplayDropdown:UpdateText()
            incomingHealDisplayDropdown:UpdateText()
            outOfRangeOpacityDropdown:UpdateText()
        end
    end

    -- Build Layouts section content
    do
        local section = layoutsSection

        -- Helper to create a layout dropdown
        local function CreateLayoutDropdown(parent, label, tooltip, property, options, yOffset, defaultValue)
            local dropdown = CreateLabeledDropdown(parent, label, tooltip)
                :SetWidth(200)
                :SetPoint("TOP", parent, "TOP", 0, yOffset)
                :SetDynamicOptions(function(addOption, level, args)
                    for _, option in ipairs(options) do
                        addOption("text", tostring(option),
                            "initFunc", args.initFunc,
                            "func", args.func)
                    end
                end, {
                    initFunc = function(self, gui)
                        local selectedFrame = FrameDropdown:GetText()
                        local profile = GetSelectedProfile(selectedFrame)
                        self.checked = self.text == tostring(profile[property] or defaultValue)
                    end,
                    func = function(self, gui)
                        local selectedFrame = FrameDropdown:GetText()
                        local profileName = PuppeteerSettings.GetSelectedProfileName(selectedFrame)
                        if not PTGlobalProfiles.StyleOverrides[profileName] then
                            PTGlobalProfiles.StyleOverrides[profileName] = {}
                        end
                        -- Convert to number if the option looks like a number
                        local value = tonumber(self.text) or self.text
                        PTGlobalProfiles.StyleOverrides[profileName][property] = value
                        PTProfileManager.ApplyOverrides(profileName)
                        RefreshFrameGroup(selectedFrame)
                        gui:UpdateText()
                    end
                })
                :SetTextUpdater(function(self)
                    local selectedFrame = FrameDropdown:GetText()
                    local profile = GetSelectedProfile(selectedFrame)
                    self:SetText(tostring(profile[property] or defaultValue))
                end)
            return dropdown
        end

        -- Sort Units By
        local sortUnitsDropdown = CreateLayoutDropdown(section, "Sort Units By",
            "The sorting algorithm for units in a group",
            "SortUnitsBy",
            { "ID", "Name", "Class Name" },
            -10,
            "ID")

        -- Growth Orientation
        local orientationDropdown = CreateLayoutDropdown(section, "Growth Orientation",
            "Vertical grows units up and down, Horizontal grows units left and right",
            "Orientation",
            { "Vertical", "Horizontal" },
            -55,
            "Vertical")

        -- Border Style
        local borderStyleDropdown = CreateLayoutDropdown(section, "Border Style",
            "The border of the group",
            "BorderStyle",
            { "Tooltip", "Dialog Box", "Borderless" },
            -100,
            "Tooltip")

        -- Max Units In Axis
        local maxUnitsInAxisDropdown = CreateLayoutDropdown(section, "Max Units In Axis",
            "The maximum number of units in the growth axis until it must shift down",
            "MaxUnitsInAxis",
            { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 },
            -145,
            5)

        -- Min Units X
        local minUnitsXDropdown = CreateLayoutDropdown(section, "Min Units X",
            "The minimum amount of unit space to take on the X-axis",
            "MinUnitsX",
            { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 },
            -190,
            0)

        -- Min Units Y
        local minUnitsYDropdown = CreateLayoutDropdown(section, "Min Units Y",
            "The minimum amount of unit space to take on the Y-axis",
            "MinUnitsY",
            { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 },
            -235,
            0)

        -- Horizontal Spacing
        local horizontalSpacingDropdown = CreateLayoutDropdown(section, "Horizontal Spacing",
            "The number of pixels between units",
            "HorizontalSpacing",
            { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 },
            -280,
            0)

        -- Vertical Spacing
        local verticalSpacingDropdown = CreateLayoutDropdown(section, "Vertical Spacing",
            "The number of pixels between units",
            "VerticalSpacing",
            { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 },
            -325,
            0)

        -- Update function
        function UpdateLayoutsSection()
            sortUnitsDropdown:UpdateText()
            orientationDropdown:UpdateText()
            borderStyleDropdown:UpdateText()
            maxUnitsInAxisDropdown:UpdateText()
            minUnitsXDropdown:UpdateText()
            minUnitsYDropdown:UpdateText()
            horizontalSpacingDropdown:UpdateText()
            verticalSpacingDropdown:UpdateText()
        end
    end

    -- Build Fonts section content
    do
        local section = fontsSection

        local fontTitle = CreateLabel(section, "Global Font Settings")
            :SetPoint("TOP", section, "TOP", 0, -10)
            :SetFontSize(12)

        local fontSubtitle = CreateLabel(section, "Font applies to all text elements")
            :SetPoint("TOP", fontTitle, "BOTTOM", 0, -5)
            :SetFontSize(10)

        -- Font dropdown
        fontDropdown = CreateLabeledDropdown(section, "Font Family", "The font used for all text")
            :SetWidth(200)
            :SetPoint("TOP", fontSubtitle, "BOTTOM", 0, -15)
            :SetDynamicOptions(function(addOption, level, args)
                for name, path in pairs(Puppeteer.AvailableFonts) do
                    -- Capture path in a local variable to avoid closure issues
                    local fontPath = path
                    addOption("text", name,
                        "dropdownText", name,
                        "checked", PTGlobalOptions and PTGlobalOptions.GlobalFont == fontPath,
                        "func", function(self)
                            if PTGlobalOptions then
                                PTGlobalOptions.GlobalFont = fontPath
                                RefreshAllFrameGroups()
                                if fontDropdown then
                                    fontDropdown:UpdateText()
                                end
                            end
                        end)
                end
            end, {})
            :SetTextUpdater(function(self)
                local currentFont = (PTGlobalOptions and PTGlobalOptions.GlobalFont) or "Fonts\\FRIZQT__.TTF"
                for name, path in pairs(Puppeteer.AvailableFonts) do
                    if path == currentFont then
                        self:SetText(name)
                        return
                    end
                end
                self:SetText("FRIZQT (Default)")
            end)

        -- Font style dropdown
        fontStyleDropdown = CreateLabeledDropdown(section, "Font Style", "Text rendering style")
            :SetWidth(200)
            :SetPoint("TOP", fontDropdown, "BOTTOM", 0, -15)
            :SetSimpleOptions({ "None", "Outline", "Thick Outline", "Monochrome" }, function(option)
                local flagMap = {
                    ["None"] = nil,
                    ["Outline"] = "OUTLINE",
                    ["Thick Outline"] = "THICKOUTLINE",
                    ["Monochrome"] = "MONOCHROME"
                }
                local flag = flagMap[option]
                return {
                    text = option,
                    initFunc = function(self)
                        local currentFlag = (PTGlobalOptions and PTGlobalOptions.GlobalFontFlags) or nil
                        self.checked = currentFlag == flag
                    end,
                    func = function(self)
                        if PTGlobalOptions then
                            PTGlobalOptions.GlobalFontFlags = flag
                            RefreshAllFrameGroups()
                            if fontStyleDropdown then
                                fontStyleDropdown:UpdateText()
                            end
                        end
                    end
                }
            end)
            :SetTextUpdater(function(self)
                local currentFlag = (PTGlobalOptions and PTGlobalOptions.GlobalFontFlags) or nil
                local flagToName = {
                    ["OUTLINE"] = "Outline",
                    ["THICKOUTLINE"] = "Thick Outline",
                    ["MONOCHROME"] = "Monochrome"
                }
                self:SetText(flagToName[currentFlag] or "None")
            end)

        -- Preview text
        local preview = CreateLabel(section, "The quick brown fox jumps over the lazy dog")
            :SetPoint("TOP", fontStyleDropdown, "BOTTOM", 0, -20)
            :SetFontSize(12)

        -- Text Size Controls
        local textSizeTitle = CreateLabel(section, "Text Size Per Category")
            :SetPoint("TOP", preview, "BOTTOM", 0, -25)
            :SetFontSize(12)

        local textSizeSubtitle = CreateLabel(section, "Adjust font size for each text element")
            :SetPoint("TOP", textSizeTitle, "BOTTOM", 0, -5)
            :SetFontSize(10)

        -- Helper function to create text size slider
        local function CreateTextSizeSlider(anchorElement, label, tooltip, overridePath, getValue, setValue, yOffset)
            local slider = CreateLabeledSlider(section, label, tooltip)
                :SetPoint("TOP", anchorElement, "BOTTOM", 0, yOffset)
                :SetMinMaxValues(1, 64)
                :SetValueStep(1)
            slider:GetSlider():SetNumberedText()
            local sliderScript = slider:GetSlider():GetScript("OnValueChanged")
            slider:GetSlider():SetScript("OnValueChanged", function(self)
                sliderScript()
                local selectedFrame = FrameDropdown:GetText()
                local profileName = PuppeteerSettings.GetSelectedProfileName(selectedFrame)
                if not PTGlobalProfiles.StyleOverrides[profileName] then
                    PTGlobalProfiles.StyleOverrides[profileName] = {}
                end
                -- Save to style overrides using the path
                SetStyleOverride(PTGlobalProfiles.StyleOverrides[profileName], overridePath, self:GetValue())
                PTProfileManager.ApplyOverrides(profileName)
                RefreshFrameGroup(selectedFrame)
            end)
            return slider, function()
                local selectedFrame = FrameDropdown:GetText()
                local profile = GetSelectedProfile(selectedFrame)
                slider:SetValue(getValue(profile))
            end
        end

        -- Name Text Size
        print("DEBUG: Creating nameTextSlider")
        local nameTextSlider, updateNameTextSlider = CreateTextSizeSlider(
            textSizeSubtitle, "Name Text", "Font size for unit names",
            "NameText.FontSize",
            function(p) return p.NameText.FontSize end,
            function(p, v) p.NameText.FontSize = v end,
            -15
        )

        -- Health Text Size
        local healthTextSlider, updateHealthTextSlider = CreateTextSizeSlider(
            nameTextSlider, "Health Text", "Font size for health numbers",
            "HealthTexts.Normal.FontSize",
            function(p) return p.HealthTexts.Normal.FontSize end,
            function(p, v)
                p.HealthTexts.Normal.FontSize = v
                p.HealthTexts.WithMissing.FontSize = v
            end,
            -15
        )

        -- Missing Health Text Size
        local missingHealthTextSlider, updateMissingHealthTextSlider = CreateTextSizeSlider(
            healthTextSlider, "Missing Health Text", "Font size for missing health",
            "HealthTexts.Missing.FontSize",
            function(p) return p.HealthTexts.Missing.FontSize end,
            function(p, v) p.HealthTexts.Missing.FontSize = v end,
            -15
        )

        -- Power Text Size
        local powerTextSlider, updatePowerTextSlider = CreateTextSizeSlider(
            missingHealthTextSlider, "Power Text", "Font size for power/mana",
            "PowerText.FontSize",
            function(p) return p.PowerText.FontSize end,
            function(p, v) p.PowerText.FontSize = v end,
            -15
        )

        -- Incoming Heal Text Size
        local incomingHealTextSlider, updateIncomingHealTextSlider = CreateTextSizeSlider(
            powerTextSlider, "Incoming Heal Text", "Font size for incoming heals",
            "IncomingHealText.FontSize",
            function(p) return p.IncomingHealText.FontSize end,
            function(p, v) p.IncomingHealText.FontSize = v end,
            -15
        )

        -- Range Text Size
        local rangeTextSlider, updateRangeTextSlider = CreateTextSizeSlider(
            incomingHealTextSlider, "Range Text", "Font size for range indicator",
            "RangeText.FontSize",
            function(p) return p.RangeText.FontSize end,
            function(p, v) p.RangeText.FontSize = v end,
            -15
        )

        -- Text Positioning Section
        local textPositioningTitle = CreateLabel(section, "Text Positioning")
            :SetPoint("TOP", rangeTextSlider, "BOTTOM", 0, -30)
            :SetFontSize(12)

        local textPositioningSubtitle = CreateLabel(section, "Adjust position for each text element")
            :SetPoint("TOP", textPositioningTitle, "BOTTOM", 0, -5)
            :SetFontSize(10)

        -- Helper to create anchor dropdown
        local function CreateAnchorDropdown(anchorElement, label, textPath, yOffset)
            local dropdown = CreateLabeledDropdown(section, label .. " Anchor", "What element to anchor to")
                :SetWidth(200)
                :SetPoint("TOP", anchorElement, "BOTTOM", 0, yOffset)
                :SetDynamicOptions(function(addOption, level, args)
                    local options = { "Health Bar", "Power Bar", "Button", "Container" }
                    for _, option in ipairs(options) do
                        addOption("text", option,
                            "initFunc", args.initFunc,
                            "func", args.func)
                    end
                end, {
                    initFunc = function(self, gui)
                        local selectedFrame = FrameDropdown:GetText()
                        local profile = GetSelectedProfile(selectedFrame)
                        local textObj = profile
                        for part in string.gfind(textPath, "[^%.]+") do
                            textObj = textObj[part]
                        end
                        self.checked = self.text == (textObj.Anchor or "Health Bar")
                    end,
                    func = function(self, gui)
                        local selectedFrame = FrameDropdown:GetText()
                        local profileName = PuppeteerSettings.GetSelectedProfileName(selectedFrame)
                        if not PTGlobalProfiles.StyleOverrides[profileName] then
                            PTGlobalProfiles.StyleOverrides[profileName] = {}
                        end
                        SetStyleOverride(PTGlobalProfiles.StyleOverrides[profileName], textPath .. ".Anchor", self.text)
                        PTProfileManager.ApplyOverrides(profileName)
                        RefreshFrameGroup(selectedFrame)
                        gui:UpdateText()
                    end
                })
                :SetTextUpdater(function(self)
                    local selectedFrame = FrameDropdown:GetText()
                    local profile = GetSelectedProfile(selectedFrame)
                    local textObj = profile
                    for part in string.gfind(textPath, "[^%.]+") do
                        textObj = textObj[part]
                    end
                    self:SetText(textObj.Anchor or "Health Bar")
                end)
            return dropdown
        end

        -- Helper to create alignment dropdown
        local function CreateAlignmentDropdown(anchorElement, label, textPath, alignType, yOffset)
            local options = alignType == "AlignmentH" and { "LEFT", "CENTER", "RIGHT" } or { "TOP", "CENTER", "BOTTOM" }
            local dropdown = CreateLabeledDropdown(section,
                    label .. " " .. (alignType == "AlignmentH" and "Horizontal" or "Vertical"), "Text alignment")
                :SetWidth(200)
                :SetPoint("TOP", anchorElement, "BOTTOM", 0, yOffset)
                :SetDynamicOptions(function(addOption, level, args)
                    for _, option in ipairs(options) do
                        addOption("text", option,
                            "initFunc", args.initFunc,
                            "func", args.func)
                    end
                end, {
                    initFunc = function(self, gui)
                        local selectedFrame = FrameDropdown:GetText()
                        local profile = GetSelectedProfile(selectedFrame)
                        local textObj = profile
                        for part in string.gfind(textPath, "[^%.]+") do
                            textObj = textObj[part]
                        end
                        local default = alignType == "AlignmentH" and "CENTER" or "CENTER"
                        self.checked = self.text == (textObj[alignType] or default)
                    end,
                    func = function(self, gui)
                        local selectedFrame = FrameDropdown:GetText()
                        local profileName = PuppeteerSettings.GetSelectedProfileName(selectedFrame)
                        if not PTGlobalProfiles.StyleOverrides[profileName] then
                            PTGlobalProfiles.StyleOverrides[profileName] = {}
                        end
                        SetStyleOverride(PTGlobalProfiles.StyleOverrides[profileName], textPath .. "." .. alignType,
                            self.text)
                        PTProfileManager.ApplyOverrides(profileName)
                        RefreshFrameGroup(selectedFrame)
                        gui:UpdateText()
                    end
                })
                :SetTextUpdater(function(self)
                    local selectedFrame = FrameDropdown:GetText()
                    local profile = GetSelectedProfile(selectedFrame)
                    local textObj = profile
                    for part in string.gfind(textPath, "[^%.]+") do
                        textObj = textObj[part]
                    end
                    local default = alignType == "AlignmentH" and "CENTER" or "CENTER"
                    self:SetText(textObj[alignType] or default)
                end)
            return dropdown
        end

        -- Helper to create offset slider
        local function CreateOffsetSlider(anchorElement, label, textPath, offsetType, yOffset)
            local slider = CreateLabeledSlider(section, label .. " " .. offsetType,
                    "Pixel offset " .. string.lower(offsetType))
                :SetPoint("TOP", anchorElement, "BOTTOM", 0, yOffset)
                :SetMinMaxValues(-100, 100)
                :SetValueStep(1)
            slider:GetSlider():SetNumberedText()
            local sliderScript = slider:GetSlider():GetScript("OnValueChanged")
            slider:GetSlider():SetScript("OnValueChanged", function(self)
                sliderScript()
                local selectedFrame = FrameDropdown:GetText()
                local profileName = PuppeteerSettings.GetSelectedProfileName(selectedFrame)
                if not PTGlobalProfiles.StyleOverrides[profileName] then
                    PTGlobalProfiles.StyleOverrides[profileName] = {}
                end
                SetStyleOverride(PTGlobalProfiles.StyleOverrides[profileName], textPath .. "." .. offsetType,
                    self:GetValue())
                PTProfileManager.ApplyOverrides(profileName)
                RefreshFrameGroup(selectedFrame)
            end)
            return slider, function()
                local selectedFrame = FrameDropdown:GetText()
                local profile = GetSelectedProfile(selectedFrame)
                local textObj = profile
                for part in string.gfind(textPath, "[^%.]+") do
                    textObj = textObj[part]
                end
                slider:SetValue(textObj[offsetType] or 0)
            end
        end

        -- Name Text Positioning
        local nameAnchorDropdown = CreateAnchorDropdown(textPositioningSubtitle, "Name Text", "NameText", -15)
        local nameAlignH = CreateAlignmentDropdown(nameAnchorDropdown, "Name Text", "NameText", "AlignmentH", -15)
        local nameAlignV = CreateAlignmentDropdown(nameAlignH, "Name Text", "NameText", "AlignmentV", -15)
        local nameOffsetXSlider, updateNameOffsetX = CreateOffsetSlider(nameAlignV, "Name Text", "NameText", "OffsetX",
            -15)
        local nameOffsetYSlider, updateNameOffsetY = CreateOffsetSlider(nameOffsetXSlider, "Name Text", "NameText",
            "OffsetY", -15)

        -- Health Text Positioning (applies to both Normal and WithMissing)
        local healthAnchorDropdown = CreateLabeledDropdown(section, "Health Text Anchor", "What element to anchor to")
            :SetWidth(200)
            :SetPoint("TOP", nameOffsetYSlider, "BOTTOM", 0, -30)
            :SetDynamicOptions(function(addOption, level, args)
                local options = { "Health Bar", "Power Bar", "Button", "Container" }
                for _, option in ipairs(options) do
                    addOption("text", option,
                        "initFunc", args.initFunc,
                        "func", args.func)
                end
            end, {
                initFunc = function(self, gui)
                    local selectedFrame = FrameDropdown:GetText()
                    local profile = GetSelectedProfile(selectedFrame)
                    self.checked = self.text == (profile.HealthTexts.Normal.Anchor or "Health Bar")
                end,
                func = function(self, gui)
                    local selectedFrame = FrameDropdown:GetText()
                    local profileName = PuppeteerSettings.GetSelectedProfileName(selectedFrame)
                    if not PTGlobalProfiles.StyleOverrides[profileName] then
                        PTGlobalProfiles.StyleOverrides[profileName] = {}
                    end
                    SetStyleOverride(PTGlobalProfiles.StyleOverrides[profileName], "HealthTexts.Normal.Anchor", self
                        .text)
                    SetStyleOverride(PTGlobalProfiles.StyleOverrides[profileName], "HealthTexts.WithMissing.Anchor",
                        self.text)
                    PTProfileManager.ApplyOverrides(profileName)
                    RefreshFrameGroup(selectedFrame)
                    gui:UpdateText()
                end
            })
            :SetTextUpdater(function(self)
                local selectedFrame = FrameDropdown:GetText()
                local profile = GetSelectedProfile(selectedFrame)
                self:SetText(profile.HealthTexts.Normal.Anchor or "Health Bar")
            end)

        -- Health Alignment (manually created to apply to both Normal and WithMissing)
        local healthAlignH = CreateLabeledDropdown(section, "Health Text Horizontal", "Horizontal text alignment")
            :SetWidth(200)
            :SetPoint("TOP", healthAnchorDropdown, "BOTTOM", 0, -15)
            :SetSimpleOptions({ "LEFT", "CENTER", "RIGHT" }, function(option)
                return {
                    text = option,
                    initFunc = function(self)
                        local selectedFrame = FrameDropdown:GetText()
                        local profile = GetSelectedProfile(selectedFrame)
                        self.checked = self.text == (profile.HealthTexts.Normal.AlignmentH or "CENTER")
                    end,
                    func = function(self, gui)
                        local selectedFrame = FrameDropdown:GetText()
                        local profileName = PuppeteerSettings.GetSelectedProfileName(selectedFrame)
                        if not PTGlobalProfiles.StyleOverrides[profileName] then
                            PTGlobalProfiles.StyleOverrides[profileName] = {}
                        end
                        SetStyleOverride(PTGlobalProfiles.StyleOverrides[profileName], "HealthTexts.Normal.AlignmentH",
                            self.text)
                        SetStyleOverride(PTGlobalProfiles.StyleOverrides[profileName],
                            "HealthTexts.WithMissing.AlignmentH", self.text)
                        PTProfileManager.ApplyOverrides(profileName)
                        RefreshFrameGroup(selectedFrame)
                        gui:UpdateText()
                    end
                }
            end)
            :SetTextUpdater(function(self)
                local selectedFrame = FrameDropdown:GetText()
                local profile = GetSelectedProfile(selectedFrame)
                self:SetText(profile.HealthTexts.Normal.AlignmentH or "CENTER")
            end)

        local healthAlignV = CreateLabeledDropdown(section, "Health Text Vertical", "Vertical text alignment")
            :SetWidth(200)
            :SetPoint("TOP", healthAlignH, "BOTTOM", 0, -15)
            :SetSimpleOptions({ "TOP", "CENTER", "BOTTOM" }, function(option)
                return {
                    text = option,
                    initFunc = function(self)
                        local selectedFrame = FrameDropdown:GetText()
                        local profile = GetSelectedProfile(selectedFrame)
                        self.checked = self.text == (profile.HealthTexts.Normal.AlignmentV or "CENTER")
                    end,
                    func = function(self, gui)
                        local selectedFrame = FrameDropdown:GetText()
                        local profileName = PuppeteerSettings.GetSelectedProfileName(selectedFrame)
                        if not PTGlobalProfiles.StyleOverrides[profileName] then
                            PTGlobalProfiles.StyleOverrides[profileName] = {}
                        end
                        SetStyleOverride(PTGlobalProfiles.StyleOverrides[profileName], "HealthTexts.Normal.AlignmentV",
                            self.text)
                        SetStyleOverride(PTGlobalProfiles.StyleOverrides[profileName],
                            "HealthTexts.WithMissing.AlignmentV", self.text)
                        PTProfileManager.ApplyOverrides(profileName)
                        RefreshFrameGroup(selectedFrame)
                        gui:UpdateText()
                    end
                }
            end)
            :SetTextUpdater(function(self)
                local selectedFrame = FrameDropdown:GetText()
                local profile = GetSelectedProfile(selectedFrame)
                self:SetText(profile.HealthTexts.Normal.AlignmentV or "CENTER")
            end)

        local healthOffsetXSlider = CreateLabeledSlider(section, "Health Text OffsetX", "Pixel offset offsetx")
            :SetPoint("TOP", healthAlignV, "BOTTOM", 0, -15)
            :SetMinMaxValues(-100, 100)
            :SetValueStep(1)
        healthOffsetXSlider:GetSlider():SetNumberedText()
        local updateHealthOffsetX = function()
            local selectedFrame = FrameDropdown:GetText()
            local profile = GetSelectedProfile(selectedFrame)
            healthOffsetXSlider:SetValue(profile.HealthTexts.Normal.OffsetX or 0)
        end
        local healthOffsetXScript = healthOffsetXSlider:GetSlider():GetScript("OnValueChanged")
        healthOffsetXSlider:GetSlider():SetScript("OnValueChanged", function(self)
            healthOffsetXScript()
            local selectedFrame = FrameDropdown:GetText()
            local profileName = PuppeteerSettings.GetSelectedProfileName(selectedFrame)
            if not PTGlobalProfiles.StyleOverrides[profileName] then
                PTGlobalProfiles.StyleOverrides[profileName] = {}
            end
            SetStyleOverride(PTGlobalProfiles.StyleOverrides[profileName], "HealthTexts.Normal.OffsetX", self:GetValue())
            SetStyleOverride(PTGlobalProfiles.StyleOverrides[profileName], "HealthTexts.WithMissing.OffsetX",
                self:GetValue())
            PTProfileManager.ApplyOverrides(profileName)
            RefreshFrameGroup(selectedFrame)
        end)

        local healthOffsetYSlider = CreateLabeledSlider(section, "Health Text OffsetY", "Pixel offset offsety")
            :SetPoint("TOP", healthOffsetXSlider, "BOTTOM", 0, -15)
            :SetMinMaxValues(-100, 100)
            :SetValueStep(1)
        healthOffsetYSlider:GetSlider():SetNumberedText()
        local updateHealthOffsetY = function()
            local selectedFrame = FrameDropdown:GetText()
            local profile = GetSelectedProfile(selectedFrame)
            healthOffsetYSlider:SetValue(profile.HealthTexts.Normal.OffsetY or 0)
        end
        local healthOffsetYScript = healthOffsetYSlider:GetSlider():GetScript("OnValueChanged")
        healthOffsetYSlider:GetSlider():SetScript("OnValueChanged", function(self)
            healthOffsetYScript()
            local selectedFrame = FrameDropdown:GetText()
            local profileName = PuppeteerSettings.GetSelectedProfileName(selectedFrame)
            if not PTGlobalProfiles.StyleOverrides[profileName] then
                PTGlobalProfiles.StyleOverrides[profileName] = {}
            end
            SetStyleOverride(PTGlobalProfiles.StyleOverrides[profileName], "HealthTexts.Normal.OffsetY", self:GetValue())
            SetStyleOverride(PTGlobalProfiles.StyleOverrides[profileName], "HealthTexts.WithMissing.OffsetY",
                self:GetValue())
            PTProfileManager.ApplyOverrides(profileName)
            RefreshFrameGroup(selectedFrame)
        end)

        -- Power Text Positioning
        local powerAnchorDropdown = CreateAnchorDropdown(healthOffsetYSlider, "Power Text", "PowerText", -30)
        local powerAlignH = CreateAlignmentDropdown(powerAnchorDropdown, "Power Text", "PowerText", "AlignmentH", -15)
        local powerAlignV = CreateAlignmentDropdown(powerAlignH, "Power Text", "PowerText", "AlignmentV", -15)
        local powerOffsetXSlider, updatePowerOffsetX = CreateOffsetSlider(powerAlignV, "Power Text", "PowerText",
            "OffsetX", -15)
        local powerOffsetYSlider, updatePowerOffsetY = CreateOffsetSlider(powerOffsetXSlider, "Power Text", "PowerText",
            "OffsetY", -15)

        -- Update function for Fonts section
        UpdateFontsSection = function()
            if updateNameTextSlider then updateNameTextSlider() end
            if updateHealthTextSlider then updateHealthTextSlider() end
            if updateMissingHealthTextSlider then updateMissingHealthTextSlider() end
            if updatePowerTextSlider then updatePowerTextSlider() end
            if updateIncomingHealTextSlider then updateIncomingHealTextSlider() end
            if updateRangeTextSlider then updateRangeTextSlider() end
            if nameAnchorDropdown then nameAnchorDropdown:UpdateText() end
            if nameAlignH then nameAlignH:UpdateText() end
            if nameAlignV then nameAlignV:UpdateText() end
            if updateNameOffsetX then updateNameOffsetX() end
            if updateNameOffsetY then updateNameOffsetY() end
            if healthAnchorDropdown then healthAnchorDropdown:UpdateText() end
            if healthAlignH then healthAlignH:UpdateText() end
            if healthAlignV then healthAlignV:UpdateText() end
            if updateHealthOffsetX then updateHealthOffsetX() end
            if updateHealthOffsetY then updateHealthOffsetY() end
            if powerAnchorDropdown then powerAnchorDropdown:UpdateText() end
            if powerAlignH then powerAlignH:UpdateText() end
            if powerAlignV then powerAlignV:UpdateText() end
            if updatePowerOffsetX then updatePowerOffsetX() end
            if updatePowerOffsetY then updatePowerOffsetY() end
            if fontDropdown then fontDropdown:UpdateText() end
            if fontStyleDropdown then fontStyleDropdown:UpdateText() end
        end
    end

    -- Show Dimensions by default
    ShowCategorySection("Dimensions")
end

function UpdateFrameOptions()
    LockFrameCheckbox:SetChecked(PuppeteerSettings.IsFrameLocked(FrameDropdown:GetText()))
    HideTitleCheckbox:SetChecked(PuppeteerSettings.IsTitleHidden(FrameDropdown:GetText()))
    HideFrameCheckbox:SetChecked(PuppeteerSettings.IsFrameHidden(FrameDropdown:GetText()))
end

-- Old style override UI code removed - now using categorized sections above

function TraverseOverride(style, location)
    local path = util.SplitString(location, ".")
    local currentTable = style
    for i = 1, table.getn(path) - 1 do
        if not currentTable[path[i]] then
            currentTable[path[i]] = {}
        end
        currentTable = currentTable[path[i]]
    end
    return currentTable, path[table.getn(path)]
end

function GetStyleOverride(style, location)
    local optionTable, location = TraverseOverride(style, location)
    return optionTable[location]
end

function SetStyleOverride(style, location, value)
    -- style can be either a style name (string) or a style override object (table)
    -- If it's a string, use it directly. If it's an object, we need to traverse it.
    if PTDirtyTracker and type(style) == "string" then
        -- style is a style name, use dirty tracker
        PTDirtyTracker.SetStyleOverride(style, location, value)
    else
        -- style is an override object or dirty tracker not available, use direct update
        local optionTable, finalKey = TraverseOverride(style, location)
        optionTable[finalKey] = value
        if PTDirtyTracker then
            PTDirtyTracker.MarkDirty()
        end
    end

    categoryContainer:UpdateScrollChildRect()

    -- Show default category
    ShowCategorySection("Dimensions")
end

-- Profile management buttons
function CreateTab_Profiles()
    local container = TabFrame:CreateTab("Profiles")

    -- Profile selector at top
    local profileLabel = CreateLabel(container, "Profile:")
        :SetPoint("TOPLEFT", container, "TOPLEFT", 20, -20)

    -- Forward declare profileDropdown so it can be referenced in callbacks
    local profileDropdown
    profileDropdown = CreateDropdown(container, 200)
        :SetPoint("LEFT", profileLabel, "RIGHT", 10, 0)
        :ApplyTooltip("Select which profile to save to or load from.",
            "Selecting a profile does NOT automatically load it.")
        :SetDynamicOptions(function(addOption, level, args)
            local profiles = PTProfileData.GetProfileList()
            for _, profileName in ipairs(profiles) do
                addOption("text", profileName,
                    "checked", PTProfileData.GetCurrentCharacterProfile() == profileName,
                    "func", args.func)
            end
        end, {
            func = function(self)
                local selectedProfile = self.text
                local currentProfile = PTProfileData.GetCurrentCharacterProfile()

                if selectedProfile == currentProfile then
                    return
                end

                PTProfileData.SetCurrentCharacterProfile(selectedProfile)
                profileDropdown:UpdateText()
                DEFAULT_CHAT_FRAME:AddMessage("[Puppeteer] Selected profile: " ..
                    selectedProfile .. " (click 'Load' to apply)")
            end
        })
        :SetTextUpdater(function(self)
            self:SetText(PTProfileData.GetCurrentCharacterProfile())
        end)

    -- Profile management buttons
    local createButton = PTGuiLib.Get("button", container)
        :SetPoint("TOPLEFT", profileLabel, "BOTTOMLEFT", 0, -20)
        :SetSize(100, 25)
        :SetText("Create")
        :SetScript("OnClick", function()
            local dialog
            local nameEditBox

            dialog = PTGuiLib.Get("simple_dialog", TabFrame)
                :SetPoint("CENTER", TabFrame, "CENTER")
                :SetTitle("Create New Profile")
                :SetText("Enter a name for the new profile:")
                :SetHeight(240)

            nameEditBox = PTGuiLib.Get("editbox", dialog)
            nameEditBox:SetParent(dialog)
            nameEditBox:SetPoint("TOP", dialog:GetComponent("text"), "BOTTOM", 0, -10)
            nameEditBox:SetSize(200, 20)

            local _, firstButton = dialog:AddButton("Create from Current", function()
                local profileName = nameEditBox:GetText()
                if profileName and profileName ~= "" then
                    if PTProfileData.CreateProfile(profileName, nil) then
                        -- Capture current settings and save to the new profile
                        local currentData = PTProfileData.GetCurrentProfileData()
                        PTProfileData.SaveProfile(profileName, currentData)
                        PopOverlayFrame()
                        dialog:Dispose()
                        DEFAULT_CHAT_FRAME:AddMessage("[Puppeteer] Profile '" .. profileName .. "' created")
                    end
                else
                    DEFAULT_CHAT_FRAME:AddMessage("[Puppeteer] Error: Please enter a profile name")
                end
            end)

            dialog:AddButton("Create from Default", function()
                local profileName = nameEditBox:GetText()
                if profileName and profileName ~= "" then
                    if PTProfileData.CreateProfile(profileName, "Default") then
                        PopOverlayFrame()
                        dialog:Dispose()
                        DEFAULT_CHAT_FRAME:AddMessage("[Puppeteer] Profile '" .. profileName .. "' created from Default")
                    end
                else
                    DEFAULT_CHAT_FRAME:AddMessage("[Puppeteer] Error: Please enter a profile name")
                end
            end)

            dialog:AddButton("Cancel", function()
                PopOverlayFrame()
                dialog:Dispose()
            end)

            -- Reposition first button to be below the editbox instead of the text
            firstButton:SetPoint("TOP", nameEditBox, "BOTTOM", 0, -10)

            AddOverlayFrame(dialog)
        end)

    local copyButton = PTGuiLib.Get("button", container)
        :SetPoint("LEFT", createButton, "RIGHT", 5, 0)
        :SetSize(100, 25)
        :SetText("Copy")
        :SetScript("OnClick", function()
            local currentProfile = PTProfileData.GetCurrentCharacterProfile()
            local dialog
            local nameEditBox

            dialog = PTGuiLib.Get("simple_dialog", TabFrame)
                :SetPoint("CENTER", TabFrame, "CENTER")
                :SetTitle("Copy Profile")
                :SetText("Enter a name for the copy of '" .. currentProfile .. "':")
                :SetHeight(200)

            nameEditBox = PTGuiLib.Get("editbox", dialog)
            nameEditBox:SetParent(dialog)
            nameEditBox:SetPoint("TOP", dialog:GetComponent("text"), "BOTTOM", 0, -10)
            nameEditBox:SetSize(200, 20)
            nameEditBox:SetText(currentProfile .. " Copy")

            local _, firstButton = dialog:AddButton("Copy", function()
                local newName = nameEditBox:GetText()
                if newName and newName ~= "" then
                    if PTProfileData.CopyProfile(currentProfile, newName) then
                        PopOverlayFrame()
                        dialog:Dispose()
                        DEFAULT_CHAT_FRAME:AddMessage("[Puppeteer] Profile copied to '" .. newName .. "'")
                    end
                else
                    DEFAULT_CHAT_FRAME:AddMessage("[Puppeteer] Error: Please enter a profile name")
                end
            end)

            dialog:AddButton("Cancel", function()
                PopOverlayFrame()
                dialog:Dispose()
            end)

            -- Reposition first button to be below the editbox
            firstButton:SetPoint("TOP", nameEditBox, "BOTTOM", 0, -10)

            AddOverlayFrame(dialog)
        end)

    local deleteButton = PTGuiLib.Get("button", container)
        :SetPoint("LEFT", copyButton, "RIGHT", 5, 0)
        :SetSize(100, 25)
        :SetText("Delete")
        :SetScript("OnClick", function()
            local currentProfile = PTProfileData.GetCurrentCharacterProfile()
            if currentProfile == "Default" then
                DEFAULT_CHAT_FRAME:AddMessage("[Puppeteer] Error: Cannot delete the Default profile")
                return
            end

            local dialog
            dialog = PTGuiLib.Get("simple_dialog", TabFrame)
                :SetPoint("CENTER", TabFrame, "CENTER")
                :SetTitle("Delete Profile")
                :SetText("Are you sure you want to delete profile '" .. currentProfile .. "'?")
                :AddButton("Delete", function()
                    if PTProfileData.DeleteProfile(currentProfile) then
                        -- Switch to Default profile after deleting current
                        PTProfileData.SetCurrentCharacterProfile("Default")
                        profileDropdown:UpdateText()
                        local defaultData = PTProfileData.LoadProfile("Default")
                        if defaultData then
                            PTProfileData.ApplyProfileData(defaultData)
                            PuppeteerSettings.ApplyFramePositions()
                            RefreshAllFrameGroups()
                        end
                        PopOverlayFrame()
                        dialog:Dispose()
                        DEFAULT_CHAT_FRAME:AddMessage("[Puppeteer] Profile '" .. currentProfile .. "' deleted")
                    end
                end)
                :AddButton("Cancel", function()
                    PopOverlayFrame()
                    dialog:Dispose()
                end)

            AddOverlayFrame(dialog)
        end)

    local renameButton = PTGuiLib.Get("button", container)
        :SetPoint("LEFT", deleteButton, "RIGHT", 5, 0)
        :SetSize(100, 25)
        :SetText("Rename")
        :SetScript("OnClick", function()
            local currentProfile = PTProfileData.GetCurrentCharacterProfile()
            if currentProfile == "Default" then
                DEFAULT_CHAT_FRAME:AddMessage("[Puppeteer] Error: Cannot rename the Default profile")
                return
            end

            local dialog
            local nameEditBox

            dialog = PTGuiLib.Get("simple_dialog", TabFrame)
                :SetPoint("CENTER", TabFrame, "CENTER")
                :SetTitle("Rename Profile")
                :SetText("Enter a new name for '" .. currentProfile .. "':")
                :SetHeight(200)

            nameEditBox = PTGuiLib.Get("editbox", dialog)
            nameEditBox:SetParent(dialog)
            nameEditBox:SetPoint("TOP", dialog:GetComponent("text"), "BOTTOM", 0, -10)
            nameEditBox:SetSize(200, 20)
            nameEditBox:SetText(currentProfile)

            local _, firstButton = dialog:AddButton("Rename", function()
                local newName = nameEditBox:GetText()
                if newName and newName ~= "" then
                    if PTProfileData.RenameProfile(currentProfile, newName) then
                        profileDropdown:UpdateText()
                        PopOverlayFrame()
                        dialog:Dispose()
                        DEFAULT_CHAT_FRAME:AddMessage("[Puppeteer] Profile renamed to '" .. newName .. "'")
                    end
                else
                    DEFAULT_CHAT_FRAME:AddMessage("[Puppeteer] Error: Please enter a profile name")
                end
            end)

            dialog:AddButton("Cancel", function()
                PopOverlayFrame()
                dialog:Dispose()
            end)

            -- Reposition first button to be below the editbox
            firstButton:SetPoint("TOP", nameEditBox, "BOTTOM", 0, -10)

            AddOverlayFrame(dialog)
        end)

    -- Save, Load, and Revert buttons
    local separator = container:GetHandle():CreateTexture(nil, "ARTWORK")
    separator:SetTexture(0.3, 0.3, 0.3, 0.8)
    separator:SetHeight(1)
    separator:SetPoint("TOPLEFT", createButton:GetHandle(), "BOTTOMLEFT", 0, -30)
    separator:SetPoint("TOPRIGHT", container:GetHandle(), "TOPRIGHT", -20, -120)

    -- Checkbox for including positions in profile
    local includePositionsLabel = CreateLabel(container, "Include frame positions in profile:")
        :SetPoint("TOPLEFT", separator, "BOTTOMLEFT", 0, -15)

    local includePositionsCheckbox = CreateCheckbox(container, 20, 20)
        :SetPoint("LEFT", includePositionsLabel, "RIGHT", 5, 0)
        :ApplyTooltip("When enabled, saving a profile includes frame positions.",
            "Loading a profile will move frames to the saved positions.",
            "When disabled, each character keeps its own positions.")
        :SetChecked(PTOptions.IncludePositionsInProfile and 1 or 0)
        :OnClick(function(self)
            PTOptions.IncludePositionsInProfile = self:GetChecked() == 1
        end)

    local loadButton = PTGuiLib.Get("button", container)
        :SetPoint("TOPLEFT", includePositionsLabel, "BOTTOMLEFT", 0, -10)
        :SetSize(100, 30)
        :SetText("Load")
        :ApplyTooltip("Load settings from the selected profile.", "This will replace your current settings.")
        :SetScript("OnClick", function()
            local profileName = PTProfileData.GetCurrentCharacterProfile()
            local profileData = PTProfileData.LoadProfile(profileName)
            if profileData then
                PTProfileData.ApplyProfileData(profileData)
                PuppeteerSettings.ApplyFramePositions()
                RefreshAllFrameGroups()
                MarkProfileSwitched()
                DEFAULT_CHAT_FRAME:AddMessage("[Puppeteer] Loaded profile: " .. profileName)
            else
                DEFAULT_CHAT_FRAME:AddMessage("[Puppeteer] Error: Failed to load profile '" .. profileName .. "'")
            end
        end)

    local saveButton = PTGuiLib.Get("button", container)
        :SetPoint("LEFT", loadButton, "RIGHT", 10, 0)
        :SetSize(100, 30)
        :SetText("Save")
        :ApplyTooltip("Save current settings to the selected profile.",
            "Your settings are already persisted - this saves a profile snapshot.")
        :SetScript("OnClick", function()
            local profileName = PTProfileData.GetCurrentCharacterProfile()
            local profileData = PTProfileData.GetCurrentProfileData()
            if PTProfileData.SaveProfile(profileName, profileData) then
                DEFAULT_CHAT_FRAME:AddMessage("[Puppeteer] Profile settings saved to '" .. profileName .. "'")
            else
                DEFAULT_CHAT_FRAME:AddMessage("[Puppeteer] Error: Failed to save profile '" .. profileName .. "'")
            end
        end)
end

function CreateTab_About()
    local container = TabFrame:CreateTab("About")

    local text = PTGuiLib.GetText(container,
            "Puppeteer Version " .. Puppeteer.VERSION ..
            "\n\n\nPuppeteer Author: OldManAlpha\nTurtle Nordanaar IGN: Oldmana, Lowall, Jmdruid" ..
            "\n\nHealersMate Original Author: i2ichardt\nEmail: rj299@yahoo.com" ..
            "\n\nAdditional Contributors" ..
            "\nTurtle WoW Community: Answers to addon development questions" ..
            "\nShagu: Utility functions & providing a wealth of research material" ..
            "\nChatGPT: Utility functions" ..
            "\n\n\nCheck For Updates, Report Issues, Make Suggestions:\n",
            12)
        :SetPoint("TOP", container, "TOP", 0, -80)

    CreateLinkEditbox(container, "https://github.com/OldManAlpha/Puppeteer")
        :SetPoint("TOP", text, "BOTTOM", 0, -10)
        :SetSize(300, 20)
end

-- TODO: These tab functions are currently unused (tabs not created in Init()).
-- They contain useful UI for dimensions/fonts/colors/textures that could be
-- integrated into the Customize tab with a category system in the future.

function CreateTab_Dimensions()
    local container = TabFrame:CreateTab("Dimensions")

    local frameStyleContainer = PTGuiLib.Get("container", container)
        :SetSimpleBackground()
        :SetPoint("TOPLEFT", container, "TOPLEFT", 5, -26)
        :SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -5, -5)

    local title = CreateLabel(frameStyleContainer, "Bar Dimensions")
        :SetPoint("TOP", frameStyleContainer, "TOP", 0, -10)
        :SetFontSize(14)

    local subtitle = CreateLabel(frameStyleContainer, "")
        :SetPoint("TOP", title, "BOTTOM", 0, -5)
        :SetFontSize(10)

    -- Frame selection dropdown
    local preferredFrameOrder = { "Party", "Pets", "Raid", "Raid Pets", "Target", "Focus" }
    local frameDropdown = CreateLabeledDropdown(frameStyleContainer, "Configure Frame",
            "The frame to edit the dimensions of")
        :SetWidth(150)
        :SetPoint("TOP", subtitle, "BOTTOM", 0, -10)
        :SetDynamicOptions(function(addOption, level, args)
            for _, name in ipairs(preferredFrameOrder) do
                if Puppeteer.UnitFrameGroups[name] then
                    addOption("text", name,
                        "dropdownText", name,
                        "initFunc", args.initFunc,
                        "func", args.func)
                end
            end
        end, {
            initFunc = function(self, gui)
                self.checked = self.text == gui:GetText()
            end,
            func = function(self, gui)
                UpdateDimensionSliders()
            end
        })
        :SetText("Party")

    -- Width slider
    local widthSlider = CreateLabeledSlider(frameStyleContainer, "Width", "The width of the frame")
        :SetPoint("TOP", frameDropdown, "BOTTOM", 0, -30)
        :SetMinMaxValues(50, 300)
        :SetValueStep(1)
    widthSlider:GetSlider():SetNumberedText()
    local widthScript = widthSlider:GetSlider():GetScript("OnValueChanged")
    widthSlider:GetSlider():SetScript("OnValueChanged", function(self)
        widthScript()
        local selectedFrame = frameDropdown:GetText()
        local profile = GetSelectedProfile(selectedFrame)
        profile.Width = self:GetValue()
        RefreshFrameGroup(selectedFrame)
    end)

    -- Health Bar Height slider
    local healthHeightSlider = CreateLabeledSlider(frameStyleContainer, "Health Bar Height",
            "The height of the health bar")
        :SetPoint("TOP", widthSlider, "BOTTOM", 0, -15)
        :SetMinMaxValues(5, 100)
        :SetValueStep(1)
    healthHeightSlider:GetSlider():SetNumberedText()
    local healthHeightScript = healthHeightSlider:GetSlider():GetScript("OnValueChanged")
    healthHeightSlider:GetSlider():SetScript("OnValueChanged", function(self)
        healthHeightScript()
        local selectedFrame = frameDropdown:GetText()
        local profile = GetSelectedProfile(selectedFrame)
        profile.HealthBarHeight = self:GetValue()
        RefreshFrameGroup(selectedFrame)
    end)

    -- Power Bar Height slider
    local powerHeightSlider = CreateLabeledSlider(frameStyleContainer, "Power Bar Height", "The height of the power bar")
        :SetPoint("TOP", healthHeightSlider, "BOTTOM", 0, -15)
        :SetMinMaxValues(0, 30)
        :SetValueStep(1)
    powerHeightSlider:GetSlider():SetNumberedText()
    local powerHeightScript = powerHeightSlider:GetSlider():GetScript("OnValueChanged")
    powerHeightSlider:GetSlider():SetScript("OnValueChanged", function(self)
        powerHeightScript()
        local selectedFrame = frameDropdown:GetText()
        local profile = GetSelectedProfile(selectedFrame)
        profile.PowerBarHeight = self:GetValue()
        RefreshFrameGroup(selectedFrame)
    end)

    -- Function to update sliders when frame changes
    function UpdateDimensionSliders()
        local selectedFrame = frameDropdown:GetText()
        local profileName = PuppeteerSettings.GetSelectedProfileName(selectedFrame)
        local profile = GetSelectedProfile(selectedFrame)
        subtitle:SetText("Editing profile: " .. profileName)
        widthSlider:SetValue(profile.Width or 150)
        healthHeightSlider:SetValue(profile.HealthBarHeight or 24)
        powerHeightSlider:SetValue(profile.PowerBarHeight or 10)
    end

    UpdateDimensionSliders()
end

function CreateTab_Fonts()
    local container = TabFrame:CreateTab("Fonts")

    local title = CreateLabel(container, "Global Font Settings")
        :SetPoint("TOP", container, "TOP", 0, -15)
        :SetFontSize(14)

    local subtitle = CreateLabel(container, "Font applies to all text elements")
        :SetPoint("TOP", title, "BOTTOM", 0, -10)
        :SetFontSize(10)

    -- Font dropdown
    local fontDropdown
    fontDropdown = CreateLabeledDropdown(container, "Font Family", "The font used for all text")
        :SetWidth(200)
        :SetPoint("TOP", subtitle, "BOTTOM", 0, -30)
        :SetDynamicOptions(function(addOption, level, args)
            for name, path in pairs(Puppeteer.AvailableFonts) do
                -- Capture path in a local variable to avoid closure issues
                local fontPath = path
                addOption("text", name,
                    "dropdownText", name,
                    "checked", PTGlobalOptions and PTGlobalOptions.GlobalFont == fontPath,
                    "func", function(self)
                        if PTGlobalOptions then
                            PTGlobalOptions.GlobalFont = fontPath
                            RefreshAllFrameGroups()
                            if fontDropdown then
                                fontDropdown:UpdateText()
                            end
                        end
                    end)
            end
        end, {})
        :SetTextUpdater(function(self)
            local currentFont = (PTGlobalOptions and PTGlobalOptions.GlobalFont) or "Fonts\\FRIZQT__.TTF"
            for name, path in pairs(Puppeteer.AvailableFonts) do
                if path == currentFont then
                    self:SetText(name)
                    return
                end
            end
            self:SetText("FRIZQT (Default)")
        end)

    -- Preview text
    local preview = CreateLabel(container, "The quick brown fox jumps over the lazy dog")
        :SetPoint("TOP", fontDropdown, "BOTTOM", 0, -30)
        :SetFontSize(12)
end

function CreateTab_Colors()
    local container = TabFrame:CreateTab("Colors")

    local frameStyleContainer = PTGuiLib.Get("container", container)
        :SetSimpleBackground()
        :SetPoint("TOPLEFT", container, "TOPLEFT", 5, -26)
        :SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -5, -5)

    local title = CreateLabel(frameStyleContainer, "Text Color Settings")
        :SetPoint("TOP", frameStyleContainer, "TOP", 0, -10)
        :SetFontSize(14)

    local subtitle = CreateLabel(frameStyleContainer, "")
        :SetPoint("TOP", title, "BOTTOM", 0, -5)
        :SetFontSize(10)

    -- Frame selection dropdown
    local preferredFrameOrder = { "Party", "Pets", "Raid", "Raid Pets", "Target", "Focus" }
    local frameDropdown = CreateLabeledDropdown(frameStyleContainer, "Configure Frame", "The frame to edit the colors of")
        :SetWidth(150)
        :SetPoint("TOP", subtitle, "BOTTOM", 0, -10)
        :SetDynamicOptions(function(addOption, level, args)
            for _, name in ipairs(preferredFrameOrder) do
                if Puppeteer.UnitFrameGroups[name] then
                    addOption("text", name,
                        "dropdownText", name,
                        "initFunc", args.initFunc,
                        "func", args.func)
                end
            end
        end, {
            initFunc = function(self, gui)
                self.checked = self.text == gui:GetText()
            end,
            func = function(self, gui)
                UpdateColorDropdowns()
            end
        })
        :SetText("Party")

    -- Helper function to create color dropdown
    local function CreateColorDropdown(parent, label, tooltip, colorProperty)
        local dropdown = CreateLabeledDropdown(parent, label, tooltip)
            :SetWidth(150)
            :SetDynamicOptions(function(addOption, level, args)
                for _, colorName in ipairs(Puppeteer.ColorPaletteOrder) do
                    addOption("text", colorName,
                        "dropdownText", Puppeteer.GetColorPreviewString(colorName, colorName),
                        "initFunc", args.initFunc,
                        "func", args.func)
                end
            end, {
                initFunc = function(self, gui)
                    local selectedFrame = frameDropdown:GetText()
                    local profile = GetSelectedProfile(selectedFrame)
                    local currentColor = colorProperty(profile)
                    self.checked = self.text == currentColor
                end,
                func = function(self, gui)
                    local selectedFrame = frameDropdown:GetText()
                    local profile = GetSelectedProfile(selectedFrame)

                    -- Set the value through colorProperty (which now uses SetStyleOverride)
                    colorProperty(profile, self.text)

                    RefreshFrameGroup(selectedFrame)
                    gui:UpdateText()
                end
            })
            :SetTextUpdater(function(self)
                local selectedFrame = frameDropdown:GetText()
                local profile = GetSelectedProfile(selectedFrame)
                local colorName = colorProperty(profile)
                self:SetText(Puppeteer.GetColorPreviewString(colorName, colorName))
            end)
        return dropdown
    end

    -- Name Text Color
    local nameColorDropdown = CreateColorDropdown(frameStyleContainer, "Name Text Color", "Color of unit names",
            function(profile, newValue)
                if newValue then
                    local selectedFrame = frameDropdown:GetText()
                    local profileName = PuppeteerSettings.GetSelectedProfileName(selectedFrame)
                    SetStyleOverride(profileName, "NameText.Color", newValue)
                else
                    return profile.NameText.Color or "Class"
                end
            end)
        :SetPoint("TOP", frameDropdown, "BOTTOM", 0, -30)

    -- Health Text Color
    local healthColorDropdown = CreateColorDropdown(frameStyleContainer, "Health Text Color", "Color of health numbers",
            function(profile, newValue)
                if newValue then
                    local selectedFrame = frameDropdown:GetText()
                    local profileName = PuppeteerSettings.GetSelectedProfileName(selectedFrame)
                    SetStyleOverride(profileName, "HealthTexts.Normal.Color", newValue)
                    SetStyleOverride(profileName, "HealthTexts.WithMissing.Color", newValue)
                else
                    return profile.HealthTexts.Normal.Color or "White"
                end
            end)
        :SetPoint("TOP", nameColorDropdown, "BOTTOM", 0, -15)

    -- Missing Health Text Color
    local missingHealthColorDropdown = CreateColorDropdown(frameStyleContainer, "Missing Health Color",
            "Color of missing health text",
            function(profile, newValue)
                if newValue then
                    local selectedFrame = frameDropdown:GetText()
                    local profileName = PuppeteerSettings.GetSelectedProfileName(selectedFrame)
                    SetStyleOverride(profileName, "HealthTexts.Missing.Color", newValue)
                else
                    return profile.HealthTexts.Missing.Color or "Red"
                end
            end)
        :SetPoint("TOP", healthColorDropdown, "BOTTOM", 0, -15)

    -- Power Text Color
    local powerColorDropdown = CreateColorDropdown(frameStyleContainer, "Power Text Color", "Color of power/mana numbers",
            function(profile, newValue)
                if newValue then
                    local selectedFrame = frameDropdown:GetText()
                    local profileName = PuppeteerSettings.GetSelectedProfileName(selectedFrame)
                    SetStyleOverride(profileName, "PowerText.Color", newValue)
                else
                    return profile.PowerText.Color or "White"
                end
            end)
        :SetPoint("TOP", missingHealthColorDropdown, "BOTTOM", 0, -15)

    -- Function to update dropdowns when frame changes
    function UpdateColorDropdowns()
        local selectedFrame = frameDropdown:GetText()
        local profileName = PuppeteerSettings.GetSelectedProfileName(selectedFrame)
        subtitle:SetText("Editing profile: " .. profileName)
        nameColorDropdown:UpdateText()
        healthColorDropdown:UpdateText()
        missingHealthColorDropdown:UpdateText()
        powerColorDropdown:UpdateText()
    end

    UpdateColorDropdowns()
end

function CreateTab_Textures()
    local container = TabFrame:CreateTab("Textures")

    local frameStyleContainer = PTGuiLib.Get("container", container)
        :SetSimpleBackground()
        :SetPoint("TOPLEFT", container, "TOPLEFT", 5, -26)
        :SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -5, -5)

    local title = CreateLabel(frameStyleContainer, "Bar Texture Settings")
        :SetPoint("TOP", frameStyleContainer, "TOP", 0, -10)
        :SetFontSize(14)

    local subtitle = CreateLabel(frameStyleContainer, "")
        :SetPoint("TOP", title, "BOTTOM", 0, -5)
        :SetFontSize(10)

    -- Frame selection dropdown
    local preferredFrameOrder = { "Party", "Pets", "Raid", "Raid Pets", "Target", "Focus" }
    local frameDropdown = CreateLabeledDropdown(frameStyleContainer, "Configure Frame",
            "The frame to edit the textures of")
        :SetWidth(150)
        :SetPoint("TOP", subtitle, "BOTTOM", 0, -10)
        :SetDynamicOptions(function(addOption, level, args)
            for _, name in ipairs(preferredFrameOrder) do
                if Puppeteer.UnitFrameGroups[name] then
                    addOption("text", name,
                        "dropdownText", name,
                        "initFunc", args.initFunc,
                        "func", args.func)
                end
            end
        end, {
            initFunc = function(self, gui)
                self.checked = self.text == gui:GetText()
            end,
            func = function(self, gui)
                UpdateTextureDropdowns()
            end
        })
        :SetText("Party")

    -- Health Bar Texture dropdown
    local healthBarTextureDropdown = CreateLabeledDropdown(frameStyleContainer, "Health Bar Texture",
            "Texture for health bars")
        :SetWidth(200)
        :SetPoint("TOP", frameDropdown, "BOTTOM", 0, -30)
        :SetDynamicOptions(function(addOption, level, args)
            for name, path in pairs(Puppeteer.BarStyles) do
                addOption("text", name,
                    "dropdownText", name,
                    "initFunc", args.initFunc,
                    "func", args.func)
            end
        end, {
            initFunc = function(self, gui)
                local selectedFrame = frameDropdown:GetText()
                local profile = GetSelectedProfile(selectedFrame)
                self.checked = self.text == profile.HealthBarStyle
            end,
            func = function(self, gui)
                local selectedFrame = frameDropdown:GetText()
                local profile = GetSelectedProfile(selectedFrame)
                profile.HealthBarStyle = self.text
                RefreshFrameGroup(selectedFrame)
                gui:UpdateText()
            end
        })
        :SetTextUpdater(function(self)
            local selectedFrame = frameDropdown:GetText()
            local profile = GetSelectedProfile(selectedFrame)
            self:SetText(profile.HealthBarStyle or "Puppeteer")
        end)

    -- Power Bar Texture dropdown
    local powerBarTextureDropdown = CreateLabeledDropdown(frameStyleContainer, "Power Bar Texture",
            "Texture for power bars")
        :SetWidth(200)
        :SetPoint("TOP", healthBarTextureDropdown, "BOTTOM", 0, -15)
        :SetDynamicOptions(function(addOption, level, args)
            for name, path in pairs(Puppeteer.BarStyles) do
                addOption("text", name,
                    "dropdownText", name,
                    "initFunc", args.initFunc,
                    "func", args.func)
            end
        end, {
            initFunc = function(self, gui)
                local selectedFrame = frameDropdown:GetText()
                local profile = GetSelectedProfile(selectedFrame)
                self.checked = self.text == profile.PowerBarStyle
            end,
            func = function(self, gui)
                local selectedFrame = frameDropdown:GetText()
                local profile = GetSelectedProfile(selectedFrame)
                profile.PowerBarStyle = self.text
                RefreshFrameGroup(selectedFrame)
                gui:UpdateText()
            end
        })
        :SetTextUpdater(function(self)
            local selectedFrame = frameDropdown:GetText()
            local profile = GetSelectedProfile(selectedFrame)
            self:SetText(profile.PowerBarStyle or "Puppeteer Borderless")
        end)

    -- Function to update dropdowns when frame changes
    function UpdateTextureDropdowns()
        local selectedFrame = frameDropdown:GetText()
        local profileName = PuppeteerSettings.GetSelectedProfileName(selectedFrame)
        subtitle:SetText("Editing profile: " .. profileName)
        healthBarTextureDropdown:UpdateText()
        powerBarTextureDropdown:UpdateText()
    end

    UpdateTextureDropdowns()
end

-- Factory-related functions

function NewLabeledColumnLayout(container, columns, startY, spacing)
    local layout = {}
    layout.lastAdded = {}
    layout.params = {}
    layout.selectedColumn = 1
    function layout:getNextPoint(columnIndex)
        local offsetX, offsetY = self.params.offsetX or 0, self.params.offsetY or 0
        if self.lastAdded[columnIndex] then
            return "TOPLEFT", self.lastAdded[columnIndex], "BOTTOMLEFT", offsetX, -spacing + offsetY
        end
        return "TOPLEFT", container, "TOPLEFT", columns[columnIndex] + offsetX, startY + offsetY
    end

    function layout:layoutComponent(component)
        if not self.params.ignoreNext then
            local columnIndex = self.selectedColumn or 1
            component:SetPoint(self:getNextPoint(columnIndex))
            self.lastAdded[columnIndex] = component
        end
        util.ClearTable(self.params)
    end

    function layout:column(columnIndex)
        self.selectedColumn = columnIndex
        return self
    end

    function layout:offset(offsetX, offsetY)
        self.params.offsetX = (self.params.offsetX or 0) + offsetX
        self.params.offsetY = (self.params.offsetY or 0) + offsetY
        return self
    end

    function layout:levelAt(columnIndex)
        local lastAdded = self.lastAdded[columnIndex]
        self.lastAdded[self.selectedColumn] = lastAdded
        self:offset(columns[self.selectedColumn] - columns[columnIndex], spacing + lastAdded:GetHeight())
        return self
    end

    function layout:setLastAdded(columnIndex, component)
        self.lastAdded[columnIndex] = component
        return self
    end

    function layout:ignoreNext()
        self.params.ignoreNext = true
        return self
    end

    return layout
end

function NewComponentFactory(container, layout)
    return {
        ["layout"] = layout,
        ["doLayout"] = function(self, component)
            if self.layout then
                self.layout:layoutComponent(component)
            end
        end,
        ["checkbox"] = function(self, text, tooltipText, optionLoc, clickFunc)
            local checkbox, label = CreateLabeledCheckbox(container, text, tooltipText)
            self:doLayout(checkbox)
            checkbox:SetScript("OnClick", function(self)
                SetOption(optionLoc, this:GetChecked() == 1)
                if clickFunc then
                    clickFunc(self)
                end
            end)
            checkbox:SetChecked(GetOption(optionLoc))
            return checkbox, label
        end,
        ["dropdown"] = function(self, text, tooltipText, optionLoc, options, selectFunc)
            local dropdown, label = CreateLabeledDropdown(container, text, tooltipText)
            self:doLayout(dropdown)
            dropdown:SetSimpleOptions(options, function(option)
                return {
                    text = option,
                    dropdownText = option,
                    initFunc = function(self)
                        self.checked = GetOption(optionLoc) == self.text
                    end,
                    func = function(self)
                        SetOption(optionLoc, self.text)
                        if selectFunc then
                            selectFunc(self)
                        end
                    end
                }
            end, GetOption(optionLoc))
            return dropdown, label
        end,
        ["slider"] = function(self, text, tooltipText, optionLoc, minValue, maxValue)
            local slider, label = CreateLabeledSlider(container, text, tooltipText)
            slider:SetMinMaxValues(minValue, maxValue)
            slider:SetValue(GetOption(optionLoc))
            slider:GetSlider():SetNumberedText()
            local script = slider:GetSlider():GetScript("OnValueChanged")
            slider:GetSlider():SetScript("OnValueChanged", function(self)
                script()
                SetOption(optionLoc, self:GetValue())
            end)
            self:doLayout(slider)
            return slider, label
        end,
        ["label"] = function(self, text, tooltipText)
            -- Dummy frame
            local frame = PTGuiLib.Get("container", container)
                :SetSize(20, 20)
            local label = CreateLabel(container, text)
                :SetPoint(GetLabelPoint(frame))
            self:doLayout(frame)
            return label, frame
        end
    }
end

function GetLabelPoint(relative)
    return "RIGHT", relative, "LEFT", -5, 0
end

function CreateLabeledCheckbox(parent, text, tooltipText)
    local checkbox = CreateCheckbox(parent)
    local label = CreateLabel(parent, text)
    label:SetPoint(GetLabelPoint(checkbox))
    checkbox:ApplyTooltip(tooltipText)
    label:ApplyTooltip(tooltipText)
    return checkbox, label
end

function CreateLabeledDropdown(parent, text, tooltipText)
    local dropdown = CreateDropdown(parent)
    local label = CreateLabel(parent, text)
    label:SetPoint(GetLabelPoint(dropdown))
    dropdown:ApplyTooltip(tooltipText)
    label:ApplyTooltip(tooltipText)
    return dropdown, label
end

function CreateLabeledSlider(parent, text, tooltipText)
    local slider = CreateSlider(parent)
    local label = CreateLabel(parent, text)
    label:SetPoint(GetLabelPoint(slider))
    slider:ApplyTooltip(tooltipText)
    label:ApplyTooltip(tooltipText)
    return slider, label
end

function CreateLinkEditbox(parent, site)
    return PTGuiLib.Get("editbox", parent)
        :SetText(site)
        :SetJustifyH("CENTER")
        :SetScript("OnTextChanged", function(self)
            self:SetText(site)
        end)
end

function CreateDropdown(parent, width)
    return PTGuiLib.Get("dropdown", parent)
        :SetSize(width or 140, 25)
end

function CreateSlider(parent, width, height)
    return PTGuiLib.Get("editbox_slider", parent)
        :SetSize(width or 160, height or 36)
end

function CreateCheckbox(parent, width, height)
    return PTGuiLib.Get("checkbox", parent)
        :SetSize(width or 20, height or 20)
end

function CreateLabel(parent, text)
    return PTGuiLib.GetText(parent, text)
end
