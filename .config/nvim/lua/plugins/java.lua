--[[
===========================================================================================
[로컬 프로젝트 설정 가이드: .nvim/ 및 .vscode/ (SSOT 단일 원본)]
===========================================================================================
보안상 승인 알림(:trust)이 필요하고 관리가 분산되던 레거시 `.nvim.lua` 대신,
표준 JSON 파일(.nvim/ 또는 .vscode/)을 통해 VS Code와 설정을 100% 공유합니다.

탐색 우선순위:
  1. 프로젝트 루트의 `.nvim/` 디렉토리 (Neovim 전용 설정이 필요한 경우)
     - `.nvim/settings.json`
     - `.nvim/launch.json`
  2. 프로젝트 루트의 `.vscode/` 디렉토리 (VS Code와 공통 공유)
     - `.vscode/settings.json`
     - `.vscode/launch.json`
  3. 설정 파일이 없는 경우: 빌드 파일(build.gradle 등) 또는 시스템 기본값(Java 21 LTS)으로 폴백

주요 설정 매핑:
  - nvim.projectRoot (string)
    : settings.json에 지정 (예: "nvim.projectRoot": "./"). 미지정 시 워크스페이스 마커 자동 탐색.
  - java.import.gradle.java.home (string)
    : Gradle 데몬 및 JDTLS 구동용 JDK 경로 (예: "/var/opt/_devtools2/modules/java/jdk-21")
  - java.configuration.runtimes (array)
    : 컴파일 대상 런타임 목록 및 default 지정 (예: JavaSE-1.8 default -> Java 8 자동 인식)
  - launch.json 의 java configuration (mainClass)
    : 메인 실행 클래스 자동 감지 -> 시작 시 JDTLS 즉시 기동 및 DAP 디버깅에 공통 사용
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

return {
  {
    'mfussenegger/nvim-jdtls',
    opts = function(_, opts)
      -- ⚠️ 예전에는 여기서 lsp.log 를 비웠으나, 이 파일은 모든 LSP(eslint, basedpyright 등)가 함께 쓰는
      --    공용 로그라 다른 서버의 진단 기록까지 지워졌습니다. 이제 비우지 않고 이어서 기록합니다.
      --    (JDTLS 세션 시작은 log_jdtls 의 [SESSION] 줄로 구분됩니다)

      local jdtls = require('jdtls')

      -- [루트 탐색 로직]
      -- 파일 위치에서 위로 거슬러 올라가며 프로젝트 최상위 루트를 검색
      -- 멀티 모듈(settings.gradle / settings.gradle.kts / parent pom.xml)과 일반 프로젝트 모두 자동 인식
      -- 공통 프로젝트 설정 로더(util.project_config)를 단일 진실 공급원(SSOT)으로 사용합니다.
      -- 탐색 단계 (util.project_config):
      --   0. .nvim/settings.json 또는 .vscode/settings.json 의 nvim.projectRoot 커스텀 설정 확인 (최우선)
      --   1. nvim 실행 디렉토리(CWD) 기준 탐색 우선 (현재 파일이 CWD 또는 상위 루트 하위에 있는 경우)
      --   2. nvim 실행 디렉토리(CWD) 기준 하위(파일 방향) 탐색 (CWD가 워크스페이스의 부모인 경우)
      --   3. 파일 위치 기준 상향 탐색 (파일이 CWD 밖에 있는 경우 등)
      --   4. 폴백: 일반 프로젝트 또는 개별 모듈 마커 탐색
      opts.root_dir = function(path)
        return require('util.project_config').get_project_root(path or vim.api.nvim_buf_get_name(0))
      end

      -- 프로젝트 루트 경로 확보
      local buf_name = vim.api.nvim_buf_get_name(0)
      -- 최종적으로 문자열임을 보장 (타입 재할당으로 인한 LSP 경고 방지)
      local root_str = tostring(type(opts.root_dir) == 'function' and opts.root_dir(buf_name) or opts.root_dir)

      -- [자바 버전 탐색 헬퍼]
      local function get_jdk_info(v_num)
        if v_num <= 8 then
          return 'JavaSE-1.8', _G.DEVTOOLS2_DIR .. '/modules/java/jdk-1.8'
        elseif v_num <= 17 then
          return 'JavaSE-17', _G.DEVTOOLS2_DIR .. '/modules/java/jdk-17'
        elseif v_num <= 21 then
          return 'JavaSE-21', _G.DEVTOOLS2_DIR .. '/modules/java/jdk-21'
        else
          return 'JavaSE-25', _G.DEVTOOLS2_DIR .. '/modules/java/jdk-25'
        end
      end

      local function get_runtimes(target_name)
        local rt_list = {
          { name = 'JavaSE-25', path = _G.DEVTOOLS2_DIR .. '/modules/java/jdk-25' },
          { name = 'JavaSE-21', path = _G.DEVTOOLS2_DIR .. '/modules/java/jdk-21' },
          { name = 'JavaSE-17', path = _G.DEVTOOLS2_DIR .. '/modules/java/jdk-17' },
          { name = 'JavaSE-1.8', path = _G.DEVTOOLS2_DIR .. '/modules/java/jdk-1.8' },
        }
        local final_rt = {}
        for _, rt in ipairs(rt_list) do
          if rt.name == target_name then
            rt.default = true
            table.insert(final_rt, 1, rt) -- default를 맨 앞으로
          else
            rt.default = false
            table.insert(final_rt, rt)
          end
        end
        return final_rt
      end

      -- [프로젝트 설정 로더 헬퍼: .nvim (1순위) -> .vscode (2순위) -> 폴백]
      -- .nvim/ 또는 .vscode/ 아래의 settings.json 및 launch.json을 탐색하여 설정을 일원화합니다.
      -- util.project_config 모듈을 단일 진실 공급원(SSOT)으로 사용합니다.
      local function load_project_config(project_root_local)
        local pcfg = require('util.project_config')
        local settings, s_path = pcfg.get_settings(project_root_local)
        local main_cls, l_path = pcfg.get_main_class(project_root_local)
        return {
          settings = settings or {},
          main_class = main_cls,
          source_settings = s_path and (vim.fs.basename(vim.fs.dirname(s_path)) .. '/settings.json') or nil,
          source_launch = l_path and (vim.fs.basename(vim.fs.dirname(l_path)) .. '/launch.json') or nil,
        }
      end

      -- [자바 버전 탐색 및 JDK 결정]
      -- 프로젝트 설정 파일(build.gradle, build.gradle.kts, pom.xml 등)을 분석하여 최적의 JDK를 자동으로 선택합니다.
      local function get_java_version(project_root_local)
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
              or content:match('JavaLanguageVersion%.of%((%d+)%)')
              or content:match('JavaVersion%.VERSION_1_(%d+)')
              or content:match('JavaVersion%.VERSION_(%d+)')
              or content:match('["\']java["\']%s*:%s*([%d%.]+)')
              or content:match('["\']java["\']%s*=%s*([%d%.]+)')
              or content:match('sourceCompatibility%s*=%s*[\'"]?([%d%.]+)[\'"]?')
              or content:match('targetCompatibility%s*=%s*[\'"]?([%d%.]+)[\'"]?')
              or content:match('<java%.version>([%d%.]+)</java%.version>')
              or content:match('<maven%.compiler%.source>([%d%.]+)</maven%.compiler%.source>')
              or content:match('<maven%.compiler%.target>([%d%.]+)</maven%.compiler%.target>')
            if version then
              -- '1.8' -> 8, '17' -> 17 등 숫자로 변환
              local v_num = tonumber(version:match('^1%.(%d+)$') or version:match('^1_(%d+)$') or version)
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

        _G.log_jdtls('No Java version found in build files or environment, using default (21 LTS)')
        return nil, 'default (21 LTS)'
      end

      -- ===========================================================================================
      -- [JDTLS 실행 명령 런타임 동적 재구성] ⚠️ AI 수정 주의: 절대 정적 평가로 변경 금지!
      -- ===========================================================================================
      -- 1. 배경 및 원인:
      --    Neovim 시작 시점(opts 로드 시점)에는 프로젝트 루트의 설정(settings.json)이 아직 파싱되기 전입니다.
      --    따라서 `opts.cmd`를 정적으로 미리 평가해버리면 동적 JDK 설정을 읽지 못하고 기본값(예: JDK 25)으로 고정됩니다.
      --    Gradle 7.x/8.x 및 Spring Boot 2.7은 JDK 25(실험적 버전)에서 `TypeNotPresentException: Type T not present`
      --    크래시를 일으키므로, 반드시 실제 자바 버퍼/프로젝트에 attach되는 런타임 시점(`opts.full_cmd`)에
      --    동적으로 프로젝트 JDK 설정을 평가하여 `JAVA_HOME` 및 `cmd`를 생성해야 합니다.
      --
      -- 2. JDK 버전 및 실행 환경 결정 우선순위:
      --    ① .nvim/settings.json 또는 .vscode/settings.json (SSOT: java.import.gradle.java.home, java.configuration.runtimes)
      --    ② 프로젝트 빌드 스크립트 (build.gradle / build.gradle.kts / pom.xml) -> 자동 파싱
      --    ③ 시스템 환경변수 `JAVA_HOME` / `PATH` -> 3순위 탐색
      --    ④ 최종 기본 폴백 -> `JDK 21 LTS` (가장 안정적이며 Gradle 7/8/Spring Boot 2/3 호환성 보장)
      -- ===========================================================================================
      opts.full_cmd = function(o)
        local current_path = vim.api.nvim_buf_get_name(0)
        local root = (type(o.root_dir) == 'function' and o.root_dir(current_path)) or o.root_dir or vim.fn.getcwd()
        local p_name = (type(o.project_name) == 'function' and o.project_name(root)) or (root and vim.fs.basename(root)) or '_default'

        -- [실행 정보 기록 시작] 세션 헤더 출력
        _G.log_jdtls('================================================================================')
        _G.log_jdtls(string.format('[SESSION] Project Name: %s', p_name:upper()))
        _G.log_jdtls('================================================================================')

        -- [프로젝트 설정 통합 로드 (.nvim 우선 -> .vscode 차선)]
        local p_cfg = load_project_config(root)
        local p_settings = p_cfg.settings or {}

        -- launch.json의 첫 번째 Java launch 설정에서 mainClass 자동 감지
        if p_cfg.main_class and (not _G.MAIN_CLASS or _G.MAIN_CLASS == '') then
          _G.MAIN_CLASS = p_cfg.main_class
          _G.log_jdtls(string.format('Auto-detected MAIN_CLASS from %s: %s', p_cfg.source_launch, _G.MAIN_CLASS))
        end

        local java_version, detect_source, target_java_name, target_java_home, effective_jdk_home
        local custom_runtimes = nil

        -- 1. Gradle 데몬 및 JDTLS 실행용 JDK (java.import.gradle.java.home)
        local gradle_jdk = p_settings['java.import.gradle.java.home']
        if gradle_jdk and type(gradle_jdk) == 'string' and vim.fn.isdirectory(gradle_jdk) == 1 then
          effective_jdk_home = gradle_jdk
          _G.log_jdtls(string.format('Using Gradle Daemon/JDTLS JDK from %s: %s', p_cfg.source_settings, effective_jdk_home))
        end

        -- 2. 프로젝트 소스 타깃 JDK 및 런타임 목록 (java.configuration.runtimes)
        local p_runtimes = p_settings['java.configuration.runtimes']
        if p_runtimes and type(p_runtimes) == 'table' and #p_runtimes > 0 then
          custom_runtimes = p_runtimes
          detect_source = p_cfg.source_settings
          local def_rt = nil
          for _, rt in ipairs(p_runtimes) do
            if rt.default == true then
              def_rt = rt
              break
            end
          end
          def_rt = def_rt or p_runtimes[1]
          target_java_name = def_rt.name
          target_java_home = def_rt.path
          local v_str = target_java_name and (target_java_name:match('1%.(%d+)') or target_java_name:match('(%d+)'))
          java_version = tonumber(v_str) or 21
          _G.log_jdtls(string.format('Using Target Java %s (%s) from %s', java_version, target_java_name or 'unknown', detect_source))
        end

        -- 3. 폴백: settings.json에 runtimes 설정이 없는 경우
        if not java_version then
          java_version, detect_source = get_java_version(root)
          java_version = java_version or 21
          target_java_name, target_java_home = get_jdk_info(java_version)
        end

        effective_jdk_home = effective_jdk_home
          or ((java_version >= 21) and target_java_home or (_G.DEVTOOLS2_DIR .. '/modules/java/jdk-21'))

        -- [실행 정보 기록]
        _G.log_jdtls(string.format('Project Root : %s', root or 'N/A'))
        _G.log_jdtls(string.format('Java Version : %s (auto-detected from %s)', java_version, detect_source or 'default'))
        _G.log_jdtls(string.format('Java Home    : %s', target_java_home or 'N/A'))
        _G.log_jdtls(string.format('Daemon Home  : %s', effective_jdk_home or 'N/A'))

        local jdtls_executable = vim.fn.exepath('jdtls')
        local mason_bin_jdtls = _G.NVIM_SHARED_DIR .. '/mason/bin/jdtls'
        local real_bin = _G.NVIM_SHARED_DIR .. '/mason/packages/jdtls/bin/jdtls'

        if (jdtls_executable == nil or jdtls_executable == '' or vim.fn.executable(jdtls_executable) == 0)
          and vim.fn.executable(mason_bin_jdtls) == 1
        then
          jdtls_executable = mason_bin_jdtls
        end

        if jdtls_executable and jdtls_executable ~= '' and vim.fn.executable(jdtls_executable) == 1 then
          -- [jdtls 래퍼 자동 교정]
          -- Mason이 jdtls 래퍼 파일을 생성할 때 사용자 홈 디렉터리(~/.local/share/nvim)를
          -- 하드코딩하는데, 이 프로젝트는 NVIM_SHARED_DIR=/var/opt/_devtools2/data/nvim에
          -- 데이터를 저장하므로 경로가 맞지 않아 exit code 127(파일 없음)이 발생할 수 있습니다.
          -- 래퍼 파일을 검사하여 실제 경로로 자동 교정합니다.
          local correct_line = 'exec python3 "' .. real_bin .. '" "$@"'
          local f = io.open(jdtls_executable, 'r')
          if f then
            local content = f:read('*a')
            f:close()
            if not content:find(real_bin, 1, true) then
              _G.log_jdtls('jdtls 래퍼 경로 불일치 감지 → 자동 교정: ' .. jdtls_executable)
              local fw = io.open(jdtls_executable, 'w')
              if fw then
                fw:write('#!/usr/bin/env bash\n\n' .. correct_line .. '\n')
                fw:close()
                _G.log_jdtls('jdtls 래퍼 경로 교정 완료')
              end
            end
          end
        else
          -- Mason이 백그라운드에서 아직 jdtls를 다운로드 중인 최초 실행 시점에는
          -- exit code 127 오류 대신 안전한 no-op 반환
          _G.log_jdtls('JDTLS 실행 파일을 아직 찾을 수 없습니다 (Mason 설치 중). 완료 후 Neovim을 재시작하세요.')
          return { 'true' }
        end

        local workspace_dir = _G.NVIM_CACHE_DIR .. '/jdtls/' .. p_name
        local mason_lombok_path = _G.NVIM_SHARED_DIR .. '/mason/packages/jdtls/lombok.jar'

        -- [jdtls 힙 크기: 이 PC 의 전체 메모리에 맞춰 결정]
        -- 예전처럼 -Xms4G -Xmx12G 로 고정하면 메모리가 8GB 인 PC(WSL 은 기본으로 호스트 메모리의 절반)에서
        -- 시작부터 4GB 를 잡아 다른 프로그램이 느려지거나 메모리가 부족해집니다.
        -- 최대 힙 = 전체 메모리의 1/4 (최소 2GB, 최대 12GB), 초기 힙 = 최대 힙의 1/4 (최대 2GB).
        local function jdtls_heap_mb()
          local total_mb = 0
          local f = io.open('/proc/meminfo', 'r')
          if f then
            local kb = (f:read('*a') or ''):match('MemTotal:%s+(%d+)%s+kB')
            f:close()
            total_mb = math.floor((tonumber(kb) or 0) / 1024)
          end
          if total_mb <= 0 then
            local ok, bytes = pcall(vim.uv.get_total_memory)
            total_mb = (ok and bytes) and math.floor(bytes / 1024 / 1024) or 16384
          end
          local xmx = math.max(2048, math.min(12288, math.floor(total_mb / 4)))
          local xms = math.min(2048, math.floor(xmx / 4))
          return xms, xmx
        end
        local heap_xms, heap_xmx = jdtls_heap_mb()
        _G.log_jdtls(string.format('jdtls heap: -Xms%dm -Xmx%dm', heap_xms, heap_xmx))

        local cmd = {
          'env',
          'JAVA_HOME=' .. effective_jdk_home,
          jdtls_executable,
          '--jvm-arg=-Xms' .. heap_xms .. 'm',
          '--jvm-arg=-Xmx' .. heap_xmx .. 'm',
          '--jvm-arg=-XX:+UseG1GC',
          '--jvm-arg=-XX:+UseStringDeduplication',
          '--jvm-arg=-javaagent:' .. mason_lombok_path,
          '-data',
          workspace_dir,
        }

        -- Gradle 데몬 실행 JDK 및 runtimes 동적 동기화
        if o.settings and o.settings.java then
          if o.settings.java.import and o.settings.java.import.gradle and o.settings.java.import.gradle.java then
            o.settings.java.import.gradle.java.home = effective_jdk_home
          end
          if o.settings.java.configuration then
            o.settings.java.configuration.runtimes = custom_runtimes or get_runtimes(target_java_name)
          end
        end

        return cmd
      end

      opts.settings = {
        java = {
          -- [코드 포맷터] s2 표준 Java 코드 스타일 (s2-code-style.xml) 동기화
          -- VS Code, Zed, Neovim 3개 편집기가 동일한 Eclipse 포맷터 프로필(Standard-s2)을 공유합니다.
          format = {
            enabled = true,
            settings = (function()
              local xml_path = _G.DEVTOOLS2_DIR .. '/.config/formatter/java/s2-code-style.xml'
              if vim.uv.fs_stat(xml_path) then
                local uri = vim.uri_from_fname(xml_path)
                if uri and uri:match('^file://[^/]') then
                  uri = uri:gsub('^file://', 'file:///')
                end
                return {
                  url = uri,
                  profile = 'Standard-s2',
                }
              end
              return nil
            end)(),
            comments = {
              enabled = false,
            },
          },
          -- [버그 방지] Inlay Hints 파라미터 이름 표시 기능 비활성화
          -- 최신 JDTLS에서 구버전 JDK(rt.jar) 라이브러리의 클래스를 스캔하다가
          -- Java Model Exception (code 969) 크래시를 유발하는 고질적 버그 방지
          inlayHints = {
            parameterNames = {
              enabled = 'none',
            },
          },
          -- [생산성] 저장 시 자동 액션 설정
          -- ⚠️ 이 서버 설정만으로는 실제로 아무 일도 일어나지 않습니다(VS Code의 redhat.java와 달리
          --   nvim-jdtls는 이 설정을 저장 이벤트에 자동으로 연결해주지 않음 — 실측/공식 이슈로 확인됨).
          --   그래서 아래 opts.jdtls.on_attach 안에 BufWritePre 오토커맨드로 직접
          --   require('jdtls').organize_imports()를 호출하도록 연결해뒀습니다. 이 설정 자체는 남겨둡니다
          --   (서버가 organize imports 코드 액션 자체를 제공하는 데는 필요할 수 있음).
          saveActions = {
            organizeImports = true,
          },
          -- [멀티 모듈] 하위 프로젝트 탐색 설정
          import = {
            gradle = {
              enabled = true,
              -- Gradle 8.x 데몬 실행 JDK: JDTLS 실행과 동일한 effective_jdk_home을 사용합니다.
              -- (컴파일 대상 JDK는 gradle.properties의 org.gradle.java.installations.paths로 별도 관리)
              java = {
                home = _G.DEVTOOLS2_DIR .. '/modules/java/jdk-21',
              },
            },
            maven = { enabled = true },
          },
          -- [Eclipse 전역 환경설정 강제 주입: Spring Boot 3.2+ 호환성 유지용]
          -- 생성된 jdtls-global.epf 파일 안의 모든 규칙을 모든 프로젝트에 강제 적용합니다.
          settings = (function()
            local epf_raw = _G.DEVTOOLS2_DIR .. '/.config/nvim/jdtls-global.epf'
            local epf_path = vim.uv.fs_realpath(epf_raw) or epf_raw
            if vim.uv.fs_stat(epf_path) then
              local uri = vim.uri_from_fname(epf_path)
              -- URI 포맷 보정: Java URI 파서는 Windows 드라이브 경로(C:/...) 앞의 슬래시 3개(file:///)를 엄격하게 요구합니다.
              -- 슬래시 2개(file://C:/...)일 경우 "Expected authority at index 7" 에러를 발생시키므로 3개로 보정합니다.
              if uri and uri:match('^file://[^/]') then
                uri = uri:gsub('^file://', 'file:///')
              end
              return { url = uri }
            end
            return nil
          end)(),
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
            runtimes = get_runtimes('JavaSE-21'),
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

      -- [DAP Launch 피커 오염 방지] LazyVim의 setup_dap_main_class_configs 호출을 원천 차단
      -- JDTLS가 메인 클래스를 스캔하여 vmArgs/args 없는 빈 Launch 구성을 주입하는 것을 방지하고,
      -- 오직 표준 .vscode/launch.json 설정만 단독으로 실행되도록 보장합니다.
      opts.dap_main = false

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

      -- [Java LSP 상태 메시지 한글화 핸들러 등록]
      -- JDTLS가 보내는 language/status (Init..., Starting Java..., ServiceReady 등)를 echo하기 전에 번역
      -- LazyVim은 opts.jdtls를 JDTLS config로 병합하므로 반드시 opts.jdtls.handlers에 등록해야 합니다.
      opts.jdtls.handlers = opts.jdtls.handlers or {}
      opts.jdtls.handlers['language/status'] = function(err, result)
        if result and result.message and type(result.message) == 'string' then
          result.message = require('util.translator').translate_message(result.message)
        end
        vim.api.nvim_echo({{ string.sub(result.message, 1, vim.v.echospace), 'Function' }}, false, {})
      end


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
            -- [버그 픽스 1] resolveJavaExecutable / resolveClasspath: project 인자 누락 보정
            if
              params.command == 'vscode.java.resolveJavaExecutable'
              or params.command == 'vscode.java.resolveClasspath'
            then
              if params.arguments[1] ~= nil and params.arguments[2] == nil then
                params.arguments[2] = vim.NIL
              end
            end

            -- =======================================================================================
            -- [버그 픽스 2] java.project.getSettings: 빈 버퍼 URI("file://") 예외 처리 (⚠️ 삭제/수정 주의!)
            -- =======================================================================================
            -- 1. 발생 원인:
            --    비-자바 프로젝트(예: _devtools2)나 초기 대시보드 화면에서 LazyVim/체크헬스 등이 구동될 때
            --    JDTLS가 로드되면 `start_or_attach` 당시의 버퍼(파일명 없음)가 캡처됩니다.
            --    이후 JDTLS가 ServiceReady를 보내면 `vim.uri_from_bufnr(0)`이 "file://"를 반환하여
            --    JDTLS 서버가 `java.net.URISyntaxException: Expected authority at index 7: file://` 예외를 발생시키고
            --    화면에 "Couldn't retrieve source path settings" 경고를 띄웁니다.
            --
            -- 2. 해결 방식:
            --    URI가 "file://"이거나 비어있으면 서버로 요청을 보내지 않고 즉시 콜백을 호출합니다.
            --    ⚠️ 주의: nvim-jdtls의 setup.lua는 `paths = settings[setting]` 후 `ipairs(paths)`를 순회하므로
            --    단순 `{}`를 넘기면 `ipairs(nil)` 런타임 에러가 납니다. 반드시 `{ [setting_key] = {} }`를 넘겨야 합니다!
            -- =======================================================================================
            if params.command == 'java.project.getSettings' then
              local uri = params.arguments and params.arguments[1]
              if not uri or uri == 'file://' or uri == '' then
                local setting_key = (params.arguments and params.arguments[2] and params.arguments[2][1])
                  or 'org.eclipse.jdt.ls.core.sourcePaths'
                local callback = args[method_idx + 2]
                if type(callback) == 'function' then
                  callback(nil, { [setting_key] = {} })
                end
                return true, 1
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

        -- dap.providers.configs['jdtls'] 및 dap.configurations.java 중복/더미 등록 방지
        local dap_ok, dap = pcall(require, 'dap')
        if dap_ok then
          if dap.providers and dap.providers.configs then
            dap.providers.configs['jdtls'] = nil
          end
          if dap.configurations then
            dap.configurations.java = {}
          end
        end

        -- 클라이언트 자체에서 java-test를 재차 시도하지 않도록 리셋 (안전하게 체크)
        if client.config and client.config.settings and client.config.settings.java then
          client.config.settings.java.configuration.runtimes = opts.settings.java.configuration.runtimes
        end

        -- [저장 시 자동 import 정리: 동기 방식 (Neovim 0.12+)]
        -- 비동기 호출 시 저장이 먼저 끝나고 import 정리가 뒤늦게 적용되어 저장 직후 버퍼가
        -- 다시 수정 상태가 되거나 방금 입력한 미사용 import가 지워지는 경합을 방지하기 위해
        -- client:request_sync 로 동기 처리 후 즉시 workspace edit을 버퍼에 반영합니다.
        vim.api.nvim_create_autocmd('BufWritePre', {
          group = vim.api.nvim_create_augroup('jdtls_organize_imports_' .. bufnr, { clear = true }),
          buffer = bufnr,
          callback = function()
            -- autoformat이 비활성화된 상태(자동 저장 등)에서는 미완성 코드 보호를 위해 import 정리를 건너뜀
            if vim.b[bufnr].autoformat == false then
              return
            end
            local clients = vim.lsp.get_clients({ bufnr = bufnr, name = 'jdtls' })
            local jdtls_client = clients[1]
            if not jdtls_client then
              return
            end
            local params = vim.lsp.util.make_range_params(0, jdtls_client.offset_encoding)
            params.context = { diagnostics = {} }
            local resp = jdtls_client:request_sync('java/organizeImports', params, 1000, bufnr)
            if resp and resp.result then
              vim.lsp.util.apply_workspace_edit(resp.result, jdtls_client.offset_encoding)
            end
          end,
        })
      end

      -- 로그 창 색상 및 가독성 유지 설정 (syntax 덮어씌워짐 방지 적용)
      -- 구문 그룹을 먼저 안전하게 전역 등록합니다. (조화로운 강조를 위해 배경색 제거)
      vim.api.nvim_set_hl(0, 'LogStart', { fg = '#2ca2c5', bold = true })
      vim.api.nvim_set_hl(0, 'LogSession', { fg = '#87af87', bold = true }) -- 차분한 연두색
      vim.api.nvim_set_hl(0, 'LogTime', { fg = '#5c6370' }) -- 회색 (타임스탬프)
      vim.api.nvim_set_hl(0, 'LogTag', { fg = '#c678dd', bold = true }) -- 보라색 ([JDTLS] 태그)

      vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufNewFile', 'FileType', 'BufWinEnter' }, {
        group = vim.api.nvim_create_augroup('jdtls_log_syntax_highlight', { clear = true }),
        pattern = { '*.log', 'log' },
        callback = function(args)
          local buf = args.buf
          if not buf or not vim.api.nvim_buf_is_valid(buf) then
            return
          end
          if vim.bo[buf].filetype == 'log' or (vim.api.nvim_buf_get_name(buf):match('%.([^.]+)$') or '') == 'log' then
            -- 자동 줄바꿈
            vim.wo.wrap = true

            -- 다른 파일 타입 감지 플러그인이 텍스트 색상을 리셋하는 것을 막기 위해,
            -- 이벤트 처리가 완전히 끝난 후(syntax 분석 이후) 비동기적으로(schedule) 색상을 덧칠합니다.
            vim.schedule(function()
              vim.cmd([=[
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
              ]=])
            end)
          end
        end,
      })

      return opts
    end,
  },
  -- [MAIN_CLASS 자동 로딩 보조 플러그인 사양]
  -- launch.json (.nvim/ 또는 .vscode/)에 mainClass가 정의되어 있으면 Neovim 시작 시 해당 파일을 자동으로 열어 JDTLS를 가동시킵니다.
  {
    name = 'java-main-class-autostart',
    dir = vim.fn.stdpath('config'),
    lazy = false,
    config = function()
      vim.api.nvim_create_autocmd('VimEnter', {
        group = vim.api.nvim_create_augroup('java_main_class_autostart', { clear = true }),
        callback = function()
          -- 이미 자바 파일이 열려있는지 확인 (중복 로딩 방지)
          for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
            if vim.bo[bufnr].filetype == 'java' then
              return
            end
          end

          local pcfg = require('util.project_config')
          local search_root = pcfg.get_project_root()
          if not search_root:match('/$') then
            search_root = search_root .. '/'
          end

          -- mainClass 탐색: _G.MAIN_CLASS 우선, 없으면 .nvim/ 또는 .vscode/ 의 launch.json 에서 탐색 (util.project_config SSOT)
          local main_class = _G.MAIN_CLASS
          if not main_class or main_class == '' then
            main_class = pcfg.get_main_class(search_root)
            if main_class then
              _G.MAIN_CLASS = main_class
            end
          end

          if main_class and main_class ~= '' then
            local class_rel_path = main_class:gsub('%.', '/') .. '.java'

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
                  vim.bo[java_buf].filetype = 'java'

                  if _G.log_jdtls then
                    _G.log_jdtls(string.format('Main class detected (%s). JDTLS started in background.', main_class))
                  end
                end)
              end
            end
          end
        end,
      })
    end,
  },
}
