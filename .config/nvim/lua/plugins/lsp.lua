return {
  {
    'neovim/nvim-lspconfig',
    opts = {
      -- 1. 진단(Diagnostics) 비동기 디바운싱 및 실시간 렌더링 최적화
      diagnostics = {
        update_in_insert = false, -- 타이핑 중에는 경고 밑줄 갱신 차단
        severity_sort = true,
      },

      servers = {
        -- [JDTLS] mason-lspconfig의 자동 attach를 비활성화합니다.
        -- JDTLS는 nvim-jdtls 플러그인이 FileType java 이벤트에서 직접 실행합니다.
        -- 이 설정이 없으면 대시보드 등 비-Java 버퍼에서도 JDTLS가 붙어 오류가 발생합니다.
        jdtls = {
          enabled = false,
        },
        -- ltex(맞춤법 검사기) 비활성화
        ltex = {
          enabled = false,
        },
        eslint = {},
        -- TypeScript(vtsls)는 기본 설정을 따르도록 빈 객체로 설정
        vtsls = {},

        -- [Python 최적화] 기본 pyright 비활성화 후 basedpyright + ruff 조합 사용
        pyright = {
          enabled = false,
        },
        basedpyright = {
          settings = {
            basedpyright = {
              analysis = {
                -- 워크스페이스 전체 스캔을 방지하고 현재 열려있는 파일만 분석 (렉 방지 핵심)
                diagnosticMode = "openFilesOnly",
                useLibraryCodeForTypes = true,
                autoSearchPaths = true,
                -- Ruff와 겹치는 중복 진단 규칙 무시하여 CPU 오버헤드 축소
                diagnosticSeverityOverrides = {
                  reportUnusedImport = "none",
                  reportUnusedVariable = "none",
                  reportUnusedClass = "none",
                  reportUnusedFunction = "none",
                },
              },
            },
          },
        },
        ruff = {},
      },

      setup = {
        -- 2. 모든 LSP 서버 공통: 텍스트 변경사항 디바운스 전역 설정
        ['*'] = function(server, opts)
          local lspconfig = require('lspconfig')
          if not lspconfig.util.default_config.flags_customized then
            lspconfig.util.default_config = vim.tbl_deep_extend('force', lspconfig.util.default_config, {
              flags = {
                debounce_text_changes = 150, -- 코드가 바뀐 뒤 150ms 후 lsp 전송
              },
            })
            lspconfig.util.default_config.flags_customized = true
          end
          return false -- false 리턴 시 기존 setup 흐름을 정상 진행시킵니다.
        end,
        eslint = function(_, opts)
          local lspconfig = require('lspconfig')

          -- filetypes: HTML 포함하여 eslint를 실행할 파일 형식 목록
          opts.filetypes = {
            'javascript',
            'javascriptreact',
            'typescript',
            'typescriptreact',
            'html',
            'vue',
          }

          -- root_dir: .git 폴더 기준 탐색, 없으면 현재 작업 디렉토리 사용
          opts.root_dir = function(fname)
            if not fname or type(fname) ~= 'string' then
              return vim.uv.cwd()
            end
            local root = vim.fs.dirname(vim.fs.find('.git', { upward = true, path = fname })[1])
            return root or vim.uv.cwd()
          end

          local config_file = vim.uv.fs_realpath(_G.DEVTOOLS2_DIR .. '/.config/eslint/eslint.config.mjs')
            or (_G.DEVTOOLS2_DIR .. '/.config/eslint/eslint.config.mjs')

          opts.settings = {
            useFlatConfig = true,
            experimental = { useFlatConfig = true },
            workingDirectory = { mode = 'location' },
            -- ESLint LSP의 포맷팅 기능을 끕니다. (conform.nvim + Prettier가 담당)
            -- 중복 포맷팅으로 인한 멈춤과 충돌을 원천 차단합니다.
            format = { enable = false },
            options = {
              overrideConfigFile = config_file,
            },
            eslint = {
              useFlatConfig = true,
              experimental = { useFlatConfig = true },
              workingDirectory = { mode = 'location' },
              format = { enable = false },
              options = {
                overrideConfigFile = config_file,
              },
            },
          }

          -- [핵심 성능 최적화] on_attach: 파일 크기(_G.MAX_FILE_SIZE)에 따라 ESLint LSP를 조건부로 비활성화
          -- _G.MAX_FILE_SIZE 이상의 대용량 파일(예: Jinja2 통합 HTML)에서 실시간 코드 검사가 CPU를 장악하여 에디터가 완전히 멈추는 현상을 방지
          opts.on_attach = function(client, bufnr)
            local fname = vim.api.nvim_buf_get_name(bufnr)
            local ok, stat = pcall(vim.loop.fs_stat, fname)
            if ok and stat and stat.size > _G.get_max_file_size(bufnr) then
              -- 대용량 파일: ESLint LSP 실시간 진단 기능을 조용히 끕니다.
              client.server_capabilities.diagnosticProvider = nil
              vim.notify(
                string.format(
                  '📄 대용량 파일(%.0fKB)이므로 ESLint 실시간 검사를 비활성화합니다.\n수동 린트가 필요하면 <leader>l 을 실행하세요.',
                  stat.size / 1024
                ),
                vim.log.levels.INFO,
                { title = 'ESLint 자동 최적화', timeout = 4000 }
              )
            end
          end

          lspconfig.eslint.setup(opts)
          return true
        end,
      },
    },
  },
}
