-- [대용량 파일 트리시터 → 정규식(syntax) 폴백]
-- nvim-treesitter가 "main" 브랜치(lazy-lock.json 참고)로 고정되어 있고,
-- LazyVim의 lazyvim/plugins/treesitter.lua는 highlight.disable을
-- "언어 이름 문자열 배열"로만 처리한다 (type(f.disable) == "table" 체크).
-- 함수를 넘기는 구버전(master 브랜치) 방식은 무시되어 크기와 무관하게
-- 트리시터가 항상 켜지므로, FileType 시점에 직접 크기를 검사해
-- vim.treesitter.stop()으로 꺼서 기존 Vim 정규식 syntax 강조로 폴백시킨다.
vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('devtools2_treesitter_large_file_fallback', { clear = true }),
  callback = function(ev)
    local buf = ev.buf
    -- LazyVim의 lazyvim_treesitter FileType 콜백(vim.treesitter.start)이
    -- 같은 이벤트 사이클에서 먼저 끝난 뒤 실행되도록 다음 틱으로 미룸
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end
      local fname = vim.api.nvim_buf_get_name(buf)
      local ok, stat = pcall(vim.uv.fs_stat, fname)
      local oversized = ok and stat and stat.size > _G.get_max_file_size(buf)
      -- 파일 전체 크기는 정상이어도, HTML 등 복합 문법 파일에 <script>/<style> 인라인
      -- 콘텐츠가 유독 많으면(options.lua의 has_oversized_inline_block 참고) 별도로 더
      -- 보수적으로 처리 — 크기 검사를 이미 통과 못했으면 이 추가 검사는 건너뜀(불필요한 비용 방지).
      if not oversized then
        local ok2, is_script_heavy = pcall(_G.has_oversized_inline_block, buf)
        oversized = ok2 and is_script_heavy
      end
      if oversized then
        pcall(vim.treesitter.stop, buf)
      end
    end)
  end,
})

return {
  -- [Treesitter 파서 설정]
  -- Neovim에서 구문 강조 및 코드 분석을 위해 필요한 언어 파서들을 자동으로 설치합니다.
  {
    'nvim-treesitter/nvim-treesitter',
    lazy = false, -- 지연 로딩 완전히 비활성화: 에디터 켜질 때 무조건 즉시 로드하여 첫 버퍼부터 100% 신뢰성 보장
    priority = 1000, -- 가장 높은 우선순위로 먼저 로드
    -- [.properties 파일 하이라이팅 연결]
    -- Neovim 내장 filetype 감지는 *.properties 파일을 'jproperties'로 인식하지만,
    -- nvim-treesitter의 파서 이름은 'properties' 이므로 명시적으로 매핑해줘야
    -- gradle.properties / application.properties 등에서 트리시터 하이라이팅이 실제로 켜집니다.
    init = function()
      vim.treesitter.language.register('properties', 'jproperties')
    end,
    opts = function(_, opts)
      -- 기존 설정이 있으면 유지하면서 필요한 파서들 추가
      opts.ensure_installed = opts.ensure_installed or {}
      local parsers = {
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
        'properties', -- gradle.properties, application.properties, gradle-wrapper.properties 등을 위해 추가
      }
      local existing = {}
      for _, p in ipairs(opts.ensure_installed) do
        existing[p] = true
      end
      for _, p in ipairs(parsers) do
        if not existing[p] then
          table.insert(opts.ensure_installed, p)
          existing[p] = true
        end
      end

      -- 하이라이팅 활성화 (크기 기반 on/off는 위쪽 devtools2_treesitter_large_file_fallback autocmd가 담당)
      opts.highlight = opts.highlight or {}
      opts.highlight.enable = true
      return opts
    end,
  },

  -- [Treesitter Context 설정]
  -- 파일 상단에 현재 커서가 위치한 컨텍스트(클래스, 메서드 명 등)를 고정하여 보여줍니다.
  {
    'nvim-treesitter/nvim-treesitter-context',
    event = 'BufReadPost',
    opts = {
      max_lines = 3, -- 상단에 고정될 최대 줄 수 (너무 많으면 화면을 가리므로 3~5줄 추천)
      min_window_height = 0, -- 설정한 높이 이상의 창에서만 작동
      line_numbers = true,
      multiline_threshold = 20, -- 한 메서드가 너무 길 때 유지할 최대 줄 수
      trim_scope = 'outer', -- max_lines를 넘었을 때 어느 쪽을 숨길지 설정
      mode = 'cursor', -- 'cursor' 또는 'topline' 기준
    },
  },
}
