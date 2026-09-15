local M = {}

M.indentexpr = "v:lua.GetAsterixIndent()"
M.indentkeys = "!^F,o,O,<:>,0=case,0=default,0=definition,0=description,0=remark,0=group,0=extended,0=compound,0=element,0=table,0=uap,0=uaps,0=variations"

local applying = false

local function is_loaded_asterix_buffer(bufnr)
  return bufnr
    and vim.api.nvim_buf_is_loaded(bufnr)
    and vim.bo[bufnr].filetype == "asterix"
end

function M.apply_indent(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if applying or not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end

  pcall(require, "asterix_indent")

  applying = true
  vim.bo[bufnr].indentexpr = M.indentexpr
  vim.bo[bufnr].indentkeys = M.indentkeys
  applying = false
end

function M.ensure_indent(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if not is_loaded_asterix_buffer(bufnr) then
    return
  end

  if vim.bo[bufnr].indentexpr ~= M.indentexpr or vim.bo[bufnr].indentkeys ~= M.indentkeys then
    M.apply_indent(bufnr)
  end
end

function M.guard_indent(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if not is_loaded_asterix_buffer(bufnr) then
    return
  end

  M.apply_indent(bufnr)

  vim.schedule(function()
    M.ensure_indent(bufnr)
  end)

  for _, delay in ipairs({ 25, 100, 300, 800, 1500 }) do
    vim.defer_fn(function()
      M.ensure_indent(bufnr)
    end, delay)
  end
end

function M.guard_current_buffer()
  M.guard_indent(vim.api.nvim_get_current_buf())
end

return M
