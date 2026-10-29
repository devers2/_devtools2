--[[
===========================================================================================
[jdtls Java 설정 오류 안내: util.jdtls_diagnose]
===========================================================================================
jdtls 가 Java 설정 때문에 실패했을 때, 로그 파일(lsp.log)을 뒤지지 않아도 원인과
"어느 파일의 어떤 키를 확인하면 되는지"를 Neovim 알림(vim.notify)으로 바로 보여줍니다.
(plugins/java.lua 가 jdtls 를 띄울 때 set_context 로 프로젝트 설정 정보를 넘기고,
 jdtls 의 로그 메시지 핸들러·종료 핸들러에서 이 모듈을 호출합니다)

알림을 보내는 경우:
  1. 설정 파일을 읽을 때 (check_settings)
     - java.import.gradle.java.home 경로가 없음 (예전에는 조용히 무시하고 기본 JDK 사용)
     - java.configuration.runtimes 의 path 가 없음
  2. jdtls 가 Gradle 동기화 실패를 보고할 때 (on_log_message — "Synchronize project ... failed")
     - 툴체인 JDK 를 못 찾음      → tool-versions.toml jdkN / ~/.gradle/gradle.properties / 오래된 Gradle 데몬
     - Gradle 데몬 JDK 가 Gradle 버전과 안 맞음 → settings.json 의 java.import.gradle.java.home
     - JDK 교체 후 오래된 Gradle 데몬 ("Failed to exec spawn helper") → ./gradlew --stop
     - 그 밖의 실패              → 첫 원인(Caused by) 줄 + 확인할 설정 키
  3. jdtls 가 비정상 종료될 때 (on_exit)

같은 내용의 알림은 Neovim 세션당 한 번만 보냅니다(jdtls 재시작·여러 버퍼에서 반복되지 않도록).
===========================================================================================
--]]

local M = {}

-- jdtls 를 띄울 때의 프로젝트 설정 정보 (plugins/java.lua 의 full_cmd 에서 set_context 로 채움)
M.ctx = {}
local notified = {}

local TITLE = 'Java 설정 확인'

-- 알림을 화면이 준비된 뒤에 보냄
-- jdtls 설정 확인(check_settings)은 Neovim 이 파일을 여는 순간(FileType, VimEnter 이전)에 실행되는데, 그때는 아직
-- 알림 창(Snacks notifier, LazyVim 의 VeryLazy 단계에서 준비)이 없어 알림이 사라졌습니다(실측).
-- 그래서 VimEnter 전이면 VimEnter 를 기다리고, 그 뒤 잠깐(1.5초) 늦춰 알림 창이 준비된 다음 보냅니다.
local function deliver(msg, level)
  local send = function()
    vim.notify(msg, level or vim.log.levels.WARN, { title = TITLE })
  end
  if vim.v.vim_did_enter == 1 and (vim.uv.hrtime() - (M._entered_at or 0)) > 3e9 then
    vim.schedule(send)
  elseif vim.v.vim_did_enter == 1 then
    vim.defer_fn(send, 1500)
  else
    vim.api.nvim_create_autocmd('VimEnter', {
      once = true,
      callback = function()
        vim.defer_fn(send, 1500)
      end,
    })
  end
end
vim.api.nvim_create_autocmd('VimEnter', {
  once = true,
  callback = function()
    M._entered_at = vim.uv.hrtime()
  end,
})

local function notify_once(key, msg, level)
  if notified[key] then
    return
  end
  notified[key] = true
  deliver(msg, level)
end

-- 확인할 설정 파일 안내 문구 (.nvim 이 있으면 .nvim 이 우선, 없으면 .vscode)
local function settings_hint()
  local c = M.ctx
  if c.settings_path and c.settings_path ~= '' then
    return vim.fn.fnamemodify(c.settings_path, ':~')
  end
  local root = c.root and vim.fn.fnamemodify(c.root, ':~') or '<프로젝트>'
  return root .. '/.nvim/settings.json 또는 ' .. root .. '/.vscode/settings.json (아직 없음)'
end

-- 프로젝트의 Gradle wrapper 버전 (안내 문구용)
local function gradle_wrapper_version()
  local root = M.ctx.root
  if not root then
    return nil
  end
  local f = io.open(root .. '/gradle/wrapper/gradle-wrapper.properties', 'r')
  if not f then
    return nil
  end
  local content = f:read('*a') or ''
  f:close()
  return content:match('gradle%-([%d%.]+)%-')
end

--- jdtls 를 띄울 때의 설정 정보 저장
--- @param ctx table { root, settings_path, gradle_jdk, runtimes, jdtls_home, daemon_home, target_java }
function M.set_context(ctx)
  M.ctx = ctx or {}
end

--- 설정 파일의 JDK 경로가 실제로 있는지 확인 (없으면 어느 키가 잘못됐는지 알림)
function M.check_settings()
  local c = M.ctx
  local file = settings_hint()
  if type(c.gradle_jdk) == 'string' and c.gradle_jdk ~= '' and vim.fn.isdirectory(c.gradle_jdk) == 0 then
    notify_once('gradle_jdk_missing:' .. c.gradle_jdk, table.concat({
      'Gradle 데몬 JDK 경로가 없습니다. 기본 JDK 로 대신 실행합니다.',
      '  확인: ' .. file,
      '    "java.import.gradle.java.home": "' .. c.gradle_jdk .. '"',
      '  (설치된 JDK: ' .. M.installed_jdks() .. ')',
    }, '\n'))
  end
  if type(c.runtimes) == 'table' then
    local bad = {}
    for _, rt in ipairs(c.runtimes) do
      if type(rt) == 'table' and type(rt.path) == 'string' and vim.fn.isdirectory(rt.path) == 0 then
        table.insert(bad, string.format('%s → %s', tostring(rt.name), rt.path))
      end
    end
    if #bad > 0 then
      notify_once('runtimes_missing:' .. table.concat(bad, ','), table.concat({
        '프로젝트 런타임(JDK) 경로가 없습니다:',
        '  ' .. table.concat(bad, '\n  '),
        '  확인: ' .. file .. ' 의 "java.configuration.runtimes"',
        '  (설치된 JDK: ' .. M.installed_jdks() .. ')',
      }, '\n'))
    end
  end
end

--- 설치된 DevTools2 JDK 폴더 이름 목록 (안내 문구용)
function M.installed_jdks()
  local dir = (_G.DEVTOOLS2_DIR or '/var/opt/_devtools2') .. '/modules/java'
  local names = {}
  for _, d in ipairs(vim.fn.glob(dir .. '/jdk-*', false, true)) do
    table.insert(names, vim.fs.basename(d))
  end
  return #names > 0 and table.concat(names, ', ') or '없음'
end

--- jdtls 의 window/logMessage 내용을 보고 Java 설정 관련 실패면 알림
--- @param message string
function M.on_log_message(message)
  if type(message) ~= 'string' or not message:find('Synchronize project', 1, true) or not message:find('failed', 1, true) then
    return
  end
  local c = M.ctx
  local file = settings_hint()
  local gradle_ver = gradle_wrapper_version()

  -- JDK 교체(업데이트) 뒤 예전 JDK 로 떠 있던 Gradle 데몬: 다른 프로세스를 못 띄워 툴체인 탐색이 전부 실패
  if message:find('spawn helper', 1, true) then
    notify_once('stale_daemon', table.concat({
      'Gradle 동기화 실패: JDK 가 바뀌기 전에 떠 있던 Gradle 데몬이 고장난 상태입니다.',
      '  해결: 프로젝트에서 ./gradlew --stop 실행 후 :JdtRestart (또는 Neovim 재시작)',
    }, '\n'))
    return
  end

  -- 툴체인 JDK 를 못 찾음 (build.gradle 의 java.toolchain.languageVersion)
  local lang = message:match('Cannot find a Java installation.-languageVersion=(%d+)')
  if lang then
    notify_once('toolchain:' .. lang, table.concat({
      'Gradle 동기화 실패: 프로젝트가 요구하는 Java ' .. lang .. ' 툴체인을 찾지 못했습니다.',
      '  확인 1: Java ' .. lang .. ' 설치 여부 — 설치된 JDK: ' .. M.installed_jdks(),
      '          (없으면 tool-versions.toml 에 jdk' .. lang .. ' 추가 후 설치 스크립트 2단계 실행)',
      '  확인 2: ~/.gradle/gradle.properties 의 org.gradle.java.installations.paths 에 그 JDK 경로가 있는지',
      '  확인 3: JDK 를 업데이트한 뒤라면 오래된 Gradle 데몬 — ./gradlew --stop 후 :JdtRestart',
      '  (Gradle 데몬 JDK: ' .. tostring(c.daemon_home) .. ' — ' .. file .. ' 의 java.import.gradle.java.home)',
    }, '\n'))
    return
  end

  -- Gradle 데몬 JDK 와 Gradle 버전 불일치 (Gradle 이 실행 JDK 를 지원하지 않음)
  if message:find('Unsupported class file major version', 1, true)
    or message:find('TypeNotPresentException', 1, true)
    or message:find('Unsupported Java', 1, true)
    or message:find('Could not determine java version', 1, true)
    or message:find('requires Java', 1, true)
  then
    notify_once('daemon_jdk_mismatch', table.concat({
      'Gradle 동기화 실패: Gradle 데몬 JDK 가 이 프로젝트의 Gradle' .. (gradle_ver and (' ' .. gradle_ver) or '') .. ' 과 맞지 않습니다.',
      '  확인: ' .. file,
      '    "java.import.gradle.java.home": "' .. tostring(c.daemon_home) .. '"',
      '  (Gradle 7.x 는 JDK 21 이상 불가, Gradle 8.x 는 JDK 17·21 권장 — JDK 25 에서 크래시 사례 있음)',
    }, '\n'))
    return
  end

  -- 그 밖의 동기화 실패: 첫 원인 줄과 확인할 설정 키 안내
  local cause = message:match('Caused by: ([^\n]+)') or message:match('failed[^\n]*')
  notify_once('sync_failed:' .. tostring(cause), table.concat({
    'Gradle 동기화 실패: ' .. tostring(cause):sub(1, 200),
    '  Java 설정이 원인이면 확인: ' .. file,
    '    "java.import.gradle.java.home" (Gradle 데몬 JDK: ' .. tostring(c.daemon_home) .. ')',
    '    "java.configuration.runtimes"  (소스 Java: ' .. tostring(c.target_java) .. ')',
    '  전체 로그: ' .. vim.fn.fnamemodify(vim.lsp.get_log_path(), ':~'),
  }, '\n'))
end

--- jdtls 프로세스 종료 시 (비정상 종료면 알림)
function M.on_exit(code, signal)
  if code == 0 or (signal and signal ~= 0) then
    return -- 정상 종료 또는 Neovim 이 끝낼 때 보낸 신호
  end
  local c = M.ctx
  notify_once('exit:' .. tostring(code), table.concat({
    string.format('jdtls 가 비정상 종료되었습니다 (exit code %s).', tostring(code)),
    '  jdtls 실행 JDK: ' .. tostring(c.jdtls_home) .. ' (Java 21 이상 필요)',
    '  확인: ' .. settings_hint(),
    '    "java.import.gradle.java.home" / "java.configuration.runtimes"',
    '  전체 로그: ' .. vim.fn.fnamemodify(vim.lsp.get_log_path(), ':~'),
  }, '\n'))
end

return M
