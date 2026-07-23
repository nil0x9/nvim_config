-- vim.diagnostic.config(
--     { 
--         float = { source = true },
--         virtual_text = false,
--         underline=true,
--         update_in_insert = false,
--     }
-- )

-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
-- -- Set to "ruff_lsp" to use the old LSP implementation version.
vim.g.lazyvim_python_lsp = "pyright"
vim.g.lazyvim_python_ruff = ""
vim.g.lazyvim_python_ruff_lsp = ""
vim.opt.backup = false
vim.opt.writebackup = false
vim.opt.foldmethod='indent'
vim.opt.colorcolumn='120'
vim.g.ai_cmp = false

-- Keep regular yanks separate from the system clipboard on every platform.
vim.opt.clipboard = ""

local is_macos = (vim.uv or vim.loop).os_uname().sysname == "Darwin"
if is_macos then
  -- Let Neovim use the native pbcopy/pbpaste clipboard provider.
  vim.g.clipboard = nil
else
  -- Use OSC 52 for Linux and other terminal-based environments.
  local osc52 = require("vim.ui.clipboard.osc52")
  vim.g.clipboard = {
    name = "OSC 52",
    copy = {
      ["+"] = osc52.copy("+"),
      ["*"] = osc52.copy("*"),
    },
    paste = {
      ["+"] = osc52.paste("+"),
      ["*"] = osc52.paste("*"),
    },
  }
end
