-- [대용량 파일 및 쿼리 누락 시 트리시터 → 정규식(syntax) 자동 폴백 및 상태 메시지]
-- nvim-treesitter가 "main" 브랜치(lazy-lock.json 참고)로 고정되어 있고,
-- LazyVim의 lazyvim/plugins/treesitter.lua는 highlight.disable을
-- "언어 이름 문자열 배열"로만 처리한다 (type(f.disable) == "table" 체크).
-- 함수를 넘기는 구버전(master 브랜치) 방식은 무시되어 크기와 무관하게
-- 트리시터가 항상 켜지므로, FileType 시점에 직접 크기 및 쿼리 유효성을 검사해
-- 비정상/대용량 파일은 vim.treesitter.stop()으로 꺼서 기존 Vim 정규식 syntax 강조로 폴백시킨다.
-- 파일 열 때 상태 메시지를 기록하며 (:NoiceAll / :messages 로 확인 가능),
-- 동일 파일을 다시 열어도 트리시터 상태는 바뀌지 않으므로 최초 기록으로 충분하다.

local installing_parsers = {}

---파서 미설치 시 백그라운드 비동기 자동 설치 함수
---@param lang string 언어 파서 이름
---@param orig_buf integer 요청한 버퍼 번호
local function try_auto_install_parser(lang, orig_buf)
  if installing_parsers[lang] then
    return
  end

  local ok_ts, ts = pcall(require, 'nvim-treesitter')
  if not ok_ts or not ts.install then
    return
  end

  -- nvim-treesitter가 지원하는 언어인지 확인
  local ok_avail, available = pcall(ts.get_available)
  if ok_avail and type(available) == 'table' and not vim.tbl_contains(available, lang) then
    return
  end

  installing_parsers[lang] = true
  vim.notify(string.format("Treesitter: '%s' 파서를 백그라운드에서 자동 설치합니다...", lang), vim.log.levels.INFO, { title = 'Treesitter' })

  local function do_install()
    ts.install({ lang }, { summary = false }):await(function()
      installing_parsers[lang] = nil
      if pcall(require, 'lazyvim.util') and LazyVim and LazyVim.treesitter then
        LazyVim.treesitter.get_installed(true) -- LazyVim 파서 캐시 갱신
      end

      vim.schedule(function()
        -- 현재 열려 있는 버퍼들 중 해당 언어를 사용하는 버퍼에 트리시터 즉시 적용
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

              if filesize <= max_size then
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

      local ok_stat, stat = pcall(vim.uv.fs_stat, fname)
      local filesize = (ok_stat and stat) and stat.size or 0
      local max_size = _G.get_max_file_size and _G.get_max_file_size(buf) or (1024 * 1024)

      local lang = vim.treesitter.language.get_lang(ft) or ft
      local ok_parser, parser = pcall(vim.treesitter.get_parser, buf, lang)
      local has_query = vim.treesitter.query.get(lang, 'highlights') ~= nil

      local fallback_reason = nil
      local is_missing_parser = false

      -- 1. 파일 전체 크기 검사
      if filesize > max_size then
        local fmt_cur = (filesize > 1024 * 1024) and string.format('%.1fMB', filesize / (1024 * 1024)) or string.format('%dKB', math.floor(filesize / 1024))
        local fmt_max = (max_size > 1024 * 1024) and string.format('%.1fMB', max_size / (1024 * 1024)) or string.format('%dKB', math.floor(max_size / 1024))
        fallback_reason = string.format('대용량 파일 (%s > %s)', fmt_cur, fmt_max)
      -- 2. HTML 등 복합 문법 파일에 <script>/<style> 인라인 콘텐츠가 유독 많으면(options.lua의 has_oversized_inline_block 참고)
      --    별도로 더 보수적으로 처리 — 크기 검사를 이미 통과 못했으면 elseif로 건너뜀(불필요한 비용 방지)
      elseif _G.has_oversized_inline_block and _G.has_oversized_inline_block(buf) then
        fallback_reason = '인라인 script/style 크기 초과'
      -- 3. 파서 미설치 검사
      elseif not ok_parser or not parser then
        fallback_reason = string.format('파서 미설치 (%s)', lang)
        is_missing_parser = true
      -- 4. 하이라이트 쿼리(highlights.scm) 누락 검사
      elseif not has_query then
        fallback_reason = string.format('하이라이트 쿼리 누락 (%s)', lang)
      end

      local basename = vim.fn.fnamemodify(fname, ':t')
      if fallback_reason then
        pcall(vim.treesitter.stop, buf)
        vim.bo[buf].syntax = ft -- Vim 전통 정규식 syntax 강조로 안전 폴백
        -- 파일명이 포함되어 자연히 고유한 메시지 → :NoiceAll / :messages 로 언제든 확인 가능
        vim.api.nvim_echo({ { string.format('Treesitter: 미적용 (%s) [%s]', fallback_reason, basename), 'DiagnosticWarn' } }, true, {})

        -- 파서 미설치로 인한 미적용인 경우, 백그라운드 비동기 자동 설치 트리거
        if is_missing_parser and lang and lang ~= '' then
          try_auto_install_parser(lang, buf)
        end
      else
        vim.api.nvim_echo({ { string.format('Treesitter: 적용 [%s]', basename), 'DiagnosticOk' } }, true, {})
      end
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
