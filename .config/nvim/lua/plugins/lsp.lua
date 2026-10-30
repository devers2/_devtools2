return {
  -- [SchemaStore.nvim: Spring Boot, GitHub Actions, Kubernetes 등 YAML/JSON 스키마 자동 매핑]
  {
    'b0o/SchemaStore.nvim',
    lazy = true,
    version = false,
  },

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
        jdtls = {
          enabled = false,
        },
        -- ltex(맞춤법 검사기) 비활성화
        ltex = {
          enabled = false,
        },
        -- TypeScript(vtsls)는 기본 설정을 따르도록 빈 객체로 설정
        vtsls = {},

        -- [Kotlin LSP] 코틀린 파일(.kt, .kts, build.gradle.kts) 자동완성/진단
        kotlin_language_server = {},

        -- [Web: HTML / CSS] VS Code 와 같은 엔진(vscode-langservers-extracted)
        -- 태그·속성·CSS 속성/값 자동완성과 오류 표시. 포맷팅은 conform.nvim + Prettier 가 전담하므로 LSP 포맷팅은 끔.
        html = {
          init_options = { provideFormatter = false },
        },
        cssls = {
          init_options = { provideFormatter = false },
        },
        -- [Web: Emmet] div.box>ul>li*3 같은 축약 입력을 자동완성 목록에서 HTML 로 펼침
        -- (HTML·CSS·JSX/TSX·Vue 등에서 동작, Tailwind·Vue 는 lazyvim.json 의 lang.tailwind / lang.vue 익스트라)
        emmet_language_server = {},

        -- [Web: Tailwind] 실제로 Tailwind 를 쓰는 프로젝트에서만 시작 (lang.tailwind 익스트라의 서버 설정에 덧붙임)
        -- nvim-lspconfig 기본 설정은 Tailwind v4 용 예비 조건으로 '.git' 을 넣어 두어, Tailwind 를 쓰지 않는 git 저장소에서도
        -- HTML·CSS·Vue 파일을 열 때마다 Tailwind LSP(Node 프로세스, 메모리 약 100MB)가 떴습니다(실측: 일반 웹 프로젝트에서도 attach).
        -- → tailwind.config.* 가 있거나, package.json 에 tailwindcss(v4 의 @tailwindcss/vite·postcss·cli 포함)가 있을 때만 시작.
        --   (postcss.config.* 는 Tailwind 없이도 흔히 쓰여 조건에서 제외)
        tailwindcss = {
          root_dir = function(bufnr, on_dir)
            local fname = vim.api.nvim_buf_get_name(bufnr)
            local config = vim.fs.find(
              { 'tailwind.config.js', 'tailwind.config.cjs', 'tailwind.config.mjs', 'tailwind.config.ts' },
              { path = fname, upward = true }
            )[1]
            if config then
              return on_dir(vim.fs.dirname(config))
            end
            for _, pkg in ipairs(vim.fs.find('package.json', { path = fname, upward = true, limit = math.huge })) do
              local ok, lines = pcall(vim.fn.readfile, pkg)
              if ok and table.concat(lines, '\n'):find('tailwindcss', 1, true) then
                return on_dir(vim.fs.dirname(pkg))
              end
            end
            -- 찾지 못하면 on_dir 를 부르지 않아 서버를 시작하지 않음
          end,
        },

        -- [YAML / Spring Boot application.yml 최적화]
        -- SchemaStore.nvim과 연동하여 Spring Boot 설정 키/값 자동완성 및 검증 지원
        yamlls = {
          on_new_config = function(new_config)
            new_config.settings.yaml.schemas = vim.tbl_deep_extend(
              'force',
              new_config.settings.yaml.schemas or {},
              require('schemastore').yaml.schemas()
            )
          end,
          settings = {
            redhat = { telemetry = { enabled = false } }, -- 백그라운드 텔레메트리 차단
            yaml = {
              schemaStore = {
                enable = false, -- 내장 스키마스토어 끄고 SchemaStore.nvim 사용
                url = '',
              },
              schemas = {},
              validate = true,
              -- YAML LSP의 포맷팅 기능을 끕니다 (conform.nvim + Prettier가 전담)
              format = { enable = false },
            },
          },
        },

        -- [JSON 최적화] 포맷팅은 conform.nvim + Prettier가 전담하도록 LSP 포맷팅 비활성화
        jsonls = {
          settings = {
            json = {
              format = { enable = false },
            },
          },
        },

        -- [Python 최적화] 기본 pyright 비활성화 후 basedpyright + ruff 조합 사용
        pyright = {
          enabled = false,
        },
        basedpyright = {
          enabled = true,
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

        -- [ESLint LSP] Mason(eslint-lsp) 자동 연동 및 Neovim 0.12+ 규격화
        eslint = {
          filetypes = {
            'javascript',
            'javascriptreact',
            'typescript',
            'typescriptreact',
            'html',
            'vue',
          },
          -- ⚠️ [Neovim 0.12+ 비동기 root_dir 규격 준수 필수]
          -- Neovim 0.12 내장 LSP 매니저는 root_dir = function(bufnr, on_dir) 형태로 비동기 콜백을 전달합니다.
          -- on_dir(root) 콜백을 반드시 호출해야만 내부 start_config가 실행되어 LSP 서버가 기동됩니다.
          -- 구버전 스타일(function(fname) return path end)로 작성 시 콜백 누락으로 LSP가 영구 미기동되므로
          -- 절대 단순 return 형태로 되돌리지 마세요. (vim.fs.root는 0.12에서 bufnr 정수를 직접 지원)
          root_dir = function(bufnr, on_dir)
            on_dir(vim.fs.root(bufnr, '.git') or vim.uv.cwd())
          end,
          settings = (function()
            local raw_config = _G.DEVTOOLS2_DIR .. '/.config/eslint/eslint.config.mjs'
            local config_file = vim.uv.fs_realpath(raw_config) or raw_config
            local node_path = _G.DEVTOOLS2_DIR .. '/data/.npm-packages/lib/node_modules'
            return {
              workingDirectory = { mode = 'location' },
              nodePath = node_path,
              -- ⚠️ [포맷팅/린팅 역할 분담 및 자동 수정(Auto-fix) 배제 원칙]
              -- 1. 포맷팅(서식 정돈): conform.nvim + Prettier 가 100% 전담하므로 format = false 로 중복/충돌 차단.
              -- 2. 린팅(코드 검사): ESLint 는 순수 "실시간 경고 표시"만 전담하며, 저장 시 강제 자동 수정(Auto-fix)은
              --    의도적으로 적용하지 않습니다. (Thymeleaf/CDATA 템플릿 문법 파손 방지, 의도치 않은 로직 변형 방지,
              --    불필요한 Git diff 오염 방지 목적). 수정이 필요할 때는 해당 라인에서 <leader>ca 로 선택적 적용합니다.
              format = { enable = false },
              options = {
                overrideConfigFile = config_file,
              },
              eslint = {
                workingDirectory = { mode = 'location' },
                nodePath = node_path,
                format = { enable = false },
                options = {
                  overrideConfigFile = config_file,
                },
              },
            }
          end)(),
          -- [핵심 성능 최적화] on_attach: 파일 크기(_G.MAX_FILE_SIZE)에 따라 ESLint LSP를 조건부로 비활성화
          on_attach = function(client, bufnr)
            local fname = vim.api.nvim_buf_get_name(bufnr)
            if fname ~= '' then
              local ok, stat = pcall(vim.uv.fs_stat, fname)
              if ok and stat and stat.size > _G.get_max_file_size(bufnr) then
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
          end,
        },
      },

      -- (예전의 setup['*'] 에서 lspconfig.util.default_config 로 debounce_text_changes = 150 을 넣던 코드는
      --  Neovim 0.11+ 의 기본값과 같아 효과가 없고, 사용 중단된 lspconfig 내부 API 를 건드려 제거했습니다.)
    },
  },
}
