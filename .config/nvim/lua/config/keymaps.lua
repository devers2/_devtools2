-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- 현재 위치의 시스템 탐색기 열기: <Leader>fE (File Explore)
vim.keymap.set('n', '<leader>fE', function()
  local path = vim.fn.expand('%:p:h')
  if _G.OS_TYPE == _G.OS.WINDOWS then
    -- Windows: explorer.exe 사용
    path = path:gsub('/', '\\')
    vim.fn.jobstart({ 'explorer.exe', path }, { detach = true })
  elseif _G.OS_TYPE == _G.OS.MACOS then
    -- macOS: open 사용
    vim.fn.jobstart({ 'open', path }, { detach = true })
  else
    -- Linux: xdg-open 사용
    vim.fn.jobstart({ 'xdg-open', path }, { detach = true })
  end
end, { desc = 'Open System Explorer' })

local ok, dap = pcall(require, 'dap')
if ok then
  -- 프로젝트별 상태 관리를 위한 파일 경로 설정
  local nvim_state_dir = _G.HOME_DIR .. '/.nvim'
  local state_file = nvim_state_dir .. '/state.json'

  -- 디렉토리 생성
  vim.fn.mkdir(nvim_state_dir, 'p')

  -- 상태 읽기/쓰기 함수 (언어별 포트 분리 저장)
  local function get_last_debug_port(ft, default_port)
    local f = io.open(state_file, 'r')
    if not f then
      return default_port
    end
    local content = f:read('*all')
    f:close()
    local state = vim.json.decode(content) or {}
    local cwd = vim.fn.getcwd()
    local cwd_state = state[cwd] or {}
    -- 자바의 경우 기존 last_debug_port 키 하위 호환 처리
    if ft == 'java' and cwd_state.last_debug_port and not cwd_state.last_java_port then
      return cwd_state.last_debug_port
    end
    return cwd_state['last_' .. ft .. '_port'] or default_port
  end

  local function save_last_debug_port(ft, port)
    local f_read = io.open(state_file, 'r')
    local state = {}
    if f_read then
      local content = f_read:read('*all')
      if content and content ~= '' then
        state = vim.json.decode(content) or {}
      end
      f_read:close()
    end
    local cwd = vim.fn.getcwd()
    state[cwd] = state[cwd] or {}
    state[cwd]['last_' .. ft .. '_port'] = port
    local f_write = io.open(state_file, 'w')
    if f_write then
      f_write:write(vim.json.encode(state))
      f_write:close()
    end
  end

  -- 현재 버퍼가 자바 환경인지 감지 (filetype=java 또는 jdtls LSP 활성화 여부)
  local function is_java_env()
    if vim.bo.filetype == 'java' then
      return true
    end
    local clients = vim.lsp.get_clients({ name = 'jdtls' })
    if #clients > 0 then
      return true
    end
    return false
  end

  -- Java: 어태치 모드 / Python: FastAPI 런치 모드 자동 분기
  local function attach_debug()
    if is_java_env() then
      -- Java: 포트 입력 후 어태치
      local default_port = get_last_debug_port('java', '5005')
      vim.ui.input({
        prompt = 'Java Debug Port: ',
        default = default_port,
      }, function(input)
        if input and input ~= '' then
          local port = tonumber(input)
          if port then
            save_last_debug_port('java', tostring(port))
            dap.run({
              type = 'java',
              request = 'attach',
              name = 'Java Attach: ' .. port,
              hostName = '127.0.0.1',
              port = port,
            })
          else
            vim.notify('포트는 숫자여야 합니다.', vim.log.levels.ERROR)
          end
        end
      end)
    elseif vim.bo.filetype == 'python' then
      -- Python: 포트 입력 후 FastAPI 런치
      local default_port = get_last_debug_port('python', '8095')
      vim.ui.input({
        prompt = 'FastAPI Debug Port: ',
        default = default_port,
      }, function(input)
        if input and input ~= '' then
          local port = tonumber(input)
          if port then
            save_last_debug_port('python', tostring(port))
            dap.run({
              type = 'python',
              request = 'launch',
              name = 'FastAPI 디버깅 실행: ' .. port,
              module = 'uvicorn',
              args = {
                'main:app',
                '--reload',
                '--port',
                tostring(port),
                '--host',
                '0.0.0.0',
              },
              pythonPath = function()
                return os.getenv('VIRTUAL_ENV') and (os.getenv('VIRTUAL_ENV') .. '/bin/python') or 'python'
              end,
            })
          else
            vim.notify('포트는 숫자여야 합니다.', vim.log.levels.ERROR)
          end
        end
      end)
    else
      vim.notify(
        '현재 파일 타입('
          .. vim.bo.filetype
          .. ')은 attach/launch 디버깅을 지원하지 않습니다. (Java, Python만 지원)',
        vim.log.levels.WARN
      )
    end
  end
  _G.attach_debug = attach_debug

  -- 사용자 지정 DAP 단축키
  vim.keymap.set('n', '<leader>da', attach_debug, { desc = 'Attach/Launch Debug (Input Port)' })
  vim.keymap.set('n', '<leader>db', function()
    dap.toggle_breakpoint()
  end, { desc = 'Toggle Breakpoint' })
  vim.keymap.set('n', '<leader>dd', function()
    dap.continue()
  end, { desc = 'Run/Continue' })
  vim.keymap.set('n', '<leader>dc', function()
    dap.run_to_cursor()
  end, { desc = 'Run to Cursor' })
  vim.keymap.set('n', '<leader>de', function()
    dap.step_over()
  end, { desc = 'Step Over' })
  vim.keymap.set('n', '<leader>di', function()
    dap.step_into()
  end, { desc = 'Step Into' })
  vim.keymap.set('n', '<leader>do', function()
    dap.step_out()
  end, { desc = 'Step Out' })
  vim.keymap.set('n', '<leader>dr', function()
    dap.repl.toggle()
  end, { desc = 'Toggle REPL' })
  vim.keymap.set('n', '<leader>dt', function()
    dap.terminate()
  end, { desc = 'Terminate' })
end

-- ============================================================
-- [수동 ESLint 린터] <leader>l 로 실행, <leader>L 로 창 닫기
-- ============================================================
-- 평소에는 대용량 HTML 파일에서 ESLint 실시간 검사가 자동 비활성화되어 렉이 없습니다.
-- {{ Jinja2 }} 날것 문법, console 사용, 기타 JS 오류 등을 확인할 때만 수동으로 실행하세요.
-- ============================================================
-- [수동 ESLint 진단 네임스페이스 정의]
local eslint_ns = vim.api.nvim_create_namespace('manual_eslint')

local function run_manual_eslint()
  local bufnr = vim.api.nvim_get_current_buf()
  local file = vim.api.nvim_buf_get_name(bufnr)
  local ft = vim.bo.filetype

  if
    ft ~= 'javascript'
    and ft ~= 'javascriptreact'
    and ft ~= 'typescript'
    and ft ~= 'typescriptreact'
    and ft ~= 'html'
    and ft ~= 'vue'
  then
    vim.notify(
      'ESLint를 지원하지 않는 파일 형식입니다. (JS, TS, HTML, Vue 지원)\n현재 파일 형식: ' .. ft,
      vim.log.levels.WARN,
      { title = '수동 ESLint 린터' }
    )
    return
  end

  -- vscode-eslint-language-server가 참조하는 글로벌 eslint CLI의 절대 경로
  -- (_G.DEVTOOLS2_DIR은 심볼릭 링크까지 해석된 실제 절대경로: /var/opt/_devtools2 등)
  local eslint_bin = _G.DEVTOOLS2_DIR .. '/data/.npm-packages/lib/node_modules/.bin/eslint'
  local config_file = _G.DEVTOOLS2_DIR .. '/.config/eslint/eslint.config.mjs'

  -- eslint 바이너리가 존재하는지 미리 확인
  if vim.fn.filereadable(eslint_bin) == 0 then
    vim.notify(
      'ESLint 바이너리를 찾을 수 없습니다.\n예상 경로: ' .. eslint_bin,
      vim.log.levels.ERROR,
      { title = '수동 ESLint 린터 오류' }
    )
    return
  end

  local eslint_cmd = { eslint_bin, '--config', config_file, '--format', 'json', '--stdin', '--stdin-filename', file }

  vim.notify('⚡ ESLint 코드 분석 중...', vim.log.levels.INFO, { title = '수동 ESLint 린터', timeout = 2000 })

  local stdout_lines = {}
  local stderr_lines = {}
  
  -- 현재 버퍼의 전체 텍스트 가져오기
  local buffer_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local job_id = vim.fn.jobstart(eslint_cmd, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= '' then
            table.insert(stdout_lines, line)
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= '' then
            table.insert(stderr_lines, line)
          end
        end
      end
    end,
    on_exit = function(_, exit_code)
      local stdout_str = table.concat(stdout_lines, '\n')
      local ok_json, parsed = pcall(vim.json.decode, stdout_str)

      if not ok_json or type(parsed) ~= 'table' then
        if #stderr_lines > 0 then
          vim.notify(table.concat(stderr_lines, '\n'), vim.log.levels.ERROR, { title = 'ESLint 엔진 오류', timeout = 10000 })
        else
          vim.notify('ESLint 결과를 파싱할 수 없습니다:\n' .. stdout_str, vim.log.levels.ERROR, { title = 'ESLint 파싱 오류' })
        end
        return
      end

      -- 실행 시 이전 수동 진단 마킹을 초기화
      vim.diagnostic.reset(eslint_ns, bufnr)

      local qf_items = {}
      local diagnostics = {}

      for _, file_result in ipairs(parsed) do
        local filename = file_result.filePath
        if file_result.messages then
          for _, msg in ipairs(file_result.messages) do
            -- 포맷팅은 conform.nvim(Prettier)이 담당하므로, ESLint의 prettier 중복 경고는 무시합니다.
            if msg.ruleId ~= 'prettier/prettier' then
              local item_type = 'W'
              local d_severity = vim.diagnostic.severity.WARN
              if msg.severity == 2 then
                item_type = 'E'
                d_severity = vim.diagnostic.severity.ERROR
              end

              table.insert(qf_items, {
                filename = filename,
                lnum = msg.line or 1,
                col = msg.column or 1,
                text = string.format('[%s] %s', msg.ruleId or 'unknown', msg.message or ''),
                type = item_type,
              })

              local line_idx = (msg.line or 1) - 1
              local col_idx = (msg.column or 1) - 1
              local end_line_idx = msg.endLine and (msg.endLine - 1) or line_idx
              local end_col_idx = msg.endColumn and (msg.endColumn - 1) or col_idx

              table.insert(diagnostics, {
                lnum = line_idx,
                col = col_idx,
                end_lnum = end_line_idx,
                end_col = end_col_idx,
                severity = d_severity,
                message = string.format('[ESLint] %s (%s)', msg.message or '', msg.ruleId or 'unknown'),
                source = 'Manual ESLint',
              })
            end
          end
        end
      end

      if #qf_items == 0 then
        vim.fn.setqflist({}, 'r')
        vim.cmd('cclose')
        vim.notify('🎉 완벽합니다! JS 문법 오류나 스타일 위반이 없습니다.', vim.log.levels.INFO, { title = 'ESLint 분석 완료' })
        -- 확실하게 진단 마킹을 0개로 덮어쓰기하여 화면에 남은 에러를 지웁니다.
        vim.diagnostic.set(eslint_ns, bufnr, {})
        return
      end

      -- 코드 본문에 직접 진단 마킹 주입 (밑줄, 가상텍스트 렌더링)
      vim.diagnostic.set(eslint_ns, bufnr, diagnostics)

      -- Quickfix 목록에 등록 후 창 열기
      vim.fn.setqflist({}, 'r', {
        title = string.format('ESLint (%s)', vim.fn.fnamemodify(file, ':t')),
        items = qf_items,
      })
      vim.cmd('copen')
      
      vim.notify(
        string.format('⚠️  %d개의 JS 오류가 발견되었습니다. (목록에서 Enter로 해당 줄 이동)', #qf_items),
        vim.log.levels.WARN,
        { title = 'ESLint 분석 완료' }
      )
    end,
  })

  -- stdin으로 현재 버퍼 내용을 전송하여 디스크 저장 없이도 실시간 분석을 가능하게 합니다.
  if job_id > 0 then
    vim.fn.chansend(job_id, buffer_lines)
    vim.fn.chanclose(job_id, 'stdin')
  end
end

-- <leader>l : 수동 ESLint 실행 (비동기, Non-blocking)
-- <leader>L : 결과 창 닫기 및 진단 마킹 초기화
vim.keymap.set('n', '<leader>l', run_manual_eslint, { desc = 'ESLint: Run Manual Lint' })
vim.keymap.set('n', '<leader>L', function()
  vim.cmd('cclose')
  -- 모든 수동 린트 진단 마킹 초기화
  vim.diagnostic.reset(eslint_ns)
end, { desc = 'ESLint: Close Result Window & Clear Diagnostics' })

-- ============================================================
-- [유니코드 변환] <leader>\ 그룹
-- ============================================================
-- <leader>\a : 유니코드 디코딩  \uXXXX → 실제 문자  (예: \u00E0 → à)
-- <leader>\A : 유니코드 인코딩  실제 문자 → \uXXXX  (예: à → \u00E0)
-- ============================================================
vim.keymap.set('n', '<leader>\\a', function()
  -- \uXXXX 형식의 유니코드 이스케이프 시퀀스를 실제 유니코드 문자로 변환
  vim.cmd([[%s/\\u\([0-9a-fA-F]\{4\}\)/\=nr2char(str2nr(submatch(1), 16))/g]])
end, { desc = 'Unicode: Decode \\uXXXX → char (전체 버퍼)' })

vim.keymap.set('n', '<leader>\\A', function()
  -- ASCII 범위를 벗어난 문자(한글, 특수문자 등)를 \uXXXX 이스케이프 시퀀스로 변환
  vim.cmd([[%s/[^\x00-\x7F]/\=printf('\u%04X', char2nr(submatch(0)))/g]])
end, { desc = 'Unicode: Encode char → \\uXXXX (전체 버퍼)' })
