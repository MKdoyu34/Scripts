--[[
        =====================================================================
        StudioGUI Creator v3.0 — WYSIWYG GUI editor for script executors
        =====================================================================
        Run it: paste the whole file into your executor (Delta, Fluxus,
        Synapse, Script-Ware, KRNL, ...) and execute. Single file, no
        dependencies beyond the executor itself.

        v3.0 — FIXES + REQUESTED FEATURES:
          * Window drag REWRITTEN (delta-based, mouse AND touch) — the
            editor window is draggable again, including on mobile.
          * Toolbox lists UI-RELATED CLASSES ONLY by default. The
            "List: UI / All" toggle button switches the catalog.
          * LocalScript / ModuleScript toolbar buttons — new scripts come
            with real starter code (click handler when parented to a
            button), and "Edit Source" opens a code editor for any script.
          * Properties panel fixed (UIGradient & co. showed nothing):
            property discovery now MERGES getproperties +
            getpropertychangedsignals + native GetPropertyChangedSignals +
            probe pool, and one bad property can never blank the panel.
          * Explorer: search box, per-node collapse/expand (+/–),
            Expand-All / Collapse-All buttons.
          * New instances land at the BOTTOM of the selected parent
            (last child), never nested under some unrelated instance.
          * "CoreGui" toggle moves the project between PlayerGui and the
            protected GUI (gethui / CoreGui).
          * Saves keep CUSTOM NAMES: the save list shows every *.json /
            *.luau file found, not just SaveN.

        SAVE / LOAD (executor filesystem API):
          * "Save"  -> Save1.json (HttpService JSON)  or  Save1.luau
                (native Luau `return { ... }` data table). Default name Save1.
          * "Load"  -> rebuilds the project from either format; a .luau file
                that is a runnable EXPORT SCRIPT is executed and adopted.
          * Functions used: writefile, readfile, appendfile (session log),
            listfiles (auto-discover SaveN.json/.luau), isfile, isfolder,
            makefolder (SGC_Saves/ backups), delfile (delete a save),
            delfolder (wipe backups), loadfile + dofile (read .luau saves),
            getcustomasset (load local image files into Content properties).
          * Every save also writes a timestamped backup into SGC_Saves/
            (only the last 8 backups per name are kept).

        Editor UI mounts in gethui()/CoreGui; YOUR project lives under
        PlayerGui tagged with the "SGC_Project" attribute (the last
        remaining project ScreenGui cannot be deleted).

        Export: clean standalone re-runnable Luau generated from the same
        reflection data (defaults stripped, parent-last mounting).
        =====================================================================
]]

-- ====================================================================
-- SERVICES / ENVIRONMENT
-- ====================================================================

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local HttpService      = game:GetService("HttpService")

local LP             = Players.LocalPlayer
local PROJECT_PARENT = LP:WaitForChild("PlayerGui")

local PROJECT_ATTRIBUTE = "SGC_Project"
local MIN_SIZE          = 4
local SAVE_MAGIC        = "SGC_SAVE"
local SAVE_DIR          = "SGC_Saves"
local EXPORT_FILENAME   = "studiogui_export.lua"

-- --------------------------------------------------------------------
-- Executor capability probe. Every single capability is optional.
-- --------------------------------------------------------------------

local RAW = {}
pcall(function()
        RAW.writefile                 = writefile
        RAW.readfile                  = readfile
        RAW.appendfile                = appendfile
        RAW.listfiles                 = listfiles
        RAW.isfile                    = isfile
        RAW.isfolder                  = isfolder
        RAW.makefolder                = makefolder
        RAW.delfile                   = delfile
        RAW.delfolder                 = delfolder
        RAW.loadfile                  = loadfile
        RAW.dofile                    = dofile
        RAW.loadstring                = loadstring
        RAW.getcustomasset            = getcustomasset
        RAW.getproperties             = getproperties
        RAW.getpropertychangedsignals = getpropertychangedsignals
        RAW.getchangedsignals         = getchangedsignals
        RAW.getnilinstances           = getnilinstances
        RAW.setclipboard              = setclipboard
        RAW.identifyexecutor          = identifyexecutor
        RAW.gethui                    = gethui
end)

local function grab(name)
        local v = RAW[name]
        if type(v) ~= "function" then
                v = rawget(_G, name)
        end
        if type(v) == "function" then
                return v
        end
        return nil
end

local Executor = {
        name                      = "Unknown",
        writefile                 = grab("writefile"),
        readfile                  = grab("readfile"),
        appendfile                = grab("appendfile"),
        listfiles                 = grab("listfiles"),
        isfile                    = grab("isfile"),
        isfolder                  = grab("isfolder"),
        makefolder                = grab("makefolder"),
        delfile                   = grab("delfile"),
        delfolder                 = grab("delfolder"),
        loadfile                  = grab("loadfile"),
        dofile                    = grab("dofile"),
        loadstring                = grab("loadstring"),
        getcustomasset            = grab("getcustomasset"),
        getproperties             = grab("getproperties"),
        getpropertychangedsignals = grab("getpropertychangedsignals"),
        getchangedsignals         = grab("getchangedsignals"),
        getnilinstances           = grab("getnilinstances"),
        setclipboard              = grab("setclipboard"),
}

if not Executor.getpropertychangedsignals then
        Executor.getpropertychangedsignals = Executor.getchangedsignals
end

do
        local fn = grab("identifyexecutor")
        if fn then
                local ok, name = pcall(fn)
                if ok and type(name) == "string" and #name > 0 then
                        Executor.name = name
                end
        end
end

-- --------------------------------------------------------------------
-- Protected UI parent (gethui -> CoreGui -> PlayerGui)
-- --------------------------------------------------------------------

local protectedParent
local function resolveProtectedParent()
        local gethuiFn = grab("gethui")
        if gethuiFn then
                local ok, hui = pcall(gethuiFn)
                if ok and typeof(hui) == "Instance" then
                        protectedParent = hui
                        return protectedParent
                end
        end
        local okCG, cg = pcall(function()
                return game:GetService("CoreGui")
        end)
        if okCG and typeof(cg) == "Instance" then
                protectedParent = cg
                return protectedParent
        end
        protectedParent = PROJECT_PARENT
        return protectedParent
end

-- ====================================================================
-- EXECUTOR FILESYSTEM LAYER
-- writefile / readfile / appendfile / listfiles / isfile / isfolder /
-- makefolder / delfile / delfolder / loadfile / dofile / getcustomasset
-- Every function is optional; the layer degrades gracefully.
-- ====================================================================

local FS = {}
FS.capable = (Executor.writefile ~= nil and Executor.readfile ~= nil)

function FS.ensureDir()
        if Executor.makefolder and Executor.isfolder then
                local ok, exists = pcall(Executor.isfolder, SAVE_DIR)
                if ok and exists ~= true then
                        pcall(Executor.makefolder, SAVE_DIR)
                end
        end
end

function FS.baseName(path)
        return tostring(path):match("[/\\]([^/\\]+)$") or tostring(path)
end

function FS.path(name, fmt)
        return tostring(name) .. "." .. (fmt == "luau" and "luau" or "json")
end

function FS.exists(path)
        if Executor.isfile then
                local ok, res = pcall(Executor.isfile, path)
                if ok and res == true then
                        return true
                end
        end
        if Executor.readfile then
                local ok, data = pcall(Executor.readfile, path)
                if ok and type(data) == "string" then
                        return true
                end
        end
        return false
end

function FS.log(line)
        if not Executor.appendfile then
                return
        end
        pcall(function()
                FS.ensureDir()
                Executor.appendfile(SAVE_DIR .. "/log.txt", ("[%s] %s\n"):format(os.date("%Y-%m-%d %H:%M:%S"), tostring(line)))
        end)
end

function FS.write(path, data)
        FS.ensureDir()
        local ok, err = pcall(Executor.writefile, path, tostring(data))
        FS.log(("write %s -> %s"):format(path, ok and ("ok, " .. #tostring(data) .. " bytes") or ("FAILED: " .. tostring(err))))
        return ok, err
end

function FS.read(path)
        local ok, data = pcall(Executor.readfile, path)
        if ok and type(data) == "string" then
                return data
        end
        return nil
end

function FS.delete(path)
        if not Executor.delfile then
                return false
        end
        local ok = pcall(Executor.delfile, path)
        FS.log("delete " .. tostring(path) .. " -> " .. (ok and "ok" or "FAILED"))
        return ok
end

-- Auto-discovers save files at the executor workspace root. ANY custom
-- name is supported ("MyGui.json", "Save1.luau", ...) — every *.json /
-- *.luau found is listed, not just SaveN.
function FS.listSaves()
        local found, seen = {}, {}
        local function scanRoot(rootArg)
                if not Executor.listfiles then
                        return
                end
                local ok, list = pcall(Executor.listfiles, rootArg)
                if ok and type(list) == "table" then
                        for _, path in ipairs(list) do
                                local base = FS.baseName(tostring(path))
                                local stem, ext = base:match("^([%w%-_]+)%.([%a]+)$")
                                if stem and (ext == "json" or ext == "luau") then
                                        local key = base:lower()
                                        if not seen[key] then
                                                seen[key] = true
                                                found[#found + 1] = {
                                                        name = stem,
                                                        fmt = ext,
                                                        path = tostring(path),
                                                }
                                        end
                                end
                        end
                end
        end
        for _, rootArg in ipairs({ "", "." }) do
                scanRoot(rootArg)
        end
        -- probe fallback for executors without listfiles
        if #found == 0 then
                for slot = 1, 9 do
                        for _, fmt in ipairs({ "json", "luau" }) do
                                local name = ("Save%d"):format(slot)
                                local path = FS.path(name, fmt)
                                if FS.exists(path) then
                                        found[#found + 1] = { name = name, fmt = fmt, path = path }
                                end
                        end
                end
        end
        table.sort(found, function(a, b)
                local sa = a.name:match("^Save(%d+)$")
                local sb = b.name:match("^Save(%d+)$")
                if sa and sb and sa ~= sb then
                        return tonumber(sa) < tonumber(sb)
                end
                local aHas, bHas = (sa ~= nil), (sb ~= nil)
                if aHas ~= bHas then
                        return aHas
                end
                if a.name:lower() ~= b.name:lower() then
                        return a.name:lower() < b.name:lower()
                end
                return a.fmt < b.fmt
        end)
        return found
end

function FS.backup(saveName, fmt, data)
        if not Executor.makefolder or not Executor.writefile then
                return
        end
        pcall(function()
                FS.ensureDir()
                local stamp = os.date("%Y%m%d-%H%M%S")
                Executor.writefile(SAVE_DIR .. "/" .. saveName .. "-" .. stamp .. "." .. fmt, tostring(data))
                if Executor.listfiles and Executor.delfile then
                        local ok, list = pcall(Executor.listfiles, SAVE_DIR)
                        if ok and type(list) == "table" then
                                local mine = {}
                                local pattern = "^" .. saveName .. "%-%d%d%d%d%d%d%d%d%-%d%d%d%d%d%d%." .. fmt .. "$"
                                for _, path in ipairs(list) do
                                        if FS.baseName(path):match(pattern) then
                                                mine[#mine + 1] = tostring(path)
                                        end
                                end
                                table.sort(mine)
                                while #mine > 8 do
                                        pcall(Executor.delfile, table.remove(mine, 1))
                                end
                        end
                end
        end)
end

function FS.wipeBackups()
        if Executor.isfolder then
                local ok, exists = pcall(Executor.isfolder, SAVE_DIR)
                if ok and exists ~= true then
                        return false
                end
        end
        if Executor.delfolder then
                local ok = pcall(Executor.delfolder, SAVE_DIR)
                if ok then
                        return true
                end
        end
        if Executor.listfiles and Executor.delfile then
                local ok, list = pcall(Executor.listfiles, SAVE_DIR)
                if ok and type(list) == "table" then
                        for _, path in ipairs(list) do
                                pcall(Executor.delfile, tostring(path))
                        end
                        return true
                end
        end
        return false
end

-- ====================================================================
-- REFLECTION ENGINE
--   Auto-discovers classes + reads / serializes / parses EVERY
--   property dynamically. No hardcoded class catalog, no hardcoded
--   property schema anywhere in this script.
-- ====================================================================

local Reflection = {
        uiClasses     = {},  -- sorted array of validated UI-related classes
        allClasses    = {},  -- sorted array of ALL validated creatable classes
        classIndex    = {},  -- name -> true
        classVersion  = 0,   -- bumped while background discovery adds classes
        discoveryDone = false,
}

local protoCache     = {}  -- class -> fresh Instance.new(class) kept alive (defaults)
local creatableCache = {}  -- class -> bool
local writableCache  = {}  -- "class|prop" -> bool
local propNamesCache = {}  -- class -> sorted array of property names

-- UI catalog: everything UI-related the user can insert. The toolbox
-- shows THIS list by default ("List: UI"); "List: All" reveals every
-- creatable class found on the device instead.
local UI_SEED_CLASSES = string.split(
        "ScreenGui,SurfaceGui,BillboardGui,Frame,ScrollingFrame,CanvasGroup," ..
        "ViewportFrame,TextLabel,TextButton,TextBox,ImageLabel,ImageButton," ..
        "VideoFrame,UICorner,UIStroke,UIGradient,UIListLayout,UIGridLayout," ..
        "UITableLayout,UIPageLayout,UIPadding,UIScale,UIAspectRatioConstraint," ..
        "UITextSizeConstraint,UIFlexItem,LocalScript,ModuleScript,Script,Folder", ",")

-- Extra seeds for "List: All" so the full catalog is instantly useful.
local EXTRA_SEED_CLASSES = string.split(
        "Model,Part,Sound,SoundGroup,Animation,RemoteEvent,RemoteFunction," ..
        "BindableEvent,BindableFunction,ProximityPrompt,IntValue,StringValue," ..
        "BoolValue,NumberValue,ObjectValue,Color3Value,BrickColorValue," ..
        "Vector3Value,CFrameValue,RayValue,Camera,Humanoid", ",")

-- Is this class name UI-related? (used to filter the auto-discovered list)
local UI_NAME_EXTRA = {
        Frame         = true, CanvasGroup = true, ViewportFrame = true,
        TextLabel     = true, TextButton  = true, TextBox       = true,
        ImageLabel    = true, ImageButton = true, VideoFrame    = true,
        LocalScript   = true, ModuleScript = true, Script = true,
        Folder        = true,
}

local function isUIClassName(name)
        if type(name) ~= "string" then
                return false
        end
        if UI_NAME_EXTRA[name] then
                return true
        end
        if name:sub(1, 2) == "UI" then
                return true
        end
        return name:find("Gui", 1, true) ~= nil
end

-- Safety net ONLY (used when the executor has none of the reflection
-- APIs): common property names probed with pcall reads.
local FALLBACK_POOL = string.split(
        "Name,AnchorPoint,AutomaticSize,BackgroundColor3,BackgroundTransparency,BorderColor3," ..
        "BorderSizePixel,ClipsDescendants,LayoutOrder,Position,Rotation,Selectable,Size," ..
        "SizeConstraint,Visible,ZIndex,Font,LineHeight,MaxVisibleGraphemes,RichText,Text," ..
        "TextColor3,TextScaled,TextSize,TextStrokeColor3,TextStrokeTransparency,TextTransparency," ..
        "TextWrapped,TextXAlignment,TextYAlignment,AutoButtonColor,Modal,Image,ImageColor3," ..
        "ImageRectOffset,ImageRectSize,ImageTransparency,ResampleMode,ScaleType,SliceCenter," ..
        "SliceScale,TileSize,ClearTextOnFocus,PlaceholderColor3,PlaceholderText,MultiLine," ..
        "TextEditable,CanvasSize,ElasticBehavior,HorizontalScrollBarInset,MidImage,BottomImage," ..
        "TopImage,ScrollBarImageColor3,ScrollBarImageTransparency,ScrollBarThickness," ..
        "ScrollingDirection,VerticalScrollBarInset,VerticalScrollBarPosition,GroupTransparency," ..
        "GroupColor3,CornerRadius,ApplyStrokeMode,Color,LineJoinMode,Thickness,Transparency," ..
        "Offset,FillDirection,HorizontalAlignment,HorizontalFlex,Padding,SortOrder," ..
        "VerticalAlignment,VerticalFlex,Wrap,CellPadding,CellSize,FillDirectionMaxCells," ..
        "StartCorner,PaddingBottom,PaddingLeft,PaddingRight,PaddingTop,AutoLocalize," ..
        "DisplayOrder,Enabled,IgnoreGuiInset,ResetOnSpawn,ZIndexBehavior,ScreenInsets," ..
        "Disabled,Source,Looped,PlaybackSpeed,PlayOnRemove,SoundId,TimePosition,Volume," ..
        "Playing,Value,AlwaysOnTop,Brightness,LightInfluence,MaxDistance,StudsOffset," ..
        "Adornee,ActionText,ObjectText,HoldDuration,MaxActivationDistance,RequiresLineOfSight," ..
        "Style,FieldOfView,CameraType,Material,Anchored,CanCollide,Health,MaxHealth,WalkSpeed", ",")

function Reflection.isCreatable(class)
        local cached = creatableCache[class]
        if cached ~= nil then
                return cached
        end
        local ok, inst = pcall(Instance.new, class)
        local result = false
        if ok and typeof(inst) == "Instance" then
                pcall(function()
                        inst:Destroy()
                end)
                result = true
        end
        creatableCache[class] = result
        return result
end

-- A private fresh instance of the class used for default-value checks
-- and read-only detection. Prototypes are never parented.
function Reflection.prototype(class)
        local cached = protoCache[class]
        if cached ~= nil then
                if cached == false then
                        return nil
                end
                return cached
        end
        local ok, inst = pcall(Instance.new, class)
        if ok and typeof(inst) == "Instance" then
                protoCache[class] = inst
                return inst
        end
        protoCache[class] = false
        return nil
end

function Reflection.readable(inst, prop)
        local ok, value = pcall(function()
                return inst[prop]
        end)
        if ok then
                return true, value
        end
        return false, nil
end

-- Write-test on the class prototype (never touches the live instance).
function Reflection.writable(class, prop)
        local key = class .. "|" .. prop
        local cached = writableCache[key]
        if cached ~= nil then
                return cached
        end
        local result = false
        local proto = Reflection.prototype(class)
        if proto then
                result = (pcall(function()
                        proto[prop] = proto[prop]
                end) == true)
        end
        writableCache[key] = result
        return result
end

-- Every property name this executor can see on `inst`.
-- ALL sources are merged (first-wins was the v2 bug that left classes
-- like UIGradient with an empty property list): executor getproperties,
-- executor getpropertychangedsignals, the NATIVE Roblox
-- Instance:GetPropertyChangedSignals() map, then a pcall probe pool.
-- Each source is individually pcall-wrapped so nothing can blank the list.
function Reflection.propertyNames(inst)
        local className = "??"
        pcall(function()
                className = inst.ClassName
        end)
        local cached = propNamesCache[className]
        if cached then
                return cached
        end
        local names, seen = {}, {}

        local function add(n)
                if type(n) == "string" and #n > 0 and n ~= "Parent" and not seen[n] then
                        seen[n] = true
                        names[#names + 1] = n
                end
        end

        -- source 1: executor getproperties (dict OR array form)
        if Executor.getproperties then
                local ok, res = pcall(Executor.getproperties, inst)
                if ok and type(res) == "table" then
                        pcall(function()
                                for k in pairs(res) do
                                        if type(k) == "string" then
                                                add(k)
                                        end
                                end
                        end)
                        pcall(function()
                                for _, v in pairs(res) do
                                        if type(v) == "string" then
                                                add(v)
                                        end
                                end
                        end)
                end
        end

        -- source 2: executor getpropertychangedsignals
        if Executor.getpropertychangedsignals then
                local ok, res = pcall(Executor.getpropertychangedsignals, inst)
                if ok and type(res) == "table" then
                        pcall(function()
                                for k in pairs(res) do
                                        if type(k) == "string" then
                                                add(k)
                                        end
                                end
                        end)
                end
        end

        -- source 3: native Roblox API — always present, no executor needed
        pcall(function()
                for k in pairs(inst:GetPropertyChangedSignals()) do
                        if type(k) == "string" then
                                add(k)
                        end
                end
        end)

        -- source 4: pcall probe over a common-name pool (last resort)
        for _, n in ipairs(FALLBACK_POOL) do
                if not seen[n] then
                        local ok = pcall(function()
                                return inst[n]
                        end)
                        if ok then
                                add(n)
                        end
                end
        end

        add("Name")
        table.sort(names)
        propNamesCache[className] = names
        return names
end

-- --------------------------------------------------------------------
-- Background class discovery (toolbox / Add Instance lists)
-- --------------------------------------------------------------------

local function noteClass(set, name)
        if type(name) == "string" and #name > 0 and #name <= 64 and set[name] == nil then
                set[name] = true
        end
end

-- Adds a class to the catalog once Instance.new confirms it is creatable.
local function registerClass(name)
        if Reflection.classIndex[name] then
                return
        end
        if not Reflection.isCreatable(name) then
                return
        end
        Reflection.classIndex[name] = true
        Reflection.allClasses[#Reflection.allClasses + 1] = name
        if isUIClassName(name) then
                Reflection.uiClasses[#Reflection.uiClasses + 1] = name
        end
end

function Reflection.startDiscovery()
        -- validate the UI seeds synchronously so the toolbox is never empty
        for _, c in ipairs(UI_SEED_CLASSES) do
                registerClass(c)
        end
        table.sort(Reflection.uiClasses)
        table.sort(Reflection.allClasses)
        Reflection.classVersion = Reflection.classVersion + 1

        task.spawn(function()
                local found = {}
                for _, list in ipairs({ UI_SEED_CLASSES, EXTRA_SEED_CLASSES }) do
                        for _, c in ipairs(list) do
                                found[c] = true
                        end
                end

                -- extra "All" seeds validate in the background (non-UI stuff)
                for _, c in ipairs(EXTRA_SEED_CLASSES) do
                        registerClass(c)
                end

                -- 1) classes visible on nil-parented instances (executor API)
                if Executor.getnilinstances then
                        local ok, list = pcall(Executor.getnilinstances)
                        if ok and type(list) == "table" then
                                local count = 0
                                for _, inst in ipairs(list) do
                                        if typeof(inst) == "Instance" then
                                                noteClass(found, inst.ClassName)
                                                local okD, desc = pcall(inst.GetDescendants, inst)
                                                if okD and type(desc) == "table" then
                                                        for _, d in ipairs(desc) do
                                                                noteClass(found, d.ClassName)
                                                        end
                                                end
                                                count = count + 1
                                                if count % 20 == 0 then
                                                        task.wait()
                                                end
                                        end
                                end
                        end
                end

                -- 2) scan the DataModel, chunked so the game never freezes
                local services = {}
                local okS, kids = pcall(game.GetChildren, game)
                if okS and type(kids) == "table" then
                        for _, c in ipairs(kids) do
                                services[#services + 1] = c
                        end
                end
                local scanned = 0
                for _, svc in ipairs(services) do
                        local okD, desc = pcall(svc.GetDescendants, svc)
                        if okD and type(desc) == "table" then
                                for _, d in ipairs(desc) do
                                        noteClass(found, d.ClassName)
                                        scanned = scanned + 1
                                        if scanned % 500 == 0 then
                                                task.wait()
                                        end
                                        if scanned > 20000 then
                                                break
                                        end
                                end
                        end
                        task.wait()
                        if scanned > 20000 then
                                break
                        end
                end

                -- 3) validate every candidate with Instance.new, chunked
                local candidates = {}
                for name in pairs(found) do
                        candidates[#candidates + 1] = name
                end
                table.sort(candidates)
                local validated = 0
                for _, name in ipairs(candidates) do
                        registerClass(name)
                        validated = validated + 1
                        if validated % 30 == 0 then
                                table.sort(Reflection.uiClasses)
                                table.sort(Reflection.allClasses)
                                Reflection.classVersion = Reflection.classVersion + 1
                                task.wait()
                        end
                end
                table.sort(Reflection.uiClasses)
                table.sort(Reflection.allClasses)
                Reflection.classVersion = Reflection.classVersion + 1
                Reflection.discoveryDone = true
        end)
end

-- mode: "ui" (default) -> UI-related classes only; "all" -> everything
function Reflection.filteredClasses(query, max, mode)
        query = (query or ""):lower()
        local list = (mode == "all") and Reflection.allClasses or Reflection.uiClasses
        local out = {}
        for _, name in ipairs(list) do
                if query == "" or name:lower():find(query, 1, true) then
                        out[#out + 1] = name
                        if max and #out >= max then
                                break
                        end
                end
        end
        return out
end

-- --------------------------------------------------------------------
-- Value helpers: serialize / deserialize / format / parse / emit Luau
-- --------------------------------------------------------------------

local function numf(n)
        return string.format("%.14g", n)
end

-- Tagged values are plain tables (JSON-safe, Luau-safe):
--   { t = "Color3", v = { r, g, b } }  /  { t = "Enum", v = "Enum.Font.Gotham", n = 2 } ...
function Reflection.serializeValue(v)
        local t = typeof(v)
        if t == "string" then
                return { t = "string", v = v }
        elseif t == "number" then
                if v ~= v or v == math.huge or v == -math.huge then
                        return nil
                end
                return { t = "number", v = v }
        elseif t == "boolean" then
                return { t = "boolean", v = v }
        elseif t == "EnumItem" then
                return { t = "Enum", v = tostring(v), n = v.Value }
        elseif t == "Color3" then
                return { t = "Color3", v = { v.R, v.G, v.B } }
        elseif t == "UDim" then
                return { t = "UDim", v = { v.Scale, v.Offset } }
        elseif t == "UDim2" then
                return { t = "UDim2", v = { { v.X.Scale, v.X.Offset }, { v.Y.Scale, v.Y.Offset } } }
        elseif t == "Vector2" then
                return { t = "Vector2", v = { v.X, v.Y } }
        elseif t == "Vector3" then
                return { t = "Vector3", v = { v.X, v.Y, v.Z } }
        elseif t == "Rect" then
                return { t = "Rect", v = { v.Min.X, v.Min.Y, v.Max.X, v.Max.Y } }
        elseif t == "NumberRange" then
                return { t = "NumberRange", v = { v.Min, v.Max } }
        elseif t == "NumberSequence" then
                local kps = {}
                for _, kp in ipairs(v.Keypoints) do
                        kps[#kps + 1] = { kp.Time, kp.Value, kp.Envelope }
                end
                return { t = "NumberSequence", v = kps }
        elseif t == "ColorSequence" then
                local kps = {}
                for _, kp in ipairs(v.Keypoints) do
                        kps[#kps + 1] = { kp.Time, kp.Color.R, kp.Color.G, kp.Color.B }
                end
                return { t = "ColorSequence", v = kps }
        elseif t == "CFrame" then
                return { t = "CFrame", v = { v:GetComponents() } }
        elseif t == "BrickColor" then
                return { t = "BrickColor", v = v.Number }
        end
        return nil
end

function Reflection.deserializeValue(tag)
        if type(tag) ~= "table" or tag.t == nil then
                return nil
        end
        local t, v = tag.t, tag.v
        local ok, result
        if t == "string" then
                return tostring(v)
        elseif t == "number" then
                return tonumber(v)
        elseif t == "boolean" then
                return (v == true)
        elseif t == "Enum" then
                ok, result = pcall(function()
                        local text = tostring(v or ""):gsub("^Enum%.", "")
                        local typePart, itemPart = text:match("^([%w_]+)%.([%w_]+)$")
                        if typePart and itemPart then
                                return Enum[typePart][itemPart]
                        end
                        return nil
                end)
                if ok and result ~= nil then
                        return result
                end
                if tag.n ~= nil then
                        ok, result = pcall(function()
                                local text = tostring(v or ""):gsub("^Enum%.", "")
                                local typePart = text:match("^([%w_]+)%.") or text
                                local enumType = Enum[typePart]
                                if enumType then
                                        for _, item in ipairs(enumType:GetEnumItems()) do
                                                if item.Value == tag.n then
                                                        return item
                                                end
                                        end
                                end
                                return nil
                        end)
                        if ok and result ~= nil then
                                return result
                        end
                end
                return nil
        elseif t == "Color3" and type(v) == "table" then
                return Color3.new(tonumber(v[1]) or 0, tonumber(v[2]) or 0, tonumber(v[3]) or 0)
        elseif t == "UDim" and type(v) == "table" then
                return UDim.new(tonumber(v[1]) or 0, tonumber(v[2]) or 0)
        elseif t == "UDim2" and type(v) == "table" then
                local x, y = v[1], v[2]
                if type(x) ~= "table" or type(y) ~= "table" then
                        return nil
                end
                return UDim2.new(tonumber(x[1]) or 0, tonumber(x[2]) or 0, tonumber(y[1]) or 0, tonumber(y[2]) or 0)
        elseif t == "Vector2" and type(v) == "table" then
                return Vector2.new(tonumber(v[1]) or 0, tonumber(v[2]) or 0)
        elseif t == "Vector3" and type(v) == "table" then
                return Vector3.new(tonumber(v[1]) or 0, tonumber(v[2]) or 0, tonumber(v[3]) or 0)
        elseif t == "Rect" and type(v) == "table" then
                return Rect.new(tonumber(v[1]) or 0, tonumber(v[2]) or 0, tonumber(v[3]) or 0, tonumber(v[4]) or 0)
        elseif t == "NumberRange" and type(v) == "table" then
                return NumberRange.new(tonumber(v[1]) or 0, tonumber(v[2]) or 0)
        elseif t == "NumberSequence" and type(v) == "table" then
                ok, result = pcall(function()
                        local kps = {}
                        for _, kp in ipairs(v) do
                                kps[#kps + 1] = NumberSequenceKeypoint.new(tonumber(kp[1]) or 0, tonumber(kp[2]) or 0, tonumber(kp[3]) or 0)
                        end
                        return NumberSequence.new(kps)
                end)
                if ok then
                        return result
                end
                return nil
        elseif t == "ColorSequence" and type(v) == "table" then
                ok, result = pcall(function()
                        local kps = {}
                        for _, kp in ipairs(v) do
                                kps[#kps + 1] = ColorSequenceKeypoint.new(tonumber(kp[1]) or 0, Color3.new(tonumber(kp[2]) or 0, tonumber(kp[3]) or 0, tonumber(kp[4]) or 0))
                        end
                        return ColorSequence.new(kps)
                end)
                if ok then
                        return result
                end
                return nil
        elseif t == "CFrame" and type(v) == "table" then
                ok, result = pcall(function()
                        return CFrame.new(table.unpack(v))
                end)
                if ok then
                        return result
                end
                return nil
        elseif t == "BrickColor" then
                ok, result = pcall(function()
                        return BrickColor.new(tonumber(v) or 194)
                end)
                if ok then
                        return result
                end
                return nil
        end
        return nil
end

local function deepEqualTagged(a, b)
        if a == b then
                return true
        end
        if type(a) ~= "table" or type(b) ~= "table" then
                return a == b
        end
        if a.t ~= nil or b.t ~= nil then
                if a.t ~= b.t then
                        return false
                end
                return deepEqualTagged(a.v, b.v)
        end
        local na, nb = #a, #b
        if na > 0 and nb > 0 and na == nb then
                for i = 1, na do
                        if not deepEqualTagged(a[i], b[i]) then
                                return false
                        end
                end
                return true
        end
        for k, av in pairs(a) do
                if not deepEqualTagged(av, b[k]) then
                        return false
                end
        end
        for k in pairs(b) do
                if a[k] == nil then
                        return false
                end
        end
        return true
end

local LUAU_RESERVED = {
        ["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true, ["elseif"] = true,
        ["end"] = true, ["false"] = true, ["for"] = true, ["function"] = true, ["if"] = true,
        ["in"] = true, ["local"] = true, ["nil"] = true, ["not"] = true, ["or"] = true,
        ["repeat"] = true, ["return"] = true, ["then"] = true, ["true"] = true, ["until"] = true,
        ["while"] = true, ["continue"] = true,
}

local tableToLuau -- forward declaration (luauValue recurses through it)

local function luauValue(v, indent)
        if type(v) == "string" then
                return string.format("%q", v)
        elseif type(v) == "number" then
                return numf(v)
        elseif type(v) == "boolean" then
                return tostring(v)
        elseif type(v) == "table" then
                return tableToLuau(v, indent)
        end
        return "nil"
end

function tableToLuau(t, indent)
        indent = indent or ""
        local inner = indent .. "\t"
        local lines = { "{" }
        local count = 0
        for i = 1, 100000 do
                if t[i] == nil then
                        count = i - 1
                        break
                end
        end
        for i = 1, count do
                lines[#lines + 1] = inner .. "[" .. i .. "] = " .. luauValue(t[i], inner) .. ","
        end
        local keys = {}
        for k in pairs(t) do
                local isIndex = (type(k) == "number" and k % 1 == 0 and k >= 1 and k <= count)
                if not isIndex then
                        keys[#keys + 1] = k
                end
        end
        table.sort(keys, function(a, b)
                local ta, tb = type(a), type(b)
                if ta ~= tb then
                        return ta < tb
                end
                if ta == "number" then
                        return a < b
                end
                return tostring(a) < tostring(b)
        end)
        for _, k in ipairs(keys) do
                local keyStr
                if type(k) == "string" and k:match("^[%a_][%w_]*$") and not LUAU_RESERVED[k] then
                        keyStr = k
                elseif type(k) == "number" then
                        keyStr = "[" .. tostring(k) .. "]"
                else
                        keyStr = "[" .. string.format("%q", tostring(k)) .. "]"
                end
                lines[#lines + 1] = inner .. keyStr .. " = " .. luauValue(t[k], inner) .. ","
        end
        lines[#lines + 1] = indent .. "}"
        return table.concat(lines, "\n")
end

function Reflection.valueToLuau(v)
        local t = typeof(v)
        if t == "string" then
                return string.format("%q", v)
        elseif t == "number" then
                if v ~= v or v == math.huge or v == -math.huge then
                        return nil
                end
                return numf(v)
        elseif t == "boolean" then
                return tostring(v)
        elseif t == "EnumItem" then
                return tostring(v)
        elseif t == "Color3" then
                return ("Color3.new(%s, %s, %s)"):format(numf(v.R), numf(v.G), numf(v.B))
        elseif t == "UDim" then
                return ("UDim.new(%s, %d)"):format(numf(v.Scale), math.floor(v.Offset + 0.5))
        elseif t == "UDim2" then
                return ("UDim2.new(%s, %d, %s, %d)"):format(numf(v.X.Scale), math.floor(v.X.Offset + 0.5), numf(v.Y.Scale), math.floor(v.Y.Offset + 0.5))
        elseif t == "Vector2" then
                return ("Vector2.new(%s, %s)"):format(numf(v.X), numf(v.Y))
        elseif t == "Vector3" then
                return ("Vector3.new(%s, %s, %s)"):format(numf(v.X), numf(v.Y), numf(v.Z))
        elseif t == "Rect" then
                return ("Rect.new(%s, %s, %s, %s)"):format(numf(v.Min.X), numf(v.Min.Y), numf(v.Max.X), numf(v.Max.Y))
        elseif t == "NumberRange" then
                return ("NumberRange.new(%s, %s)"):format(numf(v.Min), numf(v.Max))
        elseif t == "NumberSequence" then
                local parts = {}
                for _, kp in ipairs(v.Keypoints) do
                        parts[#parts + 1] = ("NumberSequenceKeypoint.new(%s, %s, %s)"):format(numf(kp.Time), numf(kp.Value), numf(kp.Envelope))
                end
                return "NumberSequence.new{" .. table.concat(parts, ", ") .. "}"
        elseif t == "ColorSequence" then
                local parts = {}
                for _, kp in ipairs(v.Keypoints) do
                        parts[#parts + 1] = ("ColorSequenceKeypoint.new(%s, Color3.new(%s, %s, %s))"):format(numf(kp.Time), numf(kp.Color.R), numf(kp.Color.G), numf(kp.Color.B))
                end
                return "ColorSequence.new{" .. table.concat(parts, ", ") .. "}"
        elseif t == "CFrame" then
                local c = { v:GetComponents() }
                for i = 1, #c do
                        c[i] = numf(c[i])
                end
                return "CFrame.new(" .. table.concat(c, ", ") .. ")"
        elseif t == "BrickColor" then
                return ("BrickColor.new(%d)"):format(v.Number)
        end
        return nil
end

function Reflection.formatValue(v)
        local t = typeof(v)
        if t == "string" then
                return (v:gsub("\n", "\\n"))
        elseif t == "number" then
                return numf(v)
        elseif t == "boolean" then
                return tostring(v)
        elseif t == "EnumItem" then
                return tostring(v)
        elseif t == "Color3" then
                return ("%d, %d, %d"):format(math.floor(v.R * 255 + 0.5), math.floor(v.G * 255 + 0.5), math.floor(v.B * 255 + 0.5))
        elseif t == "UDim" then
                return ("%s, %d"):format(numf(v.Scale), v.Offset)
        elseif t == "UDim2" then
                return ("{%s, %d}, {%s, %d}"):format(numf(v.X.Scale), v.X.Offset, numf(v.Y.Scale), v.Y.Offset)
        elseif t == "Vector2" then
                return ("%s, %s"):format(numf(v.X), numf(v.Y))
        elseif t == "Vector3" then
                return ("%s, %s, %s"):format(numf(v.X), numf(v.Y), numf(v.Z))
        elseif t == "Rect" then
                return ("%s, %s, %s, %s"):format(numf(v.Min.X), numf(v.Min.Y), numf(v.Max.X), numf(v.Max.Y))
        elseif t == "NumberRange" then
                return ("%s, %s"):format(numf(v.Min), numf(v.Max))
        elseif t == "NumberSequence" then
                local parts = {}
                for _, kp in ipairs(v.Keypoints) do
                        parts[#parts + 1] = numf(kp.Time) .. ":" .. numf(kp.Value)
                end
                return table.concat(parts, "; ")
        elseif t == "ColorSequence" then
                local parts = {}
                for _, kp in ipairs(v.Keypoints) do
                        parts[#parts + 1] = numf(kp.Time) .. ":" .. math.floor(kp.Color.R * 255 + 0.5) .. "," .. math.floor(kp.Color.G * 255 + 0.5) .. "," .. math.floor(kp.Color.B * 255 + 0.5)
                end
                return table.concat(parts, "; ")
        elseif t == "CFrame" then
                local c = { v:GetComponents() }
                for i = 1, #c do
                        c[i] = numf(c[i])
                end
                return table.concat(c, ", ")
        elseif t == "BrickColor" then
                return v.Name
        elseif t == "Instance" then
                return "<" .. v.ClassName .. ">"
        elseif v == nil then
                return "nil"
        else
                return "(" .. t .. ")"
        end
end

-- --------------------------------------------------------------------
-- Text parsing driven by the CURRENT value's type (fully automatic)
-- --------------------------------------------------------------------

local function splitNums(text)
        text = text:gsub(",", " ")
        local out = {}
        for token in text:gmatch("[+-]?%d*%.?%d+") do
                out[#out + 1] = tonumber(token)
        end
        return out
end

local function parseColor3Text(text)
        text = text:gsub("^%s+", ""):gsub("%s+$", "")
        local hex = text:match("^#?(%x%x%x%x%x%x)$")
        if hex then
                local r = tonumber(hex:sub(1, 2), 16)
                local g = tonumber(hex:sub(3, 4), 16)
                local b = tonumber(hex:sub(5, 6), 16)
                if r and g and b then
                        return Color3.fromRGB(r, g, b)
                end
        end
        local n = splitNums(text)
        if #n >= 3 then
                return Color3.fromRGB(math.floor(n[1] + 0.5), math.floor(n[2] + 0.5), math.floor(n[3] + 0.5))
        end
        return nil
end

local function parseEnumText(text, enumType)
        text = text:gsub("^%s+", ""):gsub("%s+$", "")
        local stripped = text:gsub("^Enum%.", "")
        local typePart, itemPart = stripped:match("^([%w_]+)%.([%w_]+)$")
        if typePart and typePart ~= enumType.Name then
                return nil
        end
        local target = itemPart or stripped
        if target == "" then
                return nil
        end
        local ok, item = pcall(function()
                return enumType[target]
        end)
        if ok and item ~= nil and typeof(item) == "EnumItem" then
                return item
        end
        local okL, list = pcall(function()
                return enumType:GetEnumItems()
        end)
        if okL and type(list) == "table" then
                local lower = target:lower()
                local num = tonumber(target)
                for _, it in ipairs(list) do
                        if it.Name:lower() == lower then
                                return it
                        end
                end
                if num then
                        for _, it in ipairs(list) do
                                if it.Value == num then
                                        return it
                                end
                        end
                end
        end
        return nil
end

function Reflection.parseTyped(text, current)
        local t = typeof(current)
        text = tostring(text)
        if t == "string" then
                return (text:gsub("\\n", "\n"))
        end
        if t == "boolean" then
                local s = text:lower():gsub("%s+", "")
                if s == "true" or s == "1" or s == "yes" or s == "on" then
                        return true
                end
                if s == "false" or s == "0" or s == "no" or s == "off" then
                        return false
                end
                return nil
        end
        if t == "number" then
                return tonumber(text:gsub("^%s+", ""):gsub("%s+$", ""))
        end
        if t == "EnumItem" then
                return parseEnumText(text, current.EnumType)
        end
        if t == "Color3" then
                return parseColor3Text(text)
        end
        local n = splitNums(text)
        if t == "UDim" then
                if #n >= 2 then
                        return UDim.new(n[1], math.floor(n[2] + 0.5))
                end
                return nil
        end
        if t == "UDim2" then
                if #n >= 4 then
                        return UDim2.new(n[1], math.floor(n[2] + 0.5), n[3], math.floor(n[4] + 0.5))
                end
                return nil
        end
        if t == "Vector2" then
                if #n >= 2 then
                        return Vector2.new(n[1], n[2])
                end
                return nil
        end
        if t == "Vector3" then
                if #n >= 3 then
                        return Vector3.new(n[1], n[2], n[3])
                end
                return nil
        end
        if t == "Rect" then
                if #n >= 4 then
                        return Rect.new(n[1], n[2], n[3], n[4])
                end
                return nil
        end
        if t == "NumberRange" then
                if #n >= 2 then
                        return NumberRange.new(n[1], n[2])
                end
                return nil
        end
        if t == "NumberSequence" then
                local ok, seq = pcall(function()
                        local kps = {}
                        for pair in text:gmatch("[^;]+") do
                                local timeV, valueV = pair:match("([%-%d%.]+)%s*:%s*([%-%d%.]+)")
                                if timeV and valueV then
                                        kps[#kps + 1] = NumberSequenceKeypoint.new(tonumber(timeV), tonumber(valueV), 0)
                                end
                        end
                        if #kps >= 2 then
                                return NumberSequence.new(kps)
                        end
                        return nil
                end)
                if ok and seq then
                        return seq
                end
                return nil
        end
        if t == "ColorSequence" then
                local ok, seq = pcall(function()
                        local kps = {}
                        for pair in text:gmatch("[^;]+") do
                                local timeV, r, g, b = pair:match("([%-%d%.]+)%s*:%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
                                if timeV and r and g and b then
                                        kps[#kps + 1] = ColorSequenceKeypoint.new(tonumber(timeV), Color3.fromRGB(tonumber(r), tonumber(g), tonumber(b)))
                                end
                        end
                        if #kps >= 2 then
                                return ColorSequence.new(kps)
                        end
                        return nil
                end)
                if ok and seq then
                        return seq
                end
                return nil
        end
        if t == "BrickColor" then
                local num = tonumber(text)
                if num then
                        local ok, bc = pcall(BrickColor.new, num)
                        if ok then
                                return bc
                        end
                end
                local ok2, bc2 = pcall(BrickColor.new, text)
                if ok2 then
                        return bc2
                end
                return nil
        end
        if t == "CFrame" then
                if #n >= 12 then
                        local ok, cf = pcall(function()
                                return CFrame.new(table.unpack(n))
                        end)
                        if ok then
                                return cf
                        end
                elseif #n >= 3 then
                        return CFrame.new(n[1], n[2], n[3])
                end
                return nil
        end
        return nil
end

-- ====================================================================
-- PROJECT INSTANCE HELPERS
-- Your instances live under PlayerGui and are tagged with an attribute,
-- so the editor can always tell them apart from everything else.
-- ====================================================================

local function isProject(inst)
        if typeof(inst) ~= "Instance" then
                return false
        end
        local ok, v = pcall(function()
                return inst:GetAttribute(PROJECT_ATTRIBUTE)
        end)
        return ok and v == true
end

local function markProject(inst)
        if typeof(inst) == "Instance" then
                pcall(function()
                        inst:SetAttribute(PROJECT_ATTRIBUTE, true)
                end)
        end
end

local function getProjectRoots()
        local roots, seenRoots = {}, {}
        local parents = { PROJECT_PARENT }
        if protectedParent and protectedParent ~= PROJECT_PARENT then
                parents[#parents + 1] = protectedParent
        end
        for _, parent in ipairs(parents) do
                local ok, kids = pcall(parent.GetChildren, parent)
                if ok and type(kids) == "table" then
                        for _, inst in ipairs(kids) do
                                if isProject(inst) and not seenRoots[inst] then
                                        seenRoots[inst] = true
                                        roots[#roots + 1] = inst
                                end
                        end
                end
        end
        return roots
end

local function firstProjectRoot()
        return getProjectRoots()[1]
end

local function ensureProjectIntegrity()
        if not firstProjectRoot() then
                local ok, sg = pcall(Instance.new, "ScreenGui")
                if ok and typeof(sg) == "Instance" then
                        sg.Name = "MyGui"
                        markProject(sg)
                        sg.Parent = PROJECT_PARENT
                end
        end
end

local function uniqueRootName(base)
        base = tostring(base or "ScreenGui"):gsub("%d+$", "")
        if #base == 0 then
                base = "ScreenGui"
        end
        local taken = {}
        local parents = { PROJECT_PARENT }
        if protectedParent and protectedParent ~= PROJECT_PARENT then
                parents[#parents + 1] = protectedParent
        end
        for _, parent in ipairs(parents) do
                for _, r in ipairs(parent:GetChildren()) do
                        taken[r.Name] = true
                end
        end
        if not taken[base] then
                return base
        end
        local i = 2
        while taken[base .. i] do
                i = i + 1
        end
        return base .. i
end

local function siblingUniqueName(inst)
        local parent = inst.Parent
        if typeof(parent) ~= "Instance" then
                return
        end
        local base = inst.Name
        local count = 0
        for _, c in ipairs(parent:GetChildren()) do
                if c ~= inst and c.Name == base then
                        count = count + 1
                end
        end
        if count > 0 then
                inst.Name = base .. (count + 1)
        end
end

-- ====================================================================
-- STATE / THEME / UI PRIMITIVES
-- ====================================================================

local State = {
        selected       = nil,
        editMode       = true,
        dragging       = nil,
        resizing       = nil,
        windowDrag     = nil,
        propFilter     = "",
        saveFmt        = "json",
        catalogMode    = "ui",    -- toolbox list: "ui" | "all"
        coreGuiMode    = false,   -- project ScreenGuis live in gethui/CoreGui
        explorerFilter = "",
}

local Editor = {}          -- filled in later sections
local notify               -- assigned once the toast UI exists
local openExport           -- assigned in the export section
local openSavesModal       -- assigned in the save/load section
local openAddInstanceModal -- assigned in the modals section
local openFileAssetPrompt  -- assigned in the modals section
local openScriptEditor     -- assigned in the script editor section

local THEME = {
        bg       = Color3.fromRGB(24, 24, 28),
        bgDark   = Color3.fromRGB(17, 17, 21),
        bg2      = Color3.fromRGB(32, 32, 38),
        bg3      = Color3.fromRGB(42, 42, 50),
        panel    = Color3.fromRGB(28, 28, 34),
        stroke   = Color3.fromRGB(56, 56, 68),
        text     = Color3.fromRGB(235, 235, 240),
        textDim  = Color3.fromRGB(148, 148, 160),
        accent   = Color3.fromRGB(0, 132, 255),
        green    = Color3.fromRGB(52, 168, 106),
        red      = Color3.fromRGB(226, 74, 74),
        orange   = Color3.fromRGB(236, 158, 64),
        purple   = Color3.fromRGB(158, 118, 240),
        font     = Enum.Font.Gotham,
        fontMed  = Enum.Font.GothamMedium,
        fontBold = Enum.Font.GothamBold,
}

local UI = { windows = {} }

local function new(class, props, children)
        local inst = Instance.new(class)
        if props then
                for k, v in pairs(props) do
                        if k ~= "Parent" then
                                pcall(function()
                                        inst[k] = v
                                end)
                        end
                end
        end
        if children then
                for _, c in ipairs(children) do
                        c.Parent = inst
                end
        end
        if props and props.Parent ~= nil then
                inst.Parent = props.Parent
        end
        return inst
end

-- Deterministic per-class color (auto-derived, no hardcoded color map)
local function classColor(class)
        local h = 0
        for i = 1, #class do
                h = (h * 31 + string.byte(class, i)) % 360
        end
        return Color3.fromHSV(h / 360, 0.45, 0.85)
end

local function mkCorner(radius, parent)
        return new("UICorner", { CornerRadius = UDim.new(0, radius or 6), Parent = parent })
end

local function mkStroke(color, thickness, parent)
        return new("UIStroke", {
                Color = color or THEME.stroke,
                Thickness = thickness or 1,
                ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                Parent = parent,
        })
end

function UI.makeToolbarButton(text, onClick, options)
        options = options or {}
        local btn = new("TextButton", {
                Size = options.size or UDim2.new(0, 96, 1, 0),
                BackgroundColor3 = options.color or THEME.bg3,
                BorderSizePixel = 0,
                Text = text,
                TextColor3 = options.textColor or THEME.text,
                Font = THEME.fontMed,
                TextSize = 12,
                AutoButtonColor = true,
                Parent = options.parent,
        })
        mkCorner(5, btn)
        if options.stroke then
                mkStroke(options.stroke, 1, btn)
        end
        if onClick then
                btn.MouseButton1Click:Connect(onClick)
        end
        return btn
end

function UI.makeColumnHeader(text, parent, height)
        local header = new("TextLabel", {
                Size = UDim2.new(1, 0, 0, height or 22),
                BackgroundColor3 = THEME.bg2,
                BorderSizePixel = 0,
                Text = text,
                TextColor3 = THEME.textDim,
                Font = THEME.fontMed,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = parent,
        })
        new("UIPadding", { PaddingLeft = UDim.new(0, 8), Parent = header })
        return header
end

function UI.makeScrollList(parent)
        local scroll = new("ScrollingFrame", {
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                ScrollBarThickness = 4,
                ScrollBarImageColor3 = THEME.stroke,
                CanvasSize = UDim2.new(),
                AutomaticCanvasSize = Enum.AutomaticSize.Y,
                ScrollingDirection = Enum.ScrollingDirection.Y,
                Parent = parent,
        })
        new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })
        new("UIPadding", {
                PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 3),
                PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
                Parent = scroll,
        })
        return scroll
end

-- ====================================================================
-- MAIN WINDOW
-- ====================================================================

local minimized = false
local toggleMinimize -- forward declaration
local setAllExpanded -- assigned in the explorer section
local refreshToolbox -- assigned in the toolbox section

local function buildMainUI()
        local main = new("ScreenGui", {
                Name = "StudioGUICreator",
                ResetOnSpawn = false,
                IgnoreGuiInset = false,
                DisplayOrder = 500,
                Parent = protectedParent,
        })
        UI.main = main

        local root = new("Frame", {
                Name = "Root",
                Size = UDim2.fromOffset(760, 520),
                Position = UDim2.fromOffset(40, 60),
                BackgroundColor3 = THEME.bg,
                BorderSizePixel = 0,
                Active = true,
                Parent = main,
        })
        UI.root = root
        mkCorner(8, root)
        mkStroke(THEME.stroke, 1, root)
        pcall(function()
                local cam = workspace.CurrentCamera
                local vs = cam and cam.ViewportSize or Vector2.new(1280, 720)
                local scale = math.min(1, vs.X / 820, vs.Y / 620)
                if scale < 1 then
                        new("UIScale", { Scale = scale, Parent = root })
                end
        end)

        -- title bar ----------------------------------------------------------
        local title = new("Frame", {
                Name = "Title",
                Size = UDim2.new(1, 0, 0, 30),
                BackgroundColor3 = THEME.bg2,
                BorderSizePixel = 0,
                Parent = root,
        })
        new("TextLabel", {
                BackgroundTransparency = 1,
                Size = UDim2.new(1, -140, 1, 0),
                Position = UDim2.fromOffset(12, 0),
                Text = "StudioGUI Creator v3.0  —  " .. Executor.name,
                TextColor3 = THEME.text,
                Font = THEME.fontBold,
                TextSize = 13,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Parent = title,
        })
        local closeBtn = UI.makeToolbarButton("X", function()
                Editor.destroy()
        end, { parent = title, size = UDim2.fromOffset(26, 22), color = THEME.red })
        closeBtn.Position = UDim2.new(1, -30, 0, 4)
        local minBtn = UI.makeToolbarButton("_", function()
                toggleMinimize()
        end, { parent = title, size = UDim2.fromOffset(26, 22) })
        minBtn.Position = UDim2.new(1, -60, 0, 4)
        -- Delta-based window dragging (works for mouse AND touch, and is
        -- immune to any coordinate-space offset between the title bar's
        -- InputBegan and UserInputService.InputChanged).
        title.Active = true
        title.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                        State.windowDrag = {
                                lastMouse = Vector2.new(input.Position.X, input.Position.Y),
                        }
                end
        end)
        title.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                        State.windowDrag = nil
                end
        end)

        -- body ---------------------------------------------------------------
        local body = new("Frame", {
                Name = "Body",
                Position = UDim2.new(0, 0, 0, 30),
                Size = UDim2.new(1, 0, 1, -30),
                BackgroundTransparency = 1,
                Parent = root,
        })
        UI.body = body

        -- two toolbar rows
        local toolbar = new("Frame", {
                Name = "Toolbar",
                Size = UDim2.new(1, 0, 0, 56),
                BackgroundTransparency = 1,
                Parent = body,
        })
        local row1 = new("Frame", {
                Name = "Row1",
                Size = UDim2.new(1, -8, 0, 24),
                Position = UDim2.fromOffset(4, 2),
                BackgroundTransparency = 1,
                Parent = toolbar,
        })
        new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), Parent = row1 })
        local row2 = new("Frame", {
                Name = "Row2",
                Size = UDim2.new(1, -8, 0, 24),
                Position = UDim2.fromOffset(4, 28),
                BackgroundTransparency = 1,
                Parent = toolbar,
        })
        new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), Parent = row2 })
        UI.row1 = row1
        UI.row2 = row2

        -- content: toolbox | viewport | explorer+properties
        local content = new("Frame", {
                Name = "Content",
                Position = UDim2.fromOffset(0, 58),
                Size = UDim2.new(1, 0, 1, -80),
                BackgroundTransparency = 1,
                Parent = body,
        })
        UI.content = content

        local toolbox = new("Frame", {
                Name = "Toolbox",
                Size = UDim2.new(0, 170, 1, 0),
                BackgroundColor3 = THEME.panel,
                BorderSizePixel = 0,
                Parent = content,
        })
        mkStroke(THEME.stroke, 1, toolbox)

        local viewport = new("Frame", {
                Name = "Viewport",
                Size = UDim2.new(1, -432, 1, 0),
                Position = UDim2.new(0, 170, 0, 0),
                BackgroundColor3 = THEME.bgDark,
                BorderSizePixel = 0,
                Parent = content,
        })
        UI.viewport = viewport
        UI.hintLabel = new("TextLabel", {
                Name = "Hint",
                BackgroundTransparency = 1,
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(0.5, 0, 0.5, 0),
                Size = UDim2.fromOffset(430, 36),
                Text = "Click a GUI element to select\ndrag to move · handles to resize",
                TextColor3 = THEME.textDim,
                TextTransparency = 0.3,
                Font = THEME.font,
                TextSize = 12,
                Parent = viewport,
        })

        local rightCol = new("Frame", {
                Name = "Right",
                Size = UDim2.new(0, 262, 1, 0),
                Position = UDim2.new(1, -262, 0, 0),
                BackgroundColor3 = THEME.panel,
                BorderSizePixel = 0,
                Parent = content,
        })
        mkStroke(THEME.stroke, 1, rightCol)

        -- toolbox internals
        UI.toolboxHeader = UI.makeColumnHeader("Toolbox", toolbox)
        UI.catalogBtn = UI.makeToolbarButton("List: UI", function()
                State.catalogMode = (State.catalogMode == "ui") and "all" or "ui"
                UI.catalogBtn.Text = (State.catalogMode == "ui") and "List: UI" or "List: All"
                UI.catalogBtn.BackgroundColor3 = (State.catalogMode == "ui") and THEME.accent or THEME.orange
                pcall(refreshToolbox)
        end, { parent = toolbox, size = UDim2.fromOffset(64, 18), color = THEME.accent })
        UI.catalogBtn.Position = UDim2.new(1, -68, 0, 2)
        UI.toolboxSearch = new("TextBox", {
                Size = UDim2.new(1, -12, 0, 22),
                Position = UDim2.fromOffset(6, 26),
                BackgroundColor3 = THEME.bg2,
                TextColor3 = THEME.text,
                PlaceholderText = "Search classes...",
                Text = "",
                ClearTextOnFocus = false,
                Font = THEME.font,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = toolbox,
        })
        mkCorner(4, UI.toolboxSearch)
        mkStroke(THEME.stroke, 1, UI.toolboxSearch)
        UI.toolboxCount = new("TextLabel", {
                BackgroundTransparency = 1,
                Size = UDim2.new(1, -12, 0, 14),
                Position = UDim2.fromOffset(8, 50),
                Text = "scanning...",
                TextColor3 = THEME.textDim,
                Font = THEME.font,
                TextSize = 10,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = toolbox,
        })
        UI.toolboxList = UI.makeScrollList(toolbox)
        UI.toolboxList.Position = UDim2.new(0, 0, 0, 66)
        UI.toolboxList.Size = UDim2.new(1, 0, 1, -66)

        -- explorer internals (search + expand/collapse + list)
        UI.explorerHeader = UI.makeColumnHeader("Explorer", rightCol)
        UI.explorerSearch = new("TextBox", {
                Size = UDim2.new(1, -62, 0, 18),
                Position = UDim2.fromOffset(4, 24),
                BackgroundColor3 = THEME.bg2,
                TextColor3 = THEME.text,
                PlaceholderText = "Search explorer...",
                Text = "",
                ClearTextOnFocus = false,
                Font = THEME.font,
                TextSize = 10,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = rightCol,
        })
        mkCorner(4, UI.explorerSearch)
        mkStroke(THEME.stroke, 1, UI.explorerSearch)
        UI.expExpandBtn = UI.makeToolbarButton("+", function()
                pcall(setAllExpanded, true)
        end, { parent = rightCol, size = UDim2.fromOffset(24, 18) })
        UI.expExpandBtn.Position = UDim2.new(1, -56, 0, 24)
        UI.expCollapseBtn = UI.makeToolbarButton("\226\128\147", function()
                pcall(setAllExpanded, false)
        end, { parent = rightCol, size = UDim2.fromOffset(24, 18) })
        UI.expCollapseBtn.Position = UDim2.new(1, -28, 0, 24)
        UI.explorerList = UI.makeScrollList(rightCol)
        UI.explorerList.Position = UDim2.new(0, 0, 0, 44)
        UI.explorerList.Size = UDim2.new(1, 0, 0, 144)

        local propsFrame = new("Frame", {
                Name = "Props",
                Position = UDim2.new(0, 0, 0, 190),
                Size = UDim2.new(1, 0, 1, -190),
                BackgroundTransparency = 1,
                Parent = rightCol,
        })
        UI.propsHeader = UI.makeColumnHeader("Properties", propsFrame)
        UI.propsStatus = new("TextLabel", {
                BackgroundTransparency = 1,
                Size = UDim2.new(0, 118, 1, 0),
                Position = UDim2.new(1, -126, 0, 0),
                Text = "",
                TextColor3 = THEME.textDim,
                Font = THEME.font,
                TextSize = 10,
                TextXAlignment = Enum.TextXAlignment.Right,
                Parent = UI.propsHeader,
        })
        UI.propsSearch = new("TextBox", {
                Size = UDim2.new(1, -8, 0, 20),
                Position = UDim2.fromOffset(4, 24),
                BackgroundColor3 = THEME.bg2,
                TextColor3 = THEME.text,
                PlaceholderText = "Filter properties...",
                Text = "",
                ClearTextOnFocus = false,
                Font = THEME.font,
                TextSize = 10,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = propsFrame,
        })
        mkCorner(4, UI.propsSearch)
        mkStroke(THEME.stroke, 1, UI.propsSearch)
        UI.propsList = UI.makeScrollList(propsFrame)
        UI.propsList.Position = UDim2.new(0, 0, 0, 46)
        UI.propsList.Size = UDim2.new(1, 0, 1, -46)

        -- footer
        local footer = new("Frame", {
                Name = "Footer",
                Position = UDim2.new(0, 0, 1, -22),
                Size = UDim2.new(1, 0, 0, 22),
                BackgroundColor3 = THEME.bg2,
                BorderSizePixel = 0,
                Parent = body,
        })
        UI.statusLabel = new("TextLabel", {
                BackgroundTransparency = 1,
                Size = UDim2.new(1, -20, 1, 0),
                Position = UDim2.fromOffset(10, 0),
                Text = "No selection",
                TextColor3 = THEME.textDim,
                Font = THEME.font,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Parent = footer,
        })

        -- toast holder (separate ScreenGui so toasts show even when minimized)
        local toastGui = new("ScreenGui", {
                Name = "SGC_Toasts",
                ResetOnSpawn = false,
                DisplayOrder = 900,
                IgnoreGuiInset = false,
                Parent = protectedParent,
        })
        UI.toastGui = toastGui
        local toastHolder = new("Frame", {
                BackgroundTransparency = 1,
                Size = UDim2.new(0, 306, 1, 0),
                Position = UDim2.new(1, -306, 0, 8),
                Parent = toastGui,
        })
        new("UIListLayout", {
                VerticalAlignment = Enum.VerticalAlignment.Top,
                HorizontalAlignment = Enum.HorizontalAlignment.Right,
                Padding = UDim.new(0, 6),
                SortOrder = Enum.SortOrder.LayoutOrder,
                Parent = toastHolder,
        })
        UI.toastHolder = toastHolder
end

toggleMinimize = function()
        minimized = not minimized
        if UI.body then
                UI.body.Visible = not minimized
        end
        if UI.root then
                UI.root.Size = minimized and UDim2.fromOffset(760, 30) or UDim2.fromOffset(760, 520)
        end
end

notify = function(text, kind, duration)
        if not UI.toastHolder then
                return
        end
        kind = kind or "info"
        duration = duration or 3.5
        local color = THEME.accent
        if kind == "success" then
                color = THEME.green
        elseif kind == "warn" then
                color = THEME.orange
        elseif kind == "error" then
                color = THEME.red
        end
        local order = #UI.toastHolder:GetChildren() + 1
        local toast = new("Frame", {
                BackgroundColor3 = THEME.bg2,
                BorderSizePixel = 0,
                Size = UDim2.new(0, 300, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                LayoutOrder = order,
                Parent = UI.toastHolder,
        })
        mkCorner(6, toast)
        mkStroke(color, 1, toast)
        new("Frame", {
                Size = UDim2.new(0, 4, 1, 0),
                BackgroundColor3 = color,
                BorderSizePixel = 0,
                Parent = toast,
        })
        new("TextLabel", {
                BackgroundTransparency = 1,
                Size = UDim2.new(1, -24, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                Position = UDim2.fromOffset(14, 6),
                Text = tostring(text),
                TextColor3 = THEME.text,
                Font = THEME.font,
                TextSize = 12,
                TextWrapped = true,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = toast,
        })
        new("UIPadding", {
                PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
                PaddingRight = UDim.new(0, 10), Parent = toast,
        })
        task.delay(duration, function()
                if toast.Parent then
                        pcall(function()
                                TweenService:Create(toast, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
                        end)
                        task.wait(0.35)
                        pcall(function()
                                toast:Destroy()
                        end)
                end
        end)
end

-- ====================================================================
-- TOOLBOX — auto-discovered, searchable, creatable class list
-- ====================================================================

local toolboxShownVersion = -1
local toolboxSearchDirtyAt = 0

refreshToolbox = function()
        if not UI.toolboxList then
                return
        end
        toolboxShownVersion = Reflection.classVersion
        for _, c in ipairs(UI.toolboxList:GetChildren()) do
                if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then
                        c:Destroy()
                end
        end
        local query = ""
        pcall(function()
                query = UI.toolboxSearch.Text or ""
        end)
        local classes = Reflection.filteredClasses(query, 250, State.catalogMode)
        for i, className in ipairs(classes) do
                local row = new("TextButton", {
                        Size = UDim2.new(1, 0, 0, 22),
                        BackgroundColor3 = THEME.bg2,
                        BorderSizePixel = 0,
                        Text = "",
                        AutoButtonColor = true,
                        LayoutOrder = i,
                        Parent = UI.toolboxList,
                })
                mkCorner(4, row)
                local icon = new("Frame", {
                        Size = UDim2.fromOffset(14, 14),
                        Position = UDim2.fromOffset(4, 4),
                        BackgroundColor3 = classColor(className),
                        BorderSizePixel = 0,
                        Parent = row,
                })
                mkCorner(3, icon)
                new("TextLabel", {
                        BackgroundTransparency = 1,
                        Size = UDim2.new(1, -26, 1, 0),
                        Position = UDim2.fromOffset(22, 0),
                        Text = className,
                        TextColor3 = THEME.text,
                        Font = THEME.font,
                        TextSize = 11,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        TextTruncate = Enum.TextTruncate.AtEnd,
                        Parent = row,
                })
                row.MouseButton1Click:Connect(function()
                        Editor.spawnClass(className)
                end)
        end
        if UI.toolboxCount then
                local modeText = (State.catalogMode == "ui") and "UI" or "all creatable"
                UI.toolboxCount.Text = (#classes .. " " .. modeText .. " classes" .. (Reflection.discoveryDone and "" or " (scanning...)"))
        end
end

-- ====================================================================
-- EXPLORER — fully dynamic tree of the project
-- ====================================================================

local explorerDirty = true
local explorerRows = {}
local explorerWatchers = setmetatable({}, { __mode = "k" })
local explorerSearchDirtyAt = 0

-- Collapse/expand state per instance (nil = expanded by default).
local expandedMap = setmetatable({}, { __mode = "k" })

local function isExpanded(inst)
        return expandedMap[inst] ~= false
end

setAllExpanded = function(value)
        for _, root in ipairs(getProjectRoots()) do
                expandedMap[root] = value
                pcall(function()
                        for _, d in ipairs(root:GetDescendants()) do
                                expandedMap[d] = value
                        end
                end)
        end
        invalidateExplorer()
end

local function explorerDepthOf(inst)
        local d = 0
        local node = inst.Parent
        while node and typeof(node) == "Instance" do
                d = d + 1
                node = node.Parent
        end
        return d
end

local function invalidateExplorer()
        explorerDirty = true
end

local function watchInstance(inst)
        if explorerWatchers[inst] then
                return
        end
        if typeof(inst) ~= "Instance" then
                return
        end
        local conns = {}
        pcall(function()
                conns[#conns + 1] = inst.ChildAdded:Connect(function()
                        invalidateExplorer()
                end)
        end)
        pcall(function()
                conns[#conns + 1] = inst.ChildRemoved:Connect(function()
                        invalidateExplorer()
                end)
        end)
        pcall(function()
                conns[#conns + 1] = inst.AncestryChanged:Connect(function()
                        invalidateExplorer()
                end)
        end)
        pcall(function()
                conns[#conns + 1] = inst:GetPropertyChangedSignal("Name"):Connect(function()
                        invalidateExplorer()
                end)
        end)
        explorerWatchers[inst] = conns
end

local function pruneWatchers()
        for inst, conns in pairs(explorerWatchers) do
                if typeof(inst) ~= "Instance" or inst.Parent == nil then
                        for _, c in ipairs(conns) do
                                pcall(function()
                                        c:Disconnect()
                                end)
                        end
                        explorerWatchers[inst] = nil
                end
        end
end

local function refreshExplorerSelection()
        for inst, row in pairs(explorerRows) do
                if typeof(row) == "Instance" and row.Parent then
                        row.BackgroundColor3 = (inst == State.selected) and THEME.accent or THEME.bg2
                end
        end
end

local function rebuildExplorer()
        if not UI.explorerList then
                return
        end
        for _, c in ipairs(UI.explorerList:GetChildren()) do
                if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then
                        c:Destroy()
                end
        end
        explorerRows = {}
        local order = 0
        local filter = (State.explorerFilter or ""):lower()

        local function addRow(inst, depth, highlight)
                order = order + 1
                local childList = inst:GetChildren()
                local row = new("TextButton", {
                        Size = UDim2.new(1, 0, 0, 22),
                        BackgroundColor3 = (inst == State.selected) and THEME.accent or THEME.bg2,
                        BorderSizePixel = 0,
                        Text = "",
                        AutoButtonColor = true,
                        LayoutOrder = order,
                        Parent = UI.explorerList,
                })
                mkCorner(4, row)
                -- collapse/expand toggle (only in plain tree mode)
                if #childList > 0 and filter == "" then
                        local arrow = new("TextButton", {
                                Size = UDim2.fromOffset(14, 14),
                                Position = UDim2.new(0, depth * 12 + 2, 0.5, 0),
                                AnchorPoint = Vector2.new(0, 0.5),
                                BackgroundTransparency = 1,
                                BorderSizePixel = 0,
                                Text = isExpanded(inst) and "-" or "+",
                                TextColor3 = THEME.textDim,
                                Font = THEME.fontMed,
                                TextSize = 12,
                                Parent = row,
                        })
                        arrow.MouseButton1Click:Connect(function()
                                expandedMap[inst] = not isExpanded(inst)
                                invalidateExplorer()
                        end)
                end
                local icon = new("Frame", {
                        Size = UDim2.fromOffset(14, 14),
                        Position = UDim2.new(0, depth * 12 + 18, 0.5, 0),
                        AnchorPoint = Vector2.new(0, 0.5),
                        BackgroundColor3 = classColor(inst.ClassName),
                        BorderSizePixel = 0,
                        Parent = row,
                })
                mkCorner(3, icon)
                new("TextLabel", {
                        BackgroundTransparency = 1,
                        Size = UDim2.new(1, -(depth * 12 + 96), 1, 0),
                        Position = UDim2.new(0, depth * 12 + 36, 0, 0),
                        Text = inst.Name,
                        TextColor3 = highlight and THEME.accent or THEME.text,
                        Font = THEME.font,
                        TextSize = 11,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        TextTruncate = Enum.TextTruncate.AtEnd,
                        Parent = row,
                })
                new("TextLabel", {
                        BackgroundTransparency = 1,
                        Size = UDim2.new(0, 58, 1, 0),
                        Position = UDim2.new(1, -62, 0, 0),
                        Text = inst.ClassName,
                        TextColor3 = THEME.textDim,
                        Font = THEME.font,
                        TextSize = 10,
                        TextXAlignment = Enum.TextXAlignment.Right,
                        TextTruncate = Enum.TextTruncate.AtEnd,
                        Parent = row,
                })
                row.MouseButton1Click:Connect(function()
                        Editor.select(inst)
                end)
                explorerRows[inst] = row
                watchInstance(inst)
        end

        if filter ~= "" then
                -- search mode: flat list of every matching Name/ClassName
                local function matches(inst)
                        local okN, n = pcall(function()
                                return inst.Name:lower():find(filter, 1, true) ~= nil
                        end)
                        local okC, c = pcall(function()
                                return inst.ClassName:lower():find(filter, 1, true) ~= nil
                        end)
                        return (okN and n == true) or (okC and c == true)
                end
                for _, root in ipairs(getProjectRoots()) do
                        local rootDepth = explorerDepthOf(root)
                        if matches(root) then
                                addRow(root, 0, true)
                        end
                        for _, d in ipairs(root:GetDescendants()) do
                                if matches(d) then
                                        addRow(d, explorerDepthOf(d) - rootDepth, true)
                                end
                        end
                end
        else
                local function walk(inst, depth)
                        addRow(inst, depth, false)
                        if isExpanded(inst) then
                                for _, c in ipairs(inst:GetChildren()) do
                                        walk(c, depth + 1)
                                end
                        end
                end
                for _, root in ipairs(getProjectRoots()) do
                        walk(root, 0)
                end
        end
        pruneWatchers()
        if UI.explorerHeader then
                if filter ~= "" then
                        local total = 0
                        for _, root in ipairs(getProjectRoots()) do
                                total = total + 1 + #root:GetDescendants()
                        end
                        UI.explorerHeader.Text = ("Explorer  %d / %d match"):format(order, total)
                else
                        UI.explorerHeader.Text = ("Explorer  (%d)"):format(order)
                end
        end
end

-- ====================================================================
-- PROPERTIES — every readable property, listed automatically
-- ====================================================================

local propRows = {}
local propsSearchDirtyAt = 0
local CONTENT_PROPS = {
        Image = true, Texture = true, MidImage = true, TopImage = true, BottomImage = true,
}

local function rebuildProperties()
        if not UI.propsList then
                return
        end
        for _, c in ipairs(UI.propsList:GetChildren()) do
                if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then
                        c:Destroy()
                end
        end
        propRows = {}
        local inst = State.selected
        if typeof(inst) ~= "Instance" or inst.Parent == nil then
                if UI.propsHeader then
                        UI.propsHeader.Text = "Properties"
                end
                if UI.propsStatus then
                        UI.propsStatus.Text = ""
                end
                new("TextLabel", {
                        BackgroundTransparency = 1,
                        Size = UDim2.new(1, -14, 0, 48),
                        Position = UDim2.fromOffset(8, 6),
                        Text = "Select an instance in the viewport or Explorer.\nEverything you can read is auto-listed here.",
                        TextColor3 = THEME.textDim,
                        Font = THEME.font,
                        TextSize = 11,
                        TextWrapped = true,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        Parent = UI.propsList,
                })
                return
        end

        local className = inst.ClassName
        if UI.propsHeader then
                UI.propsHeader.Text = "Properties — " .. className
        end
        local names = Reflection.propertyNames(inst)
        local filter = State.propFilter:lower()
        local order = 0
        local writableCount = 0
        local rowErrors = 0

        -- Scripts get a dedicated code editor button above the property list
        if inst:IsA("LocalScript") or inst:IsA("Script") or inst:IsA("ModuleScript") then
                local editBtn = UI.makeToolbarButton("Edit Source (code)", function()
                        openScriptEditor(inst)
                end, { parent = UI.propsList, size = UDim2.new(1, 0, 0, 26), color = THEME.purple })
                editBtn.LayoutOrder = 0
        end

        for _, prop in ipairs(names) do
                if filter == "" or prop:lower():find(filter, 1, true) then
                        -- one broken property must never blank the whole panel
                        local okRow = pcall(function()
                                local okRead, value = Reflection.readable(inst, prop)
                                if not okRead then
                                        return -- unreadable property: no row
                                end
                                order = order + 1
                                local writable = Reflection.writable(className, prop)
                                if writable then
                                        writableCount = writableCount + 1
                                end
                                local row = new("Frame", {
                                        Size = UDim2.new(1, 0, 0, 24),
                                        BackgroundColor3 = THEME.bg2,
                                        BorderSizePixel = 0,
                                        LayoutOrder = order,
                                        Parent = UI.propsList,
                                })
                                mkCorner(4, row)
                                new("TextLabel", {
                                        BackgroundTransparency = 1,
                                        Size = UDim2.new(0, 116, 1, 0),
                                        Position = UDim2.fromOffset(6, 0),
                                        Text = prop .. (writable and "" or "  (R)"),
                                        TextColor3 = writable and THEME.text or THEME.textDim,
                                        Font = THEME.font,
                                        TextSize = 10,
                                        TextXAlignment = Enum.TextXAlignment.Left,
                                        TextTruncate = Enum.TextTruncate.AtEnd,
                                        Parent = row,
                                })

                                local displayText = Reflection.formatValue(value)
                                local editable = writable and #displayText <= 400
                                if #displayText > 400 then
                                        displayText = displayText:sub(1, 400) .. " ..."
                                end
                                local box = new("TextBox", {
                                        Size = UDim2.new(1, -132, 1, -6),
                                        Position = UDim2.new(0, 128, 0, 3),
                                        BackgroundColor3 = editable and THEME.bg or THEME.panel,
                                        TextColor3 = writable and THEME.text or THEME.textDim,
                                        Text = displayText,
                                        Font = THEME.font,
                                        TextSize = 10,
                                        ClearTextOnFocus = false,
                                        TextEditable = editable,
                                        TextXAlignment = Enum.TextXAlignment.Left,
                                        TextTruncate = Enum.TextTruncate.AtEnd,
                                        Parent = row,
                                })
                                mkCorner(4, box)

                                box.FocusLost:Connect(function()
                                        if not editable then
                                                return
                                        end
                                        if typeof(inst) ~= "Instance" or inst.Parent == nil then
                                                return
                                        end
                                        if box.Text == displayText then
                                                return
                                        end
                                        local current = nil
                                        pcall(function()
                                                current = inst[prop]
                                        end)
                                        local parsed = Reflection.parseTyped(box.Text, current)
                                        if parsed == nil then
                                                notify(("Invalid %s value for %s.%s"):format(typeof(current), className, prop), "warn", 2.5)
                                                box.Text = displayText
                                                return
                                        end
                                        local okA, err = pcall(function()
                                                inst[prop] = parsed
                                        end)
                                        if okA then
                                                if prop == "Name" then
                                                        invalidateExplorer()
                                                end
                                                task.defer(function()
                                                        local okR, nv = Reflection.readable(inst, prop)
                                                        if okR then
                                                                displayText = Reflection.formatValue(nv)
                                                                box.Text = displayText
                                                        end
                                                end)
                                        else
                                                notify(("Write failed: %s.%s — %s"):format(className, prop, tostring(err)), "error", 3)
                                                box.Text = displayText
                                        end
                                end)

                                -- getcustomasset: load a local image file into Content properties
                                if Executor.getcustomasset and writable and typeof(value) == "string" and CONTENT_PROPS[prop] then
                                        local fileBtn = new("TextButton", {
                                                Size = UDim2.fromOffset(18, 18),
                                                Position = UDim2.new(1, -22, 0, 3),
                                                Text = "F",
                                                Font = THEME.fontMed,
                                                TextSize = 10,
                                                TextColor3 = THEME.text,
                                                BackgroundColor3 = THEME.accent,
                                                BorderSizePixel = 0,
                                                Parent = row,
                                        })
                                        mkCorner(4, fileBtn)
                                        fileBtn.MouseButton1Click:Connect(function()
                                                openFileAssetPrompt(function(path)
                                                        local okA, content = pcall(Executor.getcustomasset, path)
                                                        if okA and type(content) == "string" then
                                                                pcall(function()
                                                                        inst[prop] = content
                                                                end)
                                                                box.Text = content
                                                                notify("Loaded asset from file.", "success")
                                                        else
                                                                notify("getcustomasset failed: " .. tostring(content), "error")
                                                        end
                                                end)
                                        end)
                                end

                                propRows[#propRows + 1] = { inst = inst, prop = prop, box = box }
                        end)
                        if not okRow then
                                rowErrors = rowErrors + 1
                        end
                end
        end

        if UI.propsStatus then
                local statusText = ("%d props · %d writable"):format(order, writableCount)
                if rowErrors > 0 then
                        statusText = statusText .. (" · %d skipped"):format(rowErrors)
                end
                UI.propsStatus.Text = statusText
        end
end

-- ====================================================================
-- MODAL FACTORY
-- ====================================================================

function UI.makeModal(title, width, height, onClose)
        local sg = new("ScreenGui", {
                Name = "SGC_Modal",
                ResetOnSpawn = false,
                DisplayOrder = 2000,
                IgnoreGuiInset = false,
                Parent = protectedParent,
        })
        local dim = new("TextButton", {
                Name = "Dim",
                Size = UDim2.fromScale(1, 1),
                BackgroundColor3 = Color3.new(0, 0, 0),
                BackgroundTransparency = 0.4,
                BorderSizePixel = 0,
                Text = "",
                AutoButtonColor = false,
                Parent = sg,
        })
        local win = new("Frame", {
                Size = UDim2.fromOffset(width, height),
                Position = UDim2.fromScale(0.5, 0.5),
                AnchorPoint = Vector2.new(0.5, 0.5),
                BackgroundColor3 = THEME.bg2,
                BorderSizePixel = 0,
                Active = true,
                Parent = dim,
        })
        mkCorner(8, win)
        mkStroke(THEME.stroke, 1, win)
        pcall(function()
                local cam = workspace.CurrentCamera
                local vs = cam and cam.ViewportSize or Vector2.new(1280, 720)
                local scale = math.min(1, (vs.X - 16) / width, (vs.Y - 16) / height)
                if scale < 1 then
                        new("UIScale", { Scale = scale, Parent = win })
                end
        end)

        local bar = new("Frame", {
                Size = UDim2.new(1, 0, 0, 28),
                BackgroundColor3 = THEME.bg,
                BorderSizePixel = 0,
                Parent = win,
        })
        new("TextLabel", {
                BackgroundTransparency = 1,
                Size = UDim2.new(1, -44, 1, 0),
                Position = UDim2.fromOffset(10, 0),
                Text = title,
                TextColor3 = THEME.text,
                Font = THEME.fontBold,
                TextSize = 13,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Parent = bar,
        })
        local closeBtn = UI.makeToolbarButton("X", nil, { parent = bar, size = UDim2.fromOffset(24, 20) })
        closeBtn.Position = UDim2.new(1, -28, 0, 4)

        local body = new("Frame", {
                Position = UDim2.fromOffset(0, 28),
                Size = UDim2.new(1, 0, 1, -28),
                BackgroundTransparency = 1,
                Parent = win,
        })

        local function close()
                for i, w in ipairs(UI.windows) do
                        if w == sg then
                                table.remove(UI.windows, i)
                                break
                        end
                end
                if onClose then
                        pcall(onClose)
                end
                pcall(function()
                        sg:Destroy()
                end)
        end
        closeBtn.MouseButton1Click:Connect(close)
        dim.MouseButton1Click:Connect(close)
        UI.windows[#UI.windows + 1] = sg

        return { sg = sg, dim = dim, win = win, body = body, close = close }
end

-- ====================================================================
-- EXPORTER — reflection-driven, standalone, re-runnable Luau
-- ====================================================================

local function generateExportCode()
        local roots = getProjectRoots()
        local out = {
                "-- ==================================================================",
                "-- GUI exported from StudioGUI Creator v3.0",
                ("-- Executor: %s   Date: %s"):format(Executor.name, os.date("%Y-%m-%d %H:%M:%S")),
                "-- Runs standalone: rebuilds every project ScreenGui under PlayerGui.",
                "-- ==================================================================",
                "",
                "local Players = game:GetService('Players')",
                "local LocalPlayer = Players.LocalPlayer",
                "local PlayerGui = LocalPlayer:WaitForChild('PlayerGui')",
                "",
                "local function build()",
        }
        local used = {}
        local parentLines = {}
        local skipped = 0

        local function sanitizeVar(base)
                base = tostring(base):gsub("[^%w_]", "_")
                if #base == 0 then
                        base = "instance"
                end
                if base:match("^%d") then
                        base = "_" .. base
                end
                if LUAU_RESERVED[base] then
                        base = base .. "_"
                end
                local candidate = base
                local i = 1
                while used[candidate] do
                        candidate = base .. "_" .. i
                        i = i + 1
                end
                used[candidate] = true
                return candidate
        end

        local function walk(inst, parentVar)
                local varBase = inst.Name
                if varBase == nil or #varBase == 0 then
                        varBase = inst.ClassName
                end
                local var = sanitizeVar(varBase)
                out[#out + 1] = ("\tlocal %s = Instance.new(%q)"):format(var, inst.ClassName)
                out[#out + 1] = ("\t%s.Name = %q"):format(var, inst.Name)

                local proto = Reflection.prototype(inst.ClassName)
                local names = Reflection.propertyNames(inst)
                for _, prop in ipairs(names) do
                        if prop ~= "Name" and prop ~= "Parent" then
                                local okRead, value = Reflection.readable(inst, prop)
                                if okRead and Reflection.writable(inst.ClassName, prop) then
                                        local isDefault = false
                                        if proto then
                                                local okD, dvalue = Reflection.readable(proto, prop)
                                                if okD then
                                                        local a = Reflection.serializeValue(value)
                                                        local b = Reflection.serializeValue(dvalue)
                                                        if a and b and deepEqualTagged(a, b) then
                                                                isDefault = true
                                                        end
                                                end
                                        end
                                        if not isDefault then
                                                local code = Reflection.valueToLuau(value)
                                                if code then
                                                        if prop == "Source" then
                                                                out[#out + 1] = ("\tpcall(function() %s.Source = %s end) -- Source writes are executor-dependent"):format(var, code)
                                                        else
                                                                out[#out + 1] = ("\t%s.%s = %s"):format(var, prop, code)
                                                        end
                                                else
                                                        skipped = skipped + 1
                                                end
                                        end
                                end
                        end
                end

                for _, child in ipairs(inst:GetChildren()) do
                        walk(child, var)
                end
                parentLines[#parentLines + 1] = ("\t%s.Parent = %s"):format(var, parentVar and parentVar or "PlayerGui")
        end

        for _, root in ipairs(roots) do
                walk(root, nil)
        end
        for _, line in ipairs(parentLines) do
                out[#out + 1] = line
        end

        out[#out + 1] = "end"
        out[#out + 1] = ""
        out[#out + 1] = "local ok, err = pcall(build)"
        out[#out + 1] = "if not ok then"
        out[#out + 1] = "\twarn('[StudioGUI Export] build failed: ' .. tostring(err))"
        out[#out + 1] = "end"
        if skipped > 0 then
                out[#out + 1] = ("-- NOTE: %d property value(s) could not be serialized (unsupported types)."):format(skipped)
        end
        return table.concat(out, "\n")
end

openExport = function()
        local code = generateExportCode()
        local modal = UI.makeModal("Export Luau — " .. #code .. " chars", 560, 420)
        local box = new("TextBox", {
                Size = UDim2.new(1, -16, 1, -54),
                Position = UDim2.fromOffset(8, 8),
                BackgroundColor3 = THEME.bg,
                TextColor3 = THEME.text,
                BorderSizePixel = 0,
                Text = code,
                Font = Enum.Font.Code,
                TextSize = 11,
                TextWrapped = true,
                MultiLine = true,
                ClearTextOnFocus = false,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextYAlignment = Enum.TextYAlignment.Top,
                Parent = modal.body,
        })
        mkCorner(6, box)
        mkStroke(THEME.stroke, 1, box)
        local btnRow = new("Frame", {
                Position = UDim2.new(0, 8, 1, -38),
                Size = UDim2.new(1, -16, 0, 30),
                BackgroundTransparency = 1,
                Parent = modal.body,
        })
        new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), Parent = btnRow })
        UI.makeToolbarButton("Copy", function()
                if Executor.setclipboard then
                        local ok = pcall(Executor.setclipboard, code)
                        notify(ok and "Copied to clipboard." or "setclipboard failed.", ok and "success" or "error")
                else
                        notify("No setclipboard here — select the text and copy manually.", "warn")
                end
        end, { parent = btnRow, size = UDim2.fromOffset(90, 30) })
        UI.makeToolbarButton("Save File", function()
                if not FS.capable then
                        notify("Executor has no writefile.", "error")
                        return
                end
                local ok = FS.write(EXPORT_FILENAME, code)
                notify(ok and ("Saved " .. EXPORT_FILENAME) or "writefile failed.", ok and "success" or "error")
        end, { parent = btnRow, size = UDim2.fromOffset(90, 30) })
        UI.makeToolbarButton("Close", modal.close, { parent = btnRow, size = UDim2.fromOffset(70, 30) })
        notify("Export generated — " .. #code .. " characters.", "info")
end

-- ====================================================================
-- SAVE / LOAD  (Save1.json / Save1.luau)
-- ====================================================================

local function sanitizeSaveName(name)
        name = tostring(name or "Save1"):gsub("^%s+", ""):gsub("%s+$", "")
        name = name:match("[/\\]([^/\\]+)$") or name
        name = name:gsub("%.json$", ""):gsub("%.luau$", "")
        name = name:gsub("[^%w%-_]", "")
        if #name == 0 then
                name = "Save1"
        end
        return name
end

local function serializeTree(inst, stats)
        local node = { class = inst.ClassName, name = inst.Name, props = {}, children = {} }
        local proto = Reflection.prototype(inst.ClassName)
        local names = Reflection.propertyNames(inst)
        for _, prop in ipairs(names) do
                if prop ~= "Parent" then
                        local okRead, value = Reflection.readable(inst, prop)
                        if okRead and Reflection.writable(inst.ClassName, prop) then
                                local isDefault = false
                                if proto then
                                        local okD, dvalue = Reflection.readable(proto, prop)
                                        if okD then
                                                local a = Reflection.serializeValue(value)
                                                local b = Reflection.serializeValue(dvalue)
                                                if a and b and deepEqualTagged(a, b) then
                                                        isDefault = true
                                                end
                                        end
                                end
                                if not isDefault then
                                        local tag = Reflection.serializeValue(value)
                                        if tag then
                                                node.props[prop] = tag
                                        else
                                                stats.skipped = stats.skipped + 1
                                        end
                                end
                        end
                end
        end
        for _, child in ipairs(inst:GetChildren()) do
                node.children[#node.children + 1] = serializeTree(child, stats)
        end
        return node
end

local function buildSaveTable()
        local stats = { skipped = 0 }
        local tree = {}
        for _, root in ipairs(getProjectRoots()) do
                tree[#tree + 1] = serializeTree(root, stats)
        end
        local data = {
                format = SAVE_MAGIC,
                version = 1,
                savedAt = os.date("%Y-%m-%d %H:%M:%S"),
                executor = Executor.name,
                tree = tree,
        }
        return data, stats
end

local function saveProject(name, fmt)
        if not FS.capable then
                notify("This executor has no writefile/readfile — saving unavailable.", "error", 4)
                return false
        end
        name = sanitizeSaveName(name)
        fmt = (fmt == "luau") and "luau" or "json"
        local data, stats = buildSaveTable()
        local ok = false
        if fmt == "luau" then
                local text = "-- StudioGUI Creator save (" .. SAVE_MAGIC .. " v1)\n"
                        .. "-- Saved: " .. data.savedAt .. " | Executor: " .. Executor.name .. "\n"
                        .. "-- Load this file again via the editor's Load button.\n"
                        .. "return " .. tableToLuau(data, "") .. "\n"
                ok = FS.write(FS.path(name, "luau"), text)
                if ok then
                        FS.backup(name, "luau", text)
                end
        else
                local okE, encoded = pcall(function()
                        return HttpService:JSONEncode(data)
                end)
                if not okE or type(encoded) ~= "string" then
                        notify("JSON encode failed — try the .luau format instead.", "error", 4)
                        return false
                end
                ok = FS.write(FS.path(name, "json"), encoded)
                if ok then
                        FS.backup(name, "json", encoded)
                end
        end
        if ok then
                local note = stats.skipped > 0 and (" (%d value(s) skipped — unsupported types)"):format(stats.skipped) or ""
                notify(("Saved %s%s"):format(FS.path(name, fmt), note), "success", 4)
        else
                notify("writefile failed — check executor permissions.", "error", 4)
        end
        return ok
end

local function deserializeNode(node, stats)
        if type(node) ~= "table" or type(node.class) ~= "string" then
                stats.failed = stats.failed + 1
                return nil
        end
        local ok, inst = pcall(Instance.new, node.class)
        if not ok or typeof(inst) ~= "Instance" then
                stats.failed = stats.failed + 1
                return nil
        end
        pcall(function()
                inst.Name = tostring(node.name or node.class)
        end)
        if type(node.props) == "table" then
                for prop, tag in pairs(node.props) do
                        if prop ~= "Parent" and prop ~= "Name" then
                                local value = Reflection.deserializeValue(tag)
                                if value ~= nil then
                                        local okA = pcall(function()
                                                inst[prop] = value
                                        end)
                                        if not okA then
                                                stats.propFails = stats.propFails + 1
                                        end
                                else
                                        stats.valueFails = stats.valueFails + 1
                                end
                        end
                end
        end
        if type(node.children) == "table" then
                for _, childNode in ipairs(node.children) do
                        local child = deserializeNode(childNode, stats)
                        if child then
                                child.Parent = inst
                        end
                end
        end
        return inst
end

local function loadFromData(data)
        if type(data) ~= "table" or data.format ~= SAVE_MAGIC then
                return false, "not a StudioGUI save"
        end
        if type(data.tree) ~= "table" or #data.tree == 0 then
                return false, "save has an empty tree"
        end
        for _, root in ipairs(getProjectRoots()) do
                pcall(function()
                        root:Destroy()
                end)
        end
        local stats = { failed = 0, propFails = 0, valueFails = 0 }
        local built = 0
        for _, node in ipairs(data.tree) do
                local root = deserializeNode(node, stats)
                if root then
                        if root:IsA("ScreenGui") then
                                markProject(root)
                        end
                        root.Parent = State.coreGuiMode and (protectedParent or PROJECT_PARENT) or PROJECT_PARENT
                        built = built + 1
                end
        end
        ensureProjectIntegrity()
        invalidateExplorer()
        Editor.select(nil)
        local issues = stats.failed + stats.propFails + stats.valueFails
        local msg = ("Loaded %d root(s) — %d issue(s)"):format(built, issues)
        if stats.failed > 0 then
                msg = msg .. (" | %d instance(s) skipped"):format(stats.failed)
        end
        if stats.propFails > 0 then
                msg = msg .. (" | %d write(s) rejected"):format(stats.propFails)
        end
        if stats.valueFails > 0 then
                msg = msg .. (" | %d value(s) unreadable"):format(stats.valueFails)
        end
        notify(msg, issues > 0 and "warn" or "success", 5)
        return true
end

-- Executes a saved .luau file: either `return { ... }` save data or a
-- runnable export script (loadfile / dofile / loadstring chain).
local function dataFromLuaFile(path)
        local chunk
        local text = FS.read(path)
        if text then
                if Executor.loadstring then
                        local ok, f = pcall(Executor.loadstring, text)
                        if ok and type(f) == "function" then
                                chunk = f
                        end
                end
                if not chunk and type(loadstring) == "function" then
                        local ok, f = pcall(loadstring, text)
                        if ok and type(f) == "function" then
                                chunk = f
                        end
                end
        end
        if not chunk and Executor.loadfile then
                local ok, f = pcall(Executor.loadfile, path)
                if ok and type(f) == "function" then
                        chunk = f
                end
        end
        if chunk then
                local okR, data = pcall(chunk)
                if okR and type(data) == "table" then
                        return data
                end
        end
        if Executor.dofile then
                local okR, data = pcall(Executor.dofile, path)
                if okR and type(data) == "table" then
                        return data
                end
        end
        return nil
end

local function adoptFromRunnable(text)
        local chunk
        if Executor.loadstring then
                local ok, f = pcall(Executor.loadstring, text)
                if ok and type(f) == "function" then
                        chunk = f
                end
        end
        if not chunk and type(loadstring) == "function" then
                local ok, f = pcall(loadstring, text)
                if ok and type(f) == "function" then
                        chunk = f
                end
        end
        if not chunk then
                notify("No loadstring available to run this file.", "error")
                return false
        end
        local before = {}
        for _, parent in ipairs({ PROJECT_PARENT, protectedParent }) do
                if parent then
                        pcall(function()
                                for _, inst in ipairs(parent:GetChildren()) do
                                        before[inst] = true
                                end
                        end)
                end
        end
        local ok, err = pcall(chunk)
        if not ok then
                notify("Script failed: " .. tostring(err), "error", 5)
                return false
        end
        task.wait(0.15)
        local adopted = 0
        for _, parent in ipairs({ PROJECT_PARENT, protectedParent }) do
                if parent then
                        pcall(function()
                                for _, inst in ipairs(parent:GetChildren()) do
                                        if not before[inst] and inst:IsA("ScreenGui") then
                                                markProject(inst)
                                                adopted = adopted + 1
                                        end
                                end
                        end)
                end
        end
        ensureProjectIntegrity()
        invalidateExplorer()
        Editor.select(nil)
        notify(("Adopted %d new ScreenGui(s) from the script."):format(adopted), adopted > 0 and "success" or "warn")
        return true
end

local function loadProject(name, fmt)
        if not FS.capable then
                notify("This executor has no readfile — loading unavailable.", "error", 4)
                return false
        end
        name = sanitizeSaveName(name)
        fmt = (fmt == "luau") and "luau" or "json"
        local path = FS.path(name, fmt)
        if not FS.exists(path) then
                notify(path .. " does not exist.", "warn")
                return false
        end
        if fmt == "json" then
                local text = FS.read(path)
                if not text then
                        notify("readfile failed.", "error")
                        return false
                end
                local okD, data = pcall(function()
                        return HttpService:JSONDecode(text)
                end)
                if not okD or type(data) ~= "table" then
                        notify("Invalid JSON in " .. path, "error", 4)
                        return false
                end
                local okL, res, reason = pcall(loadFromData, data)
                if not okL then
                        notify("Load failed: " .. tostring(res), "error", 4)
                        return false
                end
                if res == false then
                        notify("Not a valid save: " .. tostring(reason), "error", 4)
                        return false
                end
                return true
        end
        -- luau: save data table OR runnable export script
        local data = dataFromLuaFile(path)
        if data then
                local okL, res = pcall(loadFromData, data)
                if okL and res ~= false then
                        return true
                end
                notify("Save data invalid — trying as runnable script...", "warn")
        end
        local text = FS.read(path)
        if text then
                return adoptFromRunnable(text)
        end
        notify("Could not load " .. path, "error")
        return false
end

openSavesModal = function(mode)
        if not FS.capable then
                notify("Executor lacks writefile/readfile — file saving unavailable.", "error", 4)
                return
        end
        local isSave = (mode ~= "load")
        local modal = UI.makeModal(isSave and "Save project" or "Load project", 460, 400)
        local body = modal.body

        local nameBox = new("TextBox", {
                Size = UDim2.new(1, -160, 0, 26),
                Position = UDim2.fromOffset(10, 10),
                BackgroundColor3 = THEME.bg,
                TextColor3 = THEME.text,
                Text = "Save1",
                PlaceholderText = "Save1",
                ClearTextOnFocus = false,
                Font = THEME.font,
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = body,
        })
        mkCorner(5, nameBox)
        mkStroke(THEME.stroke, 1, nameBox)

        local fmtBtn
        local function fmtLabel()
                return State.saveFmt == "json" and "Format: JSON" or "Format: LUAU"
        end
        fmtBtn = UI.makeToolbarButton(fmtLabel(), function()
                State.saveFmt = (State.saveFmt == "json") and "luau" or "json"
                fmtBtn.Text = fmtLabel()
        end, { parent = body, size = UDim2.fromOffset(110, 26) })
        fmtBtn.Position = UDim2.new(1, -120, 0, 10)

        local refreshList
        local actionBtn = UI.makeToolbarButton(isSave and "Save" or "Load", function()
                if isSave then
                        saveProject(nameBox.Text, State.saveFmt)
                        refreshList()
                else
                        loadProject(nameBox.Text, State.saveFmt)
                end
        end, { parent = body, size = UDim2.fromOffset(120, 28), color = isSave and THEME.green or THEME.accent })
        actionBtn.Position = UDim2.fromOffset(10, 44)

        local wipeBtn = UI.makeToolbarButton("Wipe backups", function()
                local ok = FS.wipeBackups()
                notify(ok and "Backups folder wiped." or "Could not wipe (no delfolder/listfiles).", ok and "success" or "warn")
        end, { parent = body, size = UDim2.fromOffset(120, 28) })
        wipeBtn.Position = UDim2.fromOffset(136, 44)

        new("TextLabel", {
                BackgroundTransparency = 1,
                Size = UDim2.new(1, -20, 0, 16),
                Position = UDim2.fromOffset(10, 78),
                Text = "Existing saves (every *.json / *.luau found):",
                TextColor3 = THEME.textDim,
                Font = THEME.fontMed,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = body,
        })

        local listScroll = UI.makeScrollList(body)
        listScroll.Position = UDim2.fromOffset(10, 96)
        listScroll.Size = UDim2.new(1, -20, 1, -106)

        nameBox.FocusLost:Connect(function(enter)
                if enter and isSave then
                        saveProject(nameBox.Text, State.saveFmt)
                        refreshList()
                end
        end)

        refreshList = function()
                for _, c in ipairs(listScroll:GetChildren()) do
                        if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then
                                c:Destroy()
                        end
                end
                local saves = FS.listSaves()
                if #saves == 0 then
                        new("TextLabel", {
                                BackgroundTransparency = 1,
                                Size = UDim2.new(1, 0, 0, 24),
                                Text = "No save files (*.json / *.luau) found yet.",
                                TextColor3 = THEME.textDim,
                                Font = THEME.font,
                                TextSize = 11,
                                Parent = listScroll,
                        })
                        return
                end
                for i, entry in ipairs(saves) do
                        local row = new("Frame", {
                                Size = UDim2.new(1, 0, 0, 26),
                                BackgroundColor3 = THEME.bg2,
                                BorderSizePixel = 0,
                                LayoutOrder = i,
                                Parent = listScroll,
                        })
                        mkCorner(5, row)
                        local sizeText = ""
                        local fileData = FS.read(entry.path)
                        if fileData then
                                sizeText = ("   (%d KB)"):format(math.floor(#fileData / 1024 * 10 + 0.5) / 10)
                        end
                        new("TextLabel", {
                                BackgroundTransparency = 1,
                                Size = UDim2.new(1, -176, 1, 0),
                                Position = UDim2.fromOffset(8, 0),
                                Text = entry.name .. "." .. entry.fmt .. sizeText,
                                TextColor3 = THEME.text,
                                Font = THEME.font,
                                TextSize = 11,
                                TextXAlignment = Enum.TextXAlignment.Left,
                                TextTruncate = Enum.TextTruncate.AtEnd,
                                Parent = row,
                        })
                        local actBtn = UI.makeToolbarButton(isSave and "Overwrite" or "Load", function()
                                if isSave then
                                        saveProject(entry.name, entry.fmt)
                                        refreshList()
                                else
                                        loadProject(entry.name, entry.fmt)
                                end
                        end, { parent = row, size = UDim2.fromOffset(78, 20), color = isSave and THEME.orange or THEME.accent })
                        actBtn.Position = UDim2.new(1, -112, 0, 3)
                        local delBtn = UI.makeToolbarButton("Del", function()
                                if FS.delete(entry.path) then
                                        notify("Deleted " .. entry.path, "info")
                                        refreshList()
                                else
                                        notify("delfile unavailable or failed.", "warn")
                                end
                        end, { parent = row, size = UDim2.fromOffset(42, 20), color = THEME.red })
                        delBtn.Position = UDim2.new(1, -46, 0, 3)
                end
        end
        refreshList()
end

-- ====================================================================
-- ADD INSTANCE MODAL  (type ANY class name, e.g. LocalScript)
-- ====================================================================

openAddInstanceModal = function()
        local modal = UI.makeModal("Add Instance", 420, 380)
        local body = modal.body

        local input = new("TextBox", {
                Size = UDim2.new(1, -20, 0, 28),
                Position = UDim2.fromOffset(10, 10),
                BackgroundColor3 = THEME.bg,
                TextColor3 = THEME.text,
                PlaceholderText = "Type a class name, e.g. LocalScript, Sound, RemoteEvent...",
                ClearTextOnFocus = false,
                Font = THEME.font,
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Parent = body,
        })
        mkCorner(5, input)
        mkStroke(THEME.stroke, 1, input)

        UI.makeToolbarButton("Add instance", function()
                if input.Text ~= "" then
                        Editor.spawnArbitrary(input.Text)
                end
        end, { parent = body, size = UDim2.new(1, -20, 0, 28), color = THEME.green }).Position = UDim2.fromOffset(10, 44)

        new("TextLabel", {
                BackgroundTransparency = 1,
                Size = UDim2.new(1, -20, 0, 16),
                Position = UDim2.fromOffset(10, 78),
                Text = "Suggestions are auto-discovered creatable classes — press Enter to add:",
                TextColor3 = THEME.textDim,
                Font = THEME.font,
                TextSize = 10,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Parent = body,
        })

        local suggestionScroll = UI.makeScrollList(body)
        suggestionScroll.Position = UDim2.fromOffset(10, 96)
        suggestionScroll.Size = UDim2.new(1, -20, 1, -106)

        local refreshSuggestions
        refreshSuggestions = function()
                for _, c in ipairs(suggestionScroll:GetChildren()) do
                        if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then
                                c:Destroy()
                        end
                end
                local classes = Reflection.filteredClasses(input.Text, 40, State.catalogMode)
                for i, className in ipairs(classes) do
                        local row = new("TextButton", {
                                Size = UDim2.new(1, 0, 0, 22),
                                BackgroundColor3 = THEME.bg2,
                                BorderSizePixel = 0,
                                Text = "",
                                AutoButtonColor = true,
                                LayoutOrder = i,
                                Parent = suggestionScroll,
                        })
                        mkCorner(4, row)
                        local icon = new("Frame", {
                                Size = UDim2.fromOffset(14, 14),
                                Position = UDim2.fromOffset(4, 4),
                                BackgroundColor3 = classColor(className),
                                BorderSizePixel = 0,
                                Parent = row,
                        })
                        mkCorner(3, icon)
                        new("TextLabel", {
                                BackgroundTransparency = 1,
                                Size = UDim2.new(1, -26, 1, 0),
                                Position = UDim2.fromOffset(22, 0),
                                Text = className,
                                TextColor3 = THEME.text,
                                Font = THEME.font,
                                TextSize = 11,
                                TextXAlignment = Enum.TextXAlignment.Left,
                                TextTruncate = Enum.TextTruncate.AtEnd,
                                Parent = row,
                        })
                        row.MouseButton1Click:Connect(function()
                                Editor.spawnArbitrary(className)
                        end)
                end
        end

        input:GetPropertyChangedSignal("Text"):Connect(function()
                pcall(refreshSuggestions)
        end)
        input.FocusLost:Connect(function(enter)
                if enter and input.Text ~= "" then
                        Editor.spawnArbitrary(input.Text)
                end
        end)
        refreshSuggestions()
end

openFileAssetPrompt = function(callback)
        local modal = UI.makeModal("Load asset from file (getcustomasset)", 420, 150)
        local input = new("TextBox", {
                Size = UDim2.new(1, -20, 0, 26),
                Position = UDim2.fromOffset(10, 10),
                BackgroundColor3 = THEME.bg,
                TextColor3 = THEME.text,
                PlaceholderText = "path/to/image.png",
                ClearTextOnFocus = false,
                Font = THEME.font,
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = modal.body,
        })
        mkCorner(5, input)
        mkStroke(THEME.stroke, 1, input)
        local okBtn = UI.makeToolbarButton("Load", function()
                local path = input.Text
                if #path > 0 then
                        modal.close()
                        callback(path)
                end
        end, { parent = modal.body, size = UDim2.fromOffset(80, 26), color = THEME.green })
        okBtn.Position = UDim2.fromOffset(10, 44)
end

-- ====================================================================
-- SCRIPT SOURCE EDITOR  (edit any LocalScript / Script / ModuleScript)
-- ====================================================================

openScriptEditor = function(inst)
        if typeof(inst) ~= "Instance" or inst.Parent == nil then
                return
        end
        if not (inst:IsA("LocalScript") or inst:IsA("Script") or inst:IsA("ModuleScript")) then
                notify("Select a LocalScript / Script / ModuleScript first.", "warn")
                return
        end
        local okR, src = pcall(function()
                return inst.Source
        end)
        if not okR then
                notify("Source is not readable on this executor.", "error")
                return
        end
        local modal = UI.makeModal("Edit Source — " .. inst.Name, 640, 440)
        local box = new("TextBox", {
                Size = UDim2.new(1, -16, 1, -76),
                Position = UDim2.fromOffset(8, 8),
                BackgroundColor3 = THEME.bg,
                TextColor3 = THEME.text,
                BorderSizePixel = 0,
                Text = tostring(src),
                Font = Enum.Font.Code,
                TextSize = 11,
                TextWrapped = true,
                MultiLine = true,
                ClearTextOnFocus = false,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextYAlignment = Enum.TextYAlignment.Top,
                Parent = modal.body,
        })
        mkCorner(6, box)
        mkStroke(THEME.stroke, 1, box)
        local btnRow = new("Frame", {
                Position = UDim2.new(0, 8, 1, -38),
                Size = UDim2.new(1, -16, 0, 30),
                BackgroundTransparency = 1,
                Parent = modal.body,
        })
        new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), Parent = btnRow })
        UI.makeToolbarButton("Apply", function()
                if typeof(inst) ~= "Instance" or inst.Parent == nil then
                        notify("Script is gone.", "warn")
                        return
                end
                local okW, err = pcall(function()
                        inst.Source = box.Text
                end)
                if okW then
                        notify("Source saved to " .. inst.Name .. ".", "success")
                else
                        notify("Source write failed: " .. tostring(err), "error", 4)
                end
        end, { parent = btnRow, size = UDim2.fromOffset(90, 30), color = THEME.green })
        UI.makeToolbarButton("Reload", function()
                pcall(function()
                        box.Text = tostring(inst.Source)
                end)
        end, { parent = btnRow, size = UDim2.fromOffset(80, 30) })
        UI.makeToolbarButton("Close", modal.close, { parent = btnRow, size = UDim2.fromOffset(70, 30) })
end

-- ====================================================================
-- EDITOR API
-- ====================================================================

-- Connections collected here so Editor.destroy can tear everything down.
local liveConnections = {}

-- Classes the user "selects" when they want new stuff to go INSIDE them.
local SPAWN_CONTAINERS = {
        ScreenGui      = true, Frame          = true, ScrollingFrame = true,
        CanvasGroup    = true, ViewportFrame  = true, Folder         = true,
        BillboardGui   = true, SurfaceGui     = true,
}

-- Fresh scripts get REAL starter code, not an empty shell.
local SCRIPT_TEMPLATE_MAIN = [==[
-- Created with StudioGUI Creator
local function main()
        print("Hello from " .. script.Name)
        -- TODO: put your code here
end

main()
]==]

local SCRIPT_TEMPLATE_BUTTON = [==[
-- Created with StudioGUI Creator
local button = script.Parent

local function onClick()
        print(button.Name .. " was clicked!")
        -- TODO: react to the click here
end

button.MouseButton1Click:Connect(onClick)
]==]

local SCRIPT_TEMPLATE_MODULE = [==[
-- Created with StudioGUI Creator
local Module = {}

function Module.main(...)
        print("Module " .. script.Name .. " loaded")
        -- TODO: put your functions here
        return true
end

return Module
]==]

local function applyScriptTemplate(inst)
        local class = inst.ClassName
        if class ~= "LocalScript" and class ~= "Script" and class ~= "ModuleScript" then
                return
        end
        local okR, src = pcall(function()
                return inst.Source
        end)
        if not okR or (type(src) == "string" and #src > 0) then
                return -- Source not writable or already filled
        end
        local code = SCRIPT_TEMPLATE_MAIN
        if class == "ModuleScript" then
                code = SCRIPT_TEMPLATE_MODULE
        elseif typeof(inst.Parent) == "Instance" and inst.Parent:IsA("GuiButton") then
                code = SCRIPT_TEMPLATE_BUTTON
        end
        local okW = pcall(function()
                inst.Source = code
        end)
        if okW then
                notify(class .. " created with starter code — select it and press Edit Source to change it.", "success", 4)
        else
                notify(class .. " created, but this executor blocked the Source write.", "warn", 4)
        end
end

local function resolveSpawnParent(inst)
        if inst:IsA("ScreenGui") then
                inst.Name = uniqueRootName(inst.ClassName)
                markProject(inst)
                inst.Parent = State.coreGuiMode and (protectedParent or PROJECT_PARENT) or PROJECT_PARENT
                return true
        end
        local sel = State.selected
        local selValid = (sel ~= nil and typeof(sel) == "Instance" and sel.Parent ~= nil)

        -- UI components attach to the selected GuiObject — or the nearest
        -- GuiObject above the selection (v2 demanded an exact selection).
        if inst:IsA("UIComponent") then
                local target = nil
                if selValid and sel:IsA("GuiObject") then
                        target = sel
                else
                        local node = selValid and sel.Parent or nil
                        while node and typeof(node) == "Instance" do
                                if node:IsA("GuiObject") then
                                        target = node
                                        break
                                end
                                if node:IsA("LayerCollector") then
                                        break
                                end
                                node = node.Parent
                        end
                end
                if not target then
                        notify("Select a Frame/Label/etc. first — UI components attach to GuiObjects.", "warn", 4)
                        return false
                end
                inst.Parent = target
                siblingUniqueName(inst)
                return true
        end

        -- Everything else: the new instance is the LAST CHILD of the
        -- selected CONTAINER (ScreenGui / Frame / ScrollingFrame / ...).
        -- If the selection is a leaf widget (Label, Button, UIStroke, ...),
        -- the new instance becomes its SIBLING — bottom of the SAME parent —
        -- so it is never nested under some unrelated instance.
        local target = nil
        if selValid then
                if SPAWN_CONTAINERS[sel.ClassName] or sel:IsA("LayerCollector") then
                        target = sel
                else
                        target = sel.Parent
                end
        end
        if not target then
                target = firstProjectRoot()
        end
        if not target then
                ensureProjectIntegrity()
                target = firstProjectRoot()
        end
        if not target then
                notify("No project ScreenGui available.", "error")
                return false
        end
        inst.Parent = target
        siblingUniqueName(inst)
        return true
end

function Editor.select(inst)
        if inst ~= nil and (typeof(inst) ~= "Instance" or inst.Parent == nil) then
                inst = nil
        end
        State.selected = inst
        pcall(rebuildProperties)
        pcall(refreshExplorerSelection)
end

function Editor.spawnClass(className)
        if type(className) ~= "string" or not Reflection.isCreatable(className) then
                notify("'" .. tostring(className) .. "' cannot be created.", "error")
                return nil
        end
        local ok, inst = pcall(Instance.new, className)
        if not ok or typeof(inst) ~= "Instance" then
                notify("Instance.new failed: " .. tostring(inst), "error")
                return nil
        end
        if not resolveSpawnParent(inst) then
                pcall(function()
                        inst:Destroy()
                end)
                return nil
        end
        pcall(applyScriptTemplate, inst)
        invalidateExplorer()
        Editor.select(inst)
        return inst
end

function Editor.spawnArbitrary(className)
        className = tostring(className or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if #className == 0 then
                notify("Type a class name first.", "warn")
                return nil
        end
        if not Reflection.isCreatable(className) then
                notify("'" .. className .. "' is not a creatable Roblox class.", "error", 4)
                return nil
        end
        return Editor.spawnClass(className)
end

function Editor.deleteSelected()
        local inst = State.selected
        if typeof(inst) ~= "Instance" or inst.Parent == nil then
                notify("Nothing selected.", "warn")
                return
        end
        if inst:IsA("ScreenGui") and isProject(inst) then
                if #getProjectRoots() <= 1 then
                        notify("Cannot delete the last project ScreenGui.", "warn", 4)
                        return
                end
        end
        local name = inst.Name
        local ok, err = pcall(function()
                inst:Destroy()
        end)
        if ok then
                notify(("Deleted %s"):format(name), "info")
                Editor.select(nil)
                invalidateExplorer()
        else
                notify("Delete failed: " .. tostring(err), "error")
        end
end

function Editor.duplicateSelected()
        local inst = State.selected
        if typeof(inst) ~= "Instance" or inst.Parent == nil then
                notify("Nothing selected.", "warn")
                return
        end
        local ok, clone = pcall(function()
                return inst:Clone()
        end)
        if not ok or typeof(clone) ~= "Instance" then
                notify("Clone failed: " .. tostring(clone), "error")
                return
        end
        if clone:IsA("ScreenGui") then
                clone.Name = uniqueRootName(inst.Name)
                markProject(clone)
                clone.Parent = PROJECT_PARENT
        else
                clone.Parent = inst.Parent
        end
        invalidateExplorer()
        Editor.select(clone)
end

function Editor.setEditMode(enabled)
        State.editMode = enabled ~= false
        if UI.modeBtn then
                UI.modeBtn.Text = State.editMode and "Mode: Edit" or "Mode: Test"
                UI.modeBtn.BackgroundColor3 = State.editMode and THEME.accent or THEME.orange
        end
        if UI.hintLabel then
                UI.hintLabel.Visible = State.editMode
        end
        notify(State.editMode and "Edit mode — select, drag, resize." or "Test mode — your GUI is interactive.", "info", 2.5)
end

function Editor.toggleCoreGuiMode()
        State.coreGuiMode = not State.coreGuiMode
        local target = State.coreGuiMode and (protectedParent or PROJECT_PARENT) or PROJECT_PARENT
        local moved = 0
        for _, root in ipairs(getProjectRoots()) do
                if root:IsA("ScreenGui") and root.Parent ~= target then
                        pcall(function()
                                root.Parent = target
                        end)
                        moved = moved + 1
                end
        end
        if UI.coreGuiBtn then
                UI.coreGuiBtn.Text = State.coreGuiMode and "CoreGui: On" or "CoreGui: Off"
                UI.coreGuiBtn.BackgroundColor3 = State.coreGuiMode and THEME.purple or THEME.bg3
        end
        invalidateExplorer()
        notify(State.coreGuiMode
                and ("Project moved to the protected GUI (%d ScreenGui moved). New ScreenGuis spawn there too."):format(moved)
                or "Project moved back to PlayerGui.", "info", 4)
end

function Editor.beginResize(dir, input)
        if State.dragging then
                return
        end
        local inst = State.selected
        if typeof(inst) ~= "Instance" or inst.Parent == nil or not inst:IsA("GuiObject") then
                return
        end
        State.resizing = {
                inst = inst,
                dir = dir,
                startAbs = inst.AbsolutePosition,
                startSize = inst.AbsoluteSize,
                startMouse = Vector2.new(input.Position.X, input.Position.Y),
        }
end

function Editor.destroy()
        for _, conn in ipairs(liveConnections) do
                pcall(function()
                        conn:Disconnect()
                end)
        end
        for inst, conns in pairs(explorerWatchers) do
                for _, c in ipairs(conns) do
                        pcall(function()
                                c:Disconnect()
                        end)
                end
                explorerWatchers[inst] = nil
        end
        for _, sg in ipairs(UI.windows) do
                pcall(function()
                        sg:Destroy()
                end)
        end
        UI.windows = {}
        pcall(function()
                if UI.toastGui then
                        UI.toastGui:Destroy()
                end
        end)
        UI.toastHolder = nil
        pcall(function()
                if UI.overlaySG then
                        UI.overlaySG:Destroy()
                end
        end)
        pcall(function()
                if UI.main then
                        UI.main:Destroy()
                end
        end)
        notify("Editor closed — your project stays in PlayerGui.", "info", 3)
end

-- ====================================================================
-- VIEWPORT OVERLAY (selection box + 8 resize handles)
-- ====================================================================

local overlaySG = new("ScreenGui", {
        Name = "SGC_Overlay",
        ResetOnSpawn = false,
        DisplayOrder = 700,
        IgnoreGuiInset = false,
        Parent = protectedParent,
})
UI.overlaySG = overlaySG

local selBox = new("Frame", {
        Name = "SelBox",
        BackgroundTransparency = 1,
        Visible = false,
        Active = true,
        Parent = overlaySG,
})
mkStroke(THEME.accent, 1.5, selBox)

local sizeLabel = new("TextLabel", {
        BackgroundTransparency = 0.25,
        BackgroundColor3 = THEME.bg2,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 0, 0, -4),
        Size = UDim2.fromOffset(92, 16),
        Text = "",
        TextColor3 = THEME.text,
        Font = THEME.font,
        TextSize = 10,
        Parent = selBox,
})
mkCorner(3, sizeLabel)

local HANDLE_DEFS = {
        { dir = "nw", sx = 0, sy = 0 }, { dir = "n", sx = 0.5, sy = 0 }, { dir = "ne", sx = 1, sy = 0 },
        { dir = "w", sx = 0, sy = 0.5 }, { dir = "e", sx = 1, sy = 0.5 },
        { dir = "sw", sx = 0, sy = 1 }, { dir = "s", sx = 0.5, sy = 1 }, { dir = "se", sx = 1, sy = 1 },
}
for _, def in ipairs(HANDLE_DEFS) do
        local handle = new("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(def.sx, 0, def.sy, 0),
                Size = UDim2.fromOffset(9, 9),
                BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                BorderSizePixel = 0,
                Active = true,
                Parent = selBox,
        })
        mkStroke(THEME.accent, 1, handle)
        handle.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                        Editor.beginResize(def.dir, input)
                end
        end)
end

selBox.InputBegan:Connect(function(input)
        if not State.editMode then
                return
        end
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
                return
        end
        if State.resizing then
                return
        end
        local inst = State.selected
        if typeof(inst) ~= "Instance" or inst.Parent == nil or not inst:IsA("GuiObject") then
                return
        end
        local p = Vector2.new(input.Position.X, input.Position.Y)
        local ap, as = selBox.AbsolutePosition, selBox.AbsoluteSize
        local nearEdge = (p.X <= ap.X + 8) or (p.X >= ap.X + as.X - 8) or (p.Y <= ap.Y + 8) or (p.Y >= ap.Y + as.Y - 8)
        if nearEdge then
                return -- handles take over
        end
        State.dragging = {
                inst = inst,
                startAbs = inst.AbsolutePosition,
                startMouse = p,
        }
end)

local function updateOverlay()
        local inst = State.selected
        local canShow = State.editMode
                and inst ~= nil
                and typeof(inst) == "Instance"
                and inst.Parent ~= nil
                and inst:IsA("GuiObject")
        if not canShow then
                selBox.Visible = false
                return
        end
        local rootSG = inst
        while rootSG and typeof(rootSG) == "Instance" and not rootSG:IsA("LayerCollector") do
                rootSG = rootSG.Parent
        end
        if rootSG and typeof(rootSG) == "Instance" then
                pcall(function()
                        overlaySG.IgnoreGuiInset = rootSG.IgnoreGuiInset
                end)
        end
        pcall(function()
                selBox.Position = UDim2.fromOffset(inst.AbsolutePosition.X, inst.AbsolutePosition.Y)
                selBox.Size = UDim2.fromOffset(inst.AbsoluteSize.X, inst.AbsoluteSize.Y)
                sizeLabel.Text = ("%d x %d"):format(inst.AbsoluteSize.X, inst.AbsoluteSize.Y)
        end)
        selBox.Visible = true
end

-- ====================================================================
-- HIT TESTING / EDITOR-UI GUARDS
-- ====================================================================

local function pointIn(el, pos)
        local ok, res = pcall(function()
                local ap, as = el.AbsolutePosition, el.AbsoluteSize
                return pos.X >= ap.X and pos.X <= ap.X + as.X and pos.Y >= ap.Y and pos.Y <= ap.Y + as.Y
        end)
        return ok == true and res == true
end

local function isOverEditorUI(pos)
        if UI.root and pointIn(UI.root, pos) then
                if UI.viewport and pointIn(UI.viewport, pos) then
                        -- inside the viewport gap: NOT editor chrome
                else
                        return true
                end
        end
        for _, sg in ipairs(UI.windows) do
                if typeof(sg) == "Instance" and sg.Parent then
                        local dim = sg:FindFirstChild("Dim")
                        if dim and pointIn(dim, pos) then
                                return true
                        end
                end
        end
        return false
end

local function ancestryVisible(el)
        local node = el
        while node and typeof(node) == "Instance" do
                if node:IsA("GuiObject") then
                        local ok, v = pcall(function()
                                return node.Visible
                        end)
                        if ok and v == false then
                                return false
                        end
                elseif node:IsA("ScreenGui") then
                        local ok, v = pcall(function()
                                return node.Enabled
                        end)
                        if ok and v == false then
                                return false
                        end
                end
                node = node.Parent
        end
        return true
end

-- Fully transparent carriers let clicks pass through (v1 behaviour).
local function isVisuallyHittable(el)
        local ok, bt = pcall(function()
                return el.BackgroundTransparency
        end)
        if ok and bt ~= nil and bt >= 1 then
                local okT, text = pcall(function()
                        return el.Text
                end)
                local okTT, tTrans = pcall(function()
                        return el.TextTransparency
                end)
                if okT and type(text) == "string" and text ~= "" and okTT and tTrans < 1 then
                        return true
                end
                local okI, image = pcall(function()
                        return el.Image
                end)
                local okIT, iTrans = pcall(function()
                        return el.ImageTransparency
                end)
                if okI and type(image) == "string" and image ~= "" and okIT and iTrans < 1 then
                        return true
                end
                return false
        end
        return true
end

local function depthOf(el)
        local d = 0
        local node = el.Parent
        while node and typeof(node) == "Instance" do
                d = d + 1
                node = node.Parent
        end
        return d
end

local function hitTest(pos)
        local best, bestScore = nil, -math.huge
        local px, py = pos.X, pos.Y
        for _, root in ipairs(getProjectRoots()) do
                for _, el in ipairs(root:GetDescendants()) do
                        if el:IsA("GuiObject") then
                                local hitOk = pcall(function()
                                        local ap, as = el.AbsolutePosition, el.AbsoluteSize
                                        return px >= ap.X and px <= ap.X + as.X
                                                and py >= ap.Y and py <= ap.Y + as.Y
                                                and el.Visible ~= false
                                                and as.X > 0 and as.Y > 0
                                end)
                                if hitOk and ancestryVisible(el) and isVisuallyHittable(el) then
                                        local okZ, z = pcall(function()
                                                return el.ZIndex
                                        end)
                                        local score = (okZ and z or 1) * 1000 + depthOf(el)
                                        if score >= bestScore then
                                                bestScore = score
                                                best = el
                                        end
                                end
                        end
                end
        end
        return best
end

-- ====================================================================
-- INPUT (select / drag / resize / keyboard)
-- ====================================================================

local function guiInputSelect(input)
        if not State.editMode then
                return
        end
        if State.dragging or State.resizing then
                return
        end
        local pos = Vector2.new(input.Position.X, input.Position.Y)
        if isOverEditorUI(pos) then
                return
        end
        if selBox.Visible then
                local ap, as = selBox.AbsolutePosition, selBox.AbsoluteSize
                if pos.X >= ap.X - 10 and pos.X <= ap.X + as.X + 10 and pos.Y >= ap.Y - 10 and pos.Y <= ap.Y + as.Y + 10 then
                        return -- selBox / handles own this click
                end
        end
        local hit = hitTest(pos)
        if hit ~= State.selected then
                Editor.select(hit)
        end
        if hit then
                State.dragging = {
                        inst = hit,
                        startAbs = hit.AbsolutePosition,
                        startMouse = pos,
                }
        end
end

liveConnections[#liveConnections + 1] = UserInputService.InputBegan:Connect(function(input, gp)
        pcall(function()
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                        guiInputSelect(input)
                elseif input.UserInputType == Enum.UserInputType.Keyboard then
                        if UserInputService:GetFocusedTextBox() ~= nil then
                                return
                        end
                        if input.KeyCode == Enum.KeyCode.Delete then
                                Editor.deleteSelected()
                        elseif input.KeyCode == Enum.KeyCode.Escape then
                                Editor.select(nil)
                        end
                end
        end)
end)

liveConnections[#liveConnections + 1] = UserInputService.InputChanged:Connect(function(input)
        pcall(function()
                local t = input.UserInputType
                if t ~= Enum.UserInputType.MouseMovement and t ~= Enum.UserInputType.Touch then
                        return
                end
                local pos = Vector2.new(input.Position.X, input.Position.Y)
                if State.windowDrag and UI.root then
                        -- move by delta only: no absolute math, no inset/scale issues
                        local dm = pos - State.windowDrag.lastMouse
                        if dm.X ~= 0 or dm.Y ~= 0 then
                                State.windowDrag.lastMouse = pos
                                UI.root.Position = UI.root.Position + UDim2.fromOffset(dm.X, dm.Y)
                        end
                        return
                end
                if State.dragging then
                        local d = State.dragging
                        if typeof(d.inst) == "Instance" and d.inst.Parent then
                                local dm = pos - d.startMouse
                                d.inst.Position = UDim2.fromOffset(d.startAbs.X + dm.X, d.startAbs.Y + dm.Y)
                        end
                        return
                end
                if State.resizing then
                        local r = State.resizing
                        local inst = r.inst
                        if typeof(inst) ~= "Instance" or inst.Parent == nil then
                                State.resizing = nil
                                return
                        end
                        local dm = pos - r.startMouse
                        local minX, minY = r.startAbs.X, r.startAbs.Y
                        local maxX, maxY = r.startAbs.X + r.startSize.X, r.startAbs.Y + r.startSize.Y
                        local dir = r.dir
                        if dir:find("e") then
                                maxX = maxX + dm.X
                        end
                        if dir:find("w") then
                                minX = minX + dm.X
                        end
                        if dir:find("s") then
                                maxY = maxY + dm.Y
                        end
                        if dir:find("n") then
                                minY = minY + dm.Y
                        end
                        if maxX - minX < MIN_SIZE then
                                if dir:find("w") then
                                        minX = maxX - MIN_SIZE
                                else
                                        maxX = minX + MIN_SIZE
                                end
                        end
                        if maxY - minY < MIN_SIZE then
                                if dir:find("n") then
                                        minY = maxY - MIN_SIZE
                                else
                                        maxY = minY + MIN_SIZE
                                end
                        end
                        inst.Position = UDim2.fromOffset(math.floor(minX + 0.5), math.floor(minY + 0.5))
                        inst.Size = UDim2.fromOffset(math.floor(maxX - minX + 0.5), math.floor(maxY - minY + 0.5))
                end
        end)
end)

liveConnections[#liveConnections + 1] = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                State.dragging = nil
                State.resizing = nil
                State.windowDrag = nil
        end
end)

-- ====================================================================
-- MAIN LOOPS (render tick + watchdog)
-- ====================================================================

local lastStatus = ""

local function renderTick()
        pcall(function()
                if explorerDirty then
                        explorerDirty = false
                        rebuildExplorer()
                end
                if explorerSearchDirtyAt > 0 and os.clock() >= explorerSearchDirtyAt then
                        explorerSearchDirtyAt = 0
                        rebuildExplorer()
                end
                if toolboxSearchDirtyAt > 0 and os.clock() >= toolboxSearchDirtyAt then
                        toolboxSearchDirtyAt = 0
                        refreshToolbox()
                end
                if toolboxShownVersion ~= Reflection.classVersion then
                        refreshToolbox()
                end
                if propsSearchDirtyAt > 0 and os.clock() >= propsSearchDirtyAt then
                        propsSearchDirtyAt = 0
                        rebuildProperties()
                end
                updateOverlay()
                local inst = State.selected
                local text
                if inst and typeof(inst) == "Instance" and inst.Parent then
                        text = "Selected: " .. inst.Name .. "  (" .. inst.ClassName .. ")"
                else
                        text = "No selection — click a GUI element in the viewport"
                end
                if text ~= lastStatus then
                        lastStatus = text
                        UI.statusLabel.Text = text
                end
        end)
end

liveConnections[#liveConnections + 1] = RunService.RenderStepped:Connect(function()
        renderTick()
end)

local watchdogAcc = 0
liveConnections[#liveConnections + 1] = RunService.Heartbeat:Connect(function()
        watchdogAcc = watchdogAcc + 1
        if watchdogAcc % 60 ~= 0 then
                return
        end
        pcall(function()
                if protectedParent then
                        if typeof(UI.main) == "Instance" and UI.main.Parent ~= protectedParent then
                                UI.main.Parent = protectedParent
                        end
                        if typeof(overlaySG) == "Instance" and overlaySG.Parent ~= protectedParent then
                                overlaySG.Parent = protectedParent
                        end
                end
                ensureProjectIntegrity()
                if State.coreGuiMode and protectedParent then
                        for _, root in ipairs(getProjectRoots()) do
                                if root.Parent ~= protectedParent then
                                        pcall(function()
                                                root.Parent = protectedParent
                                        end)
                                end
                        end
                end
        end)
end)

-- panel wiring (search boxes + refresh button) — deferred so the UI exists
local function wirePanels()
        pcall(function()
                UI.toolboxSearch:GetPropertyChangedSignal("Text"):Connect(function()
                        toolboxSearchDirtyAt = os.clock() + 0.2
                end)
                UI.explorerSearch:GetPropertyChangedSignal("Text"):Connect(function()
                        State.explorerFilter = UI.explorerSearch.Text
                        explorerSearchDirtyAt = os.clock() + 0.2
                end)
                UI.propsSearch:GetPropertyChangedSignal("Text"):Connect(function()
                        State.propFilter = UI.propsSearch.Text
                        propsSearchDirtyAt = os.clock() + 0.2
                end)
        end)
end

-- ====================================================================
-- TOOLBAR WIRING (deferred until buildMainUI has created the rows)
-- ====================================================================

local function wireToolbar()
        pcall(function()
        UI.makeToolbarButton("+ ScreenGui", function()
                Editor.spawnClass("ScreenGui")
        end, { parent = UI.row1, size = UDim2.fromOffset(88, 24) })

        UI.makeToolbarButton("Add Instance", function()
                openAddInstanceModal()
        end, { parent = UI.row1, size = UDim2.fromOffset(88, 24) })

        UI.makeToolbarButton("Duplicate", function()
                Editor.duplicateSelected()
        end, { parent = UI.row1, size = UDim2.fromOffset(74, 24) })

        UI.makeToolbarButton("Delete", function()
                Editor.deleteSelected()
        end, { parent = UI.row1, size = UDim2.fromOffset(58, 24), color = THEME.red })

        UI.makeToolbarButton("LocalScript", function()
                Editor.spawnClass("LocalScript")
        end, { parent = UI.row1, size = UDim2.fromOffset(80, 24), color = THEME.green })

        UI.makeToolbarButton("ModuleScript", function()
                Editor.spawnClass("ModuleScript")
        end, { parent = UI.row1, size = UDim2.fromOffset(94, 24), color = THEME.green })

        UI.modeBtn = UI.makeToolbarButton("Mode: Edit", function()
                Editor.setEditMode(not State.editMode)
        end, { parent = UI.row1, size = UDim2.fromOffset(84, 24), color = THEME.accent })

        UI.coreGuiBtn = UI.makeToolbarButton("CoreGui: Off", function()
                Editor.toggleCoreGuiMode()
        end, { parent = UI.row1, size = UDim2.fromOffset(92, 24) })

        UI.makeToolbarButton("Save", function()
                openSavesModal("save")
        end, { parent = UI.row2, size = UDim2.fromOffset(60, 24), color = THEME.green })

        UI.makeToolbarButton("Load", function()
                openSavesModal("load")
        end, { parent = UI.row2, size = UDim2.fromOffset(60, 24) })

        UI.makeToolbarButton("Export Luau", function()
                openExport()
        end, { parent = UI.row2, size = UDim2.fromOffset(90, 24), color = THEME.purple })

        UI.makeToolbarButton("Reload Props", function()
                State.propFilter = ""
                UI.propsSearch.Text = ""
                rebuildProperties()
        end, { parent = UI.row2, size = UDim2.fromOffset(96, 24) })

        local fsFlags = {}
        if FS.capable then
                fsFlags[#fsFlags + 1] = "fs:ok"
        else
                fsFlags[#fsFlags + 1] = "fs:none"
        end
        if Executor.getproperties then
                fsFlags[#fsFlags + 1] = "props:reflect"
        else
                fsFlags[#fsFlags + 1] = "props:pool"
        end
        if Executor.listfiles then
                fsFlags[#fsFlags + 1] = "list:ok"
        end
        if Executor.getcustomasset then
                fsFlags[#fsFlags + 1] = "assets:ok"
        end
        new("TextLabel", {
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, -4, 0, 0),
                Size = UDim2.fromOffset(320, 24),
                BackgroundTransparency = 1,
                Text = table.concat(fsFlags, "  ·  "),
                TextColor3 = THEME.textDim,
                Font = THEME.font,
                TextSize = 10,
                TextXAlignment = Enum.TextXAlignment.Right,
                Parent = UI.row2,
        })
        end)
end

-- ====================================================================
-- BOOT
-- ====================================================================

local function main()
        resolveProtectedParent()
        pcall(function()
                overlaySG.Parent = protectedParent
        end)
        buildMainUI()
        wirePanels()
        wireToolbar()
        ensureProjectIntegrity()
        Editor.select(nil)
        Editor.setEditMode(true)
        Reflection.startDiscovery()
        pcall(function()
                refreshToolbox()
        end)
        -- watch both parents so externally added/removed roots refresh the Explorer
        pcall(function()
                PROJECT_PARENT.ChildAdded:Connect(function()
                        invalidateExplorer()
                end)
                PROJECT_PARENT.ChildRemoved:Connect(function()
                        invalidateExplorer()
                end)
                if protectedParent and protectedParent ~= PROJECT_PARENT then
                        protectedParent.ChildAdded:Connect(function()
                                invalidateExplorer()
                        end)
                        protectedParent.ChildRemoved:Connect(function()
                                invalidateExplorer()
                        end)
                end
        end)
        notify("StudioGUI Creator v3.0 loaded — " .. Executor.name, "success", 4)
end

local okBoot, bootErr = pcall(main)
if not okBoot then
        warn("[StudioGUI Creator] failed to start: " .. tostring(bootErr))
end
