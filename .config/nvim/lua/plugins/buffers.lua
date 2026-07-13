-- ============================================================
-- [bufferline.nvim 탭 클릭 창 관리 Fix]
--
-- 기본 동작: left_mouse_command = "buffer %d"
--   → 현재 포커스된 창에서 실행됨
--   → Explorer 창이 포커스된 상태에서 탭 클릭 시 Explorer에 파일이 열림
--
-- 수정 동작: left_mouse_command = Lua 함수
--   → find_editor_win() 으로 유효한 에디터 창을 먼저 찾아 포커스
--   → 그 다음 버퍼 전환 실행
-- ============================================================
return {
  {
    'akinsho/bufferline.nvim',
    opts = function(_, opts)
      opts.options = opts.options or {}

      -- 마우스 탭 클릭 시 항상 유효한 에디터 창에서 버퍼 전환
      opts.options.left_mouse_command = function(n)
        -- [1] 유효한 에디터 창으로 먼저 포커스 이동
        if _G.find_editor_win then
          local target = _G.find_editor_win()
          if target and target ~= vim.api.nvim_get_current_win() then
            vim.api.nvim_set_current_win(target)
          end
        end
        -- [2] 해당 창에서 버퍼 전환
        vim.cmd('buffer ' .. n)
      end

      -- 마우스 우클릭(중간 버튼)도 동일하게 처리
      opts.options.middle_mouse_command = nil -- 중간 버튼 클릭은 기본 비활성 유지

      return opts
    end,
  },
}
