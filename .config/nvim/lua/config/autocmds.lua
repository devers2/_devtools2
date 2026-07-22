-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- LazyVim의 기본 맞춤법 검사(spell) 자동 활성화 그룹 삭제
pcall(vim.api.nvim_del_augroup_by_name, 'lazyvim_wrap_spell')

-- 마크다운 파일에서 맞춤법 검사(spell) 강제 비활성화
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'markdown',
  callback = function()
    vim.opt_local.spell = false
  end,
})

-- HTML, JS, TS, CSS 등 특정 파일에서만 들여쓰기를 2칸으로 설정
vim.api.nvim_create_autocmd('FileType', {
  pattern = {
    'html',
    'javascript',
    'typescript',
    'css',
    'scss',
    'xml',
    'json',
    'jsonc',
    'yaml',
    'lua',
    'markdown',
  },
  callback = function()
    vim.opt_local.shiftwidth = 2 -- >> 또는 << 시 이동 간격
    vim.opt_local.tabstop = 2 -- 탭 문자의 너비
    vim.opt.softtabstop = 2 -- 탭 키 입력 시 삽입되는 공백
    vim.opt.expandtab = true -- 탭을 공백으로 변환
  end,
})

-- =========================================================================
-- [대용량 파일 전용 버퍼 최적화]
-- _G.MAX_FILE_SIZE 를 초과하는 모든 파일에 대해 무거운 편집 부가 기능(괄호 매칭, 폴딩 계산, 긴 줄 연산)을
-- 최적화하여 타이핑 렉 및 화면 스크롤/이동 렉을 완벽하게 차단합니다.
-- =========================================================================
vim.api.nvim_create_autocmd({ 'BufReadPre', 'BufEnter' }, {
  pattern = '*',
  callback = function(args)
    local buf = args.buf
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
      return
    end

    local fname = vim.api.nvim_buf_get_name(buf)
    local ok, stat = pcall(vim.loop.fs_stat, fname)

    if ok and stat and stat.size > _G.get_max_file_size(buf) then
      -- 1. 폴딩 연산을 수동(manual)으로 바꾸어 타이핑 시 구조 재계산 렉 방지
      vim.opt_local.foldmethod = 'manual'

      -- 2. 한 줄이 매우 길 때 최대 300자까지만 하이라이팅을 연산하여 스크롤 렉 방지
      vim.opt_local.synmaxcol = 300

      -- 3. 매 커서 이동마다 괄호 짝을 맞춰보며 화면을 지연시키는 matchparen 플러그인 임시 비활성화
      vim.cmd('NoMatchParen')

      -- 4. 실행 취소 파일(undofile) 비활성화로 디스크 I/O 최적화
      vim.opt_local.undofile = false

      -- 5. LazyVim의 무거운 기본 동기식 자동 포맷팅 차단 (대신 아래에서 비동기 포맷팅 적용)
      vim.b[buf].autoformat = false
    else
      -- 일반 파일 버퍼로 돌아왔을 때는 괄호 짝 매칭 기능을 다시 활성화
      vim.cmd('DoMatchParen')
    end
  end,
})

-- =========================================================================
-- [대용량 파일 비동기 포맷팅 최적화]
-- _G.MAX_FILE_SIZE 를 초과하는 대용량 파일 저장 시 동기식 포맷팅으로 인한 렉을 방지하고 백그라운드 비동기로 포맷팅합니다.
-- (모든 포맷터에 일괄 적용)
-- =========================================================================
vim.api.nvim_create_autocmd('BufWritePost', {
  group = vim.api.nvim_create_augroup('large_file_format_async', { clear = true }),
  callback = function(event)
    local buf = event.buf
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
      return
    end

    local fname = vim.api.nvim_buf_get_name(buf)
    local ok, stat = pcall(vim.loop.fs_stat, fname)

    if ok and stat and stat.size > _G.get_max_file_size(buf) then
      -- 비동기로 conform.nvim 포맷팅 실행
      local conform_ok, conform = pcall(require, 'conform')
      if conform_ok then
        vim.notify(
          '📄 대용량 파일('
            .. math.floor(stat.size / 1024)
            .. 'KB)이므로 비동기 포맷팅을 백그라운드에서 진행합니다.',
          vim.log.levels.INFO,
          { title = 'Formatter' }
        )
        conform.format({ bufnr = buf, async = true, lsp_fallback = true })
      end
    end
  end,
})

-- =========================================================================
-- [모든 LSP의 시맨틱 토큰 비활성화]
-- 버퍼에 LSP 클라이언트가 연결될 때(Attach) 시맨틱 토큰 제공(구문 강조) 기능을
-- 강제로 비활성화하여 에디터 반응 속도를 최적화합니다.
-- =========================================================================
vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('UserLspConfig', { clear = true }),
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if client then
      client.server_capabilities.semanticTokensProvider = nil
    end
  end,
})

-- =========================================================================
-- [파이썬 파일 오픈 시 Jinja2 포맷터 설정 자동 감지 및 대화형 셋업]
-- =========================================================================
local jinja_setup_checked = {}

vim.api.nvim_create_autocmd('FileType', {
  pattern = 'python',
  callback = function()
    local buf_name = vim.api.nvim_buf_get_name(0)
    if buf_name == '' then
      return
    end

    -- 프로젝트 루트 디렉토리 찾기 (.git, .prettierrc 등을 기준)
    local root_dirs = vim.fs.find({ '.git', '.prettierrc', 'package.json' }, {
      upward = true,
      path = vim.fs.dirname(buf_name),
    })

    local project_root = #root_dirs > 0 and vim.fs.dirname(root_dirs[1]) or nil
    if not project_root then
      return
    end

    -- 이번 세션에서 이미 검사한 프로젝트면 스킵
    if jinja_setup_checked[project_root] then
      return
    end
    jinja_setup_checked[project_root] = true

    -- 프로젝트 루트 내의 prettier 설정 파일들 확인
    local config_files = vim.fs.find({
      'prettier.config.js',
      'prettier.config.cjs',
      '.prettierrc',
      '.prettierrc.json',
      '.prettierrc.js',
      '.prettierrc.cjs',
      '.prettierrc.yaml',
      '.prettierrc.yml',
    }, { path = project_root, limit = 1 })

    local config_path = #config_files > 0 and config_files[1] or nil
    local has_jinja_config = false

    if config_path then
      local f = io.open(config_path, 'r')
      if f then
        local content = f:read('*all')
        f:close()
        -- 기존 파일에 jinja 설정이 포함되어 있는지 검사
        if content:find('jinja') then
          has_jinja_config = true
        end
      end
    end

    -- 이미 Jinja 관련 프리티어 설정이 존재한다면 아무것도 하지 않음
    if has_jinja_config then
      return
    end

    -- 비동기로 사용자에게 적용 의사 및 경로 입력 유도
    vim.schedule(function()
      vim.ui.input({
        prompt = '💡 이 프로젝트에 Prettier Jinja 포맷팅을 설정하시겠습니까? (y/n): ',
        default = 'y',
      }, function(confirm)
        if not confirm or confirm:lower() ~= 'y' then
          vim.notify(
            'Jinja 포맷팅 설정을 건너뛰었습니다.',
            vim.log.levels.INFO,
            { title = 'Jinja Formatter' }
          )
          return
        end

        vim.ui.input({
          prompt = '📂 Jinja 포맷팅 적용 HTML 경로 (예: templates/**/*.html 또는 layouts/**/*.html, templates/**/*.html) (쉼표 구분 가능, 비워두면 모든 HTML): ',
          default = 'templates/**/*.html',
        }, function(html_path)
          if not html_path then
            return
          end

          -- 쉼표로 분할하여 패턴 생성
          local file_patterns = {}
          html_path = html_path:gsub('^%s*(.-)%s*$', '%1') -- 앞뒤 전체 공백 제거

          if html_path ~= '' then
            for part in string.gmatch(html_path, '[^,]+') do
              part = part:gsub('^%s*(.-)%s*$', '%1') -- 각 경로 앞뒤 공백 제거
              if part ~= '' then
                table.insert(file_patterns, part)
              end
            end
          end

          -- 생성될 prettier.config.js 파일 경로 설정 (글로벌 설정을 JS 수준에서 자연스럽게 Extend 하기 위함)
          local target_config = project_root .. '/prettier.config.js'
          if #file_patterns == 0 then
            table.insert(file_patterns, '*.html')
          end

          -- JS array 포맷으로 변환 (훑따옴표 ' 사용)
          local files_js_array = {}
          for _, pat in ipairs(file_patterns) do
            table.insert(files_js_array, string.format("'%s'", pat))
          end
          local files_str = table.concat(files_js_array, ', ')

          -- 글로벌 설정 파일의 실제 절대경로 가져오기
          local global_config_path = _G.DEVTOOLS2_DIR .. '/.config/prettier/.prettierrc.cjs'

          -- 글로벌 설정을 완벽하게 상속하면서 overrides 룰만 덧씌우는 아름다운 JS 설정 모듈 생성
          -- string.format 내부에서 들여쓰기 하면 실제 prettierrc.cjs 에도 적용되므로 주의 필요
          local config_content = string.format(
            [[
import globalConfig from '%s';

export default {
  ...globalConfig,
  overrides: [
    ...(globalConfig.overrides || []),
    {
      files: [%s],
      options: {
        parser: 'jinja-template'
      }
    }
  ]
};
]],
            global_config_path,
            files_str
          )

          local f = io.open(target_config, 'w')
          if f then
            f:write(config_content)
            f:close()
            local scope_desc = html_path == '' and '모든 HTML' or table.concat(file_patterns, ', ')
            vim.notify(
              '✅ '
                .. vim.fs.basename(target_config)
                .. '에 기존 글로벌 설정을 상속받은 Jinja2 설정이 저장되었습니다!\n(적용 범위: '
                .. scope_desc
                .. ')',
              vim.log.levels.INFO,
              { title = 'Jinja Formatter' }
            )
          else
            vim.notify(
              '❌ 프리티어 설정을 파일에 쓸 수 없습니다.',
              vim.log.levels.ERROR,
              { title = 'Jinja Formatter' }
            )
          end
        end)
      end)
    end)
  end,
})

-- =========================================================================
-- [복합 언어 파일 내 script/style 구문 강조 누락 방지]
-- 5000줄 이상의 대용량 파일에서 네오빔이 화면을 먼저 렌더링하여
-- 내장 script(JS) 영역의 트리시터 주입 하이라이팅이 누락되는 성능 이슈를 해결합니다.
--
-- 💡 적용 대상 배경 분석:
--  - 대상 파일(html, htmldjango, vue)은 마크업, 스크립트, 스타일 등 서로 다른 문맥의 언어가
--    한 파일에 공존하여 하위 언어를 비동기로 로드(Language Injection)하므로 타이밍 렉이 발생합니다.
--  - 반면, 단일 언어(java, js, ts, py)나 React(JSX/TSX는 단일 jsx/tsx 파서가 문법 내부에서 한 번에 해석)는
--    이러한 비동기 주입 과정이 없어 시작 지연이 없으므로 최적화 대상에서 제외합니다.
-- =========================================================================
vim.api.nvim_create_autocmd({ 'BufReadPost', 'FileType' }, {
  pattern = { 'html', 'htmldjango', 'vue' },
  callback = function(args)
    local buf = args.buf
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
      return
    end

    -- 대용량 파일은 동기 파싱 및 강제 하이라이팅 적용 대상에서 제외
    local fname = vim.api.nvim_buf_get_name(buf)
    local ok, stat = pcall(vim.loop.fs_stat, fname)
    if ok and stat and stat.size > _G.get_max_file_size(buf) then
      return
    end

    pcall(function()
      -- 1. 비동기 schedule 없이 즉시 동기식으로 트리시터 및 하위 주입 언어(JS/CSS) 파싱 완료 강제
      local parser = vim.treesitter.get_parser(buf)
      if parser then
        parser:parse(true) -- 주입된 자식 트리(javascript, css)까지 강제 동기 파싱
      end

      -- 2. Neovim 0.12 공식 고수준 API로 하이라이터 안전 바인딩 및 구식 정규식 차단(syntax manual) 완벽 수행
      local ft = vim.api.nvim_get_option_value('filetype', { buf = buf })
      vim.treesitter.start(buf, ft)
    end)
  end,
})

-- =========================================================================
-- [이미지 및 PDF 파일 외부 뷰어 강제 연동 및 로딩 원천 차단]
-- Neovim이 바이너리(이미지/PDF) 파일을 텍스트 버퍼로 로드하여
-- 렌더링 부하 및 픽커 포커스 꼬임 문제를 일으키는 것을 완벽하게 차단합니다.
-- 엔터 등으로 이미지나 PDF를 열면 Neovim 버퍼 대신 외부 시스템 뷰어가 바로 열립니다.
-- =========================================================================
local image_group = vim.api.nvim_create_augroup("ExternalImageViewer", { clear = true })
vim.api.nvim_create_autocmd("BufReadCmd", {
  group = image_group,
  pattern = { "*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp", "*.bmp", "*.pdf" },
  callback = function(ev)
    local filepath = vim.fn.expand("<amatch>")
    -- OS(리눅스, 맥, 윈도우)에 무관하게 시스템 기본 지정 앱으로 비동기 실행
    vim.ui.open(filepath)
    
    -- 2. Neovim 버퍼가 바이너리 데이터를 읽지 않도록 빈 상태로 제어
    vim.bo[ev.buf].modifiable = false
    vim.bo[ev.buf].modified = false
    vim.bo[ev.buf].buftype = "nofile"
    
    -- 3. 이 버퍼를 Neovim 화면에서 즉시 닫고 이전 버퍼로 원복
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(ev.buf) then
        vim.api.nvim_buf_delete(ev.buf, { force = true })
      end
    end)
  end,
})
-- ============================================================
-- CapsLock 감지 경고
-- Normal / Visual 모드에서 연속 대문자 입력 시 CapsLock 경고
-- (단축키 모드에서 대문자가 연속 입력되면 CapsLock 이 켜진 것으로 판단)
-- ============================================================
do
  local capslock_count = 0    -- 연속 대문자 카운트
  local capslock_warned = false -- 이미 경고한 경우 중복 방지

  local THRESHOLD = 2 -- 연속 대문자 몇 개부터 경고할지

  -- 단축키 모드: Normal, Visual, Visual Line, Visual Block, Select
  local shortcut_modes = { n = true, v = true, V = true, ['\22'] = true, s = true }

  vim.on_key(function(key)
    local mode = vim.fn.mode()

    if not shortcut_modes[mode] then
      -- 단축키 모드가 아니면 카운터 초기화 (Insert 모드 진입 시 등)
      capslock_count = 0
      capslock_warned = false
      return
    end

    -- 순수 알파벳 대문자 한 글자인지 확인
    if #key == 1 and key:match('^[A-Z]$') then
      capslock_count = capslock_count + 1

      if capslock_count >= THRESHOLD and not capslock_warned then
        capslock_warned = true
        vim.schedule(function()
          vim.notify(
            table.concat({
              '⚠️  CapsLock 이 켜져 있을 수 있습니다!',
              '',
              '현재 모드(' .. mode .. ')에서 대문자 키가 연속 입력되었습니다.',
              '단축키가 의도대로 동작하지 않는다면 CapsLock 을 끄세요.',
              '',
              '  • Normal 모드 단축키는 소문자 기준으로 동작합니다.',
              '  • CapsLock 상태에서 Shift + 영문키는 소문자가 됩니다.',
            }, '\n'),
            vim.log.levels.WARN,
            {
              title = 'CapsLock 경고',
              timeout = 5000,
            }
          )
        end)
      end
    else
      -- 대문자가 아닌 키 입력 시 카운터/경고 플래그 초기화
      capslock_count = 0
      capslock_warned = false
    end
  end, vim.api.nvim_create_namespace('capslock_detect'))
end
