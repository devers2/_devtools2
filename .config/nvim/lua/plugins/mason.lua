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
    'williamboman/mason.nvim',
    cmd = 'Mason',
    keys = { { '<leader>cm', '<cmd>Mason<cr>', desc = 'Mason 패키지 관리자 (Mason)' } },
    build = ':MasonUpdate',
    opts = function(_, opts)
      opts.ui = opts.ui or {}
      opts.ui.border = 'rounded'
      opts.ui.icons = {
        package_installed = '✓',
        package_pending = '➜',
        package_uninstalled = '✗',
      }

      opts.ensure_installed = opts.ensure_installed or {}

      if ENABLE_PRE_INSTALL then
        vim.list_extend(opts.ensure_installed, {
          -- ===================================================================
          -- ── 1. LSP 서버 (Language Servers) ──
          -- ===================================================================
          'jdtls',                  -- Java (nvim-jdtls와 연동)
          'kotlin-language-server', -- Kotlin (.kt, .kts, build.gradle.kts)
          'basedpyright',           -- Python (초고속 정적 타입 분석 및 정의 이동)
          'ruff',                   -- Python (실시간 린팅 & 진단)
          'yaml-language-server',   -- YAML (Spring Boot application.yml, GitHub Actions 등)
          'vtsls',                  -- TypeScript / JavaScript

          -- ===================================================================
          -- ── 2. 포맷터 & 린터 (Formatters & Linters) ──
          -- ===================================================================
          'prettier',               -- 웹/문서 (HTML, JS/TS, CSS, JSON, YAML, Markdown)
          'stylua',                 -- Lua (Neovim 설정 파일 포맷팅)
          'ktlint',                 -- Kotlin (.kt, .kts, build.gradle.kts 표준 포맷터)
          'xmlformatter',           -- XML (pom.xml, logback.xml, mapper.xml 등)
          'sql-formatter',          -- SQL (단독 .sql 파일 및 JPA/MyBatis 텍스트 블록)
          'markdownlint-cli2',      -- Markdown (nvim-lint 마크다운 린터)
        })
      end
    end,
  },
}
