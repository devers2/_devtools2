return {
  -- [which-key 딜레이 초고속 최적화]
  -- Neovim의 timeoutlen(300~500ms)보다 먼저 팝업창이 무조건 뜨도록
  -- 내부 UI 딜레이를 150ms로 대폭 단축하여 렉 현상을 원천 방지
  {
    'folke/which-key.nvim',
    opts = {
      delay = 150, -- 팝업 표시 대기 시간을 150ms로 지정 (기본값은 500ms)
    },
  },
}
