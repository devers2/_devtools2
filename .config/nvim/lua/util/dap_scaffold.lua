-- ===========================================================================================
-- [DAP launch.json 자동 스캐폴딩 및 작성 가이드: dap_scaffold]
-- ===========================================================================================
--
-- 📌 [1. 모듈의 역할]
-- 1. 신규 프로젝트 최초 셋업 자동화:
--    - 프로젝트 루트에 `.vscode/launch.json` 파일이 없을 때 `<leader>dd`를 실행하면 자동 발동합니다.
--    - 프로젝트 언어(Java, Python, Node.js)를 자동 감지하고, 3대 필수값(Main Class, Sub Module, Profile)을
--      대화형으로 입력받아 표준 `.vscode/launch.json` 파일을 예쁘게 자동 생성한 후 즉시 첫 디버깅을 시작합니다.
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
--   • type: "python"
--   • module (웹 프레임워크): 실행할 모듈명 (예: "uvicorn")
--   • program (단일 스크립트): 실행할 파이썬 파일 경로 (예: "${workspaceFolder}/main.py")
--   • args: 실행 인자 및 포트 지정 (예: ["main:app", "--reload", "--port", "8000", "--host", "127.0.0.1"])
--   • env: 환경 변수 지정 (예: { "ENV": "local", "PYTHON_ENV": "local" })
--   • jinja / justMyCode: 템플릿 디버깅(true) 및 서드파티 라이브러리 스텝인 제외(false)
--   [예시 - FastAPI]
--   {
--     "type": "python",
--     "name": "Python: main:app (local)",
--     "request": "launch",
--     "module": "uvicorn",
--     "args": ["main:app", "--reload", "--port", "8000", "--host", "127.0.0.1"],
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
-- 🐹 [Go / 🦀 Rust (향후 확장 참고)]
--   • Go: { "type": "go", "request": "launch", "program": "${workspaceFolder}/main.go" }
--   • Rust: { "type": "lldb", "request": "launch", "program": "${workspaceFolder}/target/debug/app" }
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
      mainClass = 6,
      projectName = 7,
      module = 8,
      program = 9,
      args = 10,
      cwd = 11,
      env = 12,
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

-- 프로젝트 언어/타입 자동 감지
function M.detect_project_type()
  local cwd = vim.fn.getcwd()
  if
    vim.fn.filereadable(cwd .. '/build.gradle') == 1
    or vim.fn.filereadable(cwd .. '/build.gradle.kts') == 1
    or vim.fn.filereadable(cwd .. '/pom.xml') == 1
    or _G.MAIN_CLASS
    or vim.fn.isdirectory(cwd .. '/src/main/java') == 1
  then
    return 'java'
  end

  if
    vim.fn.filereadable(cwd .. '/pyproject.toml') == 1
    or vim.fn.filereadable(cwd .. '/requirements.txt') == 1
    or vim.fn.filereadable(cwd .. '/Pipfile') == 1
    or vim.fn.filereadable(cwd .. '/manage.py') == 1
    or #vim.fn.globpath(cwd, '*.py', false, true) > 0
  then
    return 'python'
  end

  if
    vim.fn.filereadable(cwd .. '/package.json') == 1
    or vim.fn.filereadable(cwd .. '/tsconfig.json') == 1
  then
    return 'node'
  end

  return nil
end

-- 언어별 기본 진입점(Main Class / Entry) 추론
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

-- 언어별 기본 프로필 추론
local function detect_default_profile(lang)
  if lang == 'java' then
    return 'local'
  elseif lang == 'python' then
    return 'local'
  elseif lang == 'node' then
    return 'development'
  end
  return 'local'
end

-- 3대 필수값(Main Class, Sub Module, Profile) 대화형 입력 처리
local function prompt_three_inputs(lang, on_complete)
  local default_entry = detect_default_entry(lang)
  local default_submodule = detect_default_submodule(lang)
  local default_profile = detect_default_profile(lang)

  local entry_prompt = lang == 'java' and '1. Main Class (진입 클래스명, 예: com.example.Application): '
    or '1. Main / Entry (진입 파일 또는 모듈명, 예: main:app, app.py): '

  vim.ui.input({
    prompt = entry_prompt,
    default = default_entry,
  }, function(entry_val)
    if entry_val == nil then
      vim.notify('디버그 설정 생성이 취소되었습니다.', vim.log.levels.WARN, { title = 'DAP' })
      on_complete(nil)
      return
    end

    vim.ui.input({
      prompt = '2. Sub Module (하위 모듈명 / 싱글 프로젝트면 비우기): ',
      default = default_submodule,
    }, function(submod_val)
      if submod_val == nil then
        vim.notify('디버그 설정 생성이 취소되었습니다.', vim.log.levels.WARN, { title = 'DAP' })
        on_complete(nil)
        return
      end

      vim.ui.input({
        prompt = '3. Profile (실행 프로필 / 예: local, dev / 비우면 미지정): ',
        default = default_profile,
      }, function(profile_val)
        if profile_val == nil then
          vim.notify('디버그 설정 생성이 취소되었습니다.', vim.log.levels.WARN, { title = 'DAP' })
          on_complete(nil)
          return
        end

        on_complete({
          entry = vim.trim(entry_val),
          submodule = vim.trim(submod_val),
          profile = vim.trim(profile_val),
        })
      end)
    end)
  end)
end

-- 언어별 launch.json 설정 객체 구성
local function build_configuration(lang, answers)
  local entry = answers.entry
  local submodule = answers.submodule
  local profile = answers.profile

  if lang == 'java' then
    local short_name = entry:match('[^%.]+$') or entry
    local display_name = 'Java: '
      .. (submodule ~= '' and (submodule .. ' - ') or '')
      .. short_name
      .. (profile ~= '' and (' (' .. profile .. ')') or '')

    local config = {
      type = 'java',
      name = display_name,
      request = 'launch',
      mainClass = entry,
    }
    if submodule ~= '' then
      config.projectName = submodule
    end
    if profile ~= '' then
      config.args = '--spring.profiles.active=' .. profile
    end
    return config
  elseif lang == 'python' then
    local display_name = 'Python: '
      .. (submodule ~= '' and (submodule .. ' - ') or '')
      .. entry
      .. (profile ~= '' and (' (' .. profile .. ')') or '')

    local cwd_val = submodule ~= '' and ('${workspaceFolder}/' .. submodule) or '${workspaceFolder}'
    local env_val = profile ~= '' and { ENV = profile, PYTHON_ENV = profile } or nil

    if entry:find(':') then
      local config = {
        type = 'python',
        name = display_name,
        request = 'launch',
        module = 'uvicorn',
        args = { entry, '--reload', '--port', '8000', '--host', '127.0.0.1' },
        cwd = cwd_val,
        jinja = true,
        justMyCode = false,
      }
      if env_val then
        config.env = env_val
      end
      return config
    else
      local config = {
        type = 'python',
        name = display_name,
        request = 'launch',
        program = '${workspaceFolder}/' .. (submodule ~= '' and (submodule .. '/') or '') .. entry,
        cwd = cwd_val,
      }
      if env_val then
        config.env = env_val
      end
      return config
    end
  elseif lang == 'node' then
    local display_name = 'Node: '
      .. (submodule ~= '' and (submodule .. ' - ') or '')
      .. entry
      .. (profile ~= '' and (' (' .. profile .. ')') or '')

    local cwd_val = submodule ~= '' and ('${workspaceFolder}/' .. submodule) or '${workspaceFolder}'
    local config = {
      type = 'node',
      name = display_name,
      request = 'launch',
      program = '${workspaceFolder}/' .. (submodule ~= '' and (submodule .. '/') or '') .. entry,
      cwd = cwd_val,
    }
    if profile ~= '' then
      config.env = { NODE_ENV = profile }
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
      if not answers or answers.entry == '' then
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
    }, {
      prompt = '프로젝트 언어 유형을 선택해 주세요: ',
    }, function(choice)
      if not choice then
        vim.notify('디버그 설정 생성이 취소되었습니다.', vim.log.levels.WARN, { title = 'DAP' })
        on_ready(false)
        return
      end

      local lang = choice:find('Java') and 'java' or (choice:find('Python') and 'python' or 'node')
      proceed_with_lang(lang)
    end)
  end
end

return M
