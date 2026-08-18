return {
  'mfussenegger/nvim-lint',
  opts = function(_, opts)
    opts.linters = opts.linters or {}
    opts.linters_by_ft = opts.linters_by_ft or {}
    opts.linters['markdownlint-cli2'] = {
      args = { '--config', _G.DEVTOOLS2_DIR .. '/.config/markdownlint/.markdownlint-cli2.jsonc', '--' },
    }
    opts.linters_by_ft.markdown = { 'markdownlint-cli2' }
    return opts
  end,
}
