-- Dispatcher: choose layout backend based on the user's config.
--   "auto"   (default) use Snacks.layout when snacks.nvim is installed
--   "snacks" always use Snacks.layout (errors at runtime if snacks is absent)
--   "plain"  always use raw splits regardless of snacks presence
local cfg = require("accio.config").get()

if cfg.layout == "plain" then
  return require("accio.ui.layout_plain")
elseif cfg.layout == "snacks" then
  return require("accio.ui.layout_snacks")
else -- "auto"
  local ok = pcall(require, "snacks")
  if ok then
    return require("accio.ui.layout_snacks")
  else
    return require("accio.ui.layout_plain")
  end
end
