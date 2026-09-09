--[[===========================================================================
	Vallex AI — External Themes Module
	===========================================================================
	HOSTING (required for the split-setup to work):
	  1) Upload this file to GitHub (raw URL) or a Pastebin RAW link.
	     GitHub : https://raw.githubusercontent.com/<user>/<repo>/main/VallexAIThemes.lua
	  2) Paste that URL into CONFIG.ThemesURL inside VallexAI.lua.
	  3) The main script fetches + loadstring()s this file at startup and
	     merges every theme below into the GUI. A local copy placed at
	     "Vallex AI File/VallexAIThemes.lua" takes priority over the remote.

	Each theme is a color-role table consumed by the GUI:
	  Background / Surface / Accent / Text / SubText / Stroke /
	  Success / Error / OnAccent
===========================================================================]]--

local Themes = {}

-- // palette helpers ----------------------------------------------------------
local function clamp01(n)
	if n < 0 then return 0 elseif n > 1 then return 1 end
	return n
end

local function shade(c, f)
	return Color3.new(clamp01(c.R * f), clamp01(c.G * f), clamp01(c.B * f))
end

local function lum(c)
	return 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
end

local function mix(a, b, t)
	return Color3.new(
		a.R + (b.R - a.R) * t,
		a.G + (b.G - a.G) * t,
		a.B + (b.B - a.B) * t
	)
end

-- // registrar ---------------------------------------------------------------
local function add(name, bg, surface, accent, text, over)
	over = over or {}
	local dark = lum(bg) < 0.5
	local txt = text or (dark and Color3.fromRGB(235, 235, 240) or Color3.fromRGB(28, 28, 34))
	Themes[name] = {
		Name       = name,
		Background = bg,
		Surface    = surface,
		Accent     = accent,
		Text       = txt,
		SubText    = over.SubText or mix(txt, bg, 0.42),
		Stroke     = over.Stroke or (dark and shade(bg, 2.1) or shade(bg, 0.85)),
		Success    = over.Success or Color3.fromRGB(87, 242, 135),
		Error      = over.Error or Color3.fromRGB(237, 66, 69),
		OnAccent   = (lum(accent) > 0.62) and Color3.fromRGB(24, 24, 28) or Color3.fromRGB(255, 255, 255),
	}
end

local C = Color3.fromRGB

-- //=======================================================================//--
-- //                             BASE THEMES (16)                          //--
-- //=======================================================================//--

add("Dark",    C(18, 18, 24),   C(28, 28, 36),   C(88, 101, 242))
add("Light",   C(243, 244, 248),C(255, 255, 255),C(88, 101, 242))
add("Red",     C(30, 14, 16),   C(44, 22, 26),   C(239, 68, 68))
add("Green",   C(12, 26, 18),   C(20, 38, 27),   C(52, 199, 123))
add("Blue",    C(12, 20, 34),   C(20, 32, 50),   C(59, 130, 246))
add("Yellow",  C(30, 26, 10),   C(44, 39, 16),   C(250, 204, 21))
add("Cyan",    C(8, 26, 30),    C(14, 40, 45),   C(34, 211, 238))
add("Magenta", C(30, 10, 26),   C(45, 18, 39),   C(232, 62, 214))
add("Orange",  C(30, 18, 8),    C(46, 28, 13),   C(249, 115, 22))
add("Purple",  C(22, 12, 34),   C(34, 20, 50),   C(168, 85, 247))
add("Pink",    C(32, 12, 24),   C(48, 20, 36),   C(244, 114, 182))
add("Lime",    C(16, 26, 10),   C(25, 40, 16),   C(163, 230, 53))
add("Teal",    C(8, 26, 26),    C(14, 40, 40),   C(45, 212, 191))
add("Indigo",  C(16, 16, 38),   C(26, 26, 56),   C(99, 102, 241))
add("Violet",  C(24, 12, 38),   C(37, 20, 56),   C(139, 92, 246))
add("Brown",   C(26, 18, 12),   C(40, 28, 19),   C(180, 124, 74))

-- //=======================================================================//--
-- //                            PRESET THEMES (70)                         //--
-- //=======================================================================//--

-- Reds / warm
add("Crimson",      C(26, 8, 12),    C(40, 14, 19),   C(220, 38, 38))
add("Scarlet",      C(30, 10, 8),    C(46, 16, 13),   C(239, 68, 68))
add("Ruby",         C(28, 8, 14),    C(43, 13, 22),   C(225, 29, 72))
add("Rose",         C(32, 14, 20),   C(48, 22, 30),   C(251, 113, 133))

-- Blues
add("Ocean",        C(8, 20, 32),    C(14, 31, 48),   C(56, 142, 222))
add("Deep Ocean",   C(5, 12, 22),    C(9, 20, 34),    C(37, 99, 178))
add("Arctic Ocean", C(226, 236, 244),C(245, 250, 253),C(46, 134, 193))
add("Aqua",         C(7, 24, 26),    C(12, 37, 40),   C(72, 214, 222))
add("Deep Aqua",    C(4, 16, 20),    C(7, 26, 32),    C(22, 150, 160))

-- Greens
add("Emerald",      C(7, 24, 16),    C(12, 37, 25),   C(52, 211, 153))
add("Deep Emerald", C(4, 16, 11),    C(7, 26, 17),    C(16, 150, 106))
add("Forest",       C(9, 20, 12),    C(15, 31, 19),   C(67, 160, 89))
add("Mint",         C(228, 246, 238),C(247, 253, 250),C(62, 187, 144))
add("Lime Green",   C(14, 24, 8),    C(22, 37, 13),   C(132, 204, 22))
add("Toxic Green",  C(10, 22, 6),    C(16, 34, 10),   C(126, 255, 0),   nil, { Success = C(126, 255, 0) })

-- Orange / gold
add("Sunset",       C(30, 14, 10),   C(46, 22, 16),   C(251, 146, 60))
add("Deep Sunset",  C(22, 10, 8),    C(34, 16, 13),   C(234, 101, 38))
add("Solar",        C(28, 24, 8),    C(43, 37, 13),   C(253, 224, 71))
add("Amber",        C(28, 20, 8),    C(43, 31, 13),   C(245, 158, 11))
add("Golden",       C(28, 22, 8),    C(43, 34, 13),   C(250, 204, 0))

-- Blues / purples
add("Royal Blue",   C(10, 14, 34),   C(16, 22, 50),   C(79, 110, 247))
add("Deep Blue",    C(6, 10, 26),    C(10, 16, 40),   C(49, 73, 201))
add("Midnight Blue",C(8, 10, 24),    C(13, 16, 37),   C(67, 88, 220))
add("Sapphire",     C(7, 14, 30),    C(11, 22, 46),   C(30, 136, 229))
add("Sky",          C(224, 238, 250),C(243, 249, 254),C(14, 165, 233))
add("Deep Sky",     C(6, 16, 28),    C(10, 25, 43),   C(2, 132, 199))
add("Royal Purple", C(20, 10, 32),   C(31, 16, 48),   C(147, 86, 240))
add("Deep Purple",  C(14, 7, 24),    C(22, 11, 37),   C(109, 40, 217))
add("Amethyst",     C(24, 14, 34),   C(36, 22, 50),   C(167, 110, 246))
add("Grape",        C(22, 10, 26),   C(34, 16, 39),   C(154, 60, 198))
add("Lavender",     C(238, 234, 248),C(250, 248, 254),C(150, 123, 236))
add("Neon Purple",  C(16, 6, 26),    C(25, 10, 39),   C(217, 70, 239))

-- Pinks
add("Hot Pink",     C(30, 8, 20),    C(46, 13, 31),   C(236, 72, 153))
add("Bubblegum",    C(248, 231, 240),C(254, 244, 250),C(236, 110, 173))
add("Cotton Candy", C(240, 234, 248),C(251, 247, 254),C(192, 132, 252))
add("Coral",        C(32, 16, 14),   C(48, 25, 22),   C(255, 127, 109))
add("Peach",        C(250, 236, 228),C(254, 247, 243),C(251, 146, 120))
add("Rose Gold",    C(240, 228, 228),C(250, 242, 242),C(183, 110, 121))

-- Metals / neutrals
add("Copper",       C(28, 16, 10),   C(43, 25, 16),   C(200, 110, 60))
add("Bronze",       C(24, 18, 10),   C(37, 28, 16),   C(176, 124, 60))
add("Silver",       C(232, 234, 238),C(246, 248, 250),C(148, 158, 172))
add("Platinum",     C(238, 240, 244),C(250, 252, 254),C(138, 148, 164))
add("Graphite",     C(20, 21, 24),   C(31, 33, 38),   C(108, 117, 131))
add("Slate",        C(24, 28, 34),   C(37, 43, 52),   C(100, 116, 139))
add("Midnight",     C(10, 10, 16),   C(16, 16, 25),   C(99, 102, 241))
add("Void",         C(5, 5, 8),      C(9, 9, 14),     C(120, 80, 255))
add("Obsidian",     C(12, 12, 14),   C(19, 19, 22),   C(88, 94, 106))
add("Monochrome",   C(14, 14, 14),   C(22, 22, 22),   C(235, 235, 235))

-- Retro / neon
add("Neon",         C(10, 10, 14),   C(16, 16, 22),   C(57, 255, 20))
add("Cyber",        C(8, 12, 14),    C(13, 19, 22),   C(0, 229, 255))
add("Cyberpunk",    C(16, 8, 22),    C(25, 13, 34),   C(255, 0, 153),   nil, { Success = C(255, 224, 0) })
add("Synthwave",    C(20, 10, 30),   C(31, 16, 46),   C(255, 94, 180))
add("Vaporwave",    C(24, 16, 38),   C(37, 25, 57),   C(127, 208, 255))
add("Aurora",       C(8, 16, 22),    C(13, 25, 34),   C(94, 234, 212))
add("Galaxy",       C(12, 10, 26),   C(19, 16, 40),   C(162, 110, 245))
add("Space",        C(8, 9, 14),     C(13, 14, 22),   C(110, 120, 245))
add("Twilight",     C(16, 14, 30),   C(25, 22, 46),   C(129, 110, 240))
add("Eclipse",      C(10, 8, 12),    C(16, 13, 19),   C(220, 180, 90))

-- Fire
add("Inferno",      C(24, 8, 6),     C(37, 13, 10),   C(255, 90, 40))
add("Lava",         C(22, 8, 6),     C(34, 13, 10),   C(255, 60, 40),   nil, { Error = C(255, 90, 40) })
add("Ember",        C(24, 12, 8),    C(37, 19, 13),   C(255, 120, 60))

-- Cold
add("Ice",          C(226, 240, 248),C(244, 250, 254),C(125, 190, 232))
add("Frost",        C(230, 242, 246),C(246, 252, 254),C(108, 180, 210))
add("Glacier",      C(14, 24, 34),   C(22, 37, 52),   C(120, 190, 230))
add("Storm",        C(18, 20, 26),   C(28, 31, 40),   C(120, 140, 180))
add("Thunder",      C(14, 14, 20),   C(22, 22, 31),   C(255, 214, 64))

-- Dark occult
add("Shadow",       C(8, 8, 10),     C(13, 13, 16),   C(70, 72, 80))
add("Blood Moon",   C(20, 6, 8),     C(31, 10, 13),   C(200, 30, 40),   nil, { Error = C(255, 60, 60) })
add("Moonlight",    C(14, 16, 24),   C(22, 25, 37),   C(190, 200, 225))
add("Starlight",    C(10, 12, 22),   C(16, 19, 34),   C(250, 240, 180))

return Themes
