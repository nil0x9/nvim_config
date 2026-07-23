return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        ['*'] = {
          keys = {
            -- disable signature help in insert mode
            { "<C-k>", false, mode = "i" },
            -- use the global Glance mapping instead of LazyVim's buffer-local declaration mapping
            { "gD", false },
          },
        },
      },
      diagnostics = {
        virtual_text = false,
        float = { source = true },
      },
    },
  },
}
