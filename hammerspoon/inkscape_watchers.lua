local M = {}

M.config = {
    app_name = "Inkscape",
    grace_seconds = 12,
    reconcile_interval = 2.0,
}

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function state_dir()
    local tmp = os.getenv("TMPDIR") or "/tmp"
    tmp = tmp:gsub("/+$", "")
    return tmp .. "/noah-inkscape"
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

local function trim(s)
    return (tostring(s or ""):match("^%s*(.-)%s*$"))
end

local function basename(path)
    return tostring(path or ""):match("([^/]+)$") or tostring(path or "")
end

local function stem(path)
    return basename(path):gsub("%.[Ss][Vv][Gg]$", "")
end

local function process_alive(pid)
    if not tostring(pid):match("^%d+$") then
        return false
    end
    local _, ok = hs.execute("/bin/kill -0 " .. tostring(pid) .. " 2>/dev/null", false)
    return ok == true
end

local function terminate(pid)
    if not tostring(pid):match("^%d+$") then
        return
    end
    hs.execute("/bin/kill -TERM " .. tostring(pid) .. " 2>/dev/null", false)
end

local function touch(path)
    hs.execute("/usr/bin/touch " .. shell_quote(path), false)
end

local function watcher_records()
    local dir = state_dir()
    local attrs = hs.fs.attributes(dir)
    if not attrs or attrs.mode ~= "directory" then
        return {}
    end

    local records = {}

    for name in hs.fs.dir(dir) do
        local key = name:match("^(.*)%.pid$")
        if key then
            local pid_path = dir .. "/" .. key .. ".pid"
            local path_path = dir .. "/" .. key .. ".path"
            local seen_path = dir .. "/" .. key .. ".seen"
            local pid = trim(read_file(pid_path))
            local svg = trim(read_file(path_path))
            local pid_attrs = hs.fs.attributes(pid_path)

            if pid ~= "" and svg ~= "" and process_alive(pid) then
                table.insert(records, {
                    key = key,
                    pid = pid,
                    svg = svg,
                    pid_path = pid_path,
                    path_path = path_path,
                    seen_path = seen_path,
                    started = pid_attrs and pid_attrs.modification or hs.timer.secondsSinceEpoch(),
                    seen = hs.fs.attributes(seen_path) ~= nil,
                })
            else
                os.remove(pid_path)
                os.remove(path_path)
                os.remove(seen_path)
            end
        end
    end

    return records
end

local function open_window_titles()
    if not M.filter then
        return {}
    end

    local titles = {}
    for _, win in ipairs(M.filter:getWindows() or {}) do
        local title = win:title()
        if title and title ~= "" then
            table.insert(titles, title:lower())
        end
    end
    return titles
end

local function title_matches_path(title, svg)
    local file = basename(svg):lower()
    local file_stem = stem(svg):lower()

    if title:find(file, 1, true) then
        return true
    end

    -- Some Inkscape/macOS title variants omit the extension.
    if file_stem ~= "" and title:find(file_stem, 1, true) then
        return true
    end

    return false
end

local function is_open(svg, titles)
    for _, title in ipairs(titles) do
        if title_matches_path(title, svg) then
            return true
        end
    end
    return false
end

function M.reconcile()
    local now = hs.timer.secondsSinceEpoch()
    local titles = open_window_titles()

    for _, record in ipairs(watcher_records()) do
        if is_open(record.svg, titles) then
            if not record.seen then
                touch(record.seen_path)
            end
        else
            local age = now - (record.started or now)

            -- Once a matching document window has been seen, disappearance means
            -- the document was closed. Before first sighting, allow a short grace
            -- period for Inkscape to finish opening the document.
            if record.seen or age >= M.config.grace_seconds then
                terminate(record.pid)
            end
        end
    end
end

local function schedule_reconcile(delay)
    if M.pending then
        M.pending:stop()
    end
    M.pending = hs.timer.doAfter(delay or 0.15, function()
        M.pending = nil
        M.reconcile()
    end)
end

function M.start()
    if M.started then
        return M
    end

    local wf = hs.window.filter
    M.filter = wf.new({ [M.config.app_name] = {} })

    M.filter:subscribe({
        wf.windowCreated,
        wf.windowDestroyed,
        wf.windowTitleChanged,
        wf.windowsChanged,
    }, function()
        schedule_reconcile(0.18)
    end)

    M.timer = hs.timer.doEvery(M.config.reconcile_interval, function()
        M.reconcile()
    end)

    M.started = true
    schedule_reconcile(0.3)
    print("[inkscape_watchers] started")
    return M
end

function M.stop()
    if M.pending then
        M.pending:stop()
        M.pending = nil
    end

    if M.timer then
        M.timer:stop()
        M.timer = nil
    end

    if M.filter then
        M.filter:unsubscribeAll()
        M.filter = nil
    end

    M.started = false
end

return M
