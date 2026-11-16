--[[============================================================================
    StudioGUI Creator v1.4 — WYSIWYG GUI Editor for Roblox
    Modeled after the Roblox Studio workflow.

    FEATURES
    • Insert Panel (left)      — auto-lists every UI class the executor can
                                 create (Frames, Buttons, Labels, gradients,
                                 layouts, constraints, ViewportFrame, ...)
    • Add Instance dialog      — toolbar button; search any class name
                                 (e.g. "LocalScript") and spawn it, or press
                                 Enter to create a custom class by name
    • Real instances only      — everything you insert is a live Instance and
                                 every property editor writes straight to it
    • Explorer                 — live hierarchy tree (shows ALL children:
                                 scripts, values, folders, sounds, ...)
    • Properties               — type-aware editing; Enum properties render as
                                 friendly dropdown lists (no typing "Enum.X.Y"),
                                 colors/UDim2/Vector2 keep simple text inputs
    • Script functions         — LocalScripts & ModuleScripts only; Properties
                                 shows "{Type}Script Function" plus a
                                 "Customize {Type}Script Function" editor
    • Save & Load              — stores projects as files inside the
                                 "GUI_CREATOR_SAVES" folder; any file in that
                                 folder loads regardless of its extension
    • Viewport manipulation    — click to select, drag to move, 8-handle resize
    • ScreenGui protection     — the last remaining ScreenGui can't be deleted
    • Luau Exporter            — serializes the whole project into a clean,
                                 standalone, re-runnable Luau script
    • "Put on CoreGui" toggle  — toolbar switch, GREEN when active / RED when
                                 off; moves project ScreenGuis between PlayerGui
                                 and the protected container (gethui/CoreGui);
                                 exports follow the active mode
    • AI assistant (Gemini)    — "AI" toolbar button opens a chat copilot that
                                 reads the live UI tree and can modify it two
                                 ways: (1) BUILT-IN TOOLS — Gemini function
                                 calling runs real Luau tools inside the editor
                                 (list_ui, find_instance, create_element,
                                 set_properties, rename/delete/duplicate,
                                 script source read/write, save/load/list,
                                 notify); results flow back to the model
                                 automatically. (2) Luau code blocks — every
                                 block gets a Copy button (setclipboard /
                                 toclipboard) and an Apply button (loadstring
                                 + a small `sgc` helper API). Settings expose
                                 API Key, Model, Instructions Prompt, Thinking
                                 level, Temperature, UI-context toggle and an
                                 "Allow AI to run code" gate for the optional
                                 run_lua tool. Models are fetched LIVE with
                                 your key — nothing is hardcoded; if they can't
                                 be fetched, the list stays empty. Settings
                                 persist in GUI_CREATOR_AI.json.
    • Robust input handling    — inset calibration, touch support, pcall guards

    ENVIRONMENT
    Executor LocalScript (Delta, Synapse, Wave, Script-Ware, ...).
    Editor UI is parented to a protected container (gethui/CoreGui fallback).
    User instances live inside project ScreenGuis under PlayerGui.
============================================================================]]

local function main()

-- //////////////////////////////////////////////////////////////////////////
-- SERVICES & ENVIRONMENT
-- //////////////////////////////////////////////////////////////////////////

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService       = game:GetService("GuiService")
local TweenService     = game:GetService("TweenService")
local RunService       = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
    task.wait()
    LocalPlayer = Players.LocalPlayer
end

local PlayerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
if not PlayerGui then
    PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 10)
end
if not PlayerGui then
    warn("[StudioGUI Creator] PlayerGui could not be located — aborting.")
    return
end

-- Resolve the most protected container available on this executor.
local function resolveProtectedParent()
    local ok, hui = pcall(function()
        if type(gethui) == "function" then
            return gethui()
        end
        return nil
    end)
    if ok and hui then
        return hui
    end
    local okCore, coreGui = pcall(function()
        return game:GetService("CoreGui")
    end)
    if okCore and coreGui then
        return coreGui
    end
    return PlayerGui
end

local ProtectedParent = resolveProtectedParent()
local PROJECT_PARENT = PlayerGui

-- Legacy syn.protect_gui support (optional).
local protectGui
do
    local ok, synEnvironment = pcall(function() return syn end)
    if ok and type(synEnvironment) == "table" and type(synEnvironment.protect_gui) == "function" then
        protectGui = synEnvironment.protect_gui
    end
end

-- Executor capability detection.
local Executor = {
    clipboard = nil,
    writefile = nil,
    http      = nil,
    name = "unknown",
}
do
    Executor.clipboard = (type(setclipboard) == "function" and setclipboard)
        or (type(toclipboard) == "function" and toclipboard)
        or nil
    Executor.writefile = (type(writefile) == "function") and writefile or nil
    -- HTTP capability (used by the Gemini AI assistant) — covers common APIs.
    pcall(function()
        Executor.http = (type(request) == "function") and request
            or (type(http_request) == "function") and http_request
            or (type(syn) == "table" and type(syn.request) == "function") and syn.request
            or (type(http) == "table" and type(http.request) == "function") and http.request
            or nil
    end)
    local ok, id = pcall(function() return identifyexecutor() end)
    if ok and type(id) == "string" and #id > 0 then
        Executor.name = id
    end
end

-- //////////////////////////////////////////////////////////////////////////
-- CONFIG & THEME (dark, Studio-inspired)
-- //////////////////////////////////////////////////////////////////////////

local CONFIG = {
    WindowTitle = "StudioGUI Creator",
    WindowSize  = Vector2.new(820, 520),
}

local THEME = {
    Window       = Color3.fromRGB(24, 24, 28),
    Panel        = Color3.fromRGB(30, 30, 35),
    PanelAlt     = Color3.fromRGB(37, 37, 43),
    Control      = Color3.fromRGB(48, 48, 56),
    ControlHover = Color3.fromRGB(60, 60, 70),
    Stroke       = Color3.fromRGB(58, 58, 66),
    Accent       = Color3.fromRGB(0, 120, 215),
    Selection    = Color3.fromRGB(30, 80, 150),
    Text         = Color3.fromRGB(232, 232, 238),
    TextDim      = Color3.fromRGB(150, 150, 162),
    Danger       = Color3.fromRGB(190, 62, 62),
    Good         = Color3.fromRGB(58, 150, 88),
    Warn         = Color3.fromRGB(200, 150, 50),
    Handle       = Color3.fromRGB(255, 255, 255),
    HandleStroke = Color3.fromRGB(40, 40, 45),
}

-- //////////////////////////////////////////////////////////////////////////
-- UTILITIES
-- //////////////////////////////////////////////////////////////////////////

local function create(class, props, parent)
    local inst = Instance.new(class)
    if props then
        for key, value in pairs(props) do
            pcall(function() inst[key] = value end)
        end
    end
    if parent then
        pcall(function() inst.Parent = parent end)
    end
    return inst
end

local function trimNum(n)
    local num = tonumber(n)
    if not num or num ~= num then
        return "0"
    end
    if num == math.floor(num) and math.abs(num) < 1e15 then
        return string.format("%d", num)
    end
    return tostring(num)
end

-- Cached fresh-instance probes (used for default comparisons and to check
-- whether a class can actually be created on this executor).
local defaultInstances = {}
local function defaultInstanceOf(className)
    local cached = defaultInstances[className]
    if cached == nil then
        local ok, inst = pcall(function() return Instance.new(className) end)
        cached = ok and inst or false
        defaultInstances[className] = cached
    end
    return cached or nil
end

-- //////////////////////////////////////////////////////////////////////////
-- CORE STATE
-- //////////////////////////////////////////////////////////////////////////

local Connections = {}
local function trackConnection(connection)
    table.insert(Connections, connection)
    return connection
end

-- Forward declarations (resolved later in boot order).
local Editor      = {}
local PropPanel
local invalidateExplorer
local updateStatus
local explorerScroll
local syncSelectionVisuals
local refreshExplorerSelection

local State = {
    selected      = nil,
    editMode      = true,
    dragging      = nil,
    resizing      = nil,
    windowDrag    = nil,
    collapsed     = setmetatable({}, { __mode = "k" }),
    toolboxCollapsed = {},
    nameCounters  = {},
    spawnCascade  = 0,
    coreGuiMode   = false,
}

-- //////////////////////////////////////////////////////////////////////////
-- PROJECT REGISTRY (tracked ScreenGuis)
-- //////////////////////////////////////////////////////////////////////////

local PROJECT_ATTRIBUTE = "SGC_Project"

-- All children are part of the project tree now (scripts, values, folders...).
local function treeChildren(inst)
    local out = {}
    for _, child in ipairs(inst:GetChildren()) do
        table.insert(out, child)
    end
    return out
end

local function isProjectScreenGui(inst)
    if typeof(inst) ~= "Instance" then return false end
    if not inst:IsA("ScreenGui") then return false end
    if not inst.Parent then return false end
    return inst:GetAttribute(PROJECT_ATTRIBUTE) == true
end

local function getProjectScreenGuis()
    local found = {}
    for _, child in ipairs(PROJECT_PARENT:GetChildren()) do
        if isProjectScreenGui(child) then
            table.insert(found, child)
        end
    end
    table.sort(found, function(a, b) return a.Name < b.Name end)
    return found
end

local function uniqueName(base)
    State.nameCounters[base] = (State.nameCounters[base] or 0) + 1
    local count = State.nameCounters[base]
    if count == 1 then
        return base
    end
    return base .. tostring(count)
end

local function createProjectScreenGui(customName)
    local sg = create("ScreenGui", {
        Name           = customName or uniqueName("ScreenGui"),
        ResetOnSpawn   = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder   = 50,
    })
    sg:SetAttribute(PROJECT_ATTRIBUTE, true)
    sg.Parent = PROJECT_PARENT
    return sg
end

-- ScreenGui protection rule: the project must always keep at least one.
local function ensureProjectIntegrity()
    if #getProjectScreenGuis() == 0 then
        createProjectScreenGui()
    end
end

-- //////////////////////////////////////////////////////////////////////////
-- COORDINATE CALIBRATION & MOUSE HELPERS
-- AbsolutePosition vs GetMouseLocation inset behavior varies between
-- clients/executors — this calibrates it once at runtime.
-- //////////////////////////////////////////////////////////////////////////

local InsetCompensated = false
do
    local probeGui = create("ScreenGui", {
        Name = "SGC_Calibration",
        DisplayOrder = -1000000,
        ResetOnSpawn = false,
    })
    local probe = create("Frame", {
        Size = UDim2.fromOffset(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
    }, probeGui)
    local ok = pcall(function() probeGui.Parent = PROJECT_PARENT end)
    if ok then
        task.wait() -- allow one layout pass
        pcall(function()
            -- Model A (standard): a (0,0) child inside a standard ScreenGui
            -- reports the GUI inset as its Y. If it reports 0, this client
            -- needs manual inset compensation for hit-testing.
            InsetCompensated = (probe.AbsolutePosition.Y < 1)
        end)
    end
    pcall(function() probeGui:Destroy() end)
end

local function getGuiInset()
    local ok, inset = pcall(GuiService.GetGuiInset, GuiService)
    if ok and typeof(inset) == "Vector2" then
        return inset
    end
    return Vector2.zero
end

-- Converts a GuiBase2d AbsolutePosition into physical screen space
-- (the same space used by GetMouseLocation / InputObject.Position).
local function absToScreen(ownerScreenGui, absolutePosition)
    if not InsetCompensated then
        return absolutePosition
    end
    local ignoring = false
    if ownerScreenGui then
        pcall(function() ignoring = ownerScreenGui.IgnoreGuiInset end)
    end
    if ignoring then
        return absolutePosition
    end
    return absolutePosition + getGuiInset()
end

local lastMousePos = Vector2.zero
local function inputScreenPos(inputObject)
    if inputObject then
        local ok, pos = pcall(function() return inputObject.Position end)
        if ok and typeof(pos) == "Vector2" then
            lastMousePos = pos
            return pos
        end
    end
    local ok, pos = pcall(function() return UserInputService:GetMouseLocation() end)
    if ok and typeof(pos) == "Vector2" then
        lastMousePos = pos
        return pos
    end
    return lastMousePos
end

-- //////////////////////////////////////////////////////////////////////////
-- PROTECTED OVERLAY + NOTIFICATIONS
-- //////////////////////////////////////////////////////////////////////////

local Overlay = create("ScreenGui", {
    Name           = "SGC_Editor",
    IgnoreGuiInset = true,
    ResetOnSpawn   = false,
    DisplayOrder   = 1000000,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
if protectGui then
    pcall(protectGui, Overlay)
end
Overlay.Parent = ProtectedParent

local Notifications
do
    local holder = create("Frame", {
        Name = "Notifications",
        BackgroundTransparency = 1,
        Position = UDim2.new(0.5, -160, 0, 10),
        Size = UDim2.fromOffset(320, 0),
        ZIndex = 100,
    }, Overlay)
    create("UIListLayout", {
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
    }, holder)

    local styleForKind = {
        info    = THEME.Accent,
        success = THEME.Good,
        warn    = THEME.Warn,
        error   = THEME.Danger,
    }
    local toastSequence = 0

    Notifications = {}
    function Notifications.show(text, kind, duration)
        local barColor = styleForKind[kind] or styleForKind.info
        toastSequence += 1
        local toast = create("Frame", {
            Size = UDim2.new(1, 0, 0, 34),
            BackgroundColor3 = THEME.PanelAlt,
            BorderSizePixel = 0,
            ZIndex = 100,
            LayoutOrder = toastSequence,
        }, holder)
        create("UICorner", { CornerRadius = UDim.new(0, 6) }, toast)
        create("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, toast)
        create("Frame", {
            Size = UDim2.new(0, 3, 1, -8),
            Position = UDim2.fromOffset(6, 4),
            BackgroundColor3 = barColor,
            BorderSizePixel = 0,
            ZIndex = 101,
        }, toast)
        create("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(16, 0),
            Size = UDim2.new(1, -24, 1, 0),
            Text = tostring(text),
            TextColor3 = THEME.Text,
            Font = Enum.Font.GothamMedium,
            TextSize = 13,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            ZIndex = 101,
        }, toast)

        task.delay(duration or 3, function()
            if not toast.Parent then return end
            pcall(function()
                TweenService:Create(toast, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
                for _, d in ipairs(toast:GetDescendants()) do
                    if d:IsA("TextLabel") then
                        TweenService:Create(d, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
                    elseif d:IsA("Frame") then
                        TweenService:Create(d, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
                    elseif d:IsA("UIStroke") then
                        TweenService:Create(d, TweenInfo.new(0.3), { Transparency = 1 }):Play()
                    end
                end
            end)
            task.delay(0.32, function()
                pcall(function() toast:Destroy() end)
            end)
        end)

        local kids = {}
        for _, c in ipairs(holder:GetChildren()) do
            if c:IsA("Frame") then
                table.insert(kids, c)
            end
        end
        while #kids > 5 do
            local oldest = table.remove(kids, 1)
            pcall(function() oldest:Destroy() end)
        end
    end
end

local notify = Notifications.show

-- //////////////////////////////////////////////////////////////////////////
-- SELECTION VISUALS (outline, 8 resize handles, name tag)
-- //////////////////////////////////////////////////////////////////////////

local Visuals = {}

local HANDLE_LAYOUT = {
    { dir = "TL", ax = 0,   ay = 0   },
    { dir = "T",  ax = 0.5, ay = 0   },
    { dir = "TR", ax = 1,   ay = 0   },
    { dir = "L",  ax = 0,   ay = 0.5 },
    { dir = "R",  ax = 1,   ay = 0.5 },
    { dir = "BL", ax = 0,   ay = 1   },
    { dir = "B",  ax = 0.5, ay = 1   },
    { dir = "BR", ax = 1,   ay = 1   },
}

do
    local container = create("Frame", {
        Name = "SelectionVisuals",
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Active = false,
        ZIndex = 5,
    }, Overlay)

    local outline = create("Frame", {
        Name = "Outline",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Active = false,
        Visible = false,
        ZIndex = 5,
    }, container)
    create("UIStroke", {
        Color = THEME.Accent,
        Thickness = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, outline)

    local handles = {}
    for _, mapping in ipairs(HANDLE_LAYOUT) do
        local handle = create("Frame", {
            Name = "Handle_" .. mapping.dir,
            Size = UDim2.fromOffset(8, 8),
            AnchorPoint = Vector2.new(mapping.ax, mapping.ay),
            BackgroundColor3 = THEME.Handle,
            BorderSizePixel = 0,
            Visible = false,
            Active = true,
            ZIndex = 8,
        }, container)
        create("UICorner", { CornerRadius = UDim.new(0, 2) }, handle)
        create("UIStroke", { Color = THEME.HandleStroke, Thickness = 1 }, handle)
        handles[mapping.dir] = handle
        handle.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                Editor.beginResize(mapping.dir, input)
            end
        end)
    end

    local nameTag = create("TextLabel", {
        Name = "NameTag",
        Size = UDim2.fromOffset(0, 18),
        BackgroundColor3 = THEME.PanelAlt,
        BorderSizePixel = 0,
        Visible = false,
        Text = "",
        TextColor3 = THEME.Text,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        ZIndex = 9,
        AutomaticSize = Enum.AutomaticSize.X,
    }, container)
    create("UICorner", { CornerRadius = UDim.new(0, 4) }, nameTag)
    create("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, nameTag)
    create("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, nameTag)

    Visuals = {
        container = container,
        outline = outline,
        handles = handles,
        nameTag = nameTag,
    }
end

local function ownerScreenGuiOf(inst)
    if inst:IsA("ScreenGui") then
        return inst
    end
    return inst:FindFirstAncestorOfClass("ScreenGui")
end

syncSelectionVisuals = function()
    local sel = State.selected
    local show = sel ~= nil and sel.Parent ~= nil and State.editMode
    Visuals.container.Visible = show
    if not show then
        return
    end

    pcall(function()
        -- Non-geometric instances (Scripts, UI components, Values...) outline
        -- their parent instead.
        local boundsTarget = sel:IsA("GuiObject") and sel or sel.Parent
        if not boundsTarget then
            Visuals.container.Visible = false
            return
        end
        local sg = ownerScreenGuiOf(boundsTarget)
        local origin = absToScreen(sg, boundsTarget.AbsolutePosition)
        local size = boundsTarget.AbsoluteSize

        Visuals.outline.Visible = true
        Visuals.outline.Position = UDim2.fromOffset(origin.X, origin.Y)
        Visuals.outline.Size = UDim2.fromOffset(size.X, size.Y)

        local canManipulate = sel:IsA("GuiObject")
        for _, mapping in ipairs(HANDLE_LAYOUT) do
            local handle = Visuals.handles[mapping.dir]
            handle.Visible = canManipulate
            if canManipulate then
                local px = origin.X + size.X * mapping.ax
                local py = origin.Y + size.Y * mapping.ay
                handle.Position = UDim2.fromOffset(px, py)
            end
        end

        Visuals.nameTag.Visible = true
        Visuals.nameTag.Text = sel.ClassName .. "  ·  " .. sel.Name
        local tagY = origin.Y - 24
        if tagY < 2 then
            tagY = origin.Y + size.Y + 6
        end
        Visuals.nameTag.Position = UDim2.fromOffset(origin.X, tagY)
    end)
end

local function isOverHandle(screenPos)
    local sel = State.selected
    if not sel or not sel.Parent or not sel:IsA("GuiObject") or not State.editMode then
        return false
    end
    for _, handle in pairs(Visuals.handles) do
        if handle.Visible then
            local ok, ap, as = pcall(function()
                return handle.AbsolutePosition, handle.AbsoluteSize
            end)
            if ok and ap and as
                and screenPos.X >= ap.X - 3 and screenPos.X <= ap.X + as.X + 3
                and screenPos.Y >= ap.Y - 3 and screenPos.Y <= ap.Y + as.Y + 3 then
                return true
            end
        end
    end
    return false
end

-- //////////////////////////////////////////////////////////////////////////
-- MAIN WINDOW (title bar, toolbar, toolbox | explorer/properties, status)
-- //////////////////////////////////////////////////////////////////////////

local UI = { windows = {} }

do
    local main = create("Frame", {
        Name = "MainWindow",
        Size = UDim2.fromOffset(CONFIG.WindowSize.X, CONFIG.WindowSize.Y),
        Position = UDim2.fromOffset(60, 110),
        BackgroundColor3 = THEME.Window,
        BorderSizePixel = 0,
        Active = true,
        ZIndex = 10,
    }, Overlay)
    create("UICorner", { CornerRadius = UDim.new(0, 8) }, main)
    create("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, main)

    -- Center the window on first open.
    do
        local ok, viewport = pcall(function()
            return workspace.CurrentCamera.ViewportSize
        end)
        if ok and viewport then
            local x = math.clamp((viewport.X - CONFIG.WindowSize.X) / 2, 8, math.max(8, viewport.X - CONFIG.WindowSize.X - 8))
            local y = math.clamp((viewport.Y - CONFIG.WindowSize.Y) / 2, 8, math.max(8, viewport.Y - CONFIG.WindowSize.Y - 8))
            main.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
        end
    end

    -- Title bar ------------------------------------------------------------
    local titleBar = create("Frame", {
        Name = "TitleBar",
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundColor3 = THEME.PanelAlt,
        BorderSizePixel = 0,
        Active = true,
        ZIndex = 11,
    }, main)
    create("UICorner", { CornerRadius = UDim.new(0, 8) }, titleBar)

    local titleIcon = create("Frame", {
        Size = UDim2.fromOffset(10, 10),
        Position = UDim2.fromOffset(12, 11),
        BackgroundColor3 = THEME.Accent,
        BorderSizePixel = 0,
        ZIndex = 12,
    }, titleBar)
    create("UICorner", { CornerRadius = UDim.new(0, 3) }, titleIcon)

    create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(30, 0),
        Size = UDim2.new(1, -120, 1, 0),
        Text = CONFIG.WindowTitle .. "  —  " .. Executor.name,
        TextColor3 = THEME.Text,
        Font = Enum.Font.GothamMedium,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 12,
    }, titleBar)

    local function windowButton(text, offsetX, onClick, textColor)
        local btn = create("TextButton", {
            Size = UDim2.fromOffset(26, 20),
            Position = UDim2.new(1, offsetX, 0.5, -10),
            BackgroundColor3 = THEME.Control,
            BorderSizePixel = 0,
            Text = text,
            TextColor3 = textColor or THEME.TextDim,
            Font = Enum.Font.GothamBold,
            TextSize = 12,
            AutoButtonColor = false,
            ZIndex = 12,
        }, titleBar)
        create("UICorner", { CornerRadius = UDim.new(0, 4) }, btn)
        btn.MouseEnter:Connect(function() btn.BackgroundColor3 = THEME.ControlHover end)
        btn.MouseLeave:Connect(function() btn.BackgroundColor3 = THEME.Control end)
        btn.Activated:Connect(onClick)
        return btn
    end

    local bodyAndStatus = {}
    local minimized = false
    windowButton("–", -64, function()
        minimized = not minimized
        for _, frame in ipairs(bodyAndStatus) do
            frame.Visible = not minimized
        end
        main.Size = minimized
            and UDim2.fromOffset(CONFIG.WindowSize.X, 32)
            or UDim2.fromOffset(CONFIG.WindowSize.X, CONFIG.WindowSize.Y)
    end, THEME.Text)
    windowButton("×", -34, function() Editor.destroy() end, THEME.Text)

    -- Window dragging (handled centrally in the input section).
    titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            State.windowDrag = {
                startMouse = inputScreenPos(input),
                startPosition = main.Position,
            }
        end
    end)

    -- Toolbar ---------------------------------------------------------------
    local body = create("Frame", {
        Name = "Body",
        Position = UDim2.fromOffset(0, 32),
        Size = UDim2.new(1, 0, 1, -56),
        BackgroundTransparency = 1,
        ZIndex = 11,
    }, main)
    table.insert(bodyAndStatus, body)

    local toolbar = create("Frame", {
        Name = "Toolbar",
        Size = UDim2.new(1, 0, 0, 36),
        BackgroundColor3 = THEME.Panel,
        BorderSizePixel = 0,
        ZIndex = 11,
    }, body)
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
        VerticalAlignment = Enum.VerticalAlignment.Center,
    }, toolbar)
    create("UIPadding", { PaddingLeft = UDim.new(0, 8) }, toolbar)

    local function makeToolbarButton(text, onClick, options)
        options = options or {}
        local btn = create("TextButton", {
            Size = UDim2.fromOffset(options.width or 80, 24),
            BackgroundColor3 = options.accent and THEME.Accent or THEME.Control,
            BorderSizePixel = 0,
            Text = text,
            TextColor3 = THEME.Text,
            Font = Enum.Font.GothamMedium,
            TextSize = 12,
            AutoButtonColor = false,
            ZIndex = 12,
            LayoutOrder = options.order or 0,
        }, toolbar)
        create("UICorner", { CornerRadius = UDim.new(0, 5) }, btn)
        if not options.accent then
            create("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, btn)
        end
        btn.MouseEnter:Connect(function()
            btn.BackgroundColor3 = options.accent and THEME.Accent or THEME.ControlHover
        end)
        btn.MouseLeave:Connect(function()
            btn.BackgroundColor3 = options.accent and THEME.Accent or THEME.Control
        end)
        btn.Activated:Connect(onClick)
        return btn
    end

    UI.makeToolbarButton = makeToolbarButton
    UI.toolbar = toolbar

    -- Columns: Toolbox (left) | Explorer stacked above Properties ----------
    local columns = create("Frame", {
        Position = UDim2.fromOffset(0, 36),
        Size = UDim2.new(1, 0, 1, -36),
        BackgroundTransparency = 1,
        ZIndex = 11,
    }, body)

    local toolboxColumn = create("Frame", {
        Position = UDim2.fromOffset(6, 0),
        Size = UDim2.new(0, 150, 1, -6),
        BackgroundColor3 = THEME.Panel,
        BorderSizePixel = 0,
        ZIndex = 11,
    }, columns)
    create("UICorner", { CornerRadius = UDim.new(0, 6) }, toolboxColumn)
    create("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, toolboxColumn)

    local mainColumn = create("Frame", {
        Position = UDim2.fromOffset(162, 0),
        Size = UDim2.new(1, -168, 1, -6),
        BackgroundTransparency = 1,
        ZIndex = 11,
    }, columns)

    local explorerColumn = create("Frame", {
        Size = UDim2.new(1, 0, 0.40, -4),
        BackgroundColor3 = THEME.Panel,
        BorderSizePixel = 0,
        ZIndex = 11,
    }, mainColumn)
    create("UICorner", { CornerRadius = UDim.new(0, 6) }, explorerColumn)
    create("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, explorerColumn)

    local propertiesColumn = create("Frame", {
        Position = UDim2.new(0, 0, 0.40, 6),
        Size = UDim2.new(1, 0, 0.60, -6),
        BackgroundColor3 = THEME.Panel,
        BorderSizePixel = 0,
        ZIndex = 11,
    }, mainColumn)
    create("UICorner", { CornerRadius = UDim.new(0, 6) }, propertiesColumn)
    create("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, propertiesColumn)

    local function makeColumnHeader(parent, title)
        create("TextLabel", {
            Size = UDim2.new(1, 0, 0, 24),
            BackgroundColor3 = THEME.PanelAlt,
            BorderSizePixel = 0,
            Text = title,
            TextColor3 = THEME.TextDim,
            Font = Enum.Font.GothamBold,
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 12,
        }, parent)
    end

    local function makeScrollList(parent, topOffset)
        local scroll = create("ScrollingFrame", {
            Position = UDim2.fromOffset(0, topOffset or 24),
            Size = UDim2.new(1, 0, 1, -(topOffset or 24)),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            ScrollBarThickness = 4,
            ScrollBarImageColor3 = THEME.ControlHover,
            ElasticBehavior = Enum.ElasticBehavior.Never,
            ZIndex = 12,
        }, parent)
        create("UIListLayout", {
            Padding = UDim.new(0, 2),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, scroll)
        create("UIPadding", {
            PaddingTop = UDim.new(0, 4),
            PaddingBottom = UDim.new(0, 6),
            PaddingLeft = UDim.new(0, 4),
            PaddingRight = UDim.new(0, 6),
        }, scroll)
        return scroll
    end

    -- Status bar ------------------------------------------------------------
    local statusBar = create("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 0, 1, 0),
        Size = UDim2.new(1, 0, 0, 24),
        BackgroundColor3 = THEME.PanelAlt,
        BorderSizePixel = 0,
        ZIndex = 11,
    }, main)
    table.insert(bodyAndStatus, statusBar)

    local statusLeft = create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(8, 0),
        Size = UDim2.new(0.62, 0, 1, 0),
        Text = "",
        TextColor3 = THEME.TextDim,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 12,
    }, statusBar)

    local statusRight = create("TextLabel", {
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -8, 0, 0),
        Size = UDim2.new(0.36, 0, 1, 0),
        Text = "No selection",
        TextColor3 = THEME.Text,
        Font = Enum.Font.GothamMedium,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Right,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 12,
    }, statusBar)

    UI.main = main
    UI.windows = { main }
    UI.statusLeft = statusLeft
    UI.statusRight = statusRight
    UI.toolboxColumn = toolboxColumn
    UI.explorerColumn = explorerColumn
    UI.propertiesColumn = propertiesColumn
    UI.makeColumnHeader = makeColumnHeader
    UI.makeScrollList = makeScrollList
end

-- //////////////////////////////////////////////////////////////////////////
-- ENUM DROPDOWN POPUP (friendly enum editing — no typing "Enum.X.Y")
-- //////////////////////////////////////////////////////////////////////////

local Dropdown = {}
do
    local catcher = create("TextButton", {
        Name = "DropdownCatcher",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        Visible = false,
        ZIndex = 70,
    }, Overlay)
    local listFrame = create("ScrollingFrame", {
        Name = "DropdownList",
        BackgroundColor3 = THEME.PanelAlt,
        BorderSizePixel = 0,
        Visible = false,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = THEME.ControlHover,
        ElasticBehavior = Enum.ElasticBehavior.Never,
        ZIndex = 71,
    }, Overlay)
    create("UICorner", { CornerRadius = UDim.new(0, 6) }, listFrame)
    create("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, listFrame)
    create("UIListLayout", {
        Padding = UDim.new(0, 2),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, listFrame)
    create("UIPadding", {
        PaddingTop = UDim.new(0, 4),
        PaddingBottom = UDim.new(0, 4),
        PaddingLeft = UDim.new(0, 4),
        PaddingRight = UDim.new(0, 4),
    }, listFrame)

    local function close()
        catcher.Visible = false
        listFrame.Visible = false
        for _, child in ipairs(listFrame:GetChildren()) do
            if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
                child:Destroy()
            end
        end
    end

    catcher.Activated:Connect(close)

    -- anchorPos/anchorSize are in Overlay space (Overlay ignores the GUI inset).
    function Dropdown.open(enumType, currentValue, anchorPos, anchorSize, onSelect)
        close()
        local okItems, items = pcall(function()
            return Enum[enumType]:GetEnumItems()
        end)
        if not okItems or typeof(items) ~= "table" or #items == 0 then
            notify("No enum options found for " .. tostring(enumType), "error", 2.5)
            return
        end

        local width = math.max((anchorSize and anchorSize.X) or 160, 160)
        local rowHeight = 22
        local listHeight = math.min(#items * (rowHeight + 2) + 10, 240)

        local px = anchorPos.X
        local py = anchorPos.Y + (anchorSize and anchorSize.Y or 20) + 4
        pcall(function()
            local viewport = workspace.CurrentCamera.ViewportSize
            if px + width > viewport.X - 8 then
                px = viewport.X - 8 - width
            end
            if px < 8 then px = 8 end
            if py + listHeight > viewport.Y - 8 then
                py = anchorPos.Y - listHeight - 4
            end
            if py < 8 then py = 8 end
        end)

        listFrame.Position = UDim2.fromOffset(math.floor(px), math.floor(py))
        listFrame.Size = UDim2.fromOffset(width, listHeight)

        for order, item in ipairs(items) do
            local isCurrent = (item == currentValue)
            local rowBtn = create("TextButton", {
                Size = UDim2.new(1, 0, 0, rowHeight),
                BackgroundColor3 = isCurrent and THEME.Selection or THEME.Control,
                BackgroundTransparency = isCurrent and 0 or 1,
                BorderSizePixel = 0,
                AutoButtonColor = false,
                Text = item.Name,
                TextColor3 = isCurrent and THEME.Text or Color3.fromRGB(205, 205, 214),
                Font = Enum.Font.Gotham,
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Left,
                LayoutOrder = order,
                ZIndex = 72,
            }, listFrame)
            create("UIPadding", { PaddingLeft = UDim.new(0, 8) }, rowBtn)
            rowBtn.MouseEnter:Connect(function()
                rowBtn.BackgroundColor3 = THEME.ControlHover
                rowBtn.BackgroundTransparency = 0
            end)
            rowBtn.MouseLeave:Connect(function()
                if item == currentValue then
                    rowBtn.BackgroundColor3 = THEME.Selection
                    rowBtn.BackgroundTransparency = 0
                else
                    rowBtn.BackgroundColor3 = THEME.Control
                    rowBtn.BackgroundTransparency = 1
                end
            end)
            rowBtn.Activated:Connect(function()
                close()
                onSelect(item)
            end)
        end

        catcher.Visible = true
        listFrame.Visible = true
    end

    Dropdown.close = close
end

-- //////////////////////////////////////////////////////////////////////////
-- PROPERTY SCHEMA (single source of truth for Properties panel + Exporter)
-- //////////////////////////////////////////////////////////////////////////

local PROP_GROUPS = {
    base      = { "Position", "Size", "AnchorPoint", "Rotation", "BackgroundColor3", "BackgroundTransparency", "BorderColor3", "BorderSizePixel", "Visible", "ZIndex", "LayoutOrder", "ClipsDescendants", "Active" },
    text      = { "Text", "TextColor3", "TextSize", "TextScaled", "Font", "TextTransparency", "TextStrokeColor3", "TextStrokeTransparency", "TextWrapped", "TextTruncate", "RichText", "LineHeight", "TextXAlignment", "TextYAlignment" },
    button    = { "AutoButtonColor" },
    textbox   = { "PlaceholderText", "PlaceholderColor3", "ClearTextOnFocus", "MultiLine", "TextEditable", "TextWrapped" },
    image     = { "Image", "ImageColor3", "ImageTransparency", "ScaleType", "ImageRectOffset", "ImageRectSize", "TileSize" },
    video     = { "Playing", "Looped", "Muted", "Volume", "Video" },
    scroll    = { "CanvasSize", "CanvasPosition", "ScrollingEnabled", "ScrollingDirection", "ScrollBarThickness", "ScrollBarImageColor3", "ScrollBarImageTransparency", "VerticalScrollBarInset", "HorizontalScrollBarInset" },
    viewport  = { "Ambient", "LightColor", "LightDirection" },
    corner    = { "CornerRadius" },
    stroke    = { "Color", "Thickness", "Transparency", "ApplyStrokeMode" },
    gradient  = { "Color", "Rotation", "Offset" },
    list      = { "FillDirection", "Padding", "SortOrder", "HorizontalAlignment", "VerticalAlignment" },
    grid      = { "FillDirection", "CellSize", "CellPadding", "SortOrder", "HorizontalAlignment", "VerticalAlignment" },
    table     = { "FillDirection", "Padding", "SortOrder", "HorizontalAlignment", "VerticalAlignment", "FillEmptySpaceRows", "FillEmptySpaceColumns", "MajorAxis" },
    page      = { "FillDirection", "Padding", "SortOrder", "Animated", "Circular", "EasingStyle", "EasingDirection", "TweenTime", "TouchInputEnabled", "ScrollWheelInputEnabled", "GamepadInputEnabled" },
    padding   = { "PaddingTop", "PaddingLeft", "PaddingRight", "PaddingBottom" },
    scale     = { "Scale" },
    sizeconstraint   = { "MinSize", "MaxSize" },
    textsize  = { "MaxTextSize" },
    aspectratio = { "AspectRatio", "AspectType", "DominantAxis", "DominantDirection" },
    canvas    = { "GroupTransparency", "GroupColor3" },
    screengui = { "Enabled", "DisplayOrder", "IgnoreGuiInset", "ResetOnSpawn", "ZIndexBehavior", "ScreenInsets" },
    script    = { "Source", "Disabled" },
    value     = { "Value" },
    sound     = { "SoundId", "Volume", "PlaybackSpeed", "Looped", "Playing", "TimePosition" },
}

local CLASS_GROUPS = {
    ScreenGui      = { "screengui" },
    Frame          = { "base" },
    CanvasGroup    = { "base", "canvas" },
    ScrollingFrame = { "base", "scroll" },
    ViewportFrame  = { "base", "viewport" },
    TextLabel      = { "base", "text" },
    TextButton     = { "base", "text", "button" },
    TextBox        = { "base", "text", "textbox" },
    ImageLabel     = { "base", "image" },
    ImageButton    = { "base", "image", "button" },
    VideoFrame     = { "base", "video" },
    UICorner       = { "corner" },
    UIStroke       = { "stroke" },
    UIGradient     = { "gradient" },
    UIListLayout   = { "list" },
    UIGridLayout   = { "grid" },
    UITableLayout  = { "table" },
    UIPageLayout   = { "page" },
    UIPadding      = { "padding" },
    UIScale        = { "scale" },
    UISizeConstraint        = { "sizeconstraint" },
    UITextSizeConstraint    = { "textsize" },
    UIAspectRatioConstraint = { "aspectratio" },
    LocalScript    = { "script" },
    ModuleScript   = { "script" },
    Folder         = {},
    Sound          = { "sound" },
    IntValue       = { "value" },
    NumberValue    = { "value" },
    StringValue    = { "value" },
    BoolValue      = { "value" },
    ObjectValue    = { "value" },
    Color3Value    = { "value" },
    Vector3Value   = { "value" },
    CFrameValue    = { "value" },
    BrickColorValue = { "value" },
    RayValue       = { "value" },
}

local PROP_TYPES = {
    Name = "string",
    Position = "udim2", Size = "udim2", AnchorPoint = "vector2", Rotation = "number",
    BackgroundColor3 = "color", BackgroundTransparency = "number", BorderColor3 = "color",
    BorderSizePixel = "number", LayoutOrder = "number", Active = "bool",
    Visible = "bool", ZIndex = "number", ClipsDescendants = "bool",
    Text = "string", TextColor3 = "color", TextSize = "number", TextScaled = "bool",
    Font = "enum:Font", TextTransparency = "number", TextStrokeColor3 = "color",
    TextStrokeTransparency = "number", TextWrapped = "bool", TextTruncate = "enum:TextTruncate",
    RichText = "bool", LineHeight = "number",
    TextXAlignment = "enum:TextXAlignment", TextYAlignment = "enum:TextYAlignment",
    AutoButtonColor = "bool",
    PlaceholderText = "string", PlaceholderColor3 = "color", ClearTextOnFocus = "bool",
    MultiLine = "bool", TextEditable = "bool",
    Image = "asset", ImageColor3 = "color", ImageTransparency = "number",
    ScaleType = "enum:ScaleType", ImageRectOffset = "vector2", ImageRectSize = "vector2", TileSize = "udim2",
    Playing = "bool", Looped = "bool", Muted = "bool", Video = "asset",
    CanvasSize = "udim2", CanvasPosition = "vector2", ScrollingEnabled = "bool",
    ScrollingDirection = "enum:ScrollingDirection",
    ScrollBarThickness = "number", ScrollBarImageColor3 = "color", ScrollBarImageTransparency = "number",
    VerticalScrollBarInset = "enum:ScrollBarInset", HorizontalScrollBarInset = "enum:ScrollBarInset",
    Ambient = "color", LightColor = "color", LightDirection = "vector3",
    CornerRadius = "udim",
    Color = "color", Thickness = "number", Transparency = "number", ApplyStrokeMode = "enum:ApplyStrokeMode",
    Offset = "vector2",
    FillDirection = "enum:FillDirection", Padding = "udim", SortOrder = "enum:SortOrder",
    HorizontalAlignment = "enum:HorizontalAlignment", VerticalAlignment = "enum:VerticalAlignment",
    CellSize = "udim2", CellPadding = "udim2",
    FillEmptySpaceRows = "bool", FillEmptySpaceColumns = "bool", MajorAxis = "enum:TableMajorAxis",
    Animated = "bool", Circular = "bool", EasingStyle = "enum:PageLayoutEasingStyle",
    EasingDirection = "enum:EasingDirection", TweenTime = "number",
    TouchInputEnabled = "bool", ScrollWheelInputEnabled = "bool", GamepadInputEnabled = "bool",
    PaddingTop = "udim", PaddingLeft = "udim", PaddingRight = "udim", PaddingBottom = "udim",
    Scale = "number",
    MinSize = "vector2", MaxSize = "vector2",
    MaxTextSize = "number",
    AspectRatio = "number", AspectType = "enum:AspectType", DominantAxis = "enum:DominantAxis",
    DominantDirection = "enum:DominantDirection",
    GroupTransparency = "number", GroupColor3 = "color",
    Enabled = "bool", DisplayOrder = "number", IgnoreGuiInset = "bool",
    ResetOnSpawn = "bool", ZIndexBehavior = "enum:ZIndexBehavior", ScreenInsets = "enum:ScreenInsets",
    Source = "source", Disabled = "bool",
    SoundId = "asset", Volume = "number", PlaybackSpeed = "number", TimePosition = "number",
}

-- Per-class overrides for ambiguous property names.
local CLASS_PROP_TYPES = {
    StringValue     = { Value = "string" },
    IntValue        = { Value = "number" },
    NumberValue     = { Value = "number" },
    BoolValue       = { Value = "bool" },
    ObjectValue     = { Value = "object" },
    Color3Value     = { Value = "color" },
    Vector3Value    = { Value = "vector3" },
    CFrameValue     = { Value = "object" },
    BrickColorValue = { Value = "object" },
    RayValue        = { Value = "object" },
    UITableLayout   = { Padding = "udim2" },
    UIGradient      = { Color = "colorsequence" },
}

-- Groups probed (existence-checked one by one) for classes that are not in
-- CLASS_GROUPS — this is what makes properties show up for ANY instance.
local FALLBACK_GROUP_KEYS = {
    "base", "text", "button", "textbox", "image", "video", "scroll", "viewport",
    "corner", "stroke", "gradient", "list", "grid", "table", "page", "padding",
    "scale", "sizeconstraint", "textsize", "aspectratio", "canvas", "screengui",
}

-- //////////////////////////////////////////////////////////////////////////
-- PROPERTY PARSING / FORMATTING
-- //////////////////////////////////////////////////////////////////////////

local function parseColorText(text)
    local s = tostring(text)
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    s = s:gsub("^#", ""):gsub("%s", "")
    local r, g, b = s:match("^(%d+),(%d+),(%d+)$")
    if r then
        return Color3.fromRGB(tonumber(r) or 0, tonumber(g) or 0, tonumber(b) or 0)
    end
    if #s == 6 and s:match("^%x+$") then
        local rr = tonumber(s:sub(1, 2), 16)
        local gg = tonumber(s:sub(3, 4), 16)
        local bb = tonumber(s:sub(5, 6), 16)
        if rr and gg and bb then
            return Color3.fromRGB(rr, gg, bb)
        end
    end
    return nil
end

local function parseNumberList(text, count)
    local tokens = {}
    for token in tostring(text):gmatch("[^,%s]+") do
        tokens[#tokens + 1] = token
    end
    if #tokens ~= count then
        return nil
    end
    local nums = {}
    for i, token in ipairs(tokens) do
        local n = tonumber(token)
        if not n then
            return nil
        end
        nums[i] = n
    end
    return nums
end

local function parseAssetText(text)
    local s = tostring(text)
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then
        return ""
    end
    if s:match("^rbxassetid://") or s:match("^rbxasset://") or s:match("^rbxthumb://") then
        return s
    end
    if s:match("^%d+$") then
        return "rbxassetid://" .. s
    end
    return nil
end

local function parseEnumText(enumType, text)
    local name = tostring(text)
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    name = name:gsub("^Enum%.%w+%.?", "") -- accept "Enum.Font.Gotham" too
    if name == "" then
        return nil
    end
    local ok, item = pcall(function()
        return Enum[enumType][name]
    end)
    if ok and item then
        return item
    end
    return nil
end

local function formatValue(ptype, value)
    local ok, result = pcall(function()
        if ptype == "color" then
            return ("%d, %d, %d"):format(
                math.floor(value.R * 255 + 0.5),
                math.floor(value.G * 255 + 0.5),
                math.floor(value.B * 255 + 0.5))
        elseif ptype == "udim2" then
            return ("%s, %s, %s, %s"):format(
                trimNum(value.X.Scale), trimNum(value.X.Offset),
                trimNum(value.Y.Scale), trimNum(value.Y.Offset))
        elseif ptype == "udim" then
            return ("%s, %s"):format(trimNum(value.Scale), trimNum(value.Offset))
        elseif ptype == "vector2" then
            return ("%s, %s"):format(trimNum(value.X), trimNum(value.Y))
        elseif ptype == "vector3" then
            return ("%s, %s, %s"):format(trimNum(value.X), trimNum(value.Y), trimNum(value.Z))
        elseif ptype == "colorsequence" then
            local parts = {}
            for _, keypoint in ipairs(value.Keypoints) do
                table.insert(parts, ("%s, %d, %d, %d"):format(
                    trimNum(keypoint.Time),
                    math.floor(keypoint.Value.R * 255 + 0.5),
                    math.floor(keypoint.Value.G * 255 + 0.5),
                    math.floor(keypoint.Value.B * 255 + 0.5)))
            end
            return table.concat(parts, "; ")
        elseif ptype:sub(1, 5) == "enum:" then
            return value.Name
        elseif ptype == "bool" then
            return value and "true" or "false"
        elseif ptype == "number" then
            return trimNum(value)
        end
        return tostring(value)
    end)
    return ok and result or ""
end

local function parsePropertyValue(ptype, text)
    if ptype == "string" or ptype == "source" then
        return tostring(text)
    elseif ptype == "number" then
        return tonumber(text)
    elseif ptype == "color" then
        return parseColorText(text)
    elseif ptype == "udim2" then
        local nums = parseNumberList(text, 4)
        if not nums then return nil end
        return UDim2.new(nums[1], nums[2], nums[3], nums[4])
    elseif ptype == "udim" then
        local nums = parseNumberList(text, 2)
        if not nums then
            local single = parseNumberList(text, 1)
            if single then
                nums = { 0, single[1] } -- "10" => UDim.new(0, 10)
            end
        end
        if not nums then return nil end
        return UDim.new(nums[1], nums[2])
    elseif ptype == "vector2" then
        local nums = parseNumberList(text, 2)
        if not nums then return nil end
        return Vector2.new(nums[1], nums[2])
    elseif ptype == "vector3" then
        local nums = parseNumberList(text, 3)
        if not nums then return nil end
        return Vector3.new(nums[1], nums[2], nums[3])
    elseif ptype == "colorsequence" then
        -- Format: "0,255,0,0; 0.5,255,255,0; 1,0,0,255"  (offset,R,G,B stops)
        local stops = {}
        for chunk in tostring(text):gmatch("[^;]+") do
            local nums = parseNumberList(chunk, 4)
            if not nums then return nil end
            table.insert(stops, {
                t = math.clamp(nums[1], 0, 1),
                c = Color3.fromRGB(
                    math.clamp(math.floor(nums[2] + 0.5), 0, 255),
                    math.clamp(math.floor(nums[3] + 0.5), 0, 255),
                    math.clamp(math.floor(nums[4] + 0.5), 0, 255)),
            })
        end
        if #stops < 2 then return nil end
        table.sort(stops, function(a, b) return a.t < b.t end)
        stops[1].t = 0
        stops[#stops].t = 1
        local keypoints = {}
        for _, stop in ipairs(stops) do
            table.insert(keypoints, ColorSequenceKeypoint.new(stop.t, stop.c))
        end
        return ColorSequence.new(keypoints)
    elseif ptype == "asset" then
        return parseAssetText(text)
    elseif ptype:sub(1, 5) == "enum:" then
        return parseEnumText(ptype:sub(6), text)
    end
    return nil
end

local function applyProperty(obj, propName, text, ptype)
    local value = parsePropertyValue(ptype, text)
    if value == nil then
        notify(("Invalid value for %s"):format(propName), "error", 2.5)
        return false
    end
    local ok = pcall(function()
        obj[propName] = value
    end)
    if not ok then
        notify(("Failed to set %s"):format(propName), "error", 2.5)
        return false
    end
    return true
end

local function afterPropertyChange(obj, propName)
    if propName == "Name" then
        invalidateExplorer()
        updateStatus()
    end
end

-- //////////////////////////////////////////////////////////////////////////
-- PROPERTIES PANEL
-- //////////////////////////////////////////////////////////////////////////

PropPanel = {}
do
    local scroll
    local placeholder
    local rows = {}
    local rowOrder = 0

    local function clearRows()
        rows = {}
        if scroll then
            for _, child in ipairs(scroll:GetChildren()) do
                if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
                    child:Destroy()
                end
            end
        end
        rowOrder = 0
    end

    local function inferPropType(value)
        local kind = typeof(value)
        if kind == "string" then return "string"
        elseif kind == "number" then return "number"
        elseif kind == "boolean" then return "bool"
        elseif kind == "Color3" then return "color"
        elseif kind == "UDim2" then return "udim2"
        elseif kind == "UDim" then return "udim"
        elseif kind == "Vector2" then return "vector2"
        elseif kind == "Vector3" then return "vector3"
        elseif kind == "ColorSequence" then return "colorsequence"
        elseif kind == "EnumItem" then return "enum:" .. value.EnumType.Name
        end
        return "object" -- read-only display fallback
    end

    -- Structural types: if the real value's kind disagrees with the declared
    -- type we trust the instance (keeps arbitrary classes editable).
    local STRUCTURAL_TYPES = {
        udim2 = "UDim2", udim = "UDim", vector2 = "Vector2", vector3 = "Vector3",
        color = "Color3", colorsequence = "ColorSequence",
        bool = "boolean", number = "number", string = "string",
    }

    local function resolvePropType(obj, propName)
        local classOverride = CLASS_PROP_TYPES[obj.ClassName]
        if classOverride and classOverride[propName] then
            local okOverride = pcall(function() return obj[propName] end)
            if not okOverride then
                return nil -- property doesn't exist on this instance
            end
            return classOverride[propName]
        end
        local ok, value = pcall(function() return obj[propName] end)
        if not ok then
            return nil -- property doesn't exist on this instance -> skip the row
        end
        local declared = PROP_TYPES[propName]
        if declared then
            local expectedKind = STRUCTURAL_TYPES[declared]
            if expectedKind and typeof(value) ~= expectedKind then
                return inferPropType(value) -- trust the actual value's type
            end
            if declared:sub(1, 5) == "enum:" and typeof(value) == "EnumItem" then
                local actualEnum = value.EnumType.Name
                if actualEnum ~= declared:sub(6) then
                    return "enum:" .. actualEnum -- self-heal wrong enum declarations
                end
            end
            return declared
        end
        return inferPropType(value)
    end

    local function addSection(title)
        rowOrder += 1
        create("TextLabel", {
            Size = UDim2.new(1, 0, 0, 22),
            BackgroundTransparency = 1,
            Text = string.upper(title),
            TextColor3 = THEME.Accent,
            Font = Enum.Font.GothamBold,
            TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Left,
            LayoutOrder = rowOrder,
            ZIndex = 12,
        }, scroll)
    end

    local function makeValueBox(row)
        local box = create("TextBox", {
            BackgroundColor3 = THEME.Control,
            TextColor3 = THEME.Text,
            PlaceholderColor3 = THEME.TextDim,
            Font = Enum.Font.Gotham,
            TextSize = 12,
            Text = "",
            ClearTextOnFocus = false,
            BorderSizePixel = 0,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 13,
        }, row)
        create("UICorner", { CornerRadius = UDim.new(0, 4) }, box)
        create("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, box)
        create("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 4) }, box)
        return box
    end

    local function addPropRow(obj, propName, ptype)
        rowOrder += 1
        local rowHeight = (ptype == "source") and 96 or 26
        local row = create("Frame", {
            Size = UDim2.new(1, 0, 0, rowHeight),
            BackgroundTransparency = 1,
            LayoutOrder = rowOrder,
            ZIndex = 12,
        }, scroll)

        create("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(2, 0),
            Size = UDim2.new(0, 128, 0, 22),
            Text = propName,
            TextColor3 = THEME.TextDim,
            Font = Enum.Font.Gotham,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            ZIndex = 13,
        }, row)

        if ptype == "bool" then
            local toggle = create("TextButton", {
                Position = UDim2.fromOffset(134, 3),
                Size = UDim2.fromOffset(64, 20),
                BackgroundColor3 = THEME.Control,
                BorderSizePixel = 0,
                TextColor3 = THEME.Text,
                Font = Enum.Font.GothamBold,
                TextSize = 12,
                AutoButtonColor = false,
                Text = "false",
                ZIndex = 13,
            }, row)
            create("UICorner", { CornerRadius = UDim.new(0, 4) }, toggle)
            create("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, toggle)

            local function refresh()
                local ok, value = pcall(function() return obj[propName] end)
                if not ok then return end
                toggle.Text = value and "true" or "false"
                toggle.BackgroundColor3 = value and THEME.Good or THEME.Control
            end
            toggle.Activated:Connect(function()
                local ok, value = pcall(function() return obj[propName] end)
                if ok then
                    local applied = pcall(function() obj[propName] = not value end)
                    if applied then
                        afterPropertyChange(obj, propName)
                    end
                end
                refresh()
            end)
            refresh()
            rows[propName] = refresh

        elseif ptype == "object" then
            -- Read-only reference/complex display (ObjectValue.Value, CFrame, ...)
            local display = create("TextLabel", {
                Position = UDim2.fromOffset(134, 3),
                Size = UDim2.new(1, -140, 0, 20),
                BackgroundColor3 = THEME.PanelAlt,
                TextColor3 = THEME.TextDim,
                Font = Enum.Font.Code,
                TextSize = 12,
                Text = "",
                BorderSizePixel = 0,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                ZIndex = 13,
            }, row)
            create("UICorner", { CornerRadius = UDim.new(0, 4) }, display)
            create("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, display)
            create("UIPadding", { PaddingLeft = UDim.new(0, 6) }, display)

            local function refresh()
                local ok, value = pcall(function() return obj[propName] end)
                if not ok then return end
                if typeof(value) == "Instance" then
                    display.Text = value.Name .. " (" .. value.ClassName .. ")"
                elseif value == nil then
                    display.Text = "nil"
                else
                    display.Text = tostring(value)
                end
            end
            refresh()
            rows[propName] = refresh

        elseif ptype == "source" then
            -- Multiline code editor (LocalScript/Script/ModuleScript Source).
            local box = create("TextBox", {
                Position = UDim2.fromOffset(134, 3),
                Size = UDim2.new(1, -140, 1, -9),
                BackgroundColor3 = THEME.Control,
                TextColor3 = THEME.Text,
                Font = Enum.Font.Code,
                TextSize = 12,
                Text = "",
                MultiLine = true,
                TextWrapped = false,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextYAlignment = Enum.TextYAlignment.Top,
                ClearTextOnFocus = false,
                BorderSizePixel = 0,
                ZIndex = 13,
            }, row)
            create("UICorner", { CornerRadius = UDim.new(0, 4) }, box)
            create("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, box)
            create("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 4) }, box)

            local function refresh()
                if box:IsFocused() then return end
                local ok, value = pcall(function() return obj[propName] end)
                if ok then
                    box.Text = tostring(value)
                end
            end
            box.FocusLost:Connect(function()
                local applied = applyProperty(obj, propName, box.Text, "source")
                if applied then
                    afterPropertyChange(obj, propName)
                end
                refresh()
            end)
            refresh()
            rows[propName] = refresh

        elseif ptype:sub(1, 5) == "enum:" then
            -- Friendly dropdown: every option of the enum, no typing required.
            local dropdownBtn = create("TextButton", {
                Position = UDim2.fromOffset(134, 3),
                Size = UDim2.new(1, -140, 0, 20),
                BackgroundColor3 = THEME.Control,
                BorderSizePixel = 0,
                Text = "",
                TextColor3 = THEME.Text,
                Font = Enum.Font.Gotham,
                TextSize = 12,
                AutoButtonColor = false,
                TextXAlignment = Enum.TextXAlignment.Left,
                ZIndex = 13,
            }, row)
            create("UICorner", { CornerRadius = UDim.new(0, 4) }, dropdownBtn)
            create("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, dropdownBtn)
            create("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, dropdownBtn)

            local function refresh()
                local ok, value = pcall(function() return obj[propName] end)
                if not ok or typeof(value) ~= "EnumItem" then return end
                dropdownBtn.Text = value.Name
            end

            dropdownBtn.Activated:Connect(function()
                local ok, value = pcall(function() return obj[propName] end)
                if not ok or typeof(value) ~= "EnumItem" then return end
                Dropdown.open(value.EnumType.Name, value, dropdownBtn.AbsolutePosition, dropdownBtn.AbsoluteSize, function(item)
                    local applied = pcall(function() obj[propName] = item end)
                    if applied then
                        afterPropertyChange(obj, propName)
                    else
                        notify(("Failed to set %s"):format(propName), "error", 2.5)
                    end
                    refresh()
                end)
            end)
            refresh()
            rows[propName] = refresh

        else
            local swatch
            if ptype == "color" then
                swatch = create("Frame", {
                    Position = UDim2.fromOffset(134, 4),
                    Size = UDim2.fromOffset(18, 18),
                    BackgroundColor3 = Color3.new(1, 1, 1),
                    BorderSizePixel = 0,
                    ZIndex = 13,
                }, row)
                create("UICorner", { CornerRadius = UDim.new(0, 4) }, swatch)
                create("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, swatch)
            end

            local box = makeValueBox(row)
            if swatch then
                box.Position = UDim2.fromOffset(158, 3)
                box.Size = UDim2.new(1, -164, 0, 20)
            else
                box.Position = UDim2.fromOffset(134, 3)
                box.Size = UDim2.new(1, -140, 0, 20)
            end

            local function refresh()
                if box:IsFocused() then return end
                local ok, value = pcall(function() return obj[propName] end)
                if not ok then return end
                box.Text = formatValue(ptype, value)
                if swatch then
                    pcall(function() swatch.BackgroundColor3 = value end)
                end
            end

            box.FocusLost:Connect(function()
                local applied = applyProperty(obj, propName, box.Text, ptype)
                if applied then
                    afterPropertyChange(obj, propName)
                end
                refresh()
            end)
            refresh()
            rows[propName] = refresh
        end
    end

    local function addFunctionRow(obj)
        rowOrder += 1
        local scriptType = obj:IsA("ModuleScript") and "Module" or "Local"
        local row = create("Frame", {
            Size = UDim2.new(1, 0, 0, 30),
            BackgroundTransparency = 1,
            LayoutOrder = rowOrder,
            ZIndex = 12,
        }, scroll)

        local viewBtn = create("TextButton", {
            Position = UDim2.fromOffset(2, 4),
            Size = UDim2.fromOffset(150, 22),
            BackgroundColor3 = THEME.Control,
            BorderSizePixel = 0,
            Text = scriptType .. "Script Function",
            TextColor3 = THEME.Text,
            Font = Enum.Font.GothamMedium,
            TextSize = 11,
            AutoButtonColor = false,
            TextTruncate = Enum.TextTruncate.AtEnd,
            ZIndex = 13,
        }, row)
        create("UICorner", { CornerRadius = UDim.new(0, 4) }, viewBtn)
        create("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, viewBtn)

        local editBtn = create("TextButton", {
            Position = UDim2.fromOffset(158, 4),
            Size = UDim2.fromOffset(216, 22),
            BackgroundColor3 = THEME.Accent,
            BorderSizePixel = 0,
            Text = "Customize " .. scriptType .. "Script Function",
            TextColor3 = THEME.Text,
            Font = Enum.Font.GothamMedium,
            TextSize = 11,
            AutoButtonColor = false,
            TextTruncate = Enum.TextTruncate.AtEnd,
            ZIndex = 13,
        }, row)
        create("UICorner", { CornerRadius = UDim.new(0, 4) }, editBtn)

        viewBtn.Activated:Connect(function()
            Editor.openFunctionViewer(obj)
        end)
        editBtn.Activated:Connect(function()
            Editor.openFunctionEditor(obj)
        end)
    end

    local GROUP_TITLES = {
        base = "Appearance", text = "Text", button = "Button", textbox = "TextBox",
        image = "Image", video = "VideoFrame", scroll = "Scrolling", viewport = "ViewportFrame",
        corner = "UICorner", stroke = "UIStroke", gradient = "UIGradient",
        list = "UIListLayout", grid = "UIGridLayout", table = "UITableLayout",
        page = "UIPageLayout", padding = "UIPadding",
        scale = "UIScale", sizeconstraint = "UISizeConstraint", textsize = "UITextSizeConstraint",
        aspectratio = "UIAspectRatioConstraint",
        canvas = "CanvasGroup", screengui = "ScreenGui",
        script = "Script", value = "Value", sound = "Sound",
    }

    function PropPanel.build(obj)
        clearRows()
        placeholder.Visible = (obj == nil)
        scroll.Visible = (obj ~= nil)
        if not obj then
            return
        end

        addSection("Data")
        local nameType = resolvePropType(obj, "Name") or "string"
        addPropRow(obj, "Name", nameType)

        local groups = CLASS_GROUPS[obj.ClassName] or FALLBACK_GROUP_KEYS
        for _, groupKey in ipairs(groups) do
            local propList = PROP_GROUPS[groupKey]
            if propList then
                addSection(GROUP_TITLES[groupKey] or groupKey)
                for _, propName in ipairs(propList) do
                    if propName == "Source" and (obj:IsA("LocalScript") or obj:IsA("ModuleScript")) then
                        addFunctionRow(obj) -- "{Type}Script Function" + customize button
                    else
                        local ptype = resolvePropType(obj, propName)
                        if ptype then
                            addPropRow(obj, propName, ptype)
                        end
                    end
                end
            end
        end
    end

    function PropPanel.refresh(propName)
        local refresh = rows[propName]
        if refresh then
            pcall(refresh)
        end
    end

    function PropPanel.init()
        scroll = UI.makeScrollList(UI.propertiesColumn, 24)
        placeholder = create("TextLabel", {
            Size = UDim2.new(1, -16, 1, -30),
            Position = UDim2.fromOffset(8, 24),
            BackgroundTransparency = 1,
            Text = "Select an instance in the viewport or Explorer\nto edit its properties.",
            TextColor3 = THEME.TextDim,
            Font = Enum.Font.Gotham,
            TextSize = 12,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextYAlignment = Enum.TextYAlignment.Center,
            ZIndex = 12,
        }, UI.propertiesColumn)
    end
end

-- //////////////////////////////////////////////////////////////////////////
-- TOOLBOX (INSERT PANEL)
-- //////////////////////////////////////////////////////////////////////////

local CLASS_COLORS = {
    ScreenGui      = Color3.fromRGB(86, 156, 214),
    Frame          = Color3.fromRGB(158, 158, 170),
    ScrollingFrame = Color3.fromRGB(120, 150, 210),
    CanvasGroup    = Color3.fromRGB(150, 130, 210),
    ViewportFrame  = Color3.fromRGB(120, 180, 200),
    TextLabel      = Color3.fromRGB(225, 200, 100),
    TextButton     = Color3.fromRGB(105, 190, 120),
    TextBox        = Color3.fromRGB(230, 150, 90),
    ImageLabel     = Color3.fromRGB(190, 120, 205),
    ImageButton    = Color3.fromRGB(190, 120, 205),
    VideoFrame     = Color3.fromRGB(205, 120, 130),
    UICorner       = Color3.fromRGB(235, 195, 90),
    UIStroke       = Color3.fromRGB(235, 195, 90),
    UIGradient     = Color3.fromRGB(235, 195, 90),
    UIListLayout   = Color3.fromRGB(235, 195, 90),
    UIGridLayout   = Color3.fromRGB(235, 195, 90),
    UITableLayout  = Color3.fromRGB(235, 195, 90),
    UIPageLayout   = Color3.fromRGB(235, 195, 90),
    UIPadding      = Color3.fromRGB(235, 195, 90),
    UIScale        = Color3.fromRGB(235, 195, 90),
    UISizeConstraint        = Color3.fromRGB(235, 195, 90),
    UITextSizeConstraint    = Color3.fromRGB(235, 195, 90),
    UIAspectRatioConstraint = Color3.fromRGB(235, 195, 90),
    LocalScript    = Color3.fromRGB(120, 200, 160),
    ModuleScript   = Color3.fromRGB(160, 200, 120),
    Folder         = Color3.fromRGB(235, 190, 95),
    Sound          = Color3.fromRGB(170, 130, 220),
    IntValue       = Color3.fromRGB(130, 160, 235),
    NumberValue    = Color3.fromRGB(130, 160, 235),
    StringValue    = Color3.fromRGB(130, 160, 235),
    BoolValue      = Color3.fromRGB(130, 160, 235),
    ObjectValue    = Color3.fromRGB(130, 160, 235),
    Color3Value    = Color3.fromRGB(130, 160, 235),
    Vector3Value   = Color3.fromRGB(130, 160, 235),
    CFrameValue    = Color3.fromRGB(130, 160, 235),
    BrickColorValue = Color3.fromRGB(130, 160, 235),
    RayValue       = Color3.fromRGB(130, 160, 235),
}

-- Toolbox sections: the Insert panel auto-lists every UI class the current
-- executor can actually create (each class is probed before it is shown).
local TOOLBOX_SECTIONS = {
    { title = "Containers",    classes = { "ScreenGui", "Frame", "ScrollingFrame", "CanvasGroup", "ViewportFrame" } },
    { title = "Text & Media",  classes = { "TextLabel", "TextButton", "TextBox", "ImageLabel", "ImageButton", "VideoFrame" } },
    { title = "UI Components", classes = { "UICorner", "UIStroke", "UIGradient", "UIListLayout", "UIGridLayout", "UITableLayout", "UIPageLayout", "UIPadding", "UIScale", "UISizeConstraint", "UITextSizeConstraint", "UIAspectRatioConstraint" } },
    { title = "Scripts",       classes = { "LocalScript", "ModuleScript" } },
    { title = "Organization",  classes = { "Folder" } },
}

local SPAWN_DEFAULTS = {
    Frame = function(inst, x, y)
        inst.Size = UDim2.fromOffset(220, 140)
        inst.Position = UDim2.fromOffset(x, y)
        inst.BackgroundColor3 = Color3.fromRGB(45, 45, 52)
        inst.BorderSizePixel = 0
    end,
    ScrollingFrame = function(inst, x, y)
        inst.Size = UDim2.fromOffset(260, 200)
        inst.Position = UDim2.fromOffset(x, y)
        inst.BackgroundColor3 = Color3.fromRGB(45, 45, 52)
        inst.BorderSizePixel = 0
        inst.ScrollBarThickness = 4
        inst.CanvasSize = UDim2.new()
    end,
    CanvasGroup = function(inst, x, y)
        inst.Size = UDim2.fromOffset(220, 140)
        inst.Position = UDim2.fromOffset(x, y)
        inst.BackgroundColor3 = Color3.fromRGB(45, 45, 52)
        inst.BorderSizePixel = 0
    end,
    TextLabel = function(inst, x, y)
        inst.Size = UDim2.fromOffset(200, 50)
        inst.Position = UDim2.fromOffset(x, y)
        inst.BackgroundColor3 = Color3.fromRGB(45, 45, 52)
        inst.BorderSizePixel = 0
        inst.Text = "Label"
        inst.TextColor3 = Color3.fromRGB(235, 235, 240)
        inst.Font = Enum.Font.GothamMedium
        inst.TextSize = 16
    end,
    TextButton = function(inst, x, y)
        inst.Size = UDim2.fromOffset(150, 42)
        inst.Position = UDim2.fromOffset(x, y)
        inst.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
        inst.BorderSizePixel = 0
        inst.Text = "Button"
        inst.TextColor3 = Color3.fromRGB(255, 255, 255)
        inst.Font = Enum.Font.GothamBold
        inst.TextSize = 15
    end,
    TextBox = function(inst, x, y)
        inst.Size = UDim2.fromOffset(180, 36)
        inst.Position = UDim2.fromOffset(x, y)
        inst.BackgroundColor3 = Color3.fromRGB(235, 235, 240)
        inst.BorderSizePixel = 0
        inst.Text = ""
        inst.PlaceholderText = "Type here..."
        inst.TextColor3 = Color3.fromRGB(25, 25, 30)
        inst.PlaceholderColor3 = Color3.fromRGB(120, 120, 130)
        inst.Font = Enum.Font.Gotham
        inst.TextSize = 14
        inst.ClearTextOnFocus = false
    end,
    ImageLabel = function(inst, x, y)
        inst.Size = UDim2.fromOffset(160, 160)
        inst.Position = UDim2.fromOffset(x, y)
        inst.BackgroundColor3 = Color3.fromRGB(58, 58, 68)
        inst.BorderSizePixel = 0
    end,
    ImageButton = function(inst, x, y)
        inst.Size = UDim2.fromOffset(120, 120)
        inst.Position = UDim2.fromOffset(x, y)
        inst.BackgroundColor3 = Color3.fromRGB(58, 58, 68)
        inst.BorderSizePixel = 0
    end,
    UICorner = function(inst)
        inst.CornerRadius = UDim.new(0, 8)
    end,
    UIStroke = function(inst)
        inst.Thickness = 1
        inst.Color = Color3.fromRGB(255, 255, 255)
    end,
    UIListLayout = function(inst)
        inst.Padding = UDim.new(0, 6)
        inst.SortOrder = Enum.SortOrder.LayoutOrder
    end,
    UIGridLayout = function(inst)
        inst.CellSize = UDim2.fromOffset(64, 64)
        inst.CellPadding = UDim2.fromOffset(6, 6)
        inst.SortOrder = Enum.SortOrder.LayoutOrder
    end,
    UIPadding = function() end,
    UIScale = function() end,
    ViewportFrame = function(inst, x, y)
        inst.Size = UDim2.fromOffset(220, 140)
        inst.Position = UDim2.fromOffset(x, y)
        inst.BackgroundColor3 = Color3.fromRGB(45, 45, 52)
        inst.BorderSizePixel = 0
    end,
    VideoFrame = function(inst, x, y)
        inst.Size = UDim2.fromOffset(320, 180)
        inst.Position = UDim2.fromOffset(x, y)
        inst.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
        inst.BorderSizePixel = 0
    end,
    UIGradient = function() end,
    UITableLayout = function() end,
    UIPageLayout = function() end,
    UISizeConstraint = function() end,
    UITextSizeConstraint = function() end,
    UIAspectRatioConstraint = function() end,
    Folder = function() end,
    LocalScript = function(inst)
        inst.Source = table.concat({
            "-- LocalScript created in GUI Creator",
            "",
            "print(\"Hello from \" .. script.Name)",
            "",
        }, "\n")
    end,
    ModuleScript = function(inst)
        inst.Source = table.concat({
            "-- ModuleScript created in GUI Creator",
            "",
            "local Module = {}",
            "",
            "function Module.Init()",
            "\tprint(script.Name .. \" loaded\")",
            "end",
            "",
            "return Module",
            "",
        }, "\n")
    end,
}

local function resolveSpawnParent(class)
    local isLayoutComponent = class:sub(1, 2) == "UI"
    local sel = State.selected
    if isLayoutComponent then
        if sel and sel.Parent and sel:IsA("GuiObject") then
            return sel
        end
        return nil, "Select a Frame/Button (GuiObject) before adding " .. class
    end
    if sel and sel.Parent then
        if sel:IsA("ScreenGui") or sel:IsA("GuiObject") or sel:IsA("Folder") then
            return sel
        end
        local parent = sel.Parent
        if parent:IsA("GuiObject") or parent:IsA("ScreenGui") then
            return parent
        end
    end
    local guis = getProjectScreenGuis()
    if guis[1] then
        return guis[1]
    end
    return createProjectScreenGui()
end

function Editor.spawnClass(class)
    -- Only LocalScripts and ModuleScripts — server Scripts won't run for everyone.
    local lowerClass = tostring(class):lower()
    if lowerClass == "script" or lowerClass == "corescript" then
        notify("Only LocalScript and ModuleScript are supported — server Scripts won't affect everyone.", "warn", 3.5)
        return nil
    end

    if class == "ScreenGui" then
        local sg = createProjectScreenGui()
        invalidateExplorer()
        Editor.select(sg)
        notify("Created ScreenGui '" .. sg.Name .. "'", "success", 2)
        return sg
    end

    local parent, err = resolveSpawnParent(class)
    if not parent then
        notify(err or ("Cannot spawn " .. class), "warn", 2.5)
        return nil
    end

    local okInst, inst = pcall(Instance.new, class)
    if not okInst or not inst then
        notify(("Cannot create class '%s'."):format(tostring(class)), "error", 3)
        return nil
    end
    inst.Name = uniqueName(class)

    local decorator = SPAWN_DEFAULTS[class]
    if decorator then
        State.spawnCascade = (State.spawnCascade + 1) % 8
        local cascade = State.spawnCascade * 16
        pcall(function() decorator(inst, 24 + cascade, 24 + cascade) end)
    end

    local parentOk = pcall(function() inst.Parent = parent end)
    if not parentOk then
        pcall(function() inst:Destroy() end)
        notify(("Cannot place %s under %s."):format(class, parent.ClassName), "error", 3)
        return nil
    end

    invalidateExplorer()
    Editor.select(inst)
    notify(("Created %s '%s'"):format(class, inst.Name), "success", 2)
    return inst
end

-- Build the toolbox list (auto-filtered: only classes this executor can create).
UI.makeColumnHeader(UI.toolboxColumn, "INSERT")
do
    local toolboxScroll = UI.makeScrollList(UI.toolboxColumn, 24)

    local function makeClassRow(class, layoutOrder)
        local btn = create("TextButton", {
            Size = UDim2.new(1, 0, 0, 26),
            BackgroundColor3 = THEME.Control,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Text = "",
            LayoutOrder = layoutOrder,
            ZIndex = 12,
        }, toolboxScroll)
        local icon = create("Frame", {
            Size = UDim2.fromOffset(10, 10),
            Position = UDim2.fromOffset(8, 8),
            BackgroundColor3 = CLASS_COLORS[class] or THEME.TextDim,
            BorderSizePixel = 0,
            ZIndex = 13,
        }, btn)
        create("UICorner", { CornerRadius = UDim.new(0, 2) }, icon)
        create("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(26, 0),
            Size = UDim2.new(1, -32, 1, 0),
            Text = class,
            TextColor3 = Color3.fromRGB(205, 205, 214),
            Font = Enum.Font.Gotham,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            ZIndex = 13,
        }, btn)
        btn.MouseEnter:Connect(function()
            btn.BackgroundTransparency = 0
        end)
        btn.MouseLeave:Connect(function()
            btn.BackgroundTransparency = 1
        end)
        btn.Activated:Connect(function()
            Editor.spawnClass(class)
        end)
    end

    local function rebuildToolbox()
        for _, child in ipairs(toolboxScroll:GetChildren()) do
            if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
                child:Destroy()
            end
        end
        local order = 0
        for _, section in ipairs(TOOLBOX_SECTIONS) do
            local available = {}
            for _, class in ipairs(section.classes) do
                if defaultInstanceOf(class) then
                    table.insert(available, class)
                end
            end
            if #available > 0 then
                order += 1
                local isCollapsed = State.toolboxCollapsed[section.title] == true
                local header = create("TextButton", {
                    Size = UDim2.new(1, 0, 0, 20),
                    BackgroundTransparency = 1,
                    Text = (isCollapsed and "+ " or "- ") .. string.upper(section.title),
                    TextColor3 = THEME.Accent,
                    Font = Enum.Font.GothamBold,
                    TextSize = 10,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    LayoutOrder = order,
                    ZIndex = 12,
                }, toolboxScroll)
                header.Activated:Connect(function()
                    if State.toolboxCollapsed[section.title] then
                        State.toolboxCollapsed[section.title] = nil
                    else
                        State.toolboxCollapsed[section.title] = true
                    end
                    rebuildToolbox()
                end)
                if not isCollapsed then
                    for _, class in ipairs(available) do
                        order += 1
                        makeClassRow(class, order)
                    end
                end
            end
        end
    end

    rebuildToolbox()
end

-- //////////////////////////////////////////////////////////////////////////
-- EXPLORER (hierarchy tree)
-- //////////////////////////////////////////////////////////////////////////

local explorerRows = setmetatable({}, { __mode = "k" })
local watchers = setmetatable({}, { __mode = "k" })
local explorerDirty = false
local rebuildExplorer

local function disconnectWatcherList(list)
    if not list then return end
    for _, connection in ipairs(list) do
        pcall(function() connection:Disconnect() end)
    end
end

local function clearWatchersBelow(root)
    local function walk(inst)
        disconnectWatcherList(watchers[inst])
        watchers[inst] = nil
        for _, child in ipairs(inst:GetChildren()) do
            walk(child)
        end
    end
    pcall(walk, root)
end

local function clearAllWatchers()
    for inst in pairs(watchers) do
        disconnectWatcherList(watchers[inst])
    end
    watchers = setmetatable({}, { __mode = "k" })
end

local function watchInstance(inst)
    if watchers[inst] then return end
    local list = {}
    local ok = pcall(function()
        list[#list + 1] = inst.ChildAdded:Connect(function()
            invalidateExplorer()
        end)
        list[#list + 1] = inst.ChildRemoved:Connect(function(child)
            -- Deselect if the removed instance (or an ancestor of it) was selected.
            if State.selected then
                local current = State.selected
                while current do
                    if current == child then
                        Editor.select(nil)
                        break
                    end
                    current = current.Parent
                end
            end
            clearWatchersBelow(child)
            invalidateExplorer()
        end)
        list[#list + 1] = inst.AncestryChanged:Connect(function(_, parent)
            if not parent then
                clearWatchersBelow(inst)
                if State.selected == inst then
                    Editor.select(nil)
                end
                invalidateExplorer()
            end
        end)
    end)
    if ok then
        watchers[inst] = list
    end
end

invalidateExplorer = function()
    explorerDirty = true
end

rebuildExplorer = function()
    if not explorerScroll then return end
    local savedScroll = explorerScroll.CanvasPosition
    clearAllWatchers()
    for _, child in ipairs(explorerScroll:GetChildren()) do
        if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
            child:Destroy()
        end
    end
    for key in pairs(explorerRows) do
        explorerRows[key] = nil
    end

    local function addNode(inst, depth)
        watchInstance(inst)

        local kids = treeChildren(inst)
        local hasKids = #kids > 0
        local isSelected = State.selected == inst

        local row = create("TextButton", {
            Size = UDim2.new(1, 0, 0, 22),
            BackgroundColor3 = isSelected and THEME.Selection or THEME.Panel,
            BackgroundTransparency = isSelected and 0 or 1,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Text = "",
            LayoutOrder = depth * 1000 + #explorerRows,
            ZIndex = 12,
        }, explorerScroll)

        local indent = 6 + depth * 14
        if hasKids then
            local arrow = create("TextButton", {
                Size = UDim2.fromOffset(14, 14),
                Position = UDim2.fromOffset(indent, 4),
                BackgroundTransparency = 1,
                Text = State.collapsed[inst] and "+" or "-",
                TextColor3 = THEME.TextDim,
                Font = Enum.Font.GothamBold,
                TextSize = 12,
                ZIndex = 13,
            }, row)
            arrow.Activated:Connect(function()
                if State.collapsed[inst] then
                    State.collapsed[inst] = nil
                else
                    State.collapsed[inst] = true
                end
                rebuildExplorer()
            end)
        end

        local icon = create("Frame", {
            Size = UDim2.fromOffset(10, 10),
            Position = UDim2.fromOffset(indent + (hasKids and 17 or 3), 6),
            BackgroundColor3 = CLASS_COLORS[inst.ClassName] or THEME.TextDim,
            BorderSizePixel = 0,
            ZIndex = 13,
        }, row)
        create("UICorner", { CornerRadius = UDim.new(0, 2) }, icon)

        create("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(indent + (hasKids and 31 or 17), 0),
            Size = UDim2.new(1, -(indent + (hasKids and 37 or 23)), 1, 0),
            Text = inst.Name,
            TextColor3 = isSelected and THEME.Text or Color3.fromRGB(205, 205, 214),
            Font = Enum.Font.Gotham,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            ZIndex = 13,
        }, row)

        row.Activated:Connect(function()
            Editor.select(inst)
        end)

        explorerRows[inst] = { frame = row }

        if not State.collapsed[inst] then
            for _, child in ipairs(kids) do
                addNode(child, depth + 1)
            end
        end
    end

    for _, sg in ipairs(getProjectScreenGuis()) do
        addNode(sg, 0)
    end

    explorerScroll.CanvasPosition = savedScroll
end

refreshExplorerSelection = function()
    for inst, refs in pairs(explorerRows) do
        local isSelected = State.selected == inst
        if refs.frame then
            refs.frame.BackgroundColor3 = isSelected and THEME.Selection or THEME.Panel
            refs.frame.BackgroundTransparency = isSelected and 0 or 1
        end
    end
end

-- //////////////////////////////////////////////////////////////////////////
-- STATUS BAR
-- //////////////////////////////////////////////////////////////////////////

updateStatus = function()
    if UI.statusRight then
        local sel = State.selected
        if sel and sel.Parent then
            UI.statusRight.Text = sel.Name .. "   (" .. sel.ClassName .. ")"
        else
            UI.statusRight.Text = "No selection"
        end
    end
    if UI.statusLeft then
        UI.statusLeft.Text = State.editMode
            and "EDIT — click to select · drag to move · handles resize · [Del] deletes"
            or "TEST — editing paused; interact with your GUI"
    end
end

-- //////////////////////////////////////////////////////////////////////////
-- VIEWPORT MANIPULATION (hit-test / drag / resize)
-- //////////////////////////////////////////////////////////////////////////

local MIN_SIZE = 4

local function isValidTarget(inst)
    return typeof(inst) == "Instance" and inst.Parent ~= nil
end

local function isInstanceShown(inst)
    local current = inst
    while current do
        if current:IsA("GuiObject") and current.Visible == false then
            return false
        end
        if current:IsA("LayerCollector") and current.Enabled == false then
            return false
        end
        current = current.Parent
    end
    return true
end

-- Fully transparent containers don't swallow clicks; select them via Explorer.
local function isVisuallyHittable(inst)
    local ok, transparent = pcall(function() return inst.BackgroundTransparency end)
    if ok and transparent ~= nil and transparent >= 0.99 then
        local hasContent = false
        if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
            local okT, text = pcall(function() return inst.Text end)
            local okTT, textTrans = pcall(function() return inst.TextTransparency end)
            if okT and text and text ~= "" and (not okTT or (textTrans or 0) < 0.99) then
                hasContent = true
            end
        end
        if not hasContent and (inst:IsA("ImageLabel") or inst:IsA("ImageButton")) then
            local okI, image = pcall(function() return inst.Image end)
            local okIT, imageTrans = pcall(function() return inst.ImageTransparency end)
            if okI and image and image ~= "" and (not okIT or (imageTrans or 0) < 0.99) then
                hasContent = true
            end
        end
        if not hasContent then
            return false
        end
    end
    return true
end

local function hitTest(screenPos)
    local best, bestScore
    for _, sg in ipairs(getProjectScreenGuis()) do
        local function walk(inst, depth)
            for _, child in ipairs(treeChildren(inst)) do
                if child:IsA("GuiObject") and isInstanceShown(child) and isVisuallyHittable(child) then
                    local ok, origin, size = pcall(function()
                        return absToScreen(sg, child.AbsolutePosition), child.AbsoluteSize
                    end)
                    if ok and origin and size and size.X > 0 and size.Y > 0
                        and screenPos.X >= origin.X and screenPos.X <= origin.X + size.X
                        and screenPos.Y >= origin.Y and screenPos.Y <= origin.Y + size.Y then
                        local z = 1
                        pcall(function() z = child.ZIndex end)
                        local score = depth * 1000 + z -- deepest, then highest ZIndex
                        if not bestScore or score >= bestScore then
                            best, bestScore = child, score
                        end
                    end
                end
                walk(child, depth + 1)
            end
        end
        walk(sg, 0)
    end
    return best
end

local function isOverEditorSurface(screenPos)
    for _, window in ipairs(UI.windows) do
        if window.Visible then
            local ok, ap, as = pcall(function()
                return window.AbsolutePosition, window.AbsoluteSize
            end)
            if ok and ap and as
                and screenPos.X >= ap.X and screenPos.X <= ap.X + as.X
                and screenPos.Y >= ap.Y and screenPos.Y <= ap.Y + as.Y then
                return true
            end
        end
    end
    return false
end

local function beginDrag(inst, inputObject)
    if not inst:IsA("GuiObject") then return end
    local ok, startPos = pcall(function() return inst.Position end)
    if not ok then return end
    State.dragging = {
        obj = inst,
        startMouse = inputScreenPos(inputObject),
        startPos = startPos,
    }
end

function Editor.beginResize(direction, inputObject)
    local inst = State.selected
    if not inst or not inst.Parent or not inst:IsA("GuiObject") or not State.editMode then
        return
    end
    local okPos, startPos = pcall(function() return inst.Position end)
    local okSize, startSize = pcall(function() return inst.Size end)
    if not okPos or not okSize then return end
    State.resizing = {
        obj = inst,
        dir = direction,
        startMouse = inputScreenPos(inputObject),
        startPos = startPos,
        startSize = startSize,
    }
end

local function applyDrag()
    local drag = State.dragging
    if not isValidTarget(drag.obj) then
        State.dragging = nil
        return
    end
    local delta = inputScreenPos() - drag.startMouse
    local p = drag.startPos
    pcall(function()
        drag.obj.Position = UDim2.new(
            p.X.Scale, p.X.Offset + delta.X,
            p.Y.Scale, p.Y.Offset + delta.Y
        )
    end)
    PropPanel.refresh("Position")
end

local function applyResize()
    local resize = State.resizing
    if not isValidTarget(resize.obj) then
        State.resizing = nil
        return
    end
    local delta = inputScreenPos() - resize.startMouse
    local dir = resize.dir
    local p, s = resize.startPos, resize.startSize

    local xOffset, yOffset = p.X.Offset, p.Y.Offset
    local wOffset, hOffset = s.X.Offset, s.Y.Offset
    local hasL = dir:find("L") ~= nil
    local hasT = dir:find("T") ~= nil
    local hasR = dir:find("R") ~= nil
    local hasB = dir:find("B") ~= nil

    if hasL then
        local newW = wOffset - delta.X
        local newX = xOffset + delta.X
        if newW < MIN_SIZE then
            newX = xOffset + wOffset - MIN_SIZE
            newW = MIN_SIZE
        end
        xOffset, wOffset = newX, newW
    end
    if hasR then
        wOffset = math.max(wOffset + delta.X, MIN_SIZE)
    end
    if hasT then
        local newH = hOffset - delta.Y
        local newY = yOffset + delta.Y
        if newH < MIN_SIZE then
            newY = yOffset + hOffset - MIN_SIZE
            newH = MIN_SIZE
        end
        yOffset, hOffset = newY, newH
    end
    if hasB then
        hOffset = math.max(hOffset + delta.Y, MIN_SIZE)
    end

    pcall(function()
        resize.obj.Position = UDim2.new(p.X.Scale, xOffset, p.Y.Scale, yOffset)
        resize.obj.Size = UDim2.new(s.X.Scale, wOffset, s.Y.Scale, hOffset)
    end)
    PropPanel.refresh("Position")
    PropPanel.refresh("Size")
end

-- Selection clicks (works even on Active elements like TextButtons, because we
-- hit-test geometrically instead of relying on gameProcessedEvent).
trackConnection(UserInputService.InputBegan:Connect(function(input)
    local inputType = input.UserInputType
    if inputType ~= Enum.UserInputType.MouseButton1 and inputType ~= Enum.UserInputType.Touch then
        return
    end
    if not State.editMode then return end
    if State.dragging or State.resizing then return end

    local screenPos = inputScreenPos(input)
    if isOverEditorSurface(screenPos) or isOverHandle(screenPos) then
        return
    end

    local target = hitTest(screenPos)
    if target then
        Editor.select(target)
        if not target:IsA("TextBox") then
            beginDrag(target, input) -- TextBoxes are select-only so you can type in them
        end
    else
        Editor.select(nil)
    end
end))

trackConnection(UserInputService.InputChanged:Connect(function(input)
    local inputType = input.UserInputType
    if inputType ~= Enum.UserInputType.MouseMovement and inputType ~= Enum.UserInputType.Touch then
        return
    end
    if State.windowDrag then
        local delta = inputScreenPos(input) - State.windowDrag.startMouse
        UI.main.Position = UDim2.fromOffset(
            State.windowDrag.startPosition.X.Offset + delta.X,
            State.windowDrag.startPosition.Y.Offset + delta.Y
        )
    elseif State.dragging then
        applyDrag()
    elseif State.resizing then
        applyResize()
    end
end))

trackConnection(UserInputService.InputEnded:Connect(function(input)
    local inputType = input.UserInputType
    if inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch then
        State.dragging = nil
        State.resizing = nil
        State.windowDrag = nil
    end
end))

trackConnection(UserInputService.WindowFocusReleased:Connect(function()
    State.dragging = nil
    State.resizing = nil
    State.windowDrag = nil
end))

-- Delete key shortcut (ignored while typing in a TextBox).
trackConnection(UserInputService.InputBegan:Connect(function(input)
    if input.KeyCode ~= Enum.KeyCode.Delete then return end
    local ok, focused = pcall(function() return UserInputService:GetFocusedTextBox() end)
    if ok and focused then return end
    if State.editMode then
        Editor.deleteSelected()
    end
end))

-- //////////////////////////////////////////////////////////////////////////
-- LUAU EXPORTER
-- //////////////////////////////////////////////////////////////////////////

local EXPORT_KEYWORDS = {
    ["and"]=true, ["break"]=true, ["do"]=true, ["else"]=true, ["elseif"]=true, ["end"]=true,
    ["false"]=true, ["for"]=true, ["function"]=true, ["if"]=true, ["in"]=true, ["local"]=true,
    ["nil"]=true, ["not"]=true, ["or"]=true, ["repeat"]=true, ["return"]=true, ["then"]=true,
    ["true"]=true, ["until"]=true, ["while"]=true, ["continue"]=true,
}
local EXPORT_RESERVED = {
    game=true, workspace=true, script=true, Instance=true, Enum=true, UDim=true, UDim2=true,
    Color3=true, Vector2=true, Vector3=true, CFrame=true, TweenInfo=true, Players=true,
    player=true, playerGui=true, task=true, math=true, table=true, string=true, os=true,
    pairs=true, ipairs=true, print=true, warn=true, wait=true, spawn=true, tostring=true,
}

local function valueToLuau(value)
    local kind = typeof(value)
    if kind == "string" then
        local ok, encoded = pcall(string.format, "%q", value)
        return ok and encoded or '""'
    elseif kind == "number" then
        return trimNum(value)
    elseif kind == "boolean" then
        return tostring(value)
    elseif kind == "Color3" then
        return ("Color3.fromRGB(%d, %d, %d)"):format(
            math.floor(value.R * 255 + 0.5),
            math.floor(value.G * 255 + 0.5),
            math.floor(value.B * 255 + 0.5))
    elseif kind == "UDim2" then
        return ("UDim2.new(%s, %s, %s, %s)"):format(
            trimNum(value.X.Scale), trimNum(value.X.Offset),
            trimNum(value.Y.Scale), trimNum(value.Y.Offset))
    elseif kind == "UDim" then
        return ("UDim.new(%s, %s)"):format(trimNum(value.Scale), trimNum(value.Offset))
    elseif kind == "Vector2" then
        return ("Vector2.new(%s, %s)"):format(trimNum(value.X), trimNum(value.Y))
    elseif kind == "Vector3" then
        return ("Vector3.new(%s, %s, %s)"):format(trimNum(value.X), trimNum(value.Y), trimNum(value.Z))
    elseif kind == "ColorSequence" then
        local parts = {}
        for _, keypoint in ipairs(value.Keypoints) do
            table.insert(parts, ("ColorSequenceKeypoint.new(%s, Color3.fromRGB(%d, %d, %d))"):format(
                trimNum(keypoint.Time),
                math.floor(keypoint.Value.R * 255 + 0.5),
                math.floor(keypoint.Value.G * 255 + 0.5),
                math.floor(keypoint.Value.B * 255 + 0.5)))
        end
        return "ColorSequence.new({" .. table.concat(parts, ", ") .. "})"
    elseif kind == "EnumItem" then
        return tostring(value)
    end
    return nil -- Instance refs / CFrame / BrickColor / Ray are not serializable
end

local function exportPropertyNameList(className)
    local list = { "Name" }
    local groups = CLASS_GROUPS[className]
    if groups then
        for _, groupKey in ipairs(groups) do
            local props = PROP_GROUPS[groupKey]
            if props then
                for _, propName in ipairs(props) do
                    if propName ~= "Name" then
                        table.insert(list, propName)
                    end
                end
            end
        end
    else
        list = { "Name" }
        local seenFallback = {}
        for _, groupKey in ipairs(FALLBACK_GROUP_KEYS) do
            for _, propName in ipairs(PROP_GROUPS[groupKey] or {}) do
                if propName ~= "Name" and not seenFallback[propName] then
                    seenFallback[propName] = true
                    table.insert(list, propName)
                end
            end
        end
    end
    local seen, final = {}, {}
    for _, propName in ipairs(list) do
        if not seen[propName] then
            seen[propName] = true
            table.insert(final, propName)
        end
    end
    return final
end

local function generateExportCode()
    local guis = getProjectScreenGuis()
    if #guis == 0 then
        return nil
    end

    local variableOf = {}
    local usedNames = {}
    local nameCounters = {}
    local totalInstances = 0

    local function assignVariables(inst, depth)
        totalInstances += 1
        local base = tostring(inst.Name):gsub("[^%w_]", "_")
        if base:match("^%d") then
            base = "_" .. base
        end
        if EXPORT_KEYWORDS[base] or EXPORT_RESERVED[base] then
            base = base .. "_"
        end
        nameCounters[base] = (nameCounters[base] or 0) + 1
        local candidate = nameCounters[base] == 1 and base or (base .. tostring(nameCounters[base]))
        while usedNames[candidate] do
            nameCounters[base] += 1
            candidate = base .. tostring(nameCounters[base])
        end
        usedNames[candidate] = true
        variableOf[inst] = { name = candidate, depth = depth }
        for _, child in ipairs(treeChildren(inst)) do
            assignVariables(child, depth + 1)
        end
    end
    for _, sg in ipairs(guis) do
        assignVariables(sg, 0)
    end

    local lines = {}
    local function emit(text)
        lines[#lines + 1] = text
    end

    emit("--[[")
    emit("\tGenerated by StudioGUI Creator — WYSIWYG GUI Editor")
    emit(("\tExported: %s  |  Instances: %d  |  Executor: %s"):format(
        os.date("%Y-%m-%d %H:%M:%S"), totalInstances, Executor.name))
    emit("")
    emit("\tRun as a LocalScript (or paste into your executor).")
    if State.coreGuiMode then
        emit("\tRebuilds the GUI inside a protected container (gethui/CoreGui),")
        emit("\tfalling back to PlayerGui — matches the \"Put on CoreGui\" mode")
        emit("\tthat was active when this file was exported.")
    else
        emit("\tRebuilds the entire GUI under the LocalPlayer's PlayerGui.")
    end
    emit("]]")
    emit("")
    emit("local Players = game:GetService(\"Players\")")
    emit("local playerGui = Players.LocalPlayer:WaitForChild(\"PlayerGui\")")
    if State.coreGuiMode then
        emit("-- \"Put on CoreGui\" was active: rebuild inside the protected container.")
        emit("local parentRoot = playerGui")
        emit("do")
        emit("\tlocal okHui, hui = pcall(function()")
        emit("\t\tif type(gethui) == \"function\" then return gethui() end")
        emit("\t\treturn nil")
        emit("\tend)")
        emit("\tif okHui and hui then")
        emit("\t\tparentRoot = hui")
        emit("\telse")
        emit("\t\tlocal okCore, coreGui = pcall(function() return game:GetService(\"CoreGui\") end)")
        emit("\t\tif okCore and coreGui then parentRoot = coreGui end")
        emit("\tend")
        emit("end")
    else
        emit("local parentRoot = playerGui")
    end
    emit("")

    for _, sg in ipairs(guis) do
        local function emitInstance(inst)
            local info = variableOf[inst]
            local indent = string.rep("\t", info.depth)
            local varName = info.name

            emit(indent .. ("local %s = Instance.new(\"%s\")"):format(varName, inst.ClassName))

            local isRootGui = inst:IsA("ScreenGui")
            for _, propName in ipairs(exportPropertyNameList(inst.ClassName)) do
                local okValue, value = pcall(function() return inst[propName] end)
                if okValue then
                    -- Only emit properties that differ from a fresh default (clean output).
                    local skip = false
                    local defaultInst = defaultInstanceOf(inst.ClassName)
                    if defaultInst then
                        local okDefault, defaultValue = pcall(function() return defaultInst[propName] end)
                        if okDefault and defaultValue == value then
                            skip = true
                        end
                    end
                    if not skip then
                        local code = valueToLuau(value)
                        if code then
                            emit(indent .. ("%s.%s = %s"):format(varName, propName, code))
                        end
                    end
                end
            end
            if isRootGui then
                emit(indent .. ("%s.ResetOnSpawn = false -- survive respawn"):format(varName))
            end

            local parentVar = "parentRoot"
            if not isRootGui and variableOf[inst.Parent] then
                parentVar = variableOf[inst.Parent].name
            end
            emit(indent .. ("%s.Parent = %s"):format(varName, parentVar))
            emit("")

            for _, child in ipairs(treeChildren(inst)) do
                emitInstance(child)
            end
        end
        emitInstance(sg)
    end

    emit(("-- End of export: %d instances."):format(totalInstances))
    return table.concat(lines, "\n")
end

-- Export modal (code viewer + copy/save).
do
    local modal = create("Frame", {
        Name = "ExportModal",
        Size = UDim2.fromOffset(620, 460),
        Position = UDim2.fromOffset(80, 90),
        BackgroundColor3 = THEME.Window,
        BorderSizePixel = 0,
        Visible = false,
        Active = true,
        ZIndex = 60,
    }, Overlay)
    create("UICorner", { CornerRadius = UDim.new(0, 8) }, modal)
    create("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, modal)

    create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(14, 0),
        Size = UDim2.new(1, -330, 0, 32),
        Text = "Luau Export",
        TextColor3 = THEME.Text,
        Font = Enum.Font.GothamMedium,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 61,
    }, modal)

    local function modalButton(text, offsetX, onClick, accent)
        local btn = create("TextButton", {
            Size = UDim2.fromOffset(84, 22),
            Position = UDim2.new(1, offsetX, 0, 5),
            BackgroundColor3 = accent and THEME.Accent or THEME.Control,
            BorderSizePixel = 0,
            Text = text,
            TextColor3 = THEME.Text,
            Font = Enum.Font.GothamMedium,
            TextSize = 12,
            AutoButtonColor = false,
            ZIndex = 61,
        }, modal)
        create("UICorner", { CornerRadius = UDim.new(0, 5) }, btn)
        btn.Activated:Connect(onClick)
        return btn
    end

    local codeScroll = create("ScrollingFrame", {
        Position = UDim2.fromOffset(8, 38),
        Size = UDim2.new(1, -16, 1, -76),
        BackgroundColor3 = Color3.fromRGB(18, 18, 22),
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(),
        ScrollingDirection = Enum.ScrollingDirection.XY,
        ScrollBarThickness = 5,
        ScrollBarImageColor3 = THEME.ControlHover,
        ZIndex = 61,
    }, modal)
    create("UICorner", { CornerRadius = UDim.new(0, 6) }, codeScroll)
    create("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, codeScroll)

    local codeBox = create("TextBox", {
        Size = UDim2.fromOffset(400, 100),
        Position = UDim2.fromOffset(5, 5),
        BackgroundColor3 = Color3.fromRGB(18, 18, 22),
        TextColor3 = Color3.fromRGB(200, 205, 215),
        Font = Enum.Font.Code,
        TextSize = 13,
        Text = "",
        MultiLine = true,
        ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = false,
        BorderSizePixel = 0,
        ZIndex = 62,
    }, codeScroll)

    create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 8, 1, -24),
        Size = UDim2.new(1, -16, 0, 18),
        Text = "Tip: click the code box, then Ctrl+A → Ctrl+C to copy manually.",
        TextColor3 = THEME.TextDim,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 61,
    }, modal)

    local currentCode = ""

    modalButton("Copy", -288, function()
        if Executor.clipboard then
            local ok = pcall(Executor.clipboard, currentCode)
            notify(ok and "Copied export code to clipboard." or "Clipboard copy failed.",
                ok and "success" or "error", 2.5)
        else
            notify("Clipboard API unavailable — click the code, Ctrl+A, Ctrl+C.", "warn", 4)
        end
    end, true)

    modalButton("Save File", -196, function()
        if not Executor.writefile then
            notify("writefile is not available on this executor.", "warn", 3)
            return
        end
        local ok, err = pcall(Executor.writefile, "studiogui_export.lua", currentCode)
        notify(
            ok and "Saved to workspace: studiogui_export.lua"
                or ("Save failed: %s"):format(tostring(err)),
            ok and "success" or "error", 3.5)
    end)

    modalButton("Close", -104, function()
        modal.Visible = false
    end)

    function Editor.openExport()
        local code = generateExportCode()
        if not code then
            notify("Nothing to export — create a GUI first.", "warn", 2.5)
            return
        end
        currentCode = code

        local lineCount = 1
        for _ in code:gmatch("\n") do
            lineCount += 1
        end
        local maxLen = 0
        for line in code:gmatch("[^\n]+") do
            if #line > maxLen then
                maxLen = #line
            end
        end
        local contentHeight = math.clamp(lineCount * 16 + 12, 100, 200000)
        local contentWidth = math.max(maxLen * 8 + 24, 240)
        codeBox.Size = UDim2.fromOffset(contentWidth, contentHeight)
        codeScroll.CanvasSize = UDim2.fromOffset(contentWidth + 10, contentHeight + 12)

        local ok = pcall(function() codeBox.Text = code end)
        if not ok then
            notify("Export too large to display — use Save File instead.", "warn", 4)
        end
        modal.Visible = true
        notify(("Exported %d lines of Luau."):format(lineCount), "success", 2.5)
    end

    table.insert(UI.windows, modal)
end

-- //////////////////////////////////////////////////////////////////////////
-- SCRIPT FUNCTION MODALS ("{Type}Script Function" viewer + customizer)
-- //////////////////////////////////////////////////////////////////////////

do
    local function scriptKindLabel(scriptInst)
        return scriptInst:IsA("ModuleScript") and "Module" or "Local"
    end

    local modal = create("Frame", {
        Name = "FunctionModal",
        Size = UDim2.fromOffset(620, 460),
        Position = UDim2.fromOffset(80, 90),
        BackgroundColor3 = THEME.Window,
        BorderSizePixel = 0,
        Visible = false,
        Active = true,
        ZIndex = 60,
    }, Overlay)
    create("UICorner", { CornerRadius = UDim.new(0, 8) }, modal)
    create("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, modal)

    local titleLabel = create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(14, 0),
        Size = UDim2.new(1, -330, 0, 32),
        Text = "Function",
        TextColor3 = THEME.Text,
        Font = Enum.Font.GothamMedium,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 61,
    }, modal)

    local function modalButton(text, offsetX, onClick, accent)
        local btn = create("TextButton", {
            Size = UDim2.fromOffset(84, 22),
            Position = UDim2.new(1, offsetX, 0, 5),
            BackgroundColor3 = accent and THEME.Accent or THEME.Control,
            BorderSizePixel = 0,
            Text = text,
            TextColor3 = THEME.Text,
            Font = Enum.Font.GothamMedium,
            TextSize = 12,
            AutoButtonColor = false,
            ZIndex = 61,
        }, modal)
        create("UICorner", { CornerRadius = UDim.new(0, 5) }, btn)
        btn.Activated:Connect(onClick)
        return btn
    end

    local sourceBox = create("TextBox", {
        Position = UDim2.fromOffset(8, 38),
        Size = UDim2.new(1, -16, 1, -76),
        BackgroundColor3 = Color3.fromRGB(18, 18, 22),
        TextColor3 = Color3.fromRGB(200, 205, 215),
        Font = Enum.Font.Code,
        TextSize = 13,
        Text = "",
        MultiLine = true,
        ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = false,
        BorderSizePixel = 0,
        ZIndex = 61,
    }, modal)
    create("UICorner", { CornerRadius = UDim.new(0, 6) }, sourceBox)
    create("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, sourceBox)
    create("UIPadding", {
        PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
        PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
    }, sourceBox)

    create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 8, 1, -24),
        Size = UDim2.new(1, -16, 0, 18),
        Text = "Click inside the code area to edit. Apply writes the source to the script.",
        TextColor3 = THEME.TextDim,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 61,
    }, modal)

    local currentScript = nil

    modalButton("Copy", -288, function()
        if Executor.clipboard then
            local ok = pcall(Executor.clipboard, sourceBox.Text)
            notify(ok and "Copied function source to clipboard." or "Clipboard copy failed.",
                ok and "success" or "error", 2.5)
        else
            notify("Clipboard API unavailable — click the code, Ctrl+A, Ctrl+C.", "warn", 4)
        end
    end, false)

    local applyButton = modalButton("Apply", -196, function()
        if not (currentScript and currentScript.Parent) then
            notify("The script no longer exists.", "error", 2.5)
            return
        end
        local applied = pcall(function()
            currentScript.Source = sourceBox.Text
        end)
        if applied then
            notify(currentScript.Name .. " function updated.", "success", 2.5)
        else
            notify("Failed to write Source on this executor.", "error", 3)
        end
    end, true)

    modalButton("Close", -104, function()
        modal.Visible = false
    end)

    local function openWith(scriptInst, editable)
        if typeof(scriptInst) ~= "Instance" or not scriptInst.Parent then
            notify("Select a LocalScript or ModuleScript first.", "warn", 2.5)
            return
        end
        if not (scriptInst:IsA("LocalScript") or scriptInst:IsA("ModuleScript")) then
            notify("Functions work on LocalScripts and ModuleScripts only.", "warn", 3)
            return
        end
        currentScript = scriptInst
        local kindLabel = scriptKindLabel(scriptInst)
        titleLabel.Text = ((editable and "Customize " or "") .. kindLabel .. "Script Function  —  " .. scriptInst.Name)
        local okRead, source = pcall(function() return scriptInst.Source end)
        if okRead and type(source) == "string" then
            sourceBox.Text = source
        elseif editable then
            sourceBox.Text = "-- Unable to read Source; typing here will replace it on Apply."
        else
            sourceBox.Text = "-- Unable to read Source on this executor."
        end
        sourceBox.Editable = editable
        applyButton.Visible = editable
        modal.Visible = true
    end

    function Editor.openFunctionViewer(scriptInst)
        openWith(scriptInst, false)
    end

    function Editor.openFunctionEditor(scriptInst)
        openWith(scriptInst, true)
    end

    table.insert(UI.windows, modal)
end

-- //////////////////////////////////////////////////////////////////////////
-- SAVE & LOAD (GUI_CREATOR_SAVES folder — file extension never matters)
-- //////////////////////////////////////////////////////////////////////////

local SAVE_DIR = "GUI_CREATOR_SAVES"
local HttpService = game:GetService("HttpService")

local FS = {
    readfile  = (type(readfile) == "function") and readfile or nil,
    listfiles = (type(listfiles) == "function") and listfiles or nil,
    isfolder  = (type(isfolder) == "function") and isfolder or nil,
    isfile    = (type(isfile) == "function") and isfile or nil,
}

local function ensureSaveFolder()
    if not Executor.writefile then
        return false
    end
    if FS.isfolder then
        local ok, exists = pcall(FS.isfolder, SAVE_DIR)
        if ok and exists then
            return true
        end
    end
    -- Most executors create missing folders automatically on writefile.
    local ok = pcall(Executor.writefile, SAVE_DIR .. "/.keep", "GUI Creator save folder")
    return ok
end

local function sanitizeSaveName(raw)
    local name = tostring(raw):gsub("^%s+", ""):gsub("%s+$", "")
    name = name:gsub("[/\\:%*%?\"<>|]", "")
    name = name:gsub("^%.", "")
    name = name:gsub("%s+", " ")
    if #name > 64 then
        name = name:sub(1, 64)
    end
    return name
end

local function serializeValue(value)
    local kind = typeof(value)
    if kind == "string" or kind == "number" or kind == "boolean" then
        return value
    elseif kind == "EnumItem" then
        return { ct = "Enum", et = value.EnumType.Name, en = value.Name }
    elseif kind == "Color3" then
        return { ct = "Color3", r = value.R, g = value.G, b = value.B }
    elseif kind == "UDim2" then
        return { ct = "UDim2", xs = value.X.Scale, xo = value.X.Offset, ys = value.Y.Scale, yo = value.Y.Offset }
    elseif kind == "UDim" then
        return { ct = "UDim", s = value.Scale, o = value.Offset }
    elseif kind == "Vector2" then
        return { ct = "Vector2", x = value.X, y = value.Y }
    elseif kind == "Vector3" then
        return { ct = "Vector3", x = value.X, y = value.Y, z = value.Z }
    elseif kind == "ColorSequence" then
        local pts = {}
        for _, keypoint in ipairs(value.Keypoints) do
            table.insert(pts, { t = keypoint.Time, r = keypoint.Value.R, g = keypoint.Value.G, b = keypoint.Value.B })
        end
        return { ct = "ColorSequence", pts = pts }
    end
    return nil -- Instance refs / CFrame / BrickColor / Ray are not serializable
end

local function deserializeValue(encoded)
    local kind = typeof(encoded)
    if kind == "string" or kind == "number" or kind == "boolean" then
        return encoded
    elseif kind == "table" then
        local ct = encoded.ct
        if ct == "Enum" and type(encoded.et) == "string" and type(encoded.en) == "string" then
            local ok, item = pcall(function()
                return Enum[encoded.et][encoded.en]
            end)
            if ok then
                return item
            end
        elseif ct == "Color3" then
            return Color3.new(tonumber(encoded.r) or 0, tonumber(encoded.g) or 0, tonumber(encoded.b) or 0)
        elseif ct == "UDim2" then
            return UDim2.new(
                tonumber(encoded.xs) or 0, tonumber(encoded.xo) or 0,
                tonumber(encoded.ys) or 0, tonumber(encoded.yo) or 0)
        elseif ct == "UDim" then
            return UDim.new(tonumber(encoded.s) or 0, tonumber(encoded.o) or 0)
        elseif ct == "Vector2" then
            return Vector2.new(tonumber(encoded.x) or 0, tonumber(encoded.y) or 0)
        elseif ct == "Vector3" then
            return Vector3.new(tonumber(encoded.x) or 0, tonumber(encoded.y) or 0, tonumber(encoded.z) or 0)
        elseif ct == "ColorSequence" and typeof(encoded.pts) == "table" then
            local stops = {}
            for _, pt in ipairs(encoded.pts) do
                if typeof(pt) == "table" then
                    table.insert(stops, {
                        t = math.clamp(tonumber(pt.t) or 0, 0, 1),
                        c = Color3.new(tonumber(pt.r) or 0, tonumber(pt.g) or 0, tonumber(pt.b) or 0),
                    })
                end
            end
            if #stops >= 2 then
                table.sort(stops, function(a, b) return a.t < b.t end)
                stops[1].t = 0
                stops[#stops].t = 1
                local keypoints = {}
                for _, stop in ipairs(stops) do
                    table.insert(keypoints, ColorSequenceKeypoint.new(stop.t, stop.c))
                end
                return ColorSequence.new(keypoints)
            end
        end
    end
    return nil
end

local function getSerializableProps(inst)
    local names, seen = {}, {}
    local groups = CLASS_GROUPS[inst.ClassName] or FALLBACK_GROUP_KEYS
    for _, groupKey in ipairs(groups) do
        for _, propName in ipairs(PROP_GROUPS[groupKey] or {}) do
            if propName ~= "Name" and not seen[propName] then
                seen[propName] = true
                table.insert(names, propName)
            end
        end
    end
    local final = {}
    for _, propName in ipairs(names) do
        local ok = pcall(function() return inst[propName] end)
        if ok then
            table.insert(final, propName)
        end
    end
    return final
end

local function serializeInstanceTree(inst)
    local entry = { c = inst.ClassName, n = inst.Name, p = {}, ch = {} }
    local defaultInst = defaultInstanceOf(inst.ClassName)
    for _, propName in ipairs(getSerializableProps(inst)) do
        local okValue, value = pcall(function() return inst[propName] end)
        if okValue then
            -- Only store properties that differ from a fresh default (small files).
            local skip = false
            if defaultInst then
                local okDefault, defaultValue = pcall(function() return defaultInst[propName] end)
                if okDefault and defaultValue == value then
                    skip = true
                end
            end
            if not skip then
                local encoded = serializeValue(value)
                if encoded ~= nil then
                    entry.p[propName] = encoded
                end
            end
        end
    end
    for _, child in ipairs(treeChildren(inst)) do
        table.insert(entry.ch, serializeInstanceTree(child))
    end
    return entry
end

local function serializeProject()
    local guis = getProjectScreenGuis()
    if #guis == 0 then
        return nil
    end
    local data = {}
    for _, sg in ipairs(guis) do
        table.insert(data, serializeInstanceTree(sg))
    end
    return data
end

local function buildInstanceTree(entry, parent)
    if typeof(entry) ~= "table" or type(entry.c) ~= "string" then
        return nil
    end
    local okInst, inst = pcall(Instance.new, entry.c)
    if not okInst or typeof(inst) ~= "Instance" then
        return nil
    end
    if type(entry.n) == "string" and entry.n ~= "" then
        pcall(function() inst.Name = entry.n end)
    end
    if typeof(entry.p) == "table" then
        for propName, encoded in pairs(entry.p) do
            if type(propName) == "string" and propName ~= "Name" then
                local value = deserializeValue(encoded)
                if value ~= nil then
                    pcall(function() inst[propName] = value end)
                end
            end
        end
    end
    if entry.c == "ScreenGui" then
        pcall(function() inst:SetAttribute(PROJECT_ATTRIBUTE, true) end)
        parent = PROJECT_PARENT
    end
    pcall(function() inst.Parent = parent end)
    if typeof(entry.ch) == "table" then
        for _, childEntry in ipairs(entry.ch) do
            buildInstanceTree(childEntry, inst)
        end
    end
    return inst
end

local function replaceProjectWith(data)
    for _, sg in ipairs(getProjectScreenGuis()) do
        pcall(function() sg:Destroy() end)
    end
    local created = 0
    if typeof(data) == "table" then
        for _, entry in ipairs(data) do
            if buildInstanceTree(entry, PROJECT_PARENT) then
                created += 1
            end
        end
    end
    ensureProjectIntegrity()
    invalidateExplorer()
    local guis = getProjectScreenGuis()
    if guis[1] then
        Editor.select(guis[1])
    else
        Editor.select(nil)
    end
    return created
end

-- Save dialog ----------------------------------------------------------------
do
    local dialog = create("Frame", {
        Name = "SaveDialog",
        Size = UDim2.fromOffset(360, 180),
        Position = UDim2.fromOffset(170, 140),
        BackgroundColor3 = THEME.Window,
        BorderSizePixel = 0,
        Visible = false,
        Active = true,
        ZIndex = 60,
    }, Overlay)
    create("UICorner", { CornerRadius = UDim.new(0, 8) }, dialog)
    create("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, dialog)

    create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(14, 0),
        Size = UDim2.new(1, -110, 0, 32),
        Text = "Save Project",
        TextColor3 = THEME.Text,
        Font = Enum.Font.GothamMedium,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 61,
    }, dialog)
    do
        local closeButton = create("TextButton", {
            Size = UDim2.fromOffset(26, 20),
            Position = UDim2.new(1, -34, 0, 6),
            BackgroundColor3 = THEME.Control,
            BorderSizePixel = 0,
            Text = "×",
            TextColor3 = THEME.Text,
            Font = Enum.Font.GothamBold,
            TextSize = 12,
            AutoButtonColor = false,
            ZIndex = 61,
        }, dialog)
        create("UICorner", { CornerRadius = UDim.new(0, 4) }, closeButton)
        closeButton.MouseEnter:Connect(function() closeButton.BackgroundColor3 = THEME.ControlHover end)
        closeButton.MouseLeave:Connect(function() closeButton.BackgroundColor3 = THEME.Control end)
        closeButton.Activated:Connect(function() dialog.Visible = false end)
    end

    local nameBox = create("TextBox", {
        Position = UDim2.fromOffset(12, 42),
        Size = UDim2.new(1, -24, 0, 30),
        BackgroundColor3 = THEME.Control,
        TextColor3 = THEME.Text,
        PlaceholderText = "File name (extension optional)",
        PlaceholderColor3 = THEME.TextDim,
        Font = Enum.Font.Gotham,
        TextSize = 13,
        Text = "",
        ClearTextOnFocus = false,
        BorderSizePixel = 0,
        ZIndex = 61,
    }, dialog)
    create("UICorner", { CornerRadius = UDim.new(0, 5) }, nameBox)
    create("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, nameBox)
    create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 6) }, nameBox)

    create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(12, 80),
        Size = UDim2.new(1, -24, 0, 30),
        Text = "Saves every project ScreenGui into the \"GUI_CREATOR_SAVES\" folder.\nAny file name works — extensions don't matter.",
        TextColor3 = THEME.TextDim,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 61,
    }, dialog)

    local cancelButton = create("TextButton", {
        Position = UDim2.new(1, -182, 1, -34),
        Size = UDim2.fromOffset(80, 24),
        BackgroundColor3 = THEME.Control,
        BorderSizePixel = 0,
        Text = "Cancel",
        TextColor3 = THEME.Text,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        AutoButtonColor = false,
        ZIndex = 61,
    }, dialog)
    create("UICorner", { CornerRadius = UDim.new(0, 5) }, cancelButton)

    local saveButton = create("TextButton", {
        Position = UDim2.new(1, -94, 1, -34),
        Size = UDim2.fromOffset(82, 24),
        BackgroundColor3 = THEME.Accent,
        BorderSizePixel = 0,
        Text = "Save",
        TextColor3 = THEME.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        AutoButtonColor = false,
        ZIndex = 61,
    }, dialog)
    create("UICorner", { CornerRadius = UDim.new(0, 5) }, saveButton)

    cancelButton.Activated:Connect(function()
        dialog.Visible = false
    end)

    saveButton.Activated:Connect(function()
        if not Executor.writefile then
            notify("writefile is not available on this executor.", "warn", 3)
            return
        end
        local name = sanitizeSaveName(nameBox.Text)
        if name == "" then
            notify("Enter a file name first.", "warn", 2.5)
            return
        end
        if not ensureSaveFolder() then
            notify("Could not create the " .. SAVE_DIR .. " folder.", "error", 3.5)
            return
        end
        local data = serializeProject()
        if not data then
            notify("Nothing to save — no project ScreenGuis found.", "warn", 2.5)
            return
        end
        local okEncode, encoded = pcall(function()
            return HttpService:JSONEncode(data)
        end)
        if not okEncode or type(encoded) ~= "string" then
            notify("Failed to encode the save data.", "error", 3)
            return
        end
        local path = SAVE_DIR .. "/" .. name
        local okWrite, err = pcall(Executor.writefile, path, encoded)
        if okWrite then
            notify("Saved: " .. path, "success", 3)
            dialog.Visible = false
        else
            notify("Save failed: " .. tostring(err), "error", 3.5)
        end
    end)

    function Editor.openSave()
        pcall(function()
            local mp, ms = UI.main.AbsolutePosition, UI.main.AbsoluteSize
            dialog.Position = UDim2.fromOffset(
                math.floor(mp.X + (ms.X - 360) / 2),
                math.floor(mp.Y + (ms.Y - 180) / 2)
            )
        end)
        dialog.Visible = true
        task.defer(function()
            pcall(function() nameBox:CaptureFocus() end)
        end)
    end

    table.insert(UI.windows, dialog)
end

-- Load dialog ----------------------------------------------------------------
do
    local dialog = create("Frame", {
        Name = "LoadDialog",
        Size = UDim2.fromOffset(380, 400),
        Position = UDim2.fromOffset(140, 110),
        BackgroundColor3 = THEME.Window,
        BorderSizePixel = 0,
        Visible = false,
        Active = true,
        ZIndex = 60,
    }, Overlay)
    create("UICorner", { CornerRadius = UDim.new(0, 8) }, dialog)
    create("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, dialog)

    create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(14, 0),
        Size = UDim2.new(1, -150, 0, 32),
        Text = "Load Project — " .. SAVE_DIR,
        TextColor3 = THEME.Text,
        Font = Enum.Font.GothamMedium,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 61,
    }, dialog)
    do
        local closeButton = create("TextButton", {
            Size = UDim2.fromOffset(26, 20),
            Position = UDim2.new(1, -34, 0, 6),
            BackgroundColor3 = THEME.Control,
            BorderSizePixel = 0,
            Text = "×",
            TextColor3 = THEME.Text,
            Font = Enum.Font.GothamBold,
            TextSize = 12,
            AutoButtonColor = false,
            ZIndex = 61,
        }, dialog)
        create("UICorner", { CornerRadius = UDim.new(0, 4) }, closeButton)
        closeButton.MouseEnter:Connect(function() closeButton.BackgroundColor3 = THEME.ControlHover end)
        closeButton.MouseLeave:Connect(function() closeButton.BackgroundColor3 = THEME.Control end)
        closeButton.Activated:Connect(function() dialog.Visible = false end)
    end

    local listScroll = create("ScrollingFrame", {
        Position = UDim2.fromOffset(8, 38),
        Size = UDim2.new(1, -16, 1, -106),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = THEME.ControlHover,
        ElasticBehavior = Enum.ElasticBehavior.Never,
        ZIndex = 61,
    }, dialog)
    create("UIListLayout", {
        Padding = UDim.new(0, 2),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, listScroll)

    create("TextLabel", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 8, 1, -58),
        Size = UDim2.new(1, -16, 0, 30),
        BackgroundTransparency = 1,
        Text = "Every file in the folder is listed — .lua, .luau, .txt or none,\nthey all load. Loading replaces the current project.",
        TextColor3 = THEME.TextDim,
        Font = Enum.Font.Gotham,
        TextSize = 10,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 61,
    }, dialog)

    local refreshButton = create("TextButton", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 8, 1, -30),
        Size = UDim2.fromOffset(84, 24),
        BackgroundColor3 = THEME.Control,
        BorderSizePixel = 0,
        Text = "Refresh",
        TextColor3 = THEME.Text,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        AutoButtonColor = false,
        ZIndex = 61,
    }, dialog)
    create("UICorner", { CornerRadius = UDim.new(0, 5) }, refreshButton)

    local function addFileRow(labelText, order, onClick)
        local btn = create("TextButton", {
            Size = UDim2.new(1, 0, 0, 26),
            BackgroundColor3 = THEME.Control,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Text = "",
            LayoutOrder = order,
            ZIndex = 61,
        }, listScroll)
        local dot = create("Frame", {
            Size = UDim2.fromOffset(10, 10),
            Position = UDim2.fromOffset(8, 8),
            BackgroundColor3 = THEME.Good,
            BorderSizePixel = 0,
            ZIndex = 62,
        }, btn)
        create("UICorner", { CornerRadius = UDim.new(0, 2) }, dot)
        create("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(26, 0),
            Size = UDim2.new(1, -34, 1, 0),
            Text = labelText,
            TextColor3 = Color3.fromRGB(205, 205, 214),
            Font = Enum.Font.Gotham,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            ZIndex = 62,
        }, btn)
        btn.MouseEnter:Connect(function()
            btn.BackgroundTransparency = 0
        end)
        btn.MouseLeave:Connect(function()
            btn.BackgroundTransparency = 1
        end)
        btn.Activated:Connect(onClick)
    end

    local function addInfoRow(text, order)
        create("TextLabel", {
            Size = UDim2.new(1, 0, 0, 26),
            BackgroundTransparency = 1,
            Text = text,
            TextColor3 = THEME.TextDim,
            Font = Enum.Font.Gotham,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextWrapped = true,
            LayoutOrder = order,
            ZIndex = 62,
        }, listScroll)
    end

    local function loadFile(path, displayName)
        if not FS.readfile then
            notify("readfile is not available on this executor.", "warn", 3)
            return
        end
        local okRead, content = pcall(FS.readfile, path)
        if not okRead or type(content) ~= "string" then
            notify("Could not read file: " .. displayName, "error", 3)
            return
        end
        local okDecode, data = pcall(function()
            return HttpService:JSONDecode(content)
        end)
        if not okDecode or typeof(data) ~= "table" then
            notify("Not a GUI Creator save file: " .. displayName, "error", 3.5)
            return
        end
        local created = replaceProjectWith(data)
        dialog.Visible = false
        notify(("Loaded '%s' — %d ScreenGui(s) rebuilt."):format(displayName, created), "success", 3)
    end

    local function refreshList()
        for _, child in ipairs(listScroll:GetChildren()) do
            if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
                child:Destroy()
            end
        end
        local order = 0
        if not Executor.writefile then
            order += 1
            addInfoRow("writefile is not available on this executor.", order)
            return
        end
        ensureSaveFolder()
        if not FS.listfiles then
            order += 1
            addInfoRow("listfiles is not available on this executor.", order)
            return
        end
        local okList, files = pcall(FS.listfiles, SAVE_DIR)
        if not okList or typeof(files) ~= "table" then
            order += 1
            addInfoRow("Could not read the " .. SAVE_DIR .. " folder.", order)
            return
        end
        local entries = {}
        for _, path in ipairs(files) do
            if type(path) == "string" and path ~= "" then
                local isFile = true
                if FS.isfile then
                    local okFile, fileResult = pcall(FS.isfile, path)
                    if okFile and fileResult == false then
                        isFile = false
                    end
                end
                local displayName = path:gsub("^" .. SAVE_DIR .. "/", ""):gsub("^/", "")
                if isFile and displayName ~= "" and displayName:sub(1, 1) ~= "." then
                    table.insert(entries, { path = path, name = displayName })
                end
            end
        end
        table.sort(entries, function(a, b)
            return a.name:lower() < b.name:lower()
        end)
        if #entries == 0 then
            order += 1
            addInfoRow("No saves yet — click Save to create one.", order)
            return
        end
        for _, entry in ipairs(entries) do
            order += 1
            addFileRow(entry.name, order, function()
                loadFile(entry.path, entry.name)
            end)
        end
    end

    refreshButton.Activated:Connect(refreshList)

    function Editor.openLoad()
        pcall(function()
            local mp, ms = UI.main.AbsolutePosition, UI.main.AbsoluteSize
            dialog.Position = UDim2.fromOffset(
                math.floor(mp.X + (ms.X - 380) / 2),
                math.floor(mp.Y + (ms.Y - 400) / 2)
            )
        end)
        refreshList()
        dialog.Visible = true
    end

    table.insert(UI.windows, dialog)
end

-- //////////////////////////////////////////////////////////////////////////
-- ADD INSTANCE DIALOG (searchable class picker, supports LocalScript etc.)
-- //////////////////////////////////////////////////////////////////////////

local INSTANCE_CATALOG = {
    -- GUI
    { class = "ScreenGui",      category = "GUI" },
    { class = "Frame",          category = "GUI" },
    { class = "ScrollingFrame", category = "GUI" },
    { class = "CanvasGroup",    category = "GUI" },
    { class = "ViewportFrame",  category = "GUI" },
    { class = "TextLabel",      category = "GUI" },
    { class = "TextButton",     category = "GUI" },
    { class = "TextBox",        category = "GUI" },
    { class = "ImageLabel",     category = "GUI" },
    { class = "ImageButton",    category = "GUI" },
    { class = "VideoFrame",     category = "GUI" },
    { class = "UICorner",       category = "GUI" },
    { class = "UIStroke",       category = "GUI" },
    { class = "UIGradient",     category = "GUI" },
    { class = "UIListLayout",   category = "GUI" },
    { class = "UIGridLayout",   category = "GUI" },
    { class = "UITableLayout",  category = "GUI" },
    { class = "UIPageLayout",   category = "GUI" },
    { class = "UIPadding",      category = "GUI" },
    { class = "UIScale",        category = "GUI" },
    { class = "UISizeConstraint",        category = "GUI" },
    { class = "UITextSizeConstraint",    category = "GUI" },
    { class = "UIAspectRatioConstraint", category = "GUI" },
    -- Scripts (server Scripts intentionally excluded)
    { class = "LocalScript",  category = "Scripts" },
    { class = "ModuleScript", category = "Scripts" },
    -- Values
    { class = "StringValue",      category = "Values" },
    { class = "IntValue",         category = "Values" },
    { class = "NumberValue",      category = "Values" },
    { class = "BoolValue",        category = "Values" },
    { class = "ObjectValue",      category = "Values" },
    { class = "Color3Value",      category = "Values" },
    { class = "Vector3Value",     category = "Values" },
    { class = "CFrameValue",      category = "Values" },
    { class = "BrickColorValue",  category = "Values" },
    { class = "RayValue",         category = "Values" },
    -- Other
    { class = "Folder", category = "Other" },
    { class = "Sound",  category = "Other" },
}

-- Validates that a class name can actually be instantiated on this client.
local function isClassCreatable(className)
    local ok, probe = pcall(Instance.new, className)
    if ok and probe then
        pcall(function() probe:Destroy() end)
        return true
    end
    return false
end

do
    local dialog = create("Frame", {
        Name = "AddInstanceDialog",
        Size = UDim2.fromOffset(380, 400),
        Position = UDim2.fromOffset(140, 110),
        BackgroundColor3 = THEME.Window,
        BorderSizePixel = 0,
        Visible = false,
        Active = true,
        ZIndex = 60,
    }, Overlay)
    create("UICorner", { CornerRadius = UDim.new(0, 8) }, dialog)
    create("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, dialog)

    -- Header
    create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(14, 0),
        Size = UDim2.new(1, -110, 0, 32),
        Text = "Add Instance",
        TextColor3 = THEME.Text,
        Font = Enum.Font.GothamMedium,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 61,
    }, dialog)
    do
        local closeButton = create("TextButton", {
            Size = UDim2.fromOffset(26, 20),
            Position = UDim2.new(1, -34, 0, 6),
            BackgroundColor3 = THEME.Control,
            BorderSizePixel = 0,
            Text = "×",
            TextColor3 = THEME.Text,
            Font = Enum.Font.GothamBold,
            TextSize = 12,
            AutoButtonColor = false,
            ZIndex = 61,
        }, dialog)
        create("UICorner", { CornerRadius = UDim.new(0, 4) }, closeButton)
        closeButton.MouseEnter:Connect(function() closeButton.BackgroundColor3 = THEME.ControlHover end)
        closeButton.MouseLeave:Connect(function() closeButton.BackgroundColor3 = THEME.Control end)
        closeButton.Activated:Connect(function() dialog.Visible = false end)
    end

    -- Search box
    local searchBox = create("TextBox", {
        Position = UDim2.fromOffset(8, 36),
        Size = UDim2.new(1, -16, 0, 28),
        BackgroundColor3 = THEME.Control,
        TextColor3 = THEME.Text,
        PlaceholderText = "Search or type a class name (e.g. LocalScript)",
        PlaceholderColor3 = THEME.TextDim,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        Text = "",
        ClearTextOnFocus = false,
        BorderSizePixel = 0,
        ZIndex = 61,
    }, dialog)
    create("UICorner", { CornerRadius = UDim.new(0, 5) }, searchBox)
    create("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, searchBox)
    create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 6) }, searchBox)

    -- Result list
    local listScroll = create("ScrollingFrame", {
        Position = UDim2.fromOffset(8, 70),
        Size = UDim2.new(1, -16, 1, -96),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = THEME.ControlHover,
        ElasticBehavior = Enum.ElasticBehavior.Never,
        ZIndex = 61,
    }, dialog)
    create("UIListLayout", {
        Padding = UDim.new(0, 2),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, listScroll)

    create("TextLabel", {
        Position = UDim2.new(0, 8, 1, -22),
        Size = UDim2.new(1, -16, 0, 18),
        BackgroundTransparency = 1,
        Text = "Tip: type ANY class name and press Enter to create it.",
        TextColor3 = THEME.TextDim,
        Font = Enum.Font.Gotham,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 61,
    }, dialog)

    local function addListRow(scroll, labelText, categoryText, order, onClick, dotColor)
        local btn = create("TextButton", {
            Size = UDim2.new(1, 0, 0, 26),
            BackgroundColor3 = THEME.Control,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Text = "",
            LayoutOrder = order,
            ZIndex = 61,
        }, scroll)
        local dot = create("Frame", {
            Size = UDim2.fromOffset(10, 10),
            Position = UDim2.fromOffset(8, 8),
            BackgroundColor3 = dotColor or CLASS_COLORS[labelText] or THEME.TextDim,
            BorderSizePixel = 0,
            ZIndex = 62,
        }, btn)
        create("UICorner", { CornerRadius = UDim.new(0, 2) }, dot)
        create("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(26, 0),
            Size = UDim2.new(1, -110, 1, 0),
            Text = labelText,
            TextColor3 = Color3.fromRGB(205, 205, 214),
            Font = Enum.Font.Gotham,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            ZIndex = 62,
        }, btn)
        if categoryText then
            create("TextLabel", {
                BackgroundTransparency = 1,
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, -6, 0, 0),
                Size = UDim2.fromOffset(96, 26),
                Text = categoryText,
                TextColor3 = THEME.TextDim,
                Font = Enum.Font.Gotham,
                TextSize = 10,
                TextXAlignment = Enum.TextXAlignment.Right,
                TextTruncate = Enum.TextTruncate.AtEnd,
                ZIndex = 62,
            }, btn)
        end
        btn.MouseEnter:Connect(function()
            btn.BackgroundTransparency = 0
        end)
        btn.MouseLeave:Connect(function()
            btn.BackgroundTransparency = 1
        end)
        btn.Activated:Connect(onClick)
        return btn
    end

    local function trySpawnFromText(raw)
        local className = tostring(raw):gsub("^%s+", ""):gsub("%s+$", "")
        if className == "" then
            return
        end
        -- Server scripts are intentionally unsupported.
        if className:lower() == "script" or className:lower() == "corescript" then
            notify("Only LocalScript and ModuleScript are supported — server Scripts won't affect everyone.", "warn", 3.5)
            return
        end
        -- Exact catalog match first (guarantees friendly handling).
        for _, entry in ipairs(INSTANCE_CATALOG) do
            if entry.class:lower() == className:lower() then
                Editor.spawnClass(entry.class)
                return
            end
        end
        -- Free-text path: validate the class is creatable, then spawn it.
        if isClassCreatable(className) then
            Editor.spawnClass(className)
        else
            notify("Unknown or restricted class: " .. className, "error", 3)
        end
    end

    local function rebuildList()
        for _, child in ipairs(listScroll:GetChildren()) do
            if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
                child:Destroy()
            end
        end

        local query = tostring(searchBox.Text):lower()
        query = query:gsub("^%s+", ""):gsub("%s+$", "")

        local order = 0
        local matchCount = 0

        for _, entry in ipairs(INSTANCE_CATALOG) do
            if query == "" or entry.class:lower():find(query, 1, true) then
                matchCount += 1
                order += 1
                local class = entry.class
                addListRow(listScroll, class, entry.category, order, function()
                    Editor.spawnClass(class)
                end)
            end
        end

        -- No catalog match: offer to create the typed name as a custom class.
        if matchCount == 0 and query ~= "" then
            local raw = tostring(searchBox.Text):gsub("^%s+", ""):gsub("%s+$", "")
            order += 1
            addListRow(listScroll, "+  Create custom class \"" .. raw .. "\"", "Custom", order, function()
                trySpawnFromText(raw)
            end, THEME.Accent)
        end
    end

    searchBox:GetPropertyChangedSignal("Text"):Connect(rebuildList)
    searchBox.FocusLost:Connect(function(enterPressed)
        if not enterPressed then return end
        trySpawnFromText(searchBox.Text)
        task.defer(function()
            pcall(function() searchBox:CaptureFocus() end)
        end)
    end)

    function Editor.openAddInstance()
        -- Center over the main window.
        pcall(function()
            local mp, ms = UI.main.AbsolutePosition, UI.main.AbsoluteSize
            dialog.Position = UDim2.fromOffset(
                math.floor(mp.X + (ms.X - 380) / 2),
                math.floor(mp.Y + (ms.Y - 400) / 2)
            )
        end)
        searchBox.Text = ""
        rebuildList()
        dialog.Visible = true
        task.defer(function()
            pcall(function() searchBox:CaptureFocus() end)
        end)
    end

    table.insert(UI.windows, dialog)
end

-- //////////////////////////////////////////////////////////////////////////
-- EDITOR ACTIONS
-- //////////////////////////////////////////////////////////////////////////

function Editor.select(inst)
    if inst ~= nil and (typeof(inst) ~= "Instance" or inst.Parent == nil) then
        inst = nil
    end
    State.selected = inst
    refreshExplorerSelection()
    PropPanel.build(inst)
    updateStatus()
end

function Editor.deleteSelected()
    local inst = State.selected
    if not isValidTarget(inst) then
        notify("Nothing selected.", "warn", 2)
        return
    end
    -- ScreenGui protection: the last remaining ScreenGui cannot be deleted.
    if inst:IsA("ScreenGui") then
        local remaining = 0
        for _, sg in ipairs(getProjectScreenGuis()) do
            if sg ~= inst then
                remaining += 1
            end
        end
        if remaining == 0 then
            notify("Protected: the project must keep at least one ScreenGui.", "error", 3.5)
            return
        end
    end
    local name = inst.Name
    local ok = pcall(function() inst:Destroy() end)
    if ok then
        Editor.select(nil)
        invalidateExplorer()
        notify(("Deleted '%s'"):format(name), "info", 2)
    else
        notify("Failed to delete instance.", "error", 2.5)
    end
end

function Editor.duplicateSelected()
    local inst = State.selected
    if not isValidTarget(inst) then
        notify("Nothing selected.", "warn", 2)
        return
    end
    local ok, clone = pcall(function() return inst:Clone() end)
    if not ok or not clone then
        notify("Cannot duplicate this instance.", "error", 2.5)
        return
    end
    clone.Name = uniqueName(inst.Name)
    pcall(function() clone.Parent = inst.Parent end)
    if clone:IsA("GuiObject") then
        pcall(function()
            local p = clone.Position
            clone.Position = UDim2.new(p.X.Scale, p.X.Offset + 14, p.Y.Scale, p.Y.Offset + 14)
        end)
    end
    invalidateExplorer()
    Editor.select(clone)
end

function Editor.setEditMode(enabled)
    State.editMode = enabled and true or false
    if UI.modeButton then
        UI.modeButton.Text = State.editMode and "Mode: Edit" or "Mode: Test"
    end
    syncSelectionVisuals()
    updateStatus()
    notify(State.editMode and "Edit mode enabled" or "Test mode enabled — click your GUI to interact", "info")
end

-- "Put on CoreGui" toggle: red = off (PlayerGui), green = on (protected).
function Editor.refreshCoreGuiToggle()
    if UI.coreGuiButton then
        UI.coreGuiButton.BackgroundColor3 = State.coreGuiMode and THEME.Good or THEME.Danger
        UI.coreGuiButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    end
end

function Editor.setCoreGuiMode(enabled)
    enabled = enabled and true or false
    if enabled == State.coreGuiMode then
        Editor.refreshCoreGuiToggle()
        return
    end
    if enabled and ProtectedParent == PlayerGui then
        State.coreGuiMode = false
        Editor.refreshCoreGuiToggle()
        notify("CoreGui is not accessible on this executor — the project stays in PlayerGui.", "error", 4)
        return
    end
    local target = enabled and ProtectedParent or PlayerGui
    local moved, failed = 0, 0
    for _, sg in ipairs(getProjectScreenGuis()) do
        local ok = pcall(function() sg.Parent = target end)
        if ok and sg.Parent == target then
            moved += 1
        else
            failed += 1
        end
    end
    if moved == 0 and failed > 0 then
        Editor.refreshCoreGuiToggle()
        notify("Could not move the project ScreenGuis — mode unchanged.", "error", 3.5)
        return
    end
    PROJECT_PARENT = target
    State.coreGuiMode = enabled
    invalidateExplorer()
    local guis = getProjectScreenGuis()
    if guis[1] then
        Editor.select(guis[1])
    else
        Editor.select(nil)
    end
    Editor.refreshCoreGuiToggle()
    notify(
        ("%d ScreenGui(s) now live in %s — new ones spawn there too."):format(
            moved, enabled and "CoreGui (protected container)" or "PlayerGui"),
        enabled and "success" or "info", 3.5)
end

function Editor.destroy()
    for _, connection in ipairs(Connections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(Connections)
    pcall(function() Overlay:Destroy() end)
    print("[StudioGUI Creator] Editor closed. Your GUI instances remain in PlayerGui.")
end

-- //////////////////////////////////////////////////////////////////////////
-- AI ASSISTANT (Gemini) — reads the live UI, applies Luau code blocks,
-- fetches its model list live with the user's API key (nothing hardcoded).
-- //////////////////////////////////////////////////////////////////////////

do
    local AI = {
        settings = {
            apiKey       = "",
            model        = nil,   -- picked from the LIVE fetched list only
            instructions = "",
            thinking     = "dynamic",
            temperature  = 0.8,
            context      = true,  -- attach the current UI tree to every request
            allowRunLua  = false, -- gate for the optional run_lua tool
        },
        models         = nil,       -- nil = never fetched successfully
        fetchingModels = false,
        history        = {},        -- { { role = "user"|"model", text = "..." } }
        waiting        = false,
    }
    Editor.AI = AI

    -- Defined in the BUILT-IN TOOLS section below; referenced by the request
    -- builder, so it needs a forward declaration.
    local buildToolDeclarations

    local AI_SETTINGS_FILE = "GUI_CREATOR_AI.json"
    local GEMINI_BASE = "https://generativelanguage.googleapis.com/v1beta"

    ------------------------------------------------------------------
    -- Settings persistence (GUI_CREATOR_AI.json next to the saves)
    ------------------------------------------------------------------
    local function saveAiSettings()
        if not Executor.writefile then return end
        local ok, encoded = pcall(function() return HttpService:JSONEncode(AI.settings) end)
        if ok and type(encoded) == "string" then
            pcall(Executor.writefile, AI_SETTINGS_FILE, encoded)
        end
    end

    local function loadAiSettings()
        if not FS.readfile then return end
        if FS.isfile then
            local ok, exists = pcall(FS.isfile, AI_SETTINGS_FILE)
            if ok and not exists then return end
        end
        local okRead, raw = pcall(FS.readfile, AI_SETTINGS_FILE)
        if not okRead or type(raw) ~= "string" or raw == "" then return end
        local okDecode, data = pcall(function() return HttpService:JSONDecode(raw) end)
        if not (okDecode and type(data) == "table") then return end
        local s = AI.settings
        if type(data.apiKey) == "string" then s.apiKey = data.apiKey end
        if type(data.model) == "string" and data.model ~= "" then s.model = data.model end
        if type(data.instructions) == "string" then s.instructions = data.instructions end
        if type(data.thinking) == "string" then s.thinking = data.thinking end
        if type(data.temperature) == "number" then s.temperature = data.temperature end
        if type(data.context) == "boolean" then s.context = data.context end
        if type(data.allowRunLua) == "boolean" then s.allowRunLua = data.allowRunLua end
    end
    loadAiSettings()

    ------------------------------------------------------------------
    -- HTTP helper (request / http_request / syn.request / http.request)
    ------------------------------------------------------------------
    local function httpJson(url, method, bodyTable)
        if not Executor.http then
            return nil, "This executor has no HTTP API (request / http_request missing)."
        end
        local opts = {
            Url = url,
            Method = method or "GET",
            Headers = { ["Content-Type"] = "application/json" },
        }
        if bodyTable ~= nil then
            local okEnc, payload = pcall(function() return HttpService:JSONEncode(bodyTable) end)
            if not okEnc then
                return nil, "JSON encode failed: " .. tostring(payload)
            end
            opts.Body = payload
        end
        local ok, res = pcall(Executor.http, opts)
        if not ok then
            return nil, tostring(res)
        end
        if type(res) ~= "table" then
            return nil, "Invalid HTTP response object."
        end
        local okFlag = res.Success
        if okFlag == nil then okFlag = res.success end
        if okFlag == nil then okFlag = res.ResponseSuccess end
        if okFlag == false then
            local errMsg = res.ErrorMessage or res.errorMessage or res.Exception or res.error
            return nil, "HTTP request failed" .. (errMsg and (": " .. tostring(errMsg)) or ".")
        end
        local bodyText = res.Body or res.body or ""
        local code = tonumber(res.StatusCode or res.statusCode) or 0
        return { body = bodyText, code = code }
    end

    ------------------------------------------------------------------
    -- Generic list popup (same look as the enum Dropdown, but any items)
    ------------------------------------------------------------------
    local ListPopup = {}
    do
        local catcher = create("TextButton", {
            Name = "AIListPopupCatcher",
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Text = "",
            AutoButtonColor = false,
            Visible = false,
            ZIndex = 80,
        }, Overlay)
        local listFrame = create("ScrollingFrame", {
            Name = "AIListPopupList",
            BackgroundColor3 = THEME.PanelAlt,
            BorderSizePixel = 0,
            Visible = false,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            ScrollBarThickness = 4,
            ScrollBarImageColor3 = THEME.ControlHover,
            ElasticBehavior = Enum.ElasticBehavior.Never,
            ZIndex = 81,
        }, Overlay)
        create("UICorner", { CornerRadius = UDim.new(0, 6) }, listFrame)
        create("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, listFrame)
        create("UIListLayout", {
            Padding = UDim.new(0, 2),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, listFrame)
        create("UIPadding", {
            PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4),
            PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4),
        }, listFrame)

        local function close()
            catcher.Visible = false
            listFrame.Visible = false
            for _, child in ipairs(listFrame:GetChildren()) do
                if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
                    child:Destroy()
                end
            end
        end
        catcher.Activated:Connect(close)

        -- items: array of { id = string, label = string } — the caller builds
        -- this list at runtime (model fetch / thinking levels), nothing hardcoded.
        function ListPopup.open(anchorPos, anchorSize, items, currentValue, onSelect)
            close()
            if type(items) ~= "table" or #items == 0 then
                notify("Nothing to list yet — fetch first.", "warn", 2.5)
                return
            end
            local width = math.max((anchorSize and anchorSize.X) or 200, 220)
            local rowHeight = 22
            local listHeight = math.min(#items * (rowHeight + 2) + 10, 280)
            local px, py = anchorPos.X, anchorPos.Y + (anchorSize and anchorSize.Y or 20) + 4
            pcall(function()
                local viewport = workspace.CurrentCamera.ViewportSize
                if px + width > viewport.X - 8 then px = viewport.X - 8 - width end
                if px < 8 then px = 8 end
                if py + listHeight > viewport.Y - 8 then py = anchorPos.Y - listHeight - 4 end
                if py < 8 then py = 8 end
            end)
            listFrame.Position = UDim2.fromOffset(math.floor(px), math.floor(py))
            listFrame.Size = UDim2.fromOffset(width, listHeight)

            for order, item in ipairs(items) do
                local id = tostring(item.id)
                local label = tostring(item.label or id)
                local isCurrent = (id == currentValue)
                local rowBtn = create("TextButton", {
                    Size = UDim2.new(1, 0, 0, rowHeight),
                    BackgroundColor3 = isCurrent and THEME.Selection or THEME.Control,
                    BackgroundTransparency = isCurrent and 0 or 1,
                    BorderSizePixel = 0,
                    AutoButtonColor = false,
                    Text = label,
                    TextColor3 = isCurrent and THEME.Text or Color3.fromRGB(205, 205, 214),
                    Font = Enum.Font.Gotham,
                    TextSize = 12,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    LayoutOrder = order,
                    ZIndex = 82,
                }, listFrame)
                create("UIPadding", { PaddingLeft = UDim.new(0, 8) }, rowBtn)
                rowBtn.MouseEnter:Connect(function()
                    rowBtn.BackgroundColor3 = THEME.ControlHover
                    rowBtn.BackgroundTransparency = 0
                end)
                rowBtn.MouseLeave:Connect(function()
                    if id == currentValue then
                        rowBtn.BackgroundColor3 = THEME.Selection
                        rowBtn.BackgroundTransparency = 0
                    else
                        rowBtn.BackgroundColor3 = THEME.Control
                        rowBtn.BackgroundTransparency = 1
                    end
                end)
                rowBtn.Activated:Connect(function()
                    close()
                    onSelect(id)
                end)
            end
            catcher.Visible = true
            listFrame.Visible = true
        end
    end

    ------------------------------------------------------------------
    -- Window frame + view containers (controls assigned below)
    ------------------------------------------------------------------
    local aiWindow, chatView, settingsView
    local statusLabel, chatScroll, inputBox, sendButton
    local keyBox, modelButton, modelCountLabel, thinkingButton, tempBox
    local contextButton, allowLuaButton, instrBox, saveButton

    aiWindow = create("Frame", {
        Name = "AIAssistant",
        Size = UDim2.fromOffset(520, 520),
        Position = UDim2.fromOffset(430, 110),
        BackgroundColor3 = THEME.Window,
        BorderSizePixel = 0,
        Visible = false,
        Active = true,
        ZIndex = 60,
    }, Overlay)
    create("UICorner", { CornerRadius = UDim.new(0, 8) }, aiWindow)
    create("UIStroke", { Color = THEME.Accent, Thickness = 1 }, aiWindow)

    -- Title bar (draggable through its own handlers).
    local aiTitleBar = create("Frame", {
        Name = "AITitleBar",
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundColor3 = THEME.PanelAlt,
        BorderSizePixel = 0,
        Active = true,
        ZIndex = 61,
    }, aiWindow)
    create("UICorner", { CornerRadius = UDim.new(0, 8) }, aiTitleBar)

    local aiDot = create("Frame", {
        Size = UDim2.fromOffset(10, 10),
        Position = UDim2.fromOffset(12, 11),
        BackgroundColor3 = THEME.Good,
        BorderSizePixel = 0,
        ZIndex = 62,
    }, aiTitleBar)
    create("UICorner", { CornerRadius = UDim.new(0, 3) }, aiDot)

    create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(30, 0),
        Size = UDim2.new(1, -260, 1, 0),
        Text = "AI Assistant  —  Gemini",
        TextColor3 = THEME.Text,
        Font = Enum.Font.GothamMedium,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 62,
    }, aiTitleBar)

    local function aiHeaderButton(text, offsetX, onClick, width)
        local btn = create("TextButton", {
            Size = UDim2.fromOffset(width or 64, 20),
            Position = UDim2.new(1, offsetX, 0.5, -10),
            BackgroundColor3 = THEME.Control,
            BorderSizePixel = 0,
            Text = text,
            TextColor3 = THEME.Text,
            Font = Enum.Font.GothamMedium,
            TextSize = 12,
            AutoButtonColor = false,
            ZIndex = 62,
        }, aiTitleBar)
        create("UICorner", { CornerRadius = UDim.new(0, 4) }, btn)
        btn.MouseEnter:Connect(function() btn.BackgroundColor3 = THEME.ControlHover end)
        btn.MouseLeave:Connect(function() btn.BackgroundColor3 = THEME.Control end)
        if onClick then
            btn.Activated:Connect(onClick)
        end
        return btn
    end

    local chatDrag = nil
    aiTitleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            chatDrag = {
                startMouse = inputScreenPos(input),
                startPosition = aiWindow.Position,
            }
        end
    end)
    trackConnection(UserInputService.InputChanged:Connect(function(input)
        if not chatDrag then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        local delta = inputScreenPos(input) - chatDrag.startMouse
        aiWindow.Position = UDim2.fromOffset(
            math.floor(chatDrag.startPosition.X.Offset + delta.X),
            math.floor(chatDrag.startPosition.Y.Offset + delta.Y))
    end))
    trackConnection(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            chatDrag = nil
        end
    end))

    ------------------------------------------------------------------
    -- CHAT VIEW
    ------------------------------------------------------------------
    chatView = create("Frame", {
        Name = "ChatView",
        Position = UDim2.fromOffset(0, 32),
        Size = UDim2.new(1, 0, 1, -32),
        BackgroundTransparency = 1,
        ZIndex = 61,
    }, aiWindow)

    statusLabel = create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(10, 4),
        Size = UDim2.new(1, -20, 0, 18),
        Text = "Provider: Gemini",
        TextColor3 = THEME.TextDim,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 62,
    }, chatView)

    chatScroll = create("ScrollingFrame", {
        Name = "ChatLog",
        Position = UDim2.fromOffset(8, 26),
        Size = UDim2.new(1, -16, 1, -70),
        BackgroundColor3 = THEME.Panel,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = THEME.ControlHover,
        ElasticBehavior = Enum.ElasticBehavior.Never,
        ZIndex = 62,
    }, chatView)
    create("UICorner", { CornerRadius = UDim.new(0, 6) }, chatScroll)
    create("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, chatScroll)
    create("UIListLayout", {
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, chatScroll)
    create("UIPadding", {
        PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6),
        PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
    }, chatScroll)

    inputBox = create("TextBox", {
        Name = "AIInput",
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 8, 1, -8),
        Size = UDim2.new(1, -78, 0, 32),
        BackgroundColor3 = THEME.Control,
        TextColor3 = THEME.Text,
        PlaceholderText = "Ask the AI to design or modify your GUI...",
        PlaceholderColor3 = THEME.TextDim,
        Font = Enum.Font.Gotham,
        TextSize = 13,
        Text = "",
        ClearTextOnFocus = false,
        BorderSizePixel = 0,
        ZIndex = 62,
    }, chatView)
    create("UICorner", { CornerRadius = UDim.new(0, 6) }, inputBox)
    create("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, inputBox)
    create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 6) }, inputBox)

    sendButton = create("TextButton", {
        Name = "AISend",
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -8, 1, -8),
        Size = UDim2.fromOffset(62, 32),
        BackgroundColor3 = THEME.Accent,
        BorderSizePixel = 0,
        Text = "Send",
        TextColor3 = THEME.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        AutoButtonColor = false,
        ZIndex = 62,
    }, chatView)
    create("UICorner", { CornerRadius = UDim.new(0, 6) }, sendButton)

    ------------------------------------------------------------------
    -- SETTINGS VIEW (API key, live models, thinking, temperature, ...)
    ------------------------------------------------------------------
    settingsView = create("Frame", {
        Name = "AISettings",
        Position = UDim2.fromOffset(0, 32),
        Size = UDim2.new(1, 0, 1, -32),
        BackgroundTransparency = 1,
        Visible = false,
        ZIndex = 61,
    }, aiWindow)

    local function settingsLabel(x, y, w, text)
        create("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(x, y),
            Size = UDim2.fromOffset(w or 220, 18),
            Text = text,
            TextColor3 = THEME.TextDim,
            Font = Enum.Font.GothamMedium,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 62,
        }, settingsView)
    end

    local function settingsBox(y, height, placeholder, multiLine)
        local box = create("TextBox", {
            Position = UDim2.fromOffset(12, y),
            Size = UDim2.new(1, -24, 0, height),
            BackgroundColor3 = THEME.Control,
            TextColor3 = THEME.Text,
            PlaceholderText = placeholder,
            PlaceholderColor3 = THEME.TextDim,
            Font = multiLine and Enum.Font.Code or Enum.Font.Gotham,
            TextSize = 12,
            Text = "",
            ClearTextOnFocus = false,
            MultiLine = multiLine or false,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = multiLine and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
            TextWrapped = false,
            BorderSizePixel = 0,
            ZIndex = 62,
        }, settingsView)
        create("UICorner", { CornerRadius = UDim.new(0, 5) }, box)
        create("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, box)
        create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 6) }, box)
        return box
    end

    -- Provider (fixed to Gemini for now, by design).
    settingsLabel(12, 4, 100, "Provider")
    create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(120, 4),
        Size = UDim2.new(1, -132, 0, 18),
        Text = "Gemini  (only provider for now)",
        TextColor3 = THEME.Text,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 62,
    }, settingsView)

    -- API key.
    settingsLabel(12, 30, 220, "API Key")
    keyBox = settingsBox(50, 28, "Paste your Gemini API key", false)
    create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(14, 82),
        Size = UDim2.new(1, -28, 0, 14),
        Text = "Free keys: aistudio.google.com/apikey  ·  stored locally in GUI_CREATOR_AI.json",
        TextColor3 = THEME.TextDim,
        Font = Enum.Font.Gotham,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 62,
    }, settingsView)

    -- Model (LIVE fetch only — no hardcoded list anywhere).
    settingsLabel(12, 104, 340, "Model  (fetched live with your key — nothing hardcoded)")
    modelButton = create("TextButton", {
        Position = UDim2.fromOffset(12, 124),
        Size = UDim2.new(1, -100, 0, 26),
        BackgroundColor3 = THEME.Control,
        BorderSizePixel = 0,
        Text = "Model: none — fetch below",
        TextColor3 = THEME.Text,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        AutoButtonColor = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 62,
    }, settingsView)
    create("UICorner", { CornerRadius = UDim.new(0, 5) }, modelButton)
    create("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, modelButton)
    create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 6) }, modelButton)

    local refreshModelsButton = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -12, 0, 124),
        Size = UDim2.fromOffset(80, 26),
        BackgroundColor3 = THEME.Accent,
        BorderSizePixel = 0,
        Text = "Refresh",
        TextColor3 = THEME.Text,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        AutoButtonColor = false,
        ZIndex = 62,
    }, settingsView)
    create("UICorner", { CornerRadius = UDim.new(0, 5) }, refreshModelsButton)

    modelCountLabel = create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(14, 154),
        Size = UDim2.new(1, -28, 0, 14),
        Text = "No models fetched yet — click Refresh.",
        TextColor3 = THEME.TextDim,
        Font = Enum.Font.Gotham,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 62,
    }, settingsView)

    -- Thinking level.
    thinkingButton = create("TextButton", {
        Position = UDim2.fromOffset(12, 176),
        Size = UDim2.fromOffset(220, 26),
        BackgroundColor3 = THEME.Control,
        BorderSizePixel = 0,
        Text = "Thinking: Dynamic",
        TextColor3 = THEME.Text,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        AutoButtonColor = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 62,
    }, settingsView)
    create("UICorner", { CornerRadius = UDim.new(0, 5) }, thinkingButton)
    create("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, thinkingButton)
    create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 6) }, thinkingButton)

    -- Temperature.
    settingsLabel(250, 178, 50, "Temp")
    tempBox = create("TextBox", {
        Position = UDim2.fromOffset(300, 176),
        Size = UDim2.fromOffset(80, 26),
        BackgroundColor3 = THEME.Control,
        TextColor3 = THEME.Text,
        PlaceholderText = "0.8",
        PlaceholderColor3 = THEME.TextDim,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        Text = "",
        ClearTextOnFocus = false,
        BorderSizePixel = 0,
        ZIndex = 62,
    }, settingsView)
    create("UICorner", { CornerRadius = UDim.new(0, 5) }, tempBox)
    create("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, tempBox)
    create("UIPadding", { PaddingLeft = UDim.new(0, 8) }, tempBox)

    -- UI context toggle (green on / red off, like the CoreGui toggle).
    contextButton = create("TextButton", {
        Position = UDim2.fromOffset(12, 210),
        Size = UDim2.fromOffset(200, 26),
        BackgroundColor3 = THEME.Good,
        BorderSizePixel = 0,
        Text = "Send UI tree: On",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        AutoButtonColor = false,
        ZIndex = 62,
    }, settingsView)
    create("UICorner", { CornerRadius = UDim.new(0, 5) }, contextButton)

    -- run_lua gate: the AI only receives the run_lua tool when this is green.
    allowLuaButton = create("TextButton", {
        Position = UDim2.fromOffset(222, 210),
        Size = UDim2.fromOffset(180, 26),
        BackgroundColor3 = THEME.Danger,
        BorderSizePixel = 0,
        Text = "Allow AI to run code: Off",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        AutoButtonColor = false,
        ZIndex = 62,
    }, settingsView)
    create("UICorner", { CornerRadius = UDim.new(0, 5) }, allowLuaButton)

    -- Instructions prompt.
    settingsLabel(12, 244, 340, "Instructions Prompt  (extra rules for the AI)")
    instrBox = settingsBox(264, 148, "e.g. 'Always use rounded corners and dark colors'...", true)

    -- Save row.
    saveButton = create("TextButton", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 12, 1, -10),
        Size = UDim2.fromOffset(110, 28),
        BackgroundColor3 = THEME.Accent,
        BorderSizePixel = 0,
        Text = "Save Settings",
        TextColor3 = THEME.Text,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        AutoButtonColor = false,
        ZIndex = 62,
    }, settingsView)
    create("UICorner", { CornerRadius = UDim.new(0, 5) }, saveButton)
    create("TextLabel", {
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -14, 1, -10),
        Size = UDim2.new(1, -160, 0, 28),
        Text = "Settings auto-save after each edit.",
        TextColor3 = THEME.TextDim,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Right,
        TextYAlignment = Enum.TextYAlignment.Center,
        ZIndex = 62,
    }, settingsView)

    ------------------------------------------------------------------
    -- UI CONTEXT (what makes the AI able to READ the current UI)
    ------------------------------------------------------------------
    local function fmtColor(c)
        return ("%d,%d,%d"):format(
            math.floor(c.R * 255 + 0.5),
            math.floor(c.G * 255 + 0.5),
            math.floor(c.B * 255 + 0.5))
    end

    local function fmtUdim2(u)
        return ("{%s,%s},{%s,%s}"):format(
            trimNum(u.X.Scale), trimNum(u.X.Offset),
            trimNum(u.Y.Scale), trimNum(u.Y.Offset))
    end

    local function describeInstance(inst, path)
        local bits = { ('%s [%s] "%s"'):format(path, inst.ClassName, inst.Name) }
        if inst:IsA("GuiObject") then
            table.insert(bits, "Pos=" .. fmtUdim2(inst.Position))
            table.insert(bits, "Size=" .. fmtUdim2(inst.Size))
            table.insert(bits, "BG=" .. fmtColor(inst.BackgroundColor3))
            if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
                table.insert(bits, ("Text=%q"):format(tostring(inst.Text):sub(1, 80)))
                table.insert(bits, "Font=" .. inst.Font.Name)
                table.insert(bits, "TextColor=" .. fmtColor(inst.TextColor3))
                table.insert(bits, "TextSize=" .. trimNum(inst.TextSize))
            end
            if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
                table.insert(bits, "Image=" .. tostring(inst.Image))
            end
            table.insert(bits, "Visible=" .. tostring(inst.Visible))
        elseif inst:IsA("ScreenGui") then
            table.insert(bits, "DisplayOrder=" .. trimNum(inst.DisplayOrder))
        elseif inst:IsA("UICorner") then
            table.insert(bits, "CornerRadius=" .. tostring(inst.CornerRadius))
        elseif inst:IsA("UIStroke") then
            table.insert(bits, "Color=" .. fmtColor(inst.Color))
            table.insert(bits, "Thickness=" .. trimNum(inst.Thickness))
        elseif inst:IsA("UIGradient") then
            local stops = {}
            for _, kp in ipairs(inst.Color.Keypoints) do
                table.insert(stops, fmtColor(kp.Value))
            end
            table.insert(bits, "Colors={" .. table.concat(stops, ";") .. "}")
            table.insert(bits, "Rotation=" .. trimNum(inst.Rotation))
        elseif inst:IsA("LocalScript") or inst:IsA("ModuleScript") then
            local srcLen = 0
            pcall(function() srcLen = #inst.Source end)
            table.insert(bits, "SourceLen=" .. trimNum(srcLen))
        end
        return table.concat(bits, "  ")
    end

    local function buildUiContext()
        local guis = getProjectScreenGuis()
        if #guis == 0 then
            return "(the project is empty — no ScreenGuis yet)"
        end
        local lines = {}
        local nodeCount = 0
        local truncated = false
        local MAX_NODES = 150
        local MAX_DEPTH = 8
        local function walk(inst, prefix, depth)
            if nodeCount >= MAX_NODES or depth > MAX_DEPTH then
                if nodeCount >= MAX_NODES then truncated = true end
                return
            end
            nodeCount += 1
            local path = (prefix == "") and inst.Name or (prefix .. "/" .. inst.Name)
            table.insert(lines, string.rep("  ", depth) .. describeInstance(inst, path))
            for _, child in ipairs(treeChildren(inst)) do
                walk(child, path, depth + 1)
            end
        end
        for _, sg in ipairs(guis) do
            walk(sg, "", 0)
        end
        if truncated then
            table.insert(lines, ("... (tree truncated at %d instances)"):format(MAX_NODES))
        end
        table.insert(lines, 1, "ScreenGuis live under: "
            .. (State.coreGuiMode and "protected container (gethui/CoreGui)" or "PlayerGui")
            .. '.  sgc.find("<RootName>/<Child>/...") addresses instances by path.')
        return table.concat(lines, "\n")
    end

    ------------------------------------------------------------------
    -- SYSTEM PROMPT + REQUEST BUILDING
    ------------------------------------------------------------------
    local BASE_INSTRUCTIONS = [=[You are the built-in AI copilot inside "StudioGUI Creator", a WYSIWYG Roblox GUI editor running in an executor (LocalScript environment, LocalPlayer context).

You have TWO ways to work with the UI:

1) BUILT-IN TOOLS (preferred for direct reads/edits). The editor registers real Luau tools via Gemini function calling. Emit a functionCall and the tool RUNS inside the editor; its result comes back to you automatically and you can then call more tools or answer. Exact tool names:
   list_ui()  find_instance(path)  create_element(class, name?, parent_path?, props?)
   set_properties(path, props)  rename_element(path, new_name)  delete_element(path)
   duplicate_element(path)  select_element(path)  set_script_source(path, source)
   get_script_source(path)  save_project(name)  load_project(name)  list_saves()
   notify_user(text, kind?)   run_lua(code) only exists when "Allow AI to run code" is ON.
   Paths look like "RootName/Child/Sub" — the same paths shown in the CURRENT UI TREE.
   props values are JSON-friendly: "0.5,0,0.1,24" (UDim2), "255,80,40" or "#FF5733" (Color3),
   enum names like "GothamBold" or "Enum.Font.GothamBold", plus numbers and booleans.
   Call find_instance/list_ui first when unsure about a path or a property.

2) LUAU CODE BLOCKS (for logic: loops, math, events, multi-step work). Output complete runnable snippets inside fenced ``` code blocks; the user can Copy them (setclipboard) or Apply them (loadstring runs them instantly). Inside applied code a helper table `sgc` is available:
    sgc.find("RootName/Child/Sub") -> Instance or nil
    sgc.guis() -> table of project ScreenGuis
    sgc.new(class, propsTable, parent) -> Instance
    sgc.select(inst) -> selects it in the editor
    sgc.notify(text, kind) -> toast (kind: info/success/warn/error)
    sgc.path(inst) -> "Root/Child/Sub" path string
  Standard globals (game, workspace, Instance, Enum, UDim2, Color3, Vector2, task, math, table, string, os) are available.

Other rules:
- The CURRENT UI TREE of the user's project is included with every message. Instance paths look like RootName/Child/Sub — that is exactly what tool paths and sgc.find() accept.
- Prefer tools for simple reads/edits; prefer code blocks when real logic is needed. The last remaining ScreenGui can never be deleted.
- After tools change the tree, nothing else is needed — the editor refreshes itself.
- Keep answers short and practical. Avoid markdown decoration other than the code blocks.]=]

    local THINKING_OPTIONS = {
        { id = "dynamic", label = "Dynamic (auto budget)" },
        { id = "off",     label = "Off (no thinking)" },
        { id = "minimal", label = "Minimal" },
        { id = "low",     label = "Low" },
        { id = "medium",  label = "Medium" },
        { id = "high",    label = "High" },
    }

    local function thinkingLabel(id)
        for _, opt in ipairs(THINKING_OPTIONS) do
            if opt.id == id then
                return opt.label
            end
        end
        return tostring(id)
    end

    local function buildSystemPrompt()
        local parts = { BASE_INSTRUCTIONS }
        local custom = AI.settings.instructions
        if type(custom) == "string" and custom:match("%S") then
            table.insert(parts, "THE USER'S EXTRA INSTRUCTIONS (follow them):\n" .. custom)
        end
        if AI.settings.context then
            table.insert(parts, "CURRENT UI TREE:\n" .. buildUiContext())
        end
        return table.concat(parts, "\n\n")
    end

    -- Builds the POST body. `withTools` controls whether the editor's built-in
    -- Luau tools are declared (Gemini function calling). History entries come
    -- in three shapes:
    --   { role = "user"|"model", text = "..." }                  plain turn
    --   { role = "model", text = "...", calls = { {name, args} } } tool request
    --   { role = "user", toolResults = { {name, response} } }      tool results
    local function buildRequestBody(withTools)
        local contents = {}
        local startIdx = math.max(1, #AI.history - 19)
        for i = startIdx, #AI.history do
            local msg = AI.history[i]
            if msg.role == "user" and type(msg.toolResults) == "table" then
                local parts = {}
                for _, tr in ipairs(msg.toolResults) do
                    table.insert(parts, {
                        functionResponse = {
                            name = tostring(tr.name),
                            response = { result = tostring(tr.response or "") },
                        },
                    })
                end
                if #parts > 0 then
                    table.insert(contents, { role = "user", parts = parts })
                end
            elseif msg.role == "model" and type(msg.calls) == "table" and #msg.calls > 0 then
                local parts = {}
                if type(msg.text) == "string" and msg.text ~= "" then
                    table.insert(parts, { text = msg.text })
                end
                for _, call in ipairs(msg.calls) do
                    table.insert(parts, {
                        functionCall = {
                            name = tostring(call.name),
                            args = (type(call.args) == "table" and call.args) or {},
                        },
                    })
                end
                if #parts > 0 then
                    table.insert(contents, { role = "model", parts = parts })
                end
            elseif msg.role == "user" or msg.role == "model" then
                table.insert(contents, {
                    role = msg.role,
                    parts = { { text = tostring(msg.text or "") } },
                })
            end
        end
        -- Gemini wants the conversation to open with a plain user turn: drop
        -- leading model/tool turns (pruning can split a tool pair), then merge
        -- consecutive PLAIN text turns only — never merge call/response turns.
        while #contents > 0 do
            local first = contents[1]
            if first.role == "user"
                and type(first.parts[1]) == "table"
                and type(first.parts[1].text) == "string" then
                break
            end
            table.remove(contents, 1)
        end
        local merged = {}
        for _, entry in ipairs(contents) do
            local last = merged[#merged]
            local plain = #entry.parts == 1 and type(entry.parts[1].text) == "string"
            if plain and last and last.role == entry.role
                and #last.parts == 1 and type(last.parts[1].text) == "string" then
                last.parts[1].text = last.parts[1].text .. "\n\n" .. entry.parts[1].text
            else
                table.insert(merged, entry)
            end
        end

        local genConfig = { temperature = tonumber(AI.settings.temperature) or 0.8 }
        local think = AI.settings.thinking or "dynamic"
        if think == "dynamic" then
            genConfig.thinkingConfig = { thinkingBudget = -1 }
        elseif think == "off" then
            genConfig.thinkingConfig = { thinkingBudget = 0 }
        else
            genConfig.thinkingConfig = { thinkingLevel = think }
        end

        local body = {
            systemInstruction = { parts = { { text = buildSystemPrompt() } } },
            contents = merged,
            generationConfig = genConfig,
        }
        if withTools then
            local tools = buildToolDeclarations()
            if tools then
                body.tools = tools
            end
        end
        return body
    end

    -- Returns (text, calls, nil) on success or (nil, nil, errText) on failure.
    -- `calls` holds the model's functionCall parts (built-in tool requests).
    local function extractResponseParts(data)
        if type(data) ~= "table" then
            return nil, nil, "Malformed API response."
        end
        if type(data.error) == "table" then
            return nil, nil, tostring(data.error.message or data.error.status or "API error")
        end
        local feedback = data.promptFeedback
        if type(feedback) == "table" and type(feedback.blockReason) == "string" then
            return nil, nil, "Blocked by safety filter: " .. feedback.blockReason
        end
        local cands = data.candidates
        if type(cands) ~= "table" or type(cands[1]) ~= "table" then
            return nil, nil, "No candidates returned."
        end
        local chunks, calls = {}, {}
        local content = cands[1].content
        if type(content) == "table" and type(content.parts) == "table" then
            for _, part in ipairs(content.parts) do
                if type(part) == "table" then
                    if type(part.text) == "string" then
                        table.insert(chunks, part.text)
                    elseif type(part.functionCall) == "table" then
                        local fc = part.functionCall
                        if type(fc.name) == "string" and fc.name ~= "" then
                            table.insert(calls, {
                                name = fc.name,
                                args = (type(fc.args) == "table" and fc.args) or {},
                            })
                        end
                    end
                end
            end
        end
        if #chunks == 0 and #calls == 0 then
            local reason = cands[1].finishReason
            return nil, nil, "Empty response" .. (reason and (" (" .. tostring(reason) .. ")") or "")
        end
        return table.concat(chunks, ""), calls, nil
    end

    ------------------------------------------------------------------
    -- CODE BLOCK PARSING (``` fences -> text/code segments)
    ------------------------------------------------------------------
    local function parseCodeBlocks(text)
        local segments = {}
        local src = tostring(text):gsub("\r\n", "\n"):gsub("\r", "\n")
        local i, n = 1, #src
        while i <= n do
            local fenceStart = src:find("```", i, true)
            if not fenceStart then
                table.insert(segments, { type = "text", content = src:sub(i) })
                break
            end
            if fenceStart > i then
                table.insert(segments, { type = "text", content = src:sub(i, fenceStart - 1) })
            end
            local langEnd = src:find("\n", fenceStart + 3, true)
            local lang = ""
            local bodyStart
            if langEnd then
                lang = src:sub(fenceStart + 3, langEnd - 1)
                bodyStart = langEnd + 1
            else
                lang = ""
                bodyStart = n + 1
            end
            lang = (lang:match("^%s*(%S+)") or "")
            local fenceClose = src:find("```", bodyStart, true)
            local codeText
            if fenceClose then
                codeText = src:sub(bodyStart, fenceClose - 1)
                i = fenceClose + 3
            else
                codeText = src:sub(bodyStart)
                i = n + 1
            end
            codeText = codeText:gsub("\n$", "")
            table.insert(segments, {
                type = "code",
                content = codeText,
                lang = (lang ~= "") and lang or "luau",
            })
        end
        if #segments == 0 then
            table.insert(segments, { type = "text", content = tostring(text) })
        end
        return segments
    end

    ------------------------------------------------------------------
    -- APPLY (run AI code) + the `sgc` helper the AI codes against
    ------------------------------------------------------------------
    local sgcHelper = {}
    function sgcHelper.guis()
        return getProjectScreenGuis()
    end
    function sgcHelper.find(path)
        if typeof(path) ~= "string" or path == "" then
            return nil
        end
        local parts = string.split(path, "/")
        local rootName = table.remove(parts, 1)
        for _, sg in ipairs(getProjectScreenGuis()) do
            if sg.Name == rootName then
                local node = sg
                for _, part in ipairs(parts) do
                    node = node:FindFirstChild(part)
                    if not node then
                        return nil
                    end
                end
                return node
            end
        end
        return nil
    end
    function sgcHelper.new(class, props, parent)
        return create(class, props, parent)
    end
    function sgcHelper.select(inst)
        Editor.select(inst)
    end
    function sgcHelper.notify(text, kind)
        notify(tostring(text), kind or "info", 3)
    end
    function sgcHelper.path(inst)
        if typeof(inst) ~= "Instance" then return nil end
        local parts = {}
        local node = inst
        while node and not node:IsA("ScreenGui") do
            table.insert(parts, 1, node.Name)
            node = node.Parent
        end
        if node and node:IsA("ScreenGui") then
            table.insert(parts, 1, node.Name)
        end
        return table.concat(parts, "/")
    end
    _G.sgc = sgcHelper
    _G.SGC = sgcHelper

    ------------------------------------------------------------------
    -- BUILT-IN TOOLS — real Luau functions registered for Gemini
    -- function calling. The model emits functionCall(name, args); we look
    -- the name up in AI_TOOLS, RUN the tool, and feed the result back so
    -- the model can continue or answer. Every tool is a fixed Luau
    -- function written by us — the model only picks a name + arguments.
    ------------------------------------------------------------------
    local AI_TOOLS = {}
    local MAX_TOOL_ROUNDS = 6

    local function registerAiTool(name, description, parameters, runFn)
        AI_TOOLS[name] = {
            description = description,
            parameters  = parameters,
            run         = runFn,
        }
    end

    local function parseNumberList(text)
        local nums = {}
        for token in tostring(text):gmatch("%-?%d+%.?%d*") do
            table.insert(nums, tonumber(token))
        end
        return nums
    end

    -- Tool arguments arrive as JSON: this turns friendly strings back into
    -- Roblox datatypes (UDim2 / Color3 / Vector2 / Vector3 / Enum).
    local function coercePropValue(inst, propName, raw)
        if type(raw) == "number" or type(raw) == "boolean" then
            return raw
        end
        if type(raw) == "table" then
            local nums = {}
            for _, v in ipairs(raw) do
                if type(v) == "number" then
                    table.insert(nums, v)
                end
            end
            if #nums == 4 then
                return UDim2.new(nums[1], nums[2], nums[3], nums[4])
            elseif #nums == 3 then
                return Color3.fromRGB(nums[1], nums[2], nums[3])
            elseif #nums == 2 then
                return UDim2.new(nums[1], nums[2], 0, 0)
            end
            return raw
        end
        if type(raw) ~= "string" then
            return raw
        end
        if raw:sub(1, 1) == "#" and #raw >= 7 then
            local okHex, hexColor = pcall(Color3.fromHex, raw:sub(2, 8))
            if okHex then
                return hexColor
            end
        end
        local compact = raw:gsub("[%s{}%[%]]", "")
        -- Lua patterns can't repeat a capture group, so validate each
        -- comma-separated part instead (also rejects letters like "Level1").
        local isNumericList = false
        if compact ~= "" and not compact:find("%a") then
            isNumericList = true
            for _, part in ipairs(string.split(compact, ",")) do
                if part == "" or part:match("^%-?%d+%.?%d*$") == nil then
                    isNumericList = false
                    break
                end
            end
        end
        local nums = isNumericList and parseNumberList(compact) or {}
        local current
        pcall(function() current = inst[propName] end)
        if #nums == 4 then
            return UDim2.new(nums[1], nums[2], nums[3], nums[4])
        elseif #nums == 3 then
            if typeof(current) == "Color3" then
                return Color3.fromRGB(nums[1], nums[2], nums[3])
            end
            return Vector3.new(nums[1], nums[2], nums[3])
        elseif #nums == 2 then
            if typeof(current) == "Vector2" then
                return Vector2.new(nums[1], nums[2])
            end
            return UDim2.new(nums[1], nums[2], 0, 0)
        elseif #nums == 1 then
            return nums[1]
        end
        if typeof(current) == "EnumItem" then
            local valueName = raw:gsub("^Enum%.", ""):gsub("^%w+%.", "")
            local item = current.EnumType[valueName]
            if item then
                return item
            end
        end
        return raw
    end

    local function applyPropsToInstance(inst, props)
        local applied, failed = 0, {}
        if type(props) == "table" then
            for propName, raw in pairs(props) do
                if type(propName) == "string" then
                    local okSet
                    if propName == "Name" then
                        okSet = pcall(function() inst.Name = tostring(raw) end)
                    else
                        local value = coercePropValue(inst, propName, raw)
                        okSet = pcall(function() inst[propName] = value end)
                    end
                    if okSet then
                        applied += 1
                    else
                        table.insert(failed, propName)
                    end
                end
            end
        end
        return applied, failed
    end

    local function findPathOrError(args)
        local path = tostring(args.path or args.instance or "")
        if path == "" then
            return nil, "Missing 'path' (e.g. 'MyGui/Header/Title'). Call list_ui first."
        end
        local inst = sgcHelper.find(path)
        if not inst then
            return nil, "No instance at '" .. path .. "'. Call list_ui to see exact paths."
        end
        return inst, nil
    end

    -- list_ui ---------------------------------------------------------
    registerAiTool("list_ui",
        "Read the whole project UI tree: every instance with class, name, key properties and exact paths.",
        nil,
        function()
            return buildUiContext()
        end)

    -- find_instance ---------------------------------------------------
    registerAiTool("find_instance",
        "Read one instance's key properties and list its children, addressed by path.",
        {
            type = "object",
            properties = {
                path = { type = "string", description = "Path like 'MyGui/Header/Title'" },
            },
            required = { "path" },
        },
        function(args)
            local inst, err = findPathOrError(args)
            if err then
                return err
            end
            local line = describeInstance(inst, sgcHelper.path(inst) or inst.Name)
            local kids = {}
            for _, child in ipairs(treeChildren(inst)) do
                table.insert(kids, child.ClassName .. ":" .. child.Name)
            end
            if #kids > 0 then
                line = line .. "  Children(" .. #kids .. "): " .. table.concat(kids, ", ")
            end
            return line
        end)

    -- create_element --------------------------------------------------
    registerAiTool("create_element",
        "Create a real UI instance (Frame, TextButton, TextLabel, UIListLayout, UICorner, LocalScript, ModuleScript, ...) and parent it into the project.",
        {
            type = "object",
            properties = {
                class = { type = "string", description = "Roblox class name, e.g. Frame, TextButton, UICorner, LocalScript" },
                name = { type = "string", description = "Name for the new instance" },
                parent_path = { type = "string", description = "Parent path (e.g. 'MyGui/Header'). Empty = selected instance or first ScreenGui." },
                props = { type = "object", description = "Initial properties, e.g. { Size = '0.5,0,0.1,0', BackgroundColor3 = '30,30,40', Text = 'Hi' }" },
            },
            required = { "class" },
        },
        function(args)
            local class = tostring(args.class or "")
            if class == "" then
                return "ERROR: missing 'class'."
            end
            local okNew, inst = pcall(Instance.new, class)
            if not okNew or typeof(inst) ~= "Instance" then
                return "ERROR: cannot create a '" .. class .. "'."
            end
            local parent
            local ppath = tostring(args.parent_path or "")
            if ppath ~= "" then
                parent = sgcHelper.find(ppath)
                if not parent then
                    return "ERROR: no instance at parent_path '" .. ppath .. "'."
                end
            end
            if not parent and typeof(State.selected) == "Instance" and State.selected.Parent then
                parent = State.selected
            end
            if not parent then
                parent = getProjectScreenGuis()[1]
            end
            if not parent then
                local okSg, sg = pcall(Instance.new, "ScreenGui")
                if okSg and typeof(sg) == "Instance" then
                    pcall(function()
                        sg.Name = "AIGui"
                        sg:SetAttribute(PROJECT_ATTRIBUTE, true)
                    end)
                    pcall(function() sg.Parent = PROJECT_PARENT end)
                    parent = sg
                end
            end
            if not parent then
                return "ERROR: no parent available."
            end
            if type(args.name) == "string" and args.name ~= "" then
                pcall(function() inst.Name = args.name end)
            end
            local applied, failed = applyPropsToInstance(inst, args.props)
            pcall(function() inst.Parent = parent end)
            invalidateExplorer()
            local note = ("Created %s '%s' under '%s' — %d propert%s applied%s.")
                :format(class, inst.Name, parent.Name, applied,
                    applied == 1 and "y" or "ies",
                    #failed > 0 and ("; failed: " .. table.concat(failed, ", ")) or "")
            return note .. "  Path: " .. (sgcHelper.path(inst) or inst.Name)
        end)

    -- set_properties --------------------------------------------------
    registerAiTool("set_properties",
        "Write properties straight onto a live instance; the editor preview and properties panel update instantly.",
        {
            type = "object",
            properties = {
                path = { type = "string", description = "Target path" },
                props = { type = "object", description = "Properties to set, e.g. { Text = 'Play', BackgroundColor3 = '40,160,80' }" },
            },
            required = { "path", "props" },
        },
        function(args)
            local inst, err = findPathOrError(args)
            if err then
                return err
            end
            if type(args.props) ~= "table" then
                return "ERROR: missing 'props' table."
            end
            local applied, failed = applyPropsToInstance(inst, args.props)
            invalidateExplorer()
            if State.selected == inst then
                Editor.select(inst)
            end
            return ("Applied %d propert%s to '%s'%s.")
                :format(applied, applied == 1 and "y" or "ies", inst.Name,
                    #failed > 0 and (" (failed: " .. table.concat(failed, ", ") .. ")") or "")
        end)

    -- rename_element --------------------------------------------------
    registerAiTool("rename_element",
        "Rename an instance (tool paths that used the old name change too).",
        {
            type = "object",
            properties = {
                path = { type = "string", description = "Target path" },
                new_name = { type = "string", description = "New name" },
            },
            required = { "path", "new_name" },
        },
        function(args)
            local inst, err = findPathOrError(args)
            if err then
                return err
            end
            local newName = tostring(args.new_name or "")
            if newName == "" then
                return "ERROR: missing 'new_name'."
            end
            local oldName = inst.Name
            pcall(function() inst.Name = newName end)
            invalidateExplorer()
            return ("Renamed '%s' to '%s'."):format(oldName, newName)
        end)

    -- delete_element --------------------------------------------------
    registerAiTool("delete_element",
        "Delete (Destroy) an instance. The last remaining ScreenGui can never be deleted.",
        {
            type = "object",
            properties = {
                path = { type = "string", description = "Target path" },
            },
            required = { "path" },
        },
        function(args)
            local inst, err = findPathOrError(args)
            if err then
                return err
            end
            if inst:IsA("ScreenGui") and #getProjectScreenGuis() <= 1 then
                return "ERROR: refused — the last remaining ScreenGui can't be deleted."
            end
            local name = inst.Name
            if State.selected == inst then
                pcall(function() Editor.select(nil) end)
            end
            pcall(function() inst:Destroy() end)
            invalidateExplorer()
            return "Deleted '" .. name .. "'."
        end)

    -- duplicate_element ----------------------------------------------
    registerAiTool("duplicate_element",
        "Clone an instance (and all its children) next to the original.",
        {
            type = "object",
            properties = {
                path = { type = "string", description = "Target path" },
            },
            required = { "path" },
        },
        function(args)
            local inst, err = findPathOrError(args)
            if err then
                return err
            end
            if inst:IsA("ScreenGui") then
                return "ERROR: ScreenGuis can't be duplicated — duplicate their children instead."
            end
            local okClone, clone = pcall(function() return inst:Clone() end)
            if not okClone or typeof(clone) ~= "Instance" then
                return "ERROR: this instance can't be cloned."
            end
            pcall(function() clone.Name = inst.Name .. "_copy" end)
            pcall(function() clone.Parent = inst.Parent end)
            invalidateExplorer()
            return ("Cloned '%s' into '%s'."):format(inst.Name, tostring(clone.Name))
        end)

    -- select_element --------------------------------------------------
    registerAiTool("select_element",
        "Select an instance in the editor (viewport highlight + properties panel follow the selection).",
        {
            type = "object",
            properties = {
                path = { type = "string", description = "Target path" },
            },
            required = { "path" },
        },
        function(args)
            local inst, err = findPathOrError(args)
            if err then
                return err
            end
            Editor.select(inst)
            return "Selected '" .. inst.Name .. "'."
        end)

    -- script source ---------------------------------------------------
    registerAiTool("set_script_source",
        "Write Luau source into a LocalScript or ModuleScript (the only script types here).",
        {
            type = "object",
            properties = {
                path = { type = "string", description = "Script path" },
                source = { type = "string", description = "Full Luau source code" },
            },
            required = { "path", "source" },
        },
        function(args)
            local inst, err = findPathOrError(args)
            if err then
                return err
            end
            if not (inst:IsA("LocalScript") or inst:IsA("ModuleScript")) then
                return "ERROR: '" .. inst.Name .. "' is a " .. inst.ClassName
                    .. " — only LocalScript and ModuleScript hold source code."
            end
            local source = tostring(args.source or "")
            pcall(function() inst.Source = source end)
            invalidateExplorer()
            return ("Wrote %d chars into %s '%s'."):format(#source, inst.ClassName, inst.Name)
        end)

    registerAiTool("get_script_source",
        "Read the current Luau source of a LocalScript or ModuleScript.",
        {
            type = "object",
            properties = {
                path = { type = "string", description = "Script path" },
            },
            required = { "path" },
        },
        function(args)
            local inst, err = findPathOrError(args)
            if err then
                return err
            end
            local src = ""
            pcall(function() src = tostring(inst.Source) end)
            if #src > 4000 then
                return src:sub(1, 4000) .. "\n... (truncated — " .. #src .. " chars total)"
            end
            return src ~= "" and src or "(empty script)"
        end)

    -- save / load -----------------------------------------------------
    registerAiTool("save_project",
        "Save every project ScreenGui as a file in the GUI_CREATOR_SAVES folder (file name only, extension optional).",
        {
            type = "object",
            properties = {
                name = { type = "string", description = "File name, e.g. 'hud_main'" },
            },
            required = { "name" },
        },
        function(args)
            local name = sanitizeSaveName(tostring(args.name or ""))
            if name == "" then
                return "ERROR: give a valid file 'name'."
            end
            if not Executor.writefile then
                return "ERROR: writefile is not available on this executor."
            end
            if not ensureSaveFolder() then
                return "ERROR: could not create the " .. SAVE_DIR .. " folder."
            end
            local data = serializeProject()
            if not data then
                return "ERROR: nothing to save — no project ScreenGuis exist."
            end
            local okEnc, encoded = pcall(function() return HttpService:JSONEncode(data) end)
            if not okEnc or type(encoded) ~= "string" then
                return "ERROR: could not encode the save data."
            end
            local path = SAVE_DIR .. "/" .. name
            local okWrite, werr = pcall(Executor.writefile, path, encoded)
            if not okWrite then
                return "ERROR: write failed: " .. tostring(werr)
            end
            return "Saved project to " .. path
        end)

    registerAiTool("list_saves",
        "List saved project files in GUI_CREATOR_SAVES (any extension).",
        nil,
        function()
            if not FS.listfiles then
                return "ERROR: listfiles is not available on this executor."
            end
            ensureSaveFolder()
            local okList, files = pcall(FS.listfiles, SAVE_DIR)
            if not okList or typeof(files) ~= "table" then
                return "ERROR: could not read the " .. SAVE_DIR .. " folder."
            end
            local names = {}
            for _, path in ipairs(files) do
                if type(path) == "string" and path ~= "" then
                    local n = path:gsub("^" .. SAVE_DIR .. "/", ""):gsub("^/", "")
                    if n ~= "" and n:sub(1, 1) ~= "." then
                        table.insert(names, n)
                    end
                end
            end
            if #names == 0 then
                return "(no saves yet)"
            end
            return "Saves(" .. #names .. "): " .. table.concat(names, ", ")
        end)

    registerAiTool("load_project",
        "Load a saved project from GUI_CREATOR_SAVES, replacing the current one. Extension never matters: 'hud' loads 'hud.lua', 'hud.txt' or 'hud' alike.",
        {
            type = "object",
            properties = {
                name = { type = "string", description = "File name with or without extension" },
            },
            required = { "name" },
        },
        function(args)
            local wanted = tostring(args.name or "")
            if wanted == "" then
                return "ERROR: missing 'name'."
            end
            if not (FS.readfile and FS.listfiles) then
                return "ERROR: readfile/listfiles are not available on this executor."
            end
            local okList, files = pcall(FS.listfiles, SAVE_DIR)
            if not okList or typeof(files) ~= "table" then
                return "ERROR: could not read the " .. SAVE_DIR .. " folder."
            end
            local path
            for _, f in ipairs(files) do
                if type(f) == "string" then
                    local n = f:gsub("^" .. SAVE_DIR .. "/", ""):gsub("^/", "")
                    if n == wanted then
                        path = f
                    end
                end
            end
            if not path then
                for _, f in ipairs(files) do
                    if type(f) == "string" then
                        local n = f:gsub("^" .. SAVE_DIR .. "/", ""):gsub("^/", "")
                        local stem = n:match("^(.*)%.[^%.]+$") or n
                        if stem == wanted then
                            path = f
                        end
                    end
                end
            end
            if not path then
                return "ERROR: no save named '" .. wanted .. "'. Call list_saves first."
            end
            local okRead, content = pcall(FS.readfile, path)
            if not okRead or type(content) ~= "string" then
                return "ERROR: could not read " .. path
            end
            local okDecode, data = pcall(function() return HttpService:JSONDecode(content) end)
            if not (okDecode and typeof(data) == "table") then
                return "ERROR: '" .. path .. "' is not a GUI Creator save (JSON expected)."
            end
            local created = replaceProjectWith(data)
            return ("Loaded '%s' — %d ScreenGui(s) rebuilt."):format(wanted, created)
        end)

    -- notify ----------------------------------------------------------
    registerAiTool("notify_user",
        "Show a toast notification to the user (kind: info/success/warn/error).",
        {
            type = "object",
            properties = {
                text = { type = "string", description = "Message text" },
                kind = { type = "string", description = "info | success | warn | error" },
            },
            required = { "text" },
        },
        function(args)
            notify(tostring(args.text or ""), tostring(args.kind or "info"), 3)
            return "notified"
        end)

    -- run_lua (gated) -------------------------------------------------
    registerAiTool("run_lua",
        "Run arbitrary Luau code right now via loadstring. Only available when 'Allow AI to run code' is ON in AI Settings.",
        {
            type = "object",
            properties = {
                code = { type = "string", description = "Luau code to execute" },
            },
            required = { "code" },
        },
        function(args)
            local code = tostring(args.code or "")
            if not code:match("%S") then
                return "ERROR: empty code."
            end
            local loadFn = (type(loadstring) == "function" and loadstring)
                or (type(load) == "function" and load)
            if not loadFn then
                return "ERROR: loadstring is not available on this executor."
            end
            local chunk, syntaxErr = loadFn(code, "SGC_AI_Tool")
            if not chunk then
                return "ERROR: syntax — " .. tostring(syntaxErr)
            end
            local okRun, runErr = pcall(chunk)
            invalidateExplorer()
            if not okRun then
                return "ERROR: runtime — " .. tostring(runErr)
            end
            return "code ran without errors"
        end)

    -- OpenAPI-style declarations for the Gemini `tools` request field.
    -- run_lua is only declared while the user keeps it enabled.
    buildToolDeclarations = function()
        local decls = {}
        for name, tool in pairs(AI_TOOLS) do
            if name ~= "run_lua" or AI.settings.allowRunLua then
                local decl = {
                    name = name,
                    description = tool.description,
                }
                if type(tool.parameters) == "table" then
                    decl.parameters = tool.parameters
                end
                table.insert(decls, decl)
            end
        end
        if #decls == 0 then
            return nil
        end
        table.sort(decls, function(a, b) return a.name < b.name end)
        return { { functionDeclarations = decls } }
    end

    -- Execute one functionCall from the model, safely and synchronously.
    local function runAiTool(call)
        if type(call) ~= "table" or type(call.name) ~= "string" then
            return "ERROR: malformed tool call."
        end
        local tool = AI_TOOLS[call.name]
        if not tool then
            return "ERROR: unknown tool '" .. call.name .. "'"
        end
        if call.name == "run_lua" and not AI.settings.allowRunLua then
            return "ERROR: run_lua is disabled — the user must enable 'Allow AI to run code' in AI Settings."
        end
        local args = (type(call.args) == "table" and call.args) or {}
        local ok, result = pcall(tool.run, args)
        if not ok then
            return "ERROR: " .. tostring(result)
        end
        if result == nil or result == "" then
            return "ok"
        end
        return tostring(result)
    end

    local function summarizeArgs(args)
        if type(args) ~= "table" then
            return ""
        end
        local ok, encoded = pcall(function() return HttpService:JSONEncode(args) end)
        local text = (ok and type(encoded) == "string") and encoded or "?"
        if #text > 140 then
            text = text:sub(1, 137) .. "..."
        end
        return text
    end

    local function applyAiCode(code)
        if type(code) ~= "string" or not code:match("%S") then
            return
        end
        local loadFn = (type(loadstring) == "function" and loadstring)
            or (type(load) == "function" and load)
        if not loadFn then
            notify("loadstring isn't available — Copy the code and run it manually.", "warn", 4)
            return
        end
        local chunk, syntaxErr = loadFn(code, "SGC_AI_Snippet")
        if not chunk then
            notify("AI snippet syntax error: " .. tostring(syntaxErr), "error", 5)
            return
        end
        local ok, runErr = pcall(chunk)
        invalidateExplorer()
        if ok then
            notify("AI snippet applied — Explorer refreshed.", "success", 3)
        else
            notify("AI snippet runtime error: " .. tostring(runErr), "error", 5)
        end
        if State.selected and State.selected.Parent then
            Editor.select(State.selected)
        end
    end

    ------------------------------------------------------------------
    -- CHAT RENDERING (bubbles + code blocks with Copy / Apply buttons)
    ------------------------------------------------------------------
    local ROLE_STYLE = {
        user   = { label = "You",    color = THEME.Accent },
        model  = { label = "Gemini", color = THEME.Good },
        error  = { label = "Error",  color = THEME.Danger },
        system = { label = "Info",   color = THEME.Warn },
        tool   = { label = "Tools",  color = THEME.Warn },
    }
    local messageOrder = 0

    local function scrollChatToBottom()
        task.defer(function()
            pcall(function()
                chatScroll.CanvasPosition = Vector2.new(0, math.max(0, chatScroll.AbsoluteContentSize.Y))
            end)
        end)
    end

    local function makeTextSegment(parent, content, role, order)
        local bubbleColor = THEME.PanelAlt
        if role == "user" then
            bubbleColor = Color3.fromRGB(36, 50, 74)
        elseif role == "error" then
            bubbleColor = Color3.fromRGB(72, 36, 36)
        end
        local bubble = create("Frame", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = bubbleColor,
            BorderSizePixel = 0,
            LayoutOrder = order,
            ZIndex = 63,
        }, parent)
        create("UICorner", { CornerRadius = UDim.new(0, 6) }, bubble)
        create("UIPadding", {
            PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
            PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
        }, bubble)
        create("TextLabel", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Text = content,
            TextWrapped = true,
            RichText = false,
            TextColor3 = THEME.Text,
            Font = Enum.Font.Gotham,
            TextSize = 13,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            ZIndex = 64,
        }, bubble)
    end

    local function makeCodeSegment(parent, content, order)
        local lineCount = 1
        for _ in content:gmatch("\n") do
            lineCount += 1
        end
        local boxHeight = math.clamp(lineCount * 13 + 12, 44, 220)
        local holder = create("Frame", {
            Size = UDim2.new(1, 0, 0, boxHeight),
            BackgroundColor3 = Color3.fromRGB(18, 18, 22),
            BorderSizePixel = 0,
            LayoutOrder = order,
            ZIndex = 63,
        }, parent)
        create("UICorner", { CornerRadius = UDim.new(0, 6) }, holder)
        create("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, holder)

        local codeBox = create("TextBox", {
            Position = UDim2.fromOffset(6, 6),
            Size = UDim2.new(1, -134, 1, -12),
            BackgroundTransparency = 1,
            TextColor3 = Color3.fromRGB(200, 205, 215),
            Font = Enum.Font.Code,
            TextSize = 12,
            Text = content,
            MultiLine = true,
            ClearTextOnFocus = false,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            TextWrapped = false,
            ZIndex = 64,
        }, holder)

        local copyBtn = create("TextButton", {
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -6, 0, 6),
            Size = UDim2.fromOffset(56, 22),
            BackgroundColor3 = THEME.Control,
            BorderSizePixel = 0,
            Text = "Copy",
            TextColor3 = THEME.Text,
            Font = Enum.Font.GothamMedium,
            TextSize = 12,
            AutoButtonColor = false,
            ZIndex = 64,
        }, holder)
        create("UICorner", { CornerRadius = UDim.new(0, 5) }, copyBtn)
        copyBtn.Activated:Connect(function()
            if Executor.clipboard then
                local ok = pcall(Executor.clipboard, codeBox.Text)
                notify(ok and "Code copied via setclipboard." or "Clipboard copy failed.",
                    ok and "success" or "error", 2.5)
            else
                notify("No clipboard API on this executor — select the text and Ctrl+C.", "warn", 4)
            end
        end)

        local applyBtn = create("TextButton", {
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -6, 0, 32),
            Size = UDim2.fromOffset(56, 22),
            BackgroundColor3 = THEME.Good,
            BorderSizePixel = 0,
            Text = "Apply",
            TextColor3 = Color3.fromRGB(255, 255, 255),
            Font = Enum.Font.GothamBold,
            TextSize = 12,
            AutoButtonColor = false,
            ZIndex = 64,
        }, holder)
        create("UICorner", { CornerRadius = UDim.new(0, 5) }, applyBtn)
        applyBtn.Activated:Connect(function()
            applyAiCode(codeBox.Text)
        end)
    end

    local function addChatMessage(role, text)
        messageOrder += 1
        local style = ROLE_STYLE[role] or ROLE_STYLE.system
        local row = create("Frame", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            LayoutOrder = messageOrder,
            ZIndex = 62,
        }, chatScroll)
        create("TextLabel", {
            Size = UDim2.new(1, 0, 0, 16),
            BackgroundTransparency = 1,
            Text = style.label,
            TextColor3 = style.color,
            Font = Enum.Font.GothamBold,
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 63,
        }, row)
        local body = create("Frame", {
            Position = UDim2.fromOffset(0, 16),
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            ZIndex = 63,
        }, row)
        create("UIListLayout", {
            Padding = UDim.new(0, 4),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, body)

        local segments = parseCodeBlocks(tostring(text))
        local rendered = 0
        for segOrder, seg in ipairs(segments) do
            if seg.type == "code" then
                makeCodeSegment(body, seg.content, segOrder)
                rendered += 1
            elseif seg.content:match("%S") then
                makeTextSegment(body, seg.content, role, segOrder)
                rendered += 1
            end
        end
        if rendered == 0 then
            makeTextSegment(body, "(empty response)", role, 1)
        end
        scrollChatToBottom()
        return row
    end

    local function clearChatLog()
        AI.history = {}
        messageOrder = 0
        for _, child in ipairs(chatScroll:GetChildren()) do
            if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
                child:Destroy()
            end
        end
        addChatMessage("system", "Chat cleared. The AI still reads your live UI on the next message.")
    end

    ------------------------------------------------------------------
    -- SETTINGS UI SYNC + LIVE MODEL FETCH (the only source of models)
    ------------------------------------------------------------------
    local function refreshStatusLabel()
        if AI.waiting then return end
        local modelPart = AI.settings.model
            and ("Model: " .. AI.settings.model)
            or "Model: none — set in Settings"
        local ctxPart = AI.settings.context and "UI tree: on" or "UI tree: off"
        statusLabel.Text = "Gemini  ·  " .. modelPart .. "  ·  " .. ctxPart
    end

    local function refreshModelControls()
        if AI.fetchingModels then
            modelButton.Text = "Fetching models..."
        elseif AI.settings.model then
            modelButton.Text = "Model: " .. AI.settings.model
        else
            modelButton.Text = "Model: none — fetch below"
        end
        modelCountLabel.Text = AI.models
            and ("%d model(s) available for this key."):format(#AI.models)
            or "No models fetched yet — click Refresh."
    end

    local function refreshSettingsUi()
        keyBox.Text = AI.settings.apiKey or ""
        instrBox.Text = AI.settings.instructions or ""
        tempBox.Text = trimNum(tonumber(AI.settings.temperature) or 0.8)
        thinkingButton.Text = "Thinking: " .. thinkingLabel(AI.settings.thinking)
        contextButton.Text = "Send UI tree: " .. (AI.settings.context and "On" or "Off")
        contextButton.BackgroundColor3 = AI.settings.context and THEME.Good or THEME.Danger
        allowLuaButton.Text = "Allow AI to run code: " .. (AI.settings.allowRunLua and "On" or "Off")
        allowLuaButton.BackgroundColor3 = AI.settings.allowRunLua and THEME.Good or THEME.Danger
        refreshModelControls()
        refreshStatusLabel()
    end

    local function fetchModels(silent)
        local key = tostring(AI.settings.apiKey or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if key == "" then
            if not silent then
                notify("Paste your Gemini API key first.", "warn", 3)
            end
            return false
        end
        if AI.fetchingModels then
            return true
        end
        AI.fetchingModels = true
        refreshModelControls()
        task.spawn(function()
            local res, err = httpJson(GEMINI_BASE .. "/models?key=" .. key, "GET", nil)
            AI.fetchingModels = false
            if not res then
                AI.models = nil
                if not silent then
                    notify("Model fetch failed: " .. tostring(err), "error", 4)
                end
                refreshModelControls()
                return
            end
            local okDecode, data = pcall(function() return HttpService:JSONDecode(res.body or "") end)
            if not (okDecode and type(data) == "table") then
                AI.models = nil
                if not silent then
                    notify(("Model fetch returned HTTP %s with an unreadable body."):format(tostring(res.code)), "error", 4)
                end
                refreshModelControls()
                return
            end
            if type(data.error) == "table" then
                AI.models = nil
                if not silent then
                    notify("API error: " .. tostring(data.error.message or data.error.status), "error", 4.5)
                end
                refreshModelControls()
                return
            end
            local list = {}
            for _, m in ipairs(type(data.models) == "table" and data.models or {}) do
                if type(m) == "table" and type(m.name) == "string" then
                    local supported = false
                    for _, method in ipairs(type(m.supportedGenerationMethods) == "table" and m.supportedGenerationMethods or {}) do
                        if method == "generateContent" then
                            supported = true
                        end
                    end
                    if supported then
                        local id = m.name:gsub("^models/", "")
                        local label = id
                        if type(m.displayName) == "string" and m.displayName ~= "" then
                            label = m.displayName .. "  ·  " .. id
                        end
                        table.insert(list, { id = id, label = label })
                    end
                end
            end
            table.sort(list, function(a, b) return a.id < b.id end)
            AI.models = list
            if AI.settings.model then
                local stillThere = false
                for _, entry in ipairs(list) do
                    if entry.id == AI.settings.model then
                        stillThere = true
                    end
                end
                if not stillThere then
                    AI.settings.model = nil
                    saveAiSettings()
                end
            end
            refreshModelControls()
            refreshStatusLabel()
            if not silent then
                if #list == 0 then
                    notify("The key works but returned no generateContent models.", "warn", 4)
                else
                    notify(("Fetched %d model(s) from Gemini."):format(#list), "success", 2.5)
                end
            end
        end)
        return true
    end

    local function openSettingsView()
        chatView.Visible = false
        settingsView.Visible = true
        refreshSettingsUi()
        -- Auto-fetch once when a key exists but models were never loaded.
        if (AI.settings.apiKey or "") ~= "" and AI.models == nil and not AI.fetchingModels then
            fetchModels(true)
        end
    end

    local function openChatView()
        settingsView.Visible = false
        chatView.Visible = true
        refreshStatusLabel()
    end

    ------------------------------------------------------------------
    -- SEND / RECEIVE
    ------------------------------------------------------------------
    local function setWaiting(waitingNow)
        AI.waiting = waitingNow and true or false
        sendButton.Text = AI.waiting and "..." or "Send"
        if AI.waiting then
            statusLabel.Text = ("Thinking with %s..."):format(tostring(AI.settings.model or "?"))
        else
            refreshStatusLabel()
        end
    end

    -- Chat pipeline with native tool calling:
    --   1. POST with tools (functionDeclarations of our built-in Luau tools)
    --   2. if the model returns functionCall parts -> run each tool for real
    --   3. append functionResponse parts and POST again (max MAX_TOOL_ROUNDS)
    --   4. when the model answers in text, show it and stop
    local function sendChat()
        if AI.waiting then return end
        local text = tostring(inputBox.Text):gsub("^%s+", ""):gsub("%s+$", "")
        if text == "" then return end
        if (AI.settings.apiKey or "") == "" then
            notify("Add your Gemini API key in AI Settings first.", "warn", 3.5)
            openSettingsView()
            return
        end
        if not AI.settings.model then
            notify("Fetch models and pick one in AI Settings first.", "warn", 3.5)
            openSettingsView()
            return
        end

        table.insert(AI.history, { role = "user", text = text })
        addChatMessage("user", text)
        inputBox.Text = ""
        setWaiting(true)

        task.spawn(function()
            local url = ("%s/models/%s:generateContent?key=%s"):format(
                GEMINI_BASE, AI.settings.model, AI.settings.apiKey)
            local rounds = 0

            while true do
                local body = buildRequestBody(true)
                local res, err = httpJson(url, "POST", body)
                if not res then
                    setWaiting(false)
                    addChatMessage("error", tostring(err))
                    return
                end
                local okDecode, data = pcall(function()
                    return HttpService:JSONDecode(res.body or "")
                end)
                if not (okDecode and type(data) == "table") then
                    setWaiting(false)
                    addChatMessage("error", ("Unreadable response (HTTP %s)."):format(tostring(res.code)))
                    return
                end

                local reply, calls, parseErr = extractResponseParts(data)
                -- Some models reject function declarations; retry once without.
                if parseErr and rounds == 0 then
                    local lowered = tostring(parseErr):lower()
                    if lowered:find("function", 1, true) or lowered:find("tool", 1, true) then
                        local res2, err2 = httpJson(url, "POST", buildRequestBody(false))
                        if res2 then
                            local okD2, data2 = pcall(function()
                                return HttpService:JSONDecode(res2.body or "")
                            end)
                            if okD2 and type(data2) == "table" then
                                reply, calls, parseErr = extractResponseParts(data2)
                            end
                        else
                            parseErr = tostring(err2)
                        end
                    end
                end
                if parseErr then
                    setWaiting(false)
                    addChatMessage("error", tostring(parseErr))
                    return
                end

                if type(calls) ~= "table" or #calls == 0 then
                    setWaiting(false)
                    local finalText = tostring(reply or "")
                    table.insert(AI.history, { role = "model", text = finalText:sub(1, 6000) })
                    while #AI.history > 30 do
                        table.remove(AI.history, 1)
                    end
                    addChatMessage("model", finalText ~= "" and finalText or "(empty response)")
                    return
                end

                -- The model asked for built-in tools: run them for real and
                -- feed every result back so it can continue or answer.
                rounds += 1
                local callLines = {}
                for _, call in ipairs(calls) do
                    table.insert(callLines, ("- %s(%s)"):format(call.name, summarizeArgs(call.args)))
                end
                table.insert(AI.history, { role = "model", text = tostring(reply or ""), calls = calls })
                addChatMessage("tool", "Running built-in tool(s):\n" .. table.concat(callLines, "\n"))

                local results, resultLines = {}, {}
                for _, call in ipairs(calls) do
                    local result = runAiTool(call)
                    table.insert(results, { name = call.name, response = result })
                    local short = tostring(result):gsub("[\r\n]+", " ")
                    if #short > 220 then
                        short = short:sub(1, 217) .. "..."
                    end
                    table.insert(resultLines, ("- %s -> %s"):format(call.name, short))
                end
                table.insert(AI.history, { role = "user", toolResults = results })
                addChatMessage("system", "Tool results:\n" .. table.concat(resultLines, "\n"))

                if rounds >= MAX_TOOL_ROUNDS then
                    -- Force a plain-text wrap-up instead of more tool calls.
                    local finalBody = buildRequestBody(false)
                    local lastContent = finalBody.contents[#finalBody.contents]
                    local nudge = "Tool round limit reached — summarize what you changed in plain text now (no more tool calls)."
                    if lastContent and lastContent.role == "user" then
                        table.insert(lastContent.parts, { text = nudge })
                    else
                        table.insert(finalBody.contents, { role = "user", parts = { { text = nudge } } })
                    end
                    local res2, err2 = httpJson(url, "POST", finalBody)
                    setWaiting(false)
                    if not res2 then
                        addChatMessage("error", tostring(err2))
                        return
                    end
                    local finalText = ""
                    local okD2, data2 = pcall(function()
                        return HttpService:JSONDecode(res2.body or "")
                    end)
                    if okD2 and type(data2) == "table" then
                        local t2, _, e2 = extractResponseParts(data2)
                        finalText = tostring(t2 or e2 or "")
                    end
                    table.insert(AI.history, { role = "model", text = finalText:sub(1, 6000) })
                    while #AI.history > 30 do
                        table.remove(AI.history, 1)
                    end
                    addChatMessage("model", finalText ~= "" and finalText or "(tools finished — no summary returned)")
                    return
                end
                task.wait(0.05)
            end
        end)
    end

    ------------------------------------------------------------------
    -- WIRING
    ------------------------------------------------------------------
    sendButton.Activated:Connect(sendChat)
    inputBox.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            sendChat()
            task.defer(function()
                pcall(function() inputBox:CaptureFocus() end)
            end)
        end
    end)

    keyBox.FocusLost:Connect(function()
        local trimmed = tostring(keyBox.Text):gsub("^%s+", ""):gsub("%s+$", "")
        AI.settings.apiKey = trimmed
        keyBox.Text = trimmed
        saveAiSettings()
        if trimmed ~= "" and AI.models == nil and not AI.fetchingModels then
            fetchModels(true)
        end
        refreshStatusLabel()
    end)

    refreshModelsButton.Activated:Connect(function()
        fetchModels(false)
    end)

    modelButton.Activated:Connect(function()
        ListPopup.open(modelButton.AbsolutePosition, modelButton.AbsoluteSize,
            AI.models, AI.settings.model, function(id)
                AI.settings.model = id
                saveAiSettings()
                refreshModelControls()
                refreshStatusLabel()
                notify("Model set: " .. id, "success", 2)
            end)
    end)

    thinkingButton.Activated:Connect(function()
        ListPopup.open(thinkingButton.AbsolutePosition, thinkingButton.AbsoluteSize,
            THINKING_OPTIONS, AI.settings.thinking, function(id)
                AI.settings.thinking = id
                saveAiSettings()
                thinkingButton.Text = "Thinking: " .. thinkingLabel(id)
            end)
    end)

    tempBox.FocusLost:Connect(function()
        local num = tonumber(tostring(tempBox.Text):gsub("^%s+", ""):gsub("%s+$", ""))
        if num then
            AI.settings.temperature = math.clamp(num, 0, 2)
        end
        tempBox.Text = trimNum(AI.settings.temperature)
        saveAiSettings()
    end)

    contextButton.Activated:Connect(function()
        AI.settings.context = not AI.settings.context
        saveAiSettings()
        contextButton.Text = "Send UI tree: " .. (AI.settings.context and "On" or "Off")
        contextButton.BackgroundColor3 = AI.settings.context and THEME.Good or THEME.Danger
        refreshStatusLabel()
    end)

    allowLuaButton.Activated:Connect(function()
        AI.settings.allowRunLua = not AI.settings.allowRunLua
        saveAiSettings()
        allowLuaButton.Text = "Allow AI to run code: " .. (AI.settings.allowRunLua and "On" or "Off")
        allowLuaButton.BackgroundColor3 = AI.settings.allowRunLua and THEME.Good or THEME.Danger
        notify(AI.settings.allowRunLua
            and "run_lua tool ENABLED — the AI may execute Luau code directly."
            or "run_lua tool DISABLED — the AI can only use the fixed built-in tools.",
            AI.settings.allowRunLua and "warn" or "info", 3.5)
    end)

    instrBox.FocusLost:Connect(function()
        AI.settings.instructions = tostring(instrBox.Text)
        saveAiSettings()
    end)

    saveButton.Activated:Connect(function()
        AI.settings.apiKey = tostring(keyBox.Text):gsub("^%s+", ""):gsub("%s+$", "")
        AI.settings.instructions = tostring(instrBox.Text)
        saveAiSettings()
        notify("AI settings saved to " .. AI_SETTINGS_FILE .. ".", "success", 2.5)
        if (AI.settings.apiKey or "") ~= "" and AI.models == nil and not AI.fetchingModels then
            fetchModels(false)
        end
    end)

    -- Header buttons: close, Settings toggle, Clear chat.
    aiHeaderButton("×", -34, function()
        aiWindow.Visible = false
    end, 26)

    local showingSettings = false
    local settingsToggle = aiHeaderButton("Settings", -110, nil, 64)
    settingsToggle.Activated:Connect(function()
        showingSettings = not showingSettings
        if showingSettings then
            openSettingsView()
        else
            openChatView()
        end
    end)
    aiHeaderButton("Clear", -182, function()
        clearChatLog()
    end, 56)

    ------------------------------------------------------------------
    -- PUBLIC: toolbar "AI" button toggles this window
    ------------------------------------------------------------------
    function Editor.openAI()
        if aiWindow.Visible then
            aiWindow.Visible = false
            return
        end
        pcall(function()
            local mp, ms = UI.main.AbsolutePosition, UI.main.AbsoluteSize
            local viewport = workspace.CurrentCamera.ViewportSize
            local x = mp.X + ms.X + 8
            if x + 520 > viewport.X - 4 then
                x = math.max(4, mp.X - 528)
            end
            aiWindow.Position = UDim2.fromOffset(math.floor(x), math.floor(mp.Y))
        end)
        aiWindow.Visible = true
        if (AI.settings.apiKey or "") ~= "" and AI.models == nil and not AI.fetchingModels then
            showingSettings = true
            openSettingsView()
        else
            showingSettings = false
            openChatView()
        end
        scrollChatToBottom()
    end

    table.insert(UI.windows, aiWindow)
end

-- //////////////////////////////////////////////////////////////////////////
-- TOOLBAR WIRING
-- //////////////////////////////////////////////////////////////////////////

do
    UI.makeToolbarButton("+ ScreenGui", function() Editor.spawnClass("ScreenGui") end, { width = 92, order = 1 })
    UI.makeToolbarButton("Add Instance", function() Editor.openAddInstance() end, { width = 84, order = 2 })
    UI.makeToolbarButton("Duplicate", function() Editor.duplicateSelected() end, { width = 76, order = 3 })
    UI.makeToolbarButton("Delete", function() Editor.deleteSelected() end, { width = 60, order = 4 })
    UI.makeToolbarButton("Save", function() Editor.openSave() end, { width = 56, order = 5 })
    UI.makeToolbarButton("Load", function() Editor.openLoad() end, { width = 56, order = 6 })
    UI.makeToolbarButton("Export", function() Editor.openExport() end, { width = 66, order = 7, accent = true })

    -- "Put on CoreGui" toggle — RED when off, GREEN when on.
    do
        local coreBtn = create("TextButton", {
            Size = UDim2.fromOffset(112, 24),
            BackgroundColor3 = THEME.Danger,
            BorderSizePixel = 0,
            Text = "Put on CoreGui",
            TextColor3 = Color3.fromRGB(255, 255, 255),
            Font = Enum.Font.GothamMedium,
            TextSize = 12,
            AutoButtonColor = false,
            ZIndex = 12,
            LayoutOrder = 8,
        }, UI.toolbar)
        create("UICorner", { CornerRadius = UDim.new(0, 5) }, coreBtn)
        coreBtn.MouseEnter:Connect(function()
            coreBtn.BackgroundColor3 = (State.coreGuiMode and THEME.Good or THEME.Danger):Lerp(Color3.new(1, 1, 1), 0.18)
        end)
        coreBtn.MouseLeave:Connect(function()
            Editor.refreshCoreGuiToggle()
        end)
        coreBtn.Activated:Connect(function()
            Editor.setCoreGuiMode(not State.coreGuiMode)
        end)
        UI.coreGuiButton = coreBtn
        Editor.refreshCoreGuiToggle()
    end

    UI.modeButton = UI.makeToolbarButton("Mode: Edit", function()
        Editor.setEditMode(not State.editMode)
    end, { width = 92, order = 9 })

    -- "AI" helper button — toggles the Gemini assistant window.
    UI.makeToolbarButton("AI", function() Editor.openAI() end, { width = 44, order = 10 })
end

-- //////////////////////////////////////////////////////////////////////////
-- RUNTIME LOOPS
-- //////////////////////////////////////////////////////////////////////////

local renderErrorCount = 0
trackConnection(RunService.RenderStepped:Connect(function()
    local ok, err = pcall(function()
        syncSelectionVisuals()
        if explorerDirty then
            explorerDirty = false
            rebuildExplorer()
        end
    end)
    if not ok then
        renderErrorCount += 1
        if renderErrorCount <= 3 then
            warn("[StudioGUI Creator] render loop error: " .. tostring(err))
        end
    end
end))

-- Watchdog: re-parent the overlay if anything ever removes it.
local watchdogTick = 0
trackConnection(RunService.Heartbeat:Connect(function()
    watchdogTick += 1
    if watchdogTick % 300 ~= 0 then return end
    if not Overlay.Parent then
        pcall(function() Overlay.Parent = resolveProtectedParent() end)
    end
end))

-- //////////////////////////////////////////////////////////////////////////
-- BOOTSTRAP
-- //////////////////////////////////////////////////////////////////////////

UI.makeColumnHeader(UI.explorerColumn, "EXPLORER")
UI.makeColumnHeader(UI.propertiesColumn, "PROPERTIES")
PropPanel.init()

explorerScroll = UI.makeScrollList(UI.explorerColumn, 24)

ensureProjectIntegrity()
rebuildExplorer()

local initialGuis = getProjectScreenGuis()
if initialGuis[1] then
    Editor.select(initialGuis[1])
end
updateStatus()

notify("StudioGUI Creator v1.4 loaded — " .. Executor.name, "success", 3.5)
print("[StudioGUI Creator] Ready. Insert from the left panel, 'Add Instance' for any class (LocalScript, ModuleScript, Values...), 'Save'/'Load' for GUI_CREATOR_SAVES files, 'Export' for a standalone Luau script, 'Put on CoreGui' to protect your GUI, and 'AI' for the Gemini assistant — it can call the editor's built-in Luau tools directly (enable 'Allow AI to run code' in AI Settings for raw run_lua).")

end -- main()

local okInit, errInit = pcall(main)
if not okInit then
    warn("[StudioGUI Creator] Initialization error: " .. tostring(errInit))
end
