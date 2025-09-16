local M = {}

-- Config
M.config = {
  api_key = vim.env.OPENAI_API_KEY,
  model = "kimi-k2-turbo-preview",
  base_url = "https://api.moonshot.cn/v1",
  max_tokens = 1000,
  temperature = 0.3,
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

local ns = vim.api.nvim_create_namespace("inline_translate_e2c")
local cache = {} -- key: action:sha256(text) -> output

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO)
end

-- HTTP request
local function make_openai_request(messages, callback)
  if not M.config.api_key or M.config.api_key == "" then
    notify("OPENAI_API_KEY not set", vim.log.levels.ERROR)
    return
  end

  local body_tbl = {
    model = M.config.model,
    messages = messages,
    max_tokens = M.config.max_tokens,
    temperature = M.config.temperature,
  }
  local body = (vim.json and vim.json.encode(body_tbl)) or vim.fn.json_encode(body_tbl)

  vim.system({
    "curl", "-s", "-X", "POST", M.config.base_url .. "/chat/completions",
    "-H", "Authorization: Bearer " .. M.config.api_key,
    "-H", "Content-Type: application/json",
    "-d", body,
  }, { text = true }, function(res)
    if res.code ~= 0 then
      notify("HTTP error: " .. (res.stderr or res.code), vim.log.levels.ERROR)
      return
    end
    local ok, decoded = pcall(function()
      return (vim.json and vim.json.decode or vim.fn.json_decode)(res.stdout)
    end)
  if not ok then
    notify("Parse error. Raw response:\n" .. (res.stdout or ""), vim.log.levels.ERROR)
    return
  end
  if decoded and decoded.error then
    local emsg = decoded.error.message or vim.inspect(decoded.error)
    notify("API error: " .. emsg .. "\nRequest body:\n" .. body .. "\nRaw response:\n" .. (res.stdout or ""), vim.log.levels.ERROR)
    return
  end
  local choice = decoded and decoded.choices and decoded.choices[1]
  local content = choice and choice.message and choice.message.content
  if content then
    callback(content)
  else
    notify("Invalid response. Request body:\n" .. body .. "\nRaw response:\n" .. (res.stdout or ""), vim.log.levels.ERROR)
end
  end)
end

-- Actions
local function build_messages(action, text)
  if action == "translate" then
    return {
      { role = "system", content = "You are a precise English to Simplified Chinese technical translator. Output only the Chinese translation. Preserve code blocks and inline code unchanged." },
      { role = "user", content = "Translate to Simplified Chinese:\n\n" .. text },
    }
  elseif action == "explain" then
    return {
      { role = "system", content = "You are an expert software engineer. Explain the provided code in concise Simplified Chinese bullet points. Preserve code blocks and identifiers. Include: purpose, flow, pitfalls, improvement suggestions." },
      { role = "user", content = "请解释下面的代码：\n\n" .. text },
    }
  end
end

local function run_action(action, text, callback)
  local messages = build_messages(action, text)
  if not messages then
    notify("Unknown action: " .. tostring(action), vim.log.levels.ERROR)
    return
  end
  make_openai_request(messages, callback)
end

local function get_visual_selection()
  -- 保存当前模式（可能是 v / V / <C-v>）
  local mode = vim.fn.mode()

  -- 取可视标记位置
  local _, ls, cs = unpack(vim.fn.getpos("'<"))
  local _, le, ce = unpack(vim.fn.getpos("'>"))

  if ls == 0 or le == 0 then return end

  -- 规范顺序
  if le < ls or (le == ls and ce < cs) then
    ls, le = le, ls
    cs, ce = ce, cs
  end

  -- 在字符/块模式下，Vim 的 ce 是“选区后一个列”，但对 linewise (V) 我们想取整行
  if mode == "v" or mode == "\22" then
    ce = ce -- nvim_buf_get_text 终列本来就是“后一个列”，无需 -1
  elseif mode == "V" then
    cs = 1
    ce = vim.fn.col({ le, "$" }) - 1
  end

  -- 使用 nvim_buf_get_text：结束列是“后一个列”
  local text = vim.api.nvim_buf_get_text(0, ls - 1, cs - 1, le - 1, ce, {})
  if not text or #text == 0 then return end
  return table.concat(text, "\n"), le - 1
end


function M.clear()
  vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
end


local function show_output(end_line, kind, text)
  M.clear()
  local icon = (kind == "explain") and " " or " "
  local lines = vim.split(text, "\n", { plain = true })
  local virt_lines = {}
  for _, l in ipairs(lines) do
    table.insert(virt_lines, { { icon .. l, "Comment" } })
  end
  vim.api.nvim_buf_set_extmark(0, ns, end_line, 0, {
    virt_lines = virt_lines,
    virt_lines_above = false,
  })
end

-- Legacy: only translate (kept for compatibility)
function M.translate_inline()
  local sel, el = get_visual_selection()
  if not sel or sel == "" then
    notify("No visual selection", vim.log.levels.WARN)
    return
  end
  local hash = (vim.fn.sha256 and vim.fn.sha256(sel)) or sel
  local key = "translate:" .. hash
  if cache[key] then
    show_output(el, "translate", cache[key])
    notify("Cached 英→中")
    return
  end
  run_action("translate", sel, function(out)
    vim.schedule(function()
      cache[key] = out
      show_output(el, "translate", out)
      notify("英→中 内联完成")
    end)
  end)
end

-- Panel to choose action
function M.panel()
  local sel, el = get_visual_selection()
  if not sel or sel == "" then
    notify("未选择文本", vim.log.levels.WARN)
    return
  end
  local choices = {
    { label = "翻译 (英→中)", action = "translate" },
    { label = "解释代码", action = "explain" },
  }
  vim.ui.select(choices, {
    prompt = "选择操作",
    format_item = function(it) return it.label end,
  }, function(choice)
    if not choice then return end
    local hash = (vim.fn.sha256 and vim.fn.sha256(sel)) or sel
    local key = choice.action .. ":" .. hash
    if cache[key] then
      show_output(el, choice.action, cache[key])
      notify("缓存: " .. choice.label)
      return
    end
    run_action(choice.action, sel, function(out)
      vim.schedule(function()
        cache[key] = out
        show_output(el, choice.action, out)
        notify(choice.label .. " 完成")
      end)
    end)
  end)
end


function M.init(opts)
  M.setup(opts)
end

-- Lazy plugin spec
return {
  {
    name = "inline-translate",
    dir = vim.fn.stdpath("config") .. "/lua/plugins/custom",
    dev = true,
    keys = {
      { "<leader>tc", function() M.panel() end, mode = "v", desc = "翻译/解释 面板" },
      { "<leader>tC", function() M.clear() end, desc = "清除翻译" },
    },
    opts = {
      api_key = vim.env.OPENAI_API_KEY,
      model = "kimi-k2-turbo-preview",
      base_url = "https://api.moonshot.cn/v1",
      max_tokens = 1000,
      temperature = 0.3,
    },
    config = function(_, opts)
      M.init(opts)
    end,
  },
}

