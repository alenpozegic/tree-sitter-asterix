local M = {}

local block_keywords = {
  preamble = true,
  items = true,
  definition = true,
  description = true,
  remark = true,
  group = true,
  extended = true,
  compound = true,
  repetitive = true,
  explicit = true,
  element = true,
  table = true,
  uap = true,
  uaps = true,
  variations = true,
}

local function line_at(lnum)
  if lnum < 1 or lnum > vim.api.nvim_buf_line_count(0) then
    return ""
  end

  return vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, false)[1] or ""
end

local function leading_indent(line)
  return #(line:match("^%s*") or "")
end

local function trim(line)
  return (line:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function first_word(text)
  return text:match("^([%a_][%w_-]*)")
end

local function previous_nonblank(lnum)
  for current = lnum - 1, 1, -1 do
    local line = line_at(current)
    if trim(line) ~= "" then
      return current, line
    end
  end

  return nil, nil
end

local function parent_keyword_before(lnum, child_indent)
  for current = lnum - 1, 1, -1 do
    local line = line_at(current)
    local text = trim(line)

    if text ~= "" then
      local indent = leading_indent(line)
      if indent < child_indent then
        return first_word(text)
      end
    end
  end

  return nil
end

local function nearest_variations_indent(lnum)
  for current = lnum - 1, 1, -1 do
    local line = line_at(current)
    local text = trim(line)

    if text == "variations" then
      return leading_indent(line)
    end

    if text == "uaps" then
      return nil
    end
  end

  return nil
end

local function is_uap_item_text(text)
  return text == "-"
    or text == "rfs"
    or text == "RE"
    or text == "SP"
    or text:match("^%d%d%d$")
    or text:match("^[A-Z][A-Z0-9_]*$")
end

local function is_variation_name(text)
  return text:match("^[a-z][%w_-]*$") ~= nil
end

local function is_case_row_header(text)
  return text:match("^%d+%s*:%s*$") ~= nil
    or text:match("^%([^)]*%)%s*:%s*$") ~= nil
    or text:match("^default%s*:%s*$") ~= nil
end

local function nearest_case_indent(lnum)
  for current = lnum - 1, 1, -1 do
    local line = line_at(current)
    local text = trim(line)

    if text:match("^case%s+") then
      return leading_indent(line)
    end
  end

  return nil
end

local function opens_block(text)
  local word = first_word(text)
  if word and block_keywords[word] then
    return true
  end

  if text:match("^case%s+") then
    return true
  end

  if text:match("^[A-Z0-9_]+%s+\"") then
    return true
  end

  if text:match("^%d+%s+\"") then
    return true
  end

  if text:match("^%d+%s*:") then
    return false
  end

  return false
end

function M.get_indent(lnum)
  lnum = lnum or vim.v.lnum

  if lnum <= 1 then
    return 0
  end

  local current = trim(line_at(lnum))
  local previous_lnum, previous = previous_nonblank(lnum)
  if not previous then
    return 0
  end

  local shiftwidth = vim.bo.shiftwidth
  if shiftwidth == 0 then
    shiftwidth = vim.bo.tabstop
  end
  if shiftwidth == 0 then
    shiftwidth = 4
  end

  local previous_text = trim(previous)
  local base = leading_indent(previous)
  local variations_indent = nearest_variations_indent(lnum)

  if is_case_row_header(current) then
    local case_indent = nearest_case_indent(lnum)
    if case_indent then
      return case_indent + shiftwidth
    end
  end

  if is_case_row_header(previous_text) then
    if parent_keyword_before(previous_lnum, base) == "case" then
      return base + shiftwidth
    end

    return base
  end

  if variations_indent and is_uap_item_text(previous_text) then
    if current:match("^case%s+") then
      return variations_indent
    end

    if is_variation_name(current) then
      return variations_indent + shiftwidth
    end
  end

  if variations_indent and is_variation_name(previous_text) then
    return base + shiftwidth
  end

  if opens_block(previous_text) then
    return base + shiftwidth
  end

  return base
end

function _G.GetAsterixIndent()
  return M.get_indent(vim.v.lnum)
end

return M
