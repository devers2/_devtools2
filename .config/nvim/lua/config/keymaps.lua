-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- 현재 위치의 시스템 탐색기 열기: <Leader>fE (File Explore)
vim.keymap.set('n', '<leader>fE', function()
  local path = vim.api.nvim_buf_get_name(0):match('(.*)[/\\]') or vim.fn.getcwd()
  vim.ui.open(path)
end, { desc = 'Open System Explorer' })

-- 프로젝트별 상태 관리를 위한 파일 경로 설정 (~/.nvim/state.json)
local nvim_state_dir = _G.HOME_DIR .. '/.nvim'
local state_file = nvim_state_dir .. '/state.json'

-- 디렉토리 생성
vim.fn.mkdir(nvim_state_dir, 'p')

-- state.json 안전 읽기 헬퍼
local function read_state()
  local f = io.open(state_file, 'r')
  if not f then
    return {}
  end
  local content = f:read('*all')
  f:close()
  if not content or content == '' then
    return {}
  end
  local ok, decoded = pcall(vim.json.decode, content)
  return (ok and type(decoded) == 'table') and decoded or {}
end

-- 프로젝트(디렉토리)별 마지막 사용 어태치 포트 읽기/쓰기 (디스크 영구 보존)
local function get_last_attach_port(lang, default_port)
  local state = read_state()
  local cwd = vim.fn.getcwd():gsub('\\', '/'):gsub('/+$', '')
  local cwd_state = state[cwd] or {}
  -- 신규 attach_<lang>_port 우선, 기존 last_<lang>_port 하위 호환
  return cwd_state['attach_' .. lang .. '_port']
    or cwd_state['last_' .. lang .. '_port']
    or (lang == 'java' and cwd_state.last_debug_port)
    or default_port
end

local function save_last_attach_port(lang, port)
  vim.fn.mkdir(nvim_state_dir, 'p')
  local state = read_state()
  local cwd = vim.fn.getcwd():gsub('\\', '/'):gsub('/+$', '')
  state[cwd] = state[cwd] or {}
  state[cwd]['attach_' .. lang .. '_port'] = port
  local f_write = io.open(state_file, 'w')
  if f_write then
    f_write:write(vim.json.encode(state))
    f_write:close()
  end
end

-- 5대 메이저 언어별 표준 어태치(Attach) 사양 정의
local ATTACH_SPECS = {
  java = {
    name = 'Java',
    port = '5005',
    prompt = 'Java Debug Port (JDWP): ',
    build = function(port)
      return {
        type = 'java',
        request = 'attach',
        name = 'Java Attach: ' .. port,
        hostName = '127.0.0.1',
        port = port,
      }
    end,
  },
  python = {
    name = 'Python',
    port = '5678',
    prompt = 'Python Debug Port (debugpy): ',
    build = function(port)
      return {
        type = 'debugpy',
        request = 'attach',
        name = 'Python Attach: ' .. port,
        connect = { host = '127.0.0.1', port = port },
        host = '127.0.0.1',
        port = port,
      }
    end,
  },
  node = {
    name = 'Node.js',
    port = '9229',
    prompt = 'Node.js Debug Port (V8 Inspector): ',
    build = function(port)
      return {
        type = 'node',
        request = 'attach',
        name = 'Node.js Attach: ' .. port,
        address = '127.0.0.1',
        port = port,
        cwd = '${workspaceFolder}',
        restart = true,
      }
    end,
  },
  go = {
    name = 'Go',
    port = '2345',
    prompt = 'Go Debug Port (Delve): ',
    build = function(port)
      return {
        type = 'go',
        request = 'attach',
        name = 'Go Attach: ' .. port,
        mode = 'remote',
        host = '127.0.0.1',
        port = port,
      }
    end,
  },
  rust = {
    name = 'Rust',
    port = '13000',
    prompt = 'Rust Debug Port (CodeLLDB): ',
    build = function(port)
      return {
        type = 'lldb',
        request = 'attach',
        name = 'Rust Attach: ' .. port,
        host = '127.0.0.1',
        port = port,
        stopOnEntry = false,
      }
    end,
  },
}

-- 5대 메이저 언어 통합 순수 어태치(Attach) 실행 함수 (<leader>da)
local function attach_debug()
  local dap = require('dap')
  local dap_scaffold = require('util.dap_scaffold')
  local detected_lang = dap_scaffold.detect_project_type()

  local function proceed_attach(lang)
    local spec = ATTACH_SPECS[lang]
    if not spec then
      vim.notify('지원하지 않는 언어입니다: ' .. tostring(lang), vim.log.levels.WARN, { title = 'DAP Attach' })
      return
    end

    local default_port = get_last_attach_port(lang, spec.port)
    vim.ui.input({
      prompt = spec.prompt,
      default = default_port,
    }, function(input)
      if not input or input == '' then
        return
      end
      local port = tonumber(vim.trim(input))
      if port and port >= 1 and port <= 65535 then
        save_last_attach_port(lang, tostring(port))
        local config = spec.build(port)
        dap.run(config)
      else
        vim.notify('포트는 1부터 65535 사이의 유효한 숫자여야 합니다.', vim.log.levels.ERROR, { title = 'DAP Attach' })
      end
    end)
  end

  if detected_lang then
    proceed_attach(detected_lang)
  else
    vim.ui.select({
      '1. Java (JDWP 5005)',
      '2. Python (debugpy 5678)',
      '3. Node.js (Inspector 9229)',
      '4. Go (Delve 2345)',
      '5. Rust (CodeLLDB 13000)',
    }, {
      prompt = '어태치할 디버그 대상 언어를 선택해 주세요: ',
    }, function(choice)
      if not choice then
        return
      end
      local lang = 'java'
      if choice:find('Java') then
        lang = 'java'
      elseif choice:find('Python') then
        lang = 'python'
      elseif choice:find('Node') then
        lang = 'node'
      elseif choice:find('Go') then
        lang = 'go'
      elseif choice:find('Rust') then
        lang = 'rust'
      end
      proceed_attach(lang)
    end)
  end
end
_G.attach_debug = attach_debug

-- DAP 단축키는 lazy-loading 시점 충돌 방지 및 일관성을 위해 lua/plugins/dap.lua 의 keys 스펙에서 관리합니다.

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
-- <leader>\a : 유니코드 디코딩  \uXXXX → 실제 문자  (예: \u00E0 → à, \uC804 → 전)
-- <leader>\A : 유니코드 인코딩  실제 문자 → \uXXXX  (예: à → \u00E0, 전 → \uC804)
-- ============================================================
-- ⚠️ [유지보수 가이드 및 주의사항]
-- 1. 운영체제(OS) 호환성:
--    - Vim Ex 명령(:%s/...) 대신 nvim_buf_get_lines / nvim_buf_set_lines를 사용합니다.
--    - 줄바꿈 문자(Windows의 CRLF, Linux/macOS의 LF)가 Lua 테이블의 각 줄로 자동 분리되어
--      OS별 개행 차이나 vim cmd 이스케이프 계층에 구애받지 않고 100% 동일하게 동작합니다.
-- 2. 백슬래시(\) 보존 원칙:
--    - `C:\경로\파일.txt`처럼 경로 구분자(\) 바로 뒤에 비ASCII 문자가 오는 경우,
--      인코드 시 `C:\\uACBD...`가 되며 디코드 시 원래의 `C:\경로...`로 완벽 복원되어야 합니다.
--    - 따라서 `\\u`를 `\u`로 강제 축약(normalize)하는 코드를 절대 추가하지 마세요!
--      (강제 축약 시 `C:\경로`의 `\`가 제거되어 `C:경로`가 되는 치명적인 버그가 발생함)
-- 3. 유니코드 이스케이프 포맷(\uXXXX) 원칙:
--    - 표준 유니코드 이스케이프 \u는 엄격히 16진수 4자리(%x%x%x%x)입니다.
--    - 5자리 이상을 허용하면 `\uAC00FF`('가' + 'FF')처럼 뒤에 16진수 알파벳이 이어지는 일반 텍스트가 깨집니다.
--    - U+FFFF를 초과하는 문자(이모지 등)는 JSON/JS/Java 표준인 UTF-16 서로게이트 페어(\uD83D\uDE80)로
--      인코드/디코드하여 모든 텍스트 및 이모지를 손실 없이 처리합니다.
-- ============================================================

-- UTF-16 서로게이트 페어 헬퍼 함수 (이모지 등 U+10000 ~ U+10FFFF 문자 지원)
local function to_surrogates(cp)
  cp = cp - 0x10000
  local high = 0xD800 + math.floor(cp / 0x400)
  local low = 0xDC00 + (cp % 0x400)
  return high, low
end

local function from_surrogates(high, low)
  return 0x10000 + (high - 0xD800) * 0x400 + (low - 0xDC00)
end

vim.keymap.set('n', '<leader>\\a', function()
  -- \uXXXX 형식의 유니코드 이스케이프를 실제 유니코드 문자로 변환
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local changed = false

  for i, line in ipairs(lines) do
    -- 1. UTF-16 서로게이트 페어 디코딩 (\uD800~\uDBFF 뒤에 \uDC00~\uDFFF 연속 등장 시 결합)
    local decoded = line:gsub('\\u([dD][89a-bA-B]%x%x)\\u([dD][c-fC-F]%x%x)', function(h_hex, l_hex)
      local high = tonumber(h_hex, 16)
      local low = tonumber(l_hex, 16)
      return vim.fn.nr2char(from_surrogates(high, low))
    end)
    -- 2. 표준 BMP \uXXXX (4자리 16진수) 디코딩
    decoded = decoded:gsub('\\u(%x%x%x%x)', function(hex)
      return vim.fn.nr2char(tonumber(hex, 16))
    end)

    if decoded ~= line then
      lines[i] = decoded
      changed = true
    end
  end

  if changed then
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  end

  vim.notify(
    changed and '유니코드 디코딩이 완료되었습니다.' or '변환할 유니코드 이스케이프가 없습니다.',
    vim.log.levels.INFO,
    { title = '유니코드 변환' }
  )
end, { desc = 'Unicode: Decode \\uXXXX → char (전체 버퍼)' })

vim.keymap.set('n', '<leader>\\A', function()
  -- ASCII 범위를 벗어난 문자(한글, 특수문자, 이모지 등)를 \uXXXX 이스케이프 시퀀스로 변환
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local changed = false

  for i, line in ipairs(lines) do
    local result = {}
    local pos = 1
    local len = #line

    while pos <= len do
      local byte = line:byte(pos)
      if byte < 0x80 then
        -- ASCII 문자(0x00~0x7F, 일반 영문, 숫자, 백슬래시 등): 그대로 유지
        table.insert(result, line:sub(pos, pos))
        pos = pos + 1
      else
        -- 비ASCII 문자: UTF-8 코드포인트 추출 후 \uXXXX 시퀀스로 변환
        local codepoint = vim.fn.char2nr(line:sub(pos))
        local char = vim.fn.nr2char(codepoint)
        if codepoint > 0xFFFF then
          -- U+FFFF 초과 문자(이모지 등): 표준 UTF-16 서로게이트 페어 2쌍(\uXXXX\uXXXX)으로 인코딩
          local high, low = to_surrogates(codepoint)
          table.insert(result, string.format('\\u%04X\\u%04X', high, low))
        else
          -- 일반 BMP 문자(한글, CJK, 라틴 확장 등): 표준 4자리 \uXXXX로 인코딩
          table.insert(result, string.format('\\u%04X', codepoint))
        end
        pos = pos + #char
        changed = true
      end
    end

    lines[i] = table.concat(result)
  end

  if changed then
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  end

  vim.notify(
    changed and '유니코드 인코딩이 완료되었습니다.' or '변환할 비ASCII 문자가 없습니다.',
    vim.log.levels.INFO,
    { title = '유니코드 변환' }
  )
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
