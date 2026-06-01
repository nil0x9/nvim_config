-- -- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
-- 将选定内容复制到系统剪贴板
vim.api.nvim_set_keymap('v', 'Y', '"+y', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', 'Y', '"+y', { noremap = true, silent = true })
-- 在普通模式下按 Ctrl+a 全选
vim.api.nvim_set_keymap('n', '<C-a>', 'ggVG', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', 'wdt', '<cmd>windo diffthis<cr>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', 'wdo', '<cmd>windo diffoff<cr>', { noremap = true, silent = true })

vim.api.nvim_set_keymap("i", "jj", "<Esc>", { noremap = true, silent = true })
vim.keymap.set("n", "<Leader>//", [[:%s/<C-r><C-w>//gn<CR>]], { desc = "Count word under cursor" })
-- 快速选中当前行
vim.keymap.set('n', '<leader>vl', '^vg_', { desc = 'Select line content (no whitespace)' })

-- Helper: 获取当前文件相对于项目根目录的路径
-- Helper: 获取当前文件相对于项目根目录的路径
local function get_relative_filepath()
  local full_path = vim.api.nvim_buf_get_name(0)
  if full_path == "" then
    return ""
  end

  -- 获取项目根目录（LazyVim 会自动处理非 Git 项目情况）
  local root
  local ok, util = pcall(require, "lazyvim.util")
  if ok then
    root = util.root()  -- 这里总是返回有效路径（Git 根目录或 cwd）
  else
    root = vim.loop.cwd()
  end

  -- 计算相对于项目根目录的路径
  local abs_file = vim.fn.fnamemodify(full_path, ":p")
  local abs_root = vim.fn.fnamemodify(root, ":p")
  
  -- 确保 root 路径格式一致
  abs_root = string.gsub(abs_root, "\\", "/")
  abs_file = string.gsub(abs_file, "\\", "/")
  
  -- 如果 root 不以 / 结尾，添加 /
  if not abs_root:match("/$") then
    abs_root = abs_root .. "/"
  end

  -- 如果文件在项目根目录下
  if abs_file:sub(1, #abs_root) == abs_root then
    local rel_path = abs_file:sub(#abs_root + 1)
    return vim.fs.normalize(rel_path)
  end
  
  -- 如果不在项目根目录下，返回相对于 cwd 的路径
  return vim.fn.fnamemodify(full_path, ":.")
end

-- Normal 模式：复制 "path/to/file:L123"
vim.keymap.set('n', '<Leader>rl', function()
  local line_num = vim.api.nvim_win_get_cursor(0)[1]
  local rel_path = get_relative_filepath()
  if rel_path == "" then
    vim.notify("Failed to get relative path", vim.log.levels.WARN)
    return
  end
  local text = rel_path .. ":L" .. line_num
  vim.fn.setreg('+', text)
  vim.notify('Yanked: ' .. text, { title = "Line Number" })
end, { desc = 'Copy file:Lline to + register' })

-- Visual 模式：复制 "path/to/file:L123-125"
vim.keymap.set('v', '<Leader>rl', function()
  local start_line = vim.fn.line('v')
  local end_line = vim.fn.line('.')
  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end
  local rel_path = get_relative_filepath()
  if rel_path == "" then
    vim.notify("Failed to get relative path", vim.log.levels.WARN)
    return
  end
  local text = rel_path .. ":L" .. start_line .. (start_line == end_line and "" or "-" .. end_line)
  vim.fn.setreg('+', text)
  vim.notify('Yanked: ' .. text, { title = "Line Range" })
end, { desc = 'Copy file:Lstart-end to + register' })

local function parse_file_line_reference(ref)
  ref = vim.trim(ref)

  local path, line = ref:match("^(.+):L(%d+)%-%d+$")
  if not path then
    path, line = ref:match("^(.+):L(%d+)$")
  end

  line = tonumber(line)
  if not path or not line or line < 1 then
    error("Expected format: path/to/file:L123 or path/to/file:L123-456", 0)
  end

  return path, line
end

local function get_file_line_root()
  local ok, util = pcall(require, "lazyvim.util")
  if ok then
    return util.root()
  end

  return vim.loop.cwd()
end

local function resolve_file_line_path(path)
  if path:match("^/") or path:match("^~") then
    return vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
  end

  return vim.fs.normalize(vim.fs.joinpath(get_file_line_root(), path))
end

local function open_file_line_reference(ref)
  local path, line = parse_file_line_reference(ref)
  local abs_path = resolve_file_line_path(path)
  local stat = (vim.uv or vim.loop).fs_stat(abs_path)

  if not stat then
    error("File does not exist: " .. path, 0)
  end

  if stat.type ~= "file" then
    error("Not a file: " .. path, 0)
  end

  local ok, lines = pcall(vim.fn.readfile, abs_path, "", line)
  if not ok then
    error("Failed to read file: " .. path, 0)
  end

  if #lines < line then
    error(("Line %d does not exist in %s (%d lines)"):format(line, path, #lines), 0)
  end

  vim.cmd.edit(vim.fn.fnameescape(abs_path))
  vim.api.nvim_win_set_cursor(0, { line, 0 })
  vim.cmd("normal! zv")
end

local function prompt_file_line_reference()
  vim.ui.input({
    prompt = "File line: ",
    completion = "file",
  }, function(input)
    if not input or vim.trim(input) == "" then
      return
    end

    open_file_line_reference(input)
  end)
end

vim.api.nvim_create_user_command("GoToFileLine", function(opts)
  if opts.args == "" then
    prompt_file_line_reference()
    return
  end

  open_file_line_reference(opts.args)
end, {
  nargs = "*",
  complete = "file",
  desc = "Open path:Lline or path:Lstart-end",
})

vim.keymap.set("n", "<leader>fl", "<cmd>GoToFileLine<cr>", { desc = "Open file:Lline prompt" })

-- -- 复制当前行号到系统剪贴板（Normal 模式）
-- vim.keymap.set('n', '<Leader>ln', function()
--   local line_num = vim.api.nvim_win_get_cursor(0)[1] -- 获取当前行号
--   vim.fn.setreg('+', tostring(line_num)) -- 复制到系统剪贴板寄存器
--   vim.notify('Yanked line number: ' .. line_num) -- 显示提示
-- end, { desc = 'Copy line number to register +' })
--
-- -- 复制选中范围的行号范围到系统剪贴板（Visual 模式）
-- vim.keymap.set('v', '<Leader>ln', function()
--   local start_line = vim.fn.line('v') -- 获取选择起始行
--   local end_line = vim.fn.line('.')   -- 获取选择结束行
--   -- 确保 start_line 是较小的行号
--   if start_line > end_line then
--     start_line, end_line = end_line, start_line
--   end
--   -- 构建格式：起始行-结束行
--   local range_str = tostring(start_line) .. '-' .. tostring(end_line)
--   vim.fn.setreg('+', range_str) -- 复制到系统剪贴板寄存器
--   vim.notify('Yanked line numbers: ' .. range_str) -- 显示提示
-- end, { desc = 'Copy line numbers to register +' })
--

local function copy_file_path_to_clipboard()
  local file_path = vim.fn.expand('%:p')
  vim.fn.setreg('+', file_path)
  print("File path copied to clipboard: " .. file_path)
end

vim.keymap.set("n", "<leader>cp", copy_file_path_to_clipboard)

local function copy_file_name_to_clipboard()
  local file_path = vim.fn.expand('%:t')
  vim.fn.setreg('+', file_path)
  print("File filename copied to clipboard: " .. file_path)
end
vim.keymap.set("n", "<leader>cpp", copy_file_name_to_clipboard)

-- 复制当前文件的相对路径到系统剪贴板
vim.keymap.set('n', '<leader>rf', function()
  local rel_path = get_relative_filepath()
  if rel_path ~= "" then
    vim.fn.setreg('+', rel_path)
    vim.notify('Yanked relative path: ' .. rel_path, { title = "Relative Path" })
  else
    vim.notify("Failed to get relative path", vim.log.levels.WARN)
  end
end, { desc = 'Copy relative filepath to + register' })

local function toggle_neotree()
 vim.cmd('Neotree show')
end

-- vim.keymap.set('n', '<leader>to', '<cmd>Neotree show<CR>')
-- vim.keymap.set('n', '<leader>tq', '<cmd>Neotree close<CR>')
-- vim.keymap.set("n", "<leader>cp", copy_file_path_to_clipboard)

-- vim.keymap.set("n", "<leader>wd", toggle_diff_mode)

-- 将 <leader>bd 映射为关闭当前 buffer 而不关闭窗口
-- vim.api.nvim_set_keymap('n', '<leader>bd', ':b# | bd #<CR>', { noremap = true, silent = true })
-- Buffer operations
vim.keymap.set("n", "<leader>bd", function()
  -- 删除当前缓冲区，同时清除跳转列表
  local current_bufnr = vim.api.nvim_get_current_buf() -- 获取当前缓冲区的编号

  local jumps_info = vim.fn.getjumplist()
  local jumplist = jumps_info[1]
  local last_jump_idx = jumps_info[2]

  local jumps_needed = 0 -- 记录需要执行 Ctrl-o 的次数

  -- vim.print(jumps_info)
  -- vim.print("current_bufnr = " .. current_bufnr .. ", current_jump_idx = " .. last_jump_idx)

  -- 从当前位置开始向前遍历跳转列表
  -- 注意：jumplist 是从最新到最旧排列的，但索引可能在中间
  -- 我们需要从 current_jump_idx 开始向前查找
  for i = last_jump_idx, 0, -1 do -- 从当前索引向前遍历
    -- vim.print("i = " .. i)
    if jumplist[i] then
      local jump_bufnr = jumplist[i].bufnr
      -- vim.print("bufnr = " .. jump_bufnr)

      -- 比较 bufnr，以确保是“不同”的 buffer
      if jump_bufnr ~= current_bufnr then
        jumps_needed = last_jump_idx + 1 - i -- 当前位置不在 jumplist 中，需要 +1
        break -- 找到第一个不同的文件，跳出循环
      end
    end
  end

  if jumps_needed ~= 0 then
    -- 找到了上一个不同的文件
    print("Found previous file in jump list. Performing " .. jumps_needed .. " jumps.")

    local function perform_jumps_and_bd(count)
      if count > 0 then
        vim.api.nvim_input("<C-o>")
        vim.defer_fn(function()
          perform_jumps_and_bd(count - 1)
        end, 0)
      else
        vim.cmd("bd #")
      end
    end

    perform_jumps_and_bd(jumps_needed)
  else
    -- 如果没有找到上一个不同的文件，则直接删除当前缓冲区
    print("No previous different file found in jump list. Deleting current buffer.")
    vim.cmd("bd")
  end
  -- vim.print("==== Finished ====")
end, { noremap = true, silent = true })


-- Fzflua 相关的配置
vim.api.nvim_set_keymap('n', '<leader>fv', '<cmd>FzfLua grep<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<leader>fh', '<cmd>FzfLua oldfiles<CR>', { noremap = true, silent = true })

-------------------------------- 把 buffer 移动到左边窗口 ------------------------------
local function move_buffer_to_left_window()
  -- 获取当前缓冲区和窗口ID
  local current_buffer = vim.fn.bufnr('%')
  local previous_buffer = vim.fn.bufnr('#')
  local current_window = vim.fn.winnr()
  vim.cmd('buffer ' .. previous_buffer)

  -- 切换到左边的窗口，如果没有则创建
  if vim.fn.winnr('h') == current_window then
    vim.cmd('vsplit')
  else
    vim.cmd('wincmd h')
  end
  -- 获取左边窗口的缓冲区ID

  local left_buffer = vim.fn.bufnr('%')

  -- 在左边窗口显示当前缓冲区
  vim.cmd('buffer ' .. current_buffer)
  
  -- 切换回原窗口并显示之前的缓冲区
  vim.cmd(current_window .. 'wincmd w')
  vim.cmd('buffer ' .. left_buffer)
end

local function move_buffer_to_right_window()
  -- 获取当前缓冲区和窗口ID
  local current_buffer = vim.fn.bufnr('%')
  local previous_buffer = vim.fn.bufnr('#')
  local current_window = vim.fn.winnr()
  vim.cmd('buffer ' .. previous_buffer)
  -- 切换到左边的窗口，如果没有则创建
  if vim.fn.winnr('l') == current_window then
    vim.cmd('vsplit')
  else
    vim.cmd('wincmd l')
  end

  -- 获取左边窗口的缓冲区ID
  local right_buffer = vim.fn.bufnr('%')

  -- 在左边窗口显示当前缓冲区
  vim.cmd('buffer ' .. current_buffer)

  -- 切换回原窗口并显示之前的缓冲区
  vim.cmd(current_window .. 'wincmd w')
  vim.cmd('buffer ' .. right_buffer)
end

vim.keymap.set("n", "<leader>mbl", move_buffer_to_left_window)
vim.keymap.set("n", "<leader>mbr", move_buffer_to_right_window)
-------------------------------- 把 buffer 移动到左边窗口 ------------------------------

-- vim.keymap.set('v', '<Tab>', '>gv')
-- vim.keymap.set('v', '<S-Tab>', '<gv')
-- vim.keymap.set('n', '<Tab>', '>>')
-- vim.keymap.set('n', '<S-Tab>', '<<')

--------------------------------------------------------
-- 解绑 <Alt-j> 快捷键
local opts = { noremap = true, silent = true }
vim.api.nvim_del_keymap('n', '<A-j>')  -- 正常模式
vim.api.nvim_del_keymap('v', '<A-j>')  -- 可视模式
vim.api.nvim_del_keymap('n', '<A-k>')  -- 正常模式
vim.api.nvim_del_keymap('v', '<A-k>')  -- 可视模式



-- 使用 Ctrl+Shift+j/k 来移动代码行（Mac 兼容性更好）
vim.api.nvim_set_keymap('v', '<C-S-k>', ":m '<-2<CR>gv=gv", opts)
vim.api.nvim_set_keymap('n', '<C-S-k>', "<cmd>m .-2<CR>==", opts)
vim.api.nvim_set_keymap('v', '<C-S-j>', ":m '>+1<CR>gv=gv", opts)
vim.api.nvim_set_keymap('n', '<C-S-j>', "<cmd>m .+1<CR>==", opts)

-- 保留原来的 Alt+j/k 映射（如果终端支持 Meta 键）
vim.api.nvim_set_keymap('v', '<M-k>', ":m '<-2<CR>gv=gv", opts)
vim.api.nvim_set_keymap('n', '<M-k>', "<cmd>m .-2<CR>==", opts)
vim.api.nvim_set_keymap('v', '<M-j>', ":m '>+1<CR>gv=gv", opts)
vim.api.nvim_set_keymap('n', '<M-j>', "<cmd>m .+1<CR>==", opts)



--------------------------------------------------------
-- 重新绑定 C-o 到 Alt-h
-- vim.api.nvim_set_keymap('n', '<A-h>', '<C-o>', { noremap = true, silent = true })
-- 重新绑定 C-i 到 Alt-l
-- vim.api.nvim_set_keymap('n', '<A-l>', '<C-i>', { noremap = true, silent = true })
--------------------------------------------------------
vim.keymap.del('n', '<leader>wd')  -- 关闭 leader wd 关闭 window 的功能
--------------------------------------------------------
local function switch_to_previous_buffer()
  -- Get the name of the previous buffer
  local prev_bufname = vim.fn.bufname('#')

  -- Check if the previous buffer is valid
  if prev_bufname ~= '' then
    -- Execute the buffer switch
    vim.cmd('b#')

    -- Reload the buffer to ensure it is in the buffer list
    vim.cmd('edit ' .. prev_bufname)
  else
    print("No previous buffer to switch to.")
  end
end

vim.keymap.set('n', '<leader>b#', switch_to_previous_buffer, { noremap = true, silent = true, desc="Reopen the closed buffer" })
--------------------------------------------------------
local function DiffFormat()

  local ignore_filetypes = { "lua" }
  if vim.tbl_contains(ignore_filetypes, vim.bo.filetype) then
    vim.notify("range formatting for " .. vim.bo.filetype .. " not working properly.")
    return
  end

  local hunks = require("gitsigns").get_hunks()
  if hunks == nil then
    return
  end

  local format = require("conform").format

  local function format_range()
    if next(hunks) == nil then
      vim.notify("done formatting git hunks", "info", { title = "formatting" })
      return
    end
    local hunk = nil
    while next(hunks) ~= nil and (hunk == nil or hunk.type == "delete") do
      hunk = table.remove(hunks)
    end

    if hunk ~= nil and hunk.type ~= "delete" then
      local start = hunk.added.start
      local last = start + hunk.added.count
      -- nvim_buf_get_lines uses zero-based indexing -> subtract from last
      local last_hunk_line = vim.api.nvim_buf_get_lines(0, last - 2, last - 1, true)[1]
      local range = { start = { start, 0 }, ["end"] = { last - 1, last_hunk_line:len() } }
      format({ range = range, async = true, lsp_fallback = true }, function()
        vim.defer_fn(function()
          format_range()
        end, 1)
      end)
    end
  end

  format_range()
end

local function Format()
  local conform = require('conform')
  conform.format()
end

vim.api.nvim_create_user_command('DiffFormat', DiffFormat, { nargs = 0, desc = "Diff Format Current File"})
vim.api.nvim_create_user_command('Format', Format, { nargs = 0, desc = "Format Current File"})


local function toggle_wrap()
    if vim.wo.wrap then
        vim.wo.wrap = false
    else
        vim.wo.wrap = true
    end
end

vim.keymap.set('n', '<A-z>', toggle_wrap)
vim.keymap.set('n', '<leader>tf', "<cmd>tabnext<CR>")
vim.keymap.set('n', '<leader>tb', "<cmd>tabprevious<CR>")
vim.keymap.set('n', '<leader>tc', "<cmd>tabclose<CR>")
vim.keymap.set('n', '<leader>tn', "<cmd>tabnew<CR>")

-- 在你的 init.lua 或相关配置文件中添加以下内容
vim.api.nvim_set_keymap('v', '<leader>ss', [[:lua SearchInVisualSelection()<CR>]], { noremap = true, silent = true })

-- 定义 SearchInVisualSelection 函数
function SearchInVisualSelection()
  -- 获取 Visual Mode 下选中的文本
  local start_pos = vim.fn.getpos("'<")  -- 获取选中区域的起始位置
  local end_pos = vim.fn.getpos("'>")    -- 获取选中区域的结束位置
  local selected_text = vim.fn.getreg('v')  -- 获取选中的文本内容

  -- 创建一个弹窗输入框 (这是一种非阻塞方式)
  vim.ui.input({
    prompt = 'Enter search term: ',
    default = selected_text,
    completion = "word",
  }, function(input)
    -- 如果用户输入了内容
    if input and input ~= "" then
      -- 恢复原来的 Visual 模式选中状态
      vim.fn.setpos("'<", start_pos)
      vim.fn.setpos("'>", end_pos)

      -- 执行搜索，并使用 \%V 限制搜索范围到选中的区域
      vim.fn.search('\\%V' .. vim.fn.escape(input, "/\\"))
    end
  end)
end

pcall(vim.keymap.del, 'n', '<c-/>')
pcall(vim.keymap.del, 't', '<c-/>')
pcall(vim.keymap.del, 'n', '<c-_>')
pcall(vim.keymap.del, 't', '<c-_>')
pcall(vim.keymap.del, 'n', '<leader>ft')
pcall(vim.keymap.del, 't', '<leader>ft')

-- 重新绑定到 ToggleTerm，使用 remap = true 来覆盖已有的映射
vim.keymap.set({'n', 'v', 'i', 't'}, '<c-/>', '<cmd>ToggleTerm<cr>', { noremap = true, silent = true, desc = "Toggle Terminal" })
vim.keymap.set({'n', 'v', 'i', 't'}, '<c-_>', '<cmd>ToggleTerm<cr>', { noremap = true, silent = true, desc = "Toggle Terminal" })
vim.keymap.set({'n', 'v', 't'}, '<leader>ft', '<cmd>ToggleTerm<cr>', { noremap = true, silent = true, desc = "Toggle Terminal" })



-- 快捷选中当前单词，不含下划线
vim.keymap.set('n', '<leader>vw', function()
    local original_iskeyword = vim.opt.iskeyword:get()
    vim.opt.iskeyword:remove('_')
    vim.cmd('normal! viw')
    vim.defer_fn(function()
        vim.opt.iskeyword = original_iskeyword
    end, 10)
end, { 
    desc = 'Select word (treat underscore as boundary)',
    silent = true 
})
