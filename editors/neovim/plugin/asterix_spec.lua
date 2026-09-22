pcall(vim.treesitter.language.register, "asterix_spec", "asterix-spec")

local group = vim.api.nvim_create_augroup("tree_sitter_asterix_spec_runtime_guard", { clear = true })

local function with_runtime(callback, bufnr)
  local ok, runtime = pcall(require, "asterix_spec_runtime")
  if ok then
    callback(runtime, bufnr)
  end
end

vim.api.nvim_create_autocmd({ "FileType", "BufEnter", "BufWinEnter" }, {
  group = group,
  pattern = "*",
  callback = function(args)
    with_runtime(function(runtime, bufnr)
      runtime.guard_indent(bufnr)
    end, args.buf)
  end,
})

vim.api.nvim_create_autocmd("OptionSet", {
  group = group,
  pattern = { "indentexpr", "indentkeys" },
  callback = function()
    local bufnr = vim.api.nvim_get_current_buf()
    vim.schedule(function()
      with_runtime(function(runtime, target)
        runtime.ensure_indent(target)
      end, bufnr)
    end)
  end,
})
