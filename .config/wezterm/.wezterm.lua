-- WezTerm 설정 파일
local wezterm = require('wezterm')
local act = wezterm.action
local config = wezterm.config_builder()

-- 실행 파일 존재 여부를 확인하는 함수 (PATH 포함)
local function file_exists(name)
  local f = io.open(name, 'r')
  if f ~= nil then
    io.close(f)
    return true
  else
    return false
  end
end

local is_windows = wezterm.target_triple:find('windows') ~= nil
local home_dir = os.getenv('HOME') or os.getenv('USERPROFILE') or os.getenv('HOMEPATH') or '.'
local wezterm_dir = home_dir:gsub('\\', '/') .. '/.wezterm'

local xdg_data_home = os.getenv('XDG_DATA_HOME')
local xdg_cache_home = os.getenv('XDG_CACHE_HOME')

local nvim_data_dir
local nvim_cache_dir

if is_windows then
  local local_app_data = os.getenv('LOCALAPPDATA')
  local temp_dir = os.getenv('TEMP')

  -- 환경 변수에서 가져온 윈도우 경로(\)를 미리 슬래시(/)로 정규화
  local_app_data = (local_app_data and local_app_data:gsub('\\', '/')) or (home_dir .. '/AppData/Local')
  temp_dir = (temp_dir and temp_dir:gsub('\\', '/')) or (local_app_data .. '/Temp')

  local x_data = xdg_data_home and xdg_data_home:gsub('\\', '/')
  local x_cache = xdg_cache_home and xdg_cache_home:gsub('\\', '/')

  nvim_data_dir = x_data and (x_data .. '/nvim-data') or (local_app_data .. '/nvim-data')
  nvim_cache_dir = x_cache and (x_cache .. '/nvim') or (temp_dir .. '/nvim')
else
  -- 리눅스 및 macOS
  nvim_data_dir = xdg_data_home and (xdg_data_home .. '/nvim') or (home_dir .. '/.local/share/nvim')
  nvim_cache_dir = xdg_cache_home and (xdg_cache_home .. '/nvim') or (home_dir .. '/.cache/nvim')
end

-- 전역 메모리 변수
local memory_state = {
  bw_session = nil,
  bw_hosts = nil, -- 조회된 호스트 목록 캐시
}

-- PATH에서 실행 파일 경로를 찾는 함수
local function find_executable(cmd)
  -- PATH 환경 변수 가져오기
  local path = os.getenv('PATH') or ''

  -- 리눅스/맥의 경우 브루(brew) 경로 등 추가 검색
  if not is_windows then
    local extra_paths = {
      '/home/linuxbrew/.linuxbrew/bin',
      '/usr/local/bin',
      '/opt/homebrew/bin',
      home_dir .. '/.linuxbrew/bin',
      '/usr/bin',
      '/bin',
    }
    for _, p in ipairs(extra_paths) do
      if not path:find(p, 1, true) then
        path = path .. ':' .. p
      end
    end
  end

  local sep = is_windows and ';' or ':'
  local p_sep = is_windows and '\\' or '/'

  -- PATH를 구분자로 분리해서 각 디렉토리 확인
  for dir in string.gmatch(path, '[^' .. sep .. ']+') do
    local full_path = dir .. p_sep .. cmd
    if is_windows then
      -- 윈도우는 .exe, .ps1, .bat, .cmd 등 확장자 확인 필요할 수 있음
      local extensions = { '', '.exe', '.ps1', '.bat', '.cmd' }
      for _, ext in ipairs(extensions) do
        if file_exists(full_path .. ext) then
          return full_path .. ext
        end
      end
    else
      if file_exists(full_path) then
        return full_path
      end
    end
  end
  return nil
end

-- 실행 파일 존재 여부를 확인하는 함수 (PATH 포함)
local function command_exists(cmd)
  return find_executable(cmd) ~= nil
end

-- WezTerm 상태 저장/불러오기 기능 (사용자 홈의 .wezterm/state.json에 프로젝트별/명령어별로 저장)
local state_file_path = wezterm_dir .. '/state.json'

-- JSON 처리 유틸리티
local function json_decode(content)
  local decode = wezterm.json_decode or wezterm.json_parse
  if not decode then
    return nil
  end
  local success, result = pcall(decode, content)
  return success and result or nil
end

local function json_encode(data)
  local encode = wezterm.json_encode or wezterm.json_string
  if not encode then
    return nil
  end
  local success, result = pcall(encode, data)
  return success and result or nil
end

-- 쉘 이스케이핑 유틸리티
local function shell_quote(s)
  if is_windows then
    -- Windows (PowerShell/CMD) 단순 이스케이핑: 따옴표로 감싸고 내부 따옴표 중복
    return '"' .. s:gsub('"', '""') .. '"'
  else
    -- Unix (sh/bash/zsh) 이스케이핑: 작은 따옴표로 감싸고 내부 작은 따옴표 처리
    return "'" .. s:gsub("'", "'\\''") .. "'"
  end
end

-- 현재 작업 디렉토리 고유 키 생성
local function get_project_key(pane)
  local cwd = pane:get_current_working_dir()
  if cwd then
    local path = cwd.path
    path = path:gsub('^file://', ''):gsub('^/%a:', function(m)
      return m:sub(2)
    end)
    return path:gsub('[\\/]+$', ''):gsub('\\', '/')
  end
  return 'default'
end

-- 상태 데이터 로드
local function load_state(pane, label)
  local f = io.open(state_file_path, 'r')
  if not f then
    return {}
  end
  local content = f:read('*all')
  f:close()

  local all_state = json_decode(content)
  if not all_state or type(all_state) ~= 'table' then
    return {}
  end

  -- 이전 버전의 배열 구조 교정 로직 유지
  if all_state[1] and type(all_state[1]) == 'table' then
    all_state = all_state[1]
  end

  local p_key = get_project_key(pane)
  return (all_state[p_key] and all_state[p_key][label]) or {}
end

-- 상태 데이터 저장
local function save_state(pane, label, data)
  local all_state = {}
  local f_read = io.open(state_file_path, 'r')
  if f_read then
    local content = f_read:read('*all')
    f_read:close()
    all_state = json_decode(content) or {}
    if all_state[1] and type(all_state[1]) == 'table' then
      all_state = all_state[1]
    end
  end

  local p_key = get_project_key(pane)
  all_state[p_key] = all_state[p_key] or {}
  all_state[p_key][label] = data

  local f_write = io.open(state_file_path, 'w')
  if f_write then
    local encoded = json_encode(all_state)
    if encoded then
      f_write:write(encoded)
    end
    f_write:close()
  end
end

-- 영어와 아이콘은 JetBrainsMono, 한글은 D2Coding으로 조화롭게 사용 (위에 잘리는 현상 방지)
config.font = wezterm.font_with_fallback({
  { family = 'JetBrainsMono Nerd Font Mono' },
  { family = 'D2Coding ligature', scale = 1.00 }, -- scale을 통해 한글 크기 미세 조정 가능
})
-- WQHD 해상도에서 폰트 상단 잘림 방지를 위해 font_size: 10.2, line_height: 1.2 로 설정
config.font_size = 10.2
config.line_height = 1.2
config.color_scheme = 'Kanagawa (Gogh)' -- 'Kanagawa (Gogh)', 'Tokyo Night'
config.window_background_opacity = 0.96 -- 투명도
config.scroll_to_bottom_on_input = true -- 입력할 때 자동으로 맨 아래로 스크롤
config.hide_tab_bar_if_only_one_tab = true -- 탭이 하나일 때는 숨기고, 여러 개일 때만 보여줌
config.front_end = 'WebGpu' -- 그래픽 가속 활성화 (WebGpu / OpenGL / Software)
-- config.window_decorations = "RESIZE" -- 타이틀을 숨기고 창 조절 가능: 나이틀리 버전에서 오류 발생하여 주석처리

if is_windows then
  -- Windows 에서 WSL2 devtools2 배포판을 기본 셸로 사용
  config.default_prog = { 'wsl.exe', '-d', 'devtools2' }

  -- PowerShell 7 폴더 색 보정 (선택적 적용 - API 지원 여부와 color_scheme 존재 여부 모두 확인)
  local ok, result = pcall(function()
    if wezterm.color and wezterm.color.get_builtin_schemes then
      local scheme = wezterm.color.get_builtin_schemes()[config.color_scheme]
      if scheme then
        local ansi = { table.unpack(scheme.ansi) }
        local brights = { table.unpack(scheme.brights) }
        ansi[5] = '#1e3a8a'    -- ANSI 4  (일반 파란색 → 어두운 파랑)
        brights[5] = '#3b82f6' -- ANSI 12 (밝은 파란색 → 선명한 파랑)
        config.colors = { ansi = ansi, brights = brights }
      end
    end
  end)
  if not ok then
    wezterm.log_warn('색상 보정 실패 (무시됨): ' .. tostring(result))
  end
end

-- SSH 호스트 파일 경로 설정
local hosts_file_path = wezterm_dir .. '/ssh_hosts.json'

-- SSH 호스트 데이터 로드 함수 (없으면 초기 파일 생성)
local function load_ssh_hosts()
  local f = io.open(hosts_file_path, 'r')
  if not f then
    -- .wezterm 디렉토리 생성
    if is_windows then
      os.execute('if not exist "' .. wezterm_dir:gsub('/', '\\') .. '" mkdir "' .. wezterm_dir:gsub('/', '\\') .. '"')
    else
      os.execute('mkdir -p "' .. wezterm_dir .. '"')
    end

    -- 기본 예시 데이터 생성
    local default_hosts = {
      {
        name = '로컬 서버 (예시)',
        uri = '192.168.0.10',
        username = 'user',
        password = 'password123',
        sshkey = '',
      },
    }
    local f_write = io.open(hosts_file_path, 'w')
    if f_write then
      f_write:write(json_encode(default_hosts))
      f_write:close()
    end
    return default_hosts
  end

  local content = f:read('*all')
  f:close()
  return json_decode(content) or {}
end

-- SSH 키 여부 확인 (정규식)
local function is_ssh_key(text)
  if not text then
    return false
  end
  -- common SSH private key headers
  return text:find('BEGIN .* PRIVATE KEY') ~= nil
end

-- Bitwarden에서 호스트 목록 가져오기
local function fetch_bitwarden_hosts(window, pane, bw_session, force_sync, password)
  -- 동일 세션이고 캐시된 데이터가 있으면 즉시 반환 (속도 최적화)
  if not force_sync and memory_state.bw_session == bw_session and memory_state.bw_hosts then
    return memory_state.bw_hosts
  end

  local bw_path = find_executable('bw')

  if not bw_path then
    return nil, 'Bitwarden CLI(bw)를 찾을 수 없습니다. 설치 여부를 확인해주세요.'
  end

  local folder_id = '9977a5c2-ee53-4a13-8dac-b43b010afabb'

  -- 강제 동기화 요청 시 bw sync 먼저 수행 (서버 변경사항 반영)
  if force_sync then
    wezterm.log_info('DEBUG: Syncing Bitwarden vault...')
    wezterm.run_child_process({ bw_path, 'sync', '--session', bw_session })
  end

  local cmd = { bw_path, 'list', 'items', '--folderid', folder_id, '--session', bw_session }

  wezterm.log_info('DEBUG: Attempting to run Bitwarden: ' .. table.concat(cmd, ' '))
  local success, stdout, stderr = wezterm.run_child_process(cmd)
  wezterm.log_info('DEBUG: Bitwarden command result - Success: ' .. tostring(success))

  -- Bitwarden CLI 버그 대응: --session 옵션을 줬는데도 Master password를 stdin으로 요구하는 경우
  -- stderr에 'Master password' 또는 readline 오류가 감지되면 stdin 파이프로 비밀번호 전달하여 재시도
  local needs_pw_pipe = stderr and (stderr:find('Master password') or stderr:find('ERR_USE_AFTER_CLOSE'))
  if needs_pw_pipe and password and password ~= '' then
    wezterm.log_info('DEBUG: Master password prompt detected in stderr. Retrying with stdin pipe...')
    -- 패스워드와 세션 토큰의 작은따옴표 이스케이프
    local esc_pw = password:gsub("'", "'\\''")
    local esc_session = bw_session:gsub("'", "'\\''")
    local pipe_cmd = string.format(
      "printf '%%s\\n' '%s' | '%s' list items --folderid %s --session '%s'",
      esc_pw,
      bw_path,
      folder_id,
      esc_session
    )
    local ok2, stdout2, stderr2 = wezterm.run_child_process({ 'sh', '-c', pipe_cmd })
    wezterm.log_info('DEBUG: Pipe retry result - Success: ' .. tostring(ok2))
    if ok2 then
      success = ok2
      stdout = stdout2
      stderr = stderr2
    end
  end

  if not success then
    wezterm.log_error('DEBUG: Bitwarden command failed. Stderr: ' .. (stderr or 'empty'))
    return nil, 'Bitwarden 세션 오류 또는 실행 실패. Error: ' .. (stderr or 'unknown')
  end

  -- JSON 배열 구간 찾기 (가장 바깥쪽 [ ] 찾기)
  local first_bracket = stdout:find('%[')
  local last_bracket = stdout:match('.*()%]')

  local stdout_clean = ''
  if first_bracket and last_bracket and first_bracket < last_bracket then
    stdout_clean = stdout:sub(first_bracket, last_bracket)
  else
    stdout_clean = stdout
  end

  -- 공백 및 기타 불필요한 문자 제거
  stdout_clean = stdout_clean:gsub('^%s+', ''):gsub('%s+$', '')
  local items = json_decode(stdout_clean)
  if not items then
    wezterm.log_error('DEBUG: Failed to decode JSON. Raw output length: ' .. #stdout)
    wezterm.log_error('DEBUG: Cleaned output snippet: ' .. stdout_clean:sub(1, 200))
    if stderr and stderr ~= '' then
      wezterm.log_error('DEBUG: Stderr content: ' .. stderr)
    end
    return nil, 'Bitwarden 응답 데이터를 해석할 수 없습니다.'
  end

  local bw_hosts = {}
  local key_dir = wezterm_dir .. '/keys'
  -- 키 저장 디렉토리 생성
  if is_windows then
    local win_key_dir = key_dir:gsub('/', '\\')
    os.execute('if not exist "' .. win_key_dir .. '" mkdir "' .. win_key_dir .. '"')
  else
    os.execute('mkdir -p "' .. key_dir .. '"')
  end

  for _, item in ipairs(items) do
    -- 아이템이 테이블 형식인지 확인 (방어적 처리)
    if type(item) == 'table' then
      local login = item.login or {}
      local uris = login.uris or {}
      local raw_uri = (uris[1] and type(uris[1]) == 'table' and uris[1].uri) or ''

      -- URI에서 ssh:// 등 접두어 제거 및 포트 분리 준비
      local sanitized_uri = raw_uri:gsub('^%a+://', '')

      local host = {
        name = '[BW] ' .. (item.name or '이름 없음'),
        uri = sanitized_uri,
        username = login.username or '',
        password = login.password or '',
        notes = item.notes or '',
      }

      -- notes가 SSH 키인 경우 파일로 저장하여 sshkey 경로로 사용
      -- item.id가 존재할 때만 키 저장 시도
      if item.id and is_ssh_key(host.notes) then
        local key_path = key_dir .. '/bw_key_' .. item.id
        local needs_write = true

        -- 기존 파일이 있고 내용이 같으면 다시 쓰지 않음 (속도 최적화)
        local f_read = io.open(key_path, 'r')
        if f_read then
          local existing_content = f_read:read('*all')
          f_read:close()
          if existing_content == host.notes then
            needs_write = false
          end
        end

        if needs_write then
          local f = io.open(key_path, 'w')
          if f then
            f:write(host.notes)
            f:close()
            if not is_windows then
              -- 경로 공백 대응을 위해 작은 따옴표로 감쌈
              os.execute("chmod 600 '" .. key_path .. "'")
            end
          end
        end
        host.sshkey = key_path
      end
      table.insert(bw_hosts, host)
    end
  end

  -- 성공 시 메모리에 세션과 함께 캐시
  memory_state.bw_session = bw_session
  memory_state.bw_hosts = bw_hosts

  return bw_hosts
end

-- 클립보드 복사 함수 (운영체제별 대응)
local function copy_to_clipboard(text)
  if not text or text == '' then
    return
  end
  if is_windows then
    -- PowerShell을 사용하여 안전하게 복사
    local escaped = text:gsub("'", "''")
    wezterm.run_child_process({
      'powershell.exe',
      '-NoProfile',
      '-Command',
      "Set-Clipboard -Value '" .. escaped .. "'",
    })
  else
    -- 리눅스/맥 대응: xclip, wl-copy, pbcopy 순차 시도
    local escaped = text:gsub('"', '\\"')
    local cmd = 'echo -n "'
      .. escaped
      .. '" | xclip -selection clipboard 2>/dev/null || '
      .. 'echo -n "'
      .. escaped
      .. '" | wl-copy 2>/dev/null || '
      .. 'echo -n "'
      .. escaped
      .. '" | pbcopy 2>/dev/null'
    wezterm.run_child_process({ 'sh', '-c', cmd })
  end
end

-- 작업 선택 서브 메뉴 표시 함수
local function show_ssh_sub_menu(window, pane, host)
  -- 필수 정보 확인
  if not host.uri or host.uri == '' or not host.username or host.username == '' then
    window:perform_action(
      act.PromptInputLine({
        description = '❌ 에러: ['
          .. (host.name or '알 수 없음')
          .. '] uri 또는 username 정보가 없습니다.',
        action = wezterm.action_callback(function() end),
      }),
      pane
    )
    return
  end

  local sub_choices = {
    { label = '원격 접속 (SSH)' },
    { label = '파일 전송 (SFTP)' },
  }

  if not is_windows then
    table.insert(sub_choices, { label = '파일 전송 (RSYNC)' })
  end

  -- 비밀번호가 있는 경우만 복사 메뉴 추가
  if host.password and host.password ~= '' then
    -- 운영체제별 클립보드 도구 사용
    local cmd = is_windows and 'powershell.exe -NoProfile -Command "Get-Clipboard"'
      or 'xclip -selection clipboard -o 2>/dev/null || wl-paste 2>/dev/null || pbpaste 2>/dev/null'
    local success, stdout, _ = wezterm.run_child_process({ 'sh', '-c', cmd })
    local clipboard_content = (success and stdout) and stdout:gsub('^%s+', ''):gsub('%s+$', '') or ''

    local copy_status = ''
    if clipboard_content == host.password then
      copy_status = ' (복사 완료)'
    end
    table.insert(sub_choices, { label = '비밀번호 복사' .. copy_status })
  end

  wezterm.time.call_after(0.1, function()
    if not window then
      return
    end
    local target_p = pane or window:active_pane()

    window:perform_action(act.SendString('\x15'), target_p)
    window:perform_action(
      act.InputSelector({
        title = '🛠️ 작업 선택: ' .. host.name,
        choices = sub_choices,
        action = wezterm.action_callback(function(window, pane, sub_id, sub_label)
          if not sub_label then
            return
          end

          local current_p = pane or window:active_pane()

          -- URI에서 포트 분리 (예: host:port)
          local actual_uri = host.uri
          local port = 22
          if host.uri:find(':') then
            actual_uri = host.uri:match('^([^:]+)')
            port = host.uri:match(':(%d+)$') or 22
          end

          local ssh_auth = ''
          if host.sshkey and host.sshkey ~= '' then
            ssh_auth = '-i ' .. host.sshkey .. ' '
          end

          if sub_label:find('원격 접속') then
            local ssh_cmd_args_str = 'wezterm ssh ' .. ssh_auth .. host.username .. '@' .. actual_uri .. ':' .. port

            window:perform_action(
              act.PromptInputLine({
                description = wezterm.format({
                  { Text = '🚀 SSH 원격 접속 안내 (' .. host.name .. ')\n\n' },
                  { Text = '  만약 ' },
                  { Text = 'WEZTERM_REMOTE_PANE 환경 변수 설정 실패' },
                  { Text = ' 오류가 발생하면\n' },
                  { Text = '  아래 가이드에 따라 원격 서버의 SSH 설정을 수정해야 합니다.\n\n' },
                  { Text = '  ➡️ 원격 서버에서 다음 단계를 따르세요:\n' },
                  { Text = '  1. 원격 서버에 SSH로 접속합니다 (기존 방식대로).\n' },
                  { Text = '  2. ' },
                  { Text = '/etc/ssh/sshd_config' },
                  { Text = ' 파일을 ' },
                  { Text = 'sudo' },
                  { Text = ' 권한으로 엽니다.\n' },
                  { Text = '     (예: ' },
                  { Text = 'sudo vim /etc/ssh/sshd_config' },
                  { Text = ')\n' },
                  { Text = '  3. ' },
                  { Text = 'AcceptEnv' },
                  { Text = ' 줄을 찾아 ' },
                  { Text = 'WEZTERM_REMOTE_PANE' },
                  { Text = ' 을 추가합니다.\n' },
                  { Text = '     (예: ' },
                  { Text = 'AcceptEnv WEZTERM_REMOTE_PANE' },
                  { Text = ')\n' },
                  { Text = '  4. SSH 서비스를 재시작합니다.\n' },
                  { Text = '     (예: ' },
                  { Text = 'sudo systemctl restart sshd' },
                  { Text = ')\n\n' },
                  {
                    Text = '  👉 접속 명령어를 확인하고 Enter를 누르세요 (취소 시 ALT+H 다시 누르세요): ',
                  },
                }),
                initial_value = ssh_cmd_args_str .. '',
                action = wezterm.action_callback(function(window, pane, input_cmd)
                  if not input_cmd then
                    show_ssh_sub_menu(window, pane, host)
                    return
                  end
                  -- 새 탭에서 SSH 접속 실행
                  window:perform_action(act.SpawnCommandInNewTab({ args = { 'sh', '-c', input_cmd } }), pane)
                end),
              }),
              pane
            )
          elseif sub_label:find('SFTP') then
            -- SFTP: 포트는 -P (대문자)
            local sftp_cmd = 'sftp -P ' .. port .. ' ' .. ssh_auth .. host.username .. '@' .. actual_uri
            window:perform_action(
              act.PromptInputLine({
                description = '🚀 SFTP 파일 전송 안내 ('
                  .. host.name
                  .. ')\n\n'
                  .. '  ls    : 원격 서버의 파일 목록을 확인\n'
                  .. '  lls   : 내 컴퓨터(Local)의 파일 목록을 확인\n'
                  .. '  cd    : 원격 서버의 디렉토리를 이동\n'
                  .. '  lcd   : 내 컴퓨터의 작업 디렉토리를 이동\n'
                  .. '  pwd   : 원격 서버의 경로 확인\n'
                  .. '  lpwd  : 내 컴퓨터의 경로 확인\n'
                  .. '  get   : 원격 파일을 내 컴퓨터로 다운로드\n'
                  .. '          ( get [파일/디렉토리명], -r: 디렉토리일때 하위 내용까지 포함  )\n'
                  .. '  put   : 내 컴퓨터의 파일을 원격으로 업로드\n'
                  .. '          ( put [파일/디렉토리명], -r: 디렉토리일때 하위 내용까지 포함 )\n'
                  .. '  exit  : 접속 종료 ( bye 또는 quit 도 가능 )\n\n'
                  .. '  👉 Enter를 눌러 접속하세요 (취소 시 ESC): ',
                initial_value = sftp_cmd,
                action = wezterm.action_callback(function(window, pane, input_cmd)
                  if not input_cmd then
                    show_ssh_sub_menu(window, pane, host)
                    return
                  end
                  window:perform_action(act.SendString(input_cmd .. '\r'), pane)
                end),
              }),
              pane
            )
          elseif sub_label:find('RSYNC') then
            -- 리눅스/맥은 RSYNC (사용 가이드 제공)
            local rsync_ssh = 'ssh -p ' .. port
            if host.sshkey and host.sshkey ~= '' then
              rsync_ssh = rsync_ssh .. ' -i ' .. host.sshkey
            end
            local rsync_base_cmd = 'rsync -avzP -n -e "' .. rsync_ssh .. '" '
            local rsync_server_path = host.username .. '@' .. actual_uri .. ':'

            window:perform_action(
              act.PromptInputLine({
                description = '🚀 RSYNC 파일 전송 안내 ('
                  .. host.name
                  .. ')\n\n'
                  .. '  rsync는 :를 기준으로 로컬/원격을 구분합니다.\n'
                  .. '  명령어 뒤에 SOURCE와 DESTINATION 경로를 추가하세요.\n\n'
                  .. '  ✔ 로컬 -> 원격 (업로드):\n'
                  .. '    '
                  .. rsync_base_cmd
                  .. '[로컬 경로] '
                  .. rsync_server_path
                  .. '/원격/목적지/경로/\n'
                  .. '  ✔ 원격 -> 로컬 (다운로드):\n'
                  .. '    '
                  .. rsync_base_cmd
                  .. rsync_server_path
                  .. '/원격/소스/경로/ [로컬 목적지 경로]\n\n'
                  .. "  ※ 경로 끝의 '/' 가 있으면 디렉토리 안의 파일만 전송, '/' 가 없으면 디렉토리 자체를 전송\n"
                  .. "  ※ 안전한 테스트: '-n' 옵션이 있으면 전송될 파일만 미리 보여줘서 확인 용으로 사용 가능\n"
                  .. "    (실제 전송 시에는 '-n' 을 제거❗해야 함)\n\n"
                  .. '  👉 SOURCE DESTINATION 입력 (취소 시 ALT+H 다시 누르세요): ',
                initial_value = rsync_base_cmd .. rsync_server_path .. '',
                action = wezterm.action_callback(function(window, pane, input_cmd)
                  if not input_cmd then
                    -- 취소 시 이전 메뉴 다시 호출 (rsync는 별도 창이 아니라 현재 창에 실행되므로 메뉴를 다시 띄워줘야 함)
                    show_ssh_sub_menu(window, pane, host)
                    return
                  end
                  window:perform_action(act.SendString('\x15' .. input_cmd .. '\r'), pane)
                end),
              }),
              pane
            )
          elseif sub_label:find('비밀번호 복사') then
            copy_to_clipboard(host.password)
            -- 복사 후 약간의 지연을 주어 클립보드 반영 확인 후 새로고침
            wezterm.time.call_after(0.1, function()
              show_ssh_sub_menu(window, pane, host)
            end)
          end
        end),
      }),
      target_p
    )
  end)
end

-- 명령어 팔레트 리스트 정의
local gw = is_windows and '.\\gradlew.bat' or './gradlew'
local my_commands = {
  --[[
    { label = '샘플', args = { '명령어', '인자1', '인자2' }, target = 'current', confirm = true },
    - target  → 'current'/생략: 현재 탭에 타이핑 (SendString), 'new_tab': 새 프로세스로 실행 (Spawn), 'split': 우측 분할 실행
    - confirm → (target='current' 전용) true/생략 시 명령어 끝에 엔터(\r) 추가, false 시 명령어만 입력 후 대기
  ]]
  { label = '[Gradle] 실행', confirm = false }, -- 콜백에서 동적 입력 처리
  { label = '[Gradle] 빌드', confirm = false }, -- 콜백에서 동적 입력 처리
  {
    label = '[Gradle] 로컬 저장소 배포',
    args = { gw, 'clean', 'publishToMavenLocal', '-x', 'test', '--build-cache' },
    confirm = false,
  },
  {
    label = '[Gradle] 중앙 저장소 배포',
    args = { gw, 'clean', 'publishAllPublicationsToCentralPortalRepository', '-x', 'test', '--build-cache' },
    confirm = false,
  },
  {
    label = '[JDTLS] 캐시 초기화',
    confirm = false,
  },
  {
    label = '포트 확인',
    args = is_windows and { 'netstat', '-ano', '|', 'findstr', ':<PORT>' } or { 'ss', '-nltp', '|', 'grep', ':<PORT>' },
    confirm = false,
  },
  {
    label = '프로세스 확인',
    args = is_windows and { 'tasklist', '|', 'findstr', '/i', '"<PATTERN>"' }
      or { 'ps', '-ef', '|', 'grep', "'<PATTERN>'", '|', 'grep', '-v', 'grep' },
    confirm = false,
  },
  {
    label = '프로세스 종료',
    args = is_windows and { 'taskkill', '/f', '/pid', '<PID>' } or { 'kill', '-9', '<PID>' },
    confirm = false,
  },
}

-- 단축키 설정
config.keys = {
  -- ALT + c 키를 누르면 명령어 팔레트가 팝업 (현재 폴더 상태에 따라 동적 필터링)
  {
    key = 'c',
    mods = 'ALT',
    action = wezterm.action_callback(function(window, pane)
      local cwd = get_project_key(pane)
      local gw_name = is_windows and 'gradlew.bat' or 'gradlew'

      -- 터미널 내부 포커스 확인: WezTerm 커서 주변의 화면 텍스트를 읽어 프롬프트 경로 추출
      local terminal_cwd = nil
      local cursor = pane:get_cursor_position()

      if cursor and cursor.y then
        -- [중요] Neovim 내부 터미널(CWD 인식 불능) 대응 로직:
        -- WezTerm의 pane:get_current_working_dir()은 Neovim이 실행된 최초 경로만 반환할 뿐,
        -- Neovim 내부 터미널 버퍼나 분할 창에서 `cd`로 이동한 실제 작업 경로는 추적하지 못합니다.
        -- 이를 해결하기 위해 현재 눈에 보이는 화면(Viewport) 전체의 텍스트를 직접 스캔하여
        -- 가장 최근 프롬프트 패턴(@사용자:경로)을 추출, 실제 작업 디렉토리를 강제로 찾아냅니다.

        local dims = pane:get_dimensions()
        -- 커서 주변만 읽는 방식은 Neovim 내부에서 위치가 어긋날 수 있으므로, 현재 보이는 화면 전체(Viewport)를 읽어옴
        local start_row = dims.scrollback_rows - dims.viewport_rows
        local end_row = dims.scrollback_rows
        local text = pane:get_text_from_region(0, start_row, dims.cols, end_row)

        if text then
          -- 줄바꿈을 공백으로 바꾸고 연속된 공백을 압축하여 경로가 끊기지 않게 함
          local joined_text = text:gsub('\n', ' '):gsub('%s+', ' ')

          -- 화면 전체에서 가장 마지막에 등장하는 @사용자:경로 패턴을 찾음
          for extracted_path in joined_text:gmatch('@[%w_.-]+:([~/%w_.-]+)') do
            -- 프롬프트 기호($, #, >) 이후 제거
            extracted_path = extracted_path:gsub('[$#>].*', '')

            if extracted_path:sub(1, 1) == '~' then
              terminal_cwd = home_dir .. extracted_path:sub(2)
            else
              terminal_cwd = extracted_path
            end
          end
        end
      end

      -- 프롬프트에서 추출한 경로가 유효한 Gradle 프로젝트인지 확인
      local active_cwd = cwd
      if
        terminal_cwd
        and (
          file_exists(terminal_cwd .. '/' .. gw_name)
          or file_exists(terminal_cwd .. '/build.gradle')
          or file_exists(terminal_cwd .. '/build.gradle.kts')
        )
      then
        active_cwd = terminal_cwd
      end

      local gradlew_exists = file_exists(active_cwd .. '/' .. gw_name)

      -- CentralPortal 설정 여부 확인 함수 (build.gradle 또는 build.gradle.kts 확인)
      local function has_central_portal(dir)
        local files = { '/build.gradle', '/build.gradle.kts' }
        for _, file in ipairs(files) do
          local f = io.open(dir .. file, 'r')
          if f then
            local content = f:read('*all')
            f:close()
            if content:find('CentralPortal', 1, true) then
              return true
            end
          end
        end
        return false
      end

      -- 중앙 저장소 배포 여부: gradlew가 있고 CentralPortal 설정이 있을 때만 true
      local central_portal_exists = gradlew_exists and has_central_portal(active_cwd)

      -- 현재 폴더 상태에 따른 동적 리스트 생성
      local choices = {}
      for _, item in ipairs(my_commands) do
        local show = true
        local label = item.label

        if label:find('^%[Gradle%]') then
          -- Gradle 관련 명령어 필터링
          if not gradlew_exists then
            -- gradlew가 없으면 모든 Gradle 명령어 숨김
            show = false
          elseif label:find('중앙 저장소 배포') then
            -- '중앙 저장소 배포'는 CentralPortal 설정이 있을 때만 표시
            if not central_portal_exists then
              show = false
            end
          end
        end

        if show then
          table.insert(choices, { label = label })
        end
      end

      window:perform_action(act.SendString('\x15'), pane)
      window:perform_action(
        act.InputSelector({
          title = '🚀 명령어 선택 (devers2)',
          choices = choices,
          action = wezterm.action_callback(function(window, pane, id, label)
            -- 아무것도 선택하지 않고 닫았을 때 예외 처리
            if not label then
              return
            end

            -- 선택한 라벨에 해당하는 명령어 데이터 찾기
            local cmd = nil
            for _, item in ipairs(my_commands) do
              if item.label == label then
                cmd = item
                break
              end
            end

            if cmd then
              -- Gradle 실행 (동적 입력, Init Script 경로 및 상태 저장)
              if label == '[Gradle] 실행' then
                local state = load_state(pane, label)
                local saved_init_script_path = state.gradle_init_script_path or ''

                -- 1. Init 스크립트 경로 입력 프롬프트
                window:perform_action(
                  act.PromptInputLine({
                    description = '📜 Init 스크립트 경로를 입력하세요 (예: /path/to/init.gradle, 없으면 엔터):',
                    initial_value = saved_init_script_path,
                    action = wezterm.action_callback(function(window, pane, init_script_path_input)
                      -- 사용자가 입력을 취소하면 중단.
                      if init_script_path_input == nil then
                        return
                      end

                      local current_init_script_path = init_script_path_input or ''

                      -- 2. 모듈명 입력 프롬프트
                      window:perform_action(
                        act.PromptInputLine({
                          description = '📦 모듈명을 입력하세요 (예: www, 없으면 엔터):',
                          initial_value = state.gradle_module or '', -- Use saved module name
                          action = wezterm.action_callback(function(window, pane, module_input)
                            -- 사용자가 입력을 취소하면 중단.
                            if module_input == nil then
                              return
                            end
                            local current_module = module_input or ''

                            -- 3. 프로필 입력 프롬프트
                            window:perform_action(
                              act.PromptInputLine({
                                description = '🔑 프로필을 입력하세요 (예: dev, 없으면 엔터):',
                                initial_value = state.gradle_profile or '', -- Use saved profile name
                                action = wezterm.action_callback(function(window, pane, profile_input)
                                  -- 사용자가 입력을 취소하면 중단.
                                  if profile_input == nil then
                                    return
                                  end
                                  local current_profile = profile_input or ''

                                  -- 수집된 모든 입력값 저장
                                  save_state(pane, label, {
                                    gradle_init_script_path = current_init_script_path,
                                    gradle_module = current_module,
                                    gradle_profile = current_profile,
                                  })

                                  -- Gradle 래퍼를 사용한 기본 명령어 구성
                                  local command_parts = { gw } -- Gradle 래퍼(wrapper)를 사용하여 빌드를 시작

                                  -- Init 스크립트 경로가 제공된 경우 -I 옵션 추가
                                  if current_init_script_path ~= '' then
                                    table.insert(command_parts, '-I')
                                    -- 경로에 대한 올바른 쉘 이스케이핑을 위해 shell_quote 사용
                                    table.insert(command_parts, shell_quote(current_init_script_path))
                                  end

                                  -- Gradle 태스크 정의 (예: 'bootRun' 또는 ':module:bootRun')
                                  local task = (current_module ~= '') and (':' .. current_module .. ':bootRun')
                                    or 'bootRun'
                                  -- 태스크명도 안전하게 이스케이핑
                                  table.insert(command_parts, shell_quote(task))

                                  -- 프로필이 입력된 경우 프로필 인자 정의
                                  if current_profile ~= '' then
                                    local profile_val = '--spring.profiles.active=' .. current_profile
                                    -- --args="내용" 전체를 OS 규칙에 맞게 이스케이핑
                                    table.insert(command_parts, '--args=' .. shell_quote(profile_val))
                                  end

                                  -- 기본으로 지속 감시 모드(소스 및 자원 변경 사항 감시 및 자동 컴파일 반영), 병렬 빌드, 빌드 캐시 적용
                                  table.insert(command_parts, '-t --parallel --build-cache')

                                  -- 명령어의 모든 부분 결합
                                  local full_command = table.concat(command_parts, ' ')

                                  if cmd.confirm ~= false then
                                    full_command = full_command .. '\r'
                                  end

                                  -- 최종 명령어를 활성 페인으로 전송
                                  window:perform_action(act.SendString('\x15' .. full_command), pane)
                                end),
                              }),
                              pane
                            )
                          end),
                        }),
                        pane
                      )
                    end),
                  }),
                  pane
                )
                return
              elseif label == '[Gradle] 빌드' then
                local state = load_state(pane, label)

                local function is_y(val)
                  return val and val:upper() == 'Y'
                end

                local function validate_yn(val, default)
                  if not val then
                    return default
                  end
                  local upper = val:upper()
                  if upper == 'Y' or upper == 'N' then
                    return upper
                  end
                  return default
                end

                local function validate_debug(val, default)
                  if not val then
                    return default
                  end
                  local lower = val:lower()
                  if lower == 'info' or lower == 'debug' or lower == '' then
                    return lower
                  end
                  return default
                end

                -- 태스크명 입력을 파싱하여 -x task1 -x task2 형태로 변환하는 함수
                local function parse_exclude_tasks(input)
                  if not input or input:match('^%s*$') then
                    return {}
                  end
                  -- 쉼표 또는 공백으로 구분 후 공백 제거
                  local tasks = {}
                  for token in input:gmatch('[^,%s]+') do
                    table.insert(tasks, token)
                  end
                  return tasks
                end

                window:perform_action(
                  act.PromptInputLine({
                    description = '🧹 클린 여부 (Y/N, 기본값 N):',
                    initial_value = state.gradle_clean or 'N',
                    action = wezterm.action_callback(function(window, pane, clean_input)
                      if clean_input == nil then
                        return
                      end

                      window:perform_action(
                        act.PromptInputLine({
                          description = '🚫 태스크 제외 (test 등 제외할 태스크 명, 공백 또는 콤마로 구분):',
                          initial_value = state.gradle_exclude_tasks or '',
                          action = wezterm.action_callback(function(window, pane, exclude_tasks_input)
                            if exclude_tasks_input == nil then
                              return
                            end

                            window:perform_action(
                              act.PromptInputLine({
                                description = '🚀 병렬 빌드 (Y/N, 기본값 Y):',
                                initial_value = state.gradle_parallel or 'Y',
                                action = wezterm.action_callback(function(window, pane, parallel_input)
                                  if parallel_input == nil then
                                    return
                                  end

                                  window:perform_action(
                                    act.PromptInputLine({
                                      description = '📦 빌드 캐시 (Y/N, 기본값 Y):',
                                      initial_value = state.gradle_build_cache or 'Y',
                                      action = wezterm.action_callback(function(window, pane, build_cache_input)
                                        if build_cache_input == nil then
                                          return
                                        end

                                        window:perform_action(
                                          act.PromptInputLine({
                                            description = '🔄 의존성 갱신 (Y/N, 기본값 N):',
                                            initial_value = state.gradle_refresh or 'N',
                                            action = wezterm.action_callback(function(window, pane, refresh_input)
                                              if refresh_input == nil then
                                                return
                                              end

                                              window:perform_action(
                                                act.PromptInputLine({
                                                  description = '🐛 디버깅 옵션 (공백/info/debug, 기본값 공백):',
                                                  initial_value = state.gradle_debug or '',
                                                  action = wezterm.action_callback(function(window, pane, debug_input)
                                                    if debug_input == nil then
                                                      return
                                                    end

                                                    window:perform_action(
                                                      act.PromptInputLine({
                                                        description = '☕ Java Home 경로 (공백이면 기본값 사용, 예: /var/opt/_devtools2/modules/java/jdk-21):',
                                                        initial_value = state.gradle_java_home or '',
                                                        action = wezterm.action_callback(
                                                          function(window, pane, java_home_input)
                                                            if java_home_input == nil then
                                                              return
                                                            end

                                                            local v_clean =
                                                              validate_yn(clean_input, state.gradle_clean or 'N')
                                                            local v_exclude_tasks = exclude_tasks_input or ''
                                                            local v_parallel =
                                                              validate_yn(parallel_input, state.gradle_parallel or 'Y')
                                                            local v_build_cache = validate_yn(
                                                              build_cache_input,
                                                              state.gradle_build_cache or 'Y'
                                                            )
                                                            local v_refresh =
                                                              validate_yn(refresh_input, state.gradle_refresh or 'N')
                                                            local v_debug =
                                                              validate_debug(debug_input, state.gradle_debug or '')
                                                            local v_java_home = java_home_input:match('^%s*(.-)%s*$') -- 앞뒤 공백 제거

                                                            save_state(pane, label, {
                                                              gradle_clean = v_clean,
                                                              gradle_exclude_tasks = v_exclude_tasks,
                                                              gradle_parallel = v_parallel,
                                                              gradle_build_cache = v_build_cache,
                                                              gradle_refresh = v_refresh,
                                                              gradle_debug = v_debug,
                                                              gradle_java_home = v_java_home,
                                                            })

                                                            local cmd_parts = { gw }

                                                            if is_y(v_clean) then
                                                              table.insert(cmd_parts, 'clean')
                                                            end
                                                            table.insert(cmd_parts, 'build')

                                                            -- 태스크 제외: 파싱된 각 태스크에 -x 추가
                                                            local exclude_list = parse_exclude_tasks(v_exclude_tasks)
                                                            for _, task_name in ipairs(exclude_list) do
                                                              table.insert(cmd_parts, '-x ' .. task_name)
                                                            end

                                                            if is_y(v_parallel) then
                                                              table.insert(cmd_parts, '--parallel')
                                                            end
                                                            if is_y(v_build_cache) then
                                                              table.insert(cmd_parts, '--build-cache')
                                                            end
                                                            if is_y(v_refresh) then
                                                              table.insert(cmd_parts, '--refresh-dependencies')
                                                            end

                                                            local dbg = v_debug
                                                            if dbg == 'info' then
                                                              table.insert(cmd_parts, '--info --stacktrace')
                                                            elseif dbg == 'debug' then
                                                              table.insert(cmd_parts, '--debug --stacktrace')
                                                            end

                                                            -- Java Home 경로가 있으면 -Dorg.gradle.java.home 추가
                                                            if v_java_home ~= '' then
                                                              table.insert(
                                                                cmd_parts,
                                                                '-Dorg.gradle.java.home=' .. shell_quote(v_java_home)
                                                              )
                                                            end

                                                            local full_cmd = table.concat(cmd_parts, ' ')
                                                            if cmd.confirm ~= false then
                                                              full_cmd = full_cmd .. '\r'
                                                            end
                                                            window:perform_action(
                                                              act.SendString('\x15' .. full_cmd),
                                                              pane
                                                            )
                                                          end
                                                        ),
                                                      }),
                                                      pane
                                                    )
                                                  end),
                                                }),
                                                pane
                                              )
                                            end),
                                          }),
                                          pane
                                        )
                                      end),
                                    }),
                                    pane
                                  )
                                end),
                              }),
                              pane
                            )
                          end),
                        }),
                        pane
                      )
                    end),
                  }),
                  pane
                )
                return
              elseif label == '[JDTLS] 캐시 초기화' then
                local project_name = active_cwd:match('([^/]+)$') or 'unknown'
                local jdtls_cache_path = nvim_cache_dir .. '/jdtls/' .. project_name

                -- 디렉토리 존재 여부 확인 (ls 명령으로 간접 확인)
                local success, _, _ = wezterm.run_child_process({ 'ls', '-d', jdtls_cache_path })

                if not success then
                  window:perform_action(
                    act.PromptInputLine({
                      description = '❌ 캐시 폴더가 존재하지 않습니다:\n'
                        .. jdtls_cache_path
                        .. '\n\n(Enter를 눌러 종료)',
                      action = wezterm.action_callback(function() end),
                    }),
                    pane
                  )
                  return
                end

                window:perform_action(
                  act.PromptInputLine({
                    description = '🗑️ JDTLS 캐시를 삭제하시겠습니까?\n경로: '
                      .. jdtls_cache_path
                      .. '\n\n(Y/N 입력, 기본값 N):',
                    initial_value = 'N',
                    action = wezterm.action_callback(function(window, pane, delete_confirm)
                      if delete_confirm and delete_confirm:upper() == 'Y' then
                        local rm_cmd = 'rm -rf ' .. shell_quote(jdtls_cache_path) .. '\r'
                        window:perform_action(act.SendString('\x15' .. rm_cmd), pane)
                      end
                    end),
                  }),
                  pane
                )
                return
              end

              -- args가 없는 명령어의 경우(동적 처리 등) 아래 로직을 건너뜜
              if not cmd.args then
                return
              end

              -- 실행될 작업 경로 (Gradle 명령어인 경우 찾은 프로젝트 경로 활용)
              local run_cwd = cwd
              if label:find('^%[Gradle%]') and active_cwd ~= cwd then
                run_cwd = active_cwd
              end

              if cmd.target == 'new_tab' then
                -- 1. 새 탭에서 실행 (Watch 모드 추천)
                window:perform_action(act.SpawnCommandInNewTab({ args = cmd.args, cwd = run_cwd }), pane)
              elseif cmd.target == 'split' then
                -- 2. 오른쪽 화면 분할 후 실행 (모니터링 추천)
                window:perform_action(
                  act.SplitPane({
                    direction = 'Right',
                    command = { args = cmd.args, cwd = run_cwd },
                  }),
                  pane
                )
              else
                -- 3. 현재 탭에서 실행 (Current)
                local cmd_string = table.concat(cmd.args, ' ')

                -- confirm이 true이거나 설정되지 않았을 때만 엔터(\r) 추가
                if cmd.confirm ~= false then
                  cmd_string = cmd_string .. '\r'
                end

                window:perform_action(act.SendString('\x15' .. cmd_string), pane)
              end
            end
          end),
        }),
        pane
      )
    end),
  },

  -- ALT + h 키를 누르면 SSH 접속 목록이 팝업
  {
    key = 'h',
    mods = 'ALT',
    action = wezterm.action_callback(function(window, pane)
      -- 세션 확인 순서: 1. 시스템 환경변수, 2. 터미널 User Var, 3. WezTerm 인메모리 상태
      local bw_session = os.getenv('BW_SESSION') or pane:get_user_vars().BW_SESSION or memory_state.bw_session

      -- 실행 로직
      local local_hosts = load_ssh_hosts()

      -- 헬퍼: 호스트 목록 표시 실행
      local function show_host_selector(all_hosts, is_synced)
        local choices = {}
        -- 비트워든 데이터 동기화를 위한 메뉴 항상 추가
        table.insert(choices, { label = '🔄 [Bitwarden 동기화 실행]' })

        for _, host in ipairs(all_hosts) do
          table.insert(choices, { label = host.name or host.uri or 'Unknown' })
        end

        window:perform_action(act.SendString('\x15'), pane)
        window:perform_action(
          act.InputSelector({
            title = '🌐 SSH 접속 선택' .. (is_synced and ' (BW 동기화됨)' or ''),
            choices = choices,
            action = wezterm.action_callback(function(window, pane, id, label)
              if not label then
                return
              end

              if label == '🔄 [Bitwarden 동기화 실행]' then
                wezterm.log_info('DEBUG: [BW] === START BITWARDEN SYNC ===')
                local bw_path = find_executable('bw')
                if not bw_path then
                  window:perform_action(
                    act.PromptInputLine({
                      description = '❌ Bitwarden CLI(bw)를 찾을 수 없습니다.',
                      action = wezterm.action_callback(function() end),
                    }),
                    pane
                  )
                  return
                end

                -- 상태 표시 함수
                local function show_msg(win, msg)
                  wezterm.log_info('DEBUG: [BW] UI MSG: ' .. msg)
                  -- 0.1초 지연으로 이전 UI 오버레이가 닫힐 시간을 확보
                  wezterm.time.call_after(0.1, function()
                    if not win then
                      return
                    end
                    local target_p = win:active_pane()
                    if not target_p then
                      return
                    end
                    win:perform_action(
                      act.PromptInputLine({
                        description = msg .. '\n잠시만 기다려주세요...',
                        initial_value = '',
                        action = wezterm.action_callback(function() end),
                      }),
                      target_p
                    )
                  end)
                end

                -- 동기화 및 목록 갱신 단계 (password: bw CLI stdin 파이프 대응용)
                local function step_3_sync(win, session, password)
                  wezterm.log_info('DEBUG: [BW] STEP 3: Starting sync/fetch')
                  show_msg(win, '⏳ Bitwarden 서버 동기화 및 데이터 분석 중...')

                  wezterm.time.call_after(0.5, function()
                    wezterm.log_info('DEBUG: [BW] Calling fetch_bitwarden_hosts...')
                    local target_p = win:active_pane()

                    -- password 전달: bw CLI가 --session 무시하고 stdin 비번 요구 시 자동 대응
                    local bh, err = fetch_bitwarden_hosts(win, target_p, session, false, password)

                    if bh then
                      wezterm.log_info('DEBUG: [BW] Sync success! Host count: ' .. #bh)
                      local lh = load_ssh_hosts()
                      local combined = {}
                      for _, h in ipairs(lh) do
                        table.insert(combined, h)
                      end
                      for _, h in ipairs(bh) do
                        table.insert(combined, h)
                      end
                      show_host_selector(combined, true)
                    else
                      -- 실패 시 에러 표시 후 종료
                      wezterm.log_error('DEBUG: [BW] Sync error: ' .. (err or 'unknown'))
                      memory_state.bw_session = nil
                      wezterm.time.call_after(0.1, function()
                        win:perform_action(
                          act.PromptInputLine({
                            description = '❌ 동기화 실패: '
                              .. (err or '알 수 없는 오류')
                              .. '\n\nALT+H 후 다시 동기화를 선택하세요.',
                            action = wezterm.action_callback(function() end),
                          }),
                          win:active_pane()
                        )
                      end)
                    end
                  end)
                end

                -- 마스터 비밀번호 입력 및 잠금 해제 단계
                local function step_2_unlock(win)
                  wezterm.log_info('DEBUG: [BW] STEP 2: Prompting for password')
                  wezterm.time.call_after(0.1, function()
                    local password = nil
                    local description = '🔐 Bitwarden 마스터 비밀번호를 입력하세요'

                    if is_windows then
                      -- 1. Windows (PowerShell GUI)
                      wezterm.log_info('DEBUG: [BW] Trying PowerShell for secure input')
                      local ps_script = [[
                        Add-Type -AssemblyName System.Windows.Forms;
                        $f = New-Object System.Windows.Forms.Form;
                        $f.Text = 'Bitwarden'; $f.Width = 350; $f.Height = 160;
                        $f.StartPosition = 'CenterScreen'; $f.TopMost = $true;
                        $l = New-Object System.Windows.Forms.Label;
                        $l.Text = 'Master Password:'; $l.Top = 15; $l.Left = 20; $l.Width = 300;
                        $f.Controls.Add($l);
                        $t = New-Object System.Windows.Forms.TextBox;
                        $t.PasswordChar = '*'; $t.Top = 40; $t.Left = 20; $t.Width = 290;
                        $f.Controls.Add($t);
                        $b = New-Object System.Windows.Forms.Button;
                        $b.Text = 'OK'; $b.Top = 80; $b.Left = 120; $b.DialogResult = [System.Windows.Forms.DialogResult]::OK;
                        $f.Controls.Add($b); $f.AcceptButton = $b;
                        if($f.ShowDialog() -eq 'OK'){ Write-Output $t.Text }
                      ]]
                      local ok, stdout, _ =
                        wezterm.run_child_process({ 'powershell', '-NoProfile', '-Command', ps_script })
                      if ok and stdout then
                        password = stdout:gsub('[\r\n]+$', '')
                      end
                    else
                      -- 2. Mac (osascript)
                      local osascript_path = find_executable('osascript')
                      if osascript_path then
                        wezterm.log_info('DEBUG: [BW] Trying osascript for secure input')
                        local ok, stdout, _ = wezterm.run_child_process({
                          osascript_path,
                          '-e',
                          'display dialog "' .. description .. '" default answer "" with hidden answer',
                          '-e',
                          'text returned of result',
                        })
                        if ok and stdout then
                          password = stdout:gsub('[\r\n]+$', '')
                        end
                      end

                      -- 3. Linux (Zenity or KDialog)
                      if not password then
                        local zenity_path = find_executable('zenity')
                        if zenity_path then
                          wezterm.log_info('DEBUG: [BW] Trying zenity for secure input')
                          local ok, stdout, _ =
                            wezterm.run_child_process({ zenity_path, '--password', '--title=' .. description })
                          if ok and stdout then
                            password = stdout:gsub('[\r\n]+$', '')
                          end
                        else
                          local kdialog_path = find_executable('kdialog')
                          if kdialog_path then
                            wezterm.log_info('DEBUG: [BW] Trying kdialog for secure input')
                            local ok, stdout, _ = wezterm.run_child_process({ kdialog_path, '--password', description })
                            if ok and stdout then
                              password = stdout:gsub('[\r\n]+$', '')
                            end
                          end
                        end
                      end
                    end

                    -- 네이티브 도구가 없거나 취소된 경우 폴백 (PromptInputLine)
                    if not password or password == '' then
                      wezterm.log_info('DEBUG: [BW] Falling back to PromptInputLine for password')
                      win:perform_action(
                        act.PromptInputLine({
                          description = description
                            .. ':\n(시스템 보안 입력창을 사용할 수 없어 마스킹을 지원하지 않습니다)',
                          action = wezterm.action_callback(function(w, pn, input_pass)
                            if not input_pass or input_pass == '' then
                              show_host_selector(local_hosts, false)
                              return
                            end

                            -- 콜백 내부에서 잠금 해제 로직 실행
                            wezterm.time.call_after(0.1, function()
                              show_msg(w, '🔓 Bitwarden 잠금 해제 중...')
                              wezterm.time.call_after(0.5, function()
                                local success, stdout, stderr =
                                  wezterm.run_child_process({ bw_path, 'unlock', input_pass, '--raw' })
                                if success and stdout and stdout ~= '' then
                                  local new_session = stdout:gsub('%s+$', '')
                                  memory_state.bw_session = new_session
                                  step_3_sync(w, new_session) -- input_pass 전달: CLI stdin 파이프 대응
                                else
                                  wezterm.time.call_after(0.1, function()
                                    w:perform_action(
                                      act.PromptInputLine({
                                        description = '❌ 잠금 해제 실패: '
                                          .. (stderr or '비밀번호를 확인해주세요.'),
                                        action = wezterm.action_callback(function() end),
                                      }),
                                      w:active_pane()
                                    )
                                  end)
                                end
                              end)
                            end)
                          end),
                        }),
                        win:active_pane()
                      )
                      return
                    end

                    -- 네이티브 입력창에서 비밀번호를 받은 경우 바로 잠금 해제 진행
                    show_msg(win, '🔓 Bitwarden 잠금 해제 중...')
                    wezterm.time.call_after(0.5, function()
                      wezterm.log_info('DEBUG: [BW] Running bw unlock (from native input)...')
                      local success, stdout, stderr =
                        wezterm.run_child_process({ bw_path, 'unlock', password, '--raw' })

                      if success and stdout and stdout ~= '' then
                        wezterm.log_info('DEBUG: [BW] Unlock success!')
                        local new_session = stdout:gsub('%s+$', '')
                        memory_state.bw_session = new_session
                        step_3_sync(win, new_session, password) -- password 전달: CLI stdin 파이프 대응
                      else
                        wezterm.log_error('DEBUG: [BW] Unlock failed. stderr: ' .. (stderr or ''))
                        wezterm.time.call_after(0.1, function()
                          win:perform_action(
                            act.PromptInputLine({
                              description = '❌ 잠금 해제 실패: '
                                .. (stderr or '비밀번호를 확인해주세요.'),
                              action = wezterm.action_callback(function() end),
                            }),
                            win:active_pane()
                          )
                        end)
                      end
                    end)
                  end)
                end

                -- 초기 상태 확인 단계
                local function step_1_check_status()
                  wezterm.log_info('DEBUG: [BW] STEP 1: Checking status')
                  show_msg(window, '🔍 Bitwarden 상태 확인 중...')

                  wezterm.time.call_after(0.5, function()
                    -- 0. 세션 재사용 시도: 이미 세션이 있다면 먼저 유효성 테스트
                    local existing_session = memory_state.bw_session or os.getenv('BW_SESSION')
                    if existing_session and existing_session ~= '' then
                      wezterm.log_info('DEBUG: [BW] Testing existing session validity...')
                      -- 가벼운 sync 명령으로 세션 유효성 확인
                      local s_ok, _, _ = wezterm.run_child_process({ bw_path, 'sync', '--session', existing_session })
                      if s_ok then
                        wezterm.log_info('DEBUG: [BW] Existing session is valid. Skipping unlock.')
                        step_3_sync(window, existing_session)
                        return
                      end
                      wezterm.log_info('DEBUG: [BW] Existing session is invalid or expired.')
                      memory_state.bw_session = nil -- 무효한 세션 초기화
                    end

                    wezterm.log_info('DEBUG: [BW] Running bw status...')
                    local success, stdout, stderr = wezterm.run_child_process({ bw_path, 'status' })
                    wezterm.log_info('DEBUG: [BW] status cmd finished, success=' .. tostring(success))

                    local status_data = json_decode(stdout)
                    if not status_data and stdout then
                      local cleaned = stdout:match('{.*}')
                      if cleaned then
                        status_data = json_decode(cleaned)
                      end
                    end

                    local status = status_data and status_data.status or 'unknown'
                    wezterm.log_info('DEBUG: [BW] Status detected: ' .. status)

                    if status == 'unlocked' then
                      -- unlocked 상태인데 위에서 세션 테스트가 실패했다면 새로 unlock이 필요할 수 있음
                      step_2_unlock(window)
                    elseif status == 'locked' then
                      step_2_unlock(window)
                    else
                      wezterm.log_info('DEBUG: [BW] Login required')
                      wezterm.time.call_after(0.1, function()
                        window:perform_action(
                          act.PromptInputLine({
                            description = '🔑 Bitwarden 로그인이 필요합니다. 터미널에서 `bw login`을 실행하세요.',
                            action = wezterm.action_callback(function() end),
                          }),
                          window:active_pane()
                        )
                      end)
                    end
                  end)
                end

                -- 시작
                step_1_check_status()
                return
              end

              local selected_host = nil
              for _, host in ipairs(all_hosts) do
                if (host.name or host.uri or 'Unknown') == label then
                  selected_host = host
                  break
                end
              end
              if selected_host then
                -- 마우스 클릭 시 즉시 선택되는 현상을 방지하기 위해 0.1초 지연 후 서브 메뉴 표시
                wezterm.time.call_after(0.1, function()
                  local current_win = window or wezterm.active_window()
                  local current_pane = pane or current_win:active_pane()
                  show_ssh_sub_menu(current_win, current_pane, selected_host)
                end)
              end
            end),
          }),
          pane
        )
      end

      if bw_session and bw_session ~= '' then
        -- 캐시된 데이터가 있는지 확인
        if memory_state.bw_session == bw_session and memory_state.bw_hosts then
          -- 캐시가 있으면 즉시 목록 표시
          local all_hosts = {}
          for _, h in ipairs(local_hosts) do
            table.insert(all_hosts, h)
          end
          for _, h in ipairs(memory_state.bw_hosts) do
            table.insert(all_hosts, h)
          end
          show_host_selector(all_hosts, true)
        else
          -- 캐시가 없으면 로딩 UI 표시 후 조회
          window:perform_action(
            act.PromptInputLine({
              description = '⏳ Bitwarden 데이터 분석 중...\n잠시만 기다려주세요...',
              action = wezterm.action_callback(function() end),
            }),
            pane
          )

          wezterm.time.call_after(0.1, function()
            local bw_hosts, err = fetch_bitwarden_hosts(window, pane, bw_session)
            if bw_hosts then
              local all_hosts = {}
              for _, h in ipairs(local_hosts) do
                table.insert(all_hosts, h)
              end
              for _, h in ipairs(bw_hosts) do
                table.insert(all_hosts, h)
              end
              show_host_selector(all_hosts, true)
            else
              -- 세션이 무효한 경우 알림 후 로컬 목록만 표시
              memory_state.bw_session = nil
              memory_state.bw_hosts = nil
              wezterm.log_error('BW Sync Failed: ' .. (err or 'unknown'))
              show_host_selector(local_hosts, false)
            end
          end)
        end
      else
        -- 세션이 없으면 바로 로컬 목록 표시 (동기화 옵션 포함됨)
        show_host_selector(local_hosts, false)
      end
    end),
  },

  -- 기본 창 분할 단축키
  { key = 'v', mods = 'ALT', action = act.SplitHorizontal({ domain = 'CurrentPaneDomain' }) },
  { key = 's', mods = 'ALT', action = act.SplitVertical({ domain = 'CurrentPaneDomain' }) },
}

--[[
로컬 설정 파일 분리: ~/.wezterm/settings.lua

-- 외장 그래픽
local M = {}
function M.apply_to_config(config)
    config.front_end = "WebGpu"
end
return M

-- 내장 그래픽
local M = {}
function M.apply_to_config(config)
    config.front_end = "Software"
    config.animation_fps = 1
end
return M
]]
local settings_file_path = home_dir:gsub('\\', '/') .. '/.wezterm/settings.lua'

-- 파일 존재 여부 확인 후 로드
local function load_external_settings(config)
  local f = io.open(settings_file_path, 'r')
  if f ~= nil then
    io.close(f)
    -- package.path에 해당 경로를 임시로 추가하거나 직접 loadfile을 사용합니다.
    local success, external_module = pcall(loadfile, settings_file_path)
    if success and external_module then
      local run_success, settings = pcall(external_module)
      if run_success and settings and type(settings.apply_to_config) == 'function' then
        settings.apply_to_config(config)
        wezterm.log_info('External settings loaded from: ' .. settings_file_path)
      end
    end
  else
    wezterm.log_info('No external settings found at: ' .. settings_file_path)
  end
end

-- 기존 복잡한 Lua 단축키 대신 독립형 fzf 셸 스크립트를 즉시 호출하도록 단축키 덮어쓰기
config.keys = {
  -- ALT + c: 명령어 팔레트 실행
  {
    key = 'c',
    mods = 'ALT',
    action = act.SendString('$DEVTOOLS2/scripts/fzf/command-palette\n'),
  },
  -- ALT + h: SSH/Bitwarden 매니저 실행
  {
    key = 'h',
    mods = 'ALT',
    action = act.SendString('$DEVTOOLS2/scripts/fzf/bw-server-manager\n'),
  },
  -- 기본 창 분할 단축키
  { key = 'v', mods = 'ALT', action = act.SplitHorizontal({ domain = 'CurrentPaneDomain' }) },
  { key = 's', mods = 'ALT', action = act.SplitVertical({ domain = 'CurrentPaneDomain' }) },
}

-- 설정 적용
load_external_settings(config)

return config
