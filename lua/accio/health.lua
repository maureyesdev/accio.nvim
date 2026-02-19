local M = {}

function M.check()
  local h = vim.health

  -- Neovim version
  h.start("accio.nvim")
  if vim.fn.has("nvim-0.10") == 1 then
    h.ok("Neovim >= 0.10")
  else
    h.error("Neovim >= 0.10 is required")
  end

  -- ripgrep
  h.start("ripgrep")
  local cfg = require("accio.config").get()
  local rg_path = cfg.rg_path or "rg"

  local found = vim.fn.executable(rg_path) == 1
  if not found then
    h.error(
      string.format("ripgrep not found (checked: %q)", rg_path),
      { "Install ripgrep: https://github.com/BurntSushi/ripgrep#installation" }
    )
    return
  end

  -- version check
  local result = vim.system({ rg_path, "--version" }, { text = true }):wait()
  if result.code ~= 0 then
    h.warn("Could not determine ripgrep version")
    return
  end

  local version_line = result.stdout:match("^[^\n]+") or ""
  local major, minor = version_line:match("ripgrep (%d+)%.(%d+)")
  if major and minor then
    if tonumber(major) > 13 or (tonumber(major) == 13 and tonumber(minor) >= 0) then
      h.ok(string.format("ripgrep %s.%s found at %q", major, minor, rg_path))
    else
      h.warn(
        string.format("ripgrep %s.%s found — version >= 14 recommended", major, minor),
        { "Upgrade: https://github.com/BurntSushi/ripgrep#installation" }
      )
    end
  else
    h.ok(string.format("ripgrep found at %q (%s)", rg_path, version_line))
  end
end

return M
