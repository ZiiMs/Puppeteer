PTProfileData = {}
PTUtil.SetEnvironment(PTProfileData)

local _G = getfenv(0)
local util = PTUtil

--[[
    Profile Data Structure:
    A profile contains all character-specific settings:
    - ChosenProfiles: Which style each frame group uses
    - FrameOptions: Frame positions, hidden, locked states
    - AddonOptions: All PTOptions settings (excluding ChosenProfiles and FrameOptions)
    - Bindings: Complete keybinding configuration
    - StyleOverrides: Customizations to styles
]]

-- Captures the current settings and returns them as profile data
function GetCurrentProfileData()
    local profileData = {}

    -- Capture chosen profiles (which style each frame uses)
    profileData.ChosenProfiles = util.CloneTable(PTOptions.ChosenProfiles, true)

    -- Capture frame options (positions, hidden, locked states)
    profileData.FrameOptions = util.CloneTable(PTOptions.FrameOptions, true)

    -- Capture all other addon options
    profileData.AddonOptions = {}
    for key, value in pairs(PTOptions) do
        if key ~= "ChosenProfiles" and key ~= "FrameOptions" and key ~= "OptionsVersion" then
            if type(value) == "table" then
                profileData.AddonOptions[key] = util.CloneTable(value, true)
            else
                profileData.AddonOptions[key] = value
            end
        end
    end

    -- Capture bindings
    profileData.Bindings = util.CloneTable(PTBindings or {}, true)

    -- Capture style overrides
    profileData.StyleOverrides = util.CloneTable(PTGlobalProfiles.StyleOverrides or {}, true)

    return profileData
end

-- Applies profile data to the current session
-- This updates PTOptions, PTBindings, and PTGlobalProfiles.StyleOverrides
function ApplyProfileData(profileData)
    if not profileData then
        DEFAULT_CHAT_FRAME:AddMessage("[Puppeteer] Error: Attempted to apply nil profile data")
        return false
    end

    -- Apply chosen profiles
    if profileData.ChosenProfiles then
        PTOptions.ChosenProfiles = util.CloneTable(profileData.ChosenProfiles, true)
    end

    -- Apply frame options
    if profileData.FrameOptions then
        PTOptions.FrameOptions = util.CloneTable(profileData.FrameOptions, true)
    end

    -- Apply addon options
    if profileData.AddonOptions then
        for key, value in pairs(profileData.AddonOptions) do
            if type(value) == "table" then
                PTOptions[key] = util.CloneTable(value, true)
            else
                PTOptions[key] = value
            end
        end
    end

    -- Apply bindings
    if profileData.Bindings then
        _G.PTBindings = util.CloneTable(profileData.Bindings, true)
    end

    -- Apply style overrides
    if profileData.StyleOverrides then
        PTGlobalProfiles.StyleOverrides = util.CloneTable(profileData.StyleOverrides, true)
    end

    return true
end

-- Returns default profile data based on current defaults
-- This is used when creating a new profile
function GetDefaultProfileData()
    -- First, apply defaults to a temporary table
    local tempOptions = {}
    local tempGlobalOptions = {}

    -- Save current options
    local savedOptions = PTOptions
    local savedGlobalOptions = PTGlobalOptions

    -- Temporarily set empty tables
    _G.PTOptions = tempOptions
    _G.PTGlobalOptions = tempGlobalOptions

    -- Apply defaults
    PuppeteerSettings.SetDefaults()

    -- Capture the defaults as profile data
    local defaultData = GetCurrentProfileData()

    -- Restore original options
    _G.PTOptions = savedOptions
    _G.PTGlobalOptions = savedGlobalOptions

    -- Clear style overrides for default profile
    defaultData.StyleOverrides = {}

    -- Clear bindings for default profile
    defaultData.Bindings = {}

    return defaultData
end

-- Saves profile data to global storage
function SaveProfile(profileName, profileData)
    if not profileName or profileName == "" then
        DEFAULT_CHAT_FRAME:AddMessage("[Puppeteer] Error: Invalid profile name")
        return false
    end

    if not _G.PTGlobalProfilesData then
        _G.PTGlobalProfilesData = {}
    end

    _G.PTGlobalProfilesData[profileName] = util.CloneTable(profileData, true)
    return true
end

-- Loads profile data from global storage
function LoadProfile(profileName)
    if not profileName or profileName == "" then
        DEFAULT_CHAT_FRAME:AddMessage("[Puppeteer] Error: Invalid profile name")
        return nil
    end

    if not _G.PTGlobalProfilesData then
        DEFAULT_CHAT_FRAME:AddMessage("[Puppeteer] Error: No profiles data found")
        return nil
    end

    local profileData = _G.PTGlobalProfilesData[profileName]
    if not profileData then
        DEFAULT_CHAT_FRAME:AddMessage("[Puppeteer] Error: Profile '"..profileName.."' not found")
        return nil
    end

    return util.CloneTable(profileData, true)
end

-- Gets a list of all available profile names
function GetProfileList()
    if not _G.PTGlobalProfilesData then
        return {}
    end

    local profiles = {}
    for name, _ in pairs(_G.PTGlobalProfilesData) do
        table.insert(profiles, name)
    end
    table.sort(profiles)
    return profiles
end

-- Checks if a profile exists
function ProfileExists(profileName)
    return _G.PTGlobalProfilesData and _G.PTGlobalProfilesData[profileName] ~= nil
end

-- Deletes a profile from global storage
function DeleteProfile(profileName)
    if not _G.PTGlobalProfilesData or not _G.PTGlobalProfilesData[profileName] then
        DEFAULT_CHAT_FRAME:AddMessage("[Puppeteer] Error: Profile '"..profileName.."' not found")
        return false
    end

    _G.PTGlobalProfilesData[profileName] = nil
    return true
end

-- Renames a profile
function RenameProfile(oldName, newName)
    if not ProfileExists(oldName) then
        DEFAULT_CHAT_FRAME:AddMessage("[Puppeteer] Error: Profile '"..oldName.."' not found")
        return false
    end

    if ProfileExists(newName) then
        DEFAULT_CHAT_FRAME:AddMessage("[Puppeteer] Error: Profile '"..newName.."' already exists")
        return false
    end

    _G.PTGlobalProfilesData[newName] = _G.PTGlobalProfilesData[oldName]
    _G.PTGlobalProfilesData[oldName] = nil

    -- Update character profile selection if they were using the old name
    if _G.PTCharacterProfile then
        for charName, selectedProfile in pairs(_G.PTCharacterProfile) do
            if selectedProfile == oldName then
                _G.PTCharacterProfile[charName] = newName
            end
        end
    end

    return true
end

-- Copies a profile to a new name
function CopyProfile(sourceName, destName)
    if not ProfileExists(sourceName) then
        DEFAULT_CHAT_FRAME:AddMessage("[Puppeteer] Error: Profile '"..sourceName.."' not found")
        return false
    end

    if ProfileExists(destName) then
        DEFAULT_CHAT_FRAME:AddMessage("[Puppeteer] Error: Profile '"..destName.."' already exists")
        return false
    end

    local sourceData = LoadProfile(sourceName)
    if not sourceData then
        return false
    end

    return SaveProfile(destName, sourceData)
end

-- Helper function to get full character name (Name-Realm)
local function GetPlayerFullName()
    local name = UnitName("player")
    local realm = GetRealmName()
    return name.."-"..realm
end

-- Gets the current character's selected profile name
function GetCurrentCharacterProfile()
    if not _G.PTCharacterProfile then
        _G.PTCharacterProfile = {}
    end

    local charName = GetPlayerFullName()
    return _G.PTCharacterProfile[charName] or "Default"
end

-- Sets the current character's selected profile
function SetCurrentCharacterProfile(profileName)
    if not _G.PTCharacterProfile then
        _G.PTCharacterProfile = {}
    end

    local charName = GetPlayerFullName()
    _G.PTCharacterProfile[charName] = profileName
end

-- Creates a new profile with the given name, optionally copying from an existing profile
function CreateProfile(profileName, copyFromProfile)
    if not profileName or profileName == "" then
        DEFAULT_CHAT_FRAME:AddMessage("[Puppeteer] Error: Invalid profile name")
        return false
    end

    if ProfileExists(profileName) then
        DEFAULT_CHAT_FRAME:AddMessage("[Puppeteer] Error: Profile '"..profileName.."' already exists")
        return false
    end

    local profileData
    if copyFromProfile and copyFromProfile ~= "" then
        -- Copy from existing profile
        profileData = LoadProfile(copyFromProfile)
        if not profileData then
            return false
        end
    else
        -- Create from defaults
        profileData = GetDefaultProfileData()
    end

    return SaveProfile(profileName, profileData)
end
