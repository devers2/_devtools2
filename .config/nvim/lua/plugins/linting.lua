return {
  'mfussenegger/nvim-lint',
  opts = {
    -- 린터별 세부 설정 커스터마이징
    linters = {
      ['markdownlint-cli2'] = {
        -- markdownlint 규칙 중 MD013(줄 길이 제한)을 120자로 변경
        args = { '--config', '{"MD013": { "line_length": 120 }}', '--' },
      },
    },
    -- 마크다운 파일에서 markdownlint-cli2를 사용하도록 지정
    linters_by_ft = {
      markdown = { 'markdownlint-cli2' },
    },
  },
}
