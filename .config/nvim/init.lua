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

-- [심각한 알림 표시 시간 (ms)]
-- 심각한 경고·오류 알림은 기본 알림보다 오래 띄웁니다.
-- 기본 시간(약 3초)으로는 다른 작업 중에 지나가 버려 알림 기록(<leader>n)에서만 보이는 경우가 있었습니다.
-- 알림마다 숫자를 따로 적지 말고 이 값을 쓰면 모두 같은 시간으로 맞춰집니다.
--   vim.notify(msg, vim.log.levels.WARN, { title = '...', timeout = _G.NOTIFY_CRITICAL_TIMEOUT })
-- ⚠️ 심각한 알림에만 사용합니다. 기준: "그대로 두면 기능이 동작하지 않아 사용자가 직접 조치해야 하는가"
--   ● 사용: jdtls 실행 불가·비정상 종료, Gradle 동기화 실패·프로젝트 파일 충돌, JDK 경로 설정 오류, Java 빌드 오류,
--          ESLint 엔진 오류, 플러그인 호환성 가드(플러그인 꺼짐)
--   ● 사용 안 함: 이미 자동으로 처리된 일의 안내(예: jdtls 작업 폴더 자동 분리), 주의 안내(예: VS Code·Zed 동시 열기),
--          진행 상황 안내(예: Java 빌드·디버그 어댑터 지연 — 같은 알림이 결과로 바뀌므로 각자 정한 시간 사용)
_G.NOTIFY_CRITICAL_TIMEOUT = 15000

-- bootstrap lazy.nvim, LazyVim and your plugins
require('config.lazy')

-- [통합 번역기 초기화: 메뉴(Code Action, DAP), LSP Progress, 알림 연동]
pcall(function()
  require('util.translator').setup()
end)

-- [언어 도구 설치 진행 안내 메시지]
-- 최초 실행 시 Mason/Treesitter 설치 중 발생하는 경합 오류는 LazyVim 내부 한계로 완전히 막을 수 없습니다.
-- 따라서 설치가 아직 끝나지 않았음을 감지하여, 오류 대신 명확한 재시작 안내를 사용자에게 표시합니다.
-- ● 판정: Mason 자동 설치 목록(ensure_installed, LazyVim·plugins/mason.lua 병합 결과) 중 아직 설치되지 않은 도구가 있으면 표시.
--   예전에는 jdtls 폴더 하나로 "최초 실행"을 판단했는데, jdtls(약 50MB) 설치가 끝나기 전에 Neovim 을 닫으면
--   Mason 이 설치를 중단("Installation was aborted")하고 다음 실행 때 처음부터 다시 받아, 느린 네트워크에서는
--   jdtls 가 끝내 설치되지 못하고 "최초 실행 감지" 메시지가 매번 반복됐습니다(실측: 6번 연속 중단).
--   또 jdtls 만 끝나면 다른 도구가 남아 있어도 메시지가 사라지는 문제도 있었습니다.
-- ● 그래서 메시지에 "끝날 때까지 닫지 마세요"를 명시하고, 남은 도구가 모두 설치되면 완료 알림을 한 번 띄웁니다.
-- ● 진행 표시: 도구 하나의 설치가 끝날 때마다(성공·실패 모두) 같은 알림을 그 자리에서 갱신합니다
--   (snacks.notifier 는 같은 id 로 다시 보내면 떠 있는 알림을 교체). 설치 중에는 사라지지 않게 띄워 두고
--   (timeout = false, 직접 닫을 수는 있음), 모두 끝나면 같은 알림을 완료 안내로 바꿉니다.
--   실패한 도구는 이름을 알려 주고 다음 실행 때 Mason 이 다시 시도합니다(:Mason 에서 직접 설치도 가능).
do
  local NOTIFY_ID = 'dt2_mason_install_progress'

  vim.api.nvim_create_autocmd('User', {
    pattern = 'VeryLazy',
    once = true,
    callback = function()
      -- 약간의 지연으로 lazy.nvim 의 설치 메시지 뒤에 표시되도록 함
      vim.defer_fn(function()
        local ok, registry = pcall(require, 'mason-registry')
        local ok_opts, mason_opts = pcall(function()
          return LazyVim.opts('mason.nvim')
        end)
        if not (ok and ok_opts) then
          return
        end
        local pending = {}
        for _, name in ipairs((mason_opts or {}).ensure_installed or {}) do
          if registry.has_package(name) and not registry.is_installed(name) then
            pending[name] = true
          end
        end
        local total = vim.tbl_count(pending)
        if total == 0 then
          return
        end
        local done, failed = 0, {}

        local function render()
          local left = vim.tbl_count(pending)
          if left > 0 then
            local lines = {
              ('🚀 언어 도구 설치 중 — 완료 %d / 전체 %d (남음 %d)'):format(
                done + #failed,
                total,
                left
              ),
            }
            if #failed > 0 then
              table.insert(
                lines,
                ('   ⚠️  실패 %d개: %s'):format(#failed, table.concat(failed, ', '))
              )
            end
            vim.list_extend(lines, {
              '',
              '플러그인 및 언어 도구를 설치하고 있습니다.',
              '설치 중에는 일부 기능이 동작하지 않거나 오류가 표시될 수 있습니다.',
              '',
              '⛔ 설치가 끝날 때까지 Neovim 을 닫지 마세요.',
              '   닫으면 설치가 중단되고, 다음 실행 때 처음부터 다시 받습니다.',
              '⚡ 완료 알림이 뜨면 Neovim 을 재시작하세요. 모든 기능이 정상 동작합니다.',
            })
            vim.notify(table.concat(lines, '\n'), vim.log.levels.WARN, {
              id = NOTIFY_ID,
              title = '⚙️  언어 도구 설치 진행 중 — 완료 후 재시작 필요',
              timeout = false,
            })
          elseif #failed == 0 then
            vim.notify(
              ('✅ 언어 도구 %d개 설치가 모두 끝났습니다. Neovim 을 재시작하면 모든 기능이 정상 동작합니다.'):format(
                total
              ),
              vim.log.levels.INFO,
              {
                id = NOTIFY_ID,
                title = '⚙️  언어 도구 설치 완료',
                timeout = _G.NOTIFY_CRITICAL_TIMEOUT,
              }
            )
          else
            vim.notify(
              table.concat({
                ('언어 도구 %d개 중 %d개를 설치하지 못했습니다: %s'):format(
                  total,
                  #failed,
                  table.concat(failed, ', ')
                ),
                '네트워크를 확인한 뒤 Neovim 을 재시작하면 다시 시도합니다. (:Mason 에서 직접 설치할 수도 있음)',
              }, '\n'),
              vim.log.levels.WARN,
              {
                id = NOTIFY_ID,
                title = '⚙️  언어 도구 설치 일부 실패',
                timeout = _G.NOTIFY_CRITICAL_TIMEOUT,
              }
            )
          end
        end

        local function on_finish(success)
          return vim.schedule_wrap(function(pkg)
            if not (pkg and pending[pkg.name]) then
              return
            end
            pending[pkg.name] = nil
            if success then
              done = done + 1
            else
              table.insert(failed, pkg.name)
            end
            render()
          end)
        end

        render()
        pcall(function()
          registry:on('package:install:success', on_finish(true))
          registry:on('package:install:failed', on_finish(false))
        end)
      end, 1000)
    end,
  })
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
