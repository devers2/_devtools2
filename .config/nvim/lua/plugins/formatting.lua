-- =============================================================================
-- 📖 [Conform.nvim 포맷팅 아키텍처 & 확장 가이드]
-- =============================================================================
-- 1. 🔄 동적 포맷팅 라우팅 (Dynamic Formatting Routing):
--    - conform.nvim은 `formatters_by_ft`에 고정 테이블뿐만 아니라 함수(`function(bufnr)`)를 지원합니다.
--    - 파일이 열릴 때마다 버퍼의 상태(Treesitter 활성 여부, 대용량 파일 여부, 프로젝트 설정 등)를
--      실시간으로 검사하여 최적의 포맷터 조합을 '100% 동적'으로 결정하여 실행합니다.
--
-- 2. 🌲 Treesitter Injected 포맷팅 & 안전 폴백 (Safe Fallback):
--    - [Treesitter 활성 시]: Markdown, HTML, JS/TS 내부의 코드 블록(SQL, Python, JSON 등)을
--      Treesitter가 감지하여 해당 언어의 전용 포맷터(`injected`)로 먼저 정렬한 뒤 전체를 포맷팅합니다.
--    - [Treesitter 비활성 시]: 대용량 파일이나 정규식 구문 강조 모드에서는 `injected` 연산을
--      자동으로 건너뛰고 기본 포맷터(`prettier` 등)만 단독 실행하여 렉과 오류를 원천 차단합니다.
--
-- 3. ➕ 새로운 언어/포맷터 추가 방법 (How to Add New Language):
--    - ① formatters_by_ft 에 언어 파일타입(ft) 추가:
--        rust = { 'rustfmt' },
--        go = { 'goimports', 'gofmt' },
--    - ② 커스텀 인자나 설정 파일 경로가 필요한 경우 아래 `formatters` 테이블에 정의:
--        my_formatter = {
--          prepend_args = { '--config', '/path/to/config' },
--        },
-- =============================================================================

-- 헬퍼 함수: 버퍼의 Treesitter 활성 여부 안전 검사 (전역 헬퍼 + Neovim 표준 API 이중 가드)
local function is_ts_active(bufnr)
  if _G.is_treesitter_active then
    return _G.is_treesitter_active(bufnr)
  end
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  return ok and parser ~= nil
end

-- 헬퍼 함수: Treesitter 활성 여부에 따라 Injected 포맷터를 동적으로 결합
local function with_injected(base_formatter)
  return function(bufnr)
    if is_ts_active(bufnr) then
      return { 'injected', base_formatter }
    else
      return { base_formatter }
    end
  end
end

-- 헬퍼 함수: 프로젝트 로컬 Prettier 설정 파일 존재 여부 검사
local function find_local_prettier_config(filename)
  if not filename or filename == '' then
    return nil
  end
  return vim.fs.root(filename, {
    '.prettierrc',
    '.prettierrc.json',
    '.prettierrc.js',
    '.prettierrc.cjs',
    '.prettierrc.mjs',
    '.prettierrc.yaml',
    '.prettierrc.yml',
    'prettier.config.js',
    'prettier.config.cjs',
    'prettier.config.mjs',
  })
end

-- 헬퍼 함수: 스마트 Prettier 인자 빌더
-- 프로젝트 로컬에 Prettier 설정이 존재하면 로컬 설정을 따르고,
-- 로컬 설정이 없을 때만 글로벌 _devtools2의 .prettierrc.cjs 설정을 안전하게 폴백 적용합니다.
local function get_smart_prettier_prepend_args(self, ctx)
  local has_local_config = find_local_prettier_config(ctx.filename) ~= nil

  if has_local_config then
    -- 로컬 설정 파일 존재 시: Prettier 자체 설정 탐색 활용 (--ignore-path ""로 와일드카드 무시 버그만 방어)
    return { '--ignore-path', '' }
  else
    -- 로컬 설정 파일 부재 시: 글로벌 _devtools2 Prettier 설정 명시 지정
    return {
      '--config',
      _G.DEVTOOLS2_DIR .. '/.config/prettier/.prettierrc.cjs',
      '--ignore-path',
      '',
    }
  end
end

return {
  {
    'stevearc/conform.nvim',
    init = function()
      -- 1. [프로젝트별 conform 로그 파일 분리]
      -- conform.nvim의 기본값(~/.local/state/nvim/conform.log)은 모든 프로젝트의 로그가 하나의 파일에 누적되어,
      -- 다른 프로젝트에서 :ConformInfo 를 열었을 때 이전 프로젝트의 오류/로그가 뒤섞여 보이는 문제가 있습니다.
      -- 이를 해결하기 위해 현재 열려있는 파일의 프로젝트 루트(Git 또는 프로젝트 디렉터리명)를 기준으로
      -- ~/.local/state/nvim/conform/<프로젝트명>.log 에 프로젝트별로 독립 저장합니다.
      -- pcall 안전 가드로 감싸 플러그인 버전 변경 시에도 100% 안전하게 기본 로거로 폴백됩니다.
      local ok, log = pcall(require, 'conform.log')
      if ok and type(log.get_logfile) == 'function' and type(log.set_handler) == 'function' then
        -- 현재 버퍼의 프로젝트 루트 디렉터리명을 기준으로 로그 파일 경로 계산
        log.get_logfile = function()
          local buf = vim.api.nvim_get_current_buf()
          local fname = vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) or ''
          local root = (fname ~= '' and vim.fs.root(fname, { '.git', 'mvnw', 'gradlew', 'package.json', 'pyproject.toml' }))
            or vim.fs.root(0, { '.git' })
            or vim.fn.getcwd()
          local proj_name = vim.fs.basename(root)
          local log_dir = vim.fn.stdpath('state') .. '/conform'
          pcall(vim.fn.mkdir, log_dir, 'p')
          return string.format('%s/%s.log', log_dir, proj_name)
        end

        -- 로그가 발생할 때마다 해당 프로젝트의 로그 파일로 실시간 기록
        log.set_handler(function(line)
          local filepath = log.get_logfile()
          local parent = vim.fs.dirname(filepath)
          pcall(vim.fn.mkdir, parent, 'p')
          local f = io.open(filepath, 'a+')
          if f then
            f:write(line .. '\n')
            f:close()
          end
        end)
      end
    end,

    opts = {
      notify_on_error = true,

      -- =========================================================================
      -- 🛠️ [언어별 포맷터 매핑 (실무 Gradle / Spring & Python 최적화)]
      -- =========================================================================
      formatters_by_ft = {
        -- ── 1. Python (Ruff 임포트 정리 + PEP8 코드 포맷팅) ──
        python = { 'ruff_fix', 'ruff_format' },

        -- ── 2. Gradle / Spring / Kotlin ──
        -- Kotlin: ktlint 표준 포맷터 (Mason에서 ktlint 설치 시 자동 연동)
        kotlin = { 'ktlint' },
        -- XML: pom.xml, logback.xml, web.xml 등 일반 스프링 XML은 정상 포맷팅하되,
        -- MyBatis 매퍼(*Mapper.xml 또는 <mapper / mybatis DTD 선언 파일)는
        -- SQL 쿼리 및 다이나믹 태그 인덴트 파손을 원천 차단하기 위해 자동 제외(스킵)합니다.
        xml = function(bufnr)
          local fname = vim.api.nvim_buf_get_name(bufnr)
          -- ① 파일명 기준 감지 (*Mapper.xml, *mapper.xml)
          if fname:match('[Mm]apper%.xml$') then
            return {}
          end

          -- ② 버퍼 상단 25줄 내용 기준 감지 (MyBatis DTD 또는 <mapper 루트 태그)
          local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 25, false)
          for _, line in ipairs(lines) do
            if line:find('mybatis', 1, true) or line:find('<mapper', 1, true) then
              return {}
            end
          end

          -- ③ 일반 스프링/자바 설정 XML은 깔끔하게 자동 정렬
          return { 'xmlformatter' }
        end,
        -- SQL: JPA / MyBatis 쿼리 및 단독 SQL 파일 포맷팅
        sql = { 'sql_formatter' },

        -- ── 3. 웹 / 템플릿 (Treesitter Injected 동적 연동 & 안전 분리) ──
        -- HTML / Django: Prettier HTML 파서가 <script>/<style> 들여쓰기를 HTML 문맥(+2)에 맞게 전담합니다.
        -- standalone JS Injected 포맷터가 0칸 기준으로 뭉갰다가 Prettier가 다시 미는
        -- 들여쓰기 누적/경합 버그(CDATA 스크립트 등)를 원천 차단하기 위해 Prettier 단독 실행합니다.
        html = { 'prettier' },
        htmldjango = { 'prettier' },
        -- JS / TS: 템플릿 리터럴(/* sql */, /* html */ 등) 내장 언어 동적 포맷팅
        javascript = with_injected('prettier'),
        typescript = with_injected('prettier'),
        javascriptreact = with_injected('prettier'),
        typescriptreact = with_injected('prettier'),
        -- Markdown: ```python, ```sql, ```json 등 내부 코드 블록 동적 포맷팅
        markdown = with_injected('prettier'),

        -- ── 4. 기타 정적 설정 파일 ──
        json = { 'prettier' },
        jsonc = { 'prettier' },
        yaml = { 'prettier' },
        css = { 'prettier' },
        scss = { 'prettier' },
        lua = { 'stylua' },
      },

      -- =========================================================================
      -- ⚙️ [포맷터 세부 실행 옵션 및 인자 설정]
      -- =========================================================================
      formatters = {
        -- 🌲 Treesitter Injected 포맷터 옵션: 코드 블록 파싱 에러 시 파일 파손 방지 (안전 보존)
        injected = {
          options = {
            ignore_errors = true,
          },
        },

        -- 🌟 스마트 Prettier:
        -- 1) 프로젝트 로컬에 .prettierrc / prettier.config 등이 존재하면 로컬 설정을 최우선 존중
        -- 2) 로컬 설정이 없는 독립 파일/프로젝트일 때만 글로벌 _devtools2의 .prettierrc.cjs 로 안전하게 폴백
        -- 3) --ignore-path "" 로 .gitignore의 '*' 와일드카드로 인해 Prettier가 파일을 건너뛰는 현상 완벽 방어
        prettier = {
          prepend_args = get_smart_prettier_prepend_args,
        },
        prettier_html = {
          prepend_args = get_smart_prettier_prepend_args,
        },

        stylua = {
          prepend_args = { '--config-path', vim.fs.joinpath(vim.fn.stdpath('config'), 'stylua.toml') },
        },

        -- XML (Spring & MyBatis 매퍼):
        -- MyBatis 다이나믹 쿼리 및 SQL 태그 내부의 줄바꿈/인덴트를 100% 보존(--preserve)하여 쿼리 뭉개짐을 방지합니다.
        xmlformatter = {
          prepend_args = {
            '--preserve',
            'select,insert,update,delete,sql,selectKey,if,choose,when,otherwise,where,set,trim,foreach,bind',
          },
        },

        -- Python
        ruff_format = {
          prepend_args = { '--config', _G.DEVTOOLS2_DIR .. '/.config/ruff/ruff.toml' },
        },
        ruff_fix = {
          prepend_args = { '--config', _G.DEVTOOLS2_DIR .. '/.config/ruff/ruff.toml' },
        },
      },
    },
  },
}
