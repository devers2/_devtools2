-- ===========================================================================================
-- [DAP launch.json 자동 스캐폴딩 및 작성 가이드: dap_scaffold]
-- ===========================================================================================
--
-- 📌 [1. 모듈의 역할]
-- 1. 신규 프로젝트 최초 셋업 자동화:
--    - 프로젝트 루트에 `.vscode/launch.json` 파일이 없을 때 `<leader>dd`를 실행하면 자동 발동합니다.
--    - 5대 메이저 언어(Java, Python, Node.js, Go, Rust)를 스마트하게 자동 감지하고,
--      각 언어별 도메인에 맞춤화된 3대 필수값을 대화형으로 입력받아 표준 `.vscode/launch.json` 파일을
--      예쁘게 자동 생성한 후 즉시 첫 디버깅을 시작합니다.
-- 2. 0ms 고속 패스스루 (평소 동작):
--    - 이미 `.vscode/launch.json`이 존재하는 프로젝트에서는 이 모듈이 전혀 개입하지 않고 0ms 만에 통과하여
--      순정 `nvim-dap`의 초고속 디버깅 파이프라인이 유지됩니다.
--
-- ===========================================================================================
-- 📖 [2. .vscode/launch.json 작성 및 커스텀 가이드]
-- ===========================================================================================
--
-- ── A. 공통 구조 (Common Attributes) ────────────────────────────────────────────────────────
-- 모든 언어의 launch.json 설정 항목은 아래 공통 필드를 기반으로 합니다:
--
-- {
--   "version": "0.2.0",
--   "configurations": [
--     {
--       "name": "메뉴에 표시될 이름 (예: Java: api - GoonoELN (local))",  [필수]
--       "type": "어댑터 타입 (java, python, node, go, lldb 등)",           [필수]
--       "request": "launch (직접 실행) 또는 attach (외부 프로세스 연결)",     [필수]
--       "cwd": "작업 디렉토리 (기본값: ${workspaceFolder})",                [선택]
--       "args": "프로그램 인자 (문자열 또는 문자열 배열)",                    [선택]
--       "env": { "KEY": "VALUE" }  // 환경 변수 설정                       [선택]
--     }
--   ]
-- }
--
-- ── B. 언어별 특화 속성 및 실제 작성 예시 (Language Specifics) ──────────────────────────────
--
-- ☕ [Java / Spring Boot (Gradle / Maven)]
--   • type: "java"
--   • mainClass (필수): 실행할 메인 클래스 FQCN (예: "so.goono.GoonoELNApplication")
--   • projectName (선택): 멀티모듈 프로젝트인 경우 서브모듈명 지정 (예: "api", "batch")
--   • args (선택): Spring Boot 프로필 지정 (예: "--spring.profiles.active=local")
--   • vmArgs (선택): JVM 실행 옵션 (예: "-Xmx1024m -Dfile.encoding=UTF-8")
--   [예시]
--   {
--     "type": "java",
--     "name": "Java: api - GoonoELNApplication (local)",
--     "request": "launch",
--     "mainClass": "so.goono.GoonoELNApplication",
--     "projectName": "api",
--     "args": "--spring.profiles.active=local"
--   }
--
-- 🐍 [Python (FastAPI / Uvicorn / Django / 일반 스크립트)]
--   • type: "debugpy"
--   • module (웹 프레임워크): 실행할 모듈명 (예: "uvicorn")
--   • program (단일 스크립트): 실행할 파이썬 파일 경로 (예: "${workspaceFolder}/main.py")
--   • python (가상환경): 사용할 Python 인터프리터 경로 (예: "${workspaceFolder}/.venv/bin/python3")
--   • args: 실행 인자 및 포트 지정 (예: ["main:app", "--reload", "--port", "8000", "--host", "0.0.0.0"])
--   • env: 환경 변수 지정 (예: { "ENV": "local", "PYTHON_ENV": "local" })
--   • jinja / justMyCode: 템플릿 디버깅(true) 및 서드파티 라이브러리 스텝인 제외(false)
--   [예시 - FastAPI]
--   {
--     "type": "debugpy",
--     "name": "Python: main:app (local)",
--     "request": "launch",
--     "module": "uvicorn",
--     "args": ["main:app", "--reload", "--port", "8000", "--host", "0.0.0.0"],
--     "python": "${workspaceFolder}/.venv/bin/python3",
--     "cwd": "${workspaceFolder}",
--     "env": { "ENV": "local" }
--   }
--
-- 🟢 [Node.js / TypeScript]
--   • type: "node" (또는 "pwa-node")
--   • program (필수): 진입 스크립트 경로 (예: "${workspaceFolder}/src/index.ts")
--   • env: 환경 변수 지정 (예: { "NODE_ENV": "development", "PORT": "3000" })
--   • runtimeExecutable (선택): npm/tsx 등 런타임 실행기 (예: "npm", "tsx")
--   • runtimeArgs (선택): 런타임 인자 (예: ["run", "dev"])
--   [예시]
--   {
--     "type": "node",
--     "name": "Node: src/index.ts (development)",
--     "request": "launch",
--     "program": "${workspaceFolder}/src/index.ts",
--     "cwd": "${workspaceFolder}",
--     "env": { "NODE_ENV": "development", "PORT": "3000" }
--   }
--
-- 🐹 [Go / Golang (Delve)]
--   • type: "go"
--   • program (필수): 진입 파일 또는 패키지 디렉토리 (예: "${workspaceFolder}/main.go" 또는 "${workspaceFolder}/cmd/server")
--   • mode (선택): 실행 모드 (기본값: "auto")
--   • env (선택): 환경 변수 (예: { "ENV": "local" })
--   [예시]
--   {
--     "type": "go",
--     "name": "Go: main.go (local)",
--     "request": "launch",
--     "mode": "auto",
--     "program": "${workspaceFolder}/main.go",
--     "cwd": "${workspaceFolder}"
--   }
--
-- 🦀 [Rust (Cargo / CodeLLDB)]
--   • type: "lldb"
--   • program (필수): 빌드 바이너리 경로 (예: "${workspaceFolder}/target/debug/app")
--   • cwd: 작업 디렉토리
--   • stopOnEntry: 진입 시 정지 여부 (기본값: false)
--   • args: 실행 인자 (선택)
--   [예시]
--   {
--     "type": "lldb",
--     "name": "Rust: app (debug)",
--     "request": "launch",
--     "program": "${workspaceFolder}/target/debug/app",
--     "cwd": "${workspaceFolder}",
--     "stopOnEntry": false
--   }
--
-- ===========================================================================================

local M = {}

-- JSON 포맷팅 헬퍼 (2스페이스 들여쓰기 표준 출력)
local function pretty_json(tbl, indent)
  indent = indent or 0
  local spaces = string.rep('  ', indent)
  local next_spaces = string.rep('  ', indent + 1)
  if type(tbl) ~= 'table' then
    return vim.json.encode(tbl)
  end

  local is_array = vim.islist(tbl)
  local items = {}

  if is_array then
    if #tbl == 0 then
      return '[]'
    end
    for _, v in ipairs(tbl) do
      table.insert(items, next_spaces .. pretty_json(v, indent + 1))
    end
    return '[\n' .. table.concat(items, ',\n') .. '\n' .. spaces .. ']'
  else
    local keys = vim.tbl_keys(tbl)
    local priority_keys = {
      version = 1,
      configurations = 2,
      name = 3,
      type = 4,
      request = 5,
      mode = 6,
      mainClass = 7,
      projectName = 8,
      module = 9,
      program = 10,
      python = 11,
      args = 12,
      cwd = 13,
      env = 14,
      stopOnEntry = 15,
      jinja = 16,
      justMyCode = 17,
    }
    table.sort(keys, function(a, b)
      local pa = priority_keys[a] or 99
      local pb = priority_keys[b] or 99
      if pa ~= pb then
        return pa < pb
      end
      return a < b
    end)

    if #keys == 0 then
      return '{}'
    end
    for _, k in ipairs(keys) do
      local v = tbl[k]
      table.insert(items, next_spaces .. string.format('%q: ', k) .. pretty_json(v, indent + 1))
    end
    return '{\n' .. table.concat(items, ',\n') .. '\n' .. spaces .. '}'
  end
end

-- 프로젝트 언어/타입 자동 감지 (5대 메이저 언어)
function M.detect_project_type()
  -- [0.5순위: 프로젝트 명시적 선언 (Java 전용)]
  -- ※ MAIN_CLASS 는 클래스 기반 실행 구조를 가진 Java/Kotlin 고유의 설정 변수입니다.
  --   Python, Node, Go, Rust 등 파일/모듈 단위로 진입하는 언어는 .nvim.lua 에 MAIN_CLASS 를 두지 않으며,
  --   .nvim.lua 에 MAIN_CLASS 가 선언되어 있다면 의심할 여지 없이 100% Java 프로젝트로 확정합니다.
  if _G.MAIN_CLASS and _G.MAIN_CLASS ~= '' then
    return 'java'
  end

  -- [1순위: 활성 파일 컨텍스트] 현재 에디터에 열려 있는 파일이 명확한 소스 파일인 경우
  local cur_buf = vim.api.nvim_get_current_buf()
  if vim.api.nvim_buf_is_valid(cur_buf) then
    local ft = vim.bo[cur_buf].filetype
    local fname = vim.api.nvim_buf_get_name(cur_buf)
    if ft == 'python' or fname:match('%.py$') then
      return 'python'
    elseif ft == 'go' or fname:match('%.go$') then
      return 'go'
    elseif ft == 'rust' or fname:match('%.rs$') then
      return 'rust'
    elseif ft == 'typescript' or ft == 'javascript' or ft == 'typescriptreact' or ft == 'javascriptreact' or fname:match('%.[jt]sx?$') then
      return 'node'
    elseif ft == 'java' or ft == 'kotlin' or fname:match('%.java$') or fname:match('%.kt$') then
      return 'java'
    end
  end

  -- [2순위: 프로젝트 루트 마커 검사]
  local cwd = vim.fn.getcwd()

  -- 1. Java / Kotlin (Gradle / Maven)
  if
    vim.fn.filereadable(cwd .. '/build.gradle') == 1
    or vim.fn.filereadable(cwd .. '/build.gradle.kts') == 1
    or vim.fn.filereadable(cwd .. '/pom.xml') == 1
    or vim.fn.isdirectory(cwd .. '/src/main/java') == 1
    or vim.fn.isdirectory(cwd .. '/src/main/kotlin') == 1
  then
    return 'java'
  end

  -- 2. Rust (Cargo)
  if
    vim.fn.filereadable(cwd .. '/Cargo.toml') == 1
    or vim.fn.filereadable(cwd .. '/Cargo.lock') == 1
    or vim.fn.filereadable(cwd .. '/src/main.rs') == 1
  then
    return 'rust'
  end

  -- 3. Go (Golang)
  if
    vim.fn.filereadable(cwd .. '/go.mod') == 1
    or vim.fn.filereadable(cwd .. '/go.work') == 1
    or vim.fn.filereadable(cwd .. '/main.go') == 1
    or #vim.fn.globpath(cwd, '*.go', false, true) > 0
  then
    return 'go'
  end

  -- 4. Python
  if
    vim.fn.filereadable(cwd .. '/pyproject.toml') == 1
    or vim.fn.filereadable(cwd .. '/requirements.txt') == 1
    or vim.fn.filereadable(cwd .. '/Pipfile') == 1
    or vim.fn.filereadable(cwd .. '/manage.py') == 1
    or #vim.fn.globpath(cwd, '*.py', false, true) > 0
  then
    return 'python'
  end

  -- 5. Node.js (TypeScript / JavaScript)
  if
    vim.fn.filereadable(cwd .. '/package.json') == 1
    or vim.fn.filereadable(cwd .. '/tsconfig.json') == 1
  then
    return 'node'
  end

  return nil
end

-- 언어별 기본 진입점(Main Class / Entry / Binary) 추론
local function detect_default_entry(lang)
  local cwd = vim.fn.getcwd()
  if lang == 'java' then
    if _G.MAIN_CLASS and _G.MAIN_CLASS ~= '' then
      return _G.MAIN_CLASS
    end
    local app_files = vim.fn.globpath(cwd, 'src/main/java/**/*Application.java', false, true)
    if #app_files > 0 then
      local rel = app_files[1]:gsub('.*/src/main/java/', ''):gsub('%.java$', '')
      return rel:gsub('/', '.')
    end
    return ''
  elseif lang == 'python' then
    if vim.fn.filereadable(cwd .. '/main.py') == 1 then
      local content = vim.fn.readfile(cwd .. '/main.py')
      for _, line in ipairs(content) do
        if line:find('FastAPI') or line:find('app =') then
          return 'main:app'
        end
      end
      return 'main.py'
    elseif vim.fn.filereadable(cwd .. '/app.py') == 1 then
      return 'app.py'
    elseif vim.fn.filereadable(cwd .. '/manage.py') == 1 then
      return 'manage.py'
    end
    return 'main:app'
  elseif lang == 'node' then
    if vim.fn.filereadable(cwd .. '/package.json') == 1 then
      local content = table.concat(vim.fn.readfile(cwd .. '/package.json'), '\n')
      local ok, parsed = pcall(vim.json.decode, content)
      if ok and type(parsed) == 'table' and parsed.main then
        return parsed.main
      end
    end
    if vim.fn.filereadable(cwd .. '/src/index.ts') == 1 then
      return 'src/index.ts'
    elseif vim.fn.filereadable(cwd .. '/src/index.js') == 1 then
      return 'src/index.js'
    elseif vim.fn.filereadable(cwd .. '/index.js') == 1 then
      return 'index.js'
    elseif vim.fn.filereadable(cwd .. '/app.js') == 1 then
      return 'app.js'
    end
    return 'src/index.ts'
  elseif lang == 'go' then
    if vim.fn.filereadable(cwd .. '/main.go') == 1 then
      return 'main.go'
    end
    local cmd_mains = vim.fn.globpath(cwd, 'cmd/*/main.go', false, true)
    if #cmd_mains > 0 then
      local rel = cmd_mains[1]:gsub('.*/cmd/', 'cmd/')
      return rel
    end
    return 'main.go'
  elseif lang == 'rust' then
    if vim.fn.filereadable(cwd .. '/Cargo.toml') == 1 then
      local lines = vim.fn.readfile(cwd .. '/Cargo.toml')
      local in_package = false
      for _, line in ipairs(lines) do
        if line:find('^%s*%[package%]') then
          in_package = true
        elseif line:find('^%s*%[') then
          in_package = false
        elseif in_package then
          local name = line:match('name%s*=%s*["\']([^"\']+)["\']')
          if name and name ~= '' then
            return name
          end
        end
      end
    end
    return vim.fn.fnamemodify(cwd, ':t')
  end
  return ''
end

-- 언어별 기본 서브모듈 추론
local function detect_default_submodule(lang)
  local cwd = vim.fn.getcwd()
  if lang == 'java' then
    local settings_file = vim.fn.filereadable(cwd .. '/settings.gradle') == 1 and (cwd .. '/settings.gradle')
      or (vim.fn.filereadable(cwd .. '/settings.gradle.kts') == 1 and (cwd .. '/settings.gradle.kts'))
    if settings_file then
      local lines = vim.fn.readfile(settings_file)
      for _, line in ipairs(lines) do
        local mod = line:match("include%s*['\":]+([%w_%-]+)")
        if mod and mod ~= '' then
          return mod
        end
      end
    end
  end
  return ''
end

-- Python 가상환경(venv) 폴더명 자동 감지
local function detect_python_venv_name()
  local cwd = vim.fn.getcwd()
  local is_win = vim.fn.has('win32') == 1

  -- 1) 표준 후보 디렉토리 (.venv, venv)
  local candidates = { '.venv', 'venv' }
  for _, name in ipairs(candidates) do
    local bin_path = is_win and (cwd .. '/' .. name .. '/Scripts/python.exe')
      or (cwd .. '/' .. name .. '/bin/python3')
    local bin_alt = is_win and (cwd .. '/' .. name .. '/Scripts/python.exe')
      or (cwd .. '/' .. name .. '/bin/python')
    if vim.fn.filereadable(bin_path) == 1 or vim.fn.filereadable(bin_alt) == 1 then
      return name
    end
  end

  -- 2) 커스텀 venv 패턴 (*venv* 등, 예: venv_math)
  local matches = vim.fn.globpath(cwd, '*venv*', false, true)
  for _, path in ipairs(matches) do
    if vim.fn.isdirectory(path) == 1 then
      local folder_name = vim.fn.fnamemodify(path, ':t')
      local bin_path = is_win and (path .. '/Scripts/python.exe') or (path .. '/bin/python3')
      local bin_alt = is_win and (path .. '/Scripts/python.exe') or (path .. '/bin/python')
      if vim.fn.filereadable(bin_path) == 1 or vim.fn.filereadable(bin_alt) == 1 then
        return folder_name
      end
    end
  end

  return '.venv'
end

-- 언어별 2번째 파라미터 기본값 추론
local function detect_default_param2(lang)
  if lang == 'java' then
    return detect_default_submodule(lang)
  elseif lang == 'python' then
    return detect_python_venv_name()
  elseif lang == 'rust' then
    return 'debug'
  end
  return ''
end

-- 언어별 3번째 파라미터 기본값 추론
local function detect_default_param3(lang)
  if lang == 'java' then
    return 'local'
  elseif lang == 'python' then
    return 'local'
  elseif lang == 'node' then
    return 'development'
  elseif lang == 'go' then
    return 'local'
  elseif lang == 'rust' then
    return ''
  end
  return 'local'
end

-- 언어별 도메인에 특화된 3대 질문 정의
local LANGUAGE_PROMPTS = {
  java = {
    q1 = '1. Main Class (진입 클래스명, 예: com.example.Application): ',
    q2 = '2. Sub Module (하위 모듈명 / 싱글 프로젝트면 비우기): ',
    q3 = '3. Profile (Spring Profile / 예: local, dev / 비우면 미지정): ',
  },
  python = {
    q1 = '1. Main / Entry (진입 파일 또는 모듈명, 예: main:app, main.py): ',
    q2 = '2. Virtualenv (가상환경 폴더명, 예: .venv, venv_math): ',
    q3 = '3. Profile (실행 환경 ENV / 예: local, dev / 비우면 미지정): ',
  },
  node = {
    q1 = '1. Entry Script (진입 파일 경로, 예: src/index.ts): ',
    q2 = '2. Sub Module / Package (모노레포 패키지 / 싱글이면 비우기): ',
    q3 = '3. Profile (NODE_ENV / 예: development, local / 비우면 미지정): ',
  },
  go = {
    q1 = '1. Entry / Program (진입 파일 또는 디렉토리, 예: main.go, .): ',
    q2 = '2. Package / Subdir (하위 패키지 경로 / 루트면 비우기): ',
    q3 = '3. Profile (실행 환경 ENV / 예: local, dev / 비우면 미지정): ',
  },
  rust = {
    q1 = '1. Binary Name (실행 바이너리 또는 패키지명): ',
    q2 = '2. Build Mode (빌드 모드, debug / release): ',
    q3 = '3. Program Args (실행 인자 / 없으면 비우기): ',
  },
}

-- 3대 필수값 대화형 입력 처리 (언어별 맞춤 3-Prompt)
local function prompt_three_inputs(lang, on_complete)
  local prompts = LANGUAGE_PROMPTS[lang] or LANGUAGE_PROMPTS.java
  local default_q1 = detect_default_entry(lang)
  local default_q2 = detect_default_param2(lang)
  local default_q3 = detect_default_param3(lang)

  vim.ui.input({
    prompt = prompts.q1,
    default = default_q1,
  }, function(val1)
    if val1 == nil then
      vim.notify('디버그 설정 생성이 취소되었습니다.', vim.log.levels.WARN, { title = 'DAP' })
      on_complete(nil)
      return
    end

    vim.ui.input({
      prompt = prompts.q2,
      default = default_q2,
    }, function(val2)
      if val2 == nil then
        vim.notify('디버그 설정 생성이 취소되었습니다.', vim.log.levels.WARN, { title = 'DAP' })
        on_complete(nil)
        return
      end

      vim.ui.input({
        prompt = prompts.q3,
        default = default_q3,
      }, function(val3)
        if val3 == nil then
          vim.notify('디버그 설정 생성이 취소되었습니다.', vim.log.levels.WARN, { title = 'DAP' })
          on_complete(nil)
          return
        end

        on_complete({
          q1 = vim.trim(val1),
          q2 = vim.trim(val2),
          q3 = vim.trim(val3),
        })
      end)
    end)
  end)
end

-- 언어별 launch.json 설정 객체 구성
local function build_configuration(lang, answers)
  local q1 = answers.q1
  local q2 = answers.q2
  local q3 = answers.q3

  if lang == 'java' then
    local short_name = q1:match('[^%.]+$') or q1
    local display_name = 'Java: '
      .. (q2 ~= '' and (q2 .. ' - ') or '')
      .. short_name
      .. (q3 ~= '' and (' (' .. q3 .. ')') or '')

    local config = {
      type = 'java',
      name = display_name,
      request = 'launch',
      mainClass = q1,
    }
    if q2 ~= '' then
      config.projectName = q2
    end
    if q3 ~= '' then
      config.args = '--spring.profiles.active=' .. q3
    end
    return config
  elseif lang == 'python' then
    local venv_name = q2 ~= '' and q2 or '.venv'
    local is_win = vim.fn.has('win32') == 1
    local python_bin = '${workspaceFolder}/' .. venv_name .. (is_win and '/Scripts/python.exe' or '/bin/python3')

    local display_name = 'Python: '
      .. q1
      .. (q3 ~= '' and (' (' .. q3 .. ')') or '')

    local env_val = q3 ~= '' and { ENV = q3, PYTHON_ENV = q3 } or nil

    if q1:find(':') then
      local config = {
        type = 'debugpy',
        name = display_name,
        request = 'launch',
        module = 'uvicorn',
        args = { q1, '--reload', '--port', '8000', '--host', '0.0.0.0' },
        python = python_bin,
        cwd = '${workspaceFolder}',
        jinja = true,
        justMyCode = false,
      }
      if env_val then
        config.env = env_val
      end
      return config
    else
      local config = {
        type = 'debugpy',
        name = display_name,
        request = 'launch',
        program = '${workspaceFolder}/' .. q1,
        python = python_bin,
        cwd = '${workspaceFolder}',
      }
      if env_val then
        config.env = env_val
      end
      return config
    end
  elseif lang == 'node' then
    local display_name = 'Node: '
      .. (q2 ~= '' and (q2 .. ' - ') or '')
      .. q1
      .. (q3 ~= '' and (' (' .. q3 .. ')') or '')

    local cwd_val = q2 ~= '' and ('${workspaceFolder}/' .. q2) or '${workspaceFolder}'
    local config = {
      type = 'node',
      name = display_name,
      request = 'launch',
      program = '${workspaceFolder}/' .. (q2 ~= '' and (q2 .. '/') or '') .. q1,
      cwd = cwd_val,
    }
    if q3 ~= '' then
      config.env = { NODE_ENV = q3 }
    end
    return config
  elseif lang == 'go' then
    local display_name = 'Go: '
      .. (q2 ~= '' and (q2 .. ' - ') or '')
      .. q1
      .. (q3 ~= '' and (' (' .. q3 .. ')') or '')

    local cwd_val = q2 ~= '' and ('${workspaceFolder}/' .. q2) or '${workspaceFolder}'
    local config = {
      type = 'go',
      name = display_name,
      request = 'launch',
      mode = 'auto',
      program = '${workspaceFolder}/' .. (q2 ~= '' and (q2 .. '/') or '') .. q1,
      cwd = cwd_val,
    }
    if q3 ~= '' then
      config.env = { ENV = q3, GO_ENV = q3 }
    end
    return config
  elseif lang == 'rust' then
    local mode = (q2 == 'release') and 'release' or 'debug'
    local display_name = 'Rust: ' .. q1 .. ' (' .. mode .. ')'

    local config = {
      type = 'lldb',
      name = display_name,
      request = 'launch',
      program = '${workspaceFolder}/target/' .. mode .. '/' .. q1,
      cwd = '${workspaceFolder}',
      stopOnEntry = false,
    }
    if q3 ~= '' then
      config.args = vim.split(q3, '%s+')
    end
    return config
  end

  return nil
end

-- .vscode/launch.json 확인 및 필요시 대화형 자동 생성
function M.ensure_launch_json(on_ready)
  on_ready = on_ready or function() end
  local cwd = vim.fn.getcwd()
  local launch_path = cwd .. '/.vscode/launch.json'

  -- 1. 이미 파일이 존재하면 즉시 진행 (0ms)
  if vim.fn.filereadable(launch_path) == 1 then
    on_ready(true)
    return
  end

  -- 2. 파일이 없으면 프로젝트 언어 판별
  local detected_lang = M.detect_project_type()

  local function proceed_with_lang(lang)
    prompt_three_inputs(lang, function(answers)
      if not answers or answers.q1 == '' then
        on_ready(false)
        return
      end

      local config = build_configuration(lang, answers)
      if not config then
        on_ready(false)
        return
      end

      local launch_data = {
        version = '0.2.0',
        configurations = { config },
      }

      vim.fn.mkdir(cwd .. '/.vscode', 'p')
      local f = io.open(launch_path, 'w')
      if f then
        f:write(pretty_json(launch_data) .. '\n')
        f:close()
        vim.notify(
          string.format('🎉 .vscode/launch.json 파일이 생성되었습니다!\n설정: %s', config.name),
          vim.log.levels.INFO,
          { title = 'DAP Scaffold' }
        )
        on_ready(true)
      else
        vim.notify('❌ .vscode/launch.json 파일 생성에 실패했습니다.', vim.log.levels.ERROR, { title = 'DAP Scaffold' })
        on_ready(false)
      end
    end)
  end

  if detected_lang then
    proceed_with_lang(detected_lang)
  else
    vim.ui.select({
      '1. Java (Spring Boot / Gradle / Maven)',
      '2. Python (FastAPI / Django / Script)',
      '3. Node.js (TypeScript / JavaScript)',
      '4. Go (Golang / Delve)',
      '5. Rust (Cargo / CodeLLDB)',
    }, {
      prompt = '프로젝트 언어 유형을 선택해 주세요: ',
    }, function(choice)
      if not choice then
        vim.notify('디버그 설정 생성이 취소되었습니다.', vim.log.levels.WARN, { title = 'DAP' })
        on_ready(false)
        return
      end

      local lang = 'java'
      if choice:find('Python') then
        lang = 'python'
      elseif choice:find('Node') then
        lang = 'node'
      elseif choice:find('Go') then
        lang = 'go'
      elseif choice:find('Rust') then
        lang = 'rust'
      end
      proceed_with_lang(lang)
    end)
  end
end

return M
