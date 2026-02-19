local M = {}

---@class accio.State
---@field query string
---@field replacement string
---@field include_glob string
---@field exclude_glob string
---@field flags accio.Flags
---@field results accio.FileGroup[]
---@field stats accio.SearchStats?
---@field status "idle"|"searching"|"error"
---@field replace_visible boolean
---@field filters_visible boolean

---@class accio.Flags
---@field case_sensitive boolean
---@field whole_word boolean
---@field regex boolean

---@class accio.Result
---@field file string
---@field lnum number
---@field col number
---@field text string
---@field match_text string

---@return accio.State
function M.new()
  return {
    query = "",
    replacement = "",
    include_glob = "",
    exclude_glob = "",
    flags = {
      case_sensitive = false,
      whole_word = false,
      regex = false,
    },
    results = {},
    stats = nil,
    status = "idle",
    replace_visible = false,
    filters_visible = false,
  }
end

return M
