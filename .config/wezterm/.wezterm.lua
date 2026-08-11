-- WezTerm 설정 파일
local wezterm = require('wezterm')
local act = wezterm.action
local config = wezterm.config_builder()

local is_windows = wezterm.target_triple:find('windows') ~= nil
local home_dir = os.getenv('HOME') or os.getenv('USERPROFILE') or os.getenv('HOMEPATH') or '.'

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
config.window_close_confirmation = 'NeverPrompt' -- 창 닫기(X 버튼) 시 확인 팝업 없이 즉시 닫기

if is_windows then
  -- Windows 에서 WSL2 devtools2 배포판을 기본 셸로 사용해 홈 디렉토리(~)로 바로 진입
  config.default_prog = { 'wsl.exe', '-d', 'devtools2', '--cd', '~' }
end

-- config.window_decorations = "RESIZE" -- 타이틀을 숨기고 창 조절 가능: 나이틀리 버전에서 오류 발생하여 주석처리

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
