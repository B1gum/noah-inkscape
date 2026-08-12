local M = {}

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local conf = require("telescope.config").values
local previewers = require("telescope.previewers")

-- -------------------------------------------------------------------------
-- Helpers
-- -------------------------------------------------------------------------


local function get_repo_root()
    local source = debug.getinfo(1, "S").source:sub(2)
    -- Resolve a ~/.config/nvim symlink back to the real repository before
    -- deriving scripts/templates relative to this module.
    source = (vim.uv and vim.uv.fs_realpath(source))
        or (vim.loop and vim.loop.fs_realpath(source))
        or source
    local module_dir = vim.fs.dirname(source)

    return vim.fs.dirname(
        vim.fs.dirname(
            vim.fs.dirname(module_dir)
        )
    )
end

local function svg_previewer()
    local preview_script = vim.fs.joinpath(
        get_repo_root(),
        "scripts",
        "preview_svg"
    )

    return previewers.new_termopen_previewer({
        get_command = function(entry)
            local item = entry and entry.value or nil
            local path = item and item.path or nil

            if not path or path == "" then
                return {
                    "/usr/bin/printf",
                    "%s\n",
                    "Type a name or select + New figure…",
                }
            end

            return { preview_script, path }
        end,
    })
end

local function relative_path(root, path)
    local prefix = root

    if prefix:sub(-1) ~= "/" then
        prefix = prefix .. "/"
    end

    if path:sub(1, #prefix) == prefix then
        return path:sub(#prefix + 1)
    end

    return vim.fn.fnamemodify(path, ":t")
end

-- -------------------------------------------------------------------------
-- Existing/new figure picker
-- -------------------------------------------------------------------------

local function figure_items(figures_dir)
    local paths = vim.fn.globpath(
        figures_dir,
        "**/*.svg",
        false,
        true
    )

    table.sort(paths)

    local items = {
        {
            kind = "new",
            display = "+ New figure…",
            ordinal = "new figure create",
        },
    }

    for _, path in ipairs(paths) do
        local relative = relative_path(figures_dir, path)

        local display = relative:gsub("%.svg$", "")

        table.insert(items, {
            kind = "figure",
            path = path,
            display = display,
            ordinal = display,
        })
    end

    return items
end

function M.pick(opts)
    opts = opts or {}

    local figures_dir = assert(
        opts.figures_dir,
        "figures_dir is required"
    )

    local on_open = assert(
        opts.on_open,
        "on_open callback is required"
    )

    local on_new = assert(
        opts.on_new,
        "on_new callback is required"
    )

    vim.fn.mkdir(figures_dir, "p")

    local items = figure_items(figures_dir)

    pickers.new(opts, {
        prompt_title = "Figures  <CR>: open  <C-n>: new",

        finder = finders.new_table({
            results = items,

            entry_maker = function(item)
                return {
                    value = item,
                    display = item.display,
                    ordinal = item.ordinal,
                }
            end,
        }),

        sorter = conf.generic_sorter(opts),

        previewer = svg_previewer(),

        attach_mappings = function(prompt_bufnr, map)

            local function create_from_prompt()
                local name = vim.trim(
                    action_state.get_current_line() or ""
                )

                actions.close(prompt_bufnr)

                vim.schedule(function()
                    if name == "" then
                        on_new(nil)
                    else
                        on_new(name)
                    end
                end)
            end

            map("i", "<C-n>", create_from_prompt)
            map("n", "<C-n>", create_from_prompt)

            actions.select_default:replace(function()
                local selection =
                    action_state.get_selected_entry()

                local prompt =
                    vim.trim(
                        action_state.get_current_line() or ""
                    )

                actions.close(prompt_bufnr)

                vim.schedule(function()
                    if selection then
                        local item = selection.value

                        if item.kind == "new" then
                            on_new(nil)

                        elseif item.kind == "figure" then
                            on_open(item.path)
                        end

                        return
                    end

                    if prompt ~= "" then
                        on_new(prompt)
                    end
                end)
            end)

            return true
        end,
    }):find()
end

-- -------------------------------------------------------------------------
-- Template picker
-- -------------------------------------------------------------------------

local function template_items(templates_dir)
    local paths = vim.fn.globpath(
        templates_dir,
        "**/*.svg",
        false,
        true
    )

    table.sort(paths)

    local items = {}

    for _, path in ipairs(paths) do
        local relative = relative_path(
            templates_dir,
            path
        )

        local display =
            relative:gsub("%.svg$", "")

        table.insert(items, {
            path = path,
            display = display,
            ordinal = display,
        })
    end

    return items
end

function M.pick_template(opts)
    opts = opts or {}

    local templates_dir = assert(
        opts.templates_dir,
        "templates_dir is required"
    )

    local on_select = assert(
        opts.on_select,
        "on_select callback is required"
    )

    local items = template_items(templates_dir)

    if #items == 0 then
        vim.notify(
            "No SVG templates found in:\n"
                .. templates_dir,
            vim.log.levels.ERROR
        )
        return
    end

    pickers.new(opts, {
        prompt_title = "Figure template",

        finder = finders.new_table({
            results = items,

            entry_maker = function(item)
                return {
                    value = item,
                    display = item.display,
                    ordinal = item.ordinal,
                    path = item.path,
                }
            end,
        }),

        sorter = conf.generic_sorter(opts),

        -- Render the SVG and show a terminal-cell thumbnail via chafa.
        previewer = svg_previewer(),

        attach_mappings = function(prompt_bufnr)
            actions.select_default:replace(function()
                local selection =
                    action_state.get_selected_entry()

                if not selection then
                    return
                end

                local template =
                    selection.value

                actions.close(prompt_bufnr)

                vim.schedule(function()
                    on_select(template.path)
                end)
            end)

            return true
        end,
    }):find()
end

return M
