return {
  -- [Treesitter 파서 설정]
  -- Neovim에서 구문 강조 및 코드 분석을 위해 필요한 언어 파서들을 자동으로 설치합니다.
  {
    'nvim-treesitter/nvim-treesitter',
    lazy = false, -- 지연 로딩 완전히 비활성화: 에디터 켜질 때 무조건 즉시 로드하여 첫 버퍼부터 100% 신뢰성 보장
    priority = 1000, -- 가장 높은 우선순위로 먼저 로드
    opts = function(_, opts)
      -- 기존 설정이 있으면 유지하면서 필요한 파서들 추가
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, {
        'html',
        'htmldjango',
        'javascript',
        'typescript',
        'tsx',
        'jsx',
        'vue',
        'css',
        'c',
        'cpp',
        'java',
        'kotlin',
        'groovy',
        'lua',
        'markdown',
        'markdown_inline',
        'bash',
        'python',
        'json',
        'yaml',
        'vim',
        'query',
        'regex',
        'xml', -- Java 설정 파일(pom.xml 등)을 위해 추가
      })
      -- 파일이 열릴 때 파서가 없으면 백그라운드가 아닌 동기식(Sync)으로 즉시 설치 시도
      opts.sync_install = true
      -- 파서 자동 설치 활성화
      opts.auto_install = true

      -- 하이라이팅 설정 최적화 및 기존 Vim 내장 정규식 구문 강조와의 충돌 방지
      opts.highlight = opts.highlight or {}
      opts.highlight.enable = true
      opts.highlight.additional_vim_regex_highlighting = false
      opts.highlight.disable = function(lang, buf)
        local ok, stats = pcall(vim.loop.fs_stat, vim.api.nvim_buf_get_name(buf))
        if ok and stats and stats.size > _G.get_max_file_size(buf) then
          return true
        end
      end
    end,
  },

  -- [Treesitter Context 설정]
  -- 파일 상단에 현재 커서가 위치한 컨텍스트(클래스, 메서드 명 등)를 고정하여 보여줍니다.
  {
    'nvim-treesitter/nvim-treesitter-context',
    event = 'BufReadPost',
    opts = {
      enable = true, -- 플러그인 활성화
      max_lines = 3, -- 상단에 고정될 최대 줄 수 (너무 많으면 화면을 가리므로 3~5줄 추천)
      min_window_height = 0, -- 설정한 높이 이상의 창에서만 작동
      line_numbers = true,
      multiline_threshold = 20, -- 한 메서드가 너무 길 때 유지할 최대 줄 수
      trim_scope = 'outer', -- max_lines를 넘었을 때 어느 쪽을 숨길지 설정
      mode = 'cursor', -- 'cursor' 또는 'topline' 기준
    },
  },
}
