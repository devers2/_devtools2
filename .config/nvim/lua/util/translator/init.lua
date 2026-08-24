local M = {}

-- ===========================================================================================
-- [통합 번역기 전역 마스터 스위치]
-- false 로 설정하면 번역 엔진 및 모든 인터셉터가 즉시 비활성화되어 순정 Neovim으로 동작합니다.
-- 런타임 제어: :lua require('util.translator').enabled = false (또는 true)
-- ===========================================================================================
M.enabled = true

-- 1. 기본 검증 사전 (Git 형상관리 대상: lua/util/translator/dict.lua)
local base_dict = require('util.translator.dict')

-- 2. 런타임 동적 학습 캐시 (Git 형상관리 제외: _devtools2/data/translations/cache.json)
local cache_dir = _G.DEVTOOLS2_DIR .. '/data/translations'
local cache_file = cache_dir .. '/cache.json'

M._runtime_cache = {}
M._pending = {}
M._queue = {}
M._is_processing = false
M._registered_interceptors = {}

-- ===========================================================================================
-- [런타임 동적 캐시 로드 및 저장]
-- ===========================================================================================
function M.load_cache()
  vim.fn.mkdir(cache_dir, 'p')
  local f = io.open(cache_file, 'r')
  if f then
    local content = f:read('*all')
    f:close()
    local ok, parsed = pcall(vim.json.decode, content)
    if ok and type(parsed) == 'table' then
      M._runtime_cache = parsed
      return
    end
  end
  M._runtime_cache = {}
end

function M.save_cache()
  vim.fn.mkdir(cache_dir, 'p')
  local f = io.open(cache_file, 'w')
  if f then
    local ok, encoded = pcall(vim.json.encode, M._runtime_cache)
    if ok and encoded then
      f:write(encoded)
    end
    f:close()
  end
end

-- ===========================================================================================
-- [텍스트 유틸리티 및 포맷팅]
-- ===========================================================================================
function M.contains_korean(str)
  if not str or type(str) ~= 'string' then return false end
  for i = 1, #str do
    local b = string.byte(str, i)
    if b and b >= 224 and b <= 237 then return true end
  end
  return false
end

function M.format_display(ko, en)
  if not ko or ko == '' or ko == en then return en end
  if ko:find('「' .. vim.pesc(en) .. '」') then return ko end
  return string.format('%s 「%s」', ko, en)
end

-- ===========================================================================================
-- [정밀 판별기 1: 메뉴/액션 항목 검증 (is_translatable_menu_item)]
-- ===========================================================================================
function M.is_translatable_menu_item(str)
  if not str or type(str) ~= 'string' then return false end
  local t = vim.trim(str)

  -- 1) 기본 길이 및 문자 검사
  if #t < 4 or #t > 100 or t:sub(1, 1) == ':' then return false end
  if M.contains_korean(t) then return false end

  -- 2) 공백이 없는 단일 단어/식별자 제외 (예: 'main', 'test', 'no', 'jdtls')
  if not t:find('%s') then return false end

  -- 3) 파일 경로, 디렉터리, 확장자 제외 (/src/main/..., lua/util/..., Foo.java, pom.xml)
  if t:match('^/') or t:match('^%./') or t:match('^%.%./') or t:match('^~') or t:match('^[a-zA-Z]:\\') then
    return false
  end
  if select(2, t:gsub('/', '')) >= 2 or t:find('\\') or t:match('%.[a-zA-Z0-9]+$') then
    return false
  end
  if t:find('/') and (not t:find('%s') or t:match('%.[a-zA-Z0-9]+')) then
    return false
  end

  -- 4) Java/프로그래밍 FQCN 패키지 및 클래스명 제외 (so.goono.GoonoELNApplication 등)
  if t:match('[%w_]+%.[%w_]+%.[%w_]+') then return false end

  -- 5) DAP Launch 설정 및 콜론(:) 기반 데이터 구조 제외 (Launch goono-eln: ..., port: 5005 등)
  if t:find(':') then return false end

  -- 6) Git 커밋 해시 / 포인터 제외 (a7f8c9b ..., HEAD -> ...)
  if t:match('^%x%x%x%x%x%x%x%s') or t:find('%->') then return false end

  -- 7) 코드 구문 및 연산자 제외 (; == !=)
  if t:find(';') or t:find('==') or t:find('!=') then return false end

  return true
end

-- ===========================================================================================
-- [정밀 판별기 2: 알림/메시지 검증 (is_translatable_sentence)]
-- ===========================================================================================
function M.is_translatable_sentence(str)
  if not str or type(str) ~= 'string' then return false end
  local t = vim.trim(str)

  if not t:find('%s') then return false end
  if #t < 6 or #t > 150 or t:sub(1, 1) == ':' then return false end
  if M.contains_korean(t) then return false end

  if t:match('[%w_]+%.[%w_]+%.[%w_]+') then return false end
  if t:match('^Launch%s+') and t:find(':') then return false end
  if t:find('/') or t:find('\\') or t:match('%.[a-zA-Z0-9]+$') then return false end
  if t:match('^[%-%*]%s+%*%*') or t:match('^diff%s+') then return false end

  return true
end

-- ===========================================================================================
-- [비동기 실시간 번역 워커]
-- ===========================================================================================
local _python_trans_script = [=[
import sys, json, urllib.request, urllib.parse

def translate(text):
    text = text.strip()
    if not text:
        return ""
    try:
        url = 'https://clients5.google.com/translate_a/t?client=dict-chrome-ex&sl=en&tl=ko&q=' + urllib.parse.quote(text)
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=3) as resp:
            data = json.loads(resp.read().decode('utf-8'))
            if isinstance(data, list) and len(data) > 0 and data[0]:
                return str(data[0])
    except Exception:
        pass
    try:
        url = 'https://api.mymemory.translated.net/get?langpair=en|ko&q=' + urllib.parse.quote(text)
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=4) as resp:
            data = json.loads(resp.read().decode('utf-8'))
            trans = data.get('responseData', {}).get('translatedText', '')
            if trans and not trans.startswith('MYMEMORY WARNING'):
                return str(trans)
    except Exception:
        pass
    return ""

try:
    input_data = json.loads(sys.stdin.read())
    results = {}
    for item in input_data:
        res = translate(item)
        if res:
            results[item] = res
    print(json.dumps(results, ensure_ascii=False))
except Exception:
    print("{}")
]=]

function M.process_queue()
  if not M.enabled or M._is_processing or #M._queue == 0 then return end
  M._is_processing = true

  local batch = {}
  for _ = 1, math.min(10, #M._queue) do
    local item = table.remove(M._queue, 1)
    if item and base_dict[item] == nil and not M._runtime_cache[item] then
      table.insert(batch, item)
    end
  end

  if #batch == 0 then
    M._is_processing = false
    return
  end

  local json_payload = vim.json.encode(batch)
  pcall(vim.system, { 'python3', '-c', _python_trans_script }, {
    stdin = json_payload,
    text = true,
  }, function(obj)
    vim.schedule(function()
      M._is_processing = false
      if obj and obj.code == 0 and obj.stdout and obj.stdout ~= '' then
        local ok, parsed = pcall(vim.json.decode, obj.stdout)
        if ok and type(parsed) == 'table' then
          local has_new = false
          for k, v in pairs(parsed) do
            if v and v ~= '' and v ~= k and base_dict[k] == nil then
              M._runtime_cache[k] = v
              has_new = true
            end
            M._pending[k] = nil
          end
          if has_new then M.save_cache() end
        end
      end
      if #M._queue > 0 then M.process_queue() end
    end)
  end)
end

function M.request_translation_async(text)
  if not M.enabled then return end
  local trimmed = vim.trim(text)
  -- Ignore List 등록 항목(false)이거나 이미 사전/캐시에 있는 경우 번역 요청 스킵
  if base_dict[trimmed] == false or base_dict[trimmed] or M._runtime_cache[trimmed] or M._pending[trimmed] then
    return
  end
  M._pending[trimmed] = true
  table.insert(M._queue, trimmed)
  vim.defer_fn(function() M.process_queue() end, 200)
end

-- ===========================================================================================
-- [1. 메뉴 전용 번역: translate_menu]
-- ===========================================================================================
function M.translate_menu(text)
  if not M.enabled or not text or type(text) ~= 'string' then return text end
  local trimmed = vim.trim(text)
  if trimmed == '' or M.contains_korean(trimmed) then return text end

  -- 1) Ignore List 검사: base_dict 값이 false인 경우 무조건 원본 영문 고정 (0ms)
  local base_entry = base_dict[trimmed]
  if base_entry == false then
    return text
  end

  -- 2) 기본 검증 사전 (1순위 ➔ 0ms)
  if base_entry then
    local ko = type(base_entry) == 'table' and base_entry.ko or base_entry
    return M.format_display(ko, trimmed)
  end

  -- 3) 런타임 캐시 (2순위 ➔ 0ms)
  local cached_ko = M._runtime_cache[trimmed]
  if cached_ko then
    return M.format_display(cached_ko, trimmed)
  end

  -- 4) 신규 메뉴 중 안전한 액션/리팩토링 메뉴만 비동기 동적 학습 큐에 등록
  if M.is_translatable_menu_item(trimmed) then
    M.request_translation_async(trimmed)
  end

  return text
end

-- ===========================================================================================
-- [2. 메시지/LSP 전용 번역: translate_message]
-- ===========================================================================================
function M.translate_message(text)
  if not M.enabled or not text or type(text) ~= 'string' then return text end
  local trimmed = vim.trim(text)
  if trimmed == '' or M.contains_korean(trimmed) then return text end

  -- 1) Ignore List 검사: base_dict 값이 false인 경우 무조건 원본 영문 고정 (0ms)
  local base_entry = base_dict[trimmed]
  if base_entry == false then
    return text
  end

  -- 2) 전체 일치 (Exact Match ➔ 0ms)
  if base_entry then
    local ko = type(base_entry) == 'table' and base_entry.ko or base_entry
    return M.format_display(ko, trimmed)
  end

  local cached_ko = M._runtime_cache[trimmed]
  if cached_ko then
    return M.format_display(cached_ko, trimmed)
  end

  -- 3) 명시적 동적 패턴: Updating <project> configuration
  local proj = text:match('Updating%s+([%w%-_%.]+)%s+configuration')
  if proj then
    local orig = text:match('Updating%s+[%w%-_%.]+%s+configuration')
    local ko = string.format('%s 빌드 구성 업데이트 중 「%s」', proj, orig)
    return (text:gsub(vim.pesc(orig), ko))
  end

  -- 4) 명시적 동적 패턴: Starting Java Language Server
  local lsp_start = text:match('Starting Java Language Server.-$')
  if lsp_start then
    local subtask = lsp_start:match('Starting Java Language Server%s*-%s*(.+)$')
    local ko_sub = nil
    if subtask then
      local b = base_dict[subtask]
      if b == false then
        ko_sub = subtask
      else
        ko_sub = b and (type(b) == 'table' and b.ko or b) or M._runtime_cache[subtask] or subtask
      end
    end
    local ko
    if ko_sub then
      ko = string.format('Java 언어 서버 시작 중 - %s 「%s」', ko_sub, lsp_start)
    else
      ko = string.format('Java 언어 서버 시작 중 「%s」', lsp_start)
    end
    return (text:gsub(vim.pesc(lsp_start), ko))
  end

  -- 5) 안전한 순수 영문 문장인 경우에만 비동기 번역 큐에 등록
  if M.is_translatable_sentence(trimmed) then
    M.request_translation_async(trimmed)
  end

  return text
end

function M.translate_text(text)
  return M.translate_message(text)
end

-- ===========================================================================================
-- [우선순위(Priority) 조회 헬퍼]
-- ===========================================================================================
function M.get_priority(raw_label)
  for _, interceptor in ipairs(M._registered_interceptors) do
    if interceptor.translations and interceptor.translations[raw_label] then
      return interceptor.translations[raw_label].priority or interceptor.default_priority
    end
  end
  if base_dict[raw_label] and type(base_dict[raw_label]) == 'table' and base_dict[raw_label].priority then
    return base_dict[raw_label].priority
  end
  return 90
end

-- ===========================================================================================
-- [인터셉터 설치: 1. 메뉴  2. DAP  3. LSP Progress  4. JDTLS Status  5. LSP Popups  6. 알림]
-- ===========================================================================================
function M.register_interceptor(opts)
  opts.default_priority = opts.default_priority or 90
  table.insert(M._registered_interceptors, opts)
end

function M.setup()
  M.load_cache()

  -- ── 1. vim.ui.select 인터셉터 (Code Actions, DAP 세션 등 메뉴 피커) ──
  if not vim._unified_ui_select_wrapped then
    vim._unified_ui_select_wrapped = true
    vim.schedule(function()
      local orig_ui_select = vim.ui.select
      vim.ui.select = function(items, select_opts, on_choice)
        if not M.enabled then
          return orig_ui_select(items, select_opts, on_choice)
        end

        select_opts = select_opts or {}
        local format_item = select_opts.format_item or function(item) return tostring(item) end

        if type(items) == 'table' and #items > 0 then
          local decorated = {}
          for idx, item in ipairs(items) do
            local raw_label = format_item(item)
            local display = M.translate_menu(raw_label)
            local priority = M.get_priority(raw_label)

            table.insert(decorated, {
              original = item,
              display = display,
              priority = priority,
              idx = idx,
            })
          end

          table.sort(decorated, function(a, b)
            if a.priority ~= b.priority then return a.priority < b.priority end
            return a.idx < b.idx
          end)

          local new_items = {}
          local item_to_display = {}
          for _, d in ipairs(decorated) do
            table.insert(new_items, d.original)
            item_to_display[d.original] = d.display
          end

          local custom_opts = vim.tbl_extend('force', select_opts, {
            format_item = function(item)
              return item_to_display[item] or format_item(item)
            end,
          })

          return orig_ui_select(new_items, custom_opts, on_choice)
        end

        return orig_ui_select(items, select_opts, on_choice)
      end
    end)
  end

  -- ── 2. dap.ui.pick_one 인터셉터 (DAP 세션 메뉴) ──
  local dap_ok, dap_ui = pcall(require, 'dap.ui')
  if dap_ok and dap_ui and dap_ui.pick_one and not dap_ui._translator_wrapped then
    dap_ui._translator_wrapped = true
    local orig_pick_one = dap_ui.pick_one
    dap_ui.pick_one = function(items, prompt, label_fn, cb)
      if not M.enabled then
        return orig_pick_one(items, prompt, label_fn, cb)
      end
      if prompt and items then
        label_fn = label_fn or function(x) return tostring(x) end
        for _, item in ipairs(items) do
          local raw_label = label_fn(item)
          item._custom_display = M.translate_menu(raw_label)
        end
        return orig_pick_one(items, prompt, function(x)
          return x._custom_display or label_fn(x)
        end, cb)
      end
      return orig_pick_one(items, prompt, label_fn, cb)
    end
  end

  -- ── 3. 공식 LSP Progress 핸들러 인터셉터 ($/progress) ──
  local orig_progress = vim.lsp.handlers['$/progress']
  vim.lsp.handlers['$/progress'] = function(err, result, ctx, config)
    if M.enabled and result and result.value then
      if result.value.title and type(result.value.title) == 'string' then
        result.value.title = M.translate_message(result.value.title)
      end
      if result.value.message and type(result.value.message) == 'string' then
        result.value.message = M.translate_message(result.value.message)
      end
    end
    if orig_progress then
      return orig_progress(err, result, ctx, config)
    end
  end

  -- ── 4. Java JDTLS 전용 language/status 핸들러 인터셉터 ──
  local orig_lang_status = vim.lsp.handlers['language/status']
  vim.lsp.handlers['language/status'] = function(err, result, ctx, config)
    if M.enabled and result and result.message and type(result.message) == 'string' then
      result.message = M.translate_message(result.message)
    end
    if orig_lang_status then
      return orig_lang_status(err, result, ctx, config)
    end
  end

  -- ── 5. 공식 LSP 서버 메시지 핸들러 (window/showMessage) ──
  local orig_show_msg = vim.lsp.handlers['window/showMessage']
  vim.lsp.handlers['window/showMessage'] = function(err, result, ctx, config)
    if M.enabled and result and result.message and type(result.message) == 'string' then
      result.message = M.translate_message(result.message)
    end
    if orig_show_msg then
      return orig_show_msg(err, result, ctx, config)
    end
  end

  -- ── 6. vim.notify 인터셉터 (플러그인 공식 알림) ──
  if not vim._unified_notify_wrapped then
    vim._unified_notify_wrapped = true
    local orig_notify = vim.notify
    vim.notify = function(msg, level, notify_opts)
      if M.enabled and type(msg) == 'string' and msg ~= '' then
        local translated_msg = M.translate_message(msg)
        return orig_notify(translated_msg, level, notify_opts)
      end
      return orig_notify(msg, level, notify_opts)
    end
  end
end

return M
