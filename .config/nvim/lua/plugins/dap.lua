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

      -- [DAP 표준 프로세스 ID(PID) 추적 및 종료 관리자]
      -- DAP 프로토콜 표준(event_process) 및 java-debug(event_processId) 이벤트를 통해
      -- 디버거가 실행한 실제 OS 프로세스 PID(systemProcessId)를 실시간으로 추적합니다.
      -- 특정 언어나 MAIN_CLASS 변수 유무와 무관하게, 세션 종료 시 정확한 PID를 직접 강제 종료합니다.
      local active_debug_pids = {}

      dap.listeners.before['event_process']['track_pid'] = function(session, body)
        if body and (body.systemProcessId or body.processId) then
          local pid = tonumber(body.systemProcessId or body.processId)
          if pid and pid > 0 then
            active_debug_pids[session.id] = pid
          end
        end
      end

      dap.listeners.before['event_processId']['track_pid'] = function(session, body)
        if body and (body.systemProcessId or body.processId) then
          local pid = tonumber(body.systemProcessId or body.processId)
          if pid and pid > 0 then
            active_debug_pids[session.id] = pid
          end
        end
      end

      -- [프로젝트 종속 디버기 프로세스 판별 헬퍼]
      -- IDE, LSP, Mason, 빌드 데몬(JDTLS, GradleDaemon)은 절대 건드리지 않고
      -- 오직 현재 프로젝트(cwd/MAIN_CLASS)의 런타임 디버깅 인스턴스만 정확히 식별합니다.
      local function is_project_debuggee(cmd, root, main_class)
        if not cmd or cmd == '' then
          return false
        end
        local cmd_lower = cmd:lower()

        -- 1) 절대 종료 금지 필터: IDE, LSP 서버, Mason, 빌드 데몬, Neovim
        if
          cmd:find('org.eclipse.equinox.launcher', 1, true)
          or cmd:find('jdtls', 1, true)
          or cmd:find('GradleDaemon', 1, true)
          or cmd:find('org.gradle', 1, true)
          or cmd:find('nvim', 1, true)
          or cmd:find('mason', 1, true)
          or cmd:find('language-server', 1, true)
          or cmd:find('vtsls', 1, true)
          or cmd:find('typescript-language-server', 1, true)
          or cmd:find('pyright', 1, true)
          or cmd:find('basedpyright', 1, true)
          or cmd:find('ruff', 1, true)
          or cmd:find('eslint', 1, true)
          or cmd:find('tailwindcss', 1, true)
        then
          return false
        end

        -- 2) Java / Spring Boot: MAIN_CLASS 일치 또는 프로젝트 경로 포함 java 런타임
        if main_class and main_class ~= '' and cmd:find(main_class, 1, true) then
          return true
        end
        if (cmd:find('java', 1, true) or cmd:find('javaw', 1, true)) and root ~= '' and cmd:find(root, 1, true) then
          return true
        end

        -- 3) Python: 현재 프로젝트 경로에서 실행 중인 python / uvicorn / gunicorn / debugpy
        if
          (
            cmd_lower:find('python', 1, true)
            or cmd_lower:find('uvicorn', 1, true)
            or cmd_lower:find('debugpy', 1, true)
            or cmd_lower:find('gunicorn', 1, true)
          )
          and root ~= ''
          and cmd:find(root, 1, true)
        then
          return true
        end

        -- 4) Node.js / TypeScript: 현재 프로젝트 경로에서 실행 중인 node / tsx / next / vite
        if
          (
            cmd_lower:find('node', 1, true)
            or cmd_lower:find('tsx', 1, true)
            or cmd_lower:find('ts-node', 1, true)
            or cmd_lower:find('vite', 1, true)
            or cmd_lower:find('next', 1, true)
          )
          and root ~= ''
          and cmd:find(root, 1, true)
        then
          return true
        end

        return false
      end

      local function kill_debuggee_process(session, on_done)
        local cb = on_done or function() end
        local session_id = session and session.id or (dap.session() and dap.session().id)
        local direct_pid = session_id and active_debug_pids[session_id]

        local my_pid = vim.uv.os_getpid()
        ---@diagnostic disable-next-line: undefined-field
        local root = (_G.PROJECT_ROOT and vim.fn.fnamemodify(_G.PROJECT_ROOT, ':p')) or vim.fn.getcwd()
        root = root:gsub('\\', '/'):gsub('/+$', '')
        ---@diagnostic disable-next-line: undefined-field
        local main_class = _G.MAIN_CLASS

        if _G.OS_TYPE == _G.OS.WINDOWS then
          -- Windows: Get-CimInstance Win32_Process 비동기 스캔 및 타겟 프로세스 종료
          local pwsh_cmd = string.format([=[
            $pids = @()
            Get-CimInstance Win32_Process | ForEach-Object {
              $cmd = $_.CommandLine
              $pid = $_.ProcessId
              if ($pid -ne %d -and $cmd) {
                $match = $false
                if ('%s' -ne '' -and $cmd -like '*%s*') { $match = $true }
                if ('%s' -ne '' -and ($cmd -like '*%s*') -and ($cmd -match 'java|python|node|uvicorn|debugpy')) { $match = $true }
                if ($match -and ($cmd -notmatch 'jdtls|GradleDaemon|nvim|code|pwsh|language-server|vtsls|pyright|eslint')) {
                  $pids += $pid
                }
              }
            }
            if (%s -gt 0) { $pids += %s }
            $pids = $pids | Select-Object -Unique
            foreach ($p in $pids) {
              Stop-Process -Id $p -Force -ErrorAction SilentlyContinue
            }
            $pids -join ','
          ]=], my_pid, main_class or '', main_class or '', root, root, tostring(direct_pid or 0), tostring(direct_pid or 0))

          pcall(vim.system, { 'powershell.exe', '-NoProfile', '-Command', pwsh_cmd }, { text = true }, function(obj)
            vim.schedule(function()
              if direct_pid and session_id then
                active_debug_pids[session_id] = nil
              end
              local killed = (obj.stdout or ''):gsub('%s+', '')
              if killed ~= '' then
                vim.notify(
                  string.format('기존 디버깅 프로세스(PID: %s)를 정리했습니다.', killed),
                  vim.log.levels.INFO,
                  { title = 'DAP 프로세스 정리' }
                )
              end
              cb()
            end)
          end)
        else
          -- Linux / WSL / macOS: ps -eo pid,args 기반 비동기 스캔 및 kill -9
          pcall(vim.system, { 'ps', '-eo', 'pid,args' }, { text = true }, function(obj)
            vim.schedule(function()
              local to_kill = {}
              if direct_pid and direct_pid > 0 and direct_pid ~= my_pid then
                to_kill[direct_pid] = true
              end

              local out = obj.stdout or ''
              for line in out:gmatch('[^\r\n]+') do
                local pid_str, cmd = line:match('^%s*(%d+)%s+(.*)$')
                local pid = tonumber(pid_str)
                if pid and pid ~= my_pid and is_project_debuggee(cmd, root, main_class) then
                  to_kill[pid] = true
                end
              end

              local pids_list = {}
              for pid in pairs(to_kill) do
                table.insert(pids_list, tostring(pid))
              end

              if #pids_list > 0 then
                local kill_args = { 'kill', '-9' }
                vim.list_extend(kill_args, pids_list)
                pcall(vim.system, kill_args, {}, function()
                  vim.schedule(function()
                    if direct_pid and session_id then
                      active_debug_pids[session_id] = nil
                    end
                    vim.notify(
                      string.format('기존 디버깅 프로세스(PID: %s)를 정리했습니다.', table.concat(pids_list, ', ')),
                      vim.log.levels.INFO,
                      { title = 'DAP 프로세스 정리' }
                    )
                    cb()
                  end)
                end)
              else
                if direct_pid and session_id then
                  active_debug_pids[session_id] = nil
                end
                cb()
              end
            end)
          end)
        end
      end
      _G.kill_debuggee_process = kill_debuggee_process


      -- [통합 디버그 UI 닫기 헬퍼 (nvim-dap-view, nvim-dap-ui, REPL 등 모든 UI 완벽 지원)]
      local function close_debug_ui()
        -- 1) nvim-dap-view 닫기
        pcall(function()
          local ok, dap_view = pcall(require, 'dap-view')
          if ok and dap_view and dap_view.close then
            dap_view.close()
          end
        end)

        -- 2) nvim-dap-ui 닫기 (기본/순정 DAP UI가 켜져 있는 경우 대응)
        pcall(function()
          local ok, dapui = pcall(require, 'dapui')
          if ok and dapui and dapui.close then
            dapui.close()
          end
        end)

        -- 3) REPL 창 닫기
        pcall(function()
          local ok, dap_mod = pcall(require, 'dap')
          if ok and dap_mod and dap_mod.repl and dap_mod.repl.close then
            dap_mod.repl.close()
          end
        end)

        -- 4) 디버깅 관련 분할 창(dap-view, dapui 윈도우 등) 정리
        vim.schedule(function()
          for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            if vim.api.nvim_win_is_valid(win) then
              local buf = vim.api.nvim_win_get_buf(win)
              local ft = vim.bo[buf].filetype
              if ft == 'dap-view' or ft:find('dapui_') or ft == 'dap-repl' then
                pcall(vim.api.nvim_win_close, win, true)
              end
            end
          end
        end)
      end
      _G.close_debug_ui = close_debug_ui

      -- [Disconnect 및 terminate 시 UI 자동 닫기 + 프로세스 강제 종료 보장]
      -- _dap_keep_process = true 이면 event_terminated/exited 리스너에서 kill을 생략합니다.
      -- (2번: Disconnect (terminate = false) 선택 시 서버를 살려두기 위해 사용)
      local _dap_keep_process = false

      local orig_terminate = dap.terminate
      dap.terminate = function(...)
        _dap_keep_process = false
        close_debug_ui()
        kill_debuggee_process()
        return orig_terminate(...)
      end

      local orig_disconnect = dap.disconnect
      dap.disconnect = function(opts, cb)
        opts = opts or {}
        if opts.terminateDebuggee == true then
          -- 1번: 디버깅 UI + 프로세스 모두 종료
          _dap_keep_process = false
          close_debug_ui()
          dap.terminate(nil, nil, cb)
          return
        else
          -- 2번: 디버거 연결만 끊기 (서버 프로세스는 유지)
          -- event_terminated 이벤트가 와도 kill을 건너뛰도록 플래그를 세움
          _dap_keep_process = true
          close_debug_ui()
          orig_disconnect(opts, cb)
        end
      end

      -- DAP 터미널 창 생성 시 포커스를 로그 창에 두고 커서를 맨 마지막 줄로 이동시켜 실시간 자동 스크롤 보장
      dap.defaults.fallback.terminal_win_cmd = function()
        vim.cmd('belowright new')
        local term_win = vim.api.nvim_get_current_win()
        local term_buf = vim.api.nvim_get_current_buf()
        vim.schedule(function()
          if vim.api.nvim_win_is_valid(term_win) and vim.api.nvim_buf_is_valid(term_buf) then
            vim.api.nvim_set_current_win(term_win)
            local line_count = vim.api.nvim_buf_line_count(term_buf)
            pcall(vim.api.nvim_win_set_cursor, term_win, { line_count, 0 })
          end
        end)
        return term_buf, term_win
      end
      -- winfixbuf 관련 버퍼 스위칭 에러(E1513) 방지를 위한 커스텀 switchbuf 로직
      dap.defaults.fallback.switchbuf = function(bufnr, line, column)
        local api = vim.api
        local col = math.max(0, (column or 1) - 1)

        -- 1) 현재 창이 winfixbuf가 아니면 바로 사용
        local cur_win = api.nvim_get_current_win()
        if not vim.wo[cur_win].winfixbuf then
          api.nvim_win_set_buf(cur_win, bufnr)
          pcall(api.nvim_win_set_cursor, cur_win, { line, col })
          api.nvim_set_current_win(cur_win)
          return true
        end

        -- 2) 현재 창이 winfixbuf로 잠겨있다면, 현재 탭 내에서 잠기지 않은 다른 창 탐색
        for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
          if not vim.wo[win].winfixbuf then
            api.nvim_win_set_buf(win, bufnr)
            pcall(api.nvim_win_set_cursor, win, { line, col })
            api.nvim_set_current_win(win)
            return true
          end
        end

        -- 3) 모든 창이 잠겨있다면 새 창을 분할해 열고 로드
        vim.cmd.split()
        local new_win = api.nvim_get_current_win()
        api.nvim_win_set_buf(new_win, bufnr)
        pcall(api.nvim_win_set_cursor, new_win, { line, col })
        return true
      end

      -- Java attach는 <leader>da(attach_debug)가 dap.run()을 직접 호출해서 처리합니다.
      -- LazyVim의 extras/lang/java.lua가 자체적으로 "Debug (Attach) - Remote" 기본 attach 설정을
      -- dap.configurations.java에 넣어두므로, 여기서 명시적으로 비워야 <leader>dd 피커에서 빠집니다.
      dap.configurations.java = {}

      -- Python FastAPI launch 기본 구성 (수동 실행 시 DAP UI에 표시됨, 중복 등록 방지)
      dap.configurations.python = dap.configurations.python or {}
      local has_fastapi = false
      for _, conf in ipairs(dap.configurations.python) do
        if conf.name and conf.name:find('FastAPI') then
          has_fastapi = true
          break
        end
      end
      if not has_fastapi then
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
      end


      -- 대신 디버깅 시작 시 nvim-dap-view가 자동으로 열리도록 설정
      dap.listeners.after.event_initialized['dapview_config'] = function(session)
        require('dap-view').open()

        -- 디버깅 실행 시 로그/터미널 창 열림 보장 및 자동 스크롤:
        -- 1) 사용자가 이전에 로그 창을 :q로 닫았더라도 새 디버깅 시작 시 다시 열어줌
        -- 2) 단, 이미 열려 있는 경우에는 중복으로 2개 열리지 않도록 기존 창을 재사용
        -- 3) 커서를 맨 마지막 줄로 이동시켜 실시간 자동 스크롤(Auto-Scroll) 활성화
        vim.schedule(function()
          local current_session = session or dap.session()
          local term_buf = current_session and current_session.term_buf

          -- term_buf가 없으면 버퍼 목록에서 dap-terminal 버퍼 탐색
          if not term_buf or not vim.api.nvim_buf_is_valid(term_buf) then
            for _, b in ipairs(vim.api.nvim_list_bufs()) do
              if vim.api.nvim_buf_is_valid(b) then
                local bname = vim.api.nvim_buf_get_name(b)
                if bname:find('%[dap%-terminal%]') or vim.b[b]['dap-type'] or vim.bo[b].buftype == 'terminal' then
                  term_buf = b
                  break
                end
              end
            end
          end

          local log_win = nil
          if term_buf and vim.api.nvim_buf_is_valid(term_buf) then
            -- 이미 열려있는 창이 있는지 확인
            local wins = vim.fn.win_findbuf(term_buf)
            if #wins > 0 then
              log_win = wins[1]
            else
              -- 사용자가 :q로 닫아서 화면에 없는 경우: 메인 에디터/대시보드 아래에 분할 창 생성하여 복원
              for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
                local buf = vim.api.nvim_win_get_buf(win)
                local ft = vim.bo[buf].filetype
                if ft ~= 'dap-view' and ft ~= 'dap-view-term' and ft ~= 'dap-repl' then
                  vim.api.nvim_set_current_win(win)
                  vim.cmd('belowright split')
                  log_win = vim.api.nvim_get_current_win()
                  vim.api.nvim_win_set_buf(log_win, term_buf)
                  break
                end
              end
            end
          end

          -- 로그 창이 확보되었으면 포커스를 두고 맨 아래로 스크롤
          if log_win and vim.api.nvim_win_is_valid(log_win) then
            pcall(vim.api.nvim_set_current_win, log_win)
            local buf = vim.api.nvim_win_get_buf(log_win)
            local line_count = vim.api.nvim_buf_line_count(buf)
            pcall(vim.api.nvim_win_set_cursor, log_win, { line_count, 0 })
          end
        end)
      end
      -- 디버깅 종료 시 모든 디버그 UI가 자동으로 닫히고 프로세스를 정리하도록 설정
      -- _dap_keep_process == true 이면 2번(disconnect keep-alive) 선택이므로 프로세스는 종료하지 않음
      dap.listeners.before.event_terminated['dapview_config'] = function()
        close_debug_ui()
        if not _dap_keep_process then
          kill_debuggee_process()
        end
        _dap_keep_process = false  -- 플래그 초기화
      end
      dap.listeners.before.event_exited['dapview_config'] = function()
        close_debug_ui()
        if not _dap_keep_process then
          kill_debuggee_process()
        end
        _dap_keep_process = false  -- 플래그 초기화
      end

      -- Console(dap-view-term) 창에서 포커스가 벗어나면 자동으로 맨 아래로 스크롤합니다.
      -- nvim-dap-view는 커서가 마지막 줄에 있을 때만 자동 스크롤하도록 이미 구현돼 있어서
      -- (직접 위로 스크롤해 이전 로그를 볼 수 있도록 하기 위함 — nvim-dap-view 소스인
      -- lua/dap-view/console/scroll.lua에서 확인), 창을 벗어나도 커서 위치가 그대로
      -- 남아있어 다시 돌아왔을 때 최신 로그를 보려면 매번 수동으로 끝까지 스크롤해야
      -- 하는 불편함이 있었습니다. WinLeave 시 커서를 마지막 줄로 옮기면, 플러그인 자체의
      -- CursorMoved 감지 로직이 "사용자가 끝까지 스크롤했다"고 인식해서 자동 스크롤이
      -- 자연스럽게 다시 켜집니다(플러그인 내부 구현을 직접 건드리지 않고 재동기화).
      vim.api.nvim_create_autocmd('WinLeave', {
        group = vim.api.nvim_create_augroup('dapview_console_autoscroll_resume', { clear = true }),
        callback = function()
          if vim.bo.filetype ~= 'dap-view-term' then
            return
          end
          local winnr = vim.api.nvim_get_current_win()
          local bufnr = vim.api.nvim_get_current_buf()
          vim.schedule(function()
            if vim.api.nvim_win_is_valid(winnr) and vim.api.nvim_buf_is_valid(bufnr) then
              local last_line = vim.api.nvim_buf_line_count(bufnr)
              pcall(vim.api.nvim_win_set_cursor, winnr, { last_line, 0 })
            end
          end)
        end,
      })

      -- [Java Launch: Spring 프로필 주입]
      -- 자바 launch 설정(setup_dap_main_class_configs가 자동 생성한 "Launch ..." 항목)을 실행할 때만
      -- Spring 프로필을 물어보고 --spring.profiles.active=... 를 프로그램 인자에 주입합니다.
      -- (테스트 러너 launch는 제외, Python 등 다른 언어는 애초에 이 조건에 안 걸립니다)
      -- 프로젝트별 마지막 입력값은 command-palette(fzf)/setup-*.sh 와 완전히 동일한
      -- ~/.devtools2/state.properties 파일 및 키 스킴(MD5(정규화된 cwd).gradle_run.profile)을
      -- 공유합니다. 예전엔 ~/.nvim/state.json 이라는 별도 파일을 썼는데, 그러면
      -- setup-goono-eln.sh가 미리 심어둔 기본값이나 fzf 쪽에서 입력한 값을 nvim이 전혀
      -- 몰라서 <leader>dd 를 눌러도 기본값이 안 뜨는 불일치가 있었습니다(실측으로 발견).
      local devtools2_state_file = _G.HOME_DIR .. '/.devtools2/state.properties'

      -- bash 쪽 PROJ_KEY 계산과 완전히 동일한 방식(정규화한 cwd를 md5sum에 stdin으로 전달)을 재현합니다.
      -- 실측으로 bash 결과와 Lua 결과가 정확히 일치함을 확인했습니다.
      local function get_devtools2_proj_key()
        local cwd = vim.fn.getcwd():gsub('\\', '/'):gsub('/$', '')
        -- vim.fn.system(cmd, input)은 input을 stdin으로 전달 — bash의 `echo cwd | md5sum`과 동일합니다.
        local output = vim.fn.system('md5sum', cwd)
        if vim.v.shell_error ~= 0 or output == '' then
          return nil
        end
        return output:match('^(%x+)')
      end

      local function get_last_spring_profile()
        local proj_key = get_devtools2_proj_key()
        if not proj_key then
          return ''
        end
        local full_key = proj_key .. '.gradle_run.profile'
        local f = io.open(devtools2_state_file, 'r')
        if not f then
          return ''
        end
        local content = f:read('*all')
        f:close()
        for line in content:gmatch('[^\r\n]+') do
          local k, v = line:match('^([^=]+)=(.*)$')
          if k == full_key then
            return v or ''
          end
        end
        return ''
      end

      local function save_last_spring_profile(profile)
        local proj_key = get_devtools2_proj_key()
        if not proj_key then
          return
        end
        local full_key = proj_key .. '.gradle_run.profile'
        vim.fn.mkdir(_G.HOME_DIR .. '/.devtools2', 'p')
        local lines = {}
        local f_read = io.open(devtools2_state_file, 'r')
        if f_read then
          local content = f_read:read('*all')
          f_read:close()
          for line in content:gmatch('[^\r\n]+') do
            local k = line:match('^([^=]+)=')
            if k ~= full_key then
              table.insert(lines, line)
            end
          end
        end
        table.insert(lines, full_key .. '=' .. profile)
        local f_write = io.open(devtools2_state_file, 'w')
        if f_write then
          f_write:write(table.concat(lines, '\n') .. '\n')
          f_write:close()
        end
      end

      local TEST_RUNNER_CLASSES = {
        ['com.microsoft.java.test.runner.Launcher'] = true,
        ['org.testng.TestNG'] = true,
      }

      -- jdt.ls에 java/buildWorkspace(증분 빌드)를 요청합니다. 폴링이 아니라 응답 콜백으로
      -- "완료된 순간 즉시" 진행하고, 1분 안에 응답이 없으면 포기하고 알려줍니다.
      local function build_workspace_with_watchdog(on_done)
        local clients = vim.lsp.get_clients({ bufnr = 0, name = 'jdtls' })
        local client = clients[1]
        if not client then
          clients = vim.lsp.get_clients({ name = 'jdtls' })
          client = clients[1]
        end
        if not client then
          vim.notify('jdtls 클라이언트를 찾을 수 없어 빌드 확인 없이 실행합니다.', vim.log.levels.WARN, { title = 'Java Launch' })
          on_done(true)
          return
        end

        local settled = false
        local timer = vim.uv.new_timer()
        timer:start(60000, 0, vim.schedule_wrap(function()
          if settled then
            return
          end
          settled = true
          timer:stop()
          timer:close()
          vim.notify('빌드 확인이 1분 넘게 응답이 없어 실행을 중단합니다.', vim.log.levels.ERROR, { title = 'Java Launch: 빌드 타임아웃' })
          on_done(false)
        end))

        vim.notify('🔨 빌드 확인 중 (incremental)...', vim.log.levels.INFO, { title = 'Java Launch' })
        -- java/buildWorkspace 파라미터: boolean(isFullBuild) → false = incremental
        client:request('java/buildWorkspace', false, function(err, result)
          if settled then
            return
          end
          settled = true
          timer:stop()
          timer:close()
          vim.schedule(function()
            local STATUS_SUCCEED = 1
            if err then
              vim.notify(
                '빌드 요청 오류: ' .. vim.inspect(err) .. '\n빌드 확인 없이 실행합니다.',
                vim.log.levels.WARN,
                { title = 'Java Launch' }
              )
              on_done(true)
              return
            end
            if result == STATUS_SUCCEED then
              on_done(true)
              return
            end
            -- 빌드 에러: quickfix에 진단 목록을 채우고 계속 진행할지 확인
            vim.diagnostic.setqflist({ open = true, severity = vim.diagnostic.severity.ERROR, title = 'Java Build Errors' })
            vim.ui.select({ '예, 그래도 실행', '아니오, 취소' }, {
              prompt = '⚠️ 빌드 에러가 있습니다 (:copen 목록 확인). 그래도 디버깅을 실행할까요?',
            }, function(choice)
              on_done(choice ~= nil and choice:find('예', 1, true) ~= nil)
            end)
          end)
        end)
      end

      -- 디버그 세션이 실제로 초기화될 때까지 dap.listeners.after.event_initialized로 기다립니다
      -- (폴링이 아니라 이벤트 발생 즉시 반응). 1분 동안 초기화도 종료도 안 되면, 고정된 숫자로
      -- 바로 강제 종료하는 대신 "계속 기다릴지 강제 종료할지" 물어봅니다 — 프로젝트마다 정상적인
      -- 초기화 소요 시간이 달라서 "안전한 고정 타임아웃"을 미리 추측할 수 없기 때문입니다.
      -- nvim-dap 자체의 55초 "Debug adapter didn't respond" 경고는 정보성 알림일 뿐 세션을
      -- 끊지 않으므로 그대로 두고, 실제 판단은 이 워치독(및 사용자 응답)이 담당합니다.
      local function run_with_init_watchdog(config, run_opts, run_next)
        local dap_mod = require('dap')
        local key = 'java_launch_watchdog_' .. tostring({})
        local settled = false
        local timer
        local start_timer

        local function cleanup()
          dap_mod.listeners.after.event_initialized[key] = nil
          dap_mod.listeners.after.event_terminated[key] = nil
          dap_mod.listeners.after.event_exited[key] = nil
          if timer then
            timer:stop()
            timer:close()
            timer = nil
          end
        end

        local function on_timeout()
          if settled then
            return
          end
          vim.ui.select({ '예, 계속 기다리기', '아니오, 강제 종료' }, {
            prompt = '⏳ 디버그 세션이 1분 넘게 초기화되지 않았습니다. 계속 기다릴까요?',
          }, function(choice)
            -- 응답을 기다리는 동안 초기화가 끝났거나 세션이 이미 종료됐을 수 있음
            if settled then
              return
            end
            if choice and choice:find('계속', 1, true) then
              start_timer()
            else
              settled = true
              cleanup()
              vim.notify(
                '사용자 요청으로 디버그 세션을 강제 종료합니다.',
                vim.log.levels.WARN,
                { title = 'Java Launch: 초기화 대기 중단' }
              )
              if dap_mod.session() then
                dap_mod.terminate()
              end
            end
          end)
        end

        start_timer = function()
          if timer then
            timer:stop()
            timer:close()
          end
          timer = vim.uv.new_timer()
          timer:start(60000, 0, vim.schedule_wrap(on_timeout))
        end
        start_timer()

        -- 초기화 성공, 혹은 (초기화 전) 세션 종료/중단 중 먼저 발생하는 쪽에서 워치독을 해제합니다.
        dap_mod.listeners.after.event_initialized[key] = function()
          if settled then
            return
          end
          settled = true
          cleanup()
        end
        dap_mod.listeners.after.event_terminated[key] = function()
          if settled then
            return
          end
          settled = true
          cleanup()
        end
        dap_mod.listeners.after.event_exited[key] = function()
          if settled then
            return
          end
          settled = true
          cleanup()
        end

        run_next(config, run_opts)
      end

      -- ===========================================================================================
      -- [Java Launch 전 자동 리소스 빌드: run_project_prebuild] ⚠️ AI 수정 주의: 필수 로직!
      -- ===========================================================================================
      -- 1. 배경 및 원인:
      --    JDTLS의 `java/buildWorkspace`는 Eclipse 내장 컴파일러(ECJ)로 `.java` → `.class` 컴파일만 수행합니다.
      --    하지만 Spring Boot 프로젝트(예: Goono-ELN)는 `build.gradle`의 `processResources` 태스크를 통해
      --    `src/main/resources/config/@build-0_LOCAL.yml` 파일 생성 및 `${build.project.basepath}` 치환 등을 수행합니다.
      --    이 과정이 누락되면 스프링 기동 시 `IllegalArgumentException: Could not resolve placeholder 'build.project.basepath'`
      --    크래시가 발생하므로, DAP 디버깅 실행 직전에 반드시 `gradlew processResources`를 먼저 비동기로 실행해야 합니다.
      --
      -- 2. Neovim 0.12 표준 비동기 API:
      --    `vim.system`을 사용하여 에디터 UI 멈춤(블로킹) 없이 백그라운드에서 빌드 후 증분 빌드 워치독으로 체이닝합니다.
      -- ===========================================================================================
      local function run_project_prebuild(on_done)
        ---@diagnostic disable-next-line: undefined-field
        local root = (_G.PROJECT_ROOT and vim.fn.fnamemodify(_G.PROJECT_ROOT, ':p')) or vim.fn.getcwd()
        if not root:match('/$') then
          root = root .. '/'
        end

        local gradlew = root .. 'gradlew'
        local mvnw = root .. 'mvnw'
        local has_gradlew = vim.fn.filereadable(gradlew) == 1
        local has_mvnw = vim.fn.filereadable(mvnw) == 1

        ---@diagnostic disable-next-line: undefined-field
        local java_ver = tonumber(_G.JDK_VERSION) or 21
        local java_home = (java_ver >= 21) and (_G.DEVTOOLS2_DIR .. '/modules/java/jdk-' .. java_ver)
          or (_G.DEVTOOLS2_DIR .. '/modules/java/jdk-21')

        if has_gradlew then
          vim.notify('📦 리소스 및 빌드 프로필 처리 중 (gradlew processResources)...', vim.log.levels.INFO, { title = 'Java Launch' })
          vim.system({ gradlew, 'processResources' }, {
            cwd = root,
            env = { JAVA_HOME = java_home },
            text = true,
          }, function(obj)
            vim.schedule(function()
              if obj.code ~= 0 then
                vim.notify('⚠️ gradlew processResources 실패:\n' .. (obj.stderr or obj.stdout or ''), vim.log.levels.WARN, { title = 'Java Launch' })
              end
              build_workspace_with_watchdog(on_done)
            end)
          end)
        elseif has_mvnw then
          vim.notify('📦 리소스 및 빌드 프로필 처리 중 (mvnw process-resources)...', vim.log.levels.INFO, { title = 'Java Launch' })
          vim.system({ mvnw, 'process-resources' }, {
            cwd = root,
            env = { JAVA_HOME = java_home },
            text = true,
          }, function(obj)
            vim.schedule(function()
              build_workspace_with_watchdog(on_done)
            end)
          end)
        else
          build_workspace_with_watchdog(on_done)
        end
      end

      local function launch_with_watchdogs(config, run_opts, run_next)
        run_project_prebuild(function(should_launch)
          if should_launch then
            run_with_init_watchdog(config, run_opts, run_next)
          end
        end)
      end

      -- ===========================================================================================
      -- [Java Launch 실행 래퍼: run_java_launch]
      -- 1. .nvim.lua의 `MAIN_CLASS` 자동 주입:
      --    사용자가 대시보드나 비-자바 파일에서 디버깅을 실행하더라도 `.nvim.lua`에 `MAIN_CLASS`가 있으면
      --    별도의 수동 파일 열기 없이 해당 메인 클래스로 즉시 디버깅을 진행합니다.
      -- 2. Spring Profile 대화형 입력 + 중복 인자 누적 방지:
      --    마지막으로 입력한 프로필을 자동 기억하여 기본값으로 제안합니다.
      -- ===========================================================================================
      local function run_java_launch(config, run_opts, run_next)
        -- .nvim.lua에 MAIN_CLASS가 정의되어 있고 config에 mainClass가 없으면 자동 주입
        ---@diagnostic disable-next-line: undefined-field
        if not config.mainClass and _G.MAIN_CLASS then
          ---@diagnostic disable-next-line: undefined-field
          config.mainClass = _G.MAIN_CLASS
        end

        if config.mainClass and TEST_RUNNER_CLASSES[config.mainClass] then
          launch_with_watchdogs(config, run_opts, run_next)
          return
        end

        vim.ui.input({
          prompt = 'Spring Profile (예: local,dev / 비우면 미지정): ',
          default = get_last_spring_profile(),
        }, function(profile_input)
          if profile_input == nil then
            return -- Esc로 취소 (실행하지 않음)
          end

          -- vscode-java-debug (com.microsoft.java.debug.core) 규격상 args는 배열이 아닌 String이어야 합니다.
          -- 테이블(배열) 타입인 경우 문자열로 결합하여 JsonSyntaxException (Expected STRING but was BEGIN_ARRAY at path $.args)을 방지합니다.
          if type(config.args) == 'table' then
            local str = table.concat(config.args, ' ')
            config.args = str ~= '' and str or nil
          end

          -- dap.configurations.java의 config 테이블은 LspAttach가 다시 발생하기 전까지 재사용되므로,
          -- 이전 실행에서 주입했던 --spring.profiles.active=...를 지우지 않으면 같은 파일에서
          -- 다른 프로필로 재실행할 때마다 계속 누적됩니다. 새로 판단하기 전에 먼저 제거합니다.
          if type(config.args) == 'string' then
            config.args = config.args:gsub('%-%-spring%.profiles%.active=%S+%s*', ''):gsub('%s+$', '')
            if config.args == '' then
              config.args = nil
            end
          end

          if profile_input ~= '' then
            save_last_spring_profile(profile_input)
            local spring_arg = '--spring.profiles.active=' .. profile_input
            if not config.args or config.args == '' then
              config.args = spring_arg
            else
              config.args = config.args .. ' ' .. spring_arg
            end
          end
          launch_with_watchdogs(config, run_opts, run_next)
        end)
      end

      -- [스마트 프로세스 선제 정리 + Java Launch 프로필 주입] dap.run 핵심 함수 래핑
      -- 디버깅이 가동되기 직전(어댑터 작동 전)에 동일 프로젝트의 잔여 런타임 프로세스를 사전에 정리합니다.
      local orig_run = dap.run
      local wrapped_java_adapters = {}

      -- [모듈화된 동적 메뉴 번역기 등록]
      -- lua/util/menu_translator.lua 모듈을 사용하여 다른 메뉴에서도 재사용 가능하도록 설계
      local menu_translator = require('util.menu_translator')

      -- 1) DAP 활성 세션 메뉴 인터셉터 (4, 5번 Disconnect 항목 최상단 정렬 + 한글/영문 표시)
      menu_translator.register_interceptor({
        name = 'dap_session',
        prompt_patterns = { 'Session', 'Thread', '세션' },
        translations = {
          ['Disconnect (terminate = true)'] = { ko = '디버깅 및 서버 프로세스 강제 종료', priority = 1 },
          ['Disconnect (terminate = false)'] = { ko = '디버거 연결만 끊기 - 서버 계속 실행', priority = 2 },
          ['Restart session'] = { ko = '디버그 세션 재시작', priority = 3 },
          ['Terminate session'] = { ko = '디버그 세션 종료', priority = 4 },
          ['Pause a thread'] = { ko = '스레드 일시 정지', priority = 5 },
          ['Start additional session'] = { ko = '추가 디버그 세션 시작', priority = 6 },
          ['Do nothing'] = { ko = '아무 작업도 하지 않음 (취소)', priority = 7 },
          ['Resume stopped thread'] = { ko = '멈춰있는 스레드 재개', priority = 0 },
        },
      })

      ---@diagnostic disable-next-line: duplicate-set-field
      dap.run = function(config, run_opts)
        -- 디버깅 실행 직전 기존 잔여 프로젝트 디버기 프로세스를 선제적으로 비동기 정리
        kill_debuggee_process(nil, function()
          if config and config.type == 'java' and config.request == 'launch' then
            local current_adapter = dap.adapters.java
            if type(current_adapter) == 'function' and not wrapped_java_adapters[current_adapter] then
              local orig_adapter = current_adapter
              local wrapped = function(cb, conf)
                orig_adapter(function(adapter_result)
                  if adapter_result then
                    adapter_result.options = adapter_result.options or {}
                    adapter_result.options.initialize_timeout_sec = 55
                  end
                  cb(adapter_result)
                end, conf)
              end
              wrapped_java_adapters[wrapped] = true
              dap.adapters.java = wrapped
            end
            run_java_launch(config, run_opts, orig_run)
            return
          end

          orig_run(config, run_opts)
        end)
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
