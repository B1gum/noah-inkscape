local M = {}

-----------------------------------------------------------------------
-- Config
-----------------------------------------------------------------------

local PASTE_STYLE_MENU = { "Edit", "Paste...", "Style" }
local INKSCAPE_APP_NAME = "Inkscape"
local INKSCAPE_MIME = "image/x-inkscape-svg"

-- 96 px per inch
local MM_TO_PX = 96 / 25.4

local function mm(v)
    return string.format("%.8f", v * MM_TO_PX)
end

-----------------------------------------------------------------------
-- Canonical style values
-----------------------------------------------------------------------

local widths = {
    s = mm(0.35), -- standard
    e = mm(0.55), -- emphasized
    h = mm(0.85), -- heavy
}

local dashes = {
    ["."] = mm(0.35) .. "," .. mm(1.40), -- dotted
    [":"] = mm(4.20) .. "," .. mm(2.80), -- light-dashed
    [";"] = mm(1.40) .. "," .. mm(1.40), -- dashed
}

-----------------------------------------------------------------------
-- Marker defs
-----------------------------------------------------------------------

local force_marker_def = [[
<defs>
  <marker
    id="noah-force-arrow"
    style="overflow:visible"
    refX="0"
    refY="0"
    orient="auto-start-reverse"
    markerWidth="2"
    markerHeight="2"
    viewBox="0 0 1 1"
    preserveAspectRatio="xMidYMid"
    markerUnits="strokeWidth">
    <path
      transform="scale(0.5)"
      style="fill:context-stroke;fill-rule:evenodd;stroke:context-stroke;stroke-width:1pt"
      d="M 5.77,0 -2.88,5 V -5 Z" />
  </marker>
</defs>
]]

local axes_marker_def = [[
<defs>
  <marker
    id="noah-axes-arrow"
    style="overflow:visible"
    refX="0"
    refY="0"
    orient="auto-start-reverse"
    markerWidth="1"
    markerHeight="1"
    viewBox="0 0 1 1"
    preserveAspectRatio="xMidYMid"
    markerUnits="strokeWidth">
    <path
      transform="scale(0.5)"
      style="fill:context-stroke;fill-rule:evenodd;stroke:context-stroke;stroke-width:1pt"
      d="M 5.77,0 -2.88,5 V -5 Z" />
  </marker>
</defs>
]]

-----------------------------------------------------------------------
-- SVG clipboard factory
-----------------------------------------------------------------------

local function makeStyleClipboard(style_string, defs)
    defs = defs or ""

    return ([[<?xml version="1.0" encoding="UTF-8"?>
<svg
  xmlns="http://www.w3.org/2000/svg"
  xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape">
  %s
  <inkscape:clipboard style="%s" />
</svg>]]):format(defs, style_string)
end

-----------------------------------------------------------------------
-- Semantic operations
--
-- IMPORTANT:
-- Each key only sets its own dimension.
-- That is what makes them composable.
-----------------------------------------------------------------------

local function op_standard()
    return makeStyleClipboard("stroke-width:" .. widths.s)
end

local function op_emphasized()
    return makeStyleClipboard("stroke-width:" .. widths.e)
end

local function op_heavy()
    return makeStyleClipboard("stroke-width:" .. widths.h)
end

local function op_solid()
    return makeStyleClipboard("stroke-dasharray:none;stroke-dashoffset:0")
end

local function op_dotted()
    return makeStyleClipboard(
        "stroke-dasharray:" .. dashes["."] .. ";stroke-dashoffset:0;stroke-linecap:round"
    )
end

local function op_lightdashed()
    return makeStyleClipboard(
        "stroke-dasharray:" .. dashes[":"] .. ";stroke-dashoffset:0;stroke-linecap:round"
    )
end

local function op_dashed()
    return makeStyleClipboard(
        "stroke-dasharray:" .. dashes[";"] .. ";stroke-dashoffset:0;stroke-linecap:round"
    )
end

local function op_force_arrow()
    return makeStyleClipboard(
        "marker-start:none;marker-mid:none;marker-end:url(#noah-force-arrow)",
        force_marker_def
    )
end

local function op_axes_arrow()
    return makeStyleClipboard(
        "marker-start:none;marker-mid:none;marker-end:url(#noah-axes-arrow)",
        axes_marker_def
    )
end

local function op_no_arrow()
    return makeStyleClipboard(
        "marker-start:none;marker-mid:none;marker-end:none"
    )
end

local operations = {
    s = op_standard,
    e = op_emphasized,
    h = op_heavy,

    l = op_solid,
    ["."] = op_dotted,
    [":"] = op_lightdashed,
    [";"] = op_dashed,

    ["æ"] = op_no_arrow,
    a = op_axes_arrow,
    x = op_force_arrow,
}

-----------------------------------------------------------------------
-- Queue so rapid successive key presses work reliably
-----------------------------------------------------------------------

local queue = {}
local busy = false

local function isInkscapeFrontmost()
    local app = hs.application.frontmostApplication()
    return app and app:name() == INKSCAPE_APP_NAME
end

-----------------------------------------------------------------------
-- Explicit style-mode behavior
--
-- We intentionally do NOT try to infer whether Inkscape is currently in
-- a canvas, text field, Save dialog, etc. That proved unreliable with the
-- GTK/macOS accessibility bridge. Instead:
--
--   '        toggles style mode on/off
--   Shift+Y   opens the symbol picker at all times while Inkscape is frontmost
--   mode OFF  -> every other key passes through normally
--   mode ON   -> style keys are intercepted
--
-- This makes text entry deterministic: turn style mode off before typing.
-----------------------------------------------------------------------

local function applyStyleSVG(svg)
    local app = hs.application.frontmostApplication()
    if not app or app:name() ~= INKSCAPE_APP_NAME then
        return
    end

    local ok = hs.pasteboard.writeDataForUTI(INKSCAPE_MIME, svg)

    if not ok then
        hs.alert.show("Could not write Inkscape style clipboard")
        return
    end

    -- small delay so pasteboard ownership settles
    hs.timer.doAfter(0.02, function()
        local pasted = app:selectMenuItem(PASTE_STYLE_MENU)
        if not pasted then
            hs.alert.show("Could not invoke Paste Style")
        end
    end)
end

local function processQueue()
    if busy or #queue == 0 then
        return
    end

    busy = true
    local key = table.remove(queue, 1)
    local fn = operations[key]

    if fn then
        applyStyleSVG(fn())
    end

    -- space out events slightly so repeated keys don't race
    hs.timer.doAfter(0.08, function()
        busy = false
        processQueue()
    end)
end

local function enqueue(key)
    table.insert(queue, key)
    processQueue()
end

-----------------------------------------------------------------------
-- Event tap
-----------------------------------------------------------------------

-- Start OFF so Inkscape behaves like a normal application until the user
-- explicitly enters the style layer with the apostrophe key.
M.enabled = false
M.tap = nil
local swallowed = {}

local function toggleStyleMode(keycode)
    swallowed[keycode] = true
    M.enabled = not M.enabled
    hs.alert.show(M.enabled and "Inkscape style mode ON" or "Inkscape style mode OFF")
    return true
end

local function handleEvent(ev)
    if not isInkscapeFrontmost() then
        return false
    end

    local t = ev:getType()
    local keycode = ev:getKeyCode()

    if t == hs.eventtap.event.types.keyUp then
        if swallowed[keycode] then
            swallowed[keycode] = nil
            return true
        end
        return false
    end

    local chars = ev:getCharacters(true)
    if not chars or chars == "" then
        return false
    end

    local flags = ev:getFlags()

    -- Never interfere with command/control/option shortcuts.
    if flags.cmd or flags.ctrl or flags.alt then
        return false
    end

    -- Apostrophe is the one always-active Inkscape-layer key.
    -- It toggles the entire bare-key style layer, regardless of whether
    -- Inkscape currently has a canvas, dialog, or text widget focused.
    if chars == "'" then
        return toggleStyleMode(keycode)
    end

    -- Symbol picker is deliberately independent of style mode. Shift+Y is an
    -- Inkscape-wide workflow shortcut; bare y remains completely untouched.
    local symbolKey = require("inkscape_symbols").config.shortcut_key or "y"
    if flags.shift and chars:lower() == symbolKey:lower() then
        swallowed[keycode] = true
        require("inkscape_symbols").show()
        return true
    end

    -- When style mode is OFF, absolutely everything else passes through.
    -- This is the key property that fixes Save As and normal text editing.
    if not M.enabled then
        return false
    end

    -- Semantic style keys are only meaningful in style mode. We use the
    -- produced character so punctuation bindings such as :, ; and . keep
    -- working correctly on the active keyboard layout.
    if operations[chars] then
        swallowed[keycode] = true
        enqueue(chars)
        return true
    end

    return false
end

function M.start()
    -- Keep save/export watchers tied to the lifetime of their Inkscape document.
    -- start() is idempotent, so this is safe even if the manager is also loaded
    -- explicitly from ~/.hammerspoon/init.lua.
    local watchers_ok, watchers = pcall(require, "inkscape_watchers")
    if watchers_ok and watchers and watchers.start then
        watchers.start()
    end

    if M.tap then
        M.tap:stop()
    end

    M.tap = hs.eventtap.new(
        {
            hs.eventtap.event.types.keyDown,
            hs.eventtap.event.types.keyUp,
        },
        handleEvent
    )

    M.tap:start()
    print("[inkscape_styles] started")
    return M
end

function M.stop()
    if M.tap then
        M.tap:stop()
        M.tap = nil
    end
end

return M
