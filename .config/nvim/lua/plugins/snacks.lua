return {
  {
    'folke/snacks.nvim',
    opts = {
      dashboard = {
        enabled = true,
        preset = {
          keys = {
            { icon = ' ', key = 'f', desc = '스마트 파일 검색 (Smart Picker)', action = ':lua Snacks.picker.smart()' },
            { icon = ' ', key = 'n', desc = '새 파일 생성 (New File)', action = ':ene | startinsert' },
            { icon = ' ', key = 'g', desc = '프로젝트 전체 검색 (Grep)', action = ':lua Snacks.picker.grep()' },
            {
              icon = ' ',
              key = 'r',
              desc = '최근 연 파일 (Recent Files)',
              action = function()
                local oldfiles = vim.v.oldfiles or {}
                if #oldfiles == 0 then
                  Snacks.picker.smart()
                else
                  Snacks.picker.recent()
                end
              end,
            },
            { icon = ' ', key = 'c', desc = '설정 파일 검색 (Config Files)', action = ":lua Snacks.picker.files({ cwd = vim.fn.stdpath('config') })" },
            { icon = ' ', key = 's', desc = '마지막 세션 복원 (Restore Session)', section = 'session' },
            { icon = '󰒲 ', key = 'L', desc = 'Lazy 플러그인 관리자', action = ':Lazy' },
            { icon = ' ', key = 'q', desc = '종료 (Quit)', action = ':qa' },
          },
        },
      },
      picker = {
        -- 전역 기본값: 숨김 파일 비허용 (아래 sources에서 소스별로 개별 override)
        hidden = false,
        -- 이미 열려있는 버퍼 프리뷰 시 외부 플러그인에 의해 모드가 풀리는 현상 수정
        preview = function(ctx)
          if ctx.item.buf and vim.api.nvim_buf_is_loaded(ctx.item.buf) then
            local title = ctx.item.preview_title or ctx.item.title
            if not title then
              local name = vim.api.nvim_buf_get_name(ctx.item.buf)
              local uv = vim.uv or vim.loop
              title = uv.fs_stat(name) and vim.fn.fnamemodify(name, ':t') or name
            end
            ctx.preview:set_title(title)

            -- 원본 버퍼를 직접 셋하면 다른 플러그인의 윈도우 감지 오동작으로 모드가 풀리므로
            -- 텍스트와 파일 타입만 복사하여 스크래치 버퍼를 통해 프리뷰합니다.
            local lines = vim.api.nvim_buf_get_lines(ctx.item.buf, 0, -1, false)
            local ft = vim.bo[ctx.item.buf].filetype
            ctx.preview:reset()
            ctx.preview:set_lines(lines)
            ctx.preview:highlight({ ft = ft, buf = ctx.buf })
          else
            -- 그 외 일반적인 파일 프리뷰는 순정 프리뷰어에 처리를 위임합니다.
            return require('snacks.picker.preview').file(ctx)
          end
        end,
        -- 각 소스별 상세 설정 (개별 명령어가 전역을 무시하는 경우 방지)
        sources = {
          smart = {
            hidden = true,
            current = true, -- 프리뷰 렌더링에 의한 모드 풀림 현상이 해결되었으므로 현재 열린 파일도 정상 표시하도록 true로 변경
            -- layout = { preview = false }, -- (필요시 주석 해제) 스마트 검색 시 우측 미리보기 창 끄기
          }, -- 스마트 검색: <leader><space>, 최근 사용 파일 + 자주 쓰는 파일 + 프로젝트 파일 조합

          files = { hidden = true }, -- 파일 검색: <leader>ff
          grep = { hidden = true }, -- 문자열 검색: <leader>sg
          explorer = { hidden = false, ignored = true }, -- 익스플로러: 숨김 파일 기본 비활성, gitignore 항목은 비활성화 색상(NonText)으로 표시
        },
      },
      image = {
        enabled = false, -- 피커 미리보기에서 이미지 렌더링 비활성화
      },
      explorer = {
        replace_netrw = true,
        trash = false,
        confirm = {
          delete = true,
        },
      },
    },
    -- 단축키 오버라이드
    keys = {
      -- <leader><space>: 스마트 피커 열기
      {
        '<leader><space>',
        function()
          if _G.find_editor_win then
            local editor_win = _G.find_editor_win()
            if editor_win and editor_win ~= vim.api.nvim_get_current_win() then
              vim.api.nvim_set_current_win(editor_win)
            end
          end
          Snacks.picker.smart()
        end,
        desc = 'Smart Picker',
      },
    },
  },
}
