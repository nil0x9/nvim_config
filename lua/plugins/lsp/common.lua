return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        ['*'] = {
          keys = {
            -- disable signature help in insert mode
            { "<C-k>", false, mode = "i" },
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
