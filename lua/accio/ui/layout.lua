local config = require("accio.config")
local input = require("accio.ui.input")
local results_ui = require("accio.ui.results")
local rg = require("accio.engine.ripgrep")
local state_mod = require("accio.state")
local actions = require("accio.actions")
local toggles = require("accio.ui.toggles")

local M = {}

M.state = nil

--- { win = integer, buf = integer, valid = fn }
M.wins = {}

-- Persistent buffers (survive open/close cycles)
local bufs = {}
local bufs_setup = {} -- tracks which buffers have had keymaps/autocmds registered

-- Set of hidden section names (key = name, value = true)
local hidden = {}

---@type uv_timer_t?
local search_timer = nil

---@type integer?
local focus_group = nil

---@type integer?
local last_win = nil

local SECTION_LABELS = {
  search  = " Search",
  replace = " Replace",
  include = " Include",
  exclude = " Exclude",
  results = " Results",
}

local INPUT_PANES = { "search", "replace", "include", "exclude" }

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

--- Thin win+buf wrapper compatible with the rest of the codebase
local function make_win_obj(win_id, buf_id)
  return {
    win = win_id,
    buf = buf_id,
    valid = function(self)
      return vim.api.nvim_win_is_valid(self.win) and vim.api.nvim_buf_is_valid(self.buf)
    end,
  }
end

--- Apply plain window options (no borders, label via winbar)
local function apply_win_opts(win_id, name)
  vim.wo[win_id].wrap            = false
  vim.wo[win_id].number          = false
  vim.wo[win_id].relativenumber  = false
  vim.wo[win_id].signcolumn      = "no"
  vim.wo[win_id].foldcolumn      = "0"
  vim.wo[win_id].statusline      = " "
  vim.wo[win_id].winbar          = SECTION_LABELS[name] or ""

  if name == "results" then
    vim.wo[win_id].statuscolumn = ""
    vim.wo[win_id].cursorline   = true
  else
    vim.wo[win_id].statuscolumn = input.prompt
    vim.wo[win_id].cursorline   = false
  end
end

--- Create or reuse a buffer for a named pane
local function get_or_create_buf(name, is_prompt)
  if bufs[name] and vim.api.nvim_buf_is_valid(bufs[name]) then
    return bufs[name]
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buflisted = false
  vim.bo[buf].swapfile  = false
  if is_prompt then
    vim.bo[buf].buftype    = "prompt"
    input.setup_prompt(buf)
    vim.bo[buf].modifiable = true
  else
    vim.bo[buf].buftype    = "nofile"
    vim.bo[buf].modifiable = false
  end
  vim.bo[buf].filetype = "accio"
  bufs[name] = buf
  return buf
end

--- One-time per-buffer setup: keymaps and buffer-local autocmds.
--- Uses buffer-local autocmds (no named group) so they survive layout close/reopen.
local function setup_buf(name)
  if bufs_setup[name] then return end
  bufs_setup[name] = true

  local buf = bufs[name]
  local opts = { buffer = buf, silent = true }

  -- Shared navigation
  vim.keymap.set({ "n", "i" }, "<C-j>", function() M.focus_next() end, opts)
  vim.keymap.set({ "n", "i" }, "<C-k>", function() M.focus_prev() end, opts)
  vim.keymap.set({ "n", "i" }, "<C-n>", function() M.focus_next() end, opts)
  vim.keymap.set({ "n", "i" }, "<C-p>", function() M.focus_prev() end, opts)
  vim.keymap.set("n", "<Tab>",   function() M.focus_next() end, opts)
  vim.keymap.set("n", "<S-Tab>", function() M.focus_prev() end, opts)
  vim.keymap.set("n", "q",       function() require("accio").close() end, opts)

  -- Block <CR> in input panes to prevent multiline (results has its own <CR> handler)
  if name ~= "results" then
    vim.keymap.set({ "n", "i" }, "<CR>", "<Nop>", opts)
  end

  -- Flag toggles (case sensitive, whole word, regex)
  local function toggle_flag(flag)
    if not M.state then return end
    M.state.flags[flag] = not M.state.flags[flag]
    if M.wins.search then
      toggles.render(M.wins.search.win, M.state.flags)
    end
    M.schedule_search()
  end

  vim.keymap.set({ "n", "i" }, "<M-s>", function() toggle_flag("case_sensitive") end,
    vim.tbl_extend("force", opts, { desc = "Toggle case sensitive" }))
  vim.keymap.set({ "n", "i" }, "<M-w>", function() toggle_flag("whole_word") end,
    vim.tbl_extend("force", opts, { desc = "Toggle whole word" }))
  vim.keymap.set({ "n", "i" }, "<M-r>", function() toggle_flag("regex") end,
    vim.tbl_extend("force", opts, { desc = "Toggle regex" }))

  -- Section toggles available from any pane
  vim.keymap.set({ "n", "i" }, "<M-c>", function()
    require("accio").toggle_replace()
  end, vim.tbl_extend("force", opts, { desc = "Toggle replace" }))
  vim.keymap.set({ "n", "i" }, "<M-f>", function()
    require("accio").toggle_filters()
  end, vim.tbl_extend("force", opts, { desc = "Toggle filters" }))

  -- Replace all available from any pane
  vim.keymap.set("n", "R", function()
    if not M.state or not M.state.results or #M.state.results == 0 then return end
    local replacement = bufs.replace and input.get_text(bufs.replace) or ""
    if replacement == "" then
      vim.notify("accio: replace field is empty", vim.log.levels.WARN)
      return
    end
    actions.replace_all(M.state.results, replacement)
    vim.notify(string.format("accio: replaced in %d file(s)", #M.state.results))
    M.schedule_search()
  end, vim.tbl_extend("force", opts, { desc = "Replace all matches" }))

  if name == "search" then
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
      buffer = buf,
      callback = function() M.schedule_search() end,
    })

  elseif name == "replace" then
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
      buffer = buf,
      callback = function() M.do_render() end,
    })

  elseif name == "include" or name == "exclude" then
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
      buffer = buf,
      callback = function() M.schedule_search() end,
    })

  elseif name == "results" then
    vim.api.nvim_create_autocmd("InsertEnter", {
      buffer = buf,
      callback = function() vim.cmd("stopinsert") end,
    })
    vim.keymap.set("n", "<CR>", function()
      local line_idx = vim.api.nvim_win_get_cursor(0)[1] - 1
      local info = results_ui.get_line_info(line_idx)
      if not info or not info.file then return end

      -- Find the first window that doesn't belong to accio
      local accio_wins = {}
      for _, w in pairs(M.wins) do
        if w then accio_wins[w.win] = true end
      end
      local target_win = nil
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if not accio_wins[win] then
          target_win = win
          break
        end
      end
      if not target_win then return end

      vim.api.nvim_set_current_win(target_win)
      vim.cmd("edit " .. vim.fn.fnameescape(info.file))
      if info.lnum then
        vim.api.nvim_win_set_cursor(0, { info.lnum, 0 })
      end
    end, vim.tbl_extend("force", opts, { desc = "Open file at match" }))
  end
end

-- ---------------------------------------------------------------------------
-- Autofocus
-- ---------------------------------------------------------------------------

local function setup_autofocus()
  if focus_group then return end
  focus_group = vim.api.nvim_create_augroup("accio_autofocus", { clear = true })

  -- Track the window we're leaving so BufEnter knows where we came from
  vim.api.nvim_create_autocmd("WinLeave", {
    group = focus_group,
    callback = function()
      last_win = vim.api.nvim_get_current_win()
    end,
  })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = focus_group,
    callback = function(args)
      if not M.is_visible() then return end

      local is_accio = false
      for _, buf in pairs(bufs) do
        if buf == args.buf then is_accio = true; break end
      end
      if not is_accio then return end

      -- Don't steal focus when navigating between accio panes
      if last_win then
        for _, w in pairs(M.wins) do
          if w and w.win == last_win then return end
        end
      end

      -- Already in search
      if M.wins.search and M.wins.search.win == vim.api.nvim_get_current_win() then
        return
      end

      vim.schedule(function()
        if M.is_visible() then M.focus_search() end
      end)
    end,
  })
end

-- ---------------------------------------------------------------------------
-- Layout building
-- ---------------------------------------------------------------------------

--- (Re)create all input pane windows inside the sidebar.
--- Closes existing input windows and rebuilds in correct order above results.
local function rebuild_input_wins()
  -- Remember which pane is focused so we can restore it after rebuilding
  local focused_pane = nil
  local cur_win = vim.api.nvim_get_current_win()
  for _, name in ipairs(INPUT_PANES) do
    local w = M.wins[name]
    if w and w.win == cur_win then
      focused_pane = name
    end
  end

  for _, name in ipairs(INPUT_PANES) do
    local w = M.wins[name]
    if w and vim.api.nvim_win_is_valid(w.win) then
      vim.api.nvim_win_close(w.win, true)
    end
    M.wins[name] = nil
  end

  if not M.wins.results or not vim.api.nvim_win_is_valid(M.wins.results.win) then
    return
  end

  -- Create visible panes above results in forward order.
  -- Each "split above results" inserts just above results, so creating
  -- search → replace → include → exclude yields: search | replace | include | exclude | results
  for _, name in ipairs(INPUT_PANES) do
    if not hidden[name] then
      local buf = bufs[name]
      local win_id = vim.api.nvim_open_win(buf, false, {
        win    = M.wins.results.win,
        split  = "above",
        height = 1,
      })
      apply_win_opts(win_id, name)
      M.wins[name] = make_win_obj(win_id, buf)
    end
  end

  -- Restore focus: if the previously focused pane is still visible use it,
  -- otherwise fall back to search
  local restore = focused_pane and M.wins[focused_pane] or M.wins.search
  if restore and vim.api.nvim_win_is_valid(restore.win) then
    vim.api.nvim_set_current_win(restore.win)
  end

  -- Re-render toggle indicators in the (possibly new) search window
  if M.wins.search and M.state then
    toggles.render(M.wins.search.win, M.state.flags)
  end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Open the sidebar
function M.create()
  if M.is_visible() then return end

  local cfg = config.get()
  M.state = state_mod.new()

  hidden = {}
  if not cfg.replace_expanded then hidden.replace = true end
  if not cfg.filters_expanded then hidden.include = true; hidden.exclude = true end

  get_or_create_buf("search",  true)
  get_or_create_buf("replace", true)
  get_or_create_buf("include", true)
  get_or_create_buf("exclude", true)
  get_or_create_buf("results", false)

  for _, name in ipairs({ "search", "replace", "include", "exclude", "results" }) do
    setup_buf(name)
  end

  -- Open the sidebar as a plain vertical split
  local split_cmd = cfg.position == "right" and "botright" or "topleft"
  vim.cmd(split_cmd .. " " .. cfg.width .. "vsplit")

  local results_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(results_win, bufs.results)
  apply_win_opts(results_win, "results")
  M.wins.results = make_win_obj(results_win, bufs.results)

  rebuild_input_wins()
  setup_autofocus()

  if cfg.auto_focus then
    vim.schedule(function() M.focus_search() end)
  end
end

--- Schedule a debounced search
function M.schedule_search()
  local cfg = config.get()
  if search_timer then search_timer:stop() end
  search_timer = vim.uv.new_timer()
  search_timer:start(cfg.debounce, 0, vim.schedule_wrap(function()
    M.do_search()
  end))
end

--- Execute the search with current input values
function M.do_search()
  if not M.state or not M.is_visible() then return end

  local search_buf  = bufs.search
  local include_buf = bufs.include
  local exclude_buf = bufs.exclude
  local results_buf = bufs.results

  if not search_buf or not results_buf then return end

  local query = input.get_text(search_buf)

  if query == "" then
    rg.abort()
    M.state.query   = ""
    M.state.results = {}
    M.state.status  = "idle"
    results_ui.clear(results_buf)
    return
  end

  local include_glob = include_buf and input.get_text(include_buf) or ""
  local exclude_glob = exclude_buf and input.get_text(exclude_buf) or ""

  M.state.query        = query
  M.state.include_glob = include_glob
  M.state.exclude_glob = exclude_glob
  M.state.status       = "searching"

  local cfg = config.get()
  rg.search({
    query        = query,
    flags        = M.state.flags,
    include_glob = include_glob,
    exclude_glob = exclude_glob,
    cwd          = vim.fn.getcwd(),
    rg_path      = cfg.rg_path,
    on_results   = function(file_groups, stats)
      if not M.is_visible() then return end
      M.state.results = file_groups
      M.state.stats   = stats
      M.state.status  = "idle"
      local replacement = bufs.replace and input.get_text(bufs.replace) or ""
      results_ui.render(results_buf, file_groups, stats, replacement)
    end,
    on_error = function(msg)
      if not M.is_visible() then return end
      M.state.status = "error"
      vim.notify("accio: " .. msg, vim.log.levels.WARN)
    end,
  })
end

--- Re-render results with the current replacement text (no new search)
function M.do_render()
  if not M.state or not M.is_visible() then return end
  if not bufs.results then return end
  local replacement = bufs.replace and input.get_text(bufs.replace) or ""
  results_ui.render(bufs.results, M.state.results, M.state.stats, replacement)
end

--- Focus the search input
function M.focus_search()
  local win = M.wins.search
  if win and win:valid() then
    vim.api.nvim_set_current_win(win.win)
  end
end

--- Ordered list of currently visible pane names
local function visible_panes()
  local order = { "search", "replace", "include", "exclude", "results" }
  local visible = {}
  for _, name in ipairs(order) do
    if not hidden[name] then
      table.insert(visible, name)
    end
  end
  return visible
end

--- Name of the pane that currently has focus
local function current_pane()
  local cur = vim.api.nvim_get_current_win()
  for name, w in pairs(M.wins) do
    if w and w.win == cur then return name end
  end
  return nil
end

--- Focus a pane by name
local function focus_pane(name)
  local w = M.wins[name]
  if w and w:valid() then
    vim.api.nvim_set_current_win(w.win)
    vim.cmd("stopinsert")
  end
end

--- Focus the next visible pane
function M.focus_next()
  local panes = visible_panes()
  local cur   = current_pane()
  if not cur then return end
  for i, name in ipairs(panes) do
    if name == cur then
      focus_pane(panes[i + 1] or panes[1])
      return
    end
  end
end

--- Focus the previous visible pane
function M.focus_prev()
  local panes = visible_panes()
  local cur   = current_pane()
  if not cur then return end
  for i, name in ipairs(panes) do
    if name == cur then
      focus_pane(panes[i - 1] or panes[#panes])
      return
    end
  end
end

--- Toggle a section's visibility
---@param name string
function M.toggle_section(name)
  if not M.is_visible() then return end
  if hidden[name] then
    hidden[name] = nil
  else
    hidden[name] = true
  end
  rebuild_input_wins()
end

--- Destroy the layout and clean up
function M.destroy()
  rg.abort()

  if search_timer then
    search_timer:stop()
    search_timer:close()
    search_timer = nil
  end

  if focus_group then
    vim.api.nvim_del_augroup_by_id(focus_group)
    focus_group = nil
  end
  last_win = nil

  -- Close all sidebar windows (inputs first, then results)
  for _, name in ipairs({ "search", "replace", "include", "exclude", "results" }) do
    local w = M.wins[name]
    if w and vim.api.nvim_win_is_valid(w.win) then
      vim.api.nvim_win_close(w.win, true)
    end
  end

  M.wins  = {}
  M.state = nil
end

--- Check if the sidebar is currently open
---@return boolean
function M.is_visible()
  return M.wins.results ~= nil and vim.api.nvim_win_is_valid(M.wins.results.win)
end

return M
