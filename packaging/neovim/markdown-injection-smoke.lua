local function fail(message)
  io.stderr:write("NVIM_MARKDOWN_INJECTION_FAIL: " .. message .. "\n")
  vim.cmd("cquit 1")
end

vim.cmd("filetype detect")
if vim.bo.filetype ~= "markdown" then
  fail("expected markdown filetype, got " .. vim.inspect(vim.bo.filetype))
end

local ok_start, start_error = pcall(vim.treesitter.start, 0, "markdown")
if not ok_start then
  fail("could not start markdown parser: " .. tostring(start_error))
end

local ok_parser, parser = pcall(vim.treesitter.get_parser, 0, "markdown")
if not ok_parser or not parser then
  fail("could not get markdown parser: " .. tostring(parser))
end

local function collect_children(tree, seen)
  for language, child in pairs(tree:children()) do
    seen[language] = true
    collect_children(child, seen)
  end
end

local seen = {}
vim.wait(2000, function()
  pcall(parser.parse, parser, true)
  seen = {}
  collect_children(parser, seen)
  return seen.asterix_spec and seen.lua
end, 20)

if not seen.asterix_spec then
  fail("asterix-spec fence did not resolve to an asterix_spec child parser")
end
if seen.asterix then
  fail("legacy asterix fence still resolved to a parser")
end
if not seen.lua then
  fail("known-good lua fence did not resolve to a child parser")
end

print("NVIM_MARKDOWN_INJECTION_OK")
vim.cmd("qa!")
