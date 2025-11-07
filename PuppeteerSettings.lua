PuppeteerSettings = {}
PTUtil.SetEnvironment(PuppeteerSettings)

local _G = getfenv(0)
local util = PTUtil

local _, playerClass = UnitClass("player")

function UpdateTrackedDebuffTypes()
    local debuffTypeCureSpells = {
        ["PALADIN"] = {
            ["Purify"] = {"Poison", "Disease"},
            ["Cleanse"] = {"Poison", "Disease", "Magic"}
        },
        ["PRIEST"] = {
            ["Cure Disease"] = {"Disease"},
            ["Abolish Disease"] = {"Disease"},
            ["Dispel Magic"] = {"Magic"}
        },
        ["DRUID"] = {
            ["Cure Poison"] = {"Poison"},
            ["Abolish Poison"] = {"Poison"},
            ["Remove Curse"] = {"Curse"}
        },
        ["SHAMAN"] = {
            ["Cure Poison"] = {"Poison"},
            ["Cure Disease"] = {"Disease"}
        },
        ["MAGE"] = {
            ["Remove Lesser Curse"] = {"Curse"}
        }
    }

    for _, class in ipairs(util.GetClasses()) do
        if not debuffTypeCureSpells[class] then
            debuffTypeCureSpells[class] = {}
        end
    end

    local trackedDebuffTypes = {}
    do
        local id = 1;
        for i = 1, GetNumSpellTabs() do
            local _, _, _, numSpells = GetSpellTabInfo(i);
            for j = 1, numSpells do
                local spellName = GetSpellName(id, "spell");
                local types = debuffTypeCureSpells[playerClass][spellName]
                if types then
                    for _, type in ipairs(types) do
                        trackedDebuffTypes[type] = 1
                    end
                end
                id = id + 1
            end
        end
    end
    TrackedDebuffTypesSet = trackedDebuffTypes
    trackedDebuffTypes = util.ToArray(trackedDebuffTypes)

    TrackedDebuffTypes = trackedDebuffTypes
end

function LetsCrashOut()
    local dialog
    dialog = PTGuiLib.Get("simple_dialog", UIParent)
        :SetPoint("CENTER")
        :SetTitle("Puppeteer")
        :SetText("You are using a newer settings version with an older version of Puppeteer! Either update the addon or "..
            "manually delete its data.")
        :AddButton("Okay", function()
            dialog:Dispose()
        end)
    Puppeteer.UnregisterEventHandlers()
    SeeYaImCrashingOut() -- im crashing out
end

function SetDefaults()
    if not PTOptions then
        _G.PTOptions = {}
    end

    if not PTGlobalOptions then
        _G.PTGlobalOptions = {}
    end


    local OPTIONS_VERSION = 4

    if PTOptions.OptionsVersion and (PTOptions.OptionsVersion > OPTIONS_VERSION) then
        LetsCrashOut()
    end

    if not PTGlobalProfiles.StyleOverrides then
        PTGlobalProfiles.StyleOverrides = {}
    end

    local isHealer = util.IsHealerClass("player")
    local isManaUser = util.ClassPowerTypes[util.GetClass("player")] == "mana"
    do
        local defaults = {
            ["ShowTargets"] = {
                ["Friendly"] = isHealer,
                ["Hostile"] = false
            },
            ["AlwaysShowTargetFrame"] = false,
            ["TargetWhileCasting"] = false,
            ["TargetAfterCasting"] = false,
            ["FrameDrag"] = {
                ["MoveAll"] = false,
                ["AltMoveKey"] = "Shift"
            },
            ["DisablePartyFrames"] = {
                ["InParty"] = false,
                ["InRaid"] = false
            },
            ["SpellsTooltip"] = {
                ["Enabled"] = isHealer,
                ["AttachTo"] = "Button", -- "Button", "Frame", "Group", "Screen"
                ["OffsetX"] = 0,
                ["OffsetY"] = 0,
                ["Anchor"] = "Top Right", -- "Top Left", "Top Right", "Bottom Left", "Bottom Right"
                ["ShowManaCost"] = false,
                ["ShowManaPercentCost"] = true,
                ["HideCastsAbove"] = 3,
                ["CriticalCastsLevel"] = 3,
                ["AbbreviatedKeys"] = false,
                ["ColoredKeys"] = true,
                ["ShowPowerBar"] = true,
                ["ShowPowerAs"] = isManaUser and "Power %" or "Power", -- "Power", "Power/Max Power", "Power %"
                ["ShowItemCount"] = false
            },
            ["ShowAuraTimesAt"] = {
                ["Short"] = 5, -- <1 min
                ["Medium"] = 10, -- <=2 min
                ["Long"] = 60 * 2 -- >2 min
            },
            ["Tracking"] = {
                ["EvaluateInterval"] = 1.25, -- How often everyone is fully scanned to determine if they should be closely tracked
                ["DistanceUpdateInterval"] = 0.1, -- How often distance tracked units are updated
                ["SightUpdateInterval"] = 0.1, -- How often sight tracked units are updated
                ["MinDistanceTracking"] = 20, -- The minimum distance to start closely tracking distance
                ["MaxDistanceTracking"] = 60, -- The maxmimum distance to start closely tracking distance
                ["MaxSightTracking"] = 80 -- The maximum distance to closely track sight
            },
            ["CastWhen"] = "Mouse Up", -- Mouse Up, Mouse Down
            ["CastWhenKey"] = "Key Up", -- Key Up, Key Down
            ["AutoResurrect"] = Puppeteer.ResurrectionSpells[util.GetClass("player")] ~= nil,
            ["UseHealPredictions"] = true,
            ["PVPFlagProtection"] = true,
            ["SetMouseover"] = true,
            ["LFTAutoRole"] = true, -- Turtle WoW
            ["TestUI"] = false,
            ["Hidden"] = false,
            ["HideWhileSolo"] = false,
            ["ChosenProfiles"] = {
                ["Party"] = "Default",
                ["Pets"] = "Default",
                ["Raid"] = "Small",
                ["Raid Pets"] = "Small",
                ["Target"] = "Long",
                ["Focus"] = "Default"
            },
            ["FrameOptions"] = {},
            ["Scripts"] = {
                ["OnLoad"] = "",
                ["OnPostLoad"] = ""
            },
            ["OptionsVersion"] = OPTIONS_VERSION
        }
        local specialDefaults = {
            ["Buttons"] = {
                "LeftButton",
                "MiddleButton",
                "RightButton",
                "Button5",
                "Button4",
                "MOUSEWHEELUP",
                "MOUSEWHEELDOWN"
            },
            ["ButtonInfo"] = {
                ["LeftButton"] = {
                    ["Name"] = "Left",
                    ["ShowUnbound"] = true
                },
                ["MiddleButton"] = {
                    ["Name"] = "Middle",
                    ["ShowUnbound"] = true
                },
                ["RightButton"] = {
                    ["Name"] = "Right",
                    ["ShowUnbound"] = true
                },
                ["Button5"] = {
                    ["Name"] = "Forward",
                    ["ShowUnbound"] = true
                },
                ["Button4"] = {
                    ["Name"] = "Back",
                    ["ShowUnbound"] = true
                },
                ["MOUSEWHEELUP"] = {
                    ["Name"] = "Wheel Up",
                    ["ShowUnbound"] = false
                },
                ["MOUSEWHEELDOWN"] = {
                    ["Name"] = "Wheel Down",
                    ["ShowUnbound"] = false
                },
            }
        }

        local optionsUpgrades = {
            {
                version = 2,
                upgrade = function(self, options)
                    local upgraded = util.CloneTable(options, true)
                    if options["ShowSpellsTooltip"] ~= nil then
                        if not options["SpellsTooltip"] then
                            upgraded["SpellsTooltip"] = {}
                        end
                        upgraded["SpellsTooltip"]["Enabled"] = options["ShowSpellsTooltip"]
                        upgraded["ShowSpellsTooltip"] = nil
                    end
                    if options["ChosenProfiles"] ~= nil then
                        local groupNames = {"Party", "Pets", "Raid", "Raid Pets", "Target"}
                        local changedProfileNames = {
                            ["Compact"] = "Default",
                            ["Compact (Small)"] = "Small",
                            ["Compact (Short Bar)"] = "Default (Short Bar)"
                        }
                        for _, name in ipairs(groupNames) do
                            local currentlySelected = options["ChosenProfiles"][name]
                            if changedProfileNames[currentlySelected] then
                                upgraded["ChosenProfiles"][name] = changedProfileNames[currentlySelected]
                            end
                        end
                    end
                    upgraded["OptionsVersion"] = self.version
                    return upgraded
                end,
                shouldUpgrade = function(self, options)
                    return options.OptionsVersion < self.version
                end
            },
            {
                version = 3,
                upgrade = function(self, options)
                    local upgraded = util.CloneTable(options, true)
                    if options["AutoTarget"] then
                        upgraded["TargetWhileCasting"] = true
                        upgraded["TargetAfterCasting"] = true
                    end
                    if options["Scripts"] then
                        local guard = "-- Auto-generated guard to prevent errors in new addon version, remove if you're sure "..
                            "your script won't produce errors\nif true then return end\n\n"
                        if options["Scripts"]["OnLoad"] ~= nil and options["Scripts"]["OnLoad"] ~= "" then
                            upgraded["Scripts"]["OnLoad"] = guard..options["Scripts"]["OnLoad"]
                        end
                        if options["Scripts"]["OnPostLoad"] ~= nil and options["Scripts"]["OnPostLoad"] ~= "" then
                            upgraded["Scripts"]["OnPostLoad"] = guard..options["Scripts"]["OnPostLoad"]
                        end
                    end
                    upgraded["OptionsVersion"] = self.version
                    return upgraded
                end,
                shouldUpgrade = function(self, options)
                    return options.OptionsVersion < self.version
                end
            }
        }

        if PTOptions.OptionsVersion and PTOptions.OptionsVersion < OPTIONS_VERSION then
            for _, upgrade in ipairs(optionsUpgrades) do
                if upgrade:shouldUpgrade(PTOptions) then
                    local prevVersion = PTOptions.OptionsVersion
                    _G.PTOptions = upgrade:upgrade(PTOptions)
                    DEFAULT_CHAT_FRAME:AddMessage("[Puppeteer] Upgraded options from version "..
                        prevVersion.." to "..upgrade.version)
                end
            end
        end

        ApplyDefaults(PTOptions, defaults)
        -- Special defaults
        if not PTOptions["Buttons"] then
            PTOptions["Buttons"] = util.CloneTable(specialDefaults["Buttons"])
        end
        if not PTOptions["ButtonInfo"] then
            PTOptions["ButtonInfo"] = util.CloneTable(specialDefaults["ButtonInfo"])
        end
    end

    do
        local defaults = {
            ["ShowLoadMessage"] = true,
            ["GlobalFont"] = "Fonts\\FRIZQT__.TTF",
            ["GlobalFontFlags"] = nil, -- nil, "OUTLINE", "THICKOUTLINE", "MONOCHROME"
            ["Experiments"] = {
                ["AutoRole"] = false
            },
            ["OptionsVersion"] = OPTIONS_VERSION
        }
        ApplyDefaults(PTGlobalOptions, defaults)
    end
end

function ApplyDefaults(t, defaults)
    for field, value in pairs(defaults) do
        if type(value) == "table" then
            t[field] = t[field] or {}
            ApplyDefaults(t[field], value)
        elseif t[field] == nil then
            t[field] = value
        end
    end
end

function TraverseOptions(location)
    local path = util.SplitString(location, ".")
    local currentTable = PTOptions
    if path[1] == "Global" then
        currentTable = PTGlobalOptions
        table.remove(path, 1)
    end
    for i = 1, table.getn(path) - 1 do
        currentTable = currentTable[path[i]]
    end
    return currentTable, path[table.getn(path)]
end

function GetOption(location)
    local optionTable, location = TraverseOptions(location)
    return optionTable[location]
end

function SetOption(location, value)
    -- Directly update PTOptions - it will auto-save on logout
    local optionTable, finalKey = TraverseOptions(location)
    optionTable[finalKey] = value
end

-- Buffs/debuffs that significantly modify healing
DefaultTrackedHealingBuffs = {"Amplify Magic", "Dampen Magic"}
DefaultTrackedHealingDebuffs = {"Mortal Strike", "Wound Poison", "Curse of the Deadwood", "Veil of Shadow", "Gehennas' Curse", 
    "Necrotic Poison", "Blood Fury", "Necrotic Aura", 
    "Shadowbane Curse" -- Turtle WoW
}
-- Tracked buffs for all classes
DefaultTrackedBuffs = {
    "Blessing of Protection", "Hand of Protection", "Divine Protection", "Divine Shield", "Divine Intervention", -- Paladin
        "Bulwark of the Righteous", "Blessing of Sacrifice", "Hand of Sacrifice",
    "Power Infusion", "Spirit of Redemption", "Inner Focus", "Abolish Disease", "Power Word: Shield", -- Priest
    "Shield Wall", "Recklessness", "Last Stand", -- Warrior
    "Evasion", "Vanish", -- Rogue
    "Deterrence", "Feign Death", "Mend Pet", -- Hunter
    "Frenzied Regeneration", "Innervate", "Abolish Poison", -- Druid
    "Soulstone Resurrection", "Hellfire", "Health Funnel", -- Warlock
    "Ice Block", "Evocation", "Ice Barrier", "Mana Shield", -- Mage
    "Quel'dorei Meditation", "Grace of the Sunwell", -- Racial
    "First Aid", "Food", "Drink" -- Generic
}
-- Tracked buffs for specific classes
DefaultClassTrackedBuffs = {
    ["PALADIN"] = {"Blessing of Wisdom", "Blessing of Might", "Blessing of Salvation", "Blessing of Sanctuary", 
        "Blessing of Kings", "Blessing of Light", "Greater Blessing of Wisdom", "Greater Blessing of Might", 
        "Greater Blessing of Salvation", "Greater Blessing of Sanctuary", "Greater Blessing of Kings", 
        "Greater Blessing of Light", "Daybreak", "Blessing of Freedom", "Hand of Freedom", "Redoubt", "Holy Shield"},
    ["PRIEST"] = {"Prayer of Fortitude", "Power Word: Fortitude", "Prayer of Spirit", "Divine Spirit", 
        "Prayer of Shadow Protection", "Shadow Protection", "Holy Champion", "Champion's Grace", "Empower Champion", 
        "Champion's Bond", "Fear Ward", "Inner Fire", "Renew", "Greater Heal", "Lightwell Renew", "Inspiration", 
        "Fade", "Spirit Tap", "Enlighten", "Enlightened"},
    ["WARRIOR"] = {"Battle Shout"},
    ["DRUID"] = {"Gift of the Wild", "Mark of the Wild", "Thorns", "Rejuvenation", "Regrowth"},
    ["SHAMAN"] = {"Water Walking", "Healing Way", "Ancestral Fortitude"},
    ["MAGE"] = {"Arcane Brilliance", "Arcane Intellect", "Frost Armor", "Ice Armor", "Mage Armor"},
    ["WARLOCK"] = {"Demon Armor", "Demon Skin", "Unending Breath", "Shadow Ward", "Fire Shield"},
    ["HUNTER"] = {"Rapid Fire", "Quick Shots", "Quick Strikes", "Aspect of the Pack", 
        "Aspect of the Wild", "Bestial Wrath", "Feed Pet Effect"}
}

-- Tracked debuffs for all classes
DefaultTrackedDebuffs = {
    "Forbearance", -- Paladin
    "Death Wish", -- Warrior
    "Enrage", -- Druid
    "Recently Bandaged", "Resurrection Sickness", "Ghost", -- Generic
    "Deafening Screech" -- Applied by mobs
}
-- Tracked debuffs for specific classes
DefaultClassTrackedDebuffs = {
    ["PRIEST"] = {"Weakened Soul"}
}

-- The baked aura sets
TrackedBuffs = {}
TrackedDebuffs = {}
TrackedDebuffTypes = {}
TrackedHealingBuffs = {}
TrackedHealingDebuffs = {}

function BakeTrackedAuras()
    util.ClearTable(TrackedBuffs)
    util.ClearTable(TrackedDebuffs)
    util.ClearTable(TrackedHealingBuffs)
    util.ClearTable(TrackedHealingDebuffs)

    local trackedBuffsArray = {}
    if DefaultClassTrackedBuffs[playerClass] then
        util.AppendArrayElements(trackedBuffsArray, DefaultClassTrackedBuffs[playerClass])
    end
    util.AppendArrayElements(trackedBuffsArray, TrackedHealingBuffs)
    util.AppendArrayElements(trackedBuffsArray, DefaultTrackedBuffs)
    util.ToSet(trackedBuffsArray, true, TrackedBuffs)

    local trackedDebuffsArray = {}
    if DefaultClassTrackedDebuffs[playerClass] then
        util.AppendArrayElements(trackedDebuffsArray, DefaultClassTrackedDebuffs[playerClass])
    end
    util.AppendArrayElements(trackedDebuffsArray, TrackedHealingDebuffs)
    util.AppendArrayElements(trackedDebuffsArray, DefaultTrackedDebuffs)
    util.ToSet(trackedDebuffsArray, true, TrackedDebuffs)

    util.ToSet(DefaultTrackedHealingBuffs, false, TrackedHealingBuffs)
    util.ToSet(DefaultTrackedHealingDebuffs, false, TrackedHealingDebuffs)
end

BakeTrackedAuras()

function AddTrackedBuffs(...)
    for _, buff in ipairs(arg) do
        table.insert(DefaultTrackedBuffs, buff)
    end
    BakeTrackedAuras()
end

function RemoveTrackedBuffs(...)
    for _, buff in ipairs(arg) do
        util.RemoveElement(DefaultTrackedBuffs, buff)
        util.RemoveElement(DefaultClassTrackedBuffs[playerClass], buff)
    end
    BakeTrackedAuras()
end

function AddTrackedDebuffs(...)
    for _, debuff in ipairs(arg) do
        table.insert(DefaultTrackedDebuffs, debuff)
    end
    BakeTrackedAuras()
end

function RemoveTrackedDebuffs(...)
    for _, debuff in ipairs(arg) do
        util.RemoveElement(DefaultTrackedDebuffs, debuff)
        util.RemoveElement(DefaultClassTrackedDebuffs[playerClass], debuff)
    end
    BakeTrackedAuras()
end

DebuffTypeColors = {
    ["Magic"] = {0.35, 0.35, 1},
    ["Curse"] = {0.5, 0, 1},
    ["Disease"] = {0.45, 0.35, 0.16},
    ["Poison"] = {0.6, 0.7, 0}
}

function GetSelectedProfileName(frame)
    local selected = PTOptions.ChosenProfiles[frame]
    if not PTProfileManager.GetProfile(selected) then
        selected = "Default"
    end
    return selected
end

function GetSelectedProfile(frame)
    return PTProfileManager.GetProfile(GetSelectedProfileName(frame))
end

local function validateFrameOptionsExistence(frameName)
    if not PTOptions.FrameOptions[frameName] then
        PTOptions.FrameOptions[frameName] = {}
    end
end

function IsFrameHidden(frameName)
    return PTOptions.FrameOptions[frameName] and PTOptions.FrameOptions[frameName].Hidden
end

function SetFrameHidden(frameName, hidden)
    validateFrameOptionsExistence(frameName)
    -- Directly update PTOptions - it will auto-save on logout
    PTOptions.FrameOptions[frameName].Hidden = hidden
    PTSettingsGui.UpdateFrameOptions()
end

function IsFrameLocked(frameName)
    return PTOptions.FrameOptions[frameName] and PTOptions.FrameOptions[frameName].Locked
end

function SetFrameLocked(frameName, locked)
    validateFrameOptionsExistence(frameName)

    -- Use dirty tracker if available to update both working copy and live options
    if PTDirtyTracker then
        PTDirtyTracker.SetFrameOption(frameName, "Locked", locked)
    else
        PTOptions.FrameOptions[frameName].Locked = locked
    end

    local group = Puppeteer.UnitFrameGroups[frameName]
    if group then
        group:UpdateHeaderColor()
    end
    PTSettingsGui.UpdateFrameOptions()
end

function IsTitleHidden(frameName)
    return PTOptions.FrameOptions[frameName] and PTOptions.FrameOptions[frameName].TitleHidden
end

function SetTitleHidden(frameName, hidden)
    validateFrameOptionsExistence(frameName)

    -- Use dirty tracker if available to update both working copy and live options
    if PTDirtyTracker then
        PTDirtyTracker.SetFrameOption(frameName, "TitleHidden", hidden)
    else
        PTOptions.FrameOptions[frameName].TitleHidden = hidden
    end

    local group = Puppeteer.UnitFrameGroups[frameName]
    if group then
        group:UpdateUIPositions()
    end
    PTSettingsGui.UpdateFrameOptions()
end

function GetFramePosition(frameName)
    if not (PTOptions.FrameOptions[frameName] and PTOptions.FrameOptions[frameName].Position) then
        return "TOPLEFT", (GetScreenWidth() / 2), -(GetScreenHeight() / 2)
    end
    return unpack(PTOptions.FrameOptions[frameName].Position)
end

function SaveFramePositions()
    for frameName, group in pairs(Puppeteer.UnitFrameGroups) do
        local anchor, _, _, x, y = group:GetContainer():GetPoint(1)
        local position = {anchor, x, y}

        -- Use dirty tracker if available to update both working copy and live options
        if PTDirtyTracker then
            PTDirtyTracker.SetFrameOption(frameName, "Position", position)
        else
            -- Fallback to direct update if dirty tracker not available
            if not PTOptions.FrameOptions[frameName] then
                PTOptions.FrameOptions[frameName] = {}
            end
            PTOptions.FrameOptions[frameName].Position = position
        end
    end
end