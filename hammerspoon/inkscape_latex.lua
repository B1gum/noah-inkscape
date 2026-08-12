local M = {}

------------------------------------------------------------------------
-- Config
------------------------------------------------------------------------

M.config = {
    inkscape_app_name = "Inkscape",
    inkscape_mime = "image/x-inkscape-svg",

    -- iTerm2 dedicated-hotkey-window shortcut. IMPORTANT: configure the
    -- "Inkscape LaTeX" profile to use this exact hotkey in iTerm2.
    -- We deliberately invoke the hotkey itself rather than iTerm2's legacy
    -- AppleScript `create hotkey window` command. On iTerm2 3.6.11 that
    -- command can crash while returning the new window AppleEvent object.
    iterm_hotkey = {
        mods = { "ctrl", "alt", "shift", "cmd" },
        key = "l",
    },

    -- Inkscape-side trigger. Shift+T leaves ordinary lowercase t untouched.
    label_shortcut = {
        key = "t",
        shift = true,
    },

    -- Bundle ID used to detect when the hotkey window has actually appeared.
    iterm_bundle_id = "com.googlecode.iterm2",
    iterm_launch_timeout = 2.5,

    -- Approximate placeholder appearance inside Inkscape. The final text is
    -- still typeset by LaTeX via PDF+LaTeX export.
    preview_font_family = "Latin Modern Roman",
    preview_font_size_px = 13.333333, -- ~10 pt at 96 CSS px/in

    -- Hammerspoon will resize the dedicated iTerm2 window after it appears.
    popup = {
        width_ratio = 0.58,
        height_ratio = 0.24,
        max_width = 780,
        max_height = 300,
        min_width = 560,
        min_height = 220,
    },
}

local PASTE_MENU = { "Edit", "Paste" }
local PASTE_IN_PLACE_MENU = { "Edit", "Paste...", "In Place" }
local COPY_MENU = { "Edit", "Copy" }
local DELETE_MENU = { "Edit", "Delete" }

------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------

local function trim_trailing_newlines(s)
    if not s then
        return ""
    end
    s = s:gsub("\r\n", "\n")
    return (s:gsub("\n+$", ""))
end

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function applescript_escape(s)
    return tostring(s)
        :gsub("\\", "\\\\")
        :gsub('"', '\\"')
end

local function xml_escape(s)
    return tostring(s)
        :gsub("&", "&amp;")
        :gsub("<", "&lt;")
        :gsub(">", "&gt;")
end

local function xml_unescape(s)
    return tostring(s)
        :gsub("&lt;", "<")
        :gsub("&gt;", ">")
        :gsub("&quot;", '"')
        :gsub("&apos;", "'")
        :gsub("&amp;", "&")
end

local function write_file(path, data)
    local f, err = io.open(path, "w")
    if not f then
        return nil, err
    end
    f:write(data)
    f:close()
    return true
end

local function read_file(path)
    local f = io.open(path, "r")
    if not f then
        return nil
    end
    local data = f:read("*a")
    f:close()
    return data
end

local function file_exists(path)
    return hs.fs.attributes(path) ~= nil
end

local function remove_file(path)
    if file_exists(path) then
        os.remove(path)
    end
end

local function is_inkscape_frontmost()
    local app = hs.application.frontmostApplication()
    return app and app:name() == M.config.inkscape_app_name
end

local TEXT_INPUT_ROLES = {
    AXTextField = true,
    AXTextArea = true,
    AXComboBox = true,
    AXSearchField = true,
}

local function focused_ui_is_text_input()
    local element = hs.uielement.focusedElement()
    if not element then
        return false
    end

    local ok, role = pcall(function()
        return element:role()
    end)

    return ok and TEXT_INPUT_ROLES[role] == true
end

local function inkscape_app()
    return hs.application.find(M.config.inkscape_app_name)
end

------------------------------------------------------------------------
-- Inkscape SVG text handling
------------------------------------------------------------------------

local NON_TEXT_OBJECT_PATTERNS = {
    "<path[%s>]",
    "<rect[%s>]",
    "<circle[%s>]",
    "<ellipse[%s>]",
    "<polygon[%s>]",
    "<polyline[%s>]",
    "<image[%s>]",
    "<use[%s>]",
}

local function looks_like_single_text_object(svg)
    if not svg or not svg:find("<text[%s>]", 1) then
        return false
    end

    local text_count = 0
    for _ in svg:gmatch("<text[%s>]") do
        text_count = text_count + 1
    end

    if text_count ~= 1 then
        return false
    end

    for _, pat in ipairs(NON_TEXT_OBJECT_PATTERNS) do
        if svg:find(pat) then
            return false
        end
    end

    -- Ordinary Phase-17 labels are intentionally one visual line. Complex or
    -- multi-line formula layout belongs to TexText (Phase 16).
    local tspan_count = 0
    for _ in svg:gmatch("<tspan[%s>]") do
        tspan_count = tspan_count + 1
    end

    return tspan_count <= 1
end

local function extract_latex_from_svg(svg)
    if not looks_like_single_text_object(svg) then
        return nil
    end

    local inner = svg:match("<tspan[^>]*>(.-)</tspan>")
    if inner == nil then
        inner = svg:match("<text[^>]*>(.-)</text>")
    end

    if inner == nil then
        return nil
    end

    -- Refuse nested markup rather than silently mangling a complex text object.
    if inner:find("<[^>]+>") then
        return nil
    end

    return xml_unescape(inner)
end

local function replace_latex_in_svg(svg, latex)
    local escaped = xml_escape(latex)

    local replaced, count = svg:gsub(
        "(<tspan[^>]*>)(.-)(</tspan>)",
        function(opening, _, closing)
            return opening .. escaped .. closing
        end,
        1
    )

    if count == 1 then
        return replaced
    end

    replaced, count = svg:gsub(
        "(<text[^>]*>)(.-)(</text>)",
        function(opening, _, closing)
            return opening .. escaped .. closing
        end,
        1
    )

    if count == 1 then
        return replaced
    end

    return nil
end

local function make_new_text_svg(latex)
    local escaped = xml_escape(latex)
    local family = xml_escape(M.config.preview_font_family)

    return ([[<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<svg
  xmlns="http://www.w3.org/2000/svg"
  xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape"
  xmlns:sodipodi="http://sodipodi.sourceforge.net/DTD/sodipodi-0.dtd">
  <text
    xml:space="preserve"
    style="font-size:%.8fpx;font-family:'%s';fill:#000000;fill-opacity:1;stroke:none;stroke-width:1">
    <tspan sodipodi:role="line">%s</tspan>
  </text>
</svg>]]):format(M.config.preview_font_size_px, family, escaped)
end

------------------------------------------------------------------------
-- Popup window management
------------------------------------------------------------------------

local function iterm_app()
    return hs.application.get(M.config.iterm_bundle_id)
        or hs.application.find("iTerm2")
end

local function position_popup_window(win, target_screen, target_space)
    if not win then
        return
    end

    -- A dedicated iTerm2 hotkey window configured as Floating + All Spaces is
    -- allowed to overlay a native-fullscreen app. Do not move it between
    -- Mission Control Spaces here: its All Spaces behavior is exactly what we
    -- want. We only move/resize it on the correct physical display.

    local sf = (target_screen or win:screen()):frame()
    local cfg = M.config.popup

    local width = math.max(
        cfg.min_width,
        math.min(cfg.max_width, sf.w * cfg.width_ratio)
    )
    local height = math.max(
        cfg.min_height,
        math.min(cfg.max_height, sf.h * cfg.height_ratio)
    )

    local frame = {
        x = sf.x + (sf.w - width) / 2,
        y = sf.y + (sf.h - height) / 2,
        w = width,
        h = height,
    }

    win:setFrame(frame, 0)
    win:focus()
end

local function send_iterm_hotkey()
    local hk = M.config.iterm_hotkey
    hs.eventtap.keyStroke(hk.mods, hk.key, 0)
end

local function close_iterm_popup(session)
    -- Close the actual transient hotkey window rather than merely leaving the
    -- login shell behind. The next dedicated-hotkey invocation can create/show
    -- a fresh window again.
    local win = session and session.iterm_window or nil

    if not win then
        local app = iterm_app()
        win = app and app:focusedWindow() or nil
    end

    if win then
        local ok, closed = pcall(function()
            return win:close()
        end)
        if ok and closed then
            return
        end
    end

    -- Fallback: if macOS no longer exposes the window object, hide the hotkey
    -- window via its own dedicated shortcut.
    local app = iterm_app()
    if app and app:isFrontmost() then
        send_iterm_hotkey()
    end
end

local function make_runner_script(tex_path, done_path, runner_path)
    local script = table.concat({
        "#!/bin/zsh\n",
        "nvim ", shell_quote(tex_path),
        " -c ", shell_quote("lua require('noah-inkscape.label').setup()"), "\n",
        "rc=$?\n",
        "printf '%s' \"$rc\" > ", shell_quote(done_path), "\n",
        "exit 0\n",
    })

    local ok, err = write_file(runner_path, script)
    if not ok then
        return nil, err
    end

    return true
end

local function launch_iterm_editor(tex_path, done_path, runner_path, target_screen, target_space, session)
    local made, make_err = make_runner_script(tex_path, done_path, runner_path)
    if not made then
        return nil, "could not create popup runner: " .. tostring(make_err)
    end

    -- Do NOT use `create hotkey window with profile` through AppleScript here.
    -- The supported interactive path for a dedicated hotkey window is its
    -- registered system-wide hotkey, and using it also gives us the desired
    -- Floating/All-Spaces behavior over fullscreen Inkscape.
    local command = "/bin/zsh " .. shell_quote(runner_path)
    local deadline = hs.timer.secondsSinceEpoch() + M.config.iterm_launch_timeout
    local timer
    send_iterm_hotkey()

    timer = hs.timer.doEvery(0.04, function()
        local app = iterm_app()
        local win = app and app:focusedWindow() or nil

        if app and app:isFrontmost() and win then
            timer:stop()
            if session then
                session.iterm_window = win
            end
            position_popup_window(win, target_screen, target_space)

            -- Give the shell a moment to become ready on the very first reveal,
            -- then type only the path to our temporary runner. No AppleScript,
            -- no nested shell quoting, and no iTerm scripting object is involved.
            hs.timer.doAfter(0.10, function()
                hs.eventtap.keyStrokes(command, app)
                hs.eventtap.keyStroke({}, "return", 0, app)
            end)
            return
        end

        if hs.timer.secondsSinceEpoch() >= deadline then
            timer:stop()
            hs.alert.show(
                "iTerm2 hotkey window did not appear. Check that the Inkscape LaTeX profile uses "
                .. table.concat(M.config.iterm_hotkey.mods, "+")
                .. "+" .. M.config.iterm_hotkey.key
            )
            -- Wake the normal completion poller so the temporary session is
            -- restored/cleaned rather than remaining stuck indefinitely.
            write_file(done_path, "1\n")
        end
    end)

    return true
end

------------------------------------------------------------------------
-- One label-edit transaction
------------------------------------------------------------------------

M.session = nil

local function restore_clipboard(session)
    if session and session.saved_clipboard then
        hs.pasteboard.writeAllData(session.saved_clipboard)
    end
end

local function cleanup_session(session)
    if not session then
        return
    end

    if session.poller then
        session.poller:stop()
    end

    remove_file(session.tex_path)
    remove_file(session.done_path)
    remove_file(session.runner_path)

    if M.session == session then
        M.session = nil
    end
end

local function focus_inkscape(session, callback)
    -- The editor process has finished. Close the transient terminal window
    -- first, then wait until Inkscape is *actually* frontmost before touching
    -- its menus. This avoids paste/delete actions leaking into iTerm2.
    close_iterm_popup(session)

    local app = inkscape_app()
    if not app then
        restore_clipboard(session)
        cleanup_session(session)
        hs.alert.show("Inkscape is no longer running")
        return
    end

    app:activate(true)

    local deadline = hs.timer.secondsSinceEpoch() + 1.5
    local timer
    timer = hs.timer.doEvery(0.03, function()
        if app:isFrontmost() then
            timer:stop()
            callback(app)
            return
        end

        if hs.timer.secondsSinceEpoch() >= deadline then
            timer:stop()
            restore_clipboard(session)
            cleanup_session(session)
            hs.alert.show("Could not return focus to Inkscape")
        end
    end)
end

local function finish_session(session)
    local rc = tonumber(trim_trailing_newlines(read_file(session.done_path) or "1")) or 1
    local edited = trim_trailing_newlines(read_file(session.tex_path) or "")

    if rc ~= 0 then
        focus_inkscape(session, function()
            restore_clipboard(session)
            cleanup_session(session)
        end)
        return
    end

    if edited:find("\n", 1, true) then
        focus_inkscape(session, function()
            restore_clipboard(session)
            cleanup_session(session)
            hs.alert.show("Raw Inkscape labels must be one line; use TexText for multi-line math")
        end)
        return
    end

    -- Castel-style empty/new sentinel: opening the editor and quitting without
    -- changing $$ should not create a label.
    if not session.original_svg and (edited == "" or edited == "$$") then
        focus_inkscape(session, function()
            restore_clipboard(session)
            cleanup_session(session)
        end)
        return
    end

    if session.original_svg and edited == session.original_latex then
        focus_inkscape(session, function()
            restore_clipboard(session)
            cleanup_session(session)
        end)
        return
    end

    local svg
    if session.original_svg then
        svg = replace_latex_in_svg(session.original_svg, edited)
        if not svg then
            focus_inkscape(session, function()
                restore_clipboard(session)
                cleanup_session(session)
                hs.alert.show("Could not rewrite the selected Inkscape text object")
            end)
            return
        end
    else
        svg = make_new_text_svg(edited)
    end

    focus_inkscape(session, function(app)
        if session.original_svg then
            -- Use Inkscape's menu directly rather than a global Delete key.
            -- That prevents a slow focus transition from sending keystrokes
            -- into the terminal after Neovim exits.
            local deleted = app:selectMenuItem(DELETE_MENU)
            if not deleted then
                restore_clipboard(session)
                cleanup_session(session)
                hs.alert.show("Could not delete the original Inkscape label")
                return
            end
        end

        local ok = hs.pasteboard.writeDataForUTI(M.config.inkscape_mime, svg)
        if not ok then
            restore_clipboard(session)
            cleanup_session(session)
            hs.alert.show("Could not put the LaTeX label on the Inkscape clipboard")
            return
        end

        hs.timer.doAfter(0.04, function()
            local pasted

            if session.original_svg then
                pasted = app:selectMenuItem(PASTE_IN_PLACE_MENU)
            else
                -- Select the Inkscape Paste menu item directly. Do not emit a
                -- global Cmd-V: if macOS focus lags by even a fraction of a
                -- second, that paste would otherwise land in the iTerm shell.
                pasted = app:selectMenuItem(PASTE_MENU)
            end

            if not pasted then
                hs.alert.show("Could not paste the edited label into Inkscape")
            end

            hs.timer.doAfter(0.20, function()
                restore_clipboard(session)
                cleanup_session(session)
            end)
        end)
    end)
end

local function start_editor_with_selection_capture()
    if M.session then
        hs.alert.show("A LaTeX label editor is already open")
        return
    end

    local app = inkscape_app()
    if not app or not app:isFrontmost() then
        return
    end

    local front_window = app:focusedWindow()
    local target_screen = front_window and front_window:screen() or hs.screen.mainScreen()
    local target_space = nil

    if front_window and hs.spaces then
        local ok, spaces = pcall(hs.spaces.windowSpaces, front_window)
        if ok and spaces and spaces[1] then
            target_space = spaces[1]
        else
            local ok_focused, focused = pcall(hs.spaces.focusedSpace)
            if ok_focused then
                target_space = focused
            end
        end
    end

    local temp_base = os.tmpname()
    -- Some Lua builds create the path returned by os.tmpname(); we only use it
    -- as a unique basename for the two files below.
    remove_file(temp_base)

    local session = {
        saved_clipboard = hs.pasteboard.readAllData(),
        original_svg = nil,
        original_latex = nil,
        tex_path = temp_base .. ".tex",
        done_path = temp_base .. ".done",
        runner_path = temp_base .. ".runner.zsh",
        target_screen = target_screen,
        target_space = target_space,
    }

    M.session = session

    local before = hs.pasteboard.changeCount()
    local copied = app:selectMenuItem(COPY_MENU)

    hs.timer.doAfter(0.06, function()
        -- If Copy actually changed the clipboard and the selection is a simple
        -- text object, pre-fill the popup with that label and preserve its SVG
        -- so we can paste it back in-place after editing.
        if copied and hs.pasteboard.changeCount() ~= before then
            local svg = hs.pasteboard.readDataForUTI(M.config.inkscape_mime)
            local latex = extract_latex_from_svg(svg)

            if latex then
                session.original_svg = svg
                session.original_latex = latex
            end
        end

        local initial = session.original_latex or "$$"
        local ok, err = write_file(session.tex_path, initial .. "\n")

        if not ok then
            restore_clipboard(session)
            cleanup_session(session)
            hs.alert.show("Could not create label temp file: " .. tostring(err))
            return
        end

        local launched, launch_err = launch_iterm_editor(
            session.tex_path,
            session.done_path,
            session.runner_path,
            session.target_screen,
            session.target_space,
            session
        )

        if not launched then
            restore_clipboard(session)
            cleanup_session(session)
            hs.alert.show("Could not open iTerm2 label popup: " .. tostring(launch_err))
            return
        end

        session.poller = hs.timer.doEvery(0.08, function()
            if file_exists(session.done_path) then
                session.poller:stop()
                finish_session(session)
            end
        end)
    end)
end

------------------------------------------------------------------------
-- Event tap: Shift+T in Inkscape
------------------------------------------------------------------------

M.tap = nil
local swallowed = {}

local function handle_event(ev)
    if not is_inkscape_frontmost() then
        return false
    end

    local t = ev:getType()
    local keycode = ev:getKeyCode()
    local t_keycode = hs.keycodes.map[M.config.label_shortcut.key]

    if keycode ~= t_keycode then
        return false
    end

    if t == hs.eventtap.event.types.keyUp then
        if swallowed[keycode] then
            swallowed[keycode] = nil
            return true
        end
        return false
    end

    if swallowed[keycode] then
        return true
    end

    local flags = ev:getFlags()
    local is_shift_t = flags.shift
        and not flags.cmd
        and not flags.ctrl
        and not flags.alt

    if not is_shift_t then
        -- Ordinary t (and every other modified T) passes through unchanged.
        return false
    end

    -- Do not steal Shift+T from normal native text fields/dialog fields. Note
    -- that Inkscape canvas text editing is not always exposed as AXTextField;
    -- if uppercase T in canvas text becomes important, use M.edit() from a
    -- non-letter hotkey instead.
    if focused_ui_is_text_input() then
        return false
    end

    swallowed[keycode] = true
    start_editor_with_selection_capture()
    return true
end

function M.start()
    if M.tap then
        M.tap:stop()
    end

    M.tap = hs.eventtap.new(
        {
            hs.eventtap.event.types.keyDown,
            hs.eventtap.event.types.keyUp,
        },
        handle_event
    )

    M.tap:start()
    print("[inkscape_latex] started")
    return M
end

function M.stop()
    if M.tap then
        M.tap:stop()
        M.tap = nil
    end
end

function M.edit()
    start_editor_with_selection_capture()
end

return M
