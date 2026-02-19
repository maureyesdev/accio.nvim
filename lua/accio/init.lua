local M = {}

---@param opts? accio.Config
function M.setup(opts)
  require("accio.config").setup(opts)
  require("accio.highlights").setup()
end

--- Open the search panel (or focus it if already open)
function M.open()
  local layout = require("accio.ui.layout")
  if layout.is_visible() then
    layout.focus_search()
    return
  end
  layout.create()
end

--- Close the search panel
function M.close()
  require("accio.ui.layout").destroy()
end

--- Toggle the search panel open/closed
function M.toggle()
  local layout = require("accio.ui.layout")
  if layout.is_visible() then
    M.close()
  else
    M.open()
  end
end

--- Toggle the replace input section
function M.toggle_replace()
  require("accio.ui.layout").toggle_section("replace")
end

--- Toggle the file filter inputs (include + exclude)
function M.toggle_filters()
  local layout = require("accio.ui.layout")
  layout.toggle_section("include")
  layout.toggle_section("exclude")
end

--- Replace all current matches with the replacement text
function M.replace_all()
  require("accio.ui.layout").replace_all()
end

return M
