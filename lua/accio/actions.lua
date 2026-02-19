local M = {}

--- Apply replacement text to a single line using submatch byte offsets.
--- Processes submatches right-to-left so earlier offsets stay valid.
---@param line string
---@param submatches accio.Submatch[]
---@param replacement string
---@return string
local function apply_to_line(line, submatches, replacement)
  local sorted = {}
  for _, sm in ipairs(submatches) do
    table.insert(sorted, sm)
  end
  table.sort(sorted, function(a, b) return a.start > b.start end)

  for _, sm in ipairs(sorted) do
    line = line:sub(1, sm.start) .. replacement .. line:sub(sm["end_"] + 1)
  end
  return line
end

--- Group all submatches in a file group by line number
---@param file_group accio.FileGroup
---@return table<number, accio.Submatch[]>
local function submatches_by_lnum(file_group)
  local by_lnum = {}
  for _, match in ipairs(file_group.matches) do
    if not by_lnum[match.lnum] then
      by_lnum[match.lnum] = {}
    end
    for _, sm in ipairs(match.submatches) do
      table.insert(by_lnum[match.lnum], sm)
    end
  end
  return by_lnum
end

--- Replace all matches in a single file group.
--- Uses the Neovim buffer API when the file is already loaded (preserves undo),
--- otherwise reads and writes the file directly.
---@param file_group accio.FileGroup
---@param replacement string
---@return boolean success
function M.replace_in_file(file_group, replacement)
  local filepath = file_group.file
  local abs_path = vim.fn.fnamemodify(filepath, ":p")
  local by_lnum = submatches_by_lnum(file_group)

  local bufnr = vim.fn.bufnr(abs_path)
  local buf_loaded = bufnr ~= -1 and vim.fn.bufloaded(bufnr) == 1

  if buf_loaded then
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    for lnum, sms in pairs(by_lnum) do
      if lines[lnum] then
        lines[lnum] = apply_to_line(lines[lnum], sms, replacement)
      end
    end
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  else
    local f = io.open(abs_path, "r")
    if not f then return false end
    local lines = {}
    for line in f:lines() do
      table.insert(lines, line)
    end
    f:close()

    for lnum, sms in pairs(by_lnum) do
      if lines[lnum] then
        lines[lnum] = apply_to_line(lines[lnum], sms, replacement)
      end
    end

    local out = io.open(abs_path, "w")
    if not out then return false end
    out:write(table.concat(lines, "\n") .. "\n")
    out:close()
  end

  return true
end

--- Replace all matches across all file groups.
---@param file_groups accio.FileGroup[]
---@param replacement string
function M.replace_all(file_groups, replacement)
  for _, group in ipairs(file_groups) do
    M.replace_in_file(group, replacement)
  end
end

return M
