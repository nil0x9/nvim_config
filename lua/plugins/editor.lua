local latex_cache = {}
local latex_converters = { "utftex", "latex2text" }

local function normalize_latex(input)
  local norm_delimiter = "left"
  return input:gsub("\\|", function()
    if norm_delimiter == "left" then
      norm_delimiter = "right"
      return "\\lVert "
    else
      norm_delimiter = "left"
      return "\\rVert "
    end
  end)
end

local function convert_latex(input)
  if latex_cache[input] ~= nil then
    return latex_cache[input]
  end

  local normalized = normalize_latex(input)

  for _, converter in ipairs(latex_converters) do
    if vim.fn.executable(converter) == 1 then
      local result = vim.system({ converter }, { stdin = normalized, text = true }):wait()
      if result.code == 0 and result.stdout and result.stdout ~= "" then
        local output = result.stdout:gsub("%s+‖", "‖")
        latex_cache[input] = vim.split(output, "\n", { plain = true, trimempty = true })
        return latex_cache[input]
      end
    end
  end

  latex_cache[input] = false
  return nil
end

local function parse_latex_blocks(ctx)
  local marks = {}
  local query = vim.treesitter.query.parse("markdown_inline", "(latex_block) @latex")
  local win = vim.fn.bufwinid(ctx.buf)
  local cursor_row = win ~= -1 and vim.api.nvim_win_get_cursor(win)[1] - 1 or nil

  for _, node in query:iter_captures(ctx.root, ctx.buf) do
    local source = vim.treesitter.get_node_text(node, ctx.buf)
    local input = vim.trim(source:match("^%$*(.-)%$*$") or source)
    local output = convert_latex(input)

    if output then
      local start_row, start_col, end_row, end_col = node:range()
      local source_height = end_row - start_row + 1

      if source_height == 1 then
        local center = math.floor(#output / 2) + 1
        marks[#marks + 1] = {
          conceal = "latex",
          start_row = start_row,
          start_col = start_col,
          opts = {
            end_row = end_row,
            end_col = end_col,
            conceal = "",
            virt_text = { { output[center], "RenderMarkdownMath" } },
            virt_text_pos = "inline",
          },
        }

        if center > 1 then
          local lines = {}
          for i = 1, center - 1 do
            lines[#lines + 1] = { { output[i], "RenderMarkdownMath" } }
          end
          marks[#marks + 1] = {
            conceal = "virtual_lines",
            start_row = start_row,
            start_col = 0,
            opts = {
              virt_lines = lines,
              virt_lines_above = true,
            },
          }
        end

        if center < #output then
          local lines = {}
          for i = center + 1, #output do
            lines[#lines + 1] = { { output[i], "RenderMarkdownMath" } }
          end
          marks[#marks + 1] = {
            conceal = "virtual_lines",
            start_row = start_row,
            start_col = 0,
            opts = { virt_lines = lines },
          }
        end
      else
        if cursor_row and cursor_row >= start_row and cursor_row <= end_row then
          goto continue
        end

        local output_offset = math.max(math.floor((source_height - #output) / 2), 0)

        for row = start_row, end_row do
          local line = vim.api.nvim_buf_get_lines(ctx.buf, row, row + 1, false)[1] or ""
          local output_line = output[row - start_row - output_offset + 1]
          local opts = {
            end_row = row,
            end_col = row == end_row and end_col or #line,
            conceal = "",
          }
          if output_line then
            opts.virt_text = { { output_line, "RenderMarkdownMath" } }
            opts.virt_text_pos = "inline"
          end
          marks[#marks + 1] = {
            conceal = "latex",
            start_row = row,
            start_col = row == start_row and start_col or 0,
            opts = opts,
          }
        end
      end
    end

    ::continue::
  end

  return marks
end

return {
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "catppuccin-macchiato",  -- tokyonight-night, retrobox, catppuccin-macchiato
    },
  },
  {
    "mg979/vim-visual-multi",
    init = function()
      -- 在插件加载后配置键映射
      vim.g.VM_maps = {
        ["Find Under"] = "<C-n>",
        ["Add Cursor Down"] = "<A-Down>",
        ["Find Subword Under"] = "<C-n>",
        ["Add Cursor Up"] = "<A-Up>",
      }
    end,
  },
  { "tpope/vim-surround" },
  {
    "chrisgrieser/nvim-spider",
    keys = {
      { "w", "<cmd>lua require('spider').motion('w')<CR>", mode = { "n", "o", "x" } },
      { "e", "<cmd>lua require('spider').motion('e')<CR>", mode = { "n", "o", "x" } },
      { "b", "<cmd>lua require('spider').motion('b')<CR>", mode = { "n", "o", "x" } },
      { "ge", "<cmd>lua require('spider').motion('ge')<CR>", mode = { "n", "o", "x" } },
    },
  },
  {
    "dnlhc/glance.nvim",
    cmd = "Glance",
    keys = {
      { "gD", "<cmd>Glance definitions<cr>", desc = "Glance Definitions" },
      { "gR", "<cmd>Glance references<cr>", desc = "Glance References" },
      { "gY", "<cmd>Glance type_definitions<cr>", desc = "Glance Type Definitions" },
      { "gM", "<cmd>Glance implementations<cr>", desc = "Glance Implementations" },
    },
  },
  {
    "cappyzawa/trim.nvim",
    opts = {},
  },
  {
    "folke/flash.nvim",
    keys = {
      { "S", mode = { "x", "o", "n" }, false },
    },
  },
  {
    "hedyhli/outline.nvim",
    lazy = true,
    cmd = { "Outline", "OutlineOpen" },
    keys = { -- Example mapping to toggle outline
      { "<leader>o", "<cmd>Outline<CR>", desc = "Toggle outline" },
    },
    opts = {
      -- Your setup opts here
    },
  },
  {
    "stevearc/conform.nvim",
    dependencies = {
      "rhysd/fixjson",
    },
    optional = true,
    opts = {
      formatters_by_ft = {
        ["python"] = { "black", "isort" },
        ["json"] = { "fixjson" },
      },
    },
  },
  -- {
  --   "nvim-neo-tree/neo-tree.nvim",
  --   opts = {
  --     filesystem = {
  --       watch_dir = false,
  --       enable_refresh_on_write = false,
  --     },
  --   },
  -- },
  {
    "saghen/blink.cmp",
    -- build = "cargo build --release",
    opts = {
      keymap = {
        ["<C-k>"] = { "select_prev", "fallback" },
        ["<C-j>"] = { "select_next", "fallback" },
        ["<Tab>"] = { "select_and_accept", "fallback" },
      },
    },
  },
  {
    "ibhagwan/fzf-lua",
    opts = {
      lsp_references = {
        jump_to_single_result = true,
        silent = true,
      },
    },
  },
  {
    "sphamba/smear-cursor.nvim",
    enabled = true,
    opts = {
      -- Smear cursor when switching buffers or windows.
      smear_between_buffers = true,

      -- Smear cursor when moving within line or to neighbor lines.
      -- Use `min_horizontal_distance_smear` and `min_vertical_distance_smear` for finer control
      smear_between_neighbor_lines = true,

      -- Draw the smear in buffer space instead of screen space when scrolling
      scroll_buffer_space = true,

      -- Set to `true` if your font supports legacy computing symbols (block unicode symbols).
      -- Smears and particles will look a lot less blocky.
      legacy_computing_symbols_support = true,
      never_draw_over_target = true,

      smear_to_cmd = false,
      -- Smear cursor in insert mode.
      -- See also `vertical_bar_cursor_insert_mode` and `distance_stop_animating_vertical_bar`.
      smear_insert_mode = true,
      stiffness = 1.0,
      trailing_stiffness = 0.5,
      distance_stop_animating = 0.5,
    },
  },
  {
    "MeanderingProgrammer/render-markdown.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    ft = { "markdown" },
    opts = {
      change_events = { "CursorMoved", "CursorMovedI" },
      latex = { enabled = false },
      custom_handlers = {
        markdown_inline = {
          extends = true,
          parse = parse_latex_blocks,
        },
      },
    },
  },
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      local parsers = { "markdown", "markdown_inline", "latex", "html" }

      opts.ensure_installed = opts.ensure_installed or {}
      if opts.ensure_installed == "all" then
        return
      end

      for _, parser in ipairs(parsers) do
        if not vim.tbl_contains(opts.ensure_installed, parser) then
          table.insert(opts.ensure_installed, parser)
        end
      end
    end,
  },
  -- {
  --   "iamcco/markdown-preview.nvim",
  --   init = function()
  --     vim.g.mkdp_echo_preview_url = 1
  --     vim.g.mkdp_port = "8879"
  --   end,
  --   cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
  --   ft = { "markdown" },
  --   -- if markdown-preview does not work, maybe need to call `call mkdp#util#install` again in nvim
  --   build = function()
  --     vim.fn["mkdp#util#install"]()
  --   end,
  -- },
  -- { "lukas-reineke/virt-column.nvim",
  --   opts = {},
  -- },
}
