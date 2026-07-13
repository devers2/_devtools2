return {
  {
    'stevearc/conform.nvim',
    opts = {
      notify_on_error = true,

      formatters_by_ft = {
        -- HTML: Jinja2 템플릿 문법 보존을 위해 로컬 .prettierrc 자동 탐색
        -- (프로젝트에 .prettierrc + prettier-plugin-jinja-template 가 설치된 경우 자동 적용)
        html = { 'prettier_html' },
        htmldjango = { 'prettier_html' },
        -- JS/TS 설정
        javascript = { 'prettier' },
        typescript = { 'prettier' },
        -- Style 설정
        css = { 'prettier' },
        scss = { 'prettier' },
        -- Python 설정
        python = { 'ruff_format' },
      },
      formatters = {
        -- 기존 prettier: 글로벌 설정 강제 적용 (JS/TS/CSS 등)
        prettier = {
          prepend_args = { '--config', _G.DEVTOOLS2_DIR .. '/.config/prettier/.prettierrc.cjs' },
        },
        -- HTML 전용: --config 없이 프로젝트 로컬 .prettierrc 자동 탐색
        -- → 프로젝트에 prettier-plugin-jinja-template 설치 시 {% %} 블록을 깨지 않음
        -- HTML 전용: 프로젝트 로컬에 .prettierrc가 존재하면 로컬 설정을 따르고, 없으면 글로벌 설정을 사용하도록 자동 폴백
        prettier_html = {
          command = 'prettier',
          args = function(self, ctx)
            local config_files = vim.fs.find({
              '.prettierrc',
              '.prettierrc.json',
              '.prettierrc.js',
              '.prettierrc.cjs',
              '.prettierrc.yaml',
              '.prettierrc.yml',
              'prettier.config.js',
              'prettier.config.cjs',
            }, { path = ctx.filename, upward = true })

            if #config_files > 0 then
              -- 프로젝트 로컬 설정 파일이 존재할 경우: --config 없이 자동으로 로컬 설정을 찾아서 사용하도록 유도
              return { '--stdin-filepath', '$FILENAME' }
            else
              -- 로컬 설정 파일이 없을 경우: 글로벌 _devtools2의 .prettierrc.cjs 설정을 사용하도록 강제 지정
              return {
                '--config',
                _G.DEVTOOLS2_DIR .. '/.config/prettier/.prettierrc.cjs',
                '--stdin-filepath',
                '$FILENAME',
              }
            end
          end,
        },
        stylua = {
          prepend_args = { '--config-path', vim.fn.stdpath('config') .. '/stylua.toml' },
        },
        -- Python
        ruff_format = {
          prepend_args = { '--config', _G.DEVTOOLS2_DIR .. '/.config/ruff/ruff.toml' },
        },
      },
    },
  },
}
