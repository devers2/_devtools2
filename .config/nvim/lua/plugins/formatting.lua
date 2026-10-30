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
-- ● 설정 파일(.prettierrc* / prettier.config.*) 또는 package.json 최상위의 "prettier" 설정을 프로젝트 설정으로 봅니다.
--   (예전에는 설정 파일만 봐서, package.json 에 Prettier 설정을 둔 프로젝트도 공통 설정으로 포맷되어 팀 규칙이 무시됐음)
-- ● package.json 은 JSON 으로 읽어 최상위 키를 확인합니다. "devDependencies": { "prettier": "^3" } 처럼 설치만 한
--   경우를 설정으로 오인하지 않기 위해서입니다.
-- ⚠️ Zed 포맷 래퍼(scripts/format/format 의 prettier)도 같은 기준이므로 바꾸면 함께 맞춰 주세요.
local PRETTIER_CONFIG_FILES = {
  '.prettierrc',
  '.prettierrc.json',
  '.prettierrc.json5',
  '.prettierrc.js',
  '.prettierrc.cjs',
  '.prettierrc.mjs',
  '.prettierrc.ts',
  '.prettierrc.cts',
  '.prettierrc.mts',
  '.prettierrc.yaml',
  '.prettierrc.yml',
  '.prettierrc.toml',
  'prettier.config.js',
  'prettier.config.cjs',
  'prettier.config.mjs',
  'prettier.config.ts',
  'prettier.config.cts',
  'prettier.config.mts',
}

local function package_json_has_prettier(dir)
  local f = io.open(dir .. '/package.json', 'r')
  if not f then
    return false
  end
  local ok, data = pcall(vim.json.decode, f:read('*a') or '')
  f:close()
  return ok and type(data) == 'table' and data.prettier ~= nil
end

local function find_local_prettier_config(filename)
  if not filename or filename == '' then
    return nil
  end
  return vim.fs.root(filename, function(name, path)
    if vim.tbl_contains(PRETTIER_CONFIG_FILES, name) then
      return true
    end
    return name == 'package.json' and package_json_has_prettier(path)
  end)
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

-- 헬퍼 함수: 스마트 Ruff 인자 빌더 (Prettier 와 같은 원칙)
-- 프로젝트에 ruff 설정(ruff.toml / .ruff.toml / pyproject.toml 의 [tool.ruff])이 있으면 그 설정을 따르고,
-- 없을 때만 글로벌 _devtools2 ruff.toml 을 지정합니다.
-- (항상 --config 로 전역 설정을 강제하면 프로젝트의 line-length 등이 무시되어 CI 와 다르게 포맷됨)
-- ● ruff 자체의 설정 탐색과 같게 위쪽 폴더로 올라가며 확인합니다: ruff.toml / .ruff.toml, 또는 [tool.ruff] 가 있는
--   pyproject.toml. [tool.ruff] 가 없는 pyproject.toml 은 건너뛰고 계속 올라갑니다.
--   (예전에는 가장 가까운 pyproject.toml 하나만 봐서, 하위 패키지의 pyproject.toml 에 [tool.ruff] 가 없으면
--    상위 폴더의 ruff 설정이 있어도 공통 설정으로 포맷됐음 — 여러 패키지를 모은 저장소)
-- ⚠️ Zed 는 ruff 언어 서버의 configurationPreference = filesystemFirst 로 같은 기준을 씀 (.config/zed/settings.json)
local function has_project_ruff_config(filename)
  if not filename or filename == '' then
    return false
  end
  local found = vim.fs.root(filename, function(name, path)
    if name == 'ruff.toml' or name == '.ruff.toml' then
      return true
    end
    if name == 'pyproject.toml' then
      local f = io.open(path .. '/pyproject.toml', 'r')
      if f then
        local content = f:read('*a') or ''
        f:close()
        return content:find('%[tool%.ruff') ~= nil
      end
    end
    return false
  end)
  return found ~= nil
end

local function get_smart_ruff_prepend_args(_, ctx)
  if has_project_ruff_config(ctx.filename) then
    return {}
  end
  return { '--config', _G.DEVTOOLS2_DIR .. '/.config/ruff/ruff.toml' }
end

-- 헬퍼 함수: 스마트 StyLua 인자 빌더 (Prettier·Ruff 와 같은 원칙)
-- 프로젝트에 stylua.toml / .stylua.toml 이 있으면 그 설정(stylua 의 --search-parent-directories 가 찾음),
-- 없을 때만 Neovim 설정 폴더의 stylua.toml(공통 설정)을 지정합니다.
-- (예전에는 항상 --config-path 로 Neovim 설정을 강제해서 프로젝트의 stylua 설정이 무시됐음)
-- ⚠️ Zed 포맷 래퍼(scripts/format/format 의 lua)도 같은 기준이므로 바꾸면 함께 맞춰 주세요.
local function get_smart_stylua_prepend_args(_, ctx)
  if vim.fs.root(ctx.filename, { 'stylua.toml', '.stylua.toml' }) then
    return {}
  end
  return { '--config-path', vim.fs.joinpath(vim.fn.stdpath('config'), 'stylua.toml') }
end

-- 헬퍼 함수: shfmt 인자 (셸 스크립트)
-- 프로젝트에 .editorconfig 가 있으면 그 설정(shfmt 가 -filename 기준으로 찾음), 없으면 DevTools2 스크립트 스타일인
-- 4칸 들여쓰기 + case 안쪽 들여쓰기(-i 4 -ci)를 씁니다.
-- (LazyVim 기본값은 .editorconfig 가 없으면 Neovim 들여쓰기 칸 수(2칸)를 넘겨서, 4칸으로 작성된 DevTools2 스크립트를
--  저장만 해도 절반 가까운 줄이 2칸으로 바뀌었음 — doctor.sh 245줄 중 109줄, 실측)
local function get_shfmt_args(_, ctx)
  local args = { '-filename', '$FILENAME' }
  if not vim.fs.find('.editorconfig', { path = ctx.dirname, upward = true })[1] then
    vim.list_extend(args, { '-i', '4', '-ci' })
  end
  return args
end

-- [셸 스크립트는 저장 시 자동 포맷 끔 — 필요할 때 <leader>cf 로 직접 정리]
-- DevTools2 스크립트는 shfmt 스타일로 작성되지 않아(예: "( cmd1 \n cmd2 ) &" 묶음, 줄 앞 "| python3" 이어쓰기),
-- 4칸으로 맞춰도 저장소 스크립트의 약 8%(14,864줄 중 1,182줄)가 바뀝니다. 동작은 같지만 일부러 쓴 스타일이고,
-- 다른 PC 가 GitHub 에서 바로 받아 실행하는 설치 스크립트라 저장할 때마다 의도하지 않은 변경이 섞이지 않게 합니다.
vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('devtools2_no_autoformat_sh', { clear = true }),
  pattern = { 'sh', 'bash', 'zsh' },
  callback = function(ev)
    vim.b[ev.buf].autoformat = false
  end,
})

return {
  {
    'stevearc/conform.nvim',
    init = function()
      -- 1. LazyVim의 기본 conform 포맷터 자동 등록 (저장 시 자동 포맷팅 엔진)
      LazyVim.on_very_lazy(function()
        LazyVim.format.register({
          name = 'conform.nvim',
          priority = 100,
          primary = true,
          format = function(buf)
            require('conform').format({ bufnr = buf })
          end,
          sources = function(buf)
            local ret = require('conform').list_formatters(buf)
            return vim.tbl_map(function(v)
              return v.name
            end, ret)
          end,
        })
      end)

      -- 2. [프로젝트별 conform 로그 파일 분리]
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
        vue = { 'prettier' },
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
        json5 = { 'prettier' },
        yaml = { 'prettier' },
        css = { 'prettier' },
        scss = { 'prettier' },
        lua = { 'stylua' },
        -- 셸: shfmt (인자는 아래 formatters.shfmt, 저장 시 자동 포맷은 위 FileType 오토커맨드로 끔)
        sh = { 'shfmt' },
        bash = { 'shfmt' },
      },

      -- =========================================================================
      -- ⚙️ [포맷터 세부 실행 옵션 및 인자 설정]
      -- =========================================================================
      formatters = {
        -- 🌲 Treesitter Injected 포맷터 옵션: 코드 블록 파싱 에러 시 파일 파손 방지 (안전 보존)
        injected = {
          options = {
            ignore_errors = true,
            -- ⚠️ [ktlint 버그 우회] Markdown 코드펜스 내 kotlin 블록을 injected 포맷팅 대상에서 제외
            --
            -- 증상: ```kotlin 코드펜스를 저장하면 코드펜스 내부 코드가 통째로 삭제됨.
            --
            -- 원인: ktlint가 파싱 실패 시 exit code 0 + stdout 빈 출력을 반환하는 버그.
            --   다른 모든 포맷터(Prettier, Ruff, StyLua, sql-formatter)는 파싱 실패 시
            --   exit code 1 이상을 반환하여 conform이 에러로 처리 → 코드 보존.
            --   ktlint만 유일하게 exit 0을 반환하므로 conform이 빈 stdout을 성공 결과로 오인,
            --   코드펜스 내용을 빈 문자열로 교체 → 코드 블록 전체 삭제.
            --
            --   * kotlin 단독 파일(.kt, .kts) 저장 시 ktlint 실행은 영향 없음 (정상 유지)
            --   * Markdown 내 다른 언어(python, js, ts, sql 등) 코드펜스 포맷팅도 정상 유지
            --
            -- TODO: ktlint가 파싱 실패 시 exit code 1+를 반환하도록 수정되면
            --   아래 lang_to_formatters 블록을 제거하여 원복하세요.
            lang_to_formatters = {
              kotlin = {}, -- ktlint 파싱 실패 exit code 0 버그 → injected 대상 제외
              -- Python 코드 블록은 포맷(ruff_format)만: 자동 수정(ruff_fix)까지 하면 "쓰지 않는 import" 로 보고
              -- 문서 예제의 import 를 지웠음 (```python import os ...``` → import 삭제, 실측)
              python = { 'ruff_format' },
            },
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
          prepend_args = get_smart_stylua_prepend_args,
        },

        -- 셸 스크립트 (위 get_shfmt_args 설명)
        shfmt = {
          args = get_shfmt_args,
        },

        -- Kotlin: 편집기 공통 포맷 래퍼(scripts/format/format kotlin)로 실행
        -- ● ktlint 는 포맷 결과를 출력한 뒤에도 자동으로 고칠 수 없는 규칙 위반(파일 이름 PascalCase, import foo.* 등)이
        --   남으면 종료 코드 1 을 내서, conform 이 실패로 보고 포맷 결과 전체를 버렸음 (Kotlin 파일이 정리되지 않음, 실측)
        -- ● 그렇다고 exit_codes = { 0, 1 } 로만 받으면, 파싱 실패 때 ktlint 가 내는 빈 출력이 그대로 적용되어 파일이 비워짐
        --   → 래퍼가 "종료 코드 0·1 이면서 출력이 비어 있지 않을 때만" 결과를 돌려주고, 그 밖에는 실패로 처리
        -- ● --stdin-path 로 파일 위치를 알려 그 파일이 속한 프로젝트의 .editorconfig 를 적용 (래퍼 안에서 지정)
        ktlint = {
          command = _G.DEVTOOLS2_DIR .. '/scripts/format/format',
          args = { 'kotlin', '$FILENAME' },
          stdin = true,
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
        -- Python: 프로젝트 ruff 설정 우선, 없으면 글로벌 설정
        ruff_format = {
          prepend_args = get_smart_ruff_prepend_args,
        },
        ruff_fix = {
          prepend_args = get_smart_ruff_prepend_args,
        },
      },
    },
  },
}
