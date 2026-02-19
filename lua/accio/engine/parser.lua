local M = {}

---@class accio.ParsedMatch
---@field type "match"
---@field file string
---@field lnum number
---@field text string trimmed line text
---@field trim_offset number bytes of leading whitespace removed
---@field submatches accio.Submatch[]

---@class accio.Submatch
---@field start number byte offset in original line
---@field end_ number byte offset end in original line
---@field match_text string

---@class accio.ParsedBegin
---@field type "begin"
---@field file string

---@class accio.ParsedEnd
---@field type "end"
---@field file string

---@class accio.ParsedSummary
---@field type "summary"

---@alias accio.Parsed accio.ParsedBegin|accio.ParsedMatch|accio.ParsedEnd|accio.ParsedSummary

--- Parse a single rg --json output line
---@param line string
---@return accio.Parsed?
function M.parse_line(line)
  local ok, data = pcall(vim.json.decode, line)
  if not ok or not data or not data.type then
    return nil
  end

  if data.type == "begin" then
    return {
      type = "begin",
      file = data.data.path.text,
    }
  elseif data.type == "match" then
    local raw_text = (data.data.lines.text or ""):gsub("\n$", "")
    local leading_ws = raw_text:match("^(%s*)") or ""
    local trim_offset = #leading_ws
    local trimmed = raw_text:sub(trim_offset + 1)

    local submatches = {}
    for _, sm in ipairs(data.data.submatches or {}) do
      table.insert(submatches, {
        start = sm.start,
        end_ = sm["end"],
        match_text = sm.match.text,
      })
    end

    return {
      type = "match",
      file = data.data.path.text,
      lnum = data.data.line_number,
      text = trimmed,
      trim_offset = trim_offset,
      submatches = submatches,
    }
  elseif data.type == "end" then
    return {
      type = "end",
      file = data.data.path.text,
    }
  elseif data.type == "summary" then
    return { type = "summary" }
  end

  return nil
end

return M
