local M = {}

function M.setup()
  local hl = {
    AccioTitle = { bold = true, default = true, link = "Title" },
    AccioMatch = { default = true, link = "Search" },
    AccioFile = { bold = true, default = true, link = "Directory" },
    AccioFilePath = { default = true, link = "Comment" },
    AccioLineNr = { default = true, link = "LineNr" },
    AccioMatchCount = { default = true, link = "Number" },
    AccioStatus = { default = true, link = "Comment" },
    AccioReplace = { default = true, link = "DiffAdd" },
    AccioStrikethrough = {
      strikethrough = true,
      default = true,
      link = "DiffDelete",
    },
    AccioPrompt = { default = true, link = "Special" },
    AccioToggleActive = { bold = true, default = true, link = "Function" },
    AccioToggleInactive = { default = true, link = "NonText" },
    AccioBorder = { default = true, link = "FloatBorder" },
  }

  for name, opts in pairs(hl) do
    vim.api.nvim_set_hl(0, name, opts)
  end
end

return M
