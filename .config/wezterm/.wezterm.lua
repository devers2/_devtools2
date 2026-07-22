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
  -- WezTerm 내장 API 우선 사용 (윈도우에서 exe 파일 권한 거부 없이 확실하게 감지)
  if wezterm.executable_find then
    local found = wezterm.executable_find(cmd)
    if found then
      return found
    end
  end

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

if is_windows then
  -- Windows 에서 WSL2 devtools2 배포판을 기본 셸로 사용해 홈 디렉토리(~)로 바로 진입
  config.default_prog = { 'wsl.exe', '-d', 'devtools2', '--cd', '~' }
end

-- config.window_decorations = "RESIZE" -- 타이틀을 숨기고 창 조절 가능: 나이틀리 버전에서 오류 발생하여 주석처리

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
