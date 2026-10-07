-- [고아 프로세스(Orphan) 방지 가드: 터미널 강제 닫힘 시 100% 완전 회수]
pcall(function()
  require('util.orphan_guard').setup()
end)

-- 전역 공통 디렉토리 경로 설정 (환경변수 DEVTOOLS2 값 우선, 없으면 설정 폴더 기준 상대 경로)
-- vim.uv.fs_realpath()로 심볼릭 링크까지 해석된 실제 절대경로로 정규화합니다.
local config_path = vim.fn.stdpath('config')
local raw_devtools2 = os.getenv('DEVTOOLS2') or (config_path .. '/../..')
local resolved = vim.uv.fs_realpath(raw_devtools2)
_G.DEVTOOLS2_DIR = (resolved or raw_devtools2):gsub('/$', '')

-- [그룹 공유 자원 경로] 한 사람이 설치한 플러그인·Mason 도구·Treesitter 파서를 같은 그룹(devers)
-- 사용자 모두가 함께 씁니다(디스크 절약). 공유 대상은 아래 4개뿐이고 나머지 데이터(stdpath('data'):
-- 파일 검색 기록, 스크래치 메모, 플러그인 캐시 등)는 사용자마다 ~/.local/share/nvim 에 따로 저장됩니다.
--   - lazy       : 플러그인        (config/lazy.lua 의 root)
--   - lazy-rocks : 플러그인용 Lua 패키지 (config/lazy.lua 의 rocks.root)
--   - mason      : LSP·포맷터·디버거 (plugins/mason.lua 의 install_root_dir)
--   - site       : Treesitter 파서 (plugins/treesitter.lua 의 install_dir)
-- ⚠️ 예전처럼 stdpath('data') 전체를 공유하면 snacks 등이 개인 기록을 공용 폴더에 써서 사용자끼리 섞이거나
--    쓰기 권한 오류가 납니다(snacks 는 기록 경로가 stdpath('data') 로 고정되어 있어 따로 지정할 수 없음).
_G.NVIM_SHARED_DIR = _G.DEVTOOLS2_DIR .. '/data/nvim'

-- [Mason PATH 설정]
-- Neovim 시작 시 Mason 도구 경로를 PATH에 추가
--   1. 셸 설정(.bashrc) 없이도 Neovim과 Neovim 내부 터미널(:terminal)에서 즉시 사용 가능
--   2. Neovim이 생성하는 모든 하위 프로세스(LSP, 포맷터 등)가 경로를 상속
local mason_bin = _G.NVIM_SHARED_DIR .. '/mason/bin'
if vim.fn.isdirectory(mason_bin) == 1 and not (vim.env.PATH or ''):find(mason_bin, 1, true) then
  vim.env.PATH = mason_bin .. ':' .. (vim.env.PATH or '')
end

-- 운영체제 식별 전역 상수 및 변수 설정
-- ⚠️ 이 설정은 리눅스(WSL2 포함)와 macOS 전용입니다. Windows 네이티브 Neovim 은 지원하지 않으므로
--    Windows 분기(PowerShell 셸, USERPROFILE, .cmd/.exe 경로 등)를 두지 않습니다.
--    WSL 안의 Neovim 은 has('win32') == 0 이라 Linux 로 판별됩니다.
_G.OS = {
  MACOS = 'macOS',
  LINUX = 'Linux',
}

if vim.fn.has('macunix') == 1 then
  _G.OS_TYPE = _G.OS.MACOS
else
  _G.OS_TYPE = _G.OS.LINUX
end

-- 전역 사용자 홈 디렉토리
_G.HOME_DIR = os.getenv('HOME') or '.'

-- 전역 캐시 및 데이터 디렉토리 (사용자별. 그룹 공유 자원은 위의 _G.NVIM_SHARED_DIR)
_G.NVIM_DATA_DIR = vim.fn.stdpath('data')
_G.NVIM_CACHE_DIR = vim.fn.stdpath('cache')
_G.NVIM_STATE_DIR = vim.fn.stdpath('state')

-- bootstrap lazy.nvim, LazyVim and your plugins
require('config.lazy')

-- [통합 번역기 초기화: 메뉴(Code Action, DAP), LSP Progress, 알림 연동]
pcall(function()
  require('util.translator').setup()
end)

-- [최초 실행 감지 및 안내 메시지]
-- 최초 실행 시 Mason/Treesitter 설치 중 발생하는 경합 오류는 LazyVim 내부 한계로 완전히 막을 수 없습니다.
-- 따라서 최초 실행임을 감지하여, 오류 대신 명확한 재시작 안내를 사용자에게 표시합니다.
do
  -- jdtls가 설치되어 있으면 이미 한 번 이상 실행된 것으로 판단
  local jdtls_marker = _G.NVIM_SHARED_DIR .. '/mason/packages/jdtls'
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

-- 터미널 셸 설정: 대화형 로그인 셸(bash/zsh 등)과 무관하게 Neovim 내부 셸 실행은
-- 항상 bash로 고정합니다. 플러그인이 system()/jobstart()로 조립하는 셸 명령은
-- POSIX(bash) 기준으로 작성되는 경우가 많아서, 로그인 셸을 zsh 등으로 바꿔도
-- Neovim 내부 동작(LSP 설치, 포매터 실행, :! 등)이 영향받지 않도록 분리해둡니다.
vim.opt.shell = '/bin/bash'
