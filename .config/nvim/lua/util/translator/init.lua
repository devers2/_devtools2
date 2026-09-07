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
  if not str or type(str) ~= 'string' then
    return false
  end
  for i = 1, #str do
    local b = string.byte(str, i)
    if b and b >= 224 and b <= 237 then
      return true
    end
  end
  return false
end

function M.format_display(ko, en)
  if not ko or ko == '' or ko == en then
    return en
  end
  if ko:find('「' .. vim.pesc(en) .. '」') then
    return ko
  end
  return string.format('%s 「%s」', ko, en)
end

-- ===========================================================================================
-- [가변 토큰 마스킹 및 템플릿 처리 (Token Masking & Templating)]
-- 프로젝트명(케밥/스네이크/카멜/파스칼), 패키지/클래스명(FQCN), 파일경로, 식별자, 퍼센트(%)를
-- {0}, {1} 플레이스홀더로 치환하여 템플릿 단위로 정규화하고 원본 고유명사를 100% 보존합니다.
-- ===========================================================================================
function M.mask_tokens(text)
  if not text or type(text) ~= 'string' then
    return text, {}
  end
  local tokens = {}
  local masked = text

  local function add_token(val)
    table.insert(tokens, val)
    return string.format('{%d}', #tokens - 1)
  end

  -- 1) 따옴표로 감싸진 문자열: 'jsgantt.js', ':detachedConfiguration7', 'classpath'
  masked = masked:gsub("'[^']+'", function(m)
    return add_token(m)
  end)
  masked = masked:gsub('"[^"]+"', function(m)
    return add_token(m)
  end)

  -- 2) 진행률 퍼센트(%): 94%, 95 %, 95.5%, 100% 등 (공백 및 소수점 포함 지원)
  masked = masked:gsub('%d+%.?%d*%s*%%', function(m)
    return add_token(m)
  end)

  -- 3) Java/프로그래밍 FQCN 패키지 및 클래스명: so.goono.GoonoELNApplication, com.example.Foo
  masked = masked:gsub('[%w_]+%.[%w_]+%.[%w_]+[%w_%.]*', function(m)
    return add_token(m)
  end)

  -- 4) 파일 경로 및 확장자: /a/b/c, Foo.java, pom.xml, layout.html
  masked = masked:gsub('[%w_%-%.]+/[%w_%-%.]+', function(m)
    return add_token(m)
  end)
  masked = masked:gsub('(%a[%w_%-]*%.[a-zA-Z0-9]+)', function(m)
    return add_token(m)
  end)

  -- 5) Gradle 빌드 식별자 / 콜론 접두어: :detachedConfiguration1, :runtimeClasspath
  masked = masked:gsub(':[%w_%-%.]+', function(m)
    return add_token(m)
  end)

  -- 6) 4대 네이밍 컨벤션 코드 식별자 및 약어:
  --    - kebab-case: goono-eln, my-custom-app, abc-def
  --    - snake_case: goono_eln, user_service, cache_dir
  --    - camelCase: goonoEln, myProject, userController
  --    - PascalCase: GoonoELN, UserController, MyProject
  --    - UPPERCASE 약어: JVM, ESLint, LSP, API, HTML, JSON
  masked = masked:gsub('([%a%d_%-]+)', function(word)
    -- snake_case: goono_eln, user_service
    if word:find('^%w+_%w+$') then
      return add_token(word)
    end

    -- kebab-case: goono-eln, my-app, abc-def
    if word:find('^[%w]+%-[%w%-]+$') then
      return add_token(word)
    end

    -- camelCase: goonoEln, myProject (소문자로 시작하여 대문자/숫자 포함)
    if word:find('^%l+[%u%d]%w*$') then
      return add_token(word)
    end

    -- PascalCase: GoonoELN, UserController (대문자로 시작하여 중간에 대문자/숫자 포함)
    if word:find('^%u%l+[%u%d]%w*$') or word:find('^%u+[%l%d]+%u+%w*$') then
      return add_token(word)
    end

    -- 2글자 이상 연속 대문자 약어: JVM, ESLint, LSP, API
    if word:find('^%u%u+$') or word:find('^%u%u+[%l%d]+%w*$') then
      return add_token(word)
    end

    return word
  end)

  return masked, tokens
end

function M.unmask_tokens(template, tokens)
  if not template or type(template) ~= 'string' then
    return template
  end
  local result = template:gsub('{ (%d+) }', '{%1}') -- 번역기가 공백을 삽입한 경우 정규화
  for i, tok in ipairs(tokens) do
    local placeholder = string.format('{%d}', i - 1)
    result = result:gsub(vim.pesc(placeholder), function()
      return tok
    end)
  end
  return result
end

-- ===========================================================================================
-- [정밀 판별기 1: 메뉴/액션 항목 검증 (is_translatable_menu_item)]
-- ===========================================================================================
function M.is_translatable_menu_item(str)
  if not str or type(str) ~= 'string' then
    return false
  end
  local t = vim.trim(str)

  -- 1) 기본 길이 및 문자 검사
  if #t < 4 or #t > 100 or t:sub(1, 1) == ':' then
    return false
  end
  if M.contains_korean(t) then
    return false
  end

  -- 2) 공백이 없는 단일 단어/식별자 제외 (예: 'main', 'test', 'no', 'jdtls')
  if not t:find('%s') then
    return false
  end

  -- 3) 파일 경로, 디렉터리, 확장자 제외 (/src/main/..., lua/util/..., Foo.java, pom.xml)
  if
    t:match('^/')
    or t:match('^%./')
    or t:match('^%.%./')
    or t:match('^~')
    or t:match('^[a-zA-Z]:\\')
  then
    return false
  end
  if select(2, t:gsub('/', '')) >= 2 or t:find('\\') or t:match('%.[a-zA-Z0-9]+$') then
    return false
  end
  if t:find('/') and (not t:find('%s') or t:match('%.[a-zA-Z0-9]+')) then
    return false
  end

  -- 4) Java/프로그래밍 FQCN 패키지 및 클래스명 제외 (so.goono.GoonoELNApplication 등)
  if t:match('[%w_]+%.[%w_]+%.[%w_]+') then
    return false
  end

  -- 5) DAP Launch 설정 및 콜론(:) 기반 데이터 구조 제외 (Launch goono-eln: ..., port: 5005 등)
  if t:find(':') then
    return false
  end

  -- 6) Git 커밋 해시 / 포인터 제외 (a7f8c9b ..., HEAD -> ...)
  if t:match('^%x%x%x%x%x%x%x%s') or t:find('%->') then
    return false
  end

  -- 7) 코드 구문 및 연산자 제외 (; == !=)
  if t:find(';') or t:find('==') or t:find('!=') then
    return false
  end

  return true
end

-- ===========================================================================================
-- [정밀 판별기 2: 알림/메시지 검증 (is_translatable_sentence)]
-- ===========================================================================================
function M.is_translatable_sentence(str)
  if not str or type(str) ~= 'string' then
    return false
  end
  local t = vim.trim(str)

  if not t:find('%s') then
    return false
  end
  if #t < 4 or #t > 150 or t:sub(1, 1) == ':' then
    return false
  end
  if M.contains_korean(t) then
    return false
  end

  if t:match('[%w_]+%.[%w_]+%.[%w_]+') then
    return false
  end
  if t:match('^Launch%s+') and t:find(':') then
    return false
  end
  if t:find('/') or t:find('\\') or t:match('%.[a-zA-Z0-9]+$') then
    return false
  end
  if t:match('^[%-%*]%s+%*%*') or t:match('^diff%s+') then
    return false
  end

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
  if not M.enabled or M._is_processing or #M._queue == 0 then
    return
  end
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
          if has_new then
            M.save_cache()
          end
        end
      end
      if #M._queue > 0 then
        M.process_queue()
      end
    end)
  end)
end

function M.request_translation_async(text)
  if not M.enabled then
    return
  end
  local trimmed = vim.trim(text)
  -- Ignore List 등록 항목(false)이거나 이미 사전/캐시에 있는 경우 번역 요청 스킵
  if
    base_dict[trimmed] == false
    or base_dict[trimmed]
    or M._runtime_cache[trimmed]
    or M._pending[trimmed]
  then
    return
  end
  M._pending[trimmed] = true
  table.insert(M._queue, trimmed)
  vim.defer_fn(function()
    M.process_queue()
  end, 200)
end

-- ===========================================================================================
-- [단어 합성 번역: translate_by_words]
-- 마스킹 후 남은 순수 영단어를 dict.lua에서 단어 단위로 조회하여 한글로 합성합니다.
-- 전치사/접속사는 한국어 조사/연결어로 변환하고, 미등록 단어가 절반 이상이면 nil 반환합니다.
-- 이 함수는 템플릿 조회 실패 후, Google Translate 폴백 전에 시도됩니다.
-- ===========================================================================================

-- 영어 전치사/접속사/관사 → 한국어 조사/연결어 매핑 테이블 (Lua 예약어는 따옴표로 감싸서 정의)
local _word_particles = {
  ['of'] = '의',
  ['for'] = '에 대한',
  ['in'] = '내',
  ['to'] = '로',
  ['with'] = '와 함께',
  ['from'] = '에서',
  ['on'] = '의',
  ['at'] = '에서',
  ['by'] = '에 의한',
  ['and'] = '및',
  ['or'] = '또는',
  ['but'] = '하지만',
  ['the'] = '',
  ['a'] = '',
  ['an'] = '',
  ['is'] = '입니다',
  ['are'] = '입니다',
  ['was'] = '이었습니다',
  ['were'] = '이었습니다',
  ['not'] = '아님',
}

function M.translate_by_words(text)
  if not text or type(text) ~= 'string' then
    return nil
  end

  -- {N} 플레이스홀더를 안전한 ASCII 마커로 임시 치환 (null 바이트 사용 금지: JSON 저장 시 오염됨)
  local tokens_map = {}
  local protected = text:gsub('{(%d+)}', function(n)
    local marker = '__PH' .. n .. '__'
    tokens_map[marker] = '{' .. n .. '}'
    return marker
  end)

  -- 단어 단위 분리
  local words = {}
  for tok in protected:gmatch('%S+') do
    table.insert(words, tok)
  end

  local translated = {}
  local total = 0
  local found = 0

  for _, word in ipairs(words) do
    -- 안전한 마커(__PHn__)는 원래 플레이스홀더로 복원하여 그대로 유지
    local restored_word = word:gsub('__PH(%d+)__', function(n)
      return '{' .. n .. '}'
    end)
    if restored_word ~= word then
      table.insert(translated, restored_word)
    else
      -- 앞뒤 구두점 분리 (예: "folder," → pre="" core="folder" post=",")
      local pre, core, post = word:match('^([%p]*)([%w%-_]+)([%p]*)$')
      if not core then
        -- 순수 구두점/기호는 그대로 유지 (예: "-", "...")
        table.insert(translated, word)
      else
        total = total + 1
        local lower_core = core:lower()

        -- 1) 전치사/접속사/관사 → 한국어 조사/연결어
        local particle = _word_particles[lower_core]
        if particle ~= nil then
          -- 빈 문자열('')인 관사(the, a, an)는 생략
          if particle ~= '' then
            table.insert(translated, pre .. particle .. post)
          end
          found = found + 1
        else
          -- 2) dict.lua에서 단어 조회 (원형 → 소문자 → 첫글자 대문자 순)
          local entry = base_dict[core]
            or base_dict[lower_core]
            or base_dict[core:sub(1, 1):upper() .. core:sub(2)]
          if entry and entry ~= false then
            local ko = type(entry) == 'table' and entry.ko or entry
            table.insert(translated, pre .. ko .. post)
            found = found + 1
          else
            -- 3) 미등록: 원문 유지
            table.insert(translated, word)
          end
        end
      end
    end
  end

  -- 번역 가능 단어가 절반 미만이면 합성 포기 → Google Translate 폴백으로 위임
  if total == 0 or (found / total) < 0.5 then
    return nil
  end

  local result = table.concat(
    vim.tbl_filter(function(s)
      return s ~= ''
    end, translated),
    ' '
  )
  return vim.trim(result:gsub('%s+', ' '))
end

-- ===========================================================================================
-- [1. 메뉴 전용 번역: translate_menu]
-- ===========================================================================================
function M.translate_menu(text)
  if not M.enabled or not text or type(text) ~= 'string' then
    return text
  end
  local trimmed = vim.trim(text)
  if trimmed == '' or M.contains_korean(trimmed) then
    return text
  end

  -- 1) Ignore List 검사: base_dict 값이 false인 경우 무조건 원본 영문 고정 (0ms)
  local base_entry = base_dict[trimmed]
  if base_entry == false then
    return text
  end

  -- 2) 기본 검증 사전 전체 문장 조회 (1순위 ➔ 0ms)
  if base_entry then
    local ko = type(base_entry) == 'table' and base_entry.ko or base_entry
    return M.format_display(ko, trimmed)
  end

  -- 3) 런타임 캐시 전체 문장 조회 (2순위 ➔ 0ms)
  local cached_ko = M._runtime_cache[trimmed]
  if cached_ko then
    return M.format_display(cached_ko, trimmed)
  end

  -- 4) 템플릿 기반 동적 번역 (Token Masking & Templating ➔ 0ms)
  local template, tokens = M.mask_tokens(trimmed)
  if #tokens > 0 then
    local t_base = base_dict[template]
    if t_base == false then
      return text
    elseif t_base then
      local ko = type(t_base) == 'table' and t_base.ko or t_base
      local restored = M.unmask_tokens(ko, tokens)
      return M.format_display(restored, trimmed)
    end

    local t_cached = M._runtime_cache[template]
    if t_cached then
      local restored = M.unmask_tokens(t_cached, tokens)
      return M.format_display(restored, trimmed)
    end

    -- 4.5) 단어 합성 번역 시도 (dict.lua 단어 사전 활용 ➔ 0ms)
    local word_ko = M.translate_by_words(template)
    if word_ko then
      M._runtime_cache[template] = word_ko
      M.save_cache()
      local restored = M.unmask_tokens(word_ko, tokens)
      return M.format_display(restored, trimmed)
    end

    -- 5) Google Translate 폴백 (템플릿 단위, 1회만 등록되어 공유됨)
    if M.is_translatable_menu_item(template) then
      M.request_translation_async(template)
    end
  else
    -- 가변 토큰 없는 순수 메뉴 항목

    -- 4.5) 단어 합성 번역 시도
    local word_ko = M.translate_by_words(trimmed)
    if word_ko then
      M._runtime_cache[trimmed] = word_ko
      M.save_cache()
      return M.format_display(word_ko, trimmed)
    end

    -- 5) Google Translate 폴백
    if M.is_translatable_menu_item(trimmed) then
      M.request_translation_async(trimmed)
    end
  end

  return text
end

-- ===========================================================================================
-- [2. 메시지/LSP 전용 번역: translate_message]
-- ===========================================================================================
function M.translate_message(text)
  if not M.enabled or not text or type(text) ~= 'string' then
    return text
  end
  local trimmed = vim.trim(text)
  if trimmed == '' or M.contains_korean(trimmed) then
    return text
  end

  -- 1) Ignore List 검사: base_dict 값이 false인 경우 무조건 원본 영문 고정 (0ms)
  local base_entry = base_dict[trimmed]
  if base_entry == false then
    return text
  end

  -- 2) 전체 문장 일치 (Exact Match ➔ 0ms)
  if base_entry then
    local ko = type(base_entry) == 'table' and base_entry.ko or base_entry
    return M.format_display(ko, trimmed)
  end

  local cached_ko = M._runtime_cache[trimmed]
  if cached_ko then
    return M.format_display(cached_ko, trimmed)
  end

  -- 3) 템플릿 기반 동적 번역 (Token Masking & Templating ➔ 0ms)
  local template, tokens = M.mask_tokens(trimmed)
  if #tokens > 0 then
    local t_base = base_dict[template]
    if t_base == false then
      return text
    elseif t_base then
      local ko = type(t_base) == 'table' and t_base.ko or t_base
      local restored = M.unmask_tokens(ko, tokens)
      return M.format_display(restored, trimmed)
    end

    local t_cached = M._runtime_cache[template]
    if t_cached then
      local restored = M.unmask_tokens(t_cached, tokens)
      return M.format_display(restored, trimmed)
    end

    -- 4) 단어 합성 번역 시도 (dict.lua 단어 사전 활용 ➔ 0ms)
    local word_ko = M.translate_by_words(template)
    if word_ko then
      M._runtime_cache[template] = word_ko
      M.save_cache()
      local restored = M.unmask_tokens(word_ko, tokens)
      return M.format_display(restored, trimmed)
    end

    -- 5) Google Translate 폴백 (템플릿 단위, 1회만 등록되어 공유됨)
    if M.is_translatable_sentence(template) then
      M.request_translation_async(template)
    end
  else
    -- 가변 토큰 없는 순수 문장

    -- 4) 단어 합성 번역 시도
    local word_ko = M.translate_by_words(trimmed)
    if word_ko then
      M._runtime_cache[trimmed] = word_ko
      M.save_cache()
      return M.format_display(word_ko, trimmed)
    end

    -- 5) Google Translate 폴백
    if M.is_translatable_sentence(trimmed) then
      M.request_translation_async(trimmed)
    end
  end

  -- 6) 명시적 동적 패턴: Starting Java Language Server
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

  return text
end

function M.translate_text(text)
  return M.translate_message(text)
end


-- ===========================================================================================
-- [인터셉터 설치: 1. 메뉴(vim.ui.select)  2. LSP Progress  3. JDTLS Status  4. LSP Popups  5. 알림]
-- ===========================================================================================

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
        local format_item = select_opts.format_item
          or function(item)
            return tostring(item)
          end

        if type(items) == 'table' and #items > 0 then
          local item_to_display = {}
          for _, item in ipairs(items) do
            local raw_label = format_item(item)
            item_to_display[item] = M.translate_menu(raw_label)
          end

          local custom_opts = vim.tbl_extend('force', select_opts, {
            format_item = function(item)
              return item_to_display[item] or format_item(item)
            end,
          })

          return orig_ui_select(items, custom_opts, on_choice)
        end

        return orig_ui_select(items, select_opts, on_choice)
      end
    end)
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
