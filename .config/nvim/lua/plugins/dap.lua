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

      -- Java attach는 <leader>da(attach_debug)가 dap.run()을 직접 호출해서 처리합니다.
      -- LazyVim의 extras/lang/java.lua가 자체적으로 "Debug (Attach) - Remote" 기본 attach 설정을
      -- dap.configurations.java에 넣어두므로, 여기서 명시적으로 비워야 <leader>dd 피커에서 빠집니다.
      dap.configurations.java = {}

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

      -- [Java Launch: Spring 프로필 주입]
      -- 자바 launch 설정(setup_dap_main_class_configs가 자동 생성한 "Launch ..." 항목)을 실행할 때만
      -- Spring 프로필을 물어보고 --spring.profiles.active=... 를 프로그램 인자에 주입합니다.
      -- (테스트 러너 launch는 제외, Python 등 다른 언어는 애초에 이 조건에 안 걸립니다)
      -- 프로젝트별 마지막 입력값은 ~/.nvim/state.json 에 기억합니다 (attach 포트 기억과 동일한 방식).
      local java_state_dir = _G.HOME_DIR .. '/.nvim'
      local java_state_file = java_state_dir .. '/state.json'

      local function get_last_spring_profile()
        local f = io.open(java_state_file, 'r')
        if not f then
          return ''
        end
        local content = f:read('*all')
        f:close()
        local ok, state = pcall(vim.json.decode, content)
        if not ok or type(state) ~= 'table' then
          return ''
        end
        local cwd_state = state[vim.fn.getcwd()] or {}
        return cwd_state.last_spring_profile or ''
      end

      local function save_last_spring_profile(profile)
        vim.fn.mkdir(java_state_dir, 'p')
        local state = {}
        local f_read = io.open(java_state_file, 'r')
        if f_read then
          local content = f_read:read('*all')
          f_read:close()
          if content and content ~= '' then
            local ok, decoded = pcall(vim.json.decode, content)
            if ok and type(decoded) == 'table' then
              state = decoded
            end
          end
        end
        local cwd = vim.fn.getcwd()
        state[cwd] = state[cwd] or {}
        state[cwd].last_spring_profile = profile
        local f_write = io.open(java_state_file, 'w')
        if f_write then
          f_write:write(vim.json.encode(state))
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
        local timer = vim.loop.new_timer()
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
              on_done(choice ~= nil and choice:find('예') ~= nil)
            end)
          end)
        end, 0)
      end

      -- 디버그 세션이 실제로 초기화될 때까지 dap.listeners.after.event_initialized로 기다립니다
      -- (폴링이 아니라 이벤트 발생 즉시 반응). 1분 안에 초기화도, 종료도 안 되면 메시지와 함께
      -- 강제로 세션을 종료합니다. nvim-dap 자체의 4초 "Debug adapter didn't respond" 경고는
      -- 정보성 알림일 뿐 세션을 끊지 않으므로 그대로 두고, 실제 판단은 이 워치독이 담당합니다.
      local function run_with_init_watchdog(config, run_opts, run_next)
        local dap_mod = require('dap')
        local key = 'java_launch_watchdog_' .. tostring({})
        local settled = false
        local timer = vim.loop.new_timer()

        local function cleanup()
          dap_mod.listeners.after.event_initialized[key] = nil
          dap_mod.listeners.after.event_terminated[key] = nil
          dap_mod.listeners.after.event_exited[key] = nil
          timer:stop()
          timer:close()
        end

        timer:start(60000, 0, vim.schedule_wrap(function()
          if settled then
            return
          end
          settled = true
          cleanup()
          vim.notify(
            '디버그 세션이 1분 넘게 초기화되지 않아 강제 종료합니다.',
            vim.log.levels.ERROR,
            { title = 'Java Launch: 초기화 타임아웃' }
          )
          if dap_mod.session() then
            dap_mod.terminate()
          end
        end))

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

          if profile_input ~= '' then
            save_last_spring_profile(profile_input)
            local spring_arg = '--spring.profiles.active=' .. profile_input
            if not config.args or config.args == '' then
              config.args = spring_arg
            elseif type(config.args) == 'string' then
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

      -- 2) DAP 디버그 실행 구성 선택 메뉴 인터셉터 (<leader>d / <leader>dd 디버그 런치 선택창)
      menu_translator.register_interceptor({
        name = 'dap_config',
        prompt_patterns = { 'Configuration', 'Select configuration', '설정' },
        translations = {
          ['Launch goono-eln: so.goono.GoonoELNApplication'] = { ko = '구노 ELN 메인 앱 디버깅 실행', priority = 1 },
          ['GoonoELNApplication'] = { ko = 'VSCode Launch: 구노 ELN 앱', priority = 2 },
          ['FastAPI 디버깅 실행 (기본: 8095)'] = { ko = '파이썬 FastAPI 웹 서버 실행', priority = 3 },
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
                  adapter_result.options.initialize_timeout_sec = 15
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
        return orig_run(config, run_opts)
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
