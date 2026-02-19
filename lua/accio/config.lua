local M = {}

---@class accio.Config
M.defaults = {
  -- Sidebar position: "left" or "right"
  position = "left",
  -- Sidebar width (columns)
  width = 40,
  -- Path to ripgrep binary
  rg_path = "rg",
  -- Debounce delay (ms) before triggering search
  debounce = 150,
  -- Auto-focus search input on open
  auto_focus = true,
  -- Show replace section expanded by default
  replace_expanded = false,
  -- Show file filter section expanded by default
  filters_expanded = false,
  -- Layout backend: "auto" | "snacks" | "plain"
  --   "auto"   use Snacks.layout when snacks.nvim is installed, else plain splits
  --   "snacks" always use Snacks.layout (requires snacks.nvim)
  --   "plain"  always use raw splits even when snacks.nvim is present
  layout = "auto",
}

---@type accio.Config
M.options = nil

---@param opts? accio.Config
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

---@return accio.Config
function M.get()
  if not M.options then
    M.setup({})
  end
  return M.options
end

return M
