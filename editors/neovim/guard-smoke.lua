local runtime = require("asterix_runtime")

local function fail(message)
  io.stderr:write("NVIM_GUARD_SMOKE_FAIL: " .. message .. "\n")
  vim.cmd("cquit 1")
end

vim.cmd("filetype plugin indent on")
vim.cmd("filetype detect")

if vim.bo.filetype ~= "asterix" then
  fail("expected filetype=asterix, got " .. vim.inspect(vim.bo.filetype))
end

if vim.bo.indentexpr ~= runtime.indentexpr then
  fail("expected initial ASTERIX indentexpr, got " .. vim.inspect(vim.bo.indentexpr))
end

vim.bo.indentexpr = "nvim_treesitter#indent()"
vim.bo.indentkeys = "0=case"

vim.wait(1000, function()
  return vim.bo.indentexpr == runtime.indentexpr and vim.bo.indentkeys == runtime.indentkeys
end, 10)

if vim.bo.indentexpr ~= runtime.indentexpr then
  fail("guard did not restore ASTERIX indentexpr, got " .. vim.inspect(vim.bo.indentexpr))
end

if vim.bo.indentkeys ~= runtime.indentkeys then
  fail("guard did not restore ASTERIX indentkeys, got " .. vim.inspect(vim.bo.indentkeys))
end

print("NVIM_GUARD_SMOKE_OK")
vim.cmd("qa!")
