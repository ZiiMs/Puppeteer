-- ColorPalette.lua
-- Defines predefined color palette system for text customization

Puppeteer = Puppeteer or {}

-- Predefined color palette
Puppeteer.ColorPalette = {
	["Class"] = "CLASS", -- Special value: uses unit's class color
	["White"] = {1, 1, 1},
	["Red"] = {1, 0, 0},
	["Green"] = {0, 1, 0},
	["Blue"] = {0, 0, 1},
	["Yellow"] = {1, 1, 0},
	["Orange"] = {1, 0.5, 0},
	["Purple"] = {0.7, 0, 1},
	["Cyan"] = {0, 1, 1},
	["Gray"] = {0.5, 0.5, 0.5},
	["Light Green"] = {0.5, 1, 0.5},
	["Light Blue"] = {0.5, 0.5, 1},
	["Pink"] = {1, 0.5, 0.75},
	["Dark Red"] = {0.7, 0, 0},
	["Dark Green"] = {0, 0.7, 0},
	["Dark Blue"] = {0, 0, 0.7},
}

-- Ordered list of palette names for dropdown menus
Puppeteer.ColorPaletteOrder = {
	"Class",
	"White",
	"Red",
	"Green",
	"Blue",
	"Yellow",
	"Orange",
	"Purple",
	"Cyan",
	"Gray",
	"Light Green",
	"Light Blue",
	"Pink",
	"Dark Red",
	"Dark Green",
	"Dark Blue",
}

-- Get color RGB values from palette name
-- Returns: r, g, b, isClassColor
function Puppeteer.GetColorFromPalette(colorName, unit)
	local colorValue = Puppeteer.ColorPalette[colorName]

	if not colorValue then
		-- Default to white if invalid color name
		return 1, 1, 1, false
	end

	if colorValue == "CLASS" then
		-- Return class color for the given unit
		if unit then
			-- Use protected call to avoid errors with custom/invalid units
			local success, exists = pcall(UnitExists, unit)
			if success and exists then
				local _, class = UnitClass(unit)
				if class then
					local color = RAID_CLASS_COLORS[class]
					if color then
						return color.r, color.g, color.b, true
					end
				end
			end
		end
		-- Fallback to white if no unit or class found
		return 1, 1, 1, false
	else
		-- Return RGB values from table
		return colorValue[1], colorValue[2], colorValue[3], false
	end
end

-- Apply text color to a font string
function Puppeteer.ApplyTextColor(fontString, colorName, unit)
	if not fontString or not colorName then
		return
	end

	local r, g, b = Puppeteer.GetColorFromPalette(colorName, unit)
	fontString:SetTextColor(r, g, b)
end

-- Get color preview string for UI display (returns "|cRRGGBBAA" format)
function Puppeteer.GetColorPreviewString(colorName, sampleText)
	sampleText = sampleText or "Sample"

	local colorValue = Puppeteer.ColorPalette[colorName]
	if not colorValue then
		return sampleText
	end

	if colorValue == "CLASS" then
		-- For class color, show a generic preview (can't know unit in UI)
		return "|cFF00FF00" .. sampleText .. "|r" -- Green as placeholder
	else
		local r, g, b = colorValue[1], colorValue[2], colorValue[3]
		local hexR = string.format("%02X", math.floor(r * 255))
		local hexG = string.format("%02X", math.floor(g * 255))
		local hexB = string.format("%02X", math.floor(b * 255))
		return "|cFF" .. hexR .. hexG .. hexB .. sampleText .. "|r"
	end
end
