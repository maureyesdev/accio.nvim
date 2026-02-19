local M = {}

function M.setup()
  local hl = {
    AccioTitle      = { bold = true, default = true, link = "Title" },
    AccioFile       = { bold = true, default = true, link = "Directory" },
    AccioFilePath   = { default = true, link = "Comment" },
    AccioLineNr     = { default = true, link = "LineNr" },
    AccioMatchCount = { default = true, link = "Number" },
    AccioStatus     = { default = true, link = "Comment" },
    AccioReplace    = { default = true, link = "DiffAdd" },
    AccioStrikethrough = {
      strikethrough = true,
      default = true,
      link = "DiffDelete",
    },
    -- Link to snacks groups when available; snacks groups themselves fall back
    -- to their own defaults, so this degrades gracefully without snacks.
    AccioMatch          = { default = true, link = "SnacksPickerMatch" },
    AccioBorder         = { default = true, link = "SnacksInputBorder" },
    AccioPrompt         = { default = true, link = "SnacksPickerPrompt" },
    AccioToggleActive   = { bold = true, default = true, link = "SnacksPickerToggle" },
    AccioToggleInactive = { default = true, link = "NonText" },
  }

  for name, opts in pairs(hl) do
    vim.api.nvim_set_hl(0, name, opts)
  end
end

return M
