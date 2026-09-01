-- [대용량 파일 및 복잡한 복합 파일 최우선 차단, O(1) 인메모리 파서 캐싱, 완전 비동기 온디맨드 설치 및 실시간 핫스왑]
-- 1. 대용량 파일 및 인라인 script/style 초과 파일은 트리시터/다운로드/파싱 검사를 100% 즉시 건너뛰어(Bail out) CPU/RAM을 보호합니다.
-- 2. 로컬 파서 설치 여부를 인메모리 테이블(installed_cache)에 캐싱하여 파일 오픈 시 디스크 I/O 없이 0.001ms O(1)로 판별합니다.
-- 3. 로컬에 파서가 없는 경우, 파일 열기를 전혀 지연시키지 않고 즉시 정규식(syntax)으로 화면을 렌더링한 뒤 백그라운드에서 비동기 다운로드/컴파일을 진행합니다.
-- 4. 설치가 완료되면 열려 있는 정상 크기 버퍼에 한해 실시간으로 Treesitter로 동적 전환(Hot-swap)하고 상태 로그를 기록합니다.

local installed_cache = {} -- [lang] = true (설치됨) | nil (미설치/재시도 가능)
local installing_parsers = {} -- [lang] = true (현재 백그라운드 설치 진행 중)

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
              local max_size = _G.get_max_file_size and _G.get_max_file_size(buf) or (1024 * 1024)

              -- 대용량 파일이나 복합 인라인 크기 초과 파일이 아닐 때만 안전하게 전환
              local is_oversized = filesize > max_size
              local is_inline_oversized = _G.has_oversized_inline_block and _G.has_oversized_inline_block(buf)

              if not is_oversized and not is_inline_oversized then
                local ok_start = pcall(vim.treesitter.start, buf, lang)
                if ok_start then
                  local basename = vim.fn.fnamemodify(fname, ':t')
                  vim.api.nvim_echo({ { string.format('Treesitter: 적용 (파서 자동 설치 완료) [%s]', basename), 'DiagnosticOk' } }, true, {})
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
      local max_size = _G.get_max_file_size and _G.get_max_file_size(buf) or (1024 * 1024)

      -- =========================================================================
      -- 🛡️ [0순위 절대 가드 (Bail-out Guard)]
      -- 파일이 대용량이거나 복합 문법 내 인라인 콘텐츠가 비정상적으로 크면
      -- 파서 유무 검사, 쿼리 확인, 백그라운드 다운로드 시도 등 모든 트리시터 연산을 100% 즉시 중단합니다.
      -- =========================================================================
      if filesize > max_size then
        pcall(vim.treesitter.stop, buf)
        vim.bo[buf].syntax = ft
        local fmt_cur = (filesize > 1024 * 1024) and string.format('%.1fMB', filesize / (1024 * 1024)) or string.format('%dKB', math.floor(filesize / 1024))
        local fmt_max = (max_size > 1024 * 1024) and string.format('%.1fMB', max_size / (1024 * 1024)) or string.format('%dKB', math.floor(max_size / 1024))
        vim.api.nvim_echo({ { string.format('Treesitter: 미적용 (대용량 파일 (%s > %s)) [%s]', fmt_cur, fmt_max, basename), 'DiagnosticWarn' } }, true, {})
        return
      end

      if _G.has_oversized_inline_block and _G.has_oversized_inline_block(buf) then
        pcall(vim.treesitter.stop, buf)
        vim.bo[buf].syntax = ft
        vim.api.nvim_echo({ { string.format('Treesitter: 미적용 (인라인 script/style 크기 초과) [%s]', basename), 'DiagnosticWarn' } }, true, {})
        return
      end

      -- =========================================================================
      -- ⚡ [1순위: O(1) 인메모리 파서 캐시 검사 및 안전 온디맨드 비동기 처리]
      -- =========================================================================
      local lang = vim.treesitter.language.get_lang(ft) or ft
      local has_parser = is_parser_installed(lang)

      if not has_parser then
        -- 1. 파서 미설치 시: 파일 오픈 지연 없이 즉시 정규식 구문 강조로 화면 렌더링
        pcall(vim.treesitter.stop, buf)
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
        pcall(vim.treesitter.stop, buf)
        vim.bo[buf].syntax = ft
        vim.api.nvim_echo({ { string.format('Treesitter: 미적용 (하이라이트 쿼리 누락 (%s)) [%s]', lang, basename), 'DiagnosticWarn' } }, true, {})
        return
      end

      -- =========================================================================
      -- ✅ [3순위: 정상 적용]
      -- =========================================================================
      vim.api.nvim_echo({ { string.format('Treesitter: 적용 [%s]', basename), 'DiagnosticOk' } }, true, {})
    end)
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
      -- 에디터 시작 시 수십 개 언어 파서를 일괄 빌드하는 CPU/RAM 부하와 초기 지연을 방지하기 위해
      -- 기본적으로 ensure_installed 목록을 비워둡니다 (opts.ensure_installed = {}).
      -- 파일타입(FileType) 감지 시 Neovim의 언어 매핑 규칙을 통해 동적으로 파서 이름을 찾아내며,
      -- 위쪽 devtools2_treesitter_fallback_guard의 try_auto_install_parser가
      -- 실제로 열람/편집하는 파일의 파서만 1개씩 안전하게 백그라운드에서 동적으로 자동 설치합니다.
      --
      -- 💡 [추후 필요 시 특정 언어를 사전 설치(Pre-install)하고 싶을 때]
      -- 첫 파일 오픈 시점의 다운로드/컴파일 딜레이 없이 항상 즉시 켜져야 하는 핵심 언어가 있다면
      -- 아래 테이블에 언어 이름을 추가해 주시면 됩니다. (이미 설치된 파서는 건너뛰므로 오버헤드가 없습니다)
      --
      -- 예시 (주요 34개 언어 파서 목록):
      -- opts.ensure_installed = {
      --   -- 백엔드 / 시스템 / 스크립트
      --   'java', 'c', 'python', 'bash', 'sql',
      --   -- 프론트엔드 / 웹
      --   'html', 'javascript', 'typescript', 'tsx', 'css', 'scss', 'jsdoc',
      --   -- 데이터 포맷 / 설정 파일
      --   'xml', 'dtd', 'json', 'yaml', 'toml', 'properties',
      --   -- 문서 / 마크다운 / 주석 / 빌드
      --   'markdown', 'markdown_inline', 'rst', 'ninja', 'printf', 'regex', 'query', 'diff',
      --   -- Neovim 설정 / Lua
      --   'lua', 'luadoc', 'luap', 'vim', 'vimdoc',
      -- }
      opts.ensure_installed = {}

      -- 하이라이팅 활성화
      opts.highlight = opts.highlight or {}
      opts.highlight.enable = true
      return opts
    end,
  },

  -- [Treesitter Context 설정]
  -- 파일 상단에 현재 커서가 위치한 컨텍스트(클래스, 메서드 명 등)를 고정하여 보여줍니다.
  {
    'nvim-treesitter/nvim-treesitter-context',
    event = 'BufReadPost',
    opts = {
      max_lines = 3, -- 상단에 고정될 최대 줄 수 (너무 많으면 화면을 가리므로 3~5줄 추천)
      min_window_height = 0, -- 설정한 높이 이상의 창에서만 작동
      line_numbers = true,
      multiline_threshold = 20, -- 한 메서드가 너무 길 때 유지할 최대 줄 수
      trim_scope = 'outer', -- max_lines를 넘었을 때 어느 쪽을 숨길지 설정
      mode = 'cursor', -- 'cursor' 또는 'topline' 기준
    },
  },
}
