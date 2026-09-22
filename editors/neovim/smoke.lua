local file = vim.fn.expand("%:p")

local function fail(message)
  io.stderr:write("NVIM_SMOKE_FAIL: " .. message .. "\n")
  vim.cmd("cquit 1")
end

vim.cmd("filetype detect")

if vim.bo.filetype ~= "asterix-spec" then
  fail("expected filetype=asterix-spec, got " .. vim.inspect(vim.bo.filetype) .. " for " .. file)
end

local ok_start, start_error = pcall(vim.treesitter.start, 0, "asterix_spec")
if not ok_start then
  fail("vim.treesitter.start failed: " .. tostring(start_error))
end

local ok_parser, parser = pcall(vim.treesitter.get_parser, 0, "asterix_spec")
if not ok_parser or not parser then
  fail("could not get asterix_spec parser: " .. tostring(parser))
end

local ok_parse, trees = pcall(parser.parse, parser)
if not ok_parse or not trees or not trees[1] then
  fail("parser did not return a syntax tree")
end

local root = trees[1]:root()
if root:type() ~= "source_file" then
  fail("expected root source_file, got " .. root:type())
end

if root:has_error() then
  fail("syntax tree contains ERROR or MISSING nodes")
end

local query = vim.treesitter.query.get("asterix_spec", "highlights")
if not query then
  fail("missing highlights query for asterix_spec")
end

local function count_captures(query_name)
  local loaded_query = vim.treesitter.query.get("asterix_spec", query_name)
  if not loaded_query then
    fail("missing " .. query_name .. " query for asterix")
  end

  local counts = {}
  for id, _node in loaded_query:iter_captures(root, 0, 0, -1) do
    local name = loaded_query.captures[id]
    counts[name] = (counts[name] or 0) + 1
  end

  return counts
end

local counts = count_captures("highlights")

for _, required in ipairs({ "keyword", "number", "string" }) do
  if not counts[required] then
    fail("missing required highlight capture @" .. required)
  end
end

local fold_counts = count_captures("folds")
if not fold_counts.fold then
  fail("missing required folds capture @fold")
end

vim.wo.foldmethod = "expr"
vim.wo.foldexpr = "v:lua.vim.treesitter.foldexpr()"
vim.wo.foldminlines = 0
vim.wo.foldnestmax = 20

local fold_starts = 0
local function count_fold_starts()
  local starts = 0
  for lnum = 1, vim.api.nvim_buf_line_count(0) do
    local level = tostring(vim.treesitter.foldexpr(lnum))
    if level:sub(1, 1) == ">" then
      starts = starts + 1
    end
  end
  return starts
end

fold_starts = count_fold_starts()

if fold_starts == 0 then
  vim.wait(1000, function()
    fold_starts = count_fold_starts()
    return fold_starts > 0
  end, 10)
end

if fold_starts == 0 then
  fail("foldexpr produced no fold starts")
end

local indent_counts = count_captures("indents")
if not indent_counts.indent and not indent_counts["indent.begin"] then
  fail("missing required indents capture @indent or @indent.begin")
end

if vim.bo.indentexpr ~= "v:lua.GetAsterixSpecIndent()" then
  fail("expected ASTERIX indentexpr, got " .. vim.inspect(vim.bo.indentexpr))
end

local summary = {}
for name, count in pairs(counts) do
  summary[#summary + 1] = string.format("@%s=%d", name, count)
end
table.sort(summary)

local fold_summary = {}
for name, count in pairs(fold_counts) do
  fold_summary[#fold_summary + 1] = string.format("@%s=%d", name, count)
end
table.sort(fold_summary)

local indent_summary = {}
for name, count in pairs(indent_counts) do
  indent_summary[#indent_summary + 1] = string.format("@%s=%d", name, count)
end
table.sort(indent_summary)

print("NVIM_SMOKE_OK")
print("file=" .. file)
print("filetype=" .. vim.bo.filetype)
print("root=" .. root:type())
print("highlight_captures=" .. table.concat(summary, ","))
print("fold_captures=" .. table.concat(fold_summary, ","))
print("fold_starts=" .. fold_starts)
print("indent_captures=" .. table.concat(indent_summary, ","))

vim.cmd("qa")
