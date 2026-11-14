-- WSL 클립보드 제공자 (win32yank) — 복사는 비동기, 붙여넣기는 캐시 우선
--
-- [왜 필요한가]
--   win32yank.exe 는 Windows 프로세스라 WSL 에서 한 번 띄우는 데 약 0.2초가 걸립니다(실측 5회 1.05초).
--   명령 문자열 방식(vim.g.clipboard 의 copy/paste 에 명령 + cache_enabled = 0)은 복사·붙여넣기 모두
--   Neovim 이 결과를 기다리는 동기 실행이라, clipboard=unnamedplus 에서 y·p·d 할 때마다 0.2초씩 멈추고
--   :g/…/d 같은 반복 삭제는 줄마다 win32yank 를 띄웠습니다.
--
-- [동작]
--   ● 복사: 내용을 캐시에 넣고 win32yank -i 는 백그라운드로 실행 (기다리지 않음)
--   ● 붙여넣기: 캐시가 유효하면 바로 돌려주고, 아니면 win32yank -o 를 실행해 읽은 뒤 캐시에 넣음
--   ● Neovim 이 포커스를 잃으면(다른 앱에서 복사했을 수 있음) 캐시를 버리고, 포커스를 다시 얻으면
--     Windows 클립보드를 백그라운드로 다시 읽어 캐시를 채웁니다.
--   ● 안전장치: 포커스 이벤트(FocusLost/FocusGained)를 한 번이라도 받은 뒤에만 캐시를 믿습니다.
--     포커스 알림을 보내지 않는 터미널에서는 예전처럼 붙여넣기마다 Windows 클립보드를 읽습니다
--     (그래야 Windows 에서 새로 복사한 내용 대신 옛 내용이 붙여넣어지는 일이 없음).
local M = {}

local cache = nil -- { lines = {...} } — 유효한 캐시가 없으면 nil
local focus_seen = false -- 이 세션에서 포커스 이벤트를 받은 적이 있는지
local refresh_seq = 0 -- 늦게 도착한 백그라운드 읽기 결과가 새 상태를 덮지 않게 하는 순번

local function split_lines(out)
  return vim.split(out or '', '\n', { plain = true })
end

---@param exe string win32yank.exe 경로
function M.setup(exe)
  local function read_sync()
    local res = vim.system({ exe, '-o', '--lf' }, { text = true }):wait()
    if res.code ~= 0 then
      return nil
    end
    return split_lines(res.stdout)
  end

  local function refresh_async()
    refresh_seq = refresh_seq + 1
    local my_seq = refresh_seq
    vim.system({ exe, '-o', '--lf' }, { text = true }, function(res)
      vim.schedule(function()
        -- 그 사이 복사·포커스 변화가 있었으면 이 결과는 버림
        if my_seq == refresh_seq and res.code == 0 then
          cache = { lines = split_lines(res.stdout) }
        end
      end)
    end)
  end

  local function copy(lines, _regtype)
    refresh_seq = refresh_seq + 1 -- 진행 중인 백그라운드 읽기 결과 무효화
    cache = { lines = vim.deepcopy(lines) }
    -- 줄 단위(V) 복사는 Neovim 이 끝에 빈 줄('')을 붙여 넘겨주므로 그대로 이으면 끝 줄바꿈이 됨
    -- (명령 방식이 systemlist 로 넘기던 것과 같은 결과 — 실측 비교)
    vim.system({ exe, '-i', '--crlf' }, { stdin = table.concat(lines, '\n') })
  end

  local function paste()
    if focus_seen and cache then
      return vim.deepcopy(cache.lines)
    end
    local lines = read_sync()
    if lines then
      cache = { lines = vim.deepcopy(lines) }
      return lines
    end
    return cache and vim.deepcopy(cache.lines) or { '' }
  end

  vim.g.clipboard = {
    name = 'win32yank-wsl (cached)',
    copy = { ['+'] = copy, ['*'] = copy },
    paste = { ['+'] = paste, ['*'] = paste },
  }

  local group = vim.api.nvim_create_augroup('Dt2WslClipboard', { clear = true })
  vim.api.nvim_create_autocmd('FocusLost', {
    group = group,
    callback = function()
      focus_seen = true
      refresh_seq = refresh_seq + 1
      cache = nil
    end,
  })
  vim.api.nvim_create_autocmd('FocusGained', {
    group = group,
    callback = function()
      focus_seen = true
      cache = nil
      refresh_async()
    end,
  })
end

-- 시험용
M._state = function()
  return { cache = cache, focus_seen = focus_seen }
end

return M
