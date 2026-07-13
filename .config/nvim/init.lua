-- [Mason PATH 설정]
-- Neovim 시작 시 Mason 도구 경로를 PATH에 추가
--   1. 셸 설정(.bashrc) 없이도 Neovim과 Neovim 내부 터미널(:terminal)에서 즉시 사용 가능
--   2. Neovim이 생성하는 모든 하위 프로세스(LSP, 포맷터 등)가 경로를 상속
local mason_bin = vim.fn.stdpath('data') .. '/mason/bin'
if vim.fn.isdirectory(mason_bin) == 1 then
  vim.env.PATH = mason_bin .. ':' .. vim.env.PATH
end

-- 전역 공통 디렉토리 경로 설정 (환경변수 DEVTOOLS2 값 우선, 없으면 설정 폴더 기준 상대 경로)
-- vim.uv.fs_realpath()로 심볼릭 링크까지 해석된 실제 절대경로로 정규화합니다.
local config_path = vim.fn.stdpath('config')
local raw_devtools2 = os.getenv('DEVTOOLS2') or (config_path:gsub('\\', '/') .. '/../..')
local resolved = vim.uv.fs_realpath(raw_devtools2)
_G.DEVTOOLS2_DIR = (resolved or raw_devtools2):gsub('/$', '')

-- 운영체제 식별 전역 상수 및 변수 설정
_G.OS = {
  WINDOWS = 'Windows',
  MACOS = 'macOS',
  LINUX = 'Linux',
}

if vim.fn.has('win32') == 1 then
  _G.OS_TYPE = _G.OS.WINDOWS
elseif vim.fn.has('macunix') == 1 then
  _G.OS_TYPE = _G.OS.MACOS
else
  _G.OS_TYPE = _G.OS.LINUX
end

-- 전역 사용자 홈 디렉토리
if _G.OS_TYPE == _G.OS.WINDOWS then
  _G.HOME_DIR = os.getenv('USERPROFILE') or os.getenv('HOMEPATH') or '.'
else
  _G.HOME_DIR = os.getenv('HOME') or '.'
end

-- 전역 캐시 및 데이터 디렉토리 (Neovim의 stdpath를 활용하여 OS별 환경변수 자동 적용)
_G.NVIM_DATA_DIR = vim.fn.stdpath('data'):gsub('\\', '/')
_G.NVIM_CACHE_DIR = vim.fn.stdpath('cache'):gsub('\\', '/')
_G.NVIM_STATE_DIR = vim.fn.stdpath('state'):gsub('\\', '/')

-- bootstrap lazy.nvim, LazyVim and your plugins
require('config.lazy')

-- [최초 실행 감지 및 안내 메시지]
-- 최초 실행 시 Mason/Treesitter 설치 중 발생하는 경합 오류는 LazyVim 내부 한계로 완전히 막을 수 없습니다.
-- 따라서 최초 실행임을 감지하여, 오류 대신 명확한 재시작 안내를 사용자에게 표시합니다.
do
  -- jdtls가 설치되어 있으면 이미 한 번 이상 실행된 것으로 판단
  local jdtls_marker = _G.NVIM_DATA_DIR .. '/mason/packages/jdtls'
  local is_first_run = vim.fn.isdirectory(jdtls_marker) == 0

  if is_first_run then
    vim.api.nvim_create_autocmd('User', {
      pattern = 'VeryLazy',
      once = true,
      callback = function()
        -- 약간의 지연으로 lazy.nvim 의 설치 메시지 뒤에 표시되도록 함
        vim.defer_fn(function()
          vim.notify(
            table.concat({
              '🚀 Neovim 최초 실행 감지!',
              '',
              '플러그인 및 언어 도구를 설치하고 있습니다.',
              '설치 중에는 일부 기능이 동작하지 않거나 오류가 표시될 수 있습니다.',
              '',
              '⚡ 설치 완료 후 Neovim을 재시작하면 모든 기능이 정상 동작합니다.',
              '   (우측 하단의 설치 진행 표시가 사라지면 완료)',
            }, '\n'),
            vim.log.levels.WARN,
            {
              title = '⚙️  최초 설치 진행 중 — 완료 후 재시작 필요',
              timeout = 15000, -- 15초간 표시
            }
          )
        end, 1000)
      end,
    })
  end
end

-- 프로젝트별 로컬 설정 파일(.nvim.lua) 허용
vim.o.exrc = true

-- TrueColor 지원 활성화
vim.opt.termguicolors = true

-- 노멀(n), 비주얼(v), 커맨드(c) 모드에서는 block, 인서트(i) 모드에서는 세로선(ver25) 지정을 확실히 명시
vim.opt.guicursor = 'n-v-c:block,i-ci-ve:ver25,r-cr:hor20,o:hor50'

local function file_exists(name)
  local f = io.open(name, 'r')
  if f ~= nil then
    io.close(f)
    return true
  else
    return false
  end
end

local function command_exists(cmd)
  local path = os.getenv('PATH')
  if not path then
    return false
  end
  local sep = package.config:sub(1, 1) -- 플랫폼별 경로 구분자 ('\' or '/')
  for dir in string.gmatch(path, '[^' .. (sep == '\\' and ';' or ':') .. ']+') do
    local full_path = dir .. sep .. cmd
    if file_exists(full_path) then
      return true
    end
  end
  return false
end

-- 터미널 셸 설정 (PowerShell 7 우선 사용)
if _G.OS_TYPE == _G.OS.WINDOWS then
  -- Windows에서만 적용
  if command_exists('pwsh.exe') then
    -- PowerShell 7 사용
    vim.opt.shell = 'pwsh.exe'
    vim.opt.shellcmdflag =
      '-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -Command [Console]::InputEncoding=[Console]::OutputEncoding=[System.Text.Encoding]::UTF8;'
  else
    -- PowerShell 5 사용
    vim.opt.shell = 'powershell.exe'
    vim.opt.shellcmdflag =
      '-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -Command [Console]::InputEncoding=[Console]::OutputEncoding=[System.Text.Encoding]::UTF8;'
  end

  -- 경로 구분자 및 인용 부호 설정
  vim.opt.shellquote = ''
  vim.opt.shellxquote = ''
end
