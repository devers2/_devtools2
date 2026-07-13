return {
  {
    'folke/snacks.nvim',
    opts = {
      picker = {
        -- 전역 설정: 모든 피커(파일, 그렙, 익스플로러 등)에서 숨김 파일 허용
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
          explorer = { hidden = false }, -- 익스플로러: 숨김 파일 기본 비활성
          -- buffers = { hidden = true }, -- 열려있는 버퍼 목록
          -- recent = { hidden = true }, -- 최근 열었던 파일
          -- git_files = { hidden = true }, -- Git 관리 대상 파일
          -- lsp_symbols = { hidden = true }, -- LSP 심볼 검색
          -- help = { hidden = true }, -- 도움말 검색
          -- colorschemes = { hidden = true }, -- 색상 테마 변경
          -- commands = { hidden = true }, -- 명령어 실행
          -- keymaps = { hidden = true }, -- 단축키 검색
        },
        -- ※ 검색 제외 설정: 프로젝트의 .gitignore, .ignore 파일의 제외 패턴을 따른다.
      },
      image = {
        enabled = false, -- 피커 미리보기에서 이미지 렌더링 비활성화 (❗true 설정 시 입력 모드에서 일반 모드로 강제 전환되는 문제가 있음)
      },
      -- 익스플로러 행동 관련 설정 (시각적 옵션은 위 picker.sources.explorer에서 담당)
      explorer = {
        replace_netrw = true, -- netrw 대체 여부
        -- 휴지통 사용 안 함
        trash = false,
        confirm = {
          delete = true, -- 삭제 시 확인 창 강제 활성화
        },
      },
    },
    -- 단축키 오버라이드
    keys = {
      -- <leader><space>: 스마트 피커 열기
      -- [Fix] 피커를 열기 전에 먼저 유효한 에디터 창으로 포커스를 이동합니다.
      -- Snacks 피커는 열릴 때의 "현재 창"을 복귀 창으로 기억합니다.
      -- Explorer가 포커스된 상태에서 피커를 열면 파일 선택 후 Explorer에 파일이 열리는 문제가 발생하므로,
      -- 피커 열기 전에 항상 에디터 창을 복귀 창으로 설정합니다.
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
