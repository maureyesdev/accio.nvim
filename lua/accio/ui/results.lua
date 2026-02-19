local M = {}

local ns = vim.api.nvim_create_namespace("accio_results")

--- Maps 0-based buffer line → { file: string, lnum?: number }
---@type table<number, { file: string, lnum?: number }>
local line_map = {}

--- Render search results into the results buffer.
--- When `replacement` is a non-empty string, match regions are shown with
--- strikethrough and the replacement text is shown inline via virtual text.
---@param buf number
---@param file_groups accio.FileGroup[]
---@param stats accio.SearchStats?
---@param replacement? string
function M.render(buf, file_groups, stats, replacement)
  local lines = {}
  local highlights = {}
  line_map = {}

  local preview = replacement and replacement ~= ""

  -- Status line
  if stats and stats.total_matches > 0 then
    local status = string.format(
      "%d result%s in %d file%s",
      stats.total_matches,
      stats.total_matches == 1 and "" or "s",
      stats.total_files,
      stats.total_files == 1 and "" or "s"
    )
    table.insert(lines, status)
    table.insert(highlights, {
      line = #lines - 1,
      col_start = 0,
      col_end = #status,
      hl_group = "AccioStatus",
    })
    table.insert(lines, "")
  elseif stats then
    table.insert(lines, "No results found")
    table.insert(highlights, {
      line = 0,
      col_start = 0,
      col_end = 16,
      hl_group = "AccioStatus",
    })
  end

  -- File groups
  for _, group in ipairs(file_groups) do
    local count_str = tostring(#group.matches)
    local file_line = "  " .. group.file
    table.insert(lines, file_line)

    local file_line_idx = #lines - 1
    line_map[file_line_idx] = { file = group.file }

    table.insert(highlights, {
      line = file_line_idx,
      col_start = 2,
      col_end = #file_line,
      hl_group = "AccioFile",
    })

    table.insert(highlights, {
      line = file_line_idx,
      virt_text = { { " " .. count_str .. " ", "AccioMatchCount" } },
      virt_text_pos = "eol",
    })

    for _, match in ipairs(group.matches) do
      local lnum_str = tostring(match.lnum)
      local prefix = "    " .. lnum_str .. ": "
      local display_line = prefix .. match.text
      table.insert(lines, display_line)

      local match_line_idx = #lines - 1
      local prefix_len = #prefix
      line_map[match_line_idx] = { file = group.file, lnum = match.lnum }

      -- Line number highlight
      table.insert(highlights, {
        line = match_line_idx,
        col_start = 4,
        col_end = 4 + #lnum_str,
        hl_group = "AccioLineNr",
      })

      -- Submatches: strikethrough + inline replacement preview, or normal match highlight
      for _, sm in ipairs(match.submatches) do
        local col_start = prefix_len + sm.start - match.trim_offset
        local col_end   = prefix_len + sm["end_"] - match.trim_offset

        if col_start >= prefix_len and col_end > col_start then
          if preview then
            -- Strikethrough the original match
            table.insert(highlights, {
              line = match_line_idx,
              col_start = col_start,
              col_end = col_end,
              hl_group = "AccioStrikethrough",
            })
            -- Inline replacement text right after the match
            table.insert(highlights, {
              line = match_line_idx,
              col = col_end,
              virt_text = { { replacement, "AccioReplace" } },
              virt_text_pos = "inline",
            })
          else
            table.insert(highlights, {
              line = match_line_idx,
              col_start = col_start,
              col_end = col_end,
              hl_group = "AccioMatch",
            })
          end
        end
      end
    end

    table.insert(lines, "")
  end

  -- Write to buffer
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  -- Apply extmarks
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, hl in ipairs(highlights) do
    if hl.virt_text_pos == "inline" then
      vim.api.nvim_buf_set_extmark(buf, ns, hl.line, hl.col, {
        virt_text = hl.virt_text,
        virt_text_pos = "inline",
      })
    elseif hl.virt_text then
      vim.api.nvim_buf_set_extmark(buf, ns, hl.line, 0, {
        virt_text = hl.virt_text,
        virt_text_pos = hl.virt_text_pos or "eol",
      })
    else
      vim.api.nvim_buf_set_extmark(buf, ns, hl.line, hl.col_start, {
        end_col = hl.col_end,
        hl_group = hl.hl_group,
      })
    end
  end
end

--- Get the file/line info for a given 0-based buffer line
---@param line_idx number 0-based line index
---@return { file: string, lnum?: number }?
function M.get_line_info(line_idx)
  return line_map[line_idx]
end

--- Clear the results buffer
---@param buf number
function M.clear(buf)
  line_map = {}
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
end

return M
