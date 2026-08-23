return {
  {
    -- im-select.nvim: 입력기(IME) 상태를 관리하는 플러그인입니다.
    -- 목적: Insert → Normal 모드 전환 시 자동으로 입력기를 영문으로 변경하여
    --       한글 입력 상태에서 단축키가 작동하지 않는 문제를 방지합니다.
    -- 정책: Normal 모드 진입 및 Insert 복귀 시 항상 영문으로 시작합니다.
    --       (Windows/WSL 에서는 AutoHotkey 가 동일한 정책을 0ms 로 처리)
    'keaising/im-select.nvim',
    event = 'VeryLazy',

    -- 플러그인 로드 조건: 각 OS에서 필요한 IME 제어 바이너리가 있을 때만 활성화
    cond = function()
      if _G.OS_TYPE == _G.OS.WINDOWS or vim.fn.has('wsl') == 1 then
        -- Windows / WSL: Windows 호스트의 AutoHotkey 가 0ms 무지연으로 IME 전환을 전담하므로 비활성화
        return false
      elseif _G.OS_TYPE == _G.OS.MACOS then
        -- macOS: macism 또는 im-select 도구가 있을 때 활성화
        return vim.fn.executable('macism') == 1
          or vim.fn.executable('im-select') == 1
      else
        -- Linux 네이티브 (Ubuntu/Fedora/Arch 등): fcitx5, ibus 입력기 도구가 있을 때 활성화
        return vim.fn.executable('fcitx5-remote') == 1
          or vim.fn.executable('ibus') == 1
      end
    end,

    config = function()
      local default_command = 'fcitx5-remote'
      local default_im_select = 'keyboard-us'

      if vim.fn.executable('fcitx5-remote') == 1 then
        -- Linux (Fcitx5) 설정
        default_command = 'fcitx5-remote'
        default_im_select = 'keyboard-us'
      elseif vim.fn.executable('ibus') == 1 then
        -- Linux (IBus) 설정
        default_command = 'ibus'
        default_im_select = 'xkb:us::eng'
      elseif _G.OS_TYPE == _G.OS.MACOS then
        -- macOS 설정
        default_command = vim.fn.executable('macism') == 1 and 'macism' or 'im-select'
        default_im_select = 'com.apple.keylayout.ABC'
      end

      require('im_select').setup({
        default_im_select = default_im_select,
        default_command = default_command,
        -- Normal 모드 및 커맨드라인 이탈 시 영문으로 전환
        set_default_events = { 'InsertLeave', 'CmdlineLeave' },
        -- Insert 재진입 시 이전 IME 복원 안 함 → 항상 영문으로 시작
        set_previous_events = {},
      })
    end,
  },
}
