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
  4. 같은 프로젝트를 다른 jdtls 가 이미 열고 있을 때 (check_concurrent — jdtls 를 띄우기 직전)
     - 다른 Neovim 창의 jdtls 가 같은 작업 폴더(-data)를 씀 → 경고 (Gradle 동기화·오류 표시가 꼬임)
     - VS Code·Zed·IntelliJ 의 jdtls 가 같은 프로젝트를 엶 → 안내 (작업 폴더는 따로지만 .project·.classpath·bin/ 을 함께 씀)
  5. jdtls 가 프로젝트 파일 충돌을 보고할 때 (on_log_message — "out of sync" / "Failed to configure project")
     - 여러 편집기가 동시에 .project 를 고쳐 쓴 경우가 대부분 → 다른 편집기 닫고 :JdtWipeDataAndRestart
     (실제 사례: Neovim 창 2개 + VS Code + Zed 가 Goono-ELN 을 동시에 열어 Gradle 동기화가 실패하고,
      의존성(jsoup 등)을 못 찾는 오류만 보여 원인을 알기 어려웠음)

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

-- ── 같은 프로젝트를 연 다른 jdtls 찾기 (check_concurrent) ─────────────────────────────
-- /proc 을 직접 읽습니다(외부 명령 실행 없음, 프로세스 수백 개 기준 수 ms). 다른 사용자의 프로세스는
-- 읽을 수 없어 자연히 건너뜁니다. Linux(WSL 포함) 전용이며 /proc 이 없으면 아무것도 하지 않습니다.

local function read_file(path)
  local f = io.open(path, 'r')
  if not f then
    return nil
  end
  local c = f:read('*a')
  f:close()
  return c
end

-- /proc/<pid>/stat 에서 부모 PID 와 시작 시각(부팅 후 클록 틱) — comm 에 공백·괄호가 있을 수 있어 마지막 ')' 뒤를 자름
local function proc_stat(pid)
  local st = read_file('/proc/' .. pid .. '/stat')
  if not st then
    return nil
  end
  local rest = st:match('.*%)%s+(.*)')
  if not rest then
    return nil
  end
  local fields = vim.split(rest, ' ', { plain = true })
  -- rest 의 1번째 = state(전체 3번째 필드), 2번째 = ppid(4번째), 20번째 = starttime(22번째)
  return tonumber(fields[2]), tonumber(fields[20])
end

-- 부모를 따라 올라가며 어느 편집기가 띄운 jdtls 인지 판별 (최대 8단계)
local function editor_of(pid, self_pid)
  local cur = pid
  for _ = 1, 8 do
    local ppid = proc_stat(cur)
    if not ppid or ppid <= 1 then
      return 'unknown'
    end
    if ppid == self_pid then
      return 'self'
    end
    local cmd = (read_file('/proc/' .. ppid .. '/cmdline') or ''):gsub('%z', ' ')
    if cmd:find('nvim', 1, true) then
      return 'nvim', ppid
    elseif cmd:find('vscode-server', 1, true) or cmd:find('/code ', 1, true) or cmd:find('Code.exe', 1, true) then
      return 'VS Code'
    elseif cmd:find('zed', 1, true) then
      return 'Zed'
    elseif cmd:find('idea', 1, true) or cmd:find('jetbrains', 1, true) then
      return 'IntelliJ'
    end
    cur = ppid
  end
  return 'unknown'
end

-- "약 N분/시간 전" (프로세스 시작 시각 안내용)
local function started_ago(starttime)
  local up = tonumber((read_file('/proc/uptime') or ''):match('^(%S+)'))
  if not up or not starttime then
    return '시작 시각 모름'
  end
  local sec = up - starttime / 100 -- Linux CLK_TCK 는 사실상 항상 100
  if sec < 3600 then
    return string.format('약 %d분 전 시작', math.max(1, math.floor(sec / 60)))
  end
  return string.format('약 %.1f시간 전 시작', sec / 3600)
end

-- 마지막 검사에서 찾은 다른 편집기 목록 (on_log_message 의 충돌 안내에서도 사용)
M.others = {}

--- 같은 프로젝트를 이미 열고 있는 다른 jdtls 가 있는지 확인해 알림
--- (plugins/java.lua 의 full_cmd 에서 jdtls 를 띄우기 직전에 호출 — 이 시점엔 내 jdtls 가 아직 없음.
---  :JdtRestart 등으로 내 jdtls 가 남아 있어도 부모가 이 Neovim 이면 제외)
--- @param workspace_dir string 이 Neovim 이 쓸 jdtls 작업 폴더(-data)
--- @param root string|nil 프로젝트 루트
function M.check_concurrent(workspace_dir, root)
  if not root or root == '' or vim.fn.isdirectory('/proc') == 0 then
    return
  end
  local self_pid = vim.fn.getpid()
  local real_ws = vim.uv.fs_realpath(workspace_dir) or workspace_dir
  local real_root = vim.uv.fs_realpath(root) or root
  local same_ws, others = {}, {}
  for _, name in ipairs(vim.fn.readdir('/proc', function(n)
    return n:match('^%d+$') and 1 or 0
  end)) do
    local cmd = read_file('/proc/' .. name .. '/cmdline')
    if cmd and cmd:find('org.eclipse.jdt.ls.core', 1, true) then
      local args = vim.split(cmd, '\0', { plain = true, trimempty = true })
      local data
      for i, a in ipairs(args) do
        if a == '-data' then
          data = args[i + 1]
        end
      end
      local cwd = vim.uv.fs_readlink('/proc/' .. name .. '/cwd') or ''
      local editor, editor_pid = editor_of(tonumber(name), self_pid)
      if editor ~= 'self' then
        local _, starttime = proc_stat(name)
        local info = { pid = tonumber(name), editor = editor, editor_pid = editor_pid, ago = started_ago(starttime) }
        if data and (vim.uv.fs_realpath(data) or data) == real_ws then
          table.insert(same_ws, info)
        elseif cwd == real_root or vim.startswith(cwd, real_root .. '/') then
          table.insert(others, info)
        end
      end
    end
  end
  M.others = others

  if #same_ws > 0 then
    local lines = {
      '같은 프로젝트의 jdtls 가 이미 실행 중입니다 (같은 작업 폴더를 함께 사용).',
    }
    for _, i in ipairs(same_ws) do
      table.insert(lines, string.format('  - %s (jdtls PID %d%s, %s)', i.editor == 'nvim' and '다른 Neovim 창' or i.editor,
        i.pid, i.editor_pid and (', nvim PID ' .. i.editor_pid) or '', i.ago))
    end
    vim.list_extend(lines, {
      '  작업 폴더: ' .. vim.fn.fnamemodify(workspace_dir, ':~'),
      '  두 jdtls 가 같은 폴더를 쓰면 Gradle 동기화가 실패하거나 의존성을 못 찾는 오류가 남을 수 있습니다.',
      '  해결: 다른 Neovim 창을 닫고, 오류가 남아 있으면 :JdtWipeDataAndRestart',
    })
    notify_once('concurrent_ws:' .. real_ws, table.concat(lines, '\n'), vim.log.levels.WARN)
  end

  if #others > 0 then
    local names, seen = {}, {}
    for _, i in ipairs(others) do
      local n = i.editor == 'nvim' and '다른 Neovim 창' or (i.editor == 'unknown' and '다른 프로그램' or i.editor)
      if not seen[n] then
        seen[n] = true
        table.insert(names, n)
      end
    end
    notify_once('concurrent_other:' .. real_root, table.concat({
      '같은 프로젝트를 ' .. table.concat(names, ', ') .. ' 에서도 Java 언어 서버로 열고 있습니다.',
      '  작업 폴더는 따로지만 프로젝트의 .project · .classpath · bin/ 을 함께 고쳐 씁니다.',
      '  동시에 열면 Gradle 동기화가 실패할 수 있습니다("Failed to configure project", "out of sync").',
      '  그런 오류가 나면 다른 편집기를 닫고 :JdtWipeDataAndRestart',
    }, '\n'), vim.log.levels.INFO)
  end
end

--- jdtls 의 window/logMessage 내용을 보고 Java 설정 관련 실패면 알림
--- @param message string
function M.on_log_message(message)
  if type(message) ~= 'string' then
    return
  end
  -- 프로젝트 파일 충돌: 여러 편집기(또는 Neovim 창)가 같은 프로젝트의 .project 를 동시에 고쳐 씀
  if message:find('out of sync with the file system', 1, true) or message:find('Failed to configure project', 1, true) then
    local names = {}
    for _, i in ipairs(M.others or {}) do
      table.insert(names, i.editor == 'nvim' and '다른 Neovim 창' or i.editor)
    end
    notify_once('project_out_of_sync', table.concat({
      'Gradle 프로젝트 구성 실패: 프로젝트 파일(.project)이 다른 프로그램과 충돌했습니다.',
      '  여러 편집기가 같은 프로젝트를 동시에 열면 생깁니다' .. (#names > 0 and (' (지금 함께 연 곳: ' .. table.concat(names, ', ') .. ')') or '') .. '.',
      '  이 상태에서는 의존성을 못 찾는 오류(The import ... cannot be resolved)가 함께 표시됩니다.',
      '  해결: 다른 편집기를 닫고 :JdtWipeDataAndRestart',
    }, '\n'))
    return
  end
  if not message:find('Synchronize project', 1, true) or not message:find('failed', 1, true) then
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

-- jdtls(Equinox)가 시작하지 못하면(exit code 13) Mason 의 jdtls 패키지 configuration/*.log 에 원인이 남습니다.
-- 가장 최근 로그에서 OSGi 모듈이 요구하는 Java 버전(osgi.ee JavaSE version=N)을 찾습니다.
-- (예: jdtls 1.63 은 Java 25 를 요구 — jdtls.py 는 "21 이상"만 검사해 실행 전에 걸러지지 않음)
local function required_java_from_config_log()
  local dir = (_G.NVIM_SHARED_DIR or '') .. '/mason/packages/jdtls/configuration'
  local logs = vim.fn.glob(dir .. '/*.log', false, true)
  if #logs == 0 then
    return nil, nil
  end
  table.sort(logs, function(a, b)
    return (vim.fn.getftime(a) or 0) > (vim.fn.getftime(b) or 0)
  end)
  local f = io.open(logs[1], 'r')
  if not f then
    return nil, logs[1]
  end
  local content = f:read('*a') or ''
  f:close()
  local best = nil
  for v in content:gmatch('osgi%.ee=JavaSE%)%(version=(%d+)') do
    v = tonumber(v)
    if v and (not best or v > best) then
      best = v
    end
  end
  return best, logs[1]
end

--- jdtls 프로세스 종료 시 (비정상 종료면 알림)
function M.on_exit(code, signal)
  if code == 0 or (signal and signal ~= 0) then
    return -- 정상 종료 또는 Neovim 이 끝낼 때 보낸 신호
  end
  local c = M.ctx
  -- exit code 13: Equinox 시작 실패 — 대부분 jdtls 가 요구하는 Java 버전보다 낮은 JDK 로 실행한 경우
  if code == 13 then
    local need, logf = required_java_from_config_log()
    if need then
      notify_once('exit13:' .. need, table.concat({
        string.format('jdtls 가 시작하지 못했습니다 (exit code 13): 이 jdtls 는 Java %d 이상이 필요합니다.', need),
        '  jdtls 실행 JDK: ' .. tostring(c.jdtls_home),
        '  설치된 JDK: ' .. M.installed_jdks(),
        string.format('  해결: tool-versions.toml 에 jdk%d 추가 후 설치 스크립트 2단계 실행 (jdtls 는 설치된 가장 높은 JDK 로 실행됨)', need),
        '  jdtls 로그: ' .. vim.fn.fnamemodify(logf, ':~'),
      }, '\n'))
      return
    end
  end
  notify_once('exit:' .. tostring(code), table.concat({
    string.format('jdtls 가 비정상 종료되었습니다 (exit code %s).', tostring(code)),
    '  jdtls 실행 JDK: ' .. tostring(c.jdtls_home) .. ' (Java 21 이상 필요)',
    '  확인: ' .. settings_hint(),
    '    "java.import.gradle.java.home" / "java.configuration.runtimes"',
    '  전체 로그: ' .. vim.fn.fnamemodify(vim.lsp.get_log_path(), ':~'),
  }, '\n'))
end

return M
