-- Plugins are built with hyprpm (./install.sh plugins) and loaded here with hl.plugin.load.
-- Hyprland loads them after this file is parsed, then parses it again: plugin options and
-- functions only exist on that second pass, so every block below is guarded.
-- HyprGlass comes from a local fork (~/.local/src/HyprGlass, MacShell shapes + displacement rim),
-- installed to ~/.local/share/hyprglass-macshell. Rebuild the fork after a Hyprland update.
local C = COLORS
local USER = os.getenv("USER")
local HOME = os.getenv("HOME")
local HYPRPM = "/var/cache/hyprpm/" .. USER

local function exists(path)
    local f = io.open(path, "r")
    if f then f:close() end
    return f ~= nil
end

-- load the first of the given .so files that exists; returns its path
local function load(...)
    for _, path in ipairs({ ... }) do
        if exists(path) then
            hl.plugin.load(path)
            return path
        end
    end
end

load(HYPRPM .. "/hyprland-plugins/hyprbars.so")
load(HYPRPM .. "/hyprland-plugins/hyprfocus.so")
load(HYPRPM .. "/Hyprspace/Hyprspace.so")
load(HYPRPM .. "/dynamic-cursors/dynamic-cursors.so")
-- the fork when it's built for this Hyprland, else upstream HyprGlass (install.sh plugins builds both)
local FORK_SO = HOME .. "/.local/share/hyprglass-macshell/hyprglass.so"
local GLASS_IS_FORK = load(FORK_SO, HOME .. "/.local/share/hyprglass/hyprglass.so", HYPRPM .. "/HyprGlass/hyprglass.so") == FORK_SO

local function loaded(name)
    for _, p in ipairs(hl.get_loaded_plugins()) do
        if p.name and p.name:lower() == name:lower() then return true end
    end
    return false
end

hl.permission({ binary = "/usr/(bin|local/bin)/hyprpm", type = "plugin", mode = "allow" })


-- Title bars with macOS traffic lights ------------------------------------------------
if hl.plugin.hyprbars then
    hl.config({ plugin = { hyprbars = {
        enabled                    = true,
        bar_height                 = 28,
        bar_color                  = C.bar_bg,
        col                        = { text = C.on_surface },
        -- hyprbars blurs a square rect that ignores window rounding (pointy corners)
        bar_blur                   = false,
        bar_text_font              = "JetBrainsMono Nerd Font",
        bar_text_size              = 10,
        bar_text_align             = "center",
        bar_part_of_window         = true,
        bar_precedence_over_border = true,
        bar_padding                = 10,
        bar_button_padding         = 8,
        icon_on_hover              = true,
        inactive_button_color      = C.outline_dim,
        on_double_click            = WINCTL .. " max",
    } } })
    -- buttons are listed right to left
    hl.plugin.hyprbars.add_button({ bg_color = C.error,    fg_color = C.surface, size = 13, icon = "󰖭",
                                    action = "hyprctl dispatch 'hl.dsp.window.close()'" })
    hl.plugin.hyprbars.add_button({ bg_color = C.tertiary, fg_color = C.surface, size = 13, icon = "󰖯",
                                    action = WINCTL .. " max" })
    hl.plugin.hyprbars.add_button({ bg_color = C.primary,  fg_color = C.surface, size = 13, icon = "󰖰",
                                    action = HOME .. "/.config/hypr/scripts/minimize.sh" })
end


-- Focus flash ---------------------------------------------------------------------------
if loaded("hyprfocus") then
    hl.config({ plugin = { hyprfocus = {
        enable                   = true,
        -- shrink also fires when closing a window refocuses the one behind (twitch)
        keyboard_focus_animation = "flash",
        mouse_focus_animation    = "none",
        shrink_percentage        = 0.97,
    } } })
    hl.animation({ leaf = "hyprfocusIn",  enabled = true, speed = 1.7, bezier = "overshot" })
    hl.animation({ leaf = "hyprfocusOut", enabled = true, speed = 1.7, bezier = "overshot" })
end


-- Workspace overview (Hyprspace) ---------------------------------------------------------
if hl.plugin.overview then
    hl.config({ plugin = { overview = {
        panelColor              = C.bar_bg,
        panelBorderColor        = C.outline_dim,
        panelBorderWidth        = 1,
        panelHeight             = 180,
        workspaceActiveBorder   = C.primary,
        workspaceInactiveBorder = C.outline_dim,
        workspaceBorderSize     = 2,
        centerAligned           = true,
        onBottom                = false,
        showNewWorkspace        = true,
        showEmptyWorkspace      = true,
        exitOnClick             = true,
        switchOnDrop            = true,
        -- 4-finger gestures are bound in hyprland.lua; keep the 3-finger workspace swipe untouched
        disableGestures         = true,
    } } })
end


-- Cursor tilt + shake to find ------------------------------------------------------------
if hl.plugin.dynamic_cursors then
    hl.config({ plugin = { dynamic_cursors = {
        enabled = true,
        mode    = "tilt",
        tilt    = { limit = 5000, activation = "negative_quadratic" },
        shake   = { enabled = true },
        -- re-render SVG hyprcursor at magnified size so shake-grow stays sharp
        hyprcursor = { enabled = true, nearest = false, resolution = -1, fallback = "clientside" },
    } } })
end


-- Liquid Glass (HyprGlass) ------------------------------------------------------------------
if hl.plugin.hyprglass then
    local hg = hl.plugin.hyprglass

    hl.config({ plugin = { hyprglass = {
        -- off by default; scripts/winctl.sh tags floating, non-maximized windows hyprglass_enabled
        enabled        = 0,
        default_theme  = "dark",
        default_preset = "pomme",
        tint_color     = tonumber(C.glass_tint) or 0,
        layers = {
            enabled = 1,
            -- re-render on every frame something behind changes (default caps at 30 fps); static scenes stay free
            live_resample_fps = 0,
        },
    } } })

    -- Liquid Glass engine (web version: backdrop-filter: url(#displace) blur(1.5px) saturate(150%)
    -- brightness(0.85 dark / 1.2 light), no tint):
    --   blur 1.5px = sigma 1.5 = blur_strength 0.375 x 1 pass (hyprglass: radius = strength * 12, sigma = radius / 3)
    -- Added on top: the thin rim highlight (bevel) real Liquid Glass has.
    hg.preset("macshell", {
        inherits = "pomme",
        blur_strength = 0.375, blur_iterations = 1, chromatic_aberration = 0, contrast = 1.0, saturation = 1.5,
        bevel_strength = 0.85, bevel_size = 1.5, bevel_tint = 0.25, specular_strength = 0.5, fresnel_strength = 0.15,
        -- dark: + adaptive tint (darken over bright content, lift over dark) so the glass never goes flat
        dark  = { tint_color = 0, brightness = 0.85, contrast = 1.0, saturation = 1.5, adaptive_dim = 0.2, adaptive_boost = 0.1 },
        light = { tint_color = 0, brightness = 1.2,  contrast = 1.0, saturation = 1.5 },
    })
    -- the menu bar sits under small text and icons: more frost there keeps them readable
    hg.preset("macshellbar", { inherits = "macshell", blur_strength = 0.6 })
    -- menus, Control Center, Spotlight: Apple's frostier "regular" glass so their text stays readable
    hg.preset("macshellpanel", { inherits = "macshell", blur_strength = 1.2, blur_iterations = 2 })

    -- MacShell layers: menu bar (macbarbg), Dock, popovers/menus/Control Center (macbar), Spotlight (macspot),
    -- Alt+Tab switcher (macswitch), wallpaper picker (macwall)
    if GLASS_IS_FORK then
        -- Fork (~/.local/src/HyprGlass): rim refraction, bevel `depth` px wide.
        -- profile 0 = the engine's displacement map (getDisplacementFilter: depth 10, strength 80, yScale 0.75);
        -- profile 1 = thick convex glass: squircle bezel + Snell's law (strength 100 = physical shift).
        -- The bevel's corner radius is the shape's own (namespace_radii), as the engine reads border-radius.
        hl.config({ plugin = { hyprglass = {
            displacement = {
                profile  = 0,
                ior      = 1.5,
                strength = 80,
                depth    = 10,
                y_scale  = 0.75,
                -- Apple's rim catches the light on both ends of the light axis
                mirror_highlight = 1.0,
            },
            layers = {
                namespaces = "waybar, rofi, macbarbg, macdock, macbar, macspot, macswitch, macwall",
                -- bar and Dock send their exact shape (ext-background-effect); macbar's region is only the popover
                -- area under the bar, so the bar's own text never gets glass
                namespace_mask_modes = "macbarbg=region, macdock=region, macbar=region",
                namespace_radii = "macbarbg=0, macdock=18",
                -- shape maps: every tile, button, menu and field is its own glass shape, taken from what
                -- MacShell draws (follows open/close animations); full glass from the threshold alpha up
                namespace_shape_maps = "macbar, macspot, macswitch, macwall",
                namespace_mask_thresholds = "macbar=0.08, macspot=0.08, macswitch=0.08, macwall=0.08",
                namespace_presets = "macbarbg:macshellbar, macdock:macshell, macbar:macshellpanel, macspot:macshellpanel, macswitch:macshellpanel, macwall:macshellpanel",
                -- the 28 px bar pulls less than the dock pill
                namespace_displacement = "macbarbg=0.25",
            },
        } } })
    else
        -- Upstream HyprGlass: no rim refraction; `contour` gives each shape MacShell draws its own glass
        -- (the fork's shape maps). Bar and Dock send their exact shape (ext-background-effect): region.
        hg.layer("waybar")
        hg.layer("rofi")
        hg.layer("macbarbg",  { preset = "macshellbar",   mask_mode = "region" })
        hg.layer("macdock",   { preset = "macshell",      mask_mode = "region" })
        -- macbar asks for blur over the whole popover area, so region would frost it all: glass only on
        -- the menus and panels it draws (contour), like the fork's shape maps
        hg.layer("macbar",    { preset = "macshellpanel", mask_mode = "contour", mask_threshold = 0.08 })
        hg.layer("macspot",   { preset = "macshellpanel", mask_mode = "contour", mask_threshold = 0.08 })
        hg.layer("macswitch", { preset = "macshellpanel", mask_mode = "contour", mask_threshold = 0.08 })
        hg.layer("macwall",   { preset = "macshellpanel", mask_mode = "contour", mask_threshold = 0.08 })
    end
end
