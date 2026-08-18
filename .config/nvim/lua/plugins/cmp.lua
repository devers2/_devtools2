-- ⚠️ LazyVim이 기본 completion 엔진을 nvim-cmp → blink.cmp로 전환하면서(실측: lazy-lock.json에
--   nvim-cmp는 없고 blink.cmp만 존재) 기존 hrsh7th/nvim-cmp opts 튜닝이 전혀 로드되지 않는
--   죽은 설정이 되어 있었음. blink.cmp 대상으로 다시 작성함.
--   (blink.cmp는 Rust 매처 기반이라 nvim-cmp식 debounce/throttle 옵션은 없음 —
--   대신 소스별 최소 트리거 글자 수(min_keyword_length)만 이식)
return {
  {
    'saghen/blink.cmp',
    opts = function(_, opts)
      opts.sources = opts.sources or {}
      opts.sources.providers = opts.sources.providers or {}
      opts.sources.providers.lsp = vim.tbl_deep_extend('force', opts.sources.providers.lsp or {}, { min_keyword_length = 2 })
      opts.sources.providers.buffer = vim.tbl_deep_extend('force', opts.sources.providers.buffer or {}, { min_keyword_length = 3 })
      return opts
    end,
  },
}
