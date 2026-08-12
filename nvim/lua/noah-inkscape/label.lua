local M = {}

local function place_cursor_for_label()
    local line = vim.api.nvim_get_current_line()

    if line == "$$" then
        -- Cursor on the closing $, then enter Insert before it.
        vim.api.nvim_win_set_cursor(0, { 1, 1 })
        return
    end

    if #line > 0 and line:sub(-1) == "$" then
        vim.api.nvim_win_set_cursor(0, { 1, #line - 1 })
    else
        vim.api.nvim_win_set_cursor(0, { 1, #line })
    end
end

local function save_and_quit()
    vim.cmd("write")
    vim.cmd("quit")
end

local function cancel()
    -- :cquit gives the Hammerspoon wrapper a non-zero exit status, so it can
    -- distinguish a deliberate cancel from a saved label.
    vim.cmd("cquit")
end

function M.setup()
    vim.g.noah_inkscape_label_popup = true

    -- The filename is .tex already, but setting this explicitly makes the
    -- intent robust and causes VimTeX's TeX syntax/context helpers to load.
    vim.bo.filetype = "tex"

    -- Load LuaSnip immediately rather than waiting for the normal VeryLazy
    -- event. This still uses the user's ordinary LuaSnip configuration and
    -- snippets; it only removes startup timing from the popup experience.
    pcall(require, "luasnip")

    -- Strip the full editor UI down to a tiny focused scratch-editor feel.
    vim.opt_local.number = false
    vim.opt_local.relativenumber = false
    vim.opt_local.signcolumn = "no"
    vim.opt_local.foldcolumn = "0"
    vim.opt_local.statuscolumn = ""
    vim.opt_local.wrap = false
    vim.opt_local.spell = false
    vim.opt_local.conceallevel = 0

    vim.opt.laststatus = 0
    vim.opt.showtabline = 0

    -- A small winbar gives the popup a purpose label without needing iTerm2
    -- chrome. It also reminds you of the two fast exits.
    vim.opt_local.winbar = "  LaTeX label   ·   Enter insert   ·   Ctrl-C cancel  "

    -- Phase-17 labels are deliberately single-line, so Return is the natural
    -- "accept this label" key rather than a newline key. This mirrors the
    -- transient-editor feel: type the label, press Enter, and the popup exits.
    vim.keymap.set({ "n", "i" }, "<CR>", save_and_quit, {
        buffer = true,
        silent = true,
        desc = "Insert Inkscape LaTeX label",
    })

    -- Keep Alt/Ctrl-Enter as fallbacks in case a terminal profile remaps Return.
    vim.keymap.set({ "n", "i" }, "<M-CR>", save_and_quit, {
        buffer = true,
        silent = true,
        desc = "Insert Inkscape LaTeX label",
    })

    vim.keymap.set({ "n", "i" }, "<C-CR>", save_and_quit, {
        buffer = true,
        silent = true,
        desc = "Insert Inkscape LaTeX label",
    })

    vim.keymap.set({ "n", "i" }, "<C-c>", cancel, {
        buffer = true,
        silent = true,
        desc = "Cancel Inkscape LaTeX label",
    })

    -- ZZ remains the normal Vim save+quit fallback.
    vim.schedule(function()
        if vim.api.nvim_get_current_buf() == 0 then
            return
        end
        place_cursor_for_label()
        vim.cmd("startinsert")
    end)
end

return M
