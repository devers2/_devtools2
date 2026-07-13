return {
  {
    'hrsh7th/nvim-cmp',
    opts = function(_, opts)
      -- 1. 자동완성 팝업 성능 및 스레드 블로킹 타임아웃 튜닝
      opts.performance = vim.tbl_deep_extend('force', opts.performance or {}, {
        debounce = 60,          -- 컴플리션 창이 뜨는 반응 속도 제어 (기본값 완화)
        throttle = 30,          -- 입력 처리 간격 지연으로 렌더링 부하 경감
        fetching_timeout = 200, -- 백그라운드 lsp 응답 대기 타임아웃 (메인 스레드 대기 방지)
      })

      -- 2. 대용량 파일에서 오토컴플릿 무한 인덱싱 방지를 위한 글자 수 제약
      if opts.sources then
        for _, source in ipairs(opts.sources) do
          if source.name == 'nvim_lsp' then
            source.keyword_length = 2 -- LSP 자동완성은 2글자 이상부터 트리거
          elseif source.name == 'buffer' then
            source.keyword_length = 3 -- 버퍼 텍스트 인덱싱은 3글자 이상부터 트리거
          end
        end
      end
    end,
  },
}
