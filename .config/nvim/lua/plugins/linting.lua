return {
  'mfussenegger/nvim-lint',
  opts = {
    -- 린터별 세부 설정 커스터마이징
    linters = {
      ['markdownlint-cli2'] = {
        -- ⚠️ markdownlint-cli2의 --config는 인라인 JSON 문자열을 받지 않고 파일 경로만
        -- 받습니다(공식 문서 확인) — 예전 방식은 존재하지 않는 파일을 여는 셈이라 매번
        -- 조용히 실패했을 가능성이 높습니다. 실제 설정 파일 경로로 교체합니다.
        args = { '--config', _G.DEVTOOLS2_DIR .. '/.config/markdownlint/.markdownlint-cli2.jsonc', '--' },
      },
    },
    -- 마크다운 파일에서 markdownlint-cli2를 사용하도록 지정
    linters_by_ft = {
      markdown = { 'markdownlint-cli2' },
    },
  },
}
