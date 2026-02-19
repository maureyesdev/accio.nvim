-- Snacks.layout + Snacks.win powered sidebar.
-- Used automatically by layout.lua when snacks.nvim is available.

local config     = require("accio.config")
local input_mod  = require("accio.ui.input")
local results_ui = require("accio.ui.results")
local rg         = require("accio.engine.ripgrep")
local state_mod  = require("accio.state")
local actions    = require("accio.actions")
local toggles    = require("accio.ui.toggles")

local M = {}

M.state = nil
M.wins  = {}

-- Persistent buffers (survive open/close cycles)
local bufs       = {}
local bufs_setup = {} -- tracks which buffers have had keymaps/autocmds registered

-- Active snacks.layout instance (nil when closed)
local snacks_layout = nil

---@type uv_timer_t?
local search_timer = nil

---@type integer?
local focus_group = nil

---@type integer?
local last_win = nil

local ALL_PANES = { "search", "replace", "include", "exclude", "results" }

-- ---------------------------------------------------------------------------
-- Buffer management — identical logic to layout_plain
-- ---------------------------------------------------------------------------

local function get_or_create_buf(name, is_prompt)
  if bufs[name] and vim.api.nvim_buf_is_valid(bufs[name]) then
    return bufs[name]
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buflisted = false
  vim.bo[buf].swapfile  = false
  if is_prompt then
    vim.bo[buf].buftype    = "prompt"
    input_mod.setup_prompt(buf)
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
local function setup_buf(name)
  if bufs_setup[name] then return end
  bufs_setup[name] = true

  local buf  = bufs[name]
  local opts = { buffer = buf, silent = true }

  -- Shared navigation
  vim.keymap.set({ "n", "i" }, "<C-j>", function() M.focus_next() end, opts)
  vim.keymap.set({ "n", "i" }, "<C-k>", function() M.focus_prev() end, opts)
  vim.keymap.set({ "n", "i" }, "<C-n>", function() M.focus_next() end, opts)
  vim.keymap.set({ "n", "i" }, "<C-p>", function() M.focus_prev() end, opts)
  vim.keymap.set("n", "<Tab>",   function() M.focus_next() end, opts)
  vim.keymap.set("n", "<S-Tab>", function() M.focus_prev() end, opts)
  vim.keymap.set("n", "q",       function() require("accio").close() end, opts)

  -- Block <CR> in input panes to prevent multiline (results has its own handler)
  if name ~= "results" then
    vim.keymap.set({ "n", "i" }, "<CR>", "<Nop>", opts)
  end

  -- Flag toggles — re-render into snacks border title after each change
  local function toggle_flag(flag)
    if not M.state then return end
    M.state.flags[flag] = not M.state.flags[flag]
    if snacks_layout and snacks_layout.wins.search then
      toggles.render_snacks(snacks_layout.wins.search, M.state.flags)
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

  -- Replace all
  vim.keymap.set("n", "R", function()
    M.replace_all()
  end, vim.tbl_extend("force", opts, { desc = "Replace all matches" }))

  if name == "search" then
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
      buffer   = buf,
      callback = function() M.schedule_search() end,
    })

  elseif name == "replace" then
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
      buffer   = buf,
      callback = function() M.do_render() end,
    })

  elseif name == "include" or name == "exclude" then
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
      buffer   = buf,
      callback = function() M.schedule_search() end,
    })

  elseif name == "results" then
    -- Prevent insert mode in results
    vim.api.nvim_create_autocmd("InsertEnter", {
      buffer   = buf,
      callback = function() vim.cmd("stopinsert") end,
    })

    -- Jump to match on <CR>
    vim.keymap.set("n", "<CR>", function()
      local line_idx = vim.api.nvim_win_get_cursor(0)[1] - 1
      local info = results_ui.get_line_info(line_idx)
      if not info or not info.file then return end

      -- Collect all accio-owned window IDs to exclude
      local accio_wins = {}
      for _, w in pairs(M.wins) do
        if w then accio_wins[w.win] = true end
      end
      -- Also exclude the snacks layout root (the structural sidebar split)
      if snacks_layout and snacks_layout.root and snacks_layout.root.win then
        accio_wins[snacks_layout.root.win] = true
      end

      -- Find the first real (non-floating) editor window
      local target_win = nil
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if not accio_wins[win] then
          local wincfg = vim.api.nvim_win_get_config(win)
          if not wincfg.relative or wincfg.relative == "" then
            target_win = win
            break
          end
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

  -- Mirrors snacks picker's "prevent entering root window for split layouts" pattern.
  -- See: snacks.nvim/lua/snacks/picker/core/picker.lua lines 332-353.

  local left_picker   = false  -- were we in an accio pane just before leaving?
  local last_accio_win = nil   -- last accio pane window id that had focus

  -- 1. Track when ANY window is left: note if we were in an accio pane.
  vim.api.nvim_create_autocmd("WinLeave", {
    group    = focus_group,
    callback = function()
      last_win    = vim.api.nvim_get_current_win()
      left_picker = false
      if snacks_layout then
        for _, sw in pairs(snacks_layout.wins) do
          if sw and sw.win == last_win then
            left_picker = true
            break
          end
        end
      end
    end,
  })

  -- 2. Track ANY window entered: save the last accio pane that had focus.
  vim.api.nvim_create_autocmd("WinEnter", {
    group    = focus_group,
    callback = function()
      if not snacks_layout then return end
      local cur = vim.api.nvim_get_current_win()
      for _, sw in pairs(snacks_layout.wins) do
        if sw and sw.win == cur then
          last_accio_win = cur
          break
        end
      end
    end,
  })

  -- 3. When focus lands on the structural root box win (e.g. via <C-h> from
  --    the editor), redirect to the right accio pane instead of sitting at (1,1).
  --    { buf = true } fires only when the root box's buffer is entered.
  --    { nested = true } lets the WinEnter for the redirect target fire too.
  snacks_layout.root:on("WinEnter", function()
    if left_picker then
      -- Came from an accio pane — escape to the editor side.
      local pos = snacks_layout.root.opts.position or "left"
      local wincmds = { left = "l", right = "h", top = "j", bottom = "k" }
      vim.cmd("wincmd " .. (wincmds[pos] or "l"))
    elseif last_accio_win and vim.api.nvim_win_is_valid(last_accio_win) then
      -- Return to whichever accio pane the user last visited.
      vim.api.nvim_set_current_win(last_accio_win)
    else
      -- First-ever focus into the layout: land on search.
      M.focus_search()
    end
  end, { buf = true, nested = true })

  -- 4. Accio-buffer guard: redirect to search when entering any accio buffer
  --    from outside the layout via buffer commands (:b, tab switches, etc.).
  vim.api.nvim_create_autocmd("BufEnter", {
    group    = focus_group,
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
-- Snacks win + layout construction
-- ---------------------------------------------------------------------------

--- Create a Snacks.win that wraps one of accio's persistent buffers.
--- We pass `keys = { q = false }` to suppress snacks' default "q → close" keymap
--- so our own buffer-local "q → accio.close()" survives.
---@param name string
---@param is_input boolean
---@return snacks.win
local function make_snacks_win(name, is_input)
  return Snacks.win({
    buf    = bufs[name],
    show   = false,
    keys   = { q = false },
    fixbuf = true,
    bo     = { filetype = "accio" },
    wo     = is_input and {
      wrap           = false,
      number         = false,
      relativenumber = false,
      signcolumn     = "no",
      foldcolumn     = "0",
      statuscolumn   = " ",
      cursorline     = false,
    } or {
      wrap           = false,
      number         = false,
      relativenumber = false,
      signcolumn     = "no",
      foldcolumn     = "0",
      statuscolumn   = "",
      cursorline     = true,
    },
  })
end

---@param cfg accio.Config
---@param hidden_list string[]
---@return snacks.layout
local function build_layout(cfg, hidden_list)
  local wins = {
    search  = make_snacks_win("search",  true),
    replace = make_snacks_win("replace", true),
    include = make_snacks_win("include", true),
    exclude = make_snacks_win("exclude", true),
    results = make_snacks_win("results", false),
  }

  return Snacks.layout.new({
    show   = false,
    wins   = wins,
    hidden = hidden_list,
    on_update = function(layout)
      -- Re-apply toggle indicators after every layout:update().
      -- Snacks re-merges win_opts on each update, resetting the title back to
      -- the plain " Search " string from the layout node definition.  This
      -- callback fires at the very end of update(), so our custom title wins.
      if layout.wins.search and layout.wins.search:valid() and M.state then
        toggles.render_snacks(layout.wins.search, M.state.flags)
      end
    end,
    layout = {
      position = cfg.position,
      width    = cfg.width,
      height   = 0,
      backdrop = false,
      border   = "none",
      box      = "vertical",
      -- height = 1 content + rounded border (top+bottom) = 3 rows total per input
      { win = "search",  height = 1, border = "rounded",
        title = " Search ", title_pos = "left" },
      { win = "replace", height = 1, border = "rounded",
        title = " Replace ", title_pos = "left" },
      { win = "include", height = 1, border = "rounded",
        title = " Include ", title_pos = "left" },
      { win = "exclude", height = 1, border = "rounded",
        title = " Exclude ", title_pos = "left" },
      { win = "results", border = "rounded",
        title = " Results ", title_pos = "left" },
    },
  })
end

--- Sync M.wins from snacks_layout.wins so the rest of accio can use it.
--- Called after layout:show() and after every toggle.
local function sync_wins()
  M.wins = {}
  for name, sw in pairs(snacks_layout.wins) do
    if sw:valid() then
      M.wins[name] = {
        win   = sw.win,
        buf   = sw.buf,
        valid = function() return sw:valid() end,
      }
    end
  end
end

-- ---------------------------------------------------------------------------
-- Focus helpers
-- ---------------------------------------------------------------------------

local function visible_panes()
  local visible = {}
  for _, name in ipairs(ALL_PANES) do
    local sw = snacks_layout and snacks_layout.wins[name]
    if sw and sw:valid() and not snacks_layout:is_hidden(name) then
      table.insert(visible, name)
    end
  end
  return visible
end

local function current_pane()
  if not snacks_layout then return nil end
  local cur = vim.api.nvim_get_current_win()
  for name, sw in pairs(snacks_layout.wins) do
    if sw and sw.win == cur then return name end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function M.create()
  if M.is_visible() then return end

  local cfg = config.get()
  M.state = state_mod.new()

  -- (Re)create or reuse persistent buffers
  get_or_create_buf("search",  true)
  get_or_create_buf("replace", true)
  get_or_create_buf("include", true)
  get_or_create_buf("exclude", true)
  get_or_create_buf("results", false)

  -- One-time keymap + autocmd setup per buffer
  for _, name in ipairs(ALL_PANES) do
    setup_buf(name)
  end

  -- Build hidden list from config
  local hidden = {}
  if not cfg.replace_expanded then
    table.insert(hidden, "replace")
  end
  if not cfg.filters_expanded then
    table.insert(hidden, "include")
    table.insert(hidden, "exclude")
  end

  snacks_layout = build_layout(cfg, hidden)
  snacks_layout:show()

  -- Sync M.wins after layout windows are open
  sync_wins()

  setup_autofocus()

  if cfg.auto_focus then
    vim.schedule(function() M.focus_search() end)
  end
end

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

  if snacks_layout then
    snacks_layout:close()
    snacks_layout = nil
  end

  M.wins  = {}
  M.state = nil
end

function M.is_visible()
  return snacks_layout ~= nil and snacks_layout:valid()
end

function M.focus_search()
  local sw = snacks_layout and snacks_layout.wins.search
  if sw and sw:valid() then sw:focus() end
end

function M.focus_next()
  if not snacks_layout then return end
  local panes = visible_panes()
  local cur   = current_pane()
  if not cur then return end
  for i, name in ipairs(panes) do
    if name == cur then
      local target = snacks_layout.wins[panes[i + 1] or panes[1]]
      if target and target:valid() then target:focus() end
      return
    end
  end
end

function M.focus_prev()
  if not snacks_layout then return end
  local panes = visible_panes()
  local cur   = current_pane()
  if not cur then return end
  for i, name in ipairs(panes) do
    if name == cur then
      local target = snacks_layout.wins[panes[i - 1] or panes[#panes]]
      if target and target:valid() then target:focus() end
      return
    end
  end
end

function M.toggle_section(name)
  if not M.is_visible() then return end
  snacks_layout:toggle(name)
  -- Re-sync M.wins (win IDs may change after layout rebuild)
  sync_wins()
  -- Toggle indicators are re-applied automatically via the on_update callback.
end

function M.schedule_search()
  local cfg = config.get()
  if search_timer then search_timer:stop() end
  search_timer = vim.uv.new_timer()
  search_timer:start(cfg.debounce, 0, vim.schedule_wrap(function()
    M.do_search()
  end))
end

function M.do_search()
  if not M.state or not M.is_visible() then return end

  local search_buf  = bufs.search
  local include_buf = bufs.include
  local exclude_buf = bufs.exclude
  local results_buf = bufs.results

  if not search_buf or not results_buf then return end

  local query = input_mod.get_text(search_buf)

  if query == "" then
    rg.abort()
    M.state.query   = ""
    M.state.results = {}
    M.state.status  = "idle"
    results_ui.clear(results_buf)
    return
  end

  local include_glob = include_buf and input_mod.get_text(include_buf) or ""
  local exclude_glob = exclude_buf and input_mod.get_text(exclude_buf) or ""

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
      local replacement = bufs.replace and input_mod.get_text(bufs.replace) or ""
      results_ui.render(results_buf, file_groups, stats, replacement)
    end,
    on_error = function(msg)
      if not M.is_visible() then return end
      M.state.status = "error"
      vim.notify("accio: " .. msg, vim.log.levels.WARN)
    end,
  })
end

function M.do_render()
  if not M.state or not M.is_visible() then return end
  if not bufs.results then return end
  local replacement = bufs.replace and input_mod.get_text(bufs.replace) or ""
  results_ui.render(bufs.results, M.state.results, M.state.stats, replacement)
end

function M.replace_all()
  if not M.state or not M.state.results or #M.state.results == 0 then return end
  local replacement = bufs.replace and input_mod.get_text(bufs.replace) or ""
  if replacement == "" then
    vim.notify("accio: replace field is empty", vim.log.levels.WARN)
    return
  end
  actions.replace_all(M.state.results, replacement)
  vim.notify(string.format("accio: replaced in %d file(s)", #M.state.results))
  M.schedule_search()
end

return M
