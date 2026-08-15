local M = {}

------------------------------------------------------------------------
-- Config
------------------------------------------------------------------------

M.config = {
    inkscape_app_name = "Inkscape",
    inkscape_mime = "image/x-inkscape-svg",

    -- Shift+S is handled by inkscape_styles.lua as an Inkscape-wide shortcut;
    -- it works whether or not the bare-key style mode is enabled.
    shortcut_key = "s",

    chooser_rows = 14,
    chooser_width = 56,

    -- hs.chooser itself uses a fixed row height, so its inline image well is
    -- inherently small. These values control the compact row icon and the
    -- much larger live preview panel shown beside the chooser.
    thumbnail_size = 96,
    thumbnail_render_size = 1024,
    preview_width_fraction = 0.30,
    preview_max_width = 460,
    preview_gap = 18,
    preview_poll_interval = 0.08,

    paste_menu = { "Edit", "Paste" },
    copy_menu = { "Edit", "Copy" },
}

------------------------------------------------------------------------
-- Repository paths
------------------------------------------------------------------------

local function dirname(path)
    return path and path:match("^(.*)/[^/]+$") or nil
end

local function module_path()
    local source = debug.getinfo(1, "S").source
    if source:sub(1, 1) == "@" then
        source = source:sub(2)
    end

    -- Important for Noah's setup: the Hammerspoon module can be symlinked
    -- into ~/.hammerspoon. pathToAbsolute resolves the symlink back to the
    -- real repository file before we derive repo_root.
    return hs.fs.pathToAbsolute(source) or source
end

local MODULE_PATH = module_path()
local HAMMERSPOON_DIR = dirname(MODULE_PATH)
local REPO_ROOT = dirname(HAMMERSPOON_DIR)

M.config.repo_root = REPO_ROOT
M.config.symbols_dir = REPO_ROOT .. "/symbols"
M.config.symbol_sources_dir = M.config.symbols_dir .. "/_sources"
M.config.symbol_template = REPO_ROOT .. "/templates/noah-symbol-sheet.svg"

------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------

local function trim(s)
    return (tostring(s or ""):match("^%s*(.-)%s*$"))
end

local function read_file(path)
    local f, err = io.open(path, "rb")
    if not f then
        return nil, err
    end

    local data = f:read("*a")
    f:close()
    return data
end

local function write_file(path, data)
    local f, err = io.open(path, "wb")
    if not f then
        return nil, err
    end

    f:write(data)
    f:close()
    return true
end

local function copy_file(source, destination)
    local data, err = read_file(source)
    if not data then
        return nil, err
    end
    return write_file(destination, data)
end

local function file_exists(path)
    return hs.fs.attributes(path) ~= nil
end

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function ensure_directory(path)
    local _, status = hs.execute(
        "/bin/mkdir -p " .. shell_quote(path),
        false
    )
    return status == true
end

local function restore_clipboard(saved)
    if type(saved) ~= "table" then
        return
    end

    hs.timer.doAfter(0.18, function()
        hs.pasteboard.writeAllData(saved)
    end)
end

local function humanize(name)
    name = name:gsub("%.svg$", "")
    name = name:gsub("[_%-]+", " ")
    return name
end

local function relative_path(root, path)
    local prefix = root
    if prefix:sub(-1) ~= "/" then
        prefix = prefix .. "/"
    end

    if path:sub(1, #prefix) == prefix then
        return path:sub(#prefix + 1)
    end

    return path
end

local function parent_category(relative)
    local dir = dirname(relative)
    if not dir or dir == "" then
        return "symbols"
    end
    return dir
end

local function is_svg_file(path)
    return path:lower():match("%.svg$") ~= nil
end

local function is_hidden_symbol_path(root, path)
    local relative = relative_path(root, path)
    for component in relative:gmatch("[^/]+") do
        if component:match("^[._]") then
            return true
        end
    end
    return false
end

local function rendered_symbol_image(path)
    -- Always render a tightly-cropped PNG for chooser use. Loading the SVG
    -- directly makes NSImage preserve the SVG page/viewBox, which leaves lots
    -- of empty space around these technical symbols and makes them look tiny.
    -- The renderer uses drawing bounds, a small margin, and a light background
    -- so black technical strokes remain crisp in Hammerspoon's dark chooser.
    local cache_dir = (os.getenv("TMPDIR") or "/tmp"):gsub("/+$", "")
        .. "/noah-inkscape/symbol-thumbnails-v2"
    ensure_directory(cache_dir)

    local relative = relative_path(M.config.symbols_dir, path)
    local cache_name = relative:gsub("[^%w%._%-]", "_"):gsub("%.svg$", ".png")
    local thumb = cache_dir .. "/" .. cache_name
    local source_attrs = hs.fs.attributes(path)
    local thumb_attrs = hs.fs.attributes(thumb)
    local stale = not thumb_attrs
        or (source_attrs and source_attrs.modification > thumb_attrs.modification)

    if stale then
        local renderer = M.config.repo_root .. "/scripts/render_thumbnail"
        local command = shell_quote(renderer)
            .. " " .. shell_quote(path)
            .. " " .. shell_quote(thumb)
            .. " " .. tostring(M.config.thumbnail_render_size)
            .. " chooser >/dev/null 2>&1"
        hs.execute(command, false)
    end

    return hs.image.imageFromPath(thumb)
end

local function symbol_thumbnail(path)
    local image = rendered_symbol_image(path)
    if not image then
        return nil
    end

    return image:size({
        w = M.config.thumbnail_size,
        h = M.config.thumbnail_size,
    }, false)
end

------------------------------------------------------------------------
-- Symbol discovery
------------------------------------------------------------------------

local function discover_symbols()
    ensure_directory(M.config.symbols_dir)

    local files = hs.fs.fileListForPath(M.config.symbols_dir, {
        subdirs = true,
        followSymlinks = true,
        relativePath = false,
    }) or {}

    local symbols = {}

    for _, path in ipairs(files) do
        if is_svg_file(path) and not is_hidden_symbol_path(M.config.symbols_dir, path) then
            local relative = relative_path(M.config.symbols_dir, path)
            local basename = relative:match("([^/]+)$") or relative
            local display = humanize(basename)
            local category = parent_category(relative)

            table.insert(symbols, {
                kind = "symbol",
                path = path,
                relative = relative,
                text = display,
                subText = category .. "   ↵ insert   ⇧↵ source",
                searchText = display .. " " .. relative .. " " .. category,
                image = symbol_thumbnail(path),
            })
        end
    end

    table.sort(symbols, function(a, b)
        return a.relative:lower() < b.relative:lower()
    end)

    return symbols
end

local function all_choices()
    local choices = {
        {
            kind = "new_symbol",
            text = "＋ New symbol from selection…",
            subText = "Save the current Inkscape selection into symbols/",
            searchText = "new symbol create save selection",
        },
        {
            kind = "new_symbol_sheet",
            text = "＋ New symbol sheet…",
            subText = "Create a symbol workspace from noah-symbol-sheet.svg",
            searchText = "new symbol sheet template workspace draw",
        },
        {
            kind = "open_folder",
            text = "＋ Open symbols folder…",
            subText = M.config.symbols_dir,
            searchText = "open symbols folder finder",
        },
    }

    for _, symbol in ipairs(discover_symbols()) do
        table.insert(choices, symbol)
    end

    return choices
end

------------------------------------------------------------------------
-- Fuzzy matching
------------------------------------------------------------------------

-- Small subsequence scorer tailored to a 10–100 item personal symbol library.
-- Examples that match:
--   spr -> spring
--   spg -> spring
--   dmp -> damper
--   sup fix -> supports/fixed_support.svg
local function fuzzy_token_score(token, candidate)
    token = token:lower()
    candidate = candidate:lower()

    if token == "" then
        return 0
    end

    local score = 0
    local last_pos = 0

    for i = 1, #token do
        local ch = token:sub(i, i)
        local pos = candidate:find(ch, last_pos + 1, true)

        if not pos then
            return nil
        end

        score = score + 10

        -- Strongly reward consecutive runs.
        if last_pos > 0 and pos == last_pos + 1 then
            score = score + 18
        end

        -- Reward word/path starts.
        if pos == 1 then
            score = score + 12
        else
            local prev = candidate:sub(pos - 1, pos - 1)
            if prev:match("[%s_/%-]") then
                score = score + 10
            end
        end

        -- Earlier matches are generally better.
        score = score - (pos * 0.08)
        last_pos = pos
    end

    -- Slight preference for shorter candidates when scores otherwise tie.
    score = score - (#candidate * 0.01)
    return score
end

local function fuzzy_score(query, candidate)
    query = trim(query):lower()
    candidate = tostring(candidate or ""):lower()

    if query == "" then
        return 0
    end

    local total = 0
    local token_count = 0

    for token in query:gmatch("%S+") do
        local score = fuzzy_token_score(token, candidate)
        if not score then
            return nil
        end

        total = total + score
        token_count = token_count + 1
    end

    if token_count == 0 then
        return 0
    end

    return total
end

local function filtered_choices(choices, query)
    query = trim(query)

    if query == "" then
        return choices
    end

    local scored = {}

    for index, choice in ipairs(choices) do
        local score = fuzzy_score(query, choice.searchText or choice.text)
        if score then
            table.insert(scored, {
                choice = choice,
                score = score,
                index = index,
            })
        end
    end

    table.sort(scored, function(a, b)
        if a.score == b.score then
            return a.index < b.index
        end
        return a.score > b.score
    end)

    local result = {}
    for _, item in ipairs(scored) do
        table.insert(result, item.choice)
    end

    return result
end

------------------------------------------------------------------------
-- Insert an SVG symbol into Inkscape
------------------------------------------------------------------------

local function insert_symbol(path, app)
    local svg, err = read_file(path)
    if not svg then
        hs.alert.show("Could not read symbol: " .. tostring(err))
        return
    end

    if not svg:find("<svg", 1, true) then
        hs.alert.show("Symbol is not an SVG document")
        return
    end

    local saved_clipboard = hs.pasteboard.readAllData()

    if app then
        app:activate(true)
    end

    -- Give the chooser time to disappear and Inkscape time to regain focus.
    hs.timer.doAfter(0.04, function()
        local ok = hs.pasteboard.writeDataForUTI(
            M.config.inkscape_mime,
            svg
        )

        if not ok then
            hs.alert.show("Could not put symbol on Inkscape clipboard")
            restore_clipboard(saved_clipboard)
            return
        end

        hs.timer.doAfter(0.03, function()
            local pasted = app and app:selectMenuItem(M.config.paste_menu)

            if not pasted then
                hs.alert.show("Could not invoke Inkscape Paste")
            end

            restore_clipboard(saved_clipboard)
        end)
    end)
end

------------------------------------------------------------------------
-- Create a reusable symbol from the current Inkscape selection
------------------------------------------------------------------------

local function normalize_symbol_name(input)
    input = trim(input):lower()
    input = input:gsub("%.svg$", "")
    input = input:gsub("%s+", "_")
    input = input:gsub("/+", "/")
    input = input:gsub("^/", ""):gsub("/$", "")

    if input == "" then
        return nil, "Name cannot be empty"
    end

    if input:find("..", 1, true) then
        return nil, "'..' is not allowed in a symbol path"
    end

    for component in input:gmatch("[^/]+") do
        if not component:match("^[a-z0-9][a-z0-9_-]*$") then
            return nil,
                "Use letters, numbers, _ and -; optionally use / for a category\n"
                .. "Example: dynamics/spring"
        end
    end

    return input .. ".svg"
end

local function create_symbol_from_selection(app)
    local button, input = hs.dialog.textPrompt(
        "New Inkscape symbol",
        "Name it. You can include a category, e.g. dynamics/spring",
        "",
        "Save",
        "Cancel"
    )

    if button ~= "Save" then
        return
    end

    local relative, name_err = normalize_symbol_name(input)
    if not relative then
        hs.alert.show(name_err)
        return
    end

    local destination = M.config.symbols_dir .. "/" .. relative
    local parent = dirname(destination)

    if file_exists(destination) then
        hs.alert.show("Symbol already exists: " .. relative)
        return
    end

    if not ensure_directory(parent) then
        hs.alert.show("Could not create symbol directory")
        return
    end

    local saved_clipboard = hs.pasteboard.readAllData()
    local before = hs.pasteboard.changeCount()

    if app then
        app:activate(true)
    end

    local copied = app and app:selectMenuItem(M.config.copy_menu)
    if not copied then
        hs.alert.show("Could not invoke Inkscape Copy")
        return
    end

    hs.timer.doAfter(0.07, function()
        if hs.pasteboard.changeCount() == before then
            hs.alert.show("Nothing was copied — select the symbol geometry first")
            restore_clipboard(saved_clipboard)
            return
        end

        local svg = hs.pasteboard.readDataForUTI(M.config.inkscape_mime)

        if not svg or not svg:find("<svg", 1, true) then
            hs.alert.show("Selection did not produce Inkscape SVG clipboard data")
            restore_clipboard(saved_clipboard)
            return
        end

        local ok, err = write_file(destination, svg)
        restore_clipboard(saved_clipboard)

        if not ok then
            hs.alert.show("Could not save symbol: " .. tostring(err))
            return
        end

        hs.alert.show("Saved symbol: " .. relative)
    end)
end

------------------------------------------------------------------------
-- Create a new symbol workspace from the symbol-sheet template
------------------------------------------------------------------------

local function open_svg_in_inkscape(path, app)
    local opener = M.config.repo_root .. "/scripts/open_figure"
    local command = shell_quote(opener) .. " " .. shell_quote(path) .. " >/dev/null 2>&1 &"

    if app then
        app:activate(true)
    end

    hs.execute(command, false)
end

local function create_symbol_sheet(app)
    local button, input = hs.dialog.textPrompt(
        "New symbol sheet",
        "Name it. You can include a category, e.g. dynamics/spring",
        "",
        "Create",
        "Cancel"
    )

    if button ~= "Create" then
        return
    end

    local relative, name_err = normalize_symbol_name(input)
    if not relative then
        hs.alert.show(name_err)
        return
    end

    if not file_exists(M.config.symbol_template) then
        hs.alert.show("Symbol template not found")
        return
    end

    local destination = M.config.symbol_sources_dir .. "/" .. relative
    local parent = dirname(destination)

    if file_exists(destination) then
        hs.alert.show("Symbol sheet already exists: " .. relative)
        open_svg_in_inkscape(destination, app)
        return
    end

    if not ensure_directory(parent) then
        hs.alert.show("Could not create symbol-sheet directory")
        return
    end

    local ok, err = copy_file(M.config.symbol_template, destination)
    if not ok then
        hs.alert.show("Could not create symbol sheet: " .. tostring(err))
        return
    end

    hs.alert.show("Created symbol sheet: _sources/" .. relative)
    open_svg_in_inkscape(destination, app)
end

local function open_symbol_source(choice, app)
    if not choice or choice.kind ~= "symbol" then
        hs.alert.show("Shift+Enter is available for saved symbols")
        return
    end

    local source = M.config.symbol_sources_dir .. "/" .. choice.relative

    if file_exists(source) then
        open_svg_in_inkscape(source, app)
        return
    end

    -- Older/library-only symbols may not have a workbench sheet. They are still
    -- editable SVGs, so opening the clean library file is a safe fallback.
    hs.alert.show("No source sheet yet — opening the library SVG")
    open_svg_in_inkscape(choice.path, app)
end

------------------------------------------------------------------------
-- Large live symbol preview
------------------------------------------------------------------------

M._preview_canvas = nil
M._preview_timer = nil
M._preview_key = nil
M._preview_frame = nil

local function destroy_preview()
    if M._preview_timer then
        M._preview_timer:stop()
        M._preview_timer = nil
    end

    if M._preview_canvas then
        M._preview_canvas:delete()
        M._preview_canvas = nil
    end

    M._preview_key = nil
    M._preview_frame = nil
end

local function chooser_layout()
    local focused = hs.window.focusedWindow()
    local screen = focused and focused:screen() or hs.screen.mainScreen()
    local frame = screen:frame()

    local chooser_w = frame.w * (M.config.chooser_width / 100)
    local preview_w = math.min(M.config.preview_max_width, frame.w * M.config.preview_width_fraction)
    local gap = M.config.preview_gap
    local total_w = chooser_w + gap + preview_w
    local left = frame.x + math.max(12, (frame.w - total_w) / 2)
    local top = frame.y + math.max(20, frame.h * 0.07)
    local preview_h = math.min(preview_w + 96, frame.h * 0.62)

    return {
        chooser = { x = left, y = top },
        preview = {
            x = left + chooser_w + gap,
            y = top,
            w = preview_w,
            h = preview_h,
        },
    }
end

local function make_preview_canvas(frame)
    local padding = 22
    local footer_h = 74
    local image_h = frame.h - footer_h - (padding * 2)

    local canvas = hs.canvas.new(frame)
    canvas[1] = {
        type = "rectangle",
        action = "strokeAndFill",
        fillColor = { white = 0.97, alpha = 0.98 },
        strokeColor = { white = 0.72, alpha = 0.8 },
        strokeWidth = 1,
        roundedRectRadii = { xRadius = 12, yRadius = 12 },
        withShadow = true,
        shadow = {
            blurRadius = 16,
            color = { white = 0, alpha = 0.28 },
            offset = { h = 3, w = 0 },
        },
    }
    canvas[2] = {
        id = "previewImage",
        type = "image",
        action = "skip",
        frame = { x = padding, y = padding, w = frame.w - 2 * padding, h = image_h },
        imageScaling = "scaleProportionally",
        imageAlignment = "center",
    }
    canvas[3] = {
        id = "previewTitle",
        type = "text",
        text = "Select a symbol",
        frame = { x = padding, y = frame.h - footer_h, w = frame.w - 2 * padding, h = 30 },
        textColor = { white = 0.10, alpha = 1 },
        textSize = 19,
        textLineBreak = "truncateTail",
    }
    canvas[4] = {
        id = "previewSubtext",
        type = "text",
        text = "↑/↓ to preview · Enter inserts · Shift+Enter opens source",
        frame = { x = padding, y = frame.h - footer_h + 31, w = frame.w - 2 * padding, h = 35 },
        textColor = { white = 0.38, alpha = 1 },
        textSize = 12,
        textLineBreak = "wordWrap",
    }

    canvas:show():bringToFront(false)
    return canvas
end

local function update_preview()
    if not M.chooser or not M.chooser:isVisible() or not M._preview_canvas then
        return
    end

    local choice = M.chooser:selectedRowContents()
    if not choice or next(choice) == nil then
        return
    end

    local key = tostring(choice.kind or "") .. "|" .. tostring(choice.relative or choice.text or "")
    if key == M._preview_key then
        return
    end
    M._preview_key = key

    if choice.kind == "symbol" and choice.path then
        local image = rendered_symbol_image(choice.path)
        if image then
            M._preview_canvas.previewImage.image = image
            M._preview_canvas.previewImage.action = "fill"
        else
            M._preview_canvas.previewImage.action = "skip"
        end
        M._preview_canvas.previewTitle.text = choice.text or "Symbol"
        M._preview_canvas.previewSubtext.text = (choice.subText or "symbols")
            .. "   ·   Enter inserts   ·   Shift+Enter opens source"
    else
        M._preview_canvas.previewImage.action = "skip"
        M._preview_canvas.previewTitle.text = choice.text or "Symbol action"
        M._preview_canvas.previewSubtext.text = choice.subText or ""
    end
end

local function start_preview()
    if not M._preview_frame then
        return
    end

    if M._preview_canvas then
        M._preview_canvas:delete()
    end
    M._preview_canvas = make_preview_canvas(M._preview_frame)
    M._preview_key = nil
    update_preview()

    if M._preview_timer then
        M._preview_timer:stop()
    end
    M._preview_timer = hs.timer.doEvery(M.config.preview_poll_interval, update_preview)
end

------------------------------------------------------------------------
-- Chooser
------------------------------------------------------------------------

M.chooser = nil
M._source_app = nil
M._choices = nil
M._source_hotkeys = nil

local function disable_source_hotkeys()
    if not M._source_hotkeys then
        return
    end

    for _, hotkey in ipairs(M._source_hotkeys) do
        hotkey:disable()
    end
end

local function open_selected_source()
    if not M.chooser or not M.chooser:isVisible() then
        return
    end

    local choice = M.chooser:selectedRowContents()
    if not choice or next(choice) == nil then
        return
    end

    local app = M._source_app
    M.chooser:hide()

    -- Let the chooser disappear before bringing Inkscape forward again.
    hs.timer.doAfter(0.04, function()
        open_symbol_source(choice, app)
    end)
end

local function ensure_source_hotkeys()
    if M._source_hotkeys then
        return
    end

    M._source_hotkeys = {}

    for _, key in ipairs({ "return", "padenter" }) do
        local hotkey = hs.hotkey.new({ "shift" }, key, open_selected_source)
        if hotkey then
            table.insert(M._source_hotkeys, hotkey)
        end
    end
end

local function enable_source_hotkeys()
    ensure_source_hotkeys()
    for _, hotkey in ipairs(M._source_hotkeys) do
        hotkey:enable()
    end
end

local function handle_choice(choice)
    if not choice then
        return
    end

    local app = M._source_app

    if choice.kind == "symbol" then
        insert_symbol(choice.path, app)
    elseif choice.kind == "new_symbol" then
        create_symbol_from_selection(app)
    elseif choice.kind == "new_symbol_sheet" then
        create_symbol_sheet(app)
    elseif choice.kind == "open_folder" then
        hs.open(M.config.symbols_dir)
    end
end

function M.show()
    local app = hs.application.frontmostApplication()

    if not app or app:name() ~= M.config.inkscape_app_name then
        return
    end

    M._source_app = app
    M._choices = all_choices()

    if M.chooser then
        disable_source_hotkeys()
        destroy_preview()
        M.chooser:delete()
        M.chooser = nil
    end

    local layout = chooser_layout()
    M._preview_frame = layout.preview

    local chooser
    chooser = hs.chooser.new(handle_choice)
        :placeholderText("Search symbols…  Enter inserts · Shift+Enter opens source")
        :rows(M.config.chooser_rows)
        :width(M.config.chooser_width)

    chooser:showCallback(function()
        enable_source_hotkeys()
        start_preview()
    end)
    chooser:hideCallback(function()
        disable_source_hotkeys()
        destroy_preview()
    end)

    -- Supplying queryChangedCallback disables hs.chooser's normal substring
    -- filtering and lets us supply fuzzy-ranked results ourselves.
    chooser:queryChangedCallback(function(query)
        local results = filtered_choices(M._choices, query)
        chooser:choices(results)

        if #results > 0 then
            chooser:selectedRow(1)
        end
    end)

    chooser:choices(M._choices)
    chooser:selectedRow(1)

    M.chooser = chooser
    chooser:show(layout.chooser)
end

function M.refresh()
    M._choices = all_choices()

    if M.chooser and M.chooser:isVisible() then
        local query = M.chooser:query() or ""
        local results = filtered_choices(M._choices, query)
        M.chooser:choices(results)
        if #results > 0 then
            M.chooser:selectedRow(1)
        end
    end
end

return M
