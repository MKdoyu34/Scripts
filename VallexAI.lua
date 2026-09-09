--[[===========================================================================
        ██    ██  █████  ██      ██     ██ ███████ ███    ██
        ██    ██ ██   ██ ██      ██     ██ ██      ████   ██
        ██    ██ ███████ ██      ██  █  ██ █████   ██ ██  ██
         ██  ██  ██   ██ ██      ██ ███ ██ ██      ██  ██ ██
          ████   ██   ██ ███████  ### ███  ███████ ██   ████

        Vallex AI  —  AI ChatBot GUI for Roblox Executors
        CORE BUILD  (v1.0.0-core)
        ===========================================================================
        SETUP
          1) Host "VallexAIThemes.lua" (GitHub raw / Pastebin raw) and paste the
             URL into CONFIG.ThemesURL below. A local copy saved at
             "Vallex AI File/VallexAIThemes.lua" overrides the remote fetch.
          2) Execute this single script in your executor. Done.

        REQUIREMENTS (executor-only build)
          • HTTP    : request / http_request / syn.request / http.request
          • Files   : writefile / readfile / isfile / isfolder / makefolder / listfiles
          • Storage : "Vallex AI File/"  (States.json, Settings.json, Saved Chats/)

        INCLUDED IN THIS CORE BUILD
          • Full chat UI (rounded + stroked panels, auto-sizing bubbles, fonts)
          • 16 base themes + 70 presets  (external themes module, loadstring'd)
          • Providers: OpenAI / Google DeepMind / Anthropic / DeepSeek / Custom /
            Mock (No Key) — with LIVE model fetching per provider
          • Typewriter reveal, Stop Generating (permanent cut-off), Continue
          • Code blocks: language label, Copy (raw code only), Run (with confirm)
          • Settings: token limits (on/off), instructions, Focus Mode (with cost
            warning), View Mode (Landscape/Portrait), font & theme pickers
          • Persistence: Vallex AI States.json / Vallex AI Settings.json /
            Saved Chats/*.json (raw transcripts, fences intact) + chat browser

        DEFERRED TO PASS 2 (branching system)
          Redo/Reshuffle, N/N branch navigator, Chat.Name_BranchN.json files and
          the "Branching Chat.Name..." indicator. Every integration point is
          marked with  -- BRANCH --  comments so pass 2 can hook in cleanly.
===========================================================================]]--

-- //=======================================================================//--
-- //                                CONFIG                                  //--
-- //=======================================================================//--

local CONFIG = {
        ThemesURL = "https://raw.githubusercontent.com/YOUR_USERNAME/VallexAI/main/VallexAIThemes.lua", -- <<< CHANGE ME
        ScriptVersion = "1.0.0-core",

        StorageFolder = "Vallex AI File",
        SavedChatsFolder = "Vallex AI File/Saved Chats",
        StatesFile = "Vallex AI File/Vallex AI States.json",
        SettingsFile = "Vallex AI File/Vallex AI Settings.json",
        LocalThemesFile = "Vallex AI File/VallexAIThemes.lua",

        RequestTimeout = 120,      -- seconds (hint header for executors that honor it)
        TypewriterDelay = 0.02,    -- seconds per reveal tick
        TypewriterChunk = 4,       -- characters (codepoints) revealed per tick
        DotInterval = 0.45,        -- animated dots interval ("." .. ".." .. "...")
        BubbleMaxRatio = 0.78,     -- player bubble max width vs list width
        AnthropicDefaultMaxTokens = 8192, -- required param when Output limit = unlimited
}

-- //=======================================================================//--
-- //                            SERVICES / ENV                             //--
-- //=======================================================================//--

local Players          = game:GetService("Players")
local HttpService      = game:GetService("HttpService")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
        LocalPlayer = Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
end

-- guarded typeof (exists in executors; plain Lua fallback keeps tooling happy)
local kindof = (typeof ~= nil) and typeof or function(v)
        return type(v)
end

-- //=======================================================================//--
-- //                          HTTP FALLBACK CHAIN                          //--
-- //=======================================================================//--

local HTTP = nil
do
        local candidates = {}
        if kindof(request) == "function" then table.insert(candidates, { name = "request", fn = request }) end
        if kindof(http_request) == "function" then table.insert(candidates, { name = "http_request", fn = http_request }) end
        if kindof(syn) == "table" and kindof(syn.request) == "function" then
                table.insert(candidates, { name = "syn.request", fn = syn.request })
        end
        if kindof(http) == "table" and kindof(http.request) == "function" then
                table.insert(candidates, { name = "http.request", fn = http.request })
        end
        if kindof(request) == "table" and kindof(request.request) == "function" then
                table.insert(candidates, { name = "request.request", fn = request.request })
        end
        if #candidates > 0 then
                HTTP = candidates[1]
        end
end

--- Normalized HTTP call. opts: { Url, Method, Headers, Body, Timeout? }
--- returns ok:boolean, response|errText where response = { body, code, headers }
local function httpRequest(opts)
        if not HTTP then
                return false, "No executor HTTP function found (request/http_request/syn.request)."
        end
        if kindof(opts.Headers) ~= "table" then opts.Headers = {} end
        opts.Headers = opts.Headers or {}
        if opts.Timeout then
                -- hint only; honored by some executors, ignored elsewhere
                opts.Timeout = CONFIG.RequestTimeout
        end
        local ok, resp = pcall(HTTP.fn, opts)
        if not ok then
                return false, tostring(resp)
        end
        if kindof(resp) ~= "table" then
                return false, "HTTP returned a non-table response"
        end
        local body = resp.Body or resp.body or resp.bodyBytes or resp.BodyBytes or ""
        local code = resp.StatusCode or resp.statusCode or resp.code or 0
        return true, {
                body = tostring(body),
                code = tonumber(code) or 0,
                headers = resp.Headers or resp.headers or {},
        }
end

-- //=======================================================================//--
-- //                        FILESYSTEM FALLBACK CHAIN                      //--
-- //=======================================================================//--

local FS = {}
do
        local _read = readfile
        local _write = writefile
        local _isfile = isfile
        local _isfolder = isfolder
        local _make = makefolder
        local _list = listfiles

        FS.available = (kindof(_write) == "function") and (kindof(_read) == "function")

        function FS.read(path)
                if kindof(_read) ~= "function" then return nil end
                local ok, res = pcall(_read, path)
                if ok then return res end
                return nil
        end

        function FS.write(path, data)
                if kindof(_write) ~= "function" then return false end
                local ok, err = pcall(_write, path, data)
                return ok, err
        end

        function FS.isFile(path)
                if kindof(_isfile) == "function" then
                        local ok, res = pcall(_isfile, path)
                        if ok then return res end
                end
                return FS.read(path) ~= nil
        end

        function FS.isFolder(path)
                if kindof(_isfolder) == "function" then
                        local ok, res = pcall(_isfolder, path)
                        if ok then return res end
                end
                return false
        end

        function FS.makeFolder(path)
                if kindof(_make) == "function" then
                        return select(1, pcall(_make, path))
                end
                return false
        end

        function FS.list(path)
                if kindof(_list) == "function" then
                        local ok, res = pcall(_list, path)
                        if ok and kindof(res) == "table" then return res end
                end
                return {}
        end

        function FS.ensureFolder(path)
                if not FS.isFolder(path) then FS.makeFolder(path) end
        end
end

-- //=======================================================================//--
-- //                               HELPERS                                 //--
-- //=======================================================================//--

local function jsonEncode(tbl)
        local ok, res = pcall(function() return HttpService:JSONEncode(tbl) end)
        if ok then return res end
        return "{}"
end

local function jsonDecode(str)
        if kindof(str) ~= "string" or #str == 0 then return nil end
        local ok, res = pcall(function() return HttpService:JSONDecode(str) end)
        if ok then return res end
        return nil
end

local function deepFill(defaults, target)
        if kindof(defaults) ~= "table" then return target end
        target = (kindof(target) == "table") and target or {}
        for k, v in pairs(defaults) do
                if target[k] == nil then
                        target[k] = (kindof(v) == "table") and deepFill(v, {}) or v
                elseif kindof(v) == "table" and kindof(target[k]) == "table" then
                        deepFill(v, target[k])
                end
        end
        return target
end

local function sanitizeFilename(name)
        name = tostring(name):gsub("[^%w%s%-_%()", ""):gsub("%s+", " ")
        name = name:gsub("^%s+", ""):gsub("%s+$", "")
        if #name == 0 then name = "Chat" end
        return name
end

local function shallowCopy(t)
        local out = {}
        for k, v in pairs(t) do out[k] = v end
        return out
end

local function getClipboardFn()
        if kindof(setclipboard) == "function" then return setclipboard end
        if kindof(toclipboard) == "function" then return toclipboard end
        return nil
end

-- (explicit chain; kept separate for clarity)
local Clipboard = nil
if kindof(setclipboard) == "function" then
        Clipboard = setclipboard
elseif kindof(toclipboard) == "function" then
        Clipboard = toclipboard
end

local function copyToClipboard(text)
        if Clipboard then
                local ok = pcall(Clipboard, text)
                return ok
        end
        return false
end

local function loadstringSafe(src, chunk)
        if kindof(loadstring) == "function" then
                local ok, fn = pcall(loadstring, src, chunk or "=vallex")
                if ok then return fn end
                return nil, fn
        end
        -- fall back to load where available
        if kindof(load) == "function" then
                local fn, err = load(src, chunk or "=vallex")
                return fn, err
        end
        return nil, "no loadstring/load available"
end

-- //=======================================================================//--
-- //                       THEME LOADER (split setup)                      //--
-- //=======================================================================//--

-- Built-in offline fallback (always present; remote themes merge on top)
local BuiltinThemes = {}
local function addBuiltin(name, bg, surface, accent, text)
        local dark = (0.299 * bg.R + 0.587 * bg.G + 0.114 * bg.B) < 0.5
        local txt = text or (dark and Color3.fromRGB(235, 235, 240) or Color3.fromRGB(28, 28, 34))
        BuiltinThemes[name] = {
                Name = name,
                Background = bg,
                Surface = surface,
                Accent = accent,
                Text = txt,
                SubText = Color3.new(
                        txt.R + (bg.R - txt.R) * 0.42,
                        txt.G + (bg.G - txt.G) * 0.42,
                        txt.B + (bg.B - txt.B) * 0.42
                ),
                Stroke = dark and Color3.fromRGB(60, 60, 78) or Color3.fromRGB(206, 208, 216),
                Success = Color3.fromRGB(87, 242, 135),
                Error = Color3.fromRGB(237, 66, 69),
                OnAccent = (0.299 * accent.R + 0.587 * accent.G + 0.114 * accent.B) > 0.62
                        and Color3.fromRGB(24, 24, 28) or Color3.fromRGB(255, 255, 255),
        }
end

addBuiltin("Dark",  Color3.fromRGB(18, 18, 24),    Color3.fromRGB(28, 28, 36),    Color3.fromRGB(88, 101, 242))
addBuiltin("Light", Color3.fromRGB(243, 244, 248), Color3.fromRGB(255, 255, 255), Color3.fromRGB(88, 101, 242))

local Themes = shallowCopy(BuiltinThemes)
local ThemesSource = "builtin"

local function mergeExternalThemes(mod)
        if kindof(mod) ~= "table" then return 0 end
        local n = 0
        for name, palette in pairs(mod) do
                if kindof(palette) == "table" and kindof(palette.Background) == "Color3" then
                        palette.Name = name
                        Themes[name] = palette
                        n = n + 1
                end
        end
        return n
end

do
        -- 1) local override file wins
        if FS.isFile(CONFIG.LocalThemesFile) then
                local src = FS.read(CONFIG.LocalThemesFile)
                local fn = src and loadstringSafe(src, "=VallexAIThemes(local)")
                if fn then
                        local ok, mod = pcall(fn)
                        local n = ok and mergeExternalThemes(mod) or 0
                        if n > 0 then ThemesSource = "local file" end
                end
        end
        -- 2) remote fetch (only if local file did not provide themes)
        if ThemesSource == "builtin" then
                if HTTP then
                        local ok, resp = httpRequest({ Url = CONFIG.ThemesURL, Method = "GET", Headers = {} })
                        if ok and resp.code == 200 and #resp.body > 40 then
                                local fn = loadstringSafe(resp.body, "=VallexAIThemes(remote)")
                                if fn then
                                        local ok2, mod = pcall(fn)
                                        local n = ok2 and mergeExternalThemes(mod) or 0
                                        if n > 0 then
                                                ThemesSource = "remote (" .. tostring(n) .. " themes)"
                                        end
                                end
                        end
                end
        end
        if ThemesSource == "builtin" then
                warn("[Vallex AI] External themes not found — using built-in Dark/Light fallback. " ..
                        "Set CONFIG.ThemesURL or drop VallexAIThemes.lua into '" .. CONFIG.StorageFolder .. "'.")
        else
                print("[Vallex AI] Themes loaded from " .. ThemesSource)
        end
end

-- //=======================================================================//--
-- //                    THEME / FONT REGISTRY + APPLY                      //--
-- //=======================================================================//--

local CurrentThemeName = "Dark"
local ThemeRegistry = {}   -- { {obj, prop, role} }
local ThemeRefreshers = {} -- { fn } called after re-coloring registry entries

local function RoleColor(role)
        local t = Themes[CurrentThemeName]
        if not t then return Color3.fromRGB(255, 0, 255) end
        return t[role] or t.Text
end

local function registerTheme(obj, prop, role)
        if not obj then return end
        table.insert(ThemeRegistry, { obj = obj, prop = prop, role = role })
        if obj and obj.Parent ~= nil then
                pcall(function() obj[prop] = RoleColor(role) end)
        end
end

local function registerRefresher(fn)
        table.insert(ThemeRefreshers, fn)
end

local function ApplyTheme(name)
        if not Themes[name] then return false end
        CurrentThemeName = name
        for _, entry in ipairs(ThemeRegistry) do
                pcall(function()
                        entry.obj[entry.prop] = RoleColor(entry.role)
                end)
        end
        for _, fn in ipairs(ThemeRefreshers) do
                pcall(fn)
        end
        return true
end

-- Fonts ---------------------------------------------------------------------
local UIFontNames = {
        "Legacy", "Arial", "ArialBold", "SourceSans", "SourceSansBold", "SourceSansSemibold",
        "SourceSansLight", "Gotham", "GothamMedium", "GothamBold", "GothamBlack",
        "Nunito", "Roboto", "RobotoCondensed", "RobotoMono", "FredokaOne", "Bangers",
        "Creepster", "DenkOne", "GrenzeGotisch", "IndieFlower", "JosefinSans", "Kalam",
        "LuckiestGuy", "Merriweather", "Michroma", "Oswald", "PatrickHand",
        "PermanentMarker", "Sarpanch", "SpecialElite", "TitilliumWeb", "Ubuntu",
}

local CurrentFontName = "Gotham"
local FontRegistry = {} -- { {obj, kind} }  kind: "Regular" | "Bold"  (Mono is fixed)

local function applyFontKind(obj, kind)
        if kind == "Mono" then
                -- code panels are always monospaced (spec R4/§9)
                pcall(function() obj.Font = Enum.Font.RobotoMono end)
                return
        end
        local name = (kind == "Bold") and (CurrentFontName .. "Bold") or CurrentFontName
        -- direct names that are not "X + Bold" composable fall back below
        local ok = pcall(function() obj.Font = Enum.Font[name] end)
        if not ok then
                pcall(function() obj.Font = Enum.Font[CurrentFontName] end)
        end
end

local function registerFont(obj, kind)
        if not obj then return end
        table.insert(FontRegistry, { obj = obj, kind = kind or "Regular" })
        applyFontKind(obj, kind or "Regular")
end

local function ApplyFont(name)
        if not name then return false end
        local probe = Instance.new("TextLabel")
        local ok = pcall(function() probe.Font = Enum.Font[name] end)
        probe:Destroy()
        if not ok then return false end
        CurrentFontName = name
        for _, entry in ipairs(FontRegistry) do
                applyFontKind(entry.obj, entry.kind)
        end
        return true
end

-- NOTE: Enum.Font.XBold does not exist for every face; normalize a few names.
-- (GothamMedium/GothamBlack etc. map directly; "XBold" handled above.)

-- //=======================================================================//--
-- //                    FORWARD DECLARATIONS (cross-part)                  //--
-- //=======================================================================//--

local States, Settings            -- persistence tables (part 3)
local ScreenGui                   -- root gui (part 4)
local saveStatesNow, saveSettingsNow
local saveCurrentChat, loadChatFile, startNewChat, listSavedChats
local renderTranscript, refreshIdeaChips
local sendUserMessage, triggerGenerate, continueFromCutoff, stopGeneration
local applyViewMode, refreshHeaderTitle
local refreshModelsDropdown, applyFontAndSave
local Generating, StopRequested = false, false

-- //=======================================================================//--
-- //                         UI COMPONENT LIBRARY                          //--
-- //=======================================================================//--

local function mk(class, props, parent)
        local inst = Instance.new(class)
        if props then
                for k, v in pairs(props) do
                        if k ~= "Parent" then
                                inst[k] = v
                        end
                end
        end
        inst.Parent = parent or ScreenGui
        return inst
end

local function addCorner(obj, px)
        return mk("UICorner", { CornerRadius = UDim.new(0, px or 10) }, obj)
end

local function addStroke(obj, role, thickness, transparency)
        local s = mk("UIStroke", {
                Thickness = thickness or 1,
                Color = RoleColor(role or "Stroke"),
                Transparency = transparency or 0,
                ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        }, obj)
        registerTheme(s, "Color", role or "Stroke")
        return s
end

local function addPadding(obj, l, t, r, b)
        return mk("UIPadding", {
                PaddingLeft = UDim.new(0, l or 0), PaddingTop = UDim.new(0, t or 0),
                PaddingRight = UDim.new(0, r or 0), PaddingBottom = UDim.new(0, b or 0),
        }, obj)
end

--- Text label with font registration
local function mkText(props, parent, kind)
        props = props or {}
        props.BackgroundTransparency = (props.BackgroundTransparency == nil) and 1 or props.BackgroundTransparency
        props.RichText = false
        local lbl = mk("TextLabel", props, parent)
        registerFont(lbl, kind or "Regular")
        return lbl
end

--- hover overlay for buttons (theme-agnostic)
local function hoverify(btn, radius)
        local ov = mk("Frame", {
                Name = "Hover", Size = UDim2.new(1, 0, 1, 0), ZIndex = btn.ZIndex + 2,
                BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
        }, btn)
        addCorner(ov, radius or 10)
        btn.MouseEnter:Connect(function()
                TweenService:Create(ov, TweenInfo.new(0.12), { BackgroundTransparency = 0.86 }):Play()
        end)
        btn.MouseLeave:Connect(function()
                TweenService:Create(ov, TweenInfo.new(0.12), { BackgroundTransparency = 1 }):Play()
        end)
end

--- Standard themed button.
--- variants: "primary" (accent bg), "surface" (surface bg), "ghost" (transparent), "danger" (error bg)
local function mkButton(props, parent)
        props = props or {}
        local variant = props.Variant or "surface"
        local bgRole, fgRole
        if variant == "primary" then bgRole, fgRole = "Accent", "OnAccent"
        elseif variant == "danger" then bgRole, fgRole = "Error", "OnAccent"
        elseif variant == "ghost" then bgRole, fgRole = nil, "Text"
        else bgRole, fgRole = "Surface", "Text" end

        local base = {
                AutoButtonColor = false, Text = props.Text or "",
                Font = Enum.Font.GothamBold, TextSize = props.TextSize or 13,
                TextColor3 = RoleColor(fgRole), BackgroundColor3 = bgRole and RoleColor(bgRole) or RoleColor("Surface"),
                BackgroundTransparency = (variant == "ghost") and 1 or 0,
                BorderSizePixel = 0,
        }
        if props.Size then base.Size = props.Size end
        if props.Position then base.Position = props.Position end
        if props.AnchorPoint then base.AnchorPoint = props.AnchorPoint end
        if props.LayoutOrder then base.LayoutOrder = props.LayoutOrder end
        if props.ZIndex then base.ZIndex = props.ZIndex end
        if props.TextWrapped ~= nil then base.TextWrapped = props.TextWrapped end
        if props.TextXAlignment then base.TextXAlignment = props.TextXAlignment end

        local btn = mk("TextButton", base, parent)
        registerTheme(btn, "TextColor3", fgRole)
        if bgRole then registerTheme(btn, "BackgroundColor3", bgRole) end
        registerFont(btn, props.Bold == false and "Regular" or "Bold")
        addCorner(btn, props.CornerRadius or 10)
        if props.Stroke ~= false and variant ~= "ghost" then
                addStroke(btn, (variant == "surface") and "Stroke" or bgRole, 1, 0.35)
        end
        hoverify(btn, props.CornerRadius or 10)
        if kindof(props.OnClick) == "function" then
                btn.MouseButton1Click:Connect(function()
                        local ok, err = pcall(props.OnClick)
                        if not ok then warn("[Vallex AI] button error: " .. tostring(err)) end
                end)
        end
        return btn
end

-- // toggle switch ------------------------------------------------------------
local Toggles = {} -- refreshers handled via ThemeRefreshers

local function mkToggle(parent, initial, onChanged, order)
        local state = (initial == true)
        local holder = mk("Frame", {
                Size = UDim2.new(0, 44, 0, 24), BackgroundTransparency = 1, LayoutOrder = order or 0,
        }, parent)
        local pill = mk("TextButton", {
                Name = "Pill", Size = UDim2.new(1, 0, 1, 0), AutoButtonColor = false, Text = "", BorderSizePixel = 0,
                BackgroundColor3 = RoleColor(state and "Success" or "Surface"),
        }, holder)
        addCorner(pill, 12)
        addStroke(pill, "Stroke", 1, 0.4)
        local knob = mk("Frame", {
                Size = UDim2.new(0, 18, 0, 18), Position = UDim2.new(0, state and 23 or 3, 0.5, -9),
                BackgroundColor3 = Color3.fromRGB(255, 255, 255), BorderSizePixel = 0, ZIndex = 2,
        }, pill)
        addCorner(knob, 9)

        local function paint()
                pill.BackgroundColor3 = RoleColor(state and "Success" or "Surface")
        end
        registerRefresher(paint)

        local function set(v, silent)
                state = (v == true)
                TweenService:Create(knob, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                        { Position = UDim2.new(0, state and 23 or 3, 0.5, -9) }):Play()
                paint()
                if not silent and kindof(onChanged) == "function" then onChanged(state) end
        end
        pill.MouseButton1Click:Connect(function() set(not state) end)

        return { Holder = holder, Get = function() return state end, Set = set }
end

-- // dropdown -----------------------------------------------------------------
local DropdownLayer = nil -- created in part 4 (parented to ScreenGui)

--- opts: { Options = fn|table, Current = string, OnPick = fn(value), Placeholder = string, Width = number }
local function mkDropdown(parent, opts)
        opts = opts or {}
        local current = opts.Current or ""

        local btn = mkButton({
                Size = opts.Size or UDim2.new(1, 0, 0, 30), TextSize = 12, CornerRadius = 8,
        }, parent)
        local arrow = mkText({
                Size = UDim2.new(0, 18, 1, 0), Position = UDim2.new(1, -20, 0, 0),
                Text = "▾", TextSize = 12, TextColor3 = RoleColor("SubText"), Name = "Arrow",
        }, btn)
        registerTheme(arrow, "TextColor3", "SubText")
        local value = mkText({
                Size = UDim2.new(1, -44, 1, 0), Position = UDim2.new(0, 10, 0, 0),
                Text = current, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd, Name = "Value",
        }, btn)
        registerTheme(value, "TextColor3", "Text")

        local api = {}

        local function resolveOptions()
                local o = opts.Options
                if kindof(o) == "function" then
                        local ok, res = pcall(o)
                        if ok and kindof(res) == "table" then return res end
                        return {}
                end
                return kindof(o) == "table" and o or {}
        end

        local function setValue(v)
                current = v
                value.Text = (v ~= "" and v) or (opts.Placeholder or "Select...")
        end

        local function open()
                if not DropdownLayer then return end
                local list = resolveOptions()
                local width = opts.Width or btn.AbsoluteSize.X
                local popupH = math.max(40, math.min(#list * 29 + 10, 240))
                local blocker = mk("TextButton", {
                        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", ZIndex = 40,
                }, DropdownLayer)
                local popup = mk("Frame", {
                        Size = UDim2.new(0, width, 0, popupH),
                        Position = UDim2.new(0, btn.AbsolutePosition.X, 0, btn.AbsolutePosition.Y + btn.AbsoluteSize.Y + 4),
                        BackgroundColor3 = RoleColor("Surface"), BorderSizePixel = 0, ZIndex = 41,
                        ClipsDescendants = true,
                }, DropdownLayer)
                addCorner(popup, 10)
                addStroke(popup, "Accent", 1, 0.2)
                addPadding(popup, 4, 4, 4, 4)
                local scroll = mk("ScrollingFrame", {
                        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
                        CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
                        ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 4, ZIndex = 42,
                }, popup)
                mk("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
                for i, optName in ipairs(list) do
                        local ob = mkButton({
                                Size = UDim2.new(1, 0, 0, 26), Text = tostring(optName), TextSize = 12,
                                Variant = "surface", CornerRadius = 7, ZIndex = 43, LayoutOrder = i,
                                OnClick = function()
                                        setValue(tostring(optName))
                                        blocker:Destroy()
                                        popup:Destroy()
                                        if kindof(opts.OnPick) == "function" then opts.OnPick(tostring(optName)) end
                                end,
                        }, scroll)
                        ob.ZIndex = 43
                end
                blocker.MouseButton1Click:Connect(function()
                        blocker:Destroy()
                        popup:Destroy()
                end)
        end

        btn.MouseButton1Click:Connect(open)

        api.Get = function() return current end
        api.Set = setValue
        api.SetOptions = function(tbl) opts.Options = tbl end
        api.Button = btn
        return api
end

-- // modal dialog -------------------------------------------------------------
local DialogLayer = nil -- created in part 4

--- mkDialog({ Title, Message, Buttons = {{Id, Text, Variant}, ...}, OnResult = fn(id|nil), Width })
local function mkDialog(info)
        if not DialogLayer then return end
        local width = info.Width or 320
        local blocker = mk("TextButton", {
                Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0),
                BackgroundTransparency = 0.45, Text = "", ZIndex = 60, AutoButtonColor = false,
        }, DialogLayer)
        local card = mk("Frame", {
                Size = UDim2.new(0, width, 0, 0), AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(0.5, 0, 0.5, 0), BackgroundColor3 = RoleColor("Surface"),
                BorderSizePixel = 0, ZIndex = 61, AutomaticSize = Enum.AutomaticSize.Y,
        }, blocker)
        addCorner(card, 14)
        addStroke(card, "Accent", 1.4, 0.15)
        addPadding(card, 16, 14, 16, 14)
        mk("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, card)

        local title = mkText({
                Size = UDim2.new(1, 0, 0, 18), Text = info.Title or "Confirm", TextSize = 15,
                TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 62, LayoutOrder = 1,
        }, card, "Bold")
        registerTheme(title, "TextColor3", "Text")

        local msg = mkText({
                Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
                Text = info.Message or "", TextSize = 12, TextWrapped = true,
                TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
                ZIndex = 62, LayoutOrder = 2,
        }, card, "Regular")
        registerTheme(msg, "TextColor3", "SubText")

        local row = mk("Frame", {
                Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, ZIndex = 62, LayoutOrder = 3,
        }, card)
        local rowLayout = mk("UIListLayout", {
                Padding = UDim.new(0, 8), FillDirection = Enum.FillDirection.Horizontal,
                HorizontalAlignment = Enum.HorizontalAlignment.Right, SortOrder = Enum.SortOrder.LayoutOrder,
        }, row)

        for i, bdef in ipairs(info.Buttons or {}) do
                mkButton({
                        Size = UDim2.new(0, bdef.Width or 130, 0, 32), Text = bdef.Text or bdef.Id,
                        Variant = bdef.Variant or "primary", TextSize = 12, ZIndex = 63, LayoutOrder = i,
                        OnClick = function()
                                blocker:Destroy()
                                if kindof(info.OnResult) == "function" then info.OnResult(bdef.Id) end
                        end,
                }, row)
        end

        blocker.MouseButton1Click:Connect(function()
                blocker:Destroy()
                if kindof(info.OnResult) == "function" then info.OnResult(nil) end
        end)
        return blocker
end

--- convenience: two-confirm dialogs where every button confirms ("Okay" / "I know what I'm doing!")
local function confirmAll(info)
        local buttons = {}
        for i, b in ipairs(info.Buttons or {}) do
                table.insert(buttons, { Id = b, Text = b, Variant = (i == 1) and "primary" or "surface" })
        end
        mkDialog({
                Title = info.Title, Message = info.Message, Buttons = buttons,
                OnResult = function(id)
                        if kindof(info.OnConfirm) == "function" then info.OnConfirm(id) end
                end,
        })
end

-- // toast --------------------------------------------------------------------
local ToastFrame = nil -- created in part 4

local function showToast(text, kind)
        if not ToastFrame then return end
        local color = RoleColor((kind == "error" and "Error") or (kind == "success" and "Success") or "Accent")
        ToastFrame.BackgroundColor3 = color
        ToastFrame.TextLabel.Text = tostring(text)
        ToastFrame.Visible = true
        ToastFrame.Position = UDim2.new(0.5, 0, 1, 20)
        ToastFrame.AnchorPoint = Vector2.new(0.5, 1)
        TweenService:Create(ToastFrame, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                { Position = UDim2.new(0.5, 0, 1, 90) }):Play()
        task.delay(2.2, function()
                if ToastFrame and ToastFrame.Visible then
                        local tw = TweenService:Create(ToastFrame, TweenInfo.new(0.2), { Position = UDim2.new(0.5, 0, 1, 40) })
                        tw:Play()
                        tw.Completed:Wait()
                        if ToastFrame.Position.Y.Offset >= 40 then ToastFrame.Visible = false end
                end
        end)
end

-- // dragging -----------------------------------------------------------------
local function makeDraggable(handle, target)
        local dragging, dragStart, startPos = false, nil, nil
        handle.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                        dragging = true
                        dragStart = input.Position
                        startPos = target.Position
                        input.Changed:Connect(function()
                                if input.UserInputState == Enum.UserInputState.End then dragging = false end
                        end)
                end
        end)
        UserInputService.InputChanged:Connect(function(input)
                if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                        local delta = input.Position - dragStart
                        target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
                end
        end)
end

-- //=======================================================================//--
-- //         PERSISTENCE — "Vallex AI File" (States / Settings / Chats)    //--
-- //=======================================================================//--

-- Vallex AI States.json — session-ish state (spec §8)
local DefaultStates = {
        TokenLimitEnabled = { Input = false, Output = false },
        LastSelectedProvider = "OpenAI",
        LastTheme = "Dark",
        SidebarOpen = true,
        FocusModeEnabled = false,
        -- extensions (backward compatible additions)
        Font = "Gotham",
        LastChat = "",
        ViewMode = "Landscape",
        ChatIndex = {}, -- [[BRANCH]] pass 2: { [chatName] = { Branches = {...}, ActiveBranch = "..." } }
}

-- Vallex AI Settings.json — per-provider config (spec §8)
local DefaultSettings = {
        OpenAI = {
                model = { selectedmodel = "GPT-4O-Mini" },
                savedapikey = { APIkey = "" },
        },
        ["Google DeepMind"] = {
                model = { selectedmodel = "Gemini-3.6-Flash" },
                savedapikey = { APIkey = "" },
        },
        Anthropic = {
                model = { selectedmodel = "Sonnet-4.6" },
                savedapikey = { APIkey = "" },
        },
        DeepSeek = {
                model = { selectedmodel = "DeepSeek-V4" },
                savedapikey = { APIkey = "" },
        },
        Custom = {
                baseurl = { baseurl = "" },
                ainame = { name = "CustomAI" },
                model = { selectedmodel = "GPT-4O-Mini" },
                savedapikey = { APIkey = "" },
                authheaderformat = { format = "Bearer" },
                customheadername = { name = "" },
                requestformat = { format = "OpenAI" },
                streaming = { enabled = true },
        },
        TokenLimits = {
                Input = { enabled = false, value = 4096 },
                Output = { enabled = false, value = 2048 },
        },
        FocusMode = { enabled = false, interval = 5 },
        ViewMode = "Landscape",
        Instructions = "",
}

local function ensureStorageFolders()
        FS.ensureFolder(CONFIG.StorageFolder)
        FS.ensureFolder(CONFIG.SavedChatsFolder)
end

local function loadStates()
        local raw = FS.isFile(CONFIG.StatesFile) and FS.read(CONFIG.StatesFile) or nil
        local decoded = raw and jsonDecode(raw) or nil
        States = deepFill(DefaultStates, decoded)
        return States
end

local function loadSettings()
        local raw = FS.isFile(CONFIG.SettingsFile) and FS.read(CONFIG.SettingsFile) or nil
        local decoded = raw and jsonDecode(raw) or nil
        Settings = deepFill(DefaultSettings, decoded)
        return Settings
end

saveStatesNow = function()
        if not FS.available then return end
        -- keep spec's TokenLimitEnabled mirror in sync with Settings.TokenLimits
        States.TokenLimitEnabled = {
                Input = Settings.TokenLimits.Input.enabled,
                Output = Settings.TokenLimits.Output.enabled,
        }
        States.FocusModeEnabled = Settings.FocusMode.enabled
        States.ViewMode = Settings.ViewMode
        FS.write(CONFIG.StatesFile, jsonEncode(States))
end

saveSettingsNow = function()
        if not FS.available then return end
        FS.write(CONFIG.SettingsFile, jsonEncode(Settings))
end

-- // chat transcript serialization (raw, fences intact — spec §8) -------------
local function getAIName()
        if States.LastSelectedProvider == "Custom" then
                local n = Settings.Custom.ainame.name
                if kindof(n) == "string" and #n > 0 then return n end
        end
        return "AI"
end

local function getPlayerName()
        return LocalPlayer.Name
end

local function serializeChat(name, messages)
        local out = { tostring(name), "" }
        for _, m in ipairs(messages) do
                local content = tostring(m.content)
                content = content:gsub("%s+$", "")
                table.insert(out, m.speaker .. ": " .. content)
        end
        return table.concat(out, "\n")
end

--- parse raw transcript back into messages.
--- A new message starts only when the line prefix matches a KNOWN speaker,
--- so code lines like "foo: bar" inside fences stay part of the AI message.
local function parseChatText(text)
        local messages = {}
        local lines = string.split(tostring(text), "\n")
        local chatName = "Chat"
        local started = false
        local current = nil
        local function flush()
                if current then
                        current.content = current.content:gsub("%s+$", "")
                        if #current.content > 0 then table.insert(messages, current) end
                        current = nil
                end
        end
        for i, line in ipairs(lines) do
                if not started then
                        if #line > 0 then
                                chatName = line
                                started = true
                        end
                else
                        local pos = string.find(line, ": ", 1, true)
                        local speaker = pos and string.sub(line, 1, pos - 1) or nil
                        local known = speaker and (speaker == getPlayerName() or speaker == "AI" or speaker == getAIName()) or false
                        if known then
                                flush()
                                current = { speaker = speaker, isPlayer = (speaker == getPlayerName()), content = string.sub(line, pos + 2) }
                        elseif current then
                                current.content = current.content .. "\n" .. line
                        elseif #line > 0 then
                                -- orphan line (unknown speaker) — keep as AI text so nothing is lost
                                current = { speaker = "AI", isPlayer = false, content = line }
                        end
                end
        end
        flush()
        return chatName, messages
end

local function chatFilePath(displayName)
        return CONFIG.SavedChatsFolder .. "/" .. displayName .. ".json"
end

local function uniqueChatName(base)
        base = sanitizeFilename(base)
        local taken = {}
        for _, path in ipairs(FS.list(CONFIG.SavedChatsFolder)) do
                local fname = tostring(path):match("([^/\\]+)$") or ""
                fname = fname:gsub("%.json$", "")
                taken[fname] = true
        end
        if not taken[base] then return base end
        local n = 2
        while taken[base .. " (" .. tostring(n) .. ")"] do n = n + 1 end
        return base .. " (" .. tostring(n) .. ")"
end

-- // current chat state -------------------------------------------------------
local CurrentChat = {
        name = "New Chat",
        messages = {}, -- { { speaker, isPlayer, content, cutOff } }
}

local function isKnownChatLoaded()
        return CurrentChat.name ~= "New Chat"
end

saveCurrentChat = function()
        if not FS.available then return end
        if #CurrentChat.messages == 0 then return end
        local displayName = sanitizeFilename(CurrentChat.name)
        local path = chatFilePath(displayName)
        if not FS.isFile(path) then
                displayName = uniqueChatName(CurrentChat.name)
                CurrentChat.name = displayName
                refreshHeaderTitle()
        end
        FS.write(chatFilePath(displayName), serializeChat(displayName, CurrentChat.messages))
        States.LastChat = displayName
        if saveStatesNow then saveStatesNow() end
end

--- load a saved chat by display name (without extension)
loadChatFile = function(displayName)
        local path = chatFilePath(displayName)
        local raw = FS.isFile(path) and FS.read(path) or nil
        if not raw then
                showToast("Chat file not found: " .. tostring(displayName), "error")
                return false
        end
        local parsedName, messages = parseChatText(raw)
        CurrentChat.name = displayName
        CurrentChat.messages = messages
        States.LastChat = displayName
        if saveStatesNow then saveStatesNow() end
        refreshHeaderTitle()
        -- renderTranscript is defined in part 5; safe to call at runtime
        if kindof(renderTranscript) == "function" then renderTranscript() end
        showToast("Loaded chat: " .. tostring(displayName), "success")
        return true
end

startNewChat = function()
        saveCurrentChat()
        CurrentChat.name = "New Chat"
        CurrentChat.messages = {}
        States.LastChat = ""
        refreshHeaderTitle()
        if kindof(renderTranscript) == "function" then renderTranscript() end
        showToast("New chat started", "success")
end

listSavedChats = function()
        local out = {}
        for _, path in ipairs(FS.list(CONFIG.SavedChatsFolder)) do
                local fname = tostring(path):match("([^/\\]+)$") or ""
                fname = fname:gsub("%.json$", "")
                if #fname > 0 and fname ~= "New Chat" then
                        table.insert(out, fname)
                end
        end
        table.sort(out)
        return out
end

-- load persisted state immediately — the GUI parts below read States/Settings
ensureStorageFolders()
loadStates()
loadSettings()

-- //=======================================================================//--
-- //                           ROOT GUI CONSTRUCTION                       //--
-- //=======================================================================//--

-- pick a safe parent (executor build): gethui -> CoreGui -> PlayerGui
local guiParent = (function()
	if kindof(gethui) == "function" then
		local ok, h = pcall(gethui)
		if ok and h then return h end
	end
	local okC, coreGui = pcall(function() return game:GetService("CoreGui") end)
	if okC and coreGui then
		local okW = pcall(function()
			local probe = Instance.new("Folder")
			probe.Parent = coreGui
			probe:Destroy()
		end)
		if okW then return coreGui end
	end
	return LocalPlayer:WaitForChild("PlayerGui")
end)()

-- re-execute safety: destroy any previous instance
do
	local existing = guiParent:FindFirstChild("VallexAI")
	if existing then existing:Destroy() end
end

ScreenGui = mk("ScreenGui", {
	Name = "VallexAI", ResetOnSpawn = false, IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 9999,
}, guiParent)

-- full-screen layers for popups / dialogs / toasts
DropdownLayer = mk("Frame", { Name = "DropdownLayer", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1 }, ScreenGui)
DialogLayer   = mk("Frame", { Name = "DialogLayer",   Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1 }, ScreenGui)

ToastFrame = mk("Frame", {
	Name = "Toast", Size = UDim2.new(0, 320, 0, 34), AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, 40), BackgroundColor3 = RoleColor("Accent"),
	BorderSizePixel = 0, Visible = false, ZIndex = 80,
}, ScreenGui)
addCorner(ToastFrame, 10)
addStroke(ToastFrame, "Stroke", 1, 0.4)
local toastLbl = mkText({
	Name = "TextLabel", Size = UDim2.new(1, -16, 1, 0), Position = UDim2.new(0, 8, 0, 0),
	Text = "", TextSize = 13, TextWrapped = true, ZIndex = 81,
}, ToastFrame, "Bold")
registerTheme(toastLbl, "TextColor3", "OnAccent")

-- // side tab toggle (🟰 open / ✖️ close) --------------------------------------
local SideTab = mk("TextButton", {
	Name = "SideTab", Size = UDim2.new(0, 46, 0, 46), Position = UDim2.new(0, 14, 0, 14),
	BackgroundColor3 = RoleColor("Surface"), AutoButtonColor = false, Text = "🟰",
	TextSize = 20, TextColor3 = RoleColor("Text"), BorderSizePixel = 0, ZIndex = 20,
}, ScreenGui)
addCorner(SideTab, 12)
addStroke(SideTab, "Accent", 1.4, 0.1)
registerTheme(SideTab, "TextColor3", "Text")
registerFont(SideTab, "Regular")
hoverify(SideTab, 12)
makeDraggable(SideTab, SideTab)

-- // main window ----------------------------------------------------------------
local WINDOW_SIZES = { Landscape = Vector2.new(560, 400), Portrait = Vector2.new(340, 480) }
local MainWindow = mk("Frame", {
	Name = "MainWindow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.new(0, 560, 0, 400), BackgroundColor3 = RoleColor("Background"),
	BorderSizePixel = 0, Active = true, ZIndex = 10,
}, ScreenGui)
addCorner(MainWindow, 14)
addStroke(MainWindow, "Accent", 1.6, 0.05)
registerTheme(MainWindow, "BackgroundColor3", "Background")

local HEADER_H, IDEA_H, INPUT_H = 54, 30, 44

-- header
local HeaderBar = mk("Frame", {
	Name = "Header", Size = UDim2.new(1, 0, 0, HEADER_H), BackgroundTransparency = 1, ZIndex = 11,
}, MainWindow)

local ChatTitle = mkText({
	Name = "ChatTitle", Position = UDim2.new(0, 14, 0, 9), Size = UDim2.new(1, -220, 0, 18),
	Text = "New Chat", TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 12,
}, HeaderBar, "Bold")
registerTheme(ChatTitle, "TextColor3", "Text")

local GreetingLabel = mkText({
	Name = "Greeting", Position = UDim2.new(0, 14, 0, 30), Size = UDim2.new(1, -220, 0, 14),
	Text = "", TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 12,
}, HeaderBar, "Regular")
registerTheme(GreetingLabel, "TextColor3", "SubText")

local headerLine = mk("Frame", {
	Name = "HeaderLine", Position = UDim2.new(0, 0, 0, HEADER_H), Size = UDim2.new(1, 0, 0, 1),
	BackgroundColor3 = RoleColor("Stroke"), BorderSizePixel = 0, BackgroundTransparency = 0.35, ZIndex = 12,
}, MainWindow)
registerTheme(headerLine, "BackgroundColor3", "Stroke")

-- header buttons (right side): ➕ 📁 ⚙ ➖ ✕
local function headerIcon(glyph, offset, onClick, tipGlyph)
	local b = mkButton({
		Size = UDim2.new(0, 28, 0, 28), Position = UDim2.new(1, offset, 0.5, -14),
		Text = glyph, TextSize = 13, Variant = "surface", CornerRadius = 8, ZIndex = 13,
		OnClick = onClick,
	}, HeaderBar)
	if tipGlyph then b:SetAttribute("Tip", tipGlyph) end
	return b
end

local NewChatBtn  = headerIcon("➕", -36,  function() startNewChat() end)
local ChatsBtn    = headerIcon("📁", -66,  nil)          -- wired in part 7 (browser)
local SettingsBtn = headerIcon("⚙", -96,  nil)          -- wired in part 7 (settings panel)
local MinimizeBtn = headerIcon("➖", -126, nil)          -- wired below (minimize)
local CloseBtn    = headerIcon("✕", -156, nil)          -- wired below (delete confirm)

-- messages area (R3: AutomaticSize + UIListLayout + UISizeConstraint)
local MessagesScroll = mk("ScrollingFrame", {
	Name = "Messages", Position = UDim2.new(0, 10, 0, HEADER_H + 6),
	Size = UDim2.new(1, -20, 1, -(HEADER_H + IDEA_H + INPUT_H + 24)),
	BackgroundTransparency = 1, BorderSizePixel = 0, CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
	ScrollBarThickness = 4,ScrollBarImageColor3 = RoleColor("SubText"), ZIndex = 11,
}, MainWindow)
registerTheme(MessagesScroll, "ScrollBarImageColor3", "SubText")
mk("UIListLayout", {
	Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder,
	HorizontalAlignment = Enum.HorizontalAlignment.Left,
}, MessagesScroll)
addPadding(MessagesScroll, 2, 2, 6, 6)

-- idea / preset chips row (3 rotating + shuffle)
local IdeaRow = mk("Frame", {
	Name = "Ideas", Position = UDim2.new(0, 10, 1, -(INPUT_H + IDEA_H + 16)),
	Size = UDim2.new(1, -20, 0, IDEA_H), BackgroundTransparency = 1, ZIndex = 11,
}, MainWindow)
mk("UIListLayout", {
	Padding = UDim.new(0, 6), FillDirection = Enum.FillDirection.Horizontal,
	SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center,
}, IdeaRow)
local IdeaChips = {}
for i = 1, 3 do
	IdeaChips[i] = mkButton({
		Size = UDim2.new(0, 120, 0, 26), Text = "…", TextSize = 11, Variant = "surface",
		CornerRadius = 13, TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = i, ZIndex = 12,
		OnClick = nil, -- wired in part 8
	}, IdeaRow)
end
local ShuffleBtn = mkButton({
	Size = UDim2.new(0, 26, 0, 26), Text = "🔁", TextSize = 12, Variant = "surface",
	CornerRadius = 13, LayoutOrder = 4, ZIndex = 12, OnClick = nil, -- wired in part 8
}, IdeaRow)

-- input row
local InputRow = mk("Frame", {
	Name = "InputRow", Position = UDim2.new(0, 10, 1, -(INPUT_H + 8)),
	Size = UDim2.new(1, -20, 0, INPUT_H), BackgroundTransparency = 1, ZIndex = 11,
}, MainWindow)

local InputBox = mk("TextBox", {
	Name = "Input", Size = UDim2.new(1, -52, 1, 0), BackgroundColor3 = RoleColor("Surface"),
	Text = "", PlaceholderText = "Ask Vallex AI anything…", PlaceholderColor3 = RoleColor("SubText"),
	TextColor3 = RoleColor("Text"), TextSize = 13, TextWrapped = true,
	ClearTextOnFocus = false, BorderSizePixel = 0, TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Center, ClipsDescendants = true, ZIndex = 12,
}, InputRow)
addCorner(InputBox, 12)
addStroke(InputBox, "Stroke", 1, 0.3)
addPadding(InputBox, 10, 4, 10, 4)
registerTheme(InputBox, "BackgroundColor3", "Surface")
registerTheme(InputBox, "TextColor3", "Text")
registerTheme(InputBox, "PlaceholderColor3", "SubText")
registerFont(InputBox, "Regular")

local SendBtn = mkButton({
	Name = "Send", Size = UDim2.new(0, 44, 1, 0), Position = UDim2.new(1, -44, 0, 0),
	Text = "🚀", TextSize = 18, Variant = "primary", CornerRadius = 12, ZIndex = 12,
	OnClick = nil, -- wired in part 8 (send / stop)
}, InputRow)

-- // window behaviors ------------------------------------------------------------

local isMinimized = false
MinimizeBtn.MouseButton1Click:Connect(function()
	isMinimized = not isMinimized
	MessagesScroll.Visible = not isMinimized
	IdeaRow.Visible = not isMinimized
	InputRow.Visible = not isMinimized
	local size = WINDOW_SIZES[Settings.ViewMode] or WINDOW_SIZES.Landscape
	local h = isMinimized and HEADER_H or size.Y
	MainWindow.Size = UDim2.new(0, size.X, 0, h)
	MinimizeBtn.Text = isMinimized and "➕" or "➖"
end)

local function toggleMainWindow(force)
	local target = (force ~= nil) and force or (not MainWindow.Visible)
	MainWindow.Visible = target
	SideTab.Text = target and "✖️" or "🟰"
	States.SidebarOpen = target
	saveStatesNow()
end
SideTab.MouseButton1Click:Connect(function() toggleMainWindow() end)

CloseBtn.MouseButton1Click:Connect(function()
	mkDialog({
		Title = "Delete GUI",
		Message = "Are you sure you want to Delete the GUI?",
		Buttons = {
			{ Id = "yes", Text = "Yes", Variant = "danger" },
			{ Id = "no",  Text = "No",  Variant = "surface" },
		},
		OnResult = function(id)
			if id == "yes" then
				saveCurrentChat()
				saveStatesNow()
				saveSettingsNow()
				ScreenGui:Destroy()
			end
		end,
	})
end)

makeDraggable(HeaderBar, MainWindow)

-- view mode (Landscape / Portrait)
applyViewMode = function(mode, silent)
	if WINDOW_SIZES[mode] == nil then mode = "Landscape" end
	Settings.ViewMode = mode
	local size = WINDOW_SIZES[mode]
	local h = isMinimized and HEADER_H or size.Y
	TweenService:Create(MainWindow, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.new(0, size.X, 0, h), Position = UDim2.new(0.5, 0, 0.5, 0) }):Play()
	States.ViewMode = mode
	saveSettingsNow()
	if not silent then
		saveStatesNow()
		-- re-layout existing messages for the new width
		task.defer(function() renderTranscript() end)
	end
end

refreshHeaderTitle = function()
	ChatTitle.Text = CurrentChat.name
end

-- greeting (time-based, spec §4)
local function greetingText()
	local h = tonumber(os.date("*t").hour) or 12
	local name = getPlayerName()
	if h >= 5 and h < 12 then
		return ("Morning Coffee, %s!"):format(name)
	elseif h >= 12 and h < 17 then
		return ("Afternoon Refuel, %s!"):format(name)
	elseif h >= 17 and h < 21 then
		return ("Evening Wind-Down, %s!"):format(name)
	end
	return ("Night Owl, %s."):format(name)
end
GreetingLabel.Text = greetingText()
task.spawn(function()
	while ScreenGui and ScreenGui.Parent do
		task.wait(60)
		pcall(function() GreetingLabel.Text = greetingText() end)
	end
end)

-- //=======================================================================//--
-- //        MESSAGE RENDERING — bubbles, code panels, typewriter           //--
-- //=======================================================================//--

local RowRefs = {} -- message index -> row frame

local function autoScroll()
        task.defer(function()
                if MessagesScroll.Active then
                        MessagesScroll.CanvasPosition = Vector2.new(0, math.max(0, MessagesScroll.AbsoluteCanvasSize.Y))
                end
        end)
end

--- split AI text into text/code segments on ``` fences (fences never shown literally)
local function parseSegments(text)
        local segments = {}
        local rest = tostring(text)
        while true do
                local s = string.find(rest, "```", 1, true)
                if not s then
                        if #rest > 0 then table.insert(segments, { kind = "text", text = rest }) end
                        break
                end
                local before = string.sub(rest, 1, s - 1)
                if #before > 0 then table.insert(segments, { kind = "text", text = before }) end
                local after = string.sub(rest, s + 3)
                local e = string.find(after, "```", 1, true)
                local block, closed
                if e then
                        block = string.sub(after, 1, e - 1)
                        closed = true
                else
                        block = after
                        closed = false
                end
                local nl = string.find(block, "\n", 1, true)
                local lang, code
                if nl then
                        lang = string.sub(block, 1, nl - 1)
                        code = string.sub(block, nl + 1)
                else
                        lang = block
                        code = ""
                end
                table.insert(segments, { kind = "code", lang = lang, code = code:gsub("%s+$", "") })
                if not closed then break end
                rest = string.sub(after, e + 3)
        end
        return segments
end

local function normalizeLangName(lang)
        lang = tostring(lang or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if #lang == 0 then return "Code" end
        local lower = string.lower(lang)
        if lower == "lua" or lower == "luau" then return "Luau" end
        return lang:sub(1, 1):upper() .. lang:sub(2)
end

local function getBubbleMaxWidth()
        return math.max(150, MessagesScroll.AbsoluteSize.X * CONFIG.BubbleMaxRatio)
end

-- // code panel ----------------------------------------------------------------
local function mkCodePanel(parent, seg, order)
        local panel = mk("Frame", {
                Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundColor3 = RoleColor("Background"), BorderSizePixel = 0,
                LayoutOrder = order, ZIndex = 14,
        }, parent)
        addCorner(panel, 10)
        addStroke(panel, "Stroke", 1, 0.25)
        registerTheme(panel, "BackgroundColor3", "Background")

        local langLabel = mkText({
                Size = UDim2.new(0, 120, 0, 16), Position = UDim2.new(0, 9, 0, 5),
                Text = normalizeLangName(seg.lang), TextSize = 10,
                TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 15, LayoutOrder = 0,
        }, panel, "Bold")
        registerTheme(langLabel, "TextColor3", "Accent")

        local copyBtn = mkButton({
                Size = UDim2.new(0, 22, 0, 22), Position = UDim2.new(1, -54, 0, 4),
                Text = "📜", TextSize = 11, Variant = "surface", CornerRadius = 6, ZIndex = 15,
                OnClick = function()
                        if copyToClipboard(seg.code) then
                                copyBtn.Text = "✅"
                                task.delay(0.7, function() copyBtn.Text = "📜" end)
                        else
                                showToast("Clipboard not available in this executor", "error")
                        end
                end,
        }, panel)

        local runBtn = mkButton({
                Size = UDim2.new(0, 22, 0, 22), Position = UDim2.new(1, -28, 0, 4),
                Text = "▶️", TextSize = 10, Variant = "surface", CornerRadius = 6, ZIndex = 15,
                OnClick = function()
                        mkDialog({
                                Title = "Run Script",
                                Message = "Are you sure you want to run this Script? Running this script could modify your game, character, or data — and since it's AI-generated, it may not behave as expected. Only run scripts you understand.",
                                Width = 360,
                                Buttons = {
                                        { Id = "okay", Text = "Okay", Variant = "primary" },
                                        { Id = "pro",  Text = "I know what I'm doing!", Variant = "surface", Width = 170 },
                                },
                                OnResult = function(id)
                                        if id == "okay" or id == "pro" then
                                                local fn = loadstringSafe(seg.code, "=VallexAIRun")
                                                if not fn then
                                                        showToast("loadstring unavailable — cannot run script", "error")
                                                        return
                                                end
                                                task.spawn(function()
                                                        local ok, err = pcall(fn)
                                                        if not ok then showToast("Script error: " .. tostring(err), "error") end
                                                end)
                                        end
                                end,
                        })
                end,
        }, panel)

        local body = mkText({
                Size = UDim2.new(1, -18, 0, 0), Position = UDim2.new(0, 9, 0, 25),
                AutomaticSize = Enum.AutomaticSize.Y, Text = seg.code, TextSize = 12,
                TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
                TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 15,
        }, panel, "Mono")
        registerTheme(body, "TextColor3", "Text")
        mk("UISizeConstraint", { MaxSize = Vector2.new(math.huge, math.huge) }, body)
        return panel
end

-- // single message row ----------------------------------------------------------
--- opts: { error = bool, fresh = bool }
local function renderMessage(msg, index, opts)
        opts = opts or {}
        if RowRefs[index] then
                RowRefs[index]:Destroy()
                RowRefs[index] = nil
        end

        local row = mk("Frame", {
                Name = "Msg" .. tostring(index), Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
                LayoutOrder = index, ZIndex = 12,
        }, MessagesScroll)
        RowRefs[index] = row

        local rowLayout = mk("UIListLayout", {
                FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 0),
                HorizontalAlignment = msg.isPlayer and Enum.HorizontalAlignment.Right or Enum.HorizontalAlignment.Left,
                SortOrder = Enum.SortOrder.LayoutOrder,
        }, row)

        local bubble = mk("Frame", {
                Name = "Bubble",
                Size = msg.isPlayer and UDim2.new(0, 0, 0, 0) or UDim2.new(1, 0, 0, 0),
                AutomaticSize = msg.isPlayer and Enum.AutomaticSize.XY or Enum.AutomaticSize.Y,
                BackgroundColor3 = RoleColor(msg.isPlayer and "Accent" or "Surface"),
                BorderSizePixel = 0, ZIndex = 13,
        }, row)
        addCorner(bubble, 14)
        if msg.isPlayer then
                addStroke(bubble, "Accent", 1, 0.35)
                mk("UISizeConstraint", { MaxSize = Vector2.new(getBubbleMaxWidth(), math.huge) }, bubble)
        else
                addStroke(bubble, "Stroke", 1, 0.4)
        end
        registerTheme(bubble, "BackgroundColor3", msg.isPlayer and "Accent" or "Surface")
        addPadding(bubble, 11, 8, 11, 8)

        local list = mk("UIListLayout", {
                Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder,
        }, bubble)

        if not msg.isPlayer then
                local who = mkText({
                        Size = UDim2.new(1, 0, 0, 13), Text = getAIName(), TextSize = 10,
                        TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 14, LayoutOrder = 0,
                }, bubble, "Bold")
                registerTheme(who, "TextColor3", "SubText")
        end

        local segOrder = 1
        local firstTextLabel = nil
        local segments = parseSegments(msg.content)
        if #segments == 0 then
                segments = { { kind = "text", text = "" } }
        end
        for _, seg in ipairs(segments) do
                if seg.kind == "text" then
                        local lbl
                        if msg.isPlayer then
                                lbl = mkText({
                                        Size = UDim2.new(0, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.XY,
                                        Text = seg.text, TextSize = 13, TextWrapped = true, ZIndex = 14, LayoutOrder = segOrder,
                                }, bubble, "Regular")
                                mk("UISizeConstraint", { MaxSize = Vector2.new(getBubbleMaxWidth() - 22, math.huge) }, lbl)
                                registerTheme(lbl, "TextColor3", "OnAccent")
                        else
                                lbl = mkText({
                                        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
                                        Text = seg.text, TextSize = 13, TextWrapped = true,
                                        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
                                        ZIndex = 14, LayoutOrder = segOrder,
                                }, bubble, "Regular")
                                registerTheme(lbl, "TextColor3", opts.error and "Error" or "Text")
                        end
                        if not firstTextLabel then firstTextLabel = lbl end
                else
                        -- player code panels get a fixed comfortable width
                        if msg.isPlayer then
                                local wrap = mk("Frame", {
                                        Size = UDim2.new(0, 280, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
                                        BackgroundTransparency = 1, LayoutOrder = segOrder, ZIndex = 14,
                                }, bubble)
                                local inner = mk("Frame", {
                                        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
                                        BackgroundTransparency = 1, ZIndex = 14,
                                }, wrap)
                                mkCodePanel(inner, seg, 0)
                        else
                                mkCodePanel(bubble, seg, segOrder)
                        end
                end
                segOrder = segOrder + 1
        end

        -- cut-off badge + Continue (spec: partial text stays permanent, Continue appears below)
        if msg.cutOff and not msg.isPlayer then
                local stopRow = mk("Frame", {
                        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
                        BackgroundTransparency = 1, LayoutOrder = 999, ZIndex = 14,
                }, bubble)
                mk("UIListLayout", {
                        Padding = UDim.new(0, 5), FillDirection = Enum.FillDirection.Horizontal,
                        VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
                }, stopRow)
                local badge = mkText({
                        Size = UDim2.new(0, 90, 0, 24), Text = "⏹ Stopped", TextSize = 11,
                        TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 15, LayoutOrder = 0,
                }, stopRow, "Regular")
                registerTheme(badge, "TextColor3", "SubText")
                mkButton({
                        Size = UDim2.new(0, 110, 0, 24), Text = "↻ Continue", TextSize = 12,
                        Variant = "primary", CornerRadius = 8, ZIndex = 15, LayoutOrder = 1,
                        OnClick = function() continueFromCutoff(index) end,
                }, stopRow)
        end

        if not opts.silent then autoScroll() end
        return bubble, firstTextLabel
end

renderTranscript = function()
        for idx, row in pairs(RowRefs) do
                row:Destroy()
                RowRefs[idx] = nil
        end
        for idx, msg in ipairs(CurrentChat.messages) do
                renderMessage(msg, idx, { silent = (idx < #CurrentChat.messages) })
        end
        autoScroll()
end

-- // generating indicator (animated dots) -----------------------------------------
local function showGeneratingIndicator(text)
        local row = mk("Frame", {
                Name = "GeneratingRow", Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 12,
                LayoutOrder = 100000,
        }, MessagesScroll)
        local bubble = mk("Frame", {
                Size = UDim2.new(0, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.XY,
                BackgroundColor3 = RoleColor("Surface"), BorderSizePixel = 0, ZIndex = 13,
        }, row)
        addCorner(bubble, 14)
        addStroke(bubble, "Stroke", 1, 0.4)
        registerTheme(bubble, "BackgroundColor3", "Surface")
        addPadding(bubble, 11, 8, 11, 8)
        local lbl = mkText({
                Size = UDim2.new(0, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.XY,
                Text = tostring(text or "Generating"), TextSize = 13, ZIndex = 14,
        }, bubble, "Regular")
        registerTheme(lbl, "TextColor3", "SubText")
        autoScroll()
        local running = true
        local dots = 0
        task.spawn(function()
                while running do
                        dots = (dots % 3) + 1
                        pcall(function() lbl.Text = tostring(text or "Generating") .. string.rep(".", dots) end)
                        task.wait(CONFIG.DotInterval)
                end
        end)
        return {
                Stop = function()
                        running = false
                        pcall(function() row:Destroy() end)
                end,
        }
end

-- // typewriter helpers ------------------------------------------------------------
local function sliceChars(s, nChars)
        local ok, pos = pcall(utf8.offset, s, nChars + 1)
        if ok and pos then return string.sub(s, 1, pos - 1) end
        if ok and pos == nil then return s end
        return string.sub(s, 1, nChars)
end

--- Reveal fullText chunk-by-chunk into a plain temp bubble (live-typing look).
--- Returns partial revealed if stopped, else full text.
--- [[BRANCH]] pass 2: a Stop here becomes a branch point via the Continue flow.
local function typewriterReveal(fullText)
        local tempMsg = { speaker = getAIName(), isPlayer = false, content = "" }
        table.insert(CurrentChat.messages, tempMsg)
        local index = #CurrentChat.messages
        -- plain single-label row (segments swap in after reveal finishes)
        local row = mk("Frame", {
                Name = "Msg" .. tostring(index), Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
                LayoutOrder = index, ZIndex = 12,
        }, MessagesScroll)
        RowRefs[index] = row
        local bubble = mk("Frame", {
                Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundColor3 = RoleColor("Surface"), BorderSizePixel = 0, ZIndex = 13,
        }, row)
        addCorner(bubble, 14)
        addStroke(bubble, "Stroke", 1, 0.4)
        registerTheme(bubble, "BackgroundColor3", "Surface")
        addPadding(bubble, 11, 8, 11, 8)
        local lbl = mkText({
                Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
                Text = "", TextSize = 13, TextWrapped = true,
                TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
                ZIndex = 14,
        }, bubble, "Regular")
        registerTheme(lbl, "TextColor3", "Text")
        autoScroll()

        local totalLen = utf8.len(fullText) or #fullText
        local revealed = 0
        while revealed < totalLen do
                if StopRequested then break end
                revealed = math.min(totalLen, revealed + CONFIG.TypewriterChunk)
                lbl.Text = sliceChars(fullText, revealed)
                autoScroll()
                task.wait(CONFIG.TypewriterDelay)
        end

        if StopRequested and sliceChars(fullText, revealed) ~= fullText then
                -- permanent cut-off message (spec §3)
                tempMsg.content = sliceChars(fullText, revealed)
                tempMsg.cutOff = true
        else
                tempMsg.content = fullText
        end
        -- swap temp raw-text row for the parsed render (code panels, continue btn)
        renderMessage(tempMsg, index)
        if saveCurrentChat then saveCurrentChat() end
        return tempMsg
end

-- //=======================================================================//--
-- //     PROVIDERS / ADAPTERS / LIVE MODEL FETCHING / CONTEXT BUILDING     //--
-- //=======================================================================//--

local PROVIDER_LIST = {
	"OpenAI", "Google DeepMind", "Anthropic", "DeepSeek", "Custom", "Mock (No Key)",
}

local PROVIDER_META = {
	["OpenAI"] = {
		kind = "openai",
		endpoint = "https://api.openai.com/v1/chat/completions",
		modelsEndpoint = "https://api.openai.com/v1/models",
		auth = "bearer",
	},
	["Google DeepMind"] = { kind = "google" },
	["Anthropic"] = { kind = "anthropic" },
	["DeepSeek"] = {
		kind = "openai",
		endpoint = "https://api.deepseek.com/chat/completions",
		modelsEndpoint = "https://api.deepseek.com/models",
		auth = "bearer",
	},
	["Custom"] = { kind = "custom" },
	["Mock (No Key)"] = { kind = "mock" },
}

-- offline fallbacks (used only if the live /models fetch fails)
local FALLBACK_MODELS = {
	["OpenAI"]         = { "GPT-4O-Mini", "GPT-4O", "GPT-4.1", "GPT-4.1-Mini", "o4-mini" },
	["Google DeepMind"]= { "Gemini-3.6-Flash", "Gemini-3.6-Pro", "Gemini-2.5-Flash", "Gemini-2.5-Pro" },
	["Anthropic"]      = { "Sonnet-4.6", "Opus-4.6", "Haiku-4.5" },
	["DeepSeek"]       = { "DeepSeek-V4", "DeepSeek-R2", "DeepSeek-V3" },
	["Custom"]         = { "custom-model" },
	["Mock (No Key)"]  = { "mock-mini", "mock-pro", "mock-ultra" },
}

local ModelCache = {} -- [provider..key] = { models }

local function getApiKey(provider)
	provider = provider or States.LastSelectedProvider
	if provider == "Mock (No Key)" then return "" end
	if provider == "Custom" then
		return tostring(Settings.Custom.savedapikey.APIkey or "")
	end
	local slot = Settings[provider]
	if slot and slot.savedapikey then
		return tostring(slot.savedapikey.APIkey or "")
	end
	return ""
end

local function getSelectedModel(provider)
	provider = provider or States.LastSelectedProvider
	if provider == "Mock (No Key)" then return "mock-mini" end
	if provider == "Custom" then
		return tostring(Settings.Custom.model.selectedmodel or "custom-model")
	end
	local slot = Settings[provider]
	return slot and tostring(slot.model.selectedmodel or "") or ""
end

local function getCustomConfig()
	local c = Settings.Custom
	return {
		ProviderName = tostring(c.ainame.name or "CustomAI"),
		ModelID = tostring(c.model.selectedmodel or ""),
		BaseURL = tostring(c.baseurl.baseurl or ""),
		APIKey = tostring(c.savedapikey.APIkey or ""),
		AuthHeaderFormat = tostring(c.authheaderformat.format or "Bearer"),
		CustomHeaderName = c.customheadername.name,
		RequestFormat = tostring(c.requestformat.format or "OpenAI"),
		SupportsStreaming = (c.streaming.enabled == true),
	}
end

--- derive chat-completions + models URLs from a Custom BaseURL that may be
--- either an endpoint (.../chat/completions) or an API root (.../v1)
local function resolveCustomUrls(baseURL)
	baseURL = baseURL:gsub("/+$", "")
	local chatURL, modelsURL
	if baseURL:match("chat/completions$") then
		chatURL = baseURL
		modelsURL = baseURL:gsub("chat/completions$", "models")
	else
		chatURL = baseURL .. "/chat/completions"
		modelsURL = baseURL .. "/models"
	end
	return chatURL, modelsURL
end

local function buildHeaders(provider)
	local headers = { ["Content-Type"] = "application/json" }
	if provider == "OpenAI" or provider == "DeepSeek" then
		headers["Authorization"] = "Bearer " .. getApiKey(provider)
	elseif provider == "Anthropic" then
		headers["x-api-key"] = getApiKey("Anthropic")
		headers["anthropic-version"] = "2023-06-01"
	elseif provider == "Custom" then
		local cfg = getCustomConfig()
		local fmt = cfg.AuthHeaderFormat
		if fmt == "Bearer" then
			headers["Authorization"] = "Bearer " .. cfg.APIKey
		elseif fmt == "x-api-key" then
			headers["x-api-key"] = cfg.APIKey
		else
			local hname = tostring(cfg.CustomHeaderName or "")
			if #hname > 0 then headers[hname] = cfg.APIKey end
		end
	end
	return headers
end

--- Convert transcript messages into API history, apply the Input token
--- limit (oldest-first trim) and Focus Mode reminders (spec §5).
local function buildContext(provider)
	local messages = {}
	for _, m in ipairs(CurrentChat.messages) do
		-- a cut-off partial still counts as assistant context (spec: Continue
		-- generates fresh response with the partial as prior assistant text)
		table.insert(messages, {
			role = m.isPlayer and "user" or "assistant",
			content = m.content,
		})
	end
	-- Input token limit (rough chars/4 heuristic)
	if Settings.TokenLimits.Input.enabled then
		local budget = (tonumber(Settings.TokenLimits.Input.value) or 4096) * 4
		local total = 0
		for _, m in ipairs(messages) do total = total + #m.content end
		while total > budget and #messages > 2 do
			total = total - #messages[1].content
			table.remove(messages, 1)
		end
	end
	-- Focus Mode: every N messages, re-inject the original instructions
	local sys = tostring(Settings.Instructions or "")
	if Settings.FocusMode.enabled and #sys > 0 then
		local interval = math.max(1, tonumber(Settings.FocusMode.interval) or 5)
		if #messages >= interval and (#messages % interval) == 0 then
			table.insert(messages, {
				role = "user",
				content = "[FOCUS REMINDER] Re-read the original instructions and stay on topic: " .. sys,
			})
		end
	end
	return messages, sys
end

local MOCK_RESPONSES = {
	[[
Here's a quick, scriptable mechanic you can drop into your game:

```lua
local Players = game:GetService("Players")

-- Simple double-jump mechanic
local DOUBLE_JUMP_POWER = 55
local jumps = {}

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid")
		local canDouble = false
		humanoid.StateChanged:Connect(function(_, new)
			if new == Enum.HumanoidStateType.Landed then
				canDouble = true
			end
		end)
		humanoid.Jumping:Connect(function()
			if canDouble then
				canDouble = false
				humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
				character.PrimaryPart.AssemblyLinearVelocity =
					Vector3.new(0, DOUBLE_JUMP_POWER, 0)
			end
		end)
	end)
end)
```
Want me to add a cooldown or a particle effect on the second jump?
]],
	[[
Quick Luau tip for you:

```lua
-- Prefer task library over legacy wait/spawn
task.wait(0.5)          -- instead of wait(0.5)
task.spawn(function()   -- instead of spawn(function() ... end)
	print("runs immediately, yields safely")
end)
```
Small habits like these keep your game smooth and avoid deprecated behavior.
]],
	[[
Here's a minimal game loop you can build on:

```lua
local runService = game:GetService("RunService")

local ROUND_TIME = 120
local state = "lobby"

while true do
	if state == "lobby" then
		print("Waiting for players...")
		task.wait(5)
		state = "round"
	elseif state == "round" then
		print("Round starting!")
		local t = 0
		repeat
			task.wait(1)
			t = t + 1
		until t >= ROUND_TIME
		state = "lobby"
	end
end
```
Want me to wire in intermission timers or a win condition?
]],
}

local function callMock()
	local idx = math.random(1, #MOCK_RESPONSES)
	task.wait(0.4 + math.random() * 0.6)
	return true, MOCK_RESPONSES[idx]
end

--- parse OpenAI-style SSE body (Custom provider, SupportsStreaming = true):
--- the executor client receives the full event stream; we concat the deltas.
local function parseSSEOpenAI(body)
	local out = {}
	for line in string.gmatch(body, "[^\r\n]+") do
		if line:sub(1, 5) == "data:" then
			local payload = line:sub(6):gsub("^%s+", "")
			if payload ~= "[DONE]" then
				local obj = jsonDecode(payload)
				if obj and obj.choices and obj.choices[1] then
					local delta = obj.choices[1].delta
					if delta and kindof(delta.content) == "string" then
						table.insert(out, delta.content)
					end
				end
			end
		end
	end
	return table.concat(out)
end

--- The main adapter. Returns ok, text|errorMessage
local function callProvider(provider, nudge)
	local meta = PROVIDER_META[provider]
	if not meta then return false, "Unknown provider" end
	if meta.kind == "mock" then return callMock() end

	local messages, sys = buildContext(provider)
	if nudge then
		table.insert(messages, { role = "user", content = nudge })
	end

	local url, headers, body, model
	if meta.kind == "openai" then
		url = meta.endpoint
		headers = buildHeaders(provider)
		model = getSelectedModel(provider)
		body = { model = model, messages = messages }
		if Settings.TokenLimits.Output.enabled then
			body.max_tokens = tonumber(Settings.TokenLimits.Output.value) or 2048
		end
	elseif meta.kind == "custom" then
		local cfg = getCustomConfig()
		if #cfg.BaseURL == 0 then return false, "Custom provider: Base URL is not set (Settings)." end
		url = resolveCustomUrls(cfg.BaseURL)
		headers = buildHeaders("Custom")
		model = cfg.ModelID
		body = { model = model, messages = messages, stream = cfg.SupportsStreaming }
		if Settings.TokenLimits.Output.enabled then
			body.max_tokens = tonumber(Settings.TokenLimits.Output.value) or 2048
		end
	elseif meta.kind == "google" then
		local key = getApiKey("Google DeepMind")
		if #key == 0 then return false, "Google DeepMind: API key is not set (Settings)." end
		model = getSelectedModel(provider)
		url = "https://generativelanguage.googleapis.com/v1beta/models/" ..
			model .. ":generateContent?key=" .. key
		headers = { ["Content-Type"] = "application/json" }
		local contents = {}
		for _, m in ipairs(messages) do
			-- focus-mode reminders ride as user turns; assistant maps to "model"
			table.insert(contents, {
				role = (m.role == "assistant") and "model" or "user",
				parts = { { text = m.content } },
			})
		end
		body = { contents = contents }
		if #sys > 0 then
			body.systemInstruction = { parts = { { text = sys } } }
		end
		body.generationConfig = {}
		if Settings.TokenLimits.Output.enabled then
			body.generationConfig.maxOutputTokens = tonumber(Settings.TokenLimits.Output.value) or 2048
		end
	elseif meta.kind == "anthropic" then
		if #getApiKey("Anthropic") == 0 then return false, "Anthropic: API key is not set (Settings)." end
		model = getSelectedModel(provider)
		url = "https://api.anthropic.com/v1/messages"
		headers = buildHeaders("Anthropic")
		-- merge consecutive same-role turns (Anthropic prefers alternation)
		local merged = {}
		for _, m in ipairs(messages) do
			if #merged > 0 and merged[#merged].role == m.role then
				merged[#merged].content = merged[#merged].content .. "\n" .. m.content
			else
				table.insert(merged, { role = m.role, content = m.content })
			end
		end
		body = { model = model, messages = merged }
		-- max_tokens is REQUIRED by Anthropic; use configured limit or safe default
		body.max_tokens = Settings.TokenLimits.Output.enabled
			and (tonumber(Settings.TokenLimits.Output.value) or CONFIG.AnthropicDefaultMaxTokens)
			or CONFIG.AnthropicDefaultMaxTokens
		if #sys > 0 then body.system = sys end
	end

	local ok, resp = httpRequest({
		Url = url, Method = "POST", Headers = headers, Body = jsonEncode(body),
	})
	if not ok then return false, "HTTP error: " .. tostring(resp) end
	if resp.code < 200 or resp.code >= 300 then
		local decoded = jsonDecode(resp.body)
		local apiMsg = nil
		if decoded then
			if decoded.error and decoded.error.message then apiMsg = decoded.error.message
			elseif kindof(decoded.message) == "string" then apiMsg = decoded.message end
		end
		return false, ("API %s: %s"):format(tostring(resp.code), apiMsg or string.sub(resp.body, 1, 200))
	end

	local decoded = jsonDecode(resp.body)
	if not decoded then return false, "API returned invalid JSON" end
	local provider_ = provider
	if meta.kind == "openai" or (meta.kind == "custom" and body.stream ~= true) then
		if decoded.choices and decoded.choices[1] and decoded.choices[1].message then
			return true, tostring(decoded.choices[1].message.content or "")
		end
	elseif meta.kind == "custom" and body.stream == true then
		local streamed = parseSSEOpenAI(resp.body)
		if #streamed > 0 then return true, streamed end
		if decoded.choices and decoded.choices[1] and decoded.choices[1].message then
			return true, tostring(decoded.choices[1].message.content or "")
		end
	elseif meta.kind == "google" then
		if decoded.candidates and decoded.candidates[1] and decoded.candidates[1].content then
			local parts = decoded.candidates[1].content.parts or {}
			local out = {}
			for _, p in ipairs(parts) do
				if kindof(p.text) == "string" then table.insert(out, p.text) end
			end
			if #out > 0 then return true, table.concat(out) end
		end
	elseif meta.kind == "anthropic" then
		if decoded.content and decoded.content[1] then
			local out = {}
			for _, p in ipairs(decoded.content) do
				if p.type == "text" and kindof(p.text) == "string" then table.insert(out, p.text) end
			end
			if #out > 0 then return true, table.concat(out) end
		end
	end
	local errMsg = (decoded.error and decoded.error.message) or "unexpected API response shape"
	return false, errMsg
end

-- // live model fetching (spec: Models dropdown auto-updates per provider) -----
local function parseModelsList(provider, respBody)
	local decoded = jsonDecode(respBody)
	if not decoded then return nil end
	local out = {}
	if provider == "Google DeepMind" then
		for _, m in ipairs(decoded.models or {}) do
			local name = tostring(m.name or ""):gsub("^models/", "")
			if #name > 0 then table.insert(out, name) end
		end
	else
		local list = decoded.data or decoded.models or {}
		for _, m in ipairs(list) do
			if kindof(m) == "table" and kindof(m.id) == "string" then table.insert(out, m.id) end
		end
	end
	if #out == 0 then return nil end
	table.sort(out)
	return out
end

--- fetchModels(provider, callback) — callback(models, fromLive)
local function fetchModels(provider, callback)
	local cachedKey = provider .. "|" .. getApiKey(provider)
	local cached = ModelCache[cachedKey]
	if cached then
		callback(cached, true)
		return
	end
	local meta = PROVIDER_META[provider]
	if meta.kind == "mock" or not HTTP then
		callback(FALLBACK_MODELS[provider] or {}, false)
		return
	end
	task.spawn(function()
		local url, headers
		if meta.kind == "google" then
			local key = getApiKey(provider)
			url = "https://generativelanguage.googleapis.com/v1beta/models?key=" .. key
			headers = { ["Content-Type"] = "application/json" }
		elseif meta.kind == "anthropic" then
			url = "https://api.anthropic.com/v1/models"
			headers = buildHeaders("Anthropic")
		elseif meta.kind == "openai" then
			url = meta.modelsEndpoint
			headers = buildHeaders(provider)
		else -- custom
			local cfg = getCustomConfig()
			if #cfg.BaseURL == 0 then
				callback(FALLBACK_MODELS[provider] or {}, false)
				return
			end
			local _, mURL = resolveCustomUrls(cfg.BaseURL)
			url = mURL
			headers = buildHeaders("Custom")
		end
		local ok, resp = httpRequest({ Url = url, Method = "GET", Headers = headers })
		local models = nil
		if ok and resp.code >= 200 and resp.code < 300 then
			models = parseModelsList(provider, resp.body)
		end
		if models then
			ModelCache[cachedKey] = models
			callback(models, true)
		else
			callback(FALLBACK_MODELS[provider] or {}, false)
		end
	end)
end

refreshModelsDropdown = function()
	-- implemented in part 7 (assigned there); referenced by provider changes
end

-- //=======================================================================//--
-- //   SETTINGS PANEL + CHATS BROWSER + THEME/FONT PICKERS                 //--
-- //=======================================================================//--

local SettingsPanel = mk("Frame", {
        Name = "SettingsPanel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(0, 470, 0, 430), BackgroundColor3 = RoleColor("Background"),
        BorderSizePixel = 0, Visible = false, ZIndex = 20, Active = true,
}, ScreenGui)
addCorner(SettingsPanel, 14)
addStroke(SettingsPanel, "Accent", 1.6, 0.05)
registerTheme(SettingsPanel, "BackgroundColor3", "Background")

local SPHeader = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, ZIndex = 21,
}, SettingsPanel)
local SPTitle = mkText({
        Position = UDim2.new(0, 14, 0, 13), Size = UDim2.new(1, -60, 0, 18),
        Text = "⚙ Settings", TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22,
}, SPHeader, "Bold")
registerTheme(SPTitle, "TextColor3", "Text")
local SPClose = mkButton({
        Size = UDim2.new(0, 28, 0, 28), Position = UDim2.new(1, -36, 0.5, -14),
        Text = "✕", TextSize = 13, Variant = "surface", CornerRadius = 8, ZIndex = 22,
}, SPHeader)
local SPLine = mk("Frame", {
        Position = UDim2.new(0, 0, 0, 44), Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = RoleColor("Stroke"), BorderSizePixel = 0, BackgroundTransparency = 0.35, ZIndex = 21,
}, SettingsPanel)
registerTheme(SPLine, "BackgroundColor3", "Stroke")
makeDraggable(SPHeader, SettingsPanel)

local SPScroll = mk("ScrollingFrame", {
        Position = UDim2.new(0, 8, 0, 52), Size = UDim2.new(1, -16, 1, -60),
        BackgroundTransparency = 1, BorderSizePixel = 0, CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
        ScrollBarThickness = 4, ScrollBarImageColor3 = RoleColor("SubText"), ZIndex = 21,
}, SettingsPanel)
registerTheme(SPScroll, "ScrollBarImageColor3", "SubText")
mk("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, SPScroll)
addPadding(SPScroll, 4, 4, 8, 8)

-- // row / input helpers ----------------------------------------------------------
local function mkRow(labelText, order, height)
        local row = mk("Frame", {
                Size = UDim2.new(1, 0, 0, height or 34), BackgroundTransparency = 1,
                LayoutOrder = order, ZIndex = 22,
        }, SPScroll)
        local lbl = mkText({
                Size = UDim2.new(0, 140, 1, 0), Text = labelText, TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 23,
        }, row, "Bold")
        registerTheme(lbl, "TextColor3", "SubText")
        return row
end

local function mkTextInput(parent, placeholder, current, onChanged, height, multiline)
        local box = mk("TextBox", {
                Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = RoleColor("Surface"),
                Text = tostring(current or ""), PlaceholderText = placeholder,
                PlaceholderColor3 = RoleColor("SubText"), TextColor3 = RoleColor("Text"),
                TextSize = 12, ClearTextOnFocus = false, TextWrapped = multiline == true,
                BorderSizePixel = 0, TextXAlignment = Enum.TextXAlignment.Left,
                TextYAlignment = multiline and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
                ZIndex = 23,
        }, parent)
        addCorner(box, 8)
        addStroke(box, "Stroke", 1, 0.3)
        addPadding(box, 8, multiline and 6 or 0, 8, 0)
        registerTheme(box, "BackgroundColor3", "Surface")
        registerTheme(box, "TextColor3", "Text")
        registerTheme(box, "PlaceholderColor3", "SubText")
        registerFont(box, "Regular")
        box.FocusLost:Connect(function()
                if kindof(onChanged) == "function" then onChanged(box.Text) end
        end)
        return box
end

-- // provider + models ------------------------------------------------------------
local CustomRows = {} -- rows only visible when Provider = Custom

local function updateCustomVisibility()
        local isCustom = (States.LastSelectedProvider == "Custom")
        for _, r in ipairs(CustomRows) do r.Visible = isCustom end
end

local rowProvider = mkRow("Provider", 1)
local ProviderDropdown = mkDropdown(rowProvider, {
        Options = PROVIDER_LIST, Current = States.LastSelectedProvider,
        OnPick = function(v)
                States.LastSelectedProvider = v
                saveStatesNow()
                updateCustomVisibility()
                refreshModelsDropdown()
        end,
})
ProviderDropdown.Button.Size = UDim2.new(1, -150, 0, 30)
ProviderDropdown.Button.Position = UDim2.new(0, 150, 0.5, -15)

local function currentModelOptions()
        local p = States.LastSelectedProvider
        local key = p .. "|" .. getApiKey(p)
        return ModelCache[key] or FALLBACK_MODELS[p] or {}
end

local rowModels = mkRow("Models", 2)
local ModelsDropdown = mkDropdown(rowModels, {
        Options = currentModelOptions, Current = getSelectedModel(),
        Placeholder = "Select model...",
        OnPick = function(v)
                local p = States.LastSelectedProvider
                if p == "Custom" then
                        Settings.Custom.model.selectedmodel = v
                elseif Settings[p] then
                        Settings[p].model.selectedmodel = v
                end
                saveSettingsNow()
        end,
})
ModelsDropdown.Button.Size = UDim2.new(1, -150, 0, 30)
ModelsDropdown.Button.Position = UDim2.new(0, 150, 0.5, -15)

refreshModelsDropdown = function()
        local p = States.LastSelectedProvider
        ModelsDropdown.Set(getSelectedModel(p))
        fetchModels(p, function(models, live)
                if States.LastSelectedProvider ~= p then return end -- stale fetch
                ModelsDropdown.SetOptions(models)
                ModelsDropdown.Set(getSelectedModel(p))
                if not live and p ~= "Mock (No Key)" then
                        showToast("Live model fetch failed — using fallback list", nil)
                end
        end)
end

-- // api keys ------------------------------------------------------------------------
-- (one shared row; writes to whichever provider is currently selected)
local function apiKeyRow(labelText, order)
        local row = mkRow(labelText, order)
        local box = mkTextInput(row, "sk-...", "", function(v)
                local p = States.LastSelectedProvider
                if p == "Custom" then
                        Settings.Custom.savedapikey.APIkey = v
                elseif p ~= "Mock (No Key)" and Settings[p] then
                        Settings[p].savedapikey.APIkey = v
                end
                saveSettingsNow()
        end)
        box.Size = UDim2.new(1, -150, 1, 0)
        box.Position = UDim2.new(0, 150, 0, 0)
        return row, box
end

local rowAPI = apiKeyRow("API Key", 3)

local function syncAPIKeyRow()
        local p = States.LastSelectedProvider
        local val
        if p == "Custom" then val = Settings.Custom.savedapikey.APIkey
        elseif p == "Mock (No Key)" then val = "(not required)"
        else val = Settings[p].savedapikey.APIkey end
        -- rewrite the textbox text directly
        local tb = rowAPI:FindFirstChildWhichIsA("TextBox", true)
        if tb then
                tb.Text = tostring(val or "")
                if p == "Mock (No Key)" then tb.PlaceholderText = "(not required)" else tb.PlaceholderText = "sk-..." end
        end
end

-- // token limits (on/off toggle = unlimited, spec §5) --------------------------------
local function tokenRow(labelText, order, which)
        local row = mkRow(labelText, order, 34)
        local cfg = Settings.TokenLimits[which]
        local valueBox
        local tgl = mkToggle(row, cfg.enabled, function(state)
                Settings.TokenLimits[which].enabled = state
                saveSettingsNow()
                if valueBox then
                        valueBox.TextEditable = state
                        valueBox.BackgroundTransparency = state and 0 or 0.55
                end
        end)
        tgl.Holder.Position = UDim2.new(0, 150, 0.5, -12)
        valueBox = mkTextInput(row, cfg.enabled and tostring(cfg.value) or "unlimited", cfg.enabled and tostring(cfg.value) or "", function(v)
                local n = tonumber(v)
                if n and n > 0 then
                        Settings.TokenLimits[which].value = math.floor(n)
                        saveSettingsNow()
                end
        end)
        valueBox.Size = UDim2.new(0, 120, 1, 0)
        valueBox.Position = UDim2.new(0, 205, 0, 0)
        valueBox.TextEditable = cfg.enabled
        valueBox.BackgroundTransparency = cfg.enabled and 0 or 0.55
        if not cfg.enabled then
                valueBox.Text = ""
                valueBox.PlaceholderText = "unlimited"
        end
        return row
end

local rowTokenIn = tokenRow("Input Token Limit", 4, "Input")
local rowTokenOut = tokenRow("Output Token Limit", 5, "Output")

-- // instructions -----------------------------------------------------------------------
local rowInstr = mkRow("Instructions", 6, 80)
local instrBox = mkTextInput(rowInstr, "System prompt / persona for the AI…", Settings.Instructions, function(v)
        Settings.Instructions = v
        saveSettingsNow()
end, 80, true)
instrBox.Size = UDim2.new(1, -150, 1, 0)
instrBox.Position = UDim2.new(0, 150, 0, 0)

-- // focus mode (with cost warning, spec §5) ----------------------------------------------
local rowFocus = mkRow("Focus Mode", 7)
local FocusToggle
FocusToggle = mkToggle(rowFocus, Settings.FocusMode.enabled, function(state)
        if state and not Settings.FocusMode.enabled then
                mkDialog({
                        Title = "Focus Mode",
                        Message = "Enabling this feature on will make your AI cost more, are you sure you want to enable this?",
                        Width = 340,
                        Buttons = {
                                { Id = "okay", Text = "Okay", Variant = "primary" },
                                { Id = "pro",  Text = "I know what I'm doing!", Variant = "surface", Width = 170 },
                        },
                        OnResult = function(id)
                                if id == "okay" or id == "pro" then
                                        Settings.FocusMode.enabled = true
                                        FocusToggle.Set(true, true)
                                else
                                        FocusToggle.Set(false, true)
                                end
                                saveSettingsNow()
                                saveStatesNow()
                        end,
                })
        elseif not state then
                Settings.FocusMode.enabled = false
                saveSettingsNow()
                saveStatesNow()
        end
end)
FocusToggle.Holder.Position = UDim2.new(0, 150, 0.5, -12)

local focusLbl = mkText({
        Size = UDim2.new(0, 46, 1, 0), Position = UDim2.new(0, 208, 0, 0),
        Text = "every", TextSize = 11, ZIndex = 23,
}, rowFocus, "Regular")
registerTheme(focusLbl, "TextColor3", "SubText")

local focusBox = mkTextInput(rowFocus, "5", tostring(Settings.FocusMode.interval), function(v)
        local n = tonumber(v)
        if n and n >= 1 then
                Settings.FocusMode.interval = math.floor(n)
                saveSettingsNow()
        end
end)
focusBox.Size = UDim2.new(0, 46, 1, 0)
focusBox.Position = UDim2.new(0, 254, 0, 0)

local focusLbl2 = mkText({
        Size = UDim2.new(0, 60, 1, 0), Position = UDim2.new(0, 306, 0, 0),
        Text = "messages", TextSize = 11, ZIndex = 23,
}, rowFocus, "Regular")
registerTheme(focusLbl2, "TextColor3", "SubText")

-- // view mode ------------------------------------------------------------------------------
local rowView = mkRow("View Mode", 8)
local LandscapeBtn = mkButton({
        Size = UDim2.new(0, 88, 0, 28), Position = UDim2.new(0, 150, 0.5, -14),
        Text = "Landscape", TextSize = 11, CornerRadius = 8, ZIndex = 23,
        OnClick = function() applyViewMode("Landscape") end,
}, rowView)
local PortraitBtn = mkButton({
        Size = UDim2.new(0, 88, 0, 28), Position = UDim2.new(0, 246, 0.5, -14),
        Text = "Portrait", TextSize = 11, CornerRadius = 8, ZIndex = 23,
        OnClick = function() applyViewMode("Portrait") end,
}, rowView)
local function syncViewButtons()
        local mode = Settings.ViewMode
        LandscapeBtn.BackgroundColor3 = RoleColor(mode == "Landscape" and "Accent" or "Surface")
        PortraitBtn.BackgroundColor3 = RoleColor(mode == "Portrait" and "Accent" or "Surface")
        LandscapeBtn.TextColor3 = RoleColor(mode == "Landscape" and "OnAccent" or "Text")
        PortraitBtn.TextColor3 = RoleColor(mode == "Portrait" and "OnAccent" or "Text")
end
registerRefresher(syncViewButtons)

-- // font + theme ----------------------------------------------------------------------------
local rowFont = mkRow("Font", 9)
local FontDropdown = mkDropdown(rowFont, {
        Options = UIFontNames, Current = States.Font or "Gotham",
        OnPick = function(v) applyFontAndSave(v) end,
})
FontDropdown.Button.Size = UDim2.new(1, -150, 0, 30)
FontDropdown.Button.Position = UDim2.new(0, 150, 0.5, -15)

local function sortedThemeNames()
        local names = {}
        for name in pairs(Themes) do table.insert(names, name) end
        table.sort(names)
        return names
end

local rowTheme = mkRow("Theme", 10)
local ThemeDropdown = mkDropdown(rowTheme, {
        Options = sortedThemeNames, Current = States.LastTheme or "Dark",
        OnPick = function(v)
                if ApplyTheme(v) then
                        States.LastTheme = v
                        saveStatesNow()
                end
        end,
})
ThemeDropdown.Button.Size = UDim2.new(1, -150, 0, 30)
ThemeDropdown.Button.Position = UDim2.new(0, 150, 0.5, -15)

-- // custom AI section (spec §6) --------------------------------------------------------------
local customOrder = 11
local rowCHeader -- forward: referenced by the Auth Header dropdown below

local function customRow(labelText, order)
        local row = mkRow(labelText, order)
        table.insert(CustomRows, row)
        return row
end

local rowCName = customRow("Provider Name", customOrder); customOrder = customOrder + 1
local cNameBox = mkTextInput(rowCName, "MyLocalServer", Settings.Custom.ainame.name, function(v)
        Settings.Custom.ainame.name = (v ~= "" and v) or "CustomAI"
        saveSettingsNow()
end)
cNameBox.Size = UDim2.new(1, -150, 1, 0); cNameBox.Position = UDim2.new(0, 150, 0, 0)

local rowCModel = customRow("Model ID", customOrder); customOrder = customOrder + 1
local cModelBox = mkTextInput(rowCModel, "llama-3-70b", Settings.Custom.model.selectedmodel, function(v)
        Settings.Custom.model.selectedmodel = v
        saveSettingsNow()
end)
cModelBox.Size = UDim2.new(1, -150, 1, 0); cModelBox.Position = UDim2.new(0, 150, 0, 0)

local rowCBase = customRow("Base URL", customOrder); customOrder = customOrder + 1
local cBaseBox = mkTextInput(rowCBase, "https://myserver.com/v1/chat/completions", Settings.Custom.baseurl.baseurl, function(v)
        Settings.Custom.baseurl.baseurl = v
        saveSettingsNow()
end)
cBaseBox.Size = UDim2.new(1, -150, 1, 0); cBaseBox.Position = UDim2.new(0, 150, 0, 0)

local rowCKey = customRow("API Key", customOrder); customOrder = customOrder + 1
local cKeyBox = mkTextInput(rowCKey, "sk-...", Settings.Custom.savedapikey.APIkey, function(v)
        Settings.Custom.savedapikey.APIkey = v
        saveSettingsNow()
end)
cKeyBox.Size = UDim2.new(1, -150, 1, 0); cKeyBox.Position = UDim2.new(0, 150, 0, 0)

local rowCAuth = customRow("Auth Header", customOrder); customOrder = customOrder + 1
local AuthDropdown = mkDropdown(rowCAuth, {
        Options = { "Bearer", "x-api-key", "Custom" },
        Current = Settings.Custom.authheaderformat.format or "Bearer",
        OnPick = function(v)
                Settings.Custom.authheaderformat.format = v
                saveSettingsNow()
                rowCHeader.Visible = (v == "Custom")
        end,
})
AuthDropdown.Button.Size = UDim2.new(1, -150, 0, 30)
AuthDropdown.Button.Position = UDim2.new(0, 150, 0.5, -15)

local rowCHeaderRow = customRow("Custom Header", customOrder); customOrder = customOrder + 1
rowCHeader = rowCHeaderRow
local cHeaderBox = mkTextInput(rowCHeader, "X-Custom-Auth", Settings.Custom.customheadername.name or "", function(v)
        Settings.Custom.customheadername.name = v
        saveSettingsNow()
end)
cHeaderBox.Size = UDim2.new(1, -150, 1, 0); cHeaderBox.Position = UDim2.new(0, 150, 0, 0)

local rowCFormat = customRow("Request Format", customOrder); customOrder = customOrder + 1
local FormatDropdown = mkDropdown(rowCFormat, {
        Options = { "OpenAI" }, Current = Settings.Custom.requestformat.format or "OpenAI",
        OnPick = function(v)
                Settings.Custom.requestformat.format = v
                saveSettingsNow()
        end,
})
FormatDropdown.Button.Size = UDim2.new(1, -150, 0, 30)
FormatDropdown.Button.Position = UDim2.new(0, 150, 0.5, -15)

local rowCStream = customRow("Streaming", customOrder); customOrder = customOrder + 1
local StreamToggle = mkToggle(rowCStream, Settings.Custom.streaming.enabled, function(state)
        Settings.Custom.streaming.enabled = state
        saveSettingsNow()
end)
StreamToggle.Holder.Position = UDim2.new(0, 150, 0.5, -12)

rowCHeader.Visible = ((Settings.Custom.authheaderformat.format or "Bearer") == "Custom")

-- // chats browser (📁) -------------------------------------------------------------------------
local function openChatBrowser()
        local chats = listSavedChats()
        if #chats == 0 then
                showToast("No saved chats yet", nil)
                return
        end
        local blocker = mk("TextButton", {
                Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", ZIndex = 40,
        }, DropdownLayer)
        local popupX = math.max(8, ChatsBtn.AbsolutePosition.X - 190)
        local popup = mk("Frame", {
                Size = UDim2.new(0, 220, 0, math.max(40, math.min(#chats * 29 + 10, 280))),
                Position = UDim2.new(0, popupX, 0, ChatsBtn.AbsolutePosition.Y + 32),
                BackgroundColor3 = RoleColor("Surface"), BorderSizePixel = 0, ZIndex = 41,
                ClipsDescendants = true,
        }, DropdownLayer)
        addCorner(popup, 10)
        addStroke(popup, "Accent", 1, 0.2)
        addPadding(popup, 4, 4, 4, 4)
        local scroll = mk("ScrollingFrame", {
                Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
                CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
                ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 4, ZIndex = 42,
        }, popup)
        mk("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
        for i, name in ipairs(chats) do
                mkButton({
                        Size = UDim2.new(1, 0, 0, 26), Text = name, TextSize = 12, Variant = "surface",
                        CornerRadius = 7, ZIndex = 43, LayoutOrder = i,
                        OnClick = function()
                                blocker:Destroy()
                                if Generating then
                                        showToast("Wait for the current response to finish", nil)
                                        return
                                end
                                loadChatFile(name)
                        end,
                }, scroll)
        end
        blocker.MouseButton1Click:Connect(function() blocker:Destroy() end)
end

-- // panel open/close + syncing --------------------------------------------------------------------
local function syncSettingsUI()
        syncAPIKeyRow()
        updateCustomVisibility()
        rowCHeader.Visible = ((Settings.Custom.authheaderformat.format or "Bearer") == "Custom")
        ModelsDropdown.Set(getSelectedModel())
        ProviderDropdown.Set(States.LastSelectedProvider)
        ThemeDropdown.Set(States.LastTheme or "Dark")
        FontDropdown.Set(States.Font or "Gotham")
        syncViewButtons()
        refreshModelsDropdown()
end

SettingsBtn.MouseButton1Click:Connect(function()
        SettingsPanel.Visible = not SettingsPanel.Visible
        if SettingsPanel.Visible then syncSettingsUI() end
end)
SPClose.MouseButton1Click:Connect(function() SettingsPanel.Visible = false end)
ChatsBtn.MouseButton1Click:Connect(openChatBrowser)

applyFontAndSave = function(name)
        if ApplyFont(name) then
                States.Font = name
                saveStatesNow()
        else
                showToast("Font not available: " .. tostring(name), "error")
        end
end

-- //=======================================================================//--
-- //              CHAT ENGINE — send / stop / continue / ideas             //--
-- //=======================================================================//--

local IDEA_POOL = {
        "Suggest 3 Scriptable Mechanics",
        "Luau Best Practices & Tips",
        "Pitch Me a Roblox Game Idea",
        "Help Me Design a Game Loop",
        "Brainstorm Game Mechanics",
}
local ideaShuffleIdx = 0

refreshIdeaChips = function()
        for i = 1, 3 do
                local text = IDEA_POOL[((ideaShuffleIdx + i - 1) % #IDEA_POOL) + 1]
                IdeaChips[i].Text = text
        end
end

local function shuffleIdeas()
        ideaShuffleIdx = (ideaShuffleIdx + 3) % #IDEA_POOL
        refreshIdeaChips()
end
ShuffleBtn.MouseButton1Click:Connect(shuffleIdeas)
for i = 1, 3 do
        IdeaChips[i].MouseButton1Click:Connect(function()
                sendUserMessage(IdeaChips[i].Text)
        end)
end

-- // send button state ----------------------------------------------------------
local function setSendButtonState()
        if Generating then
                SendBtn.Text = "⏹️"
                SendBtn.BackgroundColor3 = RoleColor("Error")
        else
                SendBtn.Text = "🚀"
                SendBtn.BackgroundColor3 = RoleColor("Accent")
        end
end
registerRefresher(setSendButtonState)

stopGeneration = function()
        if Generating then
                StopRequested = true
        end
end

--- derive a chat title from the first user message
local function deriveTitle(text)
        text = tostring(text):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
        if #text == 0 then return "New Chat" end
        if #text > 28 then text = string.sub(text, 1, 28) .. "…" end
        return text
end

local function appendUserMessage(text)
        local msg = { speaker = getPlayerName(), isPlayer = true, content = text, cutOff = false }
        table.insert(CurrentChat.messages, msg)
        renderMessage(msg, #CurrentChat.messages)
        if CurrentChat.name == "New Chat" then
                CurrentChat.name = uniqueChatName(deriveTitle(text))
                refreshHeaderTitle()
        end
        saveCurrentChat()
        return msg
end

--- shared generation pipeline.
--- nudge = hidden instruction appended to API context only (Continue flow)
local function doGenerate(nudge)
        if Generating then return end
        Generating = true
        StopRequested = false
        setSendButtonState()

        local indicator = showGeneratingIndicator("Generating")
        local ok, result
        task.spawn(function()
                ok, result = callProvider(States.LastSelectedProvider, nudge)
                indicator.Stop()

                if not ok then
                        Generating = false
                        StopRequested = false
                        setSendButtonState()
                        showToast(tostring(result), "error")
                        return
                end

                if StopRequested then
                        -- stopped before any text was revealed: discard entirely
                        Generating = false
                        StopRequested = false
                        setSendButtonState()
                        showToast("Response discarded", nil)
                        return
                end

                -- typewriter reveal (partial stays as permanent cut-off on Stop)
                local msg = typewriterReveal(result)
                Generating = false
                StopRequested = false
                setSendButtonState()

                -- [[BRANCH]] pass 2: on cutOff, the Continue flow will fork
                -- Chat.Name_BranchN.json here via States.ChatIndex instead of
                -- appending to the same transcript.
                if msg.cutOff then
                        -- Continue button is rendered by the cut-off badge; nothing else to do
                end
        end)
end

sendUserMessage = function(text)
        if Generating then
                showToast("Vallex AI is still responding…", nil)
                return
        end
        text = tostring(text or "")
        if #text == 0 then return end
        if States.LastSelectedProvider ~= "Mock (No Key)" and #getApiKey(States.LastSelectedProvider) == 0 then
                showToast("No API key set for " .. States.LastSelectedProvider .. " (Settings ⚙)", "error")
                return
        end
        appendUserMessage(text)
        doGenerate(nil)
end

continueFromCutoff = function(index)
        if Generating then
                showToast("Vallex AI is still responding…", nil)
                return
        end
        local msg = CurrentChat.messages[index]
        if not msg or not msg.cutOff then return end
        -- Keep every message (partial included) as context and ask for a fresh
        -- continuation. [[BRANCH]] pass 2 converts this into a new branch file
        -- (Chat.Name_BranchN.json) registered in States.ChatIndex.
        doGenerate("(Continue your previous response from exactly where it stopped. Do not repeat text you have already written.)")
end

SendBtn.MouseButton1Click:Connect(function()
        if Generating then
                stopGeneration()
        else
                sendUserMessage(InputBox.Text)
                InputBox.Text = ""
        end
end)
InputBox.FocusLost:Connect(function(enterPressed)
        if enterPressed and not Generating then
                sendUserMessage(InputBox.Text)
                InputBox.Text = ""
        end
end)

-- //=======================================================================//--
-- //                                 INIT                                  //--
-- //=======================================================================//--

-- (folders + States/Settings already loaded at the end of part 3, before UI)

-- keep legacy States mirror -> Settings on first migration
if States.TokenLimitEnabled then
        Settings.TokenLimits.Input.enabled = States.TokenLimitEnabled.Input == true
        Settings.TokenLimits.Output.enabled = States.TokenLimitEnabled.Output == true
end
if States.FocusModeEnabled then
        Settings.FocusMode.enabled = States.FocusModeEnabled == true
end
if kindof(States.ViewMode) == "string" then
        Settings.ViewMode = States.ViewMode
end

-- first-run: auto Portrait on small screens
if not FS.isFile(CONFIG.StatesFile) then
        local cam = workspace:FindFirstChildOfClass("Camera")
        if cam and cam.ViewportSize.X < 520 then
                Settings.ViewMode = "Portrait"
        end
end

-- validate persisted theme/font against what actually loaded
if not Themes[States.LastTheme] then States.LastTheme = "Dark" end
if not ApplyFont(States.Font or "Gotham") then
        ApplyFont("Gotham")
        States.Font = "Gotham"
end
ApplyTheme(States.LastTheme or "Dark")

-- sync everything that depends on loaded state
setSendButtonState()
syncViewButtons()
updateCustomVisibility()
refreshIdeaChips()
refreshHeaderTitle()

applyViewMode(Settings.ViewMode or "Landscape", true)

-- restore last chat or start fresh
if kindof(States.LastChat) == "string" and #States.LastChat > 0 and FS.isFile(chatFilePath(States.LastChat)) then
        loadChatFile(States.LastChat)
else
        renderTranscript()
end

-- default window visibility per persisted sidebar state
toggleMainWindow(States.SidebarOpen ~= false)

saveStatesNow()
saveSettingsNow()

print(("[Vallex AI] v%s loaded — %d themes available. Have fun, %s!")
        :format(CONFIG.ScriptVersion, (function()
                local n = 0
                for _ in pairs(Themes) do n = n + 1 end
                return n
        end)(), getPlayerName()))
