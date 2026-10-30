-- =============================================================================
-- 📦 [Mason.nvim - 외부 바이너리 패키지 통합 관리 센터 (dotfiles 연동)]
-- =============================================================================
-- ⚙️ [모드 전환 토글 플래그 (Toggle Mode Flag)]
-- -----------------------------------------------------------------------------
-- true  : [사전 일괄 자동 설치 모드 (Pre-install)] - 현재 기본값
--         Neovim 첫 기동 시 아래 ensure_installed 목록의 모든 도구를 백그라운드에서 한 번에 설치합니다.
--         • 장점: 어떤 언어 파일을 열든 첫 1초부터 딜레이 없이 즉시 자동완성/진단/포맷팅 완벽 작동.
--         • 단점: 새 환경에서 첫 실행 시 여러 패키지를 한 번에 다운로드하므로 초기 네트워크/시간 소요.
--
-- false : [순수 동적 온디맨드 설치 모드 (On-demand)]
--         사전 일괄 설치를 건너뛰고, 사용자가 실제로 해당 파일(.kt, .py 등)을 처음 열 때만 동적으로 다운로드합니다.
--         • 장점: 초기 기동이 매우 가볍고, 내가 실제로 사용하는 언어 도구만 깔끔하게 설치되어 디스크 절약.
--         • 단점: 새 언어 파일을 처음 열었을 때 다운로드 시간(수초~수십초) 동안 첫 1회 자동완성 대기 발생.
-- -----------------------------------------------------------------------------
local ENABLE_PRE_INSTALL = true

return {
  {
    'mason-org/mason.nvim',
    cmd = 'Mason',
    keys = { { '<leader>cm', '<cmd>Mason<cr>', desc = 'Mason 패키지 관리자 (Mason)' } },
    build = ':MasonUpdate',
    opts = function(_, opts)
      -- 그룹 공유 폴더에 설치 (init.lua 의 _G.NVIM_SHARED_DIR 참고)
      opts.install_root_dir = _G.NVIM_SHARED_DIR .. '/mason'
      opts.ui = opts.ui or {}
      opts.ui.border = 'rounded'
      opts.ui.icons = {
        package_installed = '✓',
        package_pending = '➜',
        package_uninstalled = '✗',
      }

      opts.ensure_installed = opts.ensure_installed or {}

      if ENABLE_PRE_INSTALL then
        local target_tools = {
          -- ===================================================================
          -- ── 1. LSP 서버 (Language Servers) ──
          -- ===================================================================
          'jdtls',                  -- Java (nvim-jdtls와 연동)
          'kotlin-language-server', -- Kotlin (.kt, .kts, build.gradle.kts)
          'basedpyright',           -- Python (초고속 정적 타입 분석 및 정의 이동)
          'ruff',                   -- Python (실시간 린팅 & 진단)
          'yaml-language-server',   -- YAML (Spring Boot application.yml, GitHub Actions 등)
          'vtsls',                  -- TypeScript / JavaScript
          'eslint-lsp',             -- JavaScript / TypeScript ESLint Language Server (vscode-eslint-language-server)

          -- ===================================================================
          -- ── 2. 포맷터 & 린터 (Formatters & Linters) ──
          -- ===================================================================
          'prettier',               -- 웹/문서 (HTML, JS/TS, CSS, JSON, YAML, Markdown)
          'stylua',                 -- Lua (Neovim 설정 파일 포맷팅)
          'ktlint',                 -- Kotlin (.kt, .kts, build.gradle.kts 표준 포맷터)
          'xmlformatter',           -- XML (pom.xml, logback.xml, mapper.xml 등)
          'sql-formatter',          -- SQL (단독 .sql 파일 및 JPA/MyBatis 텍스트 블록)
          'markdownlint-cli2',      -- Markdown (nvim-lint 마크다운 린터)

          -- ===================================================================
          -- ── 3. DAP 디버그 어댑터 (Debug Adapters) ──
          -- ===================================================================
          'debugpy',                -- Python (debugpy-adapter)
          'js-debug-adapter',       -- JavaScript / TypeScript
        }

        -- 🔒 [중복 설치 충돌 원천 방지]
        -- LazyVim 기본 목록에 이미 포함된 도구(stylua, vtsls 등)와의 중복 삽입을 방지하여
        -- Mason의 "Package is already installing" assert 에러를 100% 차단합니다.
        for _, tool in ipairs(target_tools) do
          if not vim.tbl_contains(opts.ensure_installed, tool) then
            table.insert(opts.ensure_installed, tool)
          end
        end
      end
    end,
  },

  -- 🔒 [mason-nvim-dap 자동 설치와 Mason ensure_installed 의 동시 설치 충돌 방지]
  -- 첫 실행에서 Mason 이 ensure_installed 의 디버그 어댑터(js-debug-adapter, debugpy, java-debug-adapter 등)를
  -- 백그라운드로 설치하는 동안 Java 파일이 열리면 nvim-dap 이 로드되고, mason-nvim-dap 의 automatic_installation 이
  -- "아직 설치 안 됨"(설치 중인지는 확인 안 함)으로 보고 같은 패키지 설치를 또 시작해
  --   "Failed to run `config` for nvim-dap ... Package is already installing."
  -- 로 중단됐습니다. 이 오류 화면(Press ENTER)이 떠 있는 동안에는 Mason 설치도 멈춰 첫 설치가 끝나지 않았습니다(실측).
  -- → Mason ensure_installed 로 이미 설치하는 패키지에 해당하는 어댑터는 mason-nvim-dap 자동 설치에서 제외합니다
  --   (목록을 손으로 적지 않고 실행할 때 계산 — ensure_installed 가 바뀌어도 그대로 맞음).
  {
    'jay-babu/mason-nvim-dap.nvim',
    optional = true,
    opts = function(_, opts)
      local ok_map, map = pcall(require, 'mason-nvim-dap.mappings.source')
      local ok_lv, mason_opts = pcall(function()
        return LazyVim.opts('mason.nvim')
      end)
      if not (ok_map and ok_lv and type(map.nvim_dap_to_package) == 'table') then
        return
      end
      local mason_list = (mason_opts or {}).ensure_installed or {}
      local exclude = {}
      for adapter, pkg in pairs(map.nvim_dap_to_package) do
        if vim.tbl_contains(mason_list, pkg) then
          table.insert(exclude, adapter)
        end
      end
      local cur = opts.automatic_installation
      if cur == nil or cur == true then
        opts.automatic_installation = { exclude = exclude }
      elseif type(cur) == 'table' then
        cur.exclude = vim.list_extend(cur.exclude or {}, exclude)
      end
    end,
  },
}
