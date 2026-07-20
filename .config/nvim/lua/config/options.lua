-- [성능 최적화] 대용량 파일 기준 임계값 정의
_G.MAX_FILE_SIZE_COMPLEX = 200 * 1024 -- 복합 언어 템플릿용 (HTML, Django/Jinja, Vue, Svelte, Astro, PHP, JSP 등)
_G.MAX_FILE_SIZE_SINGLE = 500 * 1024  -- 단일 소스 코드용 (Java, Python, JS, TS 등)

-- 복합 언어 템플릿 파일타입 목록 (자바/스프링, 파이썬, Node/Frontend 관련 포함)
_G.COMPLEX_FILETYPES = {
  html = true,
  htmldjango = true,
  vue = true,
  svelte = true,
  astro = true,
  php = true,
  jsp = true,
  jinja = true,
  jinja2 = true,
  twig = true,
  handlebars = true,
  hbs = true,
  blade = true,
  xhtml = true,
  xml = true, -- Java Spring XML 설정 등을 위해 포함
}

-- 복합 언어 템플릿 파일 확장자 목록 (파일타입 감지 전 시점 대응)
_G.COMPLEX_EXTENSIONS = {
  html = true,
  htm = true,
  xhtml = true,
  jsp = true,
  asp = true,
  aspx = true,
  php = true,
  vue = true,
  svelte = true,
  astro = true,
  twig = true,
  jinja = true,
  jinja2 = true,
  j2 = true,
  hbs = true,
  handlebars = true,
  mustache = true,
  ejs = true,
  blade = true,
  xml = true,
}

-- 버퍼 번호 또는 파일 경로에 따라 적절한 최대 파일 제한 크기(Byte)를 반환하는 함수
_G.get_max_file_size = function(buf_or_path)
  local filetype = ""
  local ext = ""

  if type(buf_or_path) == "number" then
    if vim.api.nvim_buf_is_valid(buf_or_path) then
      filetype = vim.bo[buf_or_path].filetype or ""
      local fname = vim.api.nvim_buf_get_name(buf_or_path)
      ext = vim.fn.fnamemodify(fname, ":e"):lower()
    end
  elseif type(buf_or_path) == "string" then
    ext = vim.fn.fnamemodify(buf_or_path, ":e"):lower()
  end

  local is_complex = _G.COMPLEX_FILETYPES[filetype] or _G.COMPLEX_EXTENSIONS[ext]
  if is_complex then
    return _G.MAX_FILE_SIZE_COMPLEX
  else
    return _G.MAX_FILE_SIZE_SINGLE
  end
end

-- 기존 코드 호환성용 폴백 정의
_G.MAX_FILE_SIZE = _G.MAX_FILE_SIZE_SINGLE

-- 캐시 경로 설정 (전역 변수 _G.NVIM_CACHE_DIR 사용)
vim.opt.undodir = _G.NVIM_CACHE_DIR .. '/undo'
vim.opt.directory = _G.NVIM_CACHE_DIR .. '/swp'

-- 불필요한 스왑 파일 충돌 경고(W325 등 ATTENTION 메시지) 화면에 띄우지 않기
vim.opt.shortmess:append('A')

-- JDTLS, Copilot 등 구동 시 발생하는 정상적인 stderr 알림들이 에러로 로그에 계속 쌓이는 현상 방지 (경고 이상의 중요한 에러만 기록)
if vim.lsp.log then
  vim.lsp.log.set_level('WARN')
else
  ---@diagnostic disable-next-line: deprecated
  local legacy_func = vim.lsp['set_log_level']
  if legacy_func then
    legacy_func('WARN')
  end
end

-- 마우스 지원 활성화 (IDE와 유사한 경험 제공)
vim.opt.mouse = 'a'

-- 탭 설정 (Java 표준 4칸 설정)
vim.opt.shiftwidth = 4
vim.opt.tabstop = 4
vim.opt.expandtab = true

--[[
- 단축키 시퀀스 대기 시간 설정 (기본값 1000ms -> 300ms)
- <Leader>(Space) 키를 눌렀을 때 which-key 메뉴가 더 빨리 나타나도록 함
- 아래와 같은 경우 다시 기본값(1000ms)으로 되돌리는 것을 검토
  1) 원격 서버(SSH) 접속 시 네트워크가 불안정하여 단축키 인식이 잘 안되는 경우
  2) 메뉴에 등록되지 않은 수동 단축키가 있어 해당 시간내에 단축키 입력이 잘 안되어 끊기는 경우
--]]
vim.o.timeoutlen = 500

-- 단축키 조합 타임아웃 적용 여부
vim.o.timeout = true
-- 단축키 조합 대기 시간
vim.o.timeoutlen = 300
-- 터미널이 네오빔으로 보내는 키 코드 이스케이프 시퀀스 대기 시간
vim.o.ttimeoutlen = 0

-- 시스템 클립보드와 연동 (OS의 클립보드 도구를 자동으로 감지하여 사용)
if vim.fn.has('wsl') == 1 then
  if vim.fn.executable('win32yank.exe') == 1 then
    vim.g.clipboard = {
      name = 'win32yank-wsl',
      copy = {
        ['+'] = 'win32yank.exe -i --crlf',
        ['*'] = 'win32yank.exe -i --crlf',
      },
      paste = {
        ['+'] = 'win32yank.exe -o --lf',
        ['*'] = 'win32yank.exe -o --lf',
      },
      cache_enabled = 0,
    }
  else
    vim.g.clipboard = {
      name = 'powershell-wsl',
      copy = {
        ['+'] = 'clip.exe',
        ['*'] = 'clip.exe',
      },
      paste = {
        ['+'] = [[powershell.exe -NoProfile -Command "[Console]::Out.Write(([string](Get-Clipboard -Raw)).Replace([string][char]13, ''))"]],
        ['*'] = [[powershell.exe -NoProfile -Command "[Console]::Out.Write(([string](Get-Clipboard -Raw)).Replace([string][char]13, ''))"]],
      },
      cache_enabled = 0,
    }
  end
end
vim.opt.clipboard = 'unnamedplus'

-- 포커스를 잃거나(FocusLost), 버퍼를 떠나거나(BufLeave), 입력 모드를 나갈 때(InsertLeave) 자동 저장
-- (인텔리제이처럼 수정 즉시 또는 창을 옮길 때 확실하게 저장되도록 이벤트를 보강)
vim.api.nvim_create_autocmd({ 'FocusLost', 'BufLeave', 'InsertLeave' }, {
  group = vim.api.nvim_create_augroup('IntelliJAutoSave', { clear = true }),
  callback = function()
    -- 버퍼가 수정되었고, 일반 파일 버퍼(buftype이 빈값)인 경우에만 실행
    if vim.bo.modified and vim.bo.buftype == '' then
      -- 인서트 모드 도중이 아닐 때만 안전하게 저장 (타이핑 끊김 방지)
      local mode = vim.api.nvim_get_mode().mode
      if mode ~= 'i' and mode ~= 'R' then
        vim.cmd('silent! update') -- 변경 사항이 있을 때만 파일 저장 (wall 대신 현재 버퍼 안전 저장)
      end
    end
  end,
})

-- 한글 주석 색상 깨짐(무지개색) 방지: Neovim 영어 맞춤법 검사기 끄기
-- (기본적으로 켜져있어 한글을 오타로 인식하고 형형색색의 에러 폰트로 렌더링함을 방지)
vim.opt.spell = false

-- ============================================================
-- [다국어(한/영, 한자, 일어 등) 입력 전환 안내 알림]
-- 일반(Normal) 및 비주얼(Visual) 모드에서 영문이나 단축키용 특수문자가 아닌
-- 다국어 문자(한글, 한자, 일어 등)를 쳤을 때 안내 메시지를 띄웁니다.
-- ============================================================
vim.on_key(function(key)
  -- Neovim 내부에서 마우스 클릭이나 방향키 등은 K_SPECIAL(128, 0x80) 코드로 처리됩니다.
  -- 실제 UTF-8 기반 다국어 텍스트(한/중/일 등)는 무조건 첫 바이트가 192(0xC0) 이상입니다.
  -- 따라서 192 이상일 때만 감지하면 방향키나 마우스 스크롤 등의 영문 모드 조작을 완벽하게 무시합니다!
  if key and #key > 0 and string.byte(key, 1) >= 192 then
    local mode = vim.api.nvim_get_mode().mode
    -- i(Insert), c(Command) 등 텍스트를 직접 입력하는 모드가 아닐 때만 작동
    if mode == 'n' or mode == 'v' or mode == 'V' or mode == '\22' then
      local now = vim.uv.now()
      -- 알림 도배 방지 (2초에 한 번만 안내)
      if not _G.__last_lang_warn or (now - _G.__last_lang_warn) > 2000 then
        _G.__last_lang_warn = now
        vim.schedule(function()
          vim.notify(
            '일반 모드에서는 영문 단축키만 지원합니다.\n입력 언어(한/영 등)를 전환해 주세요.',
            vim.log.levels.WARN,
            { title = '입력 모드 경고' }
          )
        end)
      end
    end
  end
end)

-- Diagnostic 설정 (LSP 실시간 에러 가상 텍스트 표시)
vim.diagnostic.config({
  virtual_text = {
    spacing = 4,
    source = 'if_many',
    prefix = '●',
  },
  severity_sort = true,
  signs = true,
  underline = true,
  update_in_insert = false, -- [성능 최적화] 타이핑 중(Insert 모드) 실시간 에러 갱신 및 렌더링 차단 (Insert 모드 탈출 시 갱신)
})

-- ============================================================
-- [Python 웹 프로젝트 HTML 파일 → htmldjango 자동 감지]
-- vim.filetype.add()는 Neovim의 filetype 감지 단계에서 실행됩니다.
-- 즉, LSP(ESLint 등)가 attach되기 전에 filetype이 결정되므로
-- ESLint가 Django/Flask 템플릿 파일에 붙지 않습니다.
--
-- 감지 우선순위:
--   1) Django:        manage.py / wsgi.py / asgi.py 존재
--   2) Flask/FastAPI: requirements.txt / pyproject.toml / Pipfile 존재
--   3) 그 외:         nil 반환 → Neovim 기본 html 감지 유지 (Spring 등)
-- ============================================================
vim.filetype.add({
  extension = {
    html = function(path, _)
      local file_dir = vim.fs.dirname(path)

      -- 1) Django 프로젝트 감지
      local django_markers = { 'manage.py', 'wsgi.py', 'asgi.py' }
      for _, marker in ipairs(django_markers) do
        local result = vim.fs.find(marker, { path = file_dir, upward = true, limit = 1 })
        if #result > 0 then
          return 'htmldjango'
        end
      end

      -- 2) Flask / FastAPI 등 Python 웹 프로젝트 감지
      local python_markers = { 'requirements.txt', 'pyproject.toml', 'Pipfile' }
      for _, marker in ipairs(python_markers) do
        local result = vim.fs.find(marker, { path = file_dir, upward = true, limit = 1 })
        if #result > 0 then
          return 'htmldjango'
        end
      end

      -- 3) 매칭 없음: 기본 filetype 감지로 fallback (html → Spring Thymeleaf 등)
      return nil
    end,
  },
})

-- ============================================================
-- [버퍼 탭 데신크 방지 — 창 관리 최적화]
--
-- 증상: Explorer / 사이드바 창이 포커스된 상태에서
--   1) bufferline 탭 클릭 → 잘못된 창(Explorer)에서 버퍼 전환 → 탭 내용 불일치
--   2) <leader><space> 로 파일 열기 → 탭만 생기고 내용은 기존 파일 표시
--
-- 원인:
--   - bufferline의 left_mouse_command = "buffer %d"가 현재 포커스 창에서 실행됨
--   - Snacks 피커가 열릴 때 Explorer를 "복귀 창"으로 기억 → 파일을 Explorer 창에서 열려고 시도
--
-- 해결 (3단계 방어):
--   1) find_editor_win() 전역 헬퍼: 항상 유효한 에디터 창을 찾아 반환
--   2) winfixbuf (Neovim 0.10+): 사이드바 창이 일반 파일 버퍼 전환을 OS 수준에서 차단
--   3) BufWinEnter 리다이렉트: winfixbuf 없거나 우회된 경우 즉시 에디터 창으로 이동
-- ============================================================

-- 사이드바 / 특수 창으로 분류할 파일타입 집합
local _sidebar_fts = {
  snacks_explorer  = true,
  snacks_picker_list = true,
  ['neo-tree']     = true,
  NvimTree         = true,
  trouble          = true,
  Trouble          = true,
  undotree         = true,
  DiffviewFiles    = true,
  qf               = true,
}

-- 유효한 에디터 창인지 확인 (전역 제공)
_G.is_editor_win = function(win)
  if not win or not vim.api.nvim_win_is_valid(win) then return false end
  local buf = vim.api.nvim_win_get_buf(win)
  if not vim.api.nvim_buf_is_valid(buf) then return false end
  local ft = vim.bo[buf].filetype
  local bt = vim.bo[buf].buftype
  -- floating 창은 에디터 창으로 취급하지 않음
  local cfg = vim.api.nvim_win_get_config(win)
  if cfg.relative ~= '' then return false end
  return bt == '' and not _sidebar_fts[ft]
end

-- 현재 탭에서 유효한 에디터 창을 찾는 함수 (전역 제공)
local _last_editor_win = nil
_G.find_editor_win = function()
  -- 마지막으로 포커스했던 에디터 창이 여전히 유효하면 우선 반환
  if _last_editor_win and _G.is_editor_win(_last_editor_win) then
    return _last_editor_win
  end
  -- 현재 탭의 모든 창을 순회하여 첫 번째 유효한 에디터 창 반환
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if _G.is_editor_win(win) then
      return win
    end
  end
  return nil
end

-- [추적] 마지막으로 포커스된 유효한 에디터 창을 기억
vim.api.nvim_create_autocmd('WinLeave', {
  group = vim.api.nvim_create_augroup('TrackLastEditorWin', { clear = true }),
  callback = function()
    local win = vim.api.nvim_get_current_win()
    if _G.is_editor_win(win) then
      _last_editor_win = win
    end
  end,
})

-- [Fix 1] winfixbuf: Neovim 0.10+ 에서 사이드바/비floating 특수 창의 버퍼 전환 차단
-- 이 옵션이 있으면 해당 창에서 :buffer N 이 거부되므로,
-- bufferline이 실수로 Explorer 창을 대상으로 클릭 명령을 실행해도 아무 일도 일어나지 않습니다.
if vim.fn.has('nvim-0.10') == 1 then
  vim.api.nvim_create_autocmd('FileType', {
    group = vim.api.nvim_create_augroup('SidebarWinfixbuf', { clear = true }),
    pattern = vim.tbl_keys(_sidebar_fts),
    callback = function()
      local win = vim.api.nvim_get_current_win()
      local cfg = vim.api.nvim_win_get_config(win)
      -- floating 창(Snacks 팝업 피커)에는 적용하지 않음
      if cfg.relative == '' then
        pcall(function() vim.opt_local.winfixbuf = true end)
      end
    end,
  })
end

-- [Fix 2] BufWinEnter 리다이렉트: winfixbuf가 없거나 우회된 경우의 최후 방어선
-- 사이드바/특수 창에 일반 파일 버퍼가 진입하면 마지막 에디터 창으로 즉시 이동시킵니다.
local _redirecting = false
vim.api.nvim_create_autocmd('BufWinEnter', {
  group = vim.api.nvim_create_augroup('RedirectFromSidebar', { clear = true }),
  callback = function(args)
    if _redirecting then return end

    local buf = args.buf
    local win = vim.api.nvim_get_current_win()
    local bt  = vim.bo[buf].buftype
    local ft  = vim.bo[buf].filetype

    -- 일반 파일 버퍼가 아니면 무시
    if bt ~= '' or _sidebar_fts[ft] or ft == '' then return end
    -- 현재 창이 유효한 에디터 창이면 무시
    if _G.is_editor_win(win) then return end
    -- floating 창이면 무시 (Snacks 팝업 피커 미리보기 등)
    local cfg = vim.api.nvim_win_get_config(win)
    if cfg.relative ~= '' then return end

    -- 유효한 에디터 창으로 리다이렉트
    local editor_win = _G.find_editor_win()
    if not editor_win or editor_win == win then return end

    _redirecting = true
    vim.schedule(function()
      if vim.api.nvim_win_is_valid(editor_win) and vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_win_set_buf(editor_win, buf)
        vim.api.nvim_set_current_win(editor_win)
      end
      _redirecting = false
    end)
  end,
})
