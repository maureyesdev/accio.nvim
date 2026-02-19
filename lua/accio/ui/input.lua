local M = {}

--- Prompt string shown in the statuscolumn of input windows
M.prompt = " %#AccioPrompt#>%* "

--- Set up a prompt-style input buffer (buftype=prompt with empty prompt)
---@param buf number
function M.setup_prompt(buf)
  vim.fn.prompt_setprompt(buf, "")
  vim.bo[buf].modified = false
end

--- Get the text content of a single-line input buffer
---@param buf number
---@return string
function M.get_text(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, 1, false)
  return lines[1] or ""
end

return M
