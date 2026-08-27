return {
  {
    'stevearc/conform.nvim',
    -- [프로젝트별 conform 로그 파일 분리]
    -- conform.nvim의 기본값(~/.local/state/nvim/conform.log)은 모든 프로젝트의 로그가 하나의 파일에 누적되어,
    -- 다른 프로젝트에서 :ConformInfo 를 열었을 때 이전 프로젝트의 오류/로그가 뒤섞여 보이는 문제가 있습니다.
    -- 이를 해결하기 위해 현재 열려있는 파일의 프로젝트 루트(Git 또는 프로젝트 디렉터리명)를 기준으로
    -- ~/.local/state/nvim/conform/<프로젝트명>.log 에 프로젝트별로 독립 저장합니다.
    -- pcall 안전 가드로 감싸 플러그인 버전 변경 시에도 100% 안전하게 기본 로거로 폴백됩니다.
    init = function()
      local ok, log = pcall(require, 'conform.log')
      if ok and type(log.get_logfile) == 'function' and type(log.set_handler) == 'function' then
        -- 1. 현재 버퍼의 프로젝트 루트 디렉터리명을 기준으로 로그 파일 경로 계산
        log.get_logfile = function()
          local buf = vim.api.nvim_get_current_buf()
          local fname = vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) or ''
          local root = (fname ~= '' and vim.fs.root(fname, { '.git', 'mvnw', 'gradlew', 'package.json', 'pyproject.toml' }))
            or vim.fs.root(0, { '.git' })
            or vim.fn.getcwd()
          local proj_name = vim.fs.basename(root)
          local log_dir = vim.fn.stdpath('state') .. '/conform'
          pcall(vim.fn.mkdir, log_dir, 'p')
          return string.format('%s/%s.log', log_dir, proj_name)
        end

        -- 2. 로그가 발생할 때마다 해당 프로젝트의 로그 파일로 실시간 기록
        log.set_handler(function(line)
          local filepath = log.get_logfile()
          local parent = vim.fs.dirname(filepath)
          pcall(vim.fn.mkdir, parent, 'p')
          local f = io.open(filepath, 'a+')
          if f then
            f:write(line .. '\n')
            f:close()
          end
        end)
      end
    end,

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
            local has_local_config = false
            if ctx.filename and ctx.filename ~= '' then
              has_local_config = vim.fs.root(ctx.filename, {
                '.prettierrc',
                '.prettierrc.json',
                '.prettierrc.js',
                '.prettierrc.cjs',
                '.prettierrc.yaml',
                '.prettierrc.yml',
                'prettier.config.js',
                'prettier.config.cjs',
              }) ~= nil
            end

            if has_local_config then
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
          prepend_args = { '--config-path', vim.fs.joinpath(vim.fn.stdpath('config'), 'stylua.toml') },
        },
        -- Python
        ruff_format = {
          prepend_args = { '--config', _G.DEVTOOLS2_DIR .. '/.config/ruff/ruff.toml' },
        },
      },
    },
  },
}
