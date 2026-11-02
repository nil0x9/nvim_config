local M = {}

M.config = {
  cmd = "jq",
  filter = ".",
  width = 0.8,
  height = 0.8,
  border = "rounded",
  wrap = true,
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

local state = { win = nil, buf = nil, source = nil, filter = nil }

local function close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
end

-- 取预览源文本：visual 模式用选区，normal 模式用光标所在行
local function get_source(mode)
  if mode == "v" then
    local s = vim.fn.getpos("v")
    local e = vim.fn.getpos(".")
    if s[2] > e[2] or (s[2] == e[2] and s[3] > e[3]) then
      s, e = e, s
    end
    local lines = vim.api.nvim_buf_get_text(0, s[2] - 1, s[3] - 1, e[2] - 1, e[3], {})
    return table.concat(lines, "\n")
  end
  return vim.api.nvim_get_current_line()
end

local function render(lines, failed)
  local buf = state.buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    buf = vim.api.nvim_create_buf(false, true)
    state.buf = buf
    vim.bo[buf].bufhidden = "wipe"
    vim.keymap.set("n", "q", close, { buffer = buf, nowait = true })
    vim.keymap.set("n", "<Esc>", close, { buffer = buf, nowait = true })
    vim.keymap.set("n", "f", function()
      M.prompt_filter()
    end, { buffer = buf, nowait = true, desc = "Change jq filter" })
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
  vim.bo[buf].filetype = failed and "text" or "json"

  local title = " jq " .. state.filter .. " "
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_config(state.win, { title = title })
    return
  end

  local width = math.floor(vim.o.columns * M.config.width)
  local height = math.floor(vim.o.lines * M.config.height)
  state.win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = M.config.border,
    title = title,
    title_pos = "center",
  })
  vim.wo[state.win].wrap = M.config.wrap
  vim.wo[state.win].linebreak = M.config.wrap
  vim.wo[state.win].cursorline = true
  vim.wo[state.win].number = true
  vim.wo[state.win].conceallevel = 0
end

local function run()
  if vim.fn.executable(M.config.cmd) ~= 1 then
    vim.notify(M.config.cmd .. " not found in PATH", vim.log.levels.ERROR)
    return
  end
  if vim.trim(state.source or "") == "" then
    vim.notify("Nothing to preview", vim.log.levels.WARN)
    return
  end

  vim.system({ M.config.cmd, state.filter }, { stdin = state.source, text = true }, function(res)
    vim.schedule(function()
      local failed = res.code ~= 0
      local out = failed and (res.stderr or "") or (res.stdout or "")
      local lines = vim.split(out:gsub("\n$", ""), "\n", { plain = true })
      render(lines, failed)
    end)
  end)
end

--- 预览光标所在行（或可视选区）的 JSON。
---
--- Args:
---     filter (string|nil): jq 过滤表达式，默认 `.`。
---     mode (string|nil): `"v"` 表示取可视选区，其余取当前行。
function M.preview(filter, mode)
  state.source = get_source(mode)
  state.filter = (filter and vim.trim(filter) ~= "") and filter or M.config.filter
  run()
end

--- 对已打开的预览内容输入新的 jq 过滤表达式并重新渲染。
function M.prompt_filter()
  vim.ui.input({ prompt = "jq filter: ", default = state.filter or M.config.filter }, function(input)
    if not input or vim.trim(input) == "" then
      return
    end
    state.filter = input
    run()
  end)
end

return {
  {
    name = "jq-preview",
    dir = vim.fn.stdpath("config") .. "/lua/plugins/custom",
    dev = true,
    keys = {
      {
        "<leader>jq",
        function()
          M.preview()
        end,
        desc = "jq: preview JSON on current line",
      },
      {
        "<leader>jq",
        function()
          M.preview(nil, "v")
        end,
        mode = "v",
        desc = "jq: preview selected JSON",
      },
      {
        "<leader>jf",
        function()
          state.source = get_source()
          vim.ui.input({ prompt = "jq filter: ", default = M.config.filter }, function(input)
            if not input or vim.trim(input) == "" then
              return
            end
            state.filter = input
            run()
          end)
        end,
        desc = "jq: preview current line with custom filter",
      },
    },
    config = function(_, opts)
      M.setup(opts)
      vim.api.nvim_create_user_command("JqPreview", function(o)
        M.preview(o.args, o.range > 0 and "v" or nil)
      end, { nargs = "*", range = true, desc = "Preview JSON under cursor via jq" })
    end,
  },
}
