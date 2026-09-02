-- [대용량 파일 및 복잡한 복합 파일 최우선 차단, O(1) 인메모리 파서 캐싱, 완전 비동기 온디맨드 설치 및 실시간 핫스왑]
-- 1. 대용량 파일 및 인라인 script/style 초과 파일은 트리시터/다운로드/파싱 검사를 100% 즉시 건너뛰어(Bail out) CPU/RAM을 보호합니다.
-- 2. 로컬 파서 설치 여부를 인메모리 테이블(installed_cache)에 캐싱하여 파일 오픈 시 디스크 I/O 없이 0.001ms O(1)로 판별합니다.
-- 3. 로컬에 파서가 없는 경우, 파일 열기를 전혀 지연시키지 않고 즉시 정규식(syntax)으로 화면을 렌더링한 뒤 백그라운드에서 비동기 다운로드/컴파일을 진행합니다.
-- 4. 설치가 완료되면 열려 있는 정상 크기 버퍼에 한해 실시간으로 Treesitter로 동적 전환(Hot-swap)하고 상태 로그를 기록합니다.

local installed_cache = {} -- [lang] = true (설치됨) | nil (미설치/재시도 가능)
local installing_parsers = {} -- [lang] = true (현재 백그라운드 설치 진행 중)

-- =============================================================================
-- [treesitter-context 연동 헬퍼]
-- nvim-treesitter-context 플러그인은 전역 enable/disable API만 제공하며,
-- 버퍼별 제어 API가 없습니다. 따라서 버퍼 진입(BufEnter) 시점에 해당 버퍼의
-- treesitter 파서 활성 상태를 확인하여 context 창을 동기화합니다.
-- - treesitter 켜진 버퍼 → context enable (메서드/클래스명 상단 고정 활성)
-- - treesitter 꺼진 버퍼 → context disable (상단 고정창 숨김)
-- =============================================================================

---현재 버퍼에 treesitter 파서가 활성화되어 있는지 확인
---@param buf integer 버퍼 번호
---@return boolean
local function is_treesitter_active(buf)
  local ok, parser = pcall(vim.treesitter.get_parser, buf)
  return ok and parser ~= nil
end

---treesitter-context를 현재 버퍼의 treesitter 상태에 맞춰 동기화
---treesitter가 켜진 버퍼로 진입 시 enable, 꺼진 버퍼면 disable
---@param buf integer 버퍼 번호
local function sync_ts_context(buf)
  local ok, ts_ctx = pcall(require, 'treesitter-context')
  if not ok then
    return
  end
  if is_treesitter_active(buf) then
    ts_ctx.enable()
  else
    ts_ctx.disable()
  end
end

---treesitter를 중단하고, 현재 창이 해당 버퍼를 보고 있을 때 context도 함께 비활성화
---@param buf integer 버퍼 번호
local function stop_treesitter(buf)
  pcall(vim.treesitter.stop, buf)
  if vim.api.nvim_get_current_buf() == buf then
    local ok, ts_ctx = pcall(require, 'treesitter-context')
    if ok then
      ts_ctx.disable()
    end
  end
end

---로컬에 파서가 설치되어 있는지 O(1) 인메모리 캐시 기반으로 초고속 확인
---@param lang string 언어 파서 이름
---@return boolean is_installed
local function is_parser_installed(lang)
  if installed_cache[lang] ~= nil then
    return installed_cache[lang]
  end

  -- Neovim 표준 파서 로더 테스트 (문자열 파서 가볍게 생성 시도)
  local ok = pcall(vim.treesitter.get_string_parser, '', lang)
  if ok then
    installed_cache[lang] = true
  end
  return ok
end

---버퍼 성능 티어 설정 함수 (경량 모드 시 무거운 Folds/Indent를 선별 차단하여 타이핑 렉 완벽 방지)
---@param buf integer 버퍼 번호
---@param is_light boolean 경량 모드 여부
local function configure_buffer_tier(buf, is_light)
  if is_light then
    -- 1. 코드 접기(Folds) 연산을 manual로 전환하여 타이핑/스크롤 렉 차단
    vim.opt_local.foldmethod = 'manual'
    vim.opt_local.foldexpr = '0'
    -- 2. 자동 들여쓰기(Indent) Treesitter 연산 차단 (기본 내장 들여쓰기로 폴백하여 엔터 렉 차단)
    vim.opt_local.indentexpr = ''
    -- 3. treesitter-context 상단 고정창 비활성화는 stop_treesitter() 또는 FileType 콜백 말미의
    --    sync_ts_context(buf)가 담당합니다 (treesitter-context는 버퍼별 API가 없고 전역 API만 제공)
  end
end

---파서 미설치 시 백그라운드 비동기 자동 설치 함수 (파일 오픈을 절대 블로킹하지 않음, 중복 요청 방지)
---@param lang string 언어 파서 이름
---@param orig_buf integer 요청한 버퍼 번호
local function try_auto_install_parser(lang, orig_buf)
  -- 🔒 [중복 다운로드 방지] 이미 다운로드/컴파일 중이면 추가 요청 생성 없이 스킵
  if installing_parsers[lang] then
    return
  end

  local ok_ts, ts = pcall(require, 'nvim-treesitter')
  if not ok_ts or not ts.install then
    return
  end

  -- nvim-treesitter가 공식 지원하는 언어인지 확인
  local ok_avail, available = pcall(ts.get_available)
  if ok_avail and type(available) == 'table' and not vim.tbl_contains(available, lang) then
    return
  end

  installing_parsers[lang] = true
  vim.notify(string.format("Treesitter: '%s' 파서를 백그라운드에서 자동 설치합니다...", lang), vim.log.levels.INFO, { title = 'Treesitter' })

  local function do_install()
    ts.install({ lang }, { summary = false }):await(function(err)
      installing_parsers[lang] = nil

      if err then
        -- ⚠️ 실패 시 캐시를 nil로 유지하여, 다음에 동일 종류 파일을 열 때 다시 시도할 수 있도록 함
        installed_cache[lang] = nil
        vim.notify(string.format("Treesitter: '%s' 파서 자동 설치 실패 (%s) - 다음 파일 오픈 시 재시도합니다.", lang, tostring(err)), vim.log.levels.WARN, { title = 'Treesitter' })
        return
      end

      -- ✅ 설치 성공 시 캐시 등록
      installed_cache[lang] = true
      if pcall(require, 'lazyvim.util') and LazyVim and LazyVim.treesitter then
        LazyVim.treesitter.get_installed(true) -- LazyVim 파서 캐시 갱신
      end

      vim.schedule(function()
        -- 🔄 [일괄 핫스왑] 현재 열려 있는 버퍼 중 동일 언어를 사용하는 모든 정상 크기 파일에 Treesitter 일괄 적용
        local bufs = vim.api.nvim_list_bufs()
        for _, buf in ipairs(bufs) do
          if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted then
            local ft = vim.bo[buf].filetype or ''
            local buf_lang = vim.treesitter.language.get_lang(ft) or ft
            if buf_lang == lang then
              local fname = vim.api.nvim_buf_get_name(buf)
              local ok_stat, stat = pcall(vim.uv.fs_stat, fname)
              local filesize = (ok_stat and stat) and stat.size or 0
              local max_size = _G.get_max_file_size and _G.get_max_file_size(buf) or (1500 * 1024)

              -- 대용량 파일이나 복합 인라인 크기 초과 파일이 아닐 때만 안전하게 전환
              local is_oversized = filesize > max_size
              local is_inline_oversized = _G.has_oversized_inline_block and _G.has_oversized_inline_block(buf)

              if not is_oversized and not is_inline_oversized then
                local is_light = (filesize > (_G.get_light_file_size and _G.get_light_file_size(buf) or 500 * 1024))
                  or (_G.has_light_inline_block and _G.has_light_inline_block(buf))
                configure_buffer_tier(buf, is_light)
                local ok_start = pcall(vim.treesitter.start, buf, lang)
                if ok_start then
                  -- 핫스왑된 버퍼가 현재 포커스된 버퍼일 때만 context 동기화
                  if vim.api.nvim_get_current_buf() == buf then
                    sync_ts_context(buf)
                  end
                  local basename = vim.fn.fnamemodify(fname, ':t')
                  local msg = is_light and string.format('Treesitter: 경량 적용 (파서 자동 설치 완료, 부가기능 최적화) [%s]', basename)
                    or string.format('Treesitter: 적용 (파서 자동 설치 완료) [%s]', basename)
                  vim.api.nvim_echo({ { msg, 'DiagnosticOk' } }, true, {})
                end
              end
            end
          end
        end
      end)
    end)
  end

  if pcall(require, 'lazyvim.util') and LazyVim and LazyVim.treesitter and LazyVim.treesitter.build then
    LazyVim.treesitter.build(do_install)
  else
    do_install()
  end
end

vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('devtools2_treesitter_fallback_guard', { clear = true }),
  callback = function(ev)
    local buf = ev.buf
    -- LazyVim의 lazyvim_treesitter FileType 콜백(vim.treesitter.start)이
    -- 같은 이벤트 사이클에서 먼저 끝난 뒤 실행되도록 다음 틱으로 미룸
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end

      -- 특수 UI/플로팅 버퍼(도움말, 알림, 대시보드 등)는 검사 및 메시지 출력에서 제외
      local buftype = vim.bo[buf].buftype or ''
      if buftype ~= '' or not vim.bo[buf].buflisted then
        return
      end

      local ft = vim.bo[buf].filetype or ''
      if ft == '' or ft:match('^snacks_') or ft == 'noice' or ft == 'lazy' or ft == 'mason' or ft == 'help' or ft == 'qf' or ft == 'trouble' then
        return
      end

      local fname = vim.api.nvim_buf_get_name(buf)
      if fname == '' then
        return
      end

      local basename = vim.fn.fnamemodify(fname, ':t')
      local ok_stat, stat = pcall(vim.uv.fs_stat, fname)
      local filesize = (ok_stat and stat) and stat.size or 0
      local max_size = _G.get_max_file_size and _G.get_max_file_size(buf) or (1500 * 1024)

      -- =========================================================================
      -- 🛡️ [0순위 절대 가드 (3단계: 완전 폴백)]
      -- 파일이 초대용량이거나 복합 문법 내 인라인 콘텐츠가 비정상적으로 크면
      -- 파서 유무 검사, 쿼리 확인, 백그라운드 다운로드 시도 등 모든 트리시터 연산을 100% 즉시 중단합니다.
      -- =========================================================================
      if filesize > max_size then
        stop_treesitter(buf)
        vim.bo[buf].syntax = ft
        local fmt_cur = (filesize > 1024 * 1024) and string.format('%.1fMB', filesize / (1024 * 1024)) or string.format('%dKB', math.floor(filesize / 1024))
        local fmt_max = (max_size > 1024 * 1024) and string.format('%.1fMB', max_size / (1024 * 1024)) or string.format('%dKB', math.floor(max_size / 1024))
        vim.api.nvim_echo({ { string.format('Treesitter: 미적용 (대용량 파일 (%s > %s)) [%s]', fmt_cur, fmt_max, basename), 'DiagnosticWarn' } }, true, {})
        return
      end

      if _G.has_oversized_inline_block and _G.has_oversized_inline_block(buf) then
        stop_treesitter(buf)
        vim.bo[buf].syntax = ft
        local inline_size = _G.get_inline_block_size and _G.get_inline_block_size(buf) or 0
        local fmt_inline = string.format('%dKB', math.floor(inline_size / 1024))
        local fmt_limit = string.format('%dKB', math.floor((_G.INLINE_BLOCK_LIMIT or (150 * 1024)) / 1024))
        vim.api.nvim_echo({ { string.format('Treesitter: 미적용 (인라인 script/style 크기 초과 (%s > %s)) [%s]', fmt_inline, fmt_limit, basename), 'DiagnosticWarn' } }, true, {})
        return
      end

      -- =========================================================================
      -- ⚡ [1순위: O(1) 인메모리 파서 캐시 검사 및 안전 온디맨드 비동기 처리]
      -- =========================================================================
      local lang = vim.treesitter.language.get_lang(ft) or ft
      local has_parser = is_parser_installed(lang)

      if not has_parser then
        -- 1. 파서 미설치 시: 파일 오픈 지연 없이 즉시 정규식 구문 강조로 화면 렌더링
        stop_treesitter(buf)
        vim.bo[buf].syntax = ft
        local reason_str = installing_parsers[lang] and string.format('파서 다운로드 중 (%s)', lang) or string.format('파서 미설치 (%s)', lang)
        vim.api.nvim_echo({ { string.format('Treesitter: 미적용 (%s) [%s]', reason_str, basename), 'DiagnosticWarn' } }, true, {})

        -- 2. 파일 열람과 완전히 독립된 백그라운드 비동기 다운로드 및 컴파일 트리거 (이미 진행 중이면 함수 내부에서 중복 방지 가드)
        if lang and lang ~= '' then
          try_auto_install_parser(lang, buf)
        end
        return
      end

      -- =========================================================================
      -- 🔍 [2순위: 하이라이트 쿼리(highlights.scm) 유효성 검사]
      -- =========================================================================
      local has_query = vim.treesitter.query.get(lang, 'highlights') ~= nil
      if not has_query then
        stop_treesitter(buf)
        vim.bo[buf].syntax = ft
        vim.api.nvim_echo({ { string.format('Treesitter: 미적용 (하이라이트 쿼리 누락 (%s)) [%s]', lang, basename), 'DiagnosticWarn' } }, true, {})
        return
      end

      -- =========================================================================
      -- 🌟 [3순위: 3단계 성능 티어 판별 및 적용 (풀 모드 vs 경량 모드)]
      -- =========================================================================
      local light_threshold = _G.get_light_file_size and _G.get_light_file_size(buf) or (500 * 1024)
      local is_file_light = filesize > light_threshold
      local is_inline_light = _G.has_light_inline_block and _G.has_light_inline_block(buf)
      local is_light_tier = is_file_light or is_inline_light

      -- 경량화 대상인 경우 무거운 부가기능(Folds/Indent) 선별 차단
      configure_buffer_tier(buf, is_light_tier)
      local ok_start = pcall(vim.treesitter.start, buf, lang)

      -- treesitter 시작 성공 여부에 따라 context 창 동기화
      -- (경량 모드라도 treesitter 자체는 켜지므로 context도 활성화 유지)
      if ok_start then
        sync_ts_context(buf)
      end

      if is_light_tier then
        local reason_detail = is_inline_light and '인라인 script/style 최적화' or '중대형 파일 최적화'
        vim.api.nvim_echo({ { string.format('Treesitter: 경량 적용 (%s) [%s]', reason_detail, basename), 'DiagnosticOk' } }, true, {})
      else
        vim.api.nvim_echo({ { string.format('Treesitter: 적용 [%s]', basename), 'DiagnosticOk' } }, true, {})
      end
    end)
  end,
})

-- =============================================================================
-- [BufEnter: 버퍼 전환 시 treesitter-context 자동 동기화]
-- FileType 이벤트는 버퍼를 새로 열 때만 발생합니다.
-- 이미 열린 버퍼 간 전환(BufEnter) 시에도 해당 버퍼의 treesitter 상태에
-- 맞춰 context 창을 자동으로 켜거나 끄기 위해 별도의 autocmd를 등록합니다.
--
-- 예시 시나리오:
--   A.java (treesitter 켜짐) → B.html (5MB, treesitter 꺼짐)으로 전환
--   → BufEnter B.html → context disable (상단 고정창 사라짐)
--   → 다시 A.java로 돌아옴 → BufEnter A.java → context enable (복원)
-- =============================================================================
vim.api.nvim_create_autocmd('BufEnter', {
  group = vim.api.nvim_create_augroup('devtools2_ts_context_sync', { clear = true }),
  callback = function(ev)
    local buf = ev.buf
    -- 특수 버퍼(터미널, 플로팅 등)는 건너뜀
    if vim.bo[buf].buftype ~= '' then
      return
    end
    -- treesitter-context가 아직 로드되지 않았으면 건너뜀 (로딩 지연 방지)
    if not package.loaded['treesitter-context'] then
      return
    end
    sync_ts_context(buf)
  end,
})

return {
  -- [Treesitter 파서 설정]
  -- Neovim에서 구문 강조 및 코드 분석을 위해 필요한 언어 파서들을 자동으로 설치합니다.
  {
    'nvim-treesitter/nvim-treesitter',
    lazy = false, -- 지연 로딩 완전히 비활성화: 에디터 켜질 때 무조건 즉시 로드하여 첫 버퍼부터 100% 신뢰성 보장
    priority = 1000, -- 가장 높은 우선순위로 먼저 로드
    -- [.properties 파일 하이라이팅 연결]
    -- Neovim 내장 filetype 감지는 *.properties 파일을 'jproperties'로 인식하지만,
    -- nvim-treesitter의 파서 이름은 'properties' 이므로 명시적으로 매핑해줘야
    -- gradle.properties / application.properties 등에서 트리시터 하이라이팅이 실제로 켜집니다.
    init = function()
      vim.treesitter.language.register('properties', 'jproperties')
    end,
    opts = function(_, opts)
      -- 🚀 [사전 설치 목록 완전 제거 및 순수 동적(On-demand) 자동 설치]
      -- =========================================================================
      -- ⚠️ [CRITICAL RULE: ensure_installed 등록 대상 절대 원칙]
      -- =========================================================================
      -- ❌ [추가 금지]: 단독 파일 언어 (kotlin, groovy, yaml, python, java, rust, go 등)
      --    -> 사용자가 해당 파일을 여는 순간 FileType 이벤트가 발생하여,
      --       위의 `try_auto_install_parser`가 100% 온디맨드 비동기로 자동 설치 & 핫스왑합니다.
      --       따라서 일반 언어는 여기에 절대로 추가할 필요가 없습니다.
      --
      -- ⭕ [유일한 등록 대상]: 복합 파일 내부에 삽입(Injection)되어 자체 FileType 이벤트가 없는 언어
      --    -> HTML 내부의 <style>(css), <script>(javascript), JS/TS 주석(jsdoc),
      --       정규식(regex), 마크다운 인라인(markdown_inline) 등은 단독 파일로 열리지 않아
      --       FileType 이벤트가 절대 발생하지 않으므로 온디맨드 자동 설치가 불가능합니다.
      --       오직 이러한 '순수 인젝션(Injection-only) 언어'만 여기에 등록하여 사전 설치합니다.
      -- =========================================================================
      opts.ensure_installed = {
        -- ── Injection-only: 자체 FileType 없음 → on-demand 자동 설치 절대 불가 ──
        'css',            -- <style> 내부 (HTML/htmldjango/vue/svelte 등)
        'javascript',     -- <script> 내부 (HTML/htmldjango/vue/svelte 등)
        'jsdoc',          -- JS/TS 파일의 /** */ 주석 내부 타입·파라미터 강조
        'regex',          -- JS/TS 파일의 /pattern/ 정규식 리터럴 내부 강조
        'markdown_inline', -- markdown 파서가 인라인 요소를 위임
        'luadoc',         -- .lua 파일의 --- 문서 주석 내부 강조 (Neovim 설정용)
        'luap',           -- .lua 파일의 string.find 등 패턴 문자열 강조 (Neovim 설정용)
        'printf',         -- C/Python 등 포맷 문자열(%d, %s 등) 강조
        'comment',        -- 거의 모든 언어 주석의 TODO/FIXME/NOTE/HACK 강조
      }

      -- 하이라이팅 활성화
      opts.highlight = opts.highlight or {}
      opts.highlight.enable = true
      return opts
    end,
  },

  -- [Treesitter Context 설정]
  -- 파일 상단에 현재 커서가 위치한 컨텍스트(클래스 → 메서드 → 블록)를 고정하여 보여줍니다.
  {
    'nvim-treesitter/nvim-treesitter-context',
    event = 'BufReadPost',
    opts = {
      -- 1. 고정 줄 수 제한 없음 → 화면 비율 제한(max_window_height)이 실질적으로 통제
      --    (숫자로 고정하면 창 크기가 달라질 때 너무 많거나 너무 적어지는 문제 발생)
      max_lines = 0,

      -- 2. 화면 비율 제한: 편집기 창 높이의 최대 25%까지만 컨텍스트로 고정
      --    → 작은 창에서 컨텍스트가 절반을 차지하는 현상 방지
      --    → 큰 창에서는 깊은 중첩도 충분히 표시
      max_window_height = 0.25,

      -- 3. 20줄 미만의 작은 창(팝업/미리보기 등)에서는 표시 안 함
      min_window_height = 20,

      -- 4. 줄 번호 표시 (컨텍스트가 파일의 몇 번째 줄에서 왔는지 파악 가능)
      line_numbers = true,

      -- 5. 함수 선언부가 여러 줄일 때 최대 3줄까지 표시
      --    def example(    ← 1줄
      --      param_a,      ← 2줄
      --      param_b,      ← 3줄 (여기까지만 표시)
      --    ):
      multiline_threshold = 3,

      -- 6. max_lines/max_window_height 초과 시 바깥 스코프(클래스 레벨)부터 숨김
      --    → 현재 커서가 있는 안쪽 함수/조건문을 우선 보존
      trim_scope = 'outer',

      -- 7. 커서 위치 기준으로 컨텍스트 결정 (topline보다 직관적)
      mode = 'cursor',

      -- 8. 컨텍스트 고정 영역과 실제 코드 사이 구분선 (없으면 경계가 불명확)
      separator = '─',

      -- 9. 플로팅 창 z-order (다른 팝업에 가리지 않는 기본값)
      zindex = 20,
    },
  },

  -- [Treesitter Textobjects 설정]
  -- 함수, 클래스, 파라미터 등을 코드 구조 단위로 선택/이동/교환합니다.
  -- treesitter가 꺼진 버퍼(대용량 파일 등)에서는 자동으로 비활성화됩니다:
  --   select → disable 콜백에서 is_treesitter_active() 검사로 명시적 차단
  --   move/swap → 파서 없으면 내부적으로 graceful 실패 (추가 제어 불필요)
  {
    'nvim-treesitter/nvim-treesitter-textobjects',
    event = 'BufReadPost',
    config = function()
      require('nvim-treesitter-textobjects').setup({

        -- =====================================================================
        -- [Select] 코드 단위 선택 (Visual / Operator-pending 모드)
        -- =====================================================================
        select = {
          enable = true,

          -- treesitter가 꺼진 버퍼는 선택 기능도 비활성화
          -- 기존 is_treesitter_active() 헬퍼를 재활용
          disable = function(lang, buf)
            return not is_treesitter_active(buf)
          end,

          -- 현재 커서 위치 뒤에 있는 텍스트오브젝트도 자동으로 점프해서 선택
          lookahead = true,

          keymaps = {
            -- [함수]
            ['af'] = { query = '@function.outer', desc = '함수 전체 선택 (outer)' },
            ['if'] = { query = '@function.inner', desc = '함수 본문 선택 (inner)' },
            -- [클래스]
            ['ac'] = { query = '@class.outer',    desc = '클래스 전체 선택 (outer)' },
            ['ic'] = { query = '@class.inner',    desc = '클래스 본문 선택 (inner)' },
            -- [파라미터/인자]
            ['aa'] = { query = '@parameter.outer', desc = '파라미터 선택 (outer, 콤마 포함)' },
            ['ia'] = { query = '@parameter.inner', desc = '파라미터 선택 (inner)' },
            -- [조건문]
            ['ai'] = { query = '@conditional.outer', desc = 'if/else 블록 전체 선택' },
            ['ii'] = { query = '@conditional.inner', desc = 'if/else 본문 선택' },
            -- [반복문]
            ['al'] = { query = '@loop.outer', desc = 'loop 블록 전체 선택' },
            ['il'] = { query = '@loop.inner', desc = 'loop 본문 선택' },
            -- [블록 (중괄호 등)]
            ['ab'] = { query = '@block.outer', desc = '블록 전체 선택' },
            ['ib'] = { query = '@block.inner', desc = '블록 본문 선택' },
          },

          -- 셀렉션 모드: 함수/클래스는 라인 단위(V), 파라미터는 문자 단위(v)
          selection_modes = {
            ['@function.outer']  = 'V',
            ['@function.inner']  = 'V',
            ['@class.outer']     = 'V',
            ['@class.inner']     = 'V',
            ['@parameter.outer'] = 'v',
            ['@parameter.inner'] = 'v',
          },

          -- 선택 시 앞뒤 공백 포함 여부 (false = 코드만 정확하게 선택)
          include_surrounding_whitespace = false,
        },

        -- =====================================================================
        -- [Move] 함수/클래스 경계로 커서 이동
        -- treesitter 파서 없으면 내부적으로 graceful 실패 → 별도 disable 불필요
        -- =====================================================================
        move = {
          enable = true,
          -- 이동 기록을 jumplist에 추가 (Ctrl-O/Ctrl-I로 되돌아올 수 있음)
          set_jumps = true,

          goto_next_start = {
            [']f'] = { query = '@function.outer', desc = '다음 함수 시작으로 이동' },
            [']c'] = { query = '@class.outer',    desc = '다음 클래스 시작으로 이동' },
            [']a'] = { query = '@parameter.inner', desc = '다음 파라미터로 이동' },
          },
          goto_next_end = {
            [']F'] = { query = '@function.outer', desc = '다음 함수 끝으로 이동' },
            [']C'] = { query = '@class.outer',    desc = '다음 클래스 끝으로 이동' },
          },
          goto_previous_start = {
            ['[f'] = { query = '@function.outer', desc = '이전 함수 시작으로 이동' },
            ['[c'] = { query = '@class.outer',    desc = '이전 클래스 시작으로 이동' },
            ['[a'] = { query = '@parameter.inner', desc = '이전 파라미터로 이동' },
          },
          goto_previous_end = {
            ['[F'] = { query = '@function.outer', desc = '이전 함수 끝으로 이동' },
            ['[C'] = { query = '@class.outer',    desc = '이전 클래스 끝으로 이동' },
          },
        },

        -- =====================================================================
        -- [Swap] 파라미터/인자 순서 교환
        -- treesitter 파서 없으면 내부적으로 graceful 실패 → 별도 disable 불필요
        -- =====================================================================
        swap = {
          enable = true,
          swap_next = {
            ['<leader>cp'] = { query = '@parameter.inner', desc = '현재 파라미터를 다음과 교환 (Swap Next Param)' },
          },
          swap_previous = {
            ['<leader>cP'] = { query = '@parameter.inner', desc = '현재 파라미터를 이전과 교환 (Swap Prev Param)' },
          },
        },
      })

      -- -----------------------------------------------------------------------
      -- [Move 반복 이동 지원] ; 와 , 로 마지막 이동 반복 (f/t 와 동일한 UX)
      -- -----------------------------------------------------------------------
      local ok_repeat, ts_repeat = pcall(require, 'nvim-treesitter-textobjects.repeatable_move')
      if not ok_repeat then
        ok_repeat, ts_repeat = pcall(require, 'nvim-treesitter.textobjects.repeatable_move')
      end

      if ok_repeat and ts_repeat then
        local next_move = ts_repeat.repeat_last_move_next or ts_repeat.repeat_last_move
        local prev_move = ts_repeat.repeat_last_move_previous or ts_repeat.repeat_last_move_opposite
        if next_move then
          vim.keymap.set({ 'n', 'x', 'o' }, ';', next_move, { desc = '마지막 textobject 이동 반복 (전방)' })
        end
        if prev_move then
          vim.keymap.set({ 'n', 'x', 'o' }, ',', prev_move, { desc = '마지막 textobject 이동 반복 (후방)' })
        end

        local f_fn = ts_repeat.builtin_f_expr or ts_repeat.builtin_f
        local F_fn = ts_repeat.builtin_F_expr or ts_repeat.builtin_F
        local t_fn = ts_repeat.builtin_t_expr or ts_repeat.builtin_t
        local T_fn = ts_repeat.builtin_T_expr or ts_repeat.builtin_T
        if f_fn then vim.keymap.set({ 'n', 'x', 'o' }, 'f', f_fn, { expr = true }) end
        if F_fn then vim.keymap.set({ 'n', 'x', 'o' }, 'F', F_fn, { expr = true }) end
        if t_fn then vim.keymap.set({ 'n', 'x', 'o' }, 't', t_fn, { expr = true }) end
        if T_fn then vim.keymap.set({ 'n', 'x', 'o' }, 'T', T_fn, { expr = true }) end
      end
    end,
  },

  -- [Treesitter Autotag 설정]
  -- HTML, XML, JSX, TSX, Vue, Svelte, Markdown 등에서 태그 자동 닫기 및 태그 이름 동시 수정을 제공합니다.
  -- Treesitter 파서 및 AST 노드 기반으로 동작하므로:
  -- - Treesitter가 활성화된 버퍼에서만 태그 트리를 탐색하여 동작합니다.
  -- - 대용량 파일 가드 등으로 Treesitter가 꺼진 버퍼에서는 파서 노드가 없어 자동으로 동작이 중단됩니다.
  {
    'windwp/nvim-ts-autotag',
    event = { 'BufReadPost', 'BufNewFile' },
    opts = {
      opts = {
        enable_close = true,          -- <div> 입력 시 </div> 자동 생성 (Auto close tags)
        enable_rename = true,         -- 시작 태그 이름 수정 시 닫는 태그도 동시 수정 (Auto rename)
        enable_close_on_slash = true, -- </ 입력 시 가장 가까운 상위 열린 태그 자동 닫기 (VS Code 방식)
      },
    },
  },

  -- [Treesitter Rainbow Delimiters 설정]
  -- 중첩된 괄호 (), {}, [] 의 색상을 단계별로 무지개 색상으로 구분하여 가독성을 높입니다.
  -- Treesitter 동작 여부와 완벽 연동:
  -- - condition 함수에서 is_treesitter_active(bufnr) 검사
  -- - 대용량 파일 가드 등으로 Treesitter가 꺼진 버퍼에서는 0.001ms 만에 즉시 제외되어 성능을 보존합니다.
  {
    'HiPhish/rainbow-delimiters.nvim',
    event = { 'BufReadPost', 'BufNewFile' },
    config = function()
      local rainbow = require('rainbow-delimiters')
      vim.g.rainbow_delimiters = {
        strategy = {
          [''] = rainbow.strategy['global'],
          vim = rainbow.strategy['local'],
        },
        query = {
          [''] = 'rainbow-delimiters',
          lua = 'rainbow-blocks',
        },
        priority = {
          [''] = 110,
        },
        -- 🔒 Treesitter가 켜져 있는 정상 버퍼에서만 동작하도록 가드 연동
        condition = function(bufnr)
          return is_treesitter_active(bufnr)
        end,
      }
    end,
  },

  -- [Treesitter TreeSJ 설정]
  -- 배열, 딕셔너리/객체, 함수 파라미터 등을 한 줄 ↔ 여러 줄로 스마트하게 분할/병합(Split/Join)합니다.
  -- Treesitter AST 구문 트리 기반으로 콤마와 들여쓰기를 완벽하게 유지합니다.
  {
    'Wansmer/treesj',
    keys = {
      {
        '<leader>cj',
        function()
          require('treesj').toggle()
        end,
        desc = '코드 한 줄 ↔ 여러 줄 변환 토글 (Split/Join Toggle)',
      },
      {
        '<leader>cJ',
        function()
          require('treesj').toggle({ split = { recursive = true } })
        end,
        desc = '하위 항목까지 재귀적 변환 (Recursive Split/Join)',
      },
    },
    dependencies = { 'nvim-treesitter/nvim-treesitter' },
    opts = {
      use_default_keymaps = false, -- <leader>cj 커스텀 키맵 사용을 위해 기본 키맵 비활성화
      max_join_length = 150,      -- 한 줄로 합칠 때 허용할 최대 문자 수
    },
  },

  -- [ts-comments.nvim - Treesitter 복합 파일 언어별 주석 자동 전환]
  -- HTML <script> 안: gc → // JS 주석
  -- HTML <style>  안: gc → /* CSS 주석 */
  -- HTML 본문    안: gc → <!-- HTML 주석 -->
  -- JSX/Vue/Svelte 템플릿에서도 동일하게 언어 영역을 인식합니다.
  -- ※ 성능: 키(gc)를 눌렀을 때만 현재 커서 위치의 Treesitter 노드를 1회 조회 → 상시 부하 0%
  -- ※ Neovim 0.10+ 내장 주석 엔진과 연동되어 매우 가볍고 안전합니다.
  {
    'folke/ts-comments.nvim',
    event = 'VeryLazy',
    opts = {},
  },
}
