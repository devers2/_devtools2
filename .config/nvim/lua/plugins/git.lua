return {
  -- VSCode 수준의 강력한 Git Diff 화면을 제공하는 플러그인
  {
    'sindrets/diffview.nvim',
    cmd = {
      'DiffviewOpen',
      'DiffviewClose',
      'DiffviewToggleFiles',
      'DiffviewFocusFiles',
      'DiffviewFileHistory',
      'DiffviewLog',
      'DiffviewRefresh',
    },
    keys = {
      { '<leader>gq', '<cmd>DiffviewOpen<cr>', desc = 'Git Diffview 열기' },
      { '<leader>gQ', '<cmd>DiffviewClose<cr>', desc = 'Git Diffview 닫기' },
      {
        '<leader>gu',
        function()
          local dir = vim.fn.expand('%:p:h')
          if dir == '' or vim.fn.isdirectory(dir) ~= 1 then
            dir = vim.fn.getcwd()
          end

          -- WSL2 환경 감지
          local is_wsl = vim.fn.has('wsl') == 1 or vim.fn.filereadable('/proc/sys/fs/binfmt_misc/WSLInterop') == 1
          if is_wsl and vim.fn.executable('powershell.exe') == 1 then
            local win_path = vim.fn.system('wslpath -w ' .. vim.fn.shellescape(dir)):gsub('%s+', '')
            vim.fn.jobstart({
              'powershell.exe',
              '-NoProfile',
              '-Command',
              'Start-Process gittyup -ArgumentList @("' .. win_path .. '") -ErrorAction SilentlyContinue',
            }, { detach = true })
            vim.notify('Gittyup 실행: ' .. dir, vim.log.levels.INFO)
          else
            if vim.fn.executable('gittyup') == 1 then
              vim.fn.jobstart({ 'gittyup', dir }, { detach = true })
              vim.notify('Gittyup 실행: ' .. dir, vim.log.levels.INFO)
            else
              vim.notify('gittyup 실행 파일을 찾을 수 없습니다.', vim.log.levels.ERROR)
            end
          end
        end,
        desc = 'Gittyup GUI 열기 (Open Gittyup)',
      },
    },
  },

  -- Git 3-Way 병합 충돌 시각화 및 원클릭 해결 플러그인 (VSCode/IntelliJ 스타일)
  -- co: 현재(Ours) 선택 | ct: 들어오는 변경(Theirs) 선택 | cb: 양쪽(Both) 유지 | c0: 모두 삭제
  -- [x: 이전 충돌로 이동 | ]x: 다음 충돌로 이동
  {
    'akinsho/git-conflict.nvim',
    event = { 'BufReadPre', 'BufNewFile' },
    opts = {
      default_mappings = true,
      default_commands = true,
      disable_diagnostics = false,
      list_opener = 'copen',
      highlights = {
        incoming = 'DiffAdd',
        current = 'DiffText',
      },
    },
  },
}
