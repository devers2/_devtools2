return {
  {
    'mfussenegger/nvim-dap',
    -- LazyVim 기본 <leader>da 키맵이 덮어씌워지지 않도록 명시적으로 재정의
    keys = {
      {
        '<leader>da',
        function()
          if _G.attach_debug then
            _G.attach_debug()
          else
            vim.notify('attach_debug 함수가 아직 초기화되지 않았습니다.', vim.log.levels.ERROR)
          end
        end,
        desc = 'Attach/Launch Debug (Input Port)',
      },
    },
    opts = function(_, opts)
      local dap = require('dap')

      dap.defaults.fallback = dap.defaults.fallback or {}
      -- 하나의 스레드에서 브레이크 포인트에 걸렸을때 또 다른 스레드가 브레이크 포인트에서 걸렸을때 통과 여부(동시성 테스트가 아니라면 true 권장)
      dap.defaults.fallback.auto_continue_if_many_stopped = true
      -- winfixbuf 관련 버퍼 스위칭 에러(E1513) 방지를 위한 커스텀 switchbuf 로직
      dap.defaults.fallback.switchbuf = function(bufnr, line, column)
        local api = vim.api

        -- 1) 현재 창이 winfixbuf가 아니면 바로 사용
        local cur_win = api.nvim_get_current_win()
        if not vim.wo[cur_win].winfixbuf then
          api.nvim_win_set_buf(cur_win, bufnr)
          pcall(api.nvim_win_set_cursor, cur_win, { line, column - 1 })
          api.nvim_set_current_win(cur_win)
          return true
        end

        -- 2) 현재 창이 winfixbuf로 잠겨있다면, 현재 탭 내에서 잠기지 않은 다른 창 탐색
        for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
          if not vim.wo[win].winfixbuf then
            api.nvim_win_set_buf(win, bufnr)
            pcall(api.nvim_win_set_cursor, win, { line, column - 1 })
            api.nvim_set_current_win(win)
            return true
          end
        end

        -- 3) 모든 창이 잠겨있다면 새 창을 분할해 열고 로드
        vim.cmd('split')
        local new_win = api.nvim_get_current_win()
        api.nvim_win_set_buf(new_win, bufnr)
        pcall(api.nvim_win_set_cursor, new_win, { line, column - 1 })
        return true
      end

      -- Java attach 기본 구성
      dap.configurations.java = {
        {
          type = 'java',
          request = 'attach',
          name = 'Java Attach to 5005',
          hostName = '127.0.0.1',
          port = 5005,
        },
      }

      -- Python FastAPI launch 기본 구성 (수동 실행 시 DAP UI에 표시됨)
      dap.configurations.python = dap.configurations.python or {}
      table.insert(dap.configurations.python, {
        type = 'python',
        request = 'launch',
        name = 'FastAPI 디버깅 실행 (기본: 8095)',
        module = 'uvicorn',
        args = {
          'main:app',
          '--reload',
          '--port',
          '8095',
          '--host',
          '0.0.0.0',
        },
        pythonPath = function()
          return os.getenv('VIRTUAL_ENV') and (os.getenv('VIRTUAL_ENV') .. '/bin/python') or 'python'
        end,
      })


      -- 대신 디버깅 시작 시 nvim-dap-view가 자동으로 열리도록 설정
      dap.listeners.after.event_initialized['dapview_config'] = function()
        require('dap-view').open()
      end
      -- 디버깅 종료 시 nvim-dap-view가 자동으로 닫히도록 설정
      dap.listeners.before.event_terminated['dapview_config'] = function()
        require('dap-view').close()
      end
      dap.listeners.before.event_exited['dapview_config'] = function()
        require('dap-view').close()
      end

      -- [스마트 포트 자동 킬러] dap.run 핵심 함수 래핑
      -- 디버깅이 가동되기 직전(어댑터 작동 전)에 포트를 스캔하여 선점 프로세스를 사전에 제거합니다.
      local orig_run = dap.run
      ---@diagnostic disable-next-line: duplicate-set-field
      dap.run = function(config, _)
        if config and config.request == 'launch' then
          local port = nil
          -- 1) config 자체에 port가 있는 경우
          if config.port then
            port = tonumber(config.port)
          end
          -- 2) FastAPI 런치 설정처럼 args 테이블에 '--port' '8095'가 있는 경우
          if not port and config.args then
            for i, arg in ipairs(config.args) do
              if arg == '--port' and config.args[i + 1] then
                port = tonumber(config.args[i + 1])
                break
              end
            end
          end

          if port then
            if _G.OS_TYPE == _G.OS.WINDOWS then
              -- Windows 환경: netstat -ano를 이용해 포트 점유 PID 검출 및 taskkill
              local cmd = 'netstat -ano'
              local handle = io.popen(cmd)
              if handle then
                local result = handle:read('*a')
                handle:close()

                local pids = {}
                for line in result:gmatch('[^\r\n]+') do
                  local tokens = {}
                  for token in line:gmatch('%S+') do
                    table.insert(tokens, token)
                  end
                  if #tokens >= 5 then
                    local local_addr = tokens[2]
                    local state = tokens[4]
                    local pid = tokens[5]
                    if local_addr:match(':' .. port .. '$') and state == 'LISTENING' and tonumber(pid) then
                      pids[pid] = true
                    end
                  end
                end

                for pid, _ in pairs(pids) do
                  vim.fn.system(string.format('taskkill /F /PID %s', pid))
                  vim.notify(
                    string.format('기존 포트 %d의 Windows 프로세스(%s)를 종료했습니다.', port, pid),
                    vim.log.levels.INFO
                  )
                end
                if next(pids) then
                  vim.cmd('sleep 100m')
                end
              end
            else
              -- macOS & Linux 환경
              local cmd = string.format('lsof -t -i:%d', port)
              local pids = vim.fn.system(cmd)
              if pids and pids ~= '' then
                local clean_pids = pids:gsub('\n', ' ')
                vim.fn.system(string.format('kill -9 %s', clean_pids))
                vim.cmd('sleep 100m')
                vim.notify(
                  string.format(
                    '기존 포트 %d의 프로세스(%s)를 종료하고 디버깅을 시작합니다.',
                    port,
                    clean_pids
                  ),
                  vim.log.levels.INFO
                )
              end
            end
          end
        end
        return orig_run(config, opts)
      end


      return opts
    end,
  },

  -- ─────────────────────────────────────────────────────────────────────
  -- nvim-dap-ui: LazyVim extras.dap.core 에 포함된 플러그인을 비활성화
  -- (nvim-dap-view 가 동일한 역할을 대체)
  -- ─────────────────────────────────────────────────────────────────────
  { 'rcarriga/nvim-dap-ui', enabled = false },

  -- ─────────────────────────────────────────────────────────────────────
  -- nvim-dap-view: 클릭 가능한 디버그 컨트롤바 + 모던 DAP UI
  -- <leader>dv  →  nvim-dap-view 토글 열기/닫기
  -- ─────────────────────────────────────────────────────────────────────
  {
    'igorlfs/nvim-dap-view',
    dependencies = { 'mfussenegger/nvim-dap' },
    keys = {
      {
        '<leader>dv',
        function()
          require('dap-view').toggle()
        end,
        desc = 'DAP View',
      },
    },
    opts = {
      winbar = {
        -- 보여줄 섹션 탭 순서
        sections = { 'watches', 'scopes', 'exceptions', 'breakpoints', 'threads', 'repl', 'console' },
        default_section = 'scopes',
        -- 클릭 가능한 디버그 컨트롤바 활성화
        -- (▶ Continue  ↷ Step Over  ↴ Step Into  ↱ Step Out  ⏹ Stop 등)
        controls = {
          enabled = true,
          position = 'right',
        },
      },
      windows = {
        -- 0.25 = 화면의 25% 높이로 하단에 열기
        size = 0.25,
        position = 'below',
      },
    },
  },
}
