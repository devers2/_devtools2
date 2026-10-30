-- 플러그인은 그룹 공유 폴더(_G.NVIM_SHARED_DIR, init.lua 참고)에 설치합니다.
local lazy_root = _G.NVIM_SHARED_DIR .. '/lazy'
local lazypath = lazy_root .. '/lazy.nvim'
if not vim.uv.fs_stat(lazypath) then
  local lazyrepo = 'https://github.com/folke/lazy.nvim.git'
  local out = vim.fn.system({ 'git', 'clone', '--filter=blob:none', '--branch=stable', lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { 'Failed to clone lazy.nvim:\n', 'ErrorMsg' },
      { out, 'WarningMsg' },
      { '\nPress any key to exit...' },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

-- [LazyVim 도 lazy-lock.json 의 고정 커밋으로 먼저 받기 — 새 PC 에서 플러그인 버전이 고정 커밋과 달라지는 문제 방지]
-- 새 PC 에서 처음 켜면 lazy.nvim 은 설치를 두 번에 나눠 합니다.
--   1차: 이 설정(plugins/)에 적힌 플러그인 + LazyVim 본체 설치 (고정 커밋대로)
--        → 끝나면 lazy-lock.json 을 다시 쓰는데, 이때 아직 설치하지 않은 플러그인의 고정 커밋을 목록에서 지움
--   2차: LazyVim 본체가 생긴 뒤에야 보이는 "LazyVim 이 정의한 플러그인"(gitsigns, mini.*, mason-lspconfig 등)을
--        설치하는데, 고정 커밋이 이미 지워져 최신 버전으로 설치됨 (실측: 58개 중 8개가 고정 커밋과 다름,
--        reflog 에 clone 만 있고 checkout 없음)
-- LazyVim 을 lazy.nvim 처럼 미리 받아 두면 1차에서 LazyVim 의 플러그인 목록까지 모두 보여 한 번에 고정 커밋대로
-- 설치됩니다. LazyVim 폴더가 없을 때(새 PC)만 동작하므로 이미 설치된 PC 에는 영향이 없습니다.
-- 받기에 실패해도 중단하지 않습니다(lazy.nvim 이 평소처럼 LazyVim 을 받음 — 이 경우 예전처럼 일부가 최신으로 설치될 뿐).
local lazyvim_path = lazy_root .. '/LazyVim'
if not vim.uv.fs_stat(lazyvim_path) then
  local lock_commit
  local lf = io.open(vim.fn.stdpath('config') .. '/lazy-lock.json', 'r')
  if lf then
    local ok, lock = pcall(vim.json.decode, lf:read('*a') or '')
    lf:close()
    if ok and type(lock) == 'table' and type(lock.LazyVim) == 'table' then
      lock_commit = lock.LazyVim.commit
    end
  end
  vim.fn.system({ 'git', 'clone', '--filter=blob:none', 'https://github.com/LazyVim/LazyVim.git', lazyvim_path })
  if vim.v.shell_error == 0 and lock_commit then
    vim.fn.system({ 'git', '-C', lazyvim_path, 'checkout', '--quiet', lock_commit })
  end
end

-- [그룹 공유 플러그인의 git "소유자 불일치" 허용]
-- 공유 플러그인 폴더는 처음 설치한 사람 소유라서, 같은 그룹의 다른 사용자가 :Lazy update 등으로
-- git 을 실행하면 "detected dubious ownership" 으로 거부됩니다. Neovim 이 띄우는 git 프로세스에만
-- 공유 플러그인 폴더를 safe.directory 로 넘깁니다(GIT_CONFIG_* 는 git 이 신뢰하는 "command" 범위 설정).
-- 전역 ~/.gitconfig 를 건드리지 않고, 다른 저장소의 소유자 검사는 그대로 유지됩니다.
do
  local n = tonumber(vim.env.GIT_CONFIG_COUNT or '0') or 0
  for name, kind in vim.fs.dir(lazy_root) do
    if kind == 'directory' then
      vim.env['GIT_CONFIG_KEY_' .. n] = 'safe.directory'
      vim.env['GIT_CONFIG_VALUE_' .. n] = lazy_root .. '/' .. name
      n = n + 1
    end
  end
  vim.env.GIT_CONFIG_COUNT = tostring(n)
end

require('lazy').setup({
  root = lazy_root,
  rocks = { root = _G.NVIM_SHARED_DIR .. '/lazy-rocks' },
  spec = {
    -- add LazyVim and import its plugins
    { 'LazyVim/LazyVim', import = 'lazyvim.plugins' },
    -- import/override with your plugins
    { import = 'plugins' },
  },
  defaults = {
    -- By default, only LazyVim plugins will be lazy-loaded. Your custom plugins will load during startup.
    -- If you know what you're doing, you can set this to `true` to have all your custom plugins lazy-loaded by default.
    lazy = false,
    -- It's recommended to leave version=false for now, since a lot the plugin that support versioning,
    -- have outdated releases, which may break your Neovim install.
    version = false, -- always use the latest git commit
    -- version = "*", -- try installing the latest stable version for plugins that support semver
  },
  install = { colorscheme = { 'kanagawa', 'tokyonight', 'habamax' } },
  checker = {
    enabled = true, -- check for plugin updates periodically
    notify = false, -- 순정 영문 단순 알림 대신 아래 커스텀 한글 안내 알림 사용
  }, -- automatically check for plugin updates
  performance = {
    rtp = {
      -- disable some rtp plugins
      disabled_plugins = {
        'gzip',
        -- "matchit",
        -- "matchparen",
        -- "netrwPlugin",
        'tarPlugin',
        'tohtml',
        'tutor',
        'zipPlugin',
      },
    },
  },
})

-- =============================================================================
-- [플러그인 업데이트 감지 알림]
-- 백그라운드에서 새 버전이 감지되면 알림창을 띄우고,
-- :Lazy update 와 :Lazy sync 의 역할을 설명하여 사용자가 선택할 수 있도록 안내합니다.
-- =============================================================================
vim.api.nvim_create_autocmd('User', {
  pattern = 'LazyCheck',
  callback = function()
    local ok, checker = pcall(require, 'lazy.manage.checker')
    if ok and checker.updated and #checker.updated > 0 then
      local count = #checker.updated
      vim.schedule(function()
        vim.notify(
          table.concat({
            string.format('🔔 %d개의 플러그인 업데이트가 있습니다!', count),
            '',
            '• :Lazy update  (또는 Lazy 창에서 U)',
            '  ➜ 기존 플러그인을 최신 버전으로 안전하게 갱신 (권장)',
            '',
            '• :Lazy sync    (또는 Lazy 창에서 S)',
            '  ➜ 플러그인 갱신 + 새 플러그인 설치 및 미사용 정리',
          }, '\n'),
          vim.log.levels.INFO,
          {
            title = '📦 Neovim 플러그인 업데이트 안내',
            timeout = 10000,
          }
        )
      end)
    end
  end,
})
