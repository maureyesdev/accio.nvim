if vim.g.loaded_accio then
  return
end
vim.g.loaded_accio = true

vim.api.nvim_create_user_command("Accio", function()
  require("accio").open()
end, { desc = "Open Accio search panel" })

vim.api.nvim_create_user_command("AccioToggle", function()
  require("accio").toggle()
end, { desc = "Toggle Accio search panel" })

vim.api.nvim_create_user_command("AccioClose", function()
  require("accio").close()
end, { desc = "Close Accio search panel" })
