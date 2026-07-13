--[[
===========================================================================================
[로컬 프로젝트 설정 가이드: .nvim.lua]
===========================================================================================
Neovim은 실행 디렉토리의 `.nvim.lua` 파일을 읽어 프로젝트별 맞춤 설정을 적용할 수 있습니다.
보안을 위해 처음 파일을 생성하거나 변경하면 Neovim 하단에 알림이 뜹니다.
  1. 'v'를 눌러 내용을 확인합니다.
  2. 내용이 안전하다면 ':trust' 를 눌러 승인해야 정상적으로 로드됩니다.

사용 가능한 주요 전역 변수:
  - PROJECT_ROOT (string): 프로젝트의 최상위 루트 경로를 지정합니다.
    (예: PROJECT_ROOT = "./" 또는 PROJECT_ROOT = "../my-project")
    지정 시 자동 루트 탐색 로직을 건너뛰고 해당 경로를 즉시 사용합니다.

  - JDK_VERSION (number): 프로젝트에서 사용할 Java 버전을 명시합니다. (8, 17, 21, 25 중 하나)
    (예: JDK_VERSION = 17)
    지정 시 build.gradle/pom.xml 탐색 없이 해당 버전의 JDK를 즉시 할당합니다.

  - MAIN_CLASS (string): 프로젝트의 메인 실행 클래스(패키지 포함)를 지정합니다.
    (예: MAIN_CLASS = "com.example.DemoApplication")
    지정 시 Neovim 시작(대시보드 포함)과 동시에 해당 자바 파일을 자동으로 열어
    JDTLS 서버가 즉시 구동되도록 유도합니다.

예시 (.nvim.lua):
    PROJECT_ROOT = "./my-project"
    JDK_VERSION = 21
    MAIN_CLASS = "com.example.DemoApplication"

※ _G.PROJECT_ROOT, _G.JDK_VERSION, _G.MAIN_CLASS 는 반드시 런타임 시점에 전역 변수를 직접 참조하여 사용해야 합니다.
===========================================================================================
--]]

-- [전역 로그 함수] 파일 어디서든 호출 가능하도록 최상단 정의
_G.log_jdtls = function(msg)
  local log_path = vim.lsp.log.get_filename()
  if log_path then
    local f = io.open(log_path, 'a')
    if f then
      local timestamp = os.date('%Y-%m-%d %H:%M:%S')
      -- [START] 태그 없이 타임스탬프와 함께 정갈하게 기록
      f:write(string.format('[%s] [JDTLS] %s\n', timestamp, msg))
      f:close()
    end
  end
end

local gradle_cache_error_notified = false
local buildship_error_notified = false
local unresolved_dependency_notified = false

return {
  {
    'mfussenegger/nvim-jdtls',
    opts = function(_, opts)
      -- [지연 실행 가드]
      -- Java 파일을 열었을 때 OR .nvim.lua에 MAIN_CLASS가 정의된 경우에만 초기화를 진행합니다.
      -- 그 외(대시보드, 비-Java 프로젝트)에서는 사이드 이펙트(로그 삭제, 세션 기록) 없이 즉시 반환합니다.
      ---@diagnostic disable-next-line: undefined-field
      if vim.bo.filetype ~= 'java' and not _G.MAIN_CLASS then
        return opts
      end

      -- 시작 시 기존 로그 즉시 삭제 (현재 세션만 유지)
      local log_path = vim.lsp.log.get_filename()
      if log_path then
        local f = io.open(log_path, 'w')
        if f then
          f:close()
        end
      end

      local jdtls = require('jdtls')

      -- [루트 탐색 로직]
      -- 파일 위치에서 위로 거슬러 올라가며 프로젝트 최상위 루트를 검색
      -- 멀티 모듈(settings.gradle / parent pom.xml)과 일반 프로젝트 모두 자동 인식
      opts.root_dir = function(path)
        -- 0. 로컬 설정(.nvim.lua)에 PROJECT_ROOT가 정의된 경우 우선 사용 (상대 경로 대응)
        ---@diagnostic disable-next-line: undefined-field
        if _G.PROJECT_ROOT then
          ---@diagnostic disable-next-line: undefined-field
          return vim.fn.fnamemodify(_G.PROJECT_ROOT, ':p'):gsub('/$', '')
        end

        local current_path = path or vim.api.nvim_buf_get_name(0)
        local cwd = vim.fn.getcwd()
        -- 워크스페이스를 식별하는 핵심 마커 (멀티 모듈 루트 탐색용)
        local root_markers = { '.git', 'settings.gradle', 'gradlew', 'mvnw' }

        -- 1. nvim 실행 디렉토리(CWD) 기준 탐색 우선
        -- 현재 파일이 nvim이 실행된 위치(또는 그 상위 루트)의 하위에 있다면 해당 루트를 선택
        local cwd_root = require('jdtls.setup').find_root(root_markers, cwd)
        if cwd_root and current_path:find(cwd_root, 1, true) == 1 then
          return cwd_root
        end

        -- 2. nvim 실행 디렉토리(CWD) 기준 하위(파일 방향)로 탐색
        -- CWD가 워크스페이스의 부모(예: ~/workspaces)인 경우, 파일 경로상 가장 먼저 만나는 프로젝트 루트를 선택
        if current_path:find(cwd, 1, true) == 1 then
          local rel_path = current_path:sub(#cwd + 1)
          local segment_acc = cwd
          for segment in rel_path:gmatch('[^/]+') do
            segment_acc = segment_acc .. '/' .. segment
            if vim.fn.isdirectory(segment_acc) == 1 then
              for _, marker in ipairs(root_markers) do
                if
                  vim.fn.filereadable(segment_acc .. '/' .. marker) == 1
                  or vim.fn.isdirectory(segment_acc .. '/' .. marker) == 1
                then
                  return segment_acc
                end
              end
            end
          end
        end

        -- 3. 파일 위치 기준 상향 탐색 (파일이 CWD 밖에 있는 경우 등)
        local root = require('jdtls.setup').find_root(root_markers, current_path)
        if root then
          return root
        end
        -- 4. 폴백: 일반 프로젝트 또는 개별 모듈 마커 탐색
        return require('jdtls.setup').find_root({ 'build.gradle', 'pom.xml' }, current_path) or cwd
      end

      -- 프로젝트 루트 경로 확보
      local buf_name = vim.api.nvim_buf_get_name(0)
      -- 최종적으로 문자열임을 보장 (타입 재할당으로 인한 LSP 경고 방지)
      local root_str = tostring(type(opts.root_dir) == 'function' and opts.root_dir(buf_name) or opts.root_dir)

      -- [실행 정보 기록 시작] 모든 분석 로그보다 먼저 세션 헤더를 출력
      local project_name = vim.fn.fnamemodify(root_str, ':p:h:t')
      _G.log_jdtls('================================================================================')
      _G.log_jdtls(string.format('[SESSION] Project Name: %s', project_name:upper()))
      _G.log_jdtls('================================================================================')

      -- [자바 버전 탐색 및 JDK 결정]
      -- 프로젝트 설정 파일(build.gradle, pom.xml 등)을 분석하여 최적의 JDK를 자동으로 선택합니다.
      local function get_java_version()
        local project_root_local = root_str
        if not project_root_local or project_root_local == 'nil' then
          return nil, nil
        end

        local files = { '/build.gradle', '/build.gradle.kts', '/pom.xml' }
        for _, file in ipairs(files) do
          local f = io.open(project_root_local .. file, 'r')
          if f then
            local content = f:read('*all')
            f:close()
            -- 다양한 설정 방식(Groovy, Kotlin DSL, Maven)에 대응하는 통합 정규식
            local version = content:match('languageVersion%.of%((%d+)%)')
              or content:match('sourceCompatibility%s*=%s*[\'"]?([%d%.]+)[\'"]?')
              or content:match('<java%.version>([%d%.]+)</java%.version>')
              or content:match('<maven%.compiler%.source>([%d%.]+)</maven%.compiler%.source>')
            if version then
              -- '1.8' -> 8, '17' -> 17 등 숫자로 변환
              local v_num = tonumber(version:match('^1%.(%d+)$') or version)
              local source = file:match('gradle') and 'gradle' or 'maven'

              -- 그래들인 경우 wrapper 버전을 추가로 확인하여 로그 품질 향상
              if source == 'gradle' then
                local wf = io.open(project_root_local .. '/gradle/wrapper/gradle-wrapper.properties', 'r')
                if wf then
                  local w_content = wf:read('*all')
                  wf:close()
                  local g_ver = w_content:match('gradle%-([%d%.]+)%-')
                  if g_ver then
                    source = 'gradle ' .. g_ver
                  end
                end
              end
              _G.log_jdtls(string.format('Detected Java %s from %s', v_num, file))
              return v_num, source
            end
          end
        end

        -- 시스템 환경변수 JAVA_HOME에서 버전 추출 시도 (폴백 1)
        local env_java_home = os.getenv('JAVA_HOME')
        if env_java_home then
          local version = env_java_home:match('jdk%-(%d+)')
          if version then
            local v_num = tonumber(version)
            _G.log_jdtls(string.format('Detected Java %s from system JAVA_HOME', v_num))
            return v_num, 'system JAVA_HOME'
          end
        end

        -- PATH에 잡힌 java 명령의 실제 경로에서 버전 추출 시도 (폴백 2)
        local java_path = vim.fn.exepath('java')
        if java_path and java_path ~= '' then
          local version = java_path:match('jdk%-(%d+)')
          if version then
            local v_num = tonumber(version)
            _G.log_jdtls(string.format('Detected Java %s from system PATH (exepath)', v_num))
            return v_num, 'system PATH'
          end
        end

        _G.log_jdtls('No Java version found in build files or environment, using default (25)')
        return nil, 'default'
      end

      local java_version, detect_source
      ---@diagnostic disable-next-line: undefined-field
      if _G.JDK_VERSION then
        -- .nvim.lua에 명시된 버전 우선 사용
        ---@diagnostic disable-next-line: undefined-field
        java_version = tonumber(_G.JDK_VERSION)
        detect_source = '.nvim.lua'
        _G.log_jdtls(string.format('Using Java Version %s from .nvim.lua', java_version))
      else
        java_version, detect_source = get_java_version()
      end

      java_version = java_version or 25
      local target_java_name = 'JavaSE-25' -- 기본값
      local target_java_home = _G.DEVTOOLS2_DIR .. '/modules/java/jdk-25' -- 기본값

      if java_version <= 8 then
        target_java_name = 'JavaSE-1.8'
        target_java_home = _G.DEVTOOLS2_DIR .. '/modules/java/jdk-1.8'
      elseif java_version <= 17 then
        target_java_name = 'JavaSE-17'
        target_java_home = _G.DEVTOOLS2_DIR .. '/modules/java/jdk-17'
      elseif java_version <= 21 then
        target_java_name = 'JavaSE-21'
        target_java_home = _G.DEVTOOLS2_DIR .. '/modules/java/jdk-21'
      end

      -- [공통 JDK 결정]
      -- JDTLS 실행 및 Gradle 데몬 모두 동일한 JDK를 사용해야 합니다.
      -- JDTLS 1.17+ 최소 요구 사양이 JDK 21이므로, 프로젝트 JDK가 21 미만이면 JDK 21로 고정하고
      -- 21 이상이면 프로젝트 JDK를 그대로 사용합니다.
      local effective_jdk_home = (java_version >= 21) and target_java_home
        or (_G.DEVTOOLS2_DIR .. '/modules/java/jdk-21')

      -- [실행 정보 기록] LSP 로그 파일에 상세 정보를 기록 (JdtShowLogs로 확인 가능)
      _G.log_jdtls(string.format('Project Root : %s', root_str or 'N/A'))
      _G.log_jdtls(string.format('Java Version : %s (auto-detected from %s)', java_version, detect_source))
      _G.log_jdtls(string.format('Java Home    : %s', target_java_home))

      -- LazyVim의 기본 cmd에 JVM 메모리 최적화 옵션만 추가합니다.
      -- opts.cmd가 nil인 경우를 대비해 초기화
      opts.cmd = opts.cmd or { vim.fn.exepath('jdtls') }

      -- [JDTLS 실행 명령 재구성]
      -- JDTLS가 Gradle/Maven을 호출할 때 시스템의 다른 Java 버전을 멋대로 선택하는 것을 방지하기 위해,
      -- JDTLS 프로세스의 JAVA_HOME을 프로젝트 JDK로 강제 고정합니다.
      local jdtls_executable = tostring(type(opts.cmd) == 'table' and opts.cmd[1] or opts.cmd)

      -- Java 파일 진입 시점에 실행 파일이 실제로 존재하는지 확인 (없어도 첫 실행 시에는 조용히 넘어감)
      if jdtls_executable == nil or jdtls_executable == '' or vim.fn.executable(jdtls_executable) == 0 then
        -- 최초 실행 시(Mason이 설치 중인 경우) 알림을 생략하여 노이즈 제거
        _G.log_jdtls('JDTLS executable not found yet. It might be installing via Mason.')
        -- 폴백(fallback)으로 기본 명령어 설정
        jdtls_executable = 'jdtls'
      end

      -- JDTLS 프로세스의 JAVA_HOME을 effective_jdk_home으로 강제 설정합니다.
      local new_cmd = { 'env', 'JAVA_HOME=' .. effective_jdk_home, jdtls_executable }

      -- JVM 인자 및 데이터 디렉토리 설정 (Goono-ELN 오류 방지의 핵심)
      local workspace_dir = _G.NVIM_CACHE_DIR .. '/jdtls/' .. project_name

      -- 필수 인자 주입
      local mason_lombok_path = _G.NVIM_DATA_DIR .. '/mason/packages/jdtls/lombok.jar'
      vim.list_extend(new_cmd, {
        '--jvm-arg=-Xms4G',
        '--jvm-arg=-Xmx12G',
        '--jvm-arg=-XX:+UseG1GC',
        '--jvm-arg=-XX:+UseStringDeduplication',
        '--jvm-arg=-javaagent:' .. mason_lombok_path,
        '-data',
        workspace_dir,
      })

      opts.cmd = new_cmd

      opts.settings = {
        java = {
          -- [버그 방지] Inlay Hints 파라미터 이름 표시 기능 비활성화
          -- 최신 JDTLS에서 구버전 JDK(rt.jar) 라이브러리의 클래스를 스캔하다가
          -- Java Model Exception (code 969) 크래시를 유발하는 고질적 버그 방지
          inlayHints = {
            parameterNames = {
              enabled = 'none',
            },
          },
          -- [생산성] 저장 시 자동 액션 설정
          saveActions = {
            -- 파일 저장 시 사용하지 않는 import 제거 및 필요한 import 자동 추가
            organizeImports = true,
          },
          -- [멀티 모듈] 하위 프로젝트 탐색 설정
          import = {
            gradle = {
              enabled = true,
              -- Gradle 8.x 데몬 실행 JDK: JDTLS 실행과 동일한 effective_jdk_home을 사용합니다.
              -- (컴파일 대상 JDK는 gradle.properties의 org.gradle.java.installations.paths로 별도 관리)
              java = {
                home = effective_jdk_home,
              },
            },
            maven = { enabled = true },
          },
          -- [Eclipse 전역 환경설정 강제 주입: Spring Boot 3.2+ 호환성 유지용]
          -- 생성된 jdtls-global.epf 파일 안의 모든 규칙을 모든 프로젝트에 강제 적용합니다.
          settings = {
            url = 'file:' .. _G.DEVTOOLS2_DIR .. '/.config/nvim/jdtls-global.epf',
          },
          -- [개발 편의성] 자동 완성 및 코드 컨벤션
          completion = {
            -- 정적(static) 메서드 자동 완성 즐겨찾기 (프로젝트에 라이브러리가 없어도 에러 없음)
            favoriteStaticMembers = {
              'org.junit.jupiter.api.Assertions.*',
              'org.mockito.Mockito.*',
              'org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*',
              'org.springframework.test.web.servlet.result.MockMvcResultMatchers.*',
            },
            -- Spring Boot 3+ 기준 jakarta 우선 정렬
            importOrder = {
              'java',
              'jakarta',
              'javax', -- 레거시 라이브러리 호환용 폴백
              'com',
              'org',
            },
          },
          -- 빌드 구성 업데이트 상호작용 (해당 자동화가 RestartClassLoader 간섭을 유발함)
          configuration = {
            updateBuildConfiguration = 'interactive',
            runtimes = (function()
              local rt_list = {
                { name = 'JavaSE-25', path = _G.DEVTOOLS2_DIR .. '/modules/java/jdk-25' },
                { name = 'JavaSE-21', path = _G.DEVTOOLS2_DIR .. '/modules/java/jdk-21' },
                { name = 'JavaSE-17', path = _G.DEVTOOLS2_DIR .. '/modules/java/jdk-17' },
                { name = 'JavaSE-1.8', path = _G.DEVTOOLS2_DIR .. '/modules/java/jdk-1.8' },
              }
              local final_rt = {}
              for _, rt in ipairs(rt_list) do
                if rt.name == target_java_name then
                  rt.default = true
                  table.insert(final_rt, 1, rt) -- default를 맨 앞으로
                else
                  rt.default = false
                  table.insert(final_rt, rt)
                end
              end
              return final_rt
            end)(),
          },
          -- DevTools 환경에서의 최적화 옵션 (사용자 스니펫 반영)
          eclipse = { downloadSources = true },
          maven = { downloadSources = true },

          -- java-test 번들 오류 방지 (명시적 비활성화)
          test = {
            enabled = false, -- java-test 완전 비활성화
          },
        },
      }

      -- java-test 번들 오류 방지: LazyVim 설정에서 java-test 번들 로드를 원천 차단
      opts.test = false

      -- LSP Client Capabilities 지원 설정
      local extendedClientCapabilities = jdtls.extendedClientCapabilities
      extendedClientCapabilities.resolveCodeActionSupport = true
      -- Semantic Tokens 비활성화 (Content modified 에러 방지)
      ---@diagnostic disable-next-line: inject-field
      extendedClientCapabilities.semanticTokensProvider = false

      -- _java.reloadBundles.command not supported 오류 알림 원천 차단 (더미 핸들러 등록)
      -- client가 해당 명령어를 모른다고 에러 뱉는 것을 방지
      vim.lsp.commands['_java.reloadBundles.command'] = function(_, _)
        -- JDTLS는 이 명령어에 대해 구체적인 결과값을 예상하지 않음
        ---@diagnostic disable-next-line: redundant-return-value
        return {}
      end
      -- Invalid completion proposal 등의 내부 에러가 UI에 뜨지 않도록 핸들러 등록
      -- 원본 핸들러를 먼저 저장한 후 덮어써야 무한 재귀를 방지할 수 있습니다.
      local orig_resolve_handler = vim.lsp.handlers['completionItem/resolve']
      vim.lsp.handlers['completionItem/resolve'] = function(err, result, ctx, config)
        if err and err.code == -32603 then
          return -- 내부 에러(IllegalStateException: Invalid completion proposal) 무시
        end
        if orig_resolve_handler then
          return orig_resolve_handler(err, result, ctx, config)
        end
      end

      opts.jdtls = opts.jdtls or {}
      opts.jdtls.init_options = {
        extendedClientCapabilities = extendedClientCapabilities,
      }

      -- LazyVim의 LspAttach 이벤트가 발생하기 전에, jdtls 초기화 시점에 가장 먼저 개입하기 위해
      -- opts.on_attach가 아닌 opts.jdtls.on_attach 를 사용합니다.
      -- LazyVim은 백그라운드에서 LspAttach 이벤트 발생 시 자동(비동기)으로 setup_dap_main_class_configs를 호출하는데,
      -- 이 과정에서 resolveJavaExecutable 커맨드가 서버로 전송됩니다.
      -- 따라서 반드시 그보다 먼저(동기적으로) client.request를 가로채야 버그를 막을 수 있습니다.
      local default_on_attach = opts.jdtls.on_attach or function() end

      opts.jdtls.on_attach = function(client, bufnr)
        -- [버그 픽스] nvim-jdtls 플러그인이 project 인자를 누락하여
        -- 하지만 Lua에서는 배열의 마지막 요소가 nil이면 길이가 1인 배열로 잘라버려 에러가 발생합니다.
        -- 이를 막기 위해 nil 대신 vim.NIL(JSON의 null에 해당)을 삽입하여 배열 길이를 강제로 2로 유지시킵니다.
        -- projectName 인자는 원래 선택적(Optional)이므로 null로 전달해도 기본 JDK를 사용하도록 정상 동작합니다.
        local orig_request = client.request
        client.request = function(...)
          local args = { ... }
          local method_idx = type(args[1]) == 'string' and 1 or 2
          local method = args[method_idx]
          local params = args[method_idx + 1]

          if method == 'workspace/executeCommand' and params and type(params.arguments) == 'table' then
            if
              params.command == 'vscode.java.resolveJavaExecutable'
              or params.command == 'vscode.java.resolveClasspath'
            then
              if params.arguments[1] ~= nil and params.arguments[2] == nil then
                params.arguments[2] = vim.NIL
              end
            end
          end
          return orig_request(...)
        end

        -- 기존 jdtls.on_attach 실행
        default_on_attach(client, bufnr)

        -- 2. 핵심: 디버그 모듈 초기화 강제 호출 (사용자 스니펫 반영)
        -- Spring Boot DevTools(RestartClassLoader)와의 찰떡 호환성을 위해 hotcodereplace를 auto로 지정
        require('jdtls').setup_dap({
          hotcodereplace = 'auto',
          config_overrides = {},
        })

        -- 클라이언트 자체에서 java-test를 재차 시도하지 않도록 리셋 (안전하게 체크)
        if client.config and client.config.settings and client.config.settings.java then
          client.config.settings.java.configuration.runtimes = opts.settings.java.configuration.runtimes
        end

        -- [JDTLS 및 Gradle 동기화 오류 탐지 및 알림 로직]
        -- JDTLS에서 보내는 에러 메시지를 가로채어 해결 방법을 안내합니다.
        local function check_jdtls_workspace_error(result)
          if not result or not result.message then
            return
          end

          local msg = result.message
          -- 1. Gradle 데몬 동기화 오류 (캐시 손상 등)
          if
            (msg:find('Synchronize project') and msg:find('Gradle build'))
            or msg:find('Could not connect to Gradle daemon')
            or msg:find('Connection to Gradle daemon')
            or msg:find('Could not calculate build configuration')
          then
            if not gradle_cache_error_notified then
              gradle_cache_error_notified = true
              local g_ver = '버전미확인'
              local project_root = root_str
              if project_root then
                local wf = io.open(project_root .. '/gradle/wrapper/gradle-wrapper.properties', 'r')
                if wf then
                  local w_content = wf:read('*all')
                  wf:close()
                  g_ver = w_content:match('gradle%-([%d%.]+)%-') or g_ver
                end
              end

              local kill_cmd, rm_cmd
              if _G.OS_TYPE == _G.OS.WINDOWS then
                kill_cmd = 'wmic process where "commandline like \'%GradleDaemon%\'" call terminate'
                rm_cmd = 'Remove-Item -Recurse -Force ' .. _G.HOME_DIR .. '\\.gradle\\caches\\' .. g_ver
              else
                kill_cmd = "pkill -f '.*GradleDaemon.*'"
                rm_cmd = 'rm -rf ~/.gradle/caches/' .. g_ver
              end

              vim.schedule(function()
                vim.notify(
                  string.format(
                    'Gradle 캐시 손상이 의심됩니다.\n\n'
                      .. '1. 터미널에서 다음 명령 실행:\n   %s\n   %s\n\n'
                      .. '2. Neovim에서 다음 명령 실행:\n   :JdtWipeDataAndRestart',
                    kill_cmd,
                    rm_cmd
                  ),
                  vim.log.levels.ERROR,
                  { title = 'Gradle 동기화 오류 해결 방법', timeout = 15000 }
                )
              end)
            end
          end

          -- 2. Buildship Classpath Provider 누락 및 JDT 인덱스 손상 오류 (워크스페이스 붕괴)
          if
            msg:find('org.eclipse.buildship.core.classpathprovider')
            or msg:find('Failed to save JDT index')
            or msg:find('org.eclipse.core.internal.resources.ResourceException')
            or msg:find('Could not resolve project dependencies')
            or msg:find('Project.*does not exist')
          then
            if not buildship_error_notified then
              buildship_error_notified = true

              local rm_eclipse_cmd, rm_workspace_cmd
              if _G.OS_TYPE == _G.OS.WINDOWS then
                rm_eclipse_cmd =
                  'Get-ChildItem -Path . -Include .project, .classpath -File -Recurse | Remove-Item -Force\n   Get-ChildItem -Path . -Include .settings -Directory -Recurse | Remove-Item -Recurse -Force'
                rm_workspace_cmd = 'Remove-Item -Recurse -Force '
                  .. _G.NVIM_CACHE_DIR
                  .. '/jdtls/'
                  .. tostring(vim.fn.fnamemodify(root_str, ':t'))
              else
                rm_eclipse_cmd =
                  'find . -name ".project" -type f -delete\n   find . -name ".classpath" -type f -delete\n   find . -name ".settings" -type d -exec rm -rf {} +'
                rm_workspace_cmd = 'rm -rf '
                  .. _G.NVIM_CACHE_DIR
                  .. '/jdtls/'
                  .. tostring(vim.fn.fnamemodify(root_str, ':t'))
              end

              vim.schedule(function()
                vim.notify(
                  string.format(
                    'JDTLS 워크스페이스 캐시가 손상되었습니다. (의존성 로드 불가)\n\n'
                      .. '1. 터미널(프로젝트 루트)에서 다음 명령으로 꼬인 설정 파일 삭제:\n   %s\n\n'
                      .. '2. 워크스페이스 캐시 직접 삭제:\n   %s\n\n'
                      .. '3. Neovim을 완전히 재시작하세요.',
                    rm_eclipse_cmd,
                    rm_workspace_cmd
                  ),
                  vim.log.levels.ERROR,
                  { title = 'JDTLS 워크스페이스 손상 해결 방법', timeout = 20000 }
                )
              end)
            end
          end

          -- 3. 멀티 모듈 의존성 누락 에러 (모듈 빌드 선행 필요)
          if msg:find('Unresolved dependency') then
            if not unresolved_dependency_notified then
              unresolved_dependency_notified = true

              local build_cmd
              if _G.OS_TYPE == _G.OS.WINDOWS then
                build_cmd = '.\\gradlew.bat clean classes'
              else
                build_cmd = './gradlew clean classes'
              end

              vim.schedule(function()
                vim.notify(
                  string.format(
                    '멀티 모듈 의존성을 찾을 수 없습니다. (Unresolved dependency)\n\n'
                      .. '타 모듈이 아직 빌드되지 않아 참조할 수 없는 상태일 수 있습니다.\n'
                      .. '1. 터미널(프로젝트 루트)에서 다음 명령으로 전체 모듈 강제 빌드 수행:\n   %s\n\n'
                      .. '2. Neovim에서 다음 명령 실행 (또는 재시작):\n   :JdtWipeDataAndRestart',
                    build_cmd
                  ),
                  vim.log.levels.WARN,
                  { title = '의존성 누락 해결 방법', timeout = 15000 }
                )
              end)
            end
          end
        end

        local orig_show_message = client.handlers['window/showMessage'] or vim.lsp.handlers['window/showMessage']
        client.handlers['window/showMessage'] = function(err, result, ctx, config)
          check_jdtls_workspace_error(result)
          return orig_show_message(err, result, ctx, config)
        end

        local orig_log_message = client.handlers['window/logMessage'] or vim.lsp.handlers['window/logMessage']
        client.handlers['window/logMessage'] = function(err, result, ctx, config)
          check_jdtls_workspace_error(result)
          return orig_log_message(err, result, ctx, config)
        end

        local orig_language_status = client.handlers['language/status'] or vim.lsp.handlers['language/status']
        client.handlers['language/status'] = function(err, result, ctx, config)
          check_jdtls_workspace_error(result)
          if orig_language_status then
            return orig_language_status(err, result, ctx, config)
          end
        end
      end

      -- 로그 창 색상 및 가독성 유지 설정 (syntax 덮어씌워짐 방지 적용)
      -- 구문 그룹을 먼저 안전하게 전역 등록합니다. (조화로운 강조를 위해 배경색 제거)
      vim.api.nvim_set_hl(0, 'LogStart', { fg = '#2ca2c5', bold = true })
      vim.api.nvim_set_hl(0, 'LogSession', { fg = '#87af87', bold = true }) -- 차분한 연두색
      vim.api.nvim_set_hl(0, 'LogTime', { fg = '#5c6370' }) -- 회색 (타임스탬프)
      vim.api.nvim_set_hl(0, 'LogTag', { fg = '#c678dd', bold = true }) -- 보라색 ([JDTLS] 태그)

      vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufNewFile', 'FileType', 'BufWinEnter' }, {
        pattern = { '*.log', 'log' },
        callback = function()
          if vim.bo.filetype == 'log' or vim.fn.expand('%:e') == 'log' then
            -- 자동 줄바꿈
            vim.wo.wrap = true

            -- 다른 파일 타입 감지 플러그인이 텍스트 색상을 리셋하는 것을 막기 위해,
            -- 이벤트 처리가 완전히 끝난 후(syntax 분석 이후) 비동기적으로(schedule) 색상을 덧칠합니다.
            vim.schedule(function()
              vim.cmd([[
                " 구문 초기화
                syntax clear

                " 1. 에러/경고 처리 (기본 색상 지정)
                " [ERROR]로 시작하는 모든 줄은 일단 에러(빨간색)로 처리
                syntax match LogError /^\[ERROR\].*/

                " [ERROR] 줄 중 WARNING 키워드가 있으면 경고(주황색)로 덮어씀
                syntax match LogWarn  /^\[ERROR\].*\(WARNING\|Warning\|WARN\|Unsafe\|Policy watcher\).*/
                syntax match LogWarn  /^WARNING:.*/

                " [ERROR] 줄 중 무시 가능한 노이즈 패턴이 있으면 정보(회색)로 최종 덮어씀
                " (semantic_tokens, incubator 등을 포함하여 줄 전체를 일관되게 회색으로 만듦)
                syntax match LogInfo  /^\[ERROR\].*\(Invalid completion proposal\|JavaDebuggerServerPlugin\|BaseActivator\|Starting\|정보:\|INFO\|Registered\|incubator\|semantic_tokens\|Document changed\).*/
                syntax match LogInfo  /^[0-9]\+월 [0-9]\+, [0-9]\+ .*/
                syntax match LogInfo  /^\tat .*/  " 자바 스택 트래이스 줄

                " 2. 고정 요소 강조 (에러 패턴보다 나중에 정의하여 색상을 덮어씌움)
                " 타임스탬프 및 커스텀 태그 강조
                syntax match LogTime /^\[[0-9-]\+ [0-9:]\+\]/
                syntax match LogTag /\[JDTLS\]/

                " 시작 줄 (언제나 맨 위로 보이게)
                syntax match LogStart /^\[START\].*/

                " 세션 구분선 및 프로젝트 이름 (강조색)
                syntax match LogSession /.*\[SESSION\].*/
                syntax match LogSession /.*\[JDTLS\] =\{30,\}.*/

                highlight default link LogError ErrorMsg
                highlight default link LogWarn WarningMsg
                highlight default link LogInfo Comment
                highlight default link LogTime LogTime
                highlight default link LogTag LogTag
                highlight default link LogStart LogStart
                highlight default link LogSession LogSession
              ]])
            end)
          end
        end,
      })

      return opts
    end,
  },
  -- [MAIN_CLASS 자동 로딩 보조 플러그인 사양]
  -- .nvim.lua에 MAIN_CLASS가 정의되어 있으면 Neovim 시작 시 해당 파일을 자동으로 열어 JDTLS를 가동시킵니다.
  {
    name = 'java-main-class-autostart',
    dir = vim.fn.stdpath('config'),
    lazy = false,
    config = function()
      vim.api.nvim_create_autocmd('VimEnter', {
        callback = function()
          ---@diagnostic disable-next-line: undefined-field
          if _G.MAIN_CLASS then
            -- 이미 자바 파일이 열려있는지 확인 (중복 로딩 방지)
            for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
              if vim.bo[bufnr].filetype == 'java' then
                return
              end
            end

            ---@diagnostic disable-next-line: undefined-field
            local search_root = _G.PROJECT_ROOT and vim.fn.fnamemodify(_G.PROJECT_ROOT, ':p') or vim.fn.getcwd()
            ---@diagnostic disable-next-line: undefined-field
            local class_rel_path = _G.MAIN_CLASS:gsub('%.', '/') .. '.java'

            -- 효율적인 탐색: 일반적인 소스 경로 우선 확인 (성능 최적화)
            local found_path = nil
            local common_paths = {
              search_root .. 'src/main/java/' .. class_rel_path,
              search_root .. 'src/test/java/' .. class_rel_path,
              search_root .. class_rel_path,
            }
            for _, p in ipairs(common_paths) do
              if vim.fn.filereadable(p) == 1 then
                found_path = p
                break
              end
            end

            -- 소스 폴더에서 못 찾은 경우에만 전체 하위 디렉토리 glob 탐색 (폴백)
            if not found_path then
              local found = vim.fn.globpath(search_root, '/**/' .. class_rel_path, nil, true)
              if #found > 0 then
                found_path = found[1]
              end
            end

            if found_path then
              local ft = vim.bo.filetype
              -- 대시보드(alpha, snacks_dashboard 등)나 빈 화면인 경우
              if
                ft == 'alpha'
                or ft == 'snacks_dashboard'
                or ft == 'dashboard'
                or vim.api.nvim_buf_get_name(0) == ''
              then
                vim.schedule(function()
                  -- 1. 메인 클래스 파일을 버퍼 리스트에 추가 (창 전환 없음)
                  local java_buf = vim.fn.bufadd(found_path)
                  -- 2. 버퍼 내용을 로드
                  vim.fn.bufload(java_buf)
                  -- 3. 파일 타입을 java로 명시하여 jdtls 서버 가동 트리거
                  vim.api.nvim_set_option_value('filetype', 'java', { buf = java_buf })

                  if _G.log_jdtls then
                    _G.log_jdtls(
                      ---@diagnostic disable-next-line: undefined-field
                      string.format('MAIN_CLASS detected. JDTLS started in background for: %s', _G.MAIN_CLASS)
                    )
                  end
                end)
              end
            end
          end
        end,
      })
    end,
  },

  -- [Mason 자동 설치 설정]
  -- jdtls는 lspconfig에서 비활성화되어 있으므로(nvim-jdtls 사용) 명시적 목록에 추가
  {
    'mason-org/mason.nvim',
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { 'jdtls', 'basedpyright', 'ruff' })
    end,
  },
}
