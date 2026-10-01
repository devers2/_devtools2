return {
  -- Kanagawa 테마 플러그인 설치
  {
    'rebelot/kanagawa.nvim',
    name = 'kanagawa',
    lazy = false, -- 에디터 시작 시 바로 로드되도록 설정
    priority = 1000, -- 다른 플러그인보다 먼저 로드
    -- compile = true 는 컴파일 캐시(stdpath('state')/kanagawa/*_compiled.lua)가 있으면 설정을 보지 않고
    -- 캐시만 읽습니다. 플러그인 업데이트 시 캐시를 다시 만들도록 build 훅을 겁니다.
    build = function()
      pcall(function()
        require('kanagawa').compile()
      end)
    end,
    config = function()
      require('kanagawa').setup({
        compile = true, -- 성능 최적화를 위해 컴파일 사용
        undercurl = true, -- 언더컬(물결선) 활성화
        commentStyle = { italic = true },
        functionStyle = {},
        keywordStyle = { italic = true },
        statementStyle = { bold = true },
        typeStyle = {},
        transparent = true, -- 배경 투명화 여부
        dimInactive = true, -- 포커스되지 않은 창 어둡게 하기
        terminalColors = true, -- 터미널 색상 적용
        colors = {
          theme = {
            all = {
              ui = {
                bg_gutter = 'none', -- 라인 넘버 부분 배경 제거
              },
            },
          },
        },
        theme = 'wave', -- 기본 테마 선택: "wave", "dragon", "lotus" 중 선택 가능
        overrides = function(colors)
          local theme = colors.theme
          return {
            WinSeparator = { fg = theme.ui.fg_dim, bold = true },
          }
        end,
      })

      -- 이 설정 파일이 컴파일 캐시보다 새로우면(설정 수정·git pull) 캐시를 다시 만듭니다.
      -- (없으면 overrides/transparent 등을 바꿔도 :KanagawaCompile 을 직접 실행하기 전까지 반영되지 않음)
      local cache = vim.uv.fs_stat(vim.fn.stdpath('state') .. '/kanagawa/wave_compiled.lua')
      local src = vim.uv.fs_stat(debug.getinfo(1, 'S').source:sub(2))
      local function newer(a, b)
        return a.mtime.sec > b.mtime.sec
          or (a.mtime.sec == b.mtime.sec and a.mtime.nsec > b.mtime.nsec)
      end
      if cache and src and newer(src, cache) then
        require('kanagawa').compile()
      end

      -- 테마 적용 명령
      vim.cmd.colorscheme('kanagawa')

      -- 기본 경계선 모양 설정 (두껍게)
      -- vim.opt.fillchars = {
      --   vert = '┃',
      --   horiz = '━',
      -- }
    end,
  },
}
