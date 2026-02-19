local M = {}

local INDICATORS = {
  { flag = "case_sensitive", label = "Aa" },
  { flag = "whole_word",     label = "ab" },
  { flag = "regex",          label = ".*" },
}

--- Render flag toggle indicators into the search window's winbar.
---@param win integer
---@param flags accio.Flags
function M.render(win, flags)
  if not vim.api.nvim_win_is_valid(win) then return end

  local parts = {}
  for _, ind in ipairs(INDICATORS) do
    local hl = flags[ind.flag] and "AccioToggleActive" or "AccioToggleInactive"
    table.insert(parts, "%#" .. hl .. "#" .. ind.label .. "%*")
  end

  local winbar = " Search  %=" .. table.concat(parts, "  ") .. " "
  vim.wo[win].winbar = winbar
end

--- Render flag toggle indicators into a snacks.win border title.
--- Used by layout_snacks.lua instead of the winbar-based render() above.
--- The title format is: " Search  Aa  ab  .* " (left-anchored).
---@param snacks_win snacks.win
---@param flags accio.Flags
function M.render_snacks(snacks_win, flags)
  if not snacks_win or not snacks_win:valid() then return end

  -- Highlight chunk table accepted by snacks_win:set_title()
  local title = { { " Search", "AccioTitle" }, { "  ", "" } }
  for _, ind in ipairs(INDICATORS) do
    local hl = flags[ind.flag] and "AccioToggleActive" or "AccioToggleInactive"
    table.insert(title, { ind.label, hl })
    table.insert(title, { "  ", "" })
  end

  snacks_win:set_title(title, "left")
end

return M
