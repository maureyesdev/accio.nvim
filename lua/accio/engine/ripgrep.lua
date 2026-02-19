local parser = require("accio.engine.parser")

local M = {}

---@type number?
local current_job = nil

---@class accio.SearchOpts
---@field query string
---@field flags accio.Flags
---@field include_glob? string
---@field exclude_glob? string
---@field cwd? string
---@field rg_path? string
---@field on_results? fun(file_groups: accio.FileGroup[], stats: accio.SearchStats)
---@field on_error? fun(msg: string)

---@class accio.FileGroup
---@field file string
---@field matches accio.ParsedMatch[]

---@class accio.SearchStats
---@field total_matches number
---@field total_files number

--- Build the rg command from search options
---@param opts accio.SearchOpts
---@return string[]
function M.build_cmd(opts)
  local cmd = { opts.rg_path or "rg", "--json" }

  -- Case sensitivity
  if opts.flags.case_sensitive then
    table.insert(cmd, "--case-sensitive")
  else
    table.insert(cmd, "--ignore-case")
  end

  -- Whole word
  if opts.flags.whole_word then
    table.insert(cmd, "--word-regexp")
  end

  -- Regex vs fixed string
  if not opts.flags.regex then
    table.insert(cmd, "--fixed-strings")
  end

  -- Include globs
  if opts.include_glob and opts.include_glob ~= "" then
    for glob in opts.include_glob:gmatch("[^,]+") do
      glob = vim.trim(glob)
      if glob ~= "" then
        table.insert(cmd, "--glob")
        table.insert(cmd, glob)
      end
    end
  end

  -- Exclude globs
  if opts.exclude_glob and opts.exclude_glob ~= "" then
    for glob in opts.exclude_glob:gmatch("[^,]+") do
      glob = vim.trim(glob)
      if glob ~= "" then
        table.insert(cmd, "--glob")
        table.insert(cmd, "!" .. glob)
      end
    end
  end

  -- Pattern (after --)
  table.insert(cmd, "--")
  table.insert(cmd, opts.query)

  -- Explicit search path (without this, jobstart's pipe stdin
  -- causes rg to read from stdin instead of searching the directory)
  table.insert(cmd, ".")

  return cmd
end

--- Run a search with ripgrep
---@param opts accio.SearchOpts
function M.search(opts)
  M.abort()

  local cmd = M.build_cmd(opts)
  local file_groups = {} ---@type accio.FileGroup[]
  local current_group = nil ---@type accio.FileGroup?
  local stats = { total_matches = 0, total_files = 0 }
  local stderr_lines = {}
  local line_buf = ""

  current_job = vim.fn.jobstart(cmd, {
    cwd = opts.cwd or vim.fn.getcwd(),
    on_stdout = function(_, data, _)
      for i, chunk in ipairs(data) do
        -- Handle line buffering: first chunk continues previous partial
        if i == 1 then
          chunk = line_buf .. chunk
          line_buf = ""
        end

        if i < #data then
          -- Complete line
          if chunk ~= "" then
            local parsed = parser.parse_line(chunk)
            if parsed then
              if parsed.type == "begin" then
                current_group = {
                  file = parsed.file,
                  matches = {},
                }
                table.insert(file_groups, current_group)
                stats.total_files = stats.total_files + 1
              elseif parsed.type == "match" and current_group then
                table.insert(current_group.matches, parsed)
                stats.total_matches = stats.total_matches + 1
              end
            end
          end
        else
          -- Last element: might be partial line
          line_buf = chunk
        end
      end
    end,
    on_stderr = function(_, data, _)
      for _, line in ipairs(data) do
        if line ~= "" then
          table.insert(stderr_lines, line)
        end
      end
    end,
    on_exit = function(_, exit_code, _)
      current_job = nil
      vim.schedule(function()
        -- exit_code 0 = matches found, 1 = no matches, 2 = error
        if exit_code == 2 and opts.on_error then
          opts.on_error(table.concat(stderr_lines, "\n"))
        elseif opts.on_results then
          opts.on_results(file_groups, stats)
        end
      end)
    end,
  })
end

--- Abort the current search job
function M.abort()
  if current_job then
    vim.fn.jobstop(current_job)
    current_job = nil
  end
end

--- Check if a search is currently running
---@return boolean
function M.is_running()
  return current_job ~= nil
end

return M
