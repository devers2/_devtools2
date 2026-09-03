-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- 현재 위치의 시스템 탐색기 열기: <Leader>fE (File Explore)
vim.keymap.set('n', '<leader>fE', function()
  local path = vim.api.nvim_buf_get_name(0):match('(.*)[/\\]') or vim.fn.getcwd()
  vim.ui.open(path)
end, { desc = 'Open System Explorer' })

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
  -- save_last_debug_port와 동일하게 빈 내용 방어: 쓰기 도중 중단 등으로 파일이
  -- 0바이트인 경우 vim.json.decode('')가 에러를 던지는 것을 방지합니다.
  if not content or content == '' then
    return default_port
  end
  local ok, state = pcall(vim.json.decode, content)
  if not ok or type(state) ~= 'table' then
    return default_port
  end
  local cwd = vim.fn.getcwd()
  local cwd_state = state[cwd] or {}
  -- 자바의 경우 기존 last_debug_port 키 하위 호환 처리
  if ft == 'java' and cwd_state.last_debug_port and not cwd_state.last_java_port then
    return cwd_state.last_debug_port
  end
  return cwd_state['last_' .. ft .. '_port'] or default_port
end

local function save_last_debug_port(ft, port)
  vim.fn.mkdir(nvim_state_dir, 'p')
  local f_read = io.open(state_file, 'r')
  local state = {}
  if f_read then
    local content = f_read:read('*all')
    if content and content ~= '' then
      local ok_decode, decoded = pcall(vim.json.decode, content)
      if ok_decode and type(decoded) == 'table' then
        state = decoded
      end
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
  local dap = require('dap')
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
                local venv = os.getenv('VIRTUAL_ENV')
                if venv then
                  local win_py = venv .. '/Scripts/python.exe'
                  local unix_py = venv .. '/bin/python'
                  if vim.fn.filereadable(win_py) == 1 then
                    return win_py
                  elseif vim.fn.filereadable(unix_py) == 1 then
                    return unix_py
                  end
                end
                return 'python'
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

  -- 사용자 지정 DAP 단축키 (한글 설명 + 영문 원본 명칭)
  vim.keymap.set(
    'n',
    '<leader>da',
    attach_debug,
    { desc = '포트 지정 디버그 연결 (Attach/Launch Debug)' }
  )
  vim.keymap.set('n', '<leader>db', function()
    require('dap').toggle_breakpoint()
  end, { desc = '브레이크포인트 설정/해제 (Toggle Breakpoint)' })
  -- [스마트 디버그 실행 (<leader>dd)]
  -- 1. 활성 세션 존재 시: `dap.continue()` (다음 브레이크포인트까지 계속 실행)
  -- 2. 대시보드/초기 화면이면서 Java 프로젝트(.nvim.lua의 MAIN_CLASS 또는 build.gradle/pom.xml 존재)인 경우:
  --    자바 파일을 수동으로 열지 않아도 .nvim.lua의 MAIN_CLASS로 Spring Boot 디버깅을 즉시 런치합니다.
  -- 3. 그 외 모든 경우(파이썬, JS/TS, 일반 파일): 표준 `dap.continue()`로 직행하여 각 언어별 DAP 실행
  vim.keymap.set('n', '<leader>dd', function()
    local dap = require('dap')
    if dap.session() then
      dap.continue()
      return
    end

    local ft = vim.bo.filetype
    if ft == '' or ft == 'snacks_dashboard' or ft == 'alpha' or ft == 'dashboard' then
      -- 대시보드 화면인 경우: .nvim.lua의 MAIN_CLASS 또는 Java 프로젝트인지 확인
      ---@diagnostic disable-next-line: undefined-field
      if
        _G.MAIN_CLASS
        or vim.fn.filereadable('build.gradle') == 1
        or vim.fn.filereadable('pom.xml') == 1
      then
        dap.run({
          type = 'java',
          request = 'launch',
          name = 'Java Launch (Spring Boot)',
          ---@diagnostic disable-next-line: undefined-field
          mainClass = _G.MAIN_CLASS,
        })
        return
      end
    end

    dap.continue()
  end, { desc = '디버그 실행 / 계속 (Run/Continue)' })
  vim.keymap.set('n', '<leader>dc', function()
    require('dap').run_to_cursor()
  end, { desc = '커서 위치까지 실행 (Run to Cursor)' })
  vim.keymap.set('n', '<leader>de', function()
    require('dap').step_over()
  end, { desc = '다음 줄 실행 (Step Over)' })
  vim.keymap.set('n', '<leader>di', function()
    require('dap').step_into()
  end, { desc = '함수 내부 진입 (Step Into)' })
  vim.keymap.set('n', '<leader>do', function()
    require('dap').step_out()
  end, { desc = '함수 밖으로 탈출 (Step Out)' })
  vim.keymap.set('n', '<leader>dr', function()
    require('dap').repl.toggle()
  end, { desc = 'REPL 창 토글 (Toggle REPL)' })
  vim.keymap.set('n', '<leader>dt', function()
    require('dap').terminate()
  end, { desc = '디버깅 및 서버 종료 (Terminate)' })

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
      'ESLint를 지원하지 않는 파일 형식입니다. (JS, TS, HTML, Vue 지원)\n현재 파일 형식: '
        .. ft,
      vim.log.levels.WARN,
      { title = '수동 ESLint 린터' }
    )
    return
  end

  local is_win = _G.OS_TYPE == _G.OS.WINDOWS
  local eslint_bin
  if is_win then
    local win_cmd = _G.DEVTOOLS2_DIR .. '/data/.npm-packages/eslint.cmd'
    if vim.fn.filereadable(win_cmd) == 1 then
      eslint_bin = win_cmd
    else
      eslint_bin = _G.DEVTOOLS2_DIR .. '/data/.npm-packages/node_modules/.bin/eslint.cmd'
    end
  else
    eslint_bin = _G.DEVTOOLS2_DIR .. '/data/.npm-packages/lib/node_modules/.bin/eslint'
  end
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

  local eslint_cmd =
    { eslint_bin, '--config', config_file, '--format', 'json', '--stdin', '--stdin-filename', file }

  vim.notify(
    '⚡ ESLint 코드 분석 중...',
    vim.log.levels.INFO,
    { title = '수동 ESLint 린터', timeout = 2000 }
  )

  -- 현재 버퍼의 전체 텍스트 가져오기
  local buffer_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local input_text = table.concat(buffer_lines, '\n')

  vim.system(eslint_cmd, { stdin = input_text }, function(obj)
    local stdout_str = obj.stdout or ''
    local stderr_str = obj.stderr or ''

    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end

      local ok_json, parsed = pcall(vim.json.decode, stdout_str)

      if not ok_json or type(parsed) ~= 'table' then
        if #stderr_str > 0 then
          vim.notify(
            stderr_str,
            vim.log.levels.ERROR,
            { title = 'ESLint 엔진 오류', timeout = 10000 }
          )
        else
          vim.notify(
            'ESLint 결과를 파싱할 수 없습니다:\n' .. stdout_str,
            vim.log.levels.ERROR,
            { title = 'ESLint 파싱 오류' }
          )
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
                message = string.format(
                  '[ESLint] %s (%s)',
                  msg.message or '',
                  msg.ruleId or 'unknown'
                ),
                source = 'Manual ESLint',
              })
            end
          end
        end
      end

      if #qf_items == 0 then
        vim.fn.setqflist({}, 'r')
        vim.cmd.cclose()
        vim.notify(
          '🎉 완벽합니다! JS 문법 오류나 스타일 위반이 없습니다.',
          vim.log.levels.INFO,
          { title = 'ESLint 분석 완료' }
        )
        -- 확실하게 진단 마킹을 0개로 덮어쓰기하여 화면에 남은 에러를 지웁니다.
        vim.diagnostic.set(eslint_ns, bufnr, {})
        return
      end

      -- 코드 본문에 직접 진단 마킹 주입 (밑줄, 가상텍스트 렌더링)
      vim.diagnostic.set(eslint_ns, bufnr, diagnostics)

      -- Quickfix 목록에 등록 후 창 열기
      vim.fn.setqflist({}, 'r', {
        title = string.format('ESLint (%s)', file:match('([^/\\]+)$') or file),
        items = qf_items,
      })
      vim.cmd.copen()

      vim.notify(
        string.format(
          '⚠️  %d개의 JS 오류가 발견되었습니다. (목록에서 Enter로 해당 줄 이동)',
          #qf_items
        ),
        vim.log.levels.WARN,
        { title = 'ESLint 분석 완료' }
      )
    end)
  end)
end

-- <leader>l : 수동 ESLint 실행 (비동기, Non-blocking)
-- <leader>L : 결과 창 닫기 및 진단 마킹 초기화
vim.keymap.set('n', '<leader>l', run_manual_eslint, { desc = 'ESLint: Run Manual Lint' })
vim.keymap.set('n', '<leader>L', function()
  vim.cmd.cclose()
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
  local ok, _ = pcall(vim.cmd, [[%s/\\u\([0-9a-fA-F]\{4\}\)/\=nr2char(str2nr(submatch(1), 16))/ge]])
  if ok then
    vim.notify(
      '유니코드 디코딩이 완료되었습니다.',
      vim.log.levels.INFO,
      { title = '유니코드 변환' }
    )
  end
end, { desc = 'Unicode: Decode \\uXXXX → char (전체 버퍼)' })

vim.keymap.set('n', '<leader>\\A', function()
  -- ASCII 범위를 벗어난 문자(한글, 특수문자 등)를 \uXXXX 이스케이프 시퀀스로 변환
  local ok, _ = pcall(vim.cmd, [[%s/[^\x00-\x7F]/\=printf('\\u%04X', char2nr(submatch(0)))/ge]])
  if ok then
    vim.notify(
      '유니코드 인코딩이 완료되었습니다.',
      vim.log.levels.INFO,
      { title = '유니코드 변환' }
    )
  end
end, { desc = 'Unicode: Encode char → \\uXXXX (전체 버퍼)' })

-- =========================================================================
-- [스마트 Home 키: VS Code 스타일 토글 이동]
-- Home 키를 누를 때마다:
--   1) 코드 시작 지점(들여쓰기 끝, 첫 비공백 문자 ^)으로 이동
--   2) 이미 코드 시작 지점에 있으면 줄 맨 앞(0)으로 이동
--   3) 다시 누르면 코드 시작 지점으로 토글 반복
-- 노멀(n), 비주얼(v), 인서트(i) 모드 모두 지원
-- =========================================================================
local function smart_home()
  local col = vim.fn.col('.')
  local line = vim.api.nvim_get_current_line()
  local first_non_blank = line:find('%S')
  if not first_non_blank or col == first_non_blank then
    return '0'
  else
    return '^'
  end
end

-- 노멀, 비주얼 모드
vim.keymap.set(
  { 'n', 'v' },
  '<Home>',
  smart_home,
  { expr = true, silent = true, desc = '스마트 Home (코드 시작 ↔ 줄 맨 앞 토글)' }
)

-- 인서트 모드
vim.keymap.set('i', '<Home>', function()
  local pos = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_get_current_line()
  local first_non_blank = line:find('%S')
  local target_col = 0
  if first_non_blank and pos[2] ~= (first_non_blank - 1) then
    target_col = first_non_blank - 1
  else
    target_col = 0
  end
  vim.api.nvim_win_set_cursor(0, { pos[1], target_col })
end, { silent = true, desc = '스마트 Home (코드 시작 ↔ 줄 맨 앞 토글)' })
