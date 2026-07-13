return {
  {
    -- im-select.nvim: 입력기(IME) 상태를 관리하는 플러그인입니다.
    -- 목적: Normal 모드로 전환할 때 자동으로 입력기를 영문으로 변경하여,
    -- 한글 입력 상태에서 단축키가 작동하지 않는 문제를 방지합니다.
    'keaising/im-select.nvim',

    -- 플러그인 로드 조건 설정
    cond = function()
      if _G.OS_TYPE == _G.OS.WINDOWS then
        -- Windows: im-select.exe가 설치되어 있어야 함
        return vim.fn.executable('im-select.exe') == 1
      elseif _G.OS_TYPE == _G.OS.MACOS then
        -- macOS: im-select가 설치되어 있어야 함
        return vim.fn.executable('im-select') == 1
      else
        -- Linux: fcitx5, ibus 등 지원되는 입력기 도구가 있는지 확인
        return vim.fn.executable('fcitx5-remote') == 1
          or vim.fn.executable('ibus') == 1
          or vim.fn.executable('im-select') == 1
      end
    end,

    config = function()
      -- OS 및 설치된 도구에 따라 기본 명령어와 입력기 값 설정
      local default_command = 'im-select'
      local default_im_select = 'keyboard-us'

      if _G.OS_TYPE == _G.OS.WINDOWS then
        -- Windows 설정
        default_command = 'im-select.exe'
        default_im_select = '1033'
      elseif vim.fn.executable('fcitx5-remote') == 1 then
        -- Linux (Fcitx5) 설정
        default_command = 'fcitx5-remote'
        default_im_select = 'keyboard-us'
      elseif vim.fn.executable('ibus') == 1 then
        -- Linux (Ibus) 설정
        default_command = 'ibus'
        default_im_select = 'xkb:us::eng'
      elseif _G.OS_TYPE == _G.OS.MACOS then
        -- macOS 설정
        default_command = 'im-select'
        default_im_select = 'com.apple.keylayout.US'
      end

      require('im_select').setup({
        -- Normal 모드 진입 시 자동 영어 전환 활성화
        auto_select = true,
        -- Insert 모드로 돌아올 때 이전에 사용하던 입력기(예: 한글) 복원
        remember_previous = true,
        -- 위에서 판별한 기본값 적용
        default_im_select = default_im_select,
        default_command = default_command,
      })
    end,
  },
}
