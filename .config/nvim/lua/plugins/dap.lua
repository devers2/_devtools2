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
        end, 0)
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

      local function launch_with_watchdogs(config, run_opts, run_next)
        build_workspace_with_watchdog(function(should_launch)
          if should_launch then
            run_with_init_watchdog(config, run_opts, run_next)
          end
        end)
      end

      -- run_next: 실제 실행을 넘겨받아 호출하는 콜백 (dap.run 래핑 순서와 무관하게 동작하도록 인자로 전달)
      local function run_java_launch(config, run_opts, run_next)
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

      -- [스마트 포트 자동 킬러 + Java Launch 프로필 주입] dap.run 핵심 함수 래핑
      -- 디버깅이 가동되기 직전(어댑터 작동 전)에 포트를 스캔하여 선점 프로세스를 사전에 제거합니다.
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
        if config and config.type == 'java' and config.request == 'launch' then
          local current_adapter = dap.adapters.java
          if type(current_adapter) == 'function' and not wrapped_java_adapters[current_adapter] then
            local orig_adapter = current_adapter
            local wrapped = function(cb, conf)
              orig_adapter(function(adapter_result)
                if adapter_result then
                  adapter_result.options = adapter_result.options or {}
                  -- nvim-dap의 "Debug adapter didn't respond" 경고는 순수 정보성 알림이라
                  -- 세션을 끊지 않으며(session.lua Session:initialize), 실제 성공/실패 판단은
                  -- 위쪽 run_with_init_watchdog의 60초 워치독이 전담합니다.
                  -- 이 값은 그 워치독보다 항상 먼저 뜨면 안 되므로 60초보다 낮게,
                  -- 그러나 대형 프로젝트에서 흔한 5~15초대 초기화 지연에는 안 뜨도록 55초로 둡니다.
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

        if config and config.request == 'launch' then
          local port = nil
          -- 1) config 자체에 port가 있는 경우
          if config.port then
            port = tonumber(config.port)
          end
          -- 2) FastAPI 런치 설정처럼 args 테이블에 '--port' '8095'가 있는 경우
          if not port and config.args and type(config.args) == 'table' then
            for i, arg in ipairs(config.args) do
              if arg == '--port' and config.args[i + 1] then
                port = tonumber(config.args[i + 1])
                break
              end
            end
          end

          if port then
            -- [비동기 포트 킬러] vim.system으로 UI 블록 없이 포트 점유 프로세스를 제거한 뒤
            -- 100ms 후 원래 dap.run을 실행합니다 (vim.cmd('sleep') 대신 타이머 사용).
            local function do_run_after_delay()
              local t = vim.uv.new_timer()
              t:start(100, 0, vim.schedule_wrap(function()
                t:stop(); t:close()
                orig_run(config, run_opts)
              end))
            end

            if _G.OS_TYPE == _G.OS.WINDOWS then
              -- Windows: netstat -ano → PID 추출 → taskkill (비동기)
              vim.system({ 'netstat', '-ano' }, { text = true }, function(netstat_out)
                vim.schedule(function()
                  local pids = {}
                  local result = (netstat_out.stdout or '')
                  for line in result:gmatch('[^\r\n]+') do
                    local tokens = {}
                    for token in line:gmatch('%S+') do
                      table.insert(tokens, token)
                    end
                    if #tokens >= 5 then
                      local local_addr = tokens[2]
                      local state      = tokens[4]
                      local pid        = tokens[5]
                      if local_addr:match(':' .. port .. '$') and state == 'LISTENING' and tonumber(pid) then
                        pids[pid] = true
                      end
                    end
                  end

                  local any = false
                  for pid in pairs(pids) do
                    any = true
                    vim.system({ 'taskkill', '/F', '/PID', pid }, {}, function()
                      vim.schedule(function()
                        vim.notify(
                          string.format('기존 포트 %d의 Windows 프로세스(%s)를 종료했습니다.', port, pid),
                          vim.log.levels.INFO
                        )
                      end)
                    end)
                  end

                  if any then
                    do_run_after_delay()
                  else
                    orig_run(config, run_opts)
                  end
                end)
              end)
              return -- orig_run은 콜백 내에서 실행
            else
              -- macOS & Linux: lsof -t → kill -9 (비동기)
              vim.system({ 'lsof', '-t', string.format('-i:%d', port) }, { text = true }, function(lsof_out)
                vim.schedule(function()
                  local valid_pids = {}
                  for pid in (lsof_out.stdout or ''):gmatch('%d+') do
                    table.insert(valid_pids, pid)
                  end

                  if #valid_pids > 0 then
                    local kill_args = { 'kill', '-9' }
                    vim.list_extend(kill_args, valid_pids)
                    vim.system(kill_args, {}, function()
                      vim.schedule(function()
                        vim.notify(
                          string.format(
                            '기존 포트 %d의 프로세스(%s)를 종료하고 디버깅을 시작합니다.',
                            port,
                            table.concat(valid_pids, ' ')
                          ),
                          vim.log.levels.INFO
                        )
                      end)
                    end)
                    do_run_after_delay()
                  else
                    orig_run(config, run_opts)
                  end
                end)
              end)
              return -- orig_run은 콜백 내에서 실행
            end
          end
        end
        orig_run(config, run_opts)
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
