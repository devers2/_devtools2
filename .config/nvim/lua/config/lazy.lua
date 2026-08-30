local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
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

require('lazy').setup({
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
