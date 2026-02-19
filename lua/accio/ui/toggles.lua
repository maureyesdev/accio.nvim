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

return M
