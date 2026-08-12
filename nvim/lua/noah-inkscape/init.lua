local M = {}

-- -------------------------------------------------------------------------
-- Repository / project paths
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

local function get_project_root()
    local vimtex = vim.b.vimtex

    if type(vimtex) ~= "table"
        or type(vimtex.root) ~= "string"
        or vimtex.root == ""
    then
        return nil
    end

    return vimtex.root
end

-- -------------------------------------------------------------------------
-- LaTeX generation
-- -------------------------------------------------------------------------

local function figure_label(name)
    -- beam_fbd -> beam-fbd
    return "fig:" .. name:gsub("_", "-")
end

local function figure_lines(name, caption)
    local has_caption =
        caption ~= nil
        and vim.trim(caption) ~= ""

    local incfig =
        "    \\incfig[1]{" .. name .. "}"

    if has_caption then
        incfig = incfig .. "[" .. caption .. "]"
    end

    local lines = {
        "\\begin{figure}[ht]",
        "    \\centering",
        incfig,
    }

    if has_caption then
        table.insert(
            lines,
            "    \\label{" .. figure_label(name) .. "}"
        )
    end

    table.insert(lines, "\\end{figure}")

    return lines
end

local function capture_insert_position()
    local bufnr = vim.api.nvim_get_current_buf()
    local row = vim.api.nvim_win_get_cursor(0)[1] - 1

    local current_line =
        vim.api.nvim_buf_get_lines(
            bufnr,
            row,
            row + 1,
            false
        )[1] or ""

    return {
        bufnr = bufnr,
        row = row,
        replace_blank = current_line:match("^%s*$") ~= nil,
    }
end

local function insert_figure(position, name, caption)
    if not vim.api.nvim_buf_is_valid(position.bufnr) then
        vim.notify(
            "Figure created, but original buffer no longer exists",
            vim.log.levels.WARN
        )
        return
    end

    local lines = figure_lines(name, caption)

    local start_row
    local end_row

    if position.replace_blank then
        -- Replace the blank line under the cursor.
        start_row = position.row
        end_row = position.row + 1
    else
        -- Otherwise insert immediately after the current line.
        start_row = position.row + 1
        end_row = position.row + 1
    end

    vim.api.nvim_buf_set_lines(
        position.bufnr,
        start_row,
        end_row,
        false,
        lines
    )
end

-- -------------------------------------------------------------------------
-- Figure opening
-- -------------------------------------------------------------------------

local function open_figure(path)
    local repo_root = get_repo_root()

    local script = vim.fs.joinpath(
        repo_root,
        "scripts",
        "open_figure"
    )

    if vim.fn.executable(script) ~= 1 then
        vim.notify(
            "Figure: open_figure is not executable:\n" .. script,
            vim.log.levels.ERROR
        )
        return
    end

    vim.system(
        {
            script,
            path,
        },
        {
            text = true,
        },
        function(result)
            if result.code ~= 0 then
                vim.schedule(function()
                    local message = result.stderr

                    if not message or message == "" then
                        message = result.stdout
                    end

                    if not message or message == "" then
                        message = "Unknown error"
                    end

                    vim.notify(
                        "Could not open figure:\n" .. message,
                        vim.log.levels.ERROR
                    )
                end)
            end
        end
    )
end

-- -------------------------------------------------------------------------
-- Figure creation
-- -------------------------------------------------------------------------

function M.new(name, caption, template_path)

    if not template_path or template_path == "" then
        vim.notify(
            "FigureNew: no template selected",
            vim.log.levels.ERROR
        )
        return
    end

    if not name or name == "" then
        return
    end

    local project_root = get_project_root()

    if not project_root then
        vim.notify(
            "FigureNew: current buffer is not part of a VimTeX project",
            vim.log.levels.ERROR
        )
        return
    end

    local repo_root = get_repo_root()

    local script = vim.fs.joinpath(
        repo_root,
        "scripts",
        "new_figure"
    )

    local figures_dir = vim.fs.joinpath(
        project_root,
        "figures"
    )

    if vim.fn.executable(script) ~= 1 then
        vim.notify(
            "FigureNew: new_figure is not executable:\n" .. script,
            vim.log.levels.ERROR
        )
        return
    end

    -- Remember where FigureNew was invoked so the LaTeX goes there,
    -- even though figure creation runs asynchronously.
    local insert_position = capture_insert_position()

    vim.system(
        {
            script,
            name,
            figures_dir,
            template_path,
        },
        {
            text = true,
            cwd = project_root,
        },
        function(result)
            vim.schedule(function()
                if result.code == 0 then
                    insert_figure(
                        insert_position,
                        name,
                        caption
                    )

                    vim.notify(
                        "Created figure: " .. name,
                        vim.log.levels.INFO
                    )
                else
                    local message = result.stderr

                    if not message or message == "" then
                        message = result.stdout
                    end

                    if not message or message == "" then
                        message = "Unknown error"
                    end

                    vim.notify(
                        "FigureNew failed:\n" .. message,
                        vim.log.levels.ERROR
                    )
                end
            end)
        end
    )
end

-- -------------------------------------------------------------------------
-- Interactive figure creation
-- -------------------------------------------------------------------------

local function prompt_caption(name, template_path)
    vim.ui.input(
        {
            prompt = "Caption (optional): ",
        },
        function(caption)
            if caption == nil then
                return
            end

            M.new(
                name,
                caption,
                template_path
            )
        end
    )
end

local function prompt_template(name)
    local repo_root = get_repo_root()

    local templates_dir = vim.fs.joinpath(
        repo_root,
        "templates"
    )

    require("noah-inkscape.telescope").pick_template({
        templates_dir = templates_dir,

        on_select = function(template_path)
            prompt_caption(
                name,
                template_path
            )
        end,
    })
end

local function prompt_new_figure()
    vim.ui.input(
        {
            prompt = "Figure name: ",
        },
        function(name)
            if not name or name == "" then
                return
            end

            prompt_template(name)
        end
    )
end

-- -------------------------------------------------------------------------
-- Unified Telescope figure picker
-- -------------------------------------------------------------------------

local function new_from_picker(name)
    if name and vim.trim(name) ~= "" then
        -- Name came from the main Telescope prompt.
        -- Go directly to template selection.
        prompt_template(name)
    else
        -- "+ New figure…" was selected.
        -- Ask for the name first.
        prompt_new_figure()
    end
end

function M.pick()
    local project_root = get_project_root()

    if not project_root then
        vim.notify(
            "Figure: current buffer is not part of a VimTeX project",
            vim.log.levels.ERROR
        )
        return
    end

    local figures_dir = vim.fs.joinpath(
        project_root,
        "figures"
    )

    require("noah-inkscape.telescope").pick({
        figures_dir = figures_dir,

        -- Existing figure selected.
        on_open = function(path)
            open_figure(path)
        end,

        -- New figure requested.
        on_new = function(name)
            new_from_picker(name)
        end,
    })
end

-- -------------------------------------------------------------------------
-- Commands
-- -------------------------------------------------------------------------

function M.setup()
    -- Main interactive entry point.
    --
    -- Opens Telescope, from which the user can either:
    --   - open an existing figure
    --   - create a new figure
    vim.api.nvim_create_user_command(
        "Figure",
        function()
            M.pick()
        end,
        {
            desc = "Open or create an Inkscape figure",
        }
    )

    -- Direct creation command retained as a useful primitive.
    --
    -- Examples:
    --
    --   :FigureNew
    --       -> asks for name + caption
    --
    --   :FigureNew beam_fbd
    --       -> creates beam_fbd without a caption
    vim.api.nvim_create_user_command(
        "FigureNew",
        function(opts)
            if opts.args ~= "" then
                prompt_template(opts.args)
            else
                prompt_new_figure()
            end
        end,
        {
            nargs = "?",
            desc = "Create and insert a new Inkscape figure",
        }
    )
end

return M
