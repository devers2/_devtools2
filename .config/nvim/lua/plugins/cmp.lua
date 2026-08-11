-- ⚠️ LazyVim이 기본 completion 엔진을 nvim-cmp → blink.cmp로 전환하면서(실측: lazy-lock.json에
--   nvim-cmp는 없고 blink.cmp만 존재) 기존 hrsh7th/nvim-cmp opts 튜닝이 전혀 로드되지 않는
--   죽은 설정이 되어 있었음. blink.cmp 대상으로 다시 작성함.
--   (blink.cmp는 Rust 매처 기반이라 nvim-cmp식 debounce/throttle 옵션은 없음 —
--   대신 소스별 최소 트리거 글자 수(min_keyword_length)만 이식)
return {
  {
    'saghen/blink.cmp',
    opts = {
      sources = {
        providers = {
          lsp = { min_keyword_length = 2 }, -- LSP 자동완성은 2글자 이상부터 트리거
          buffer = { min_keyword_length = 3 }, -- 버퍼 텍스트 인덱싱은 3글자 이상부터 트리거
        },
      },
    },
  },
}
