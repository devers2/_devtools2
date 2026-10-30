-- ===========================================================================================
-- [임시 우회: Groovy Treesitter 파서의 문서 주석(/** ... */) 버그 자동 수정 — ts_groovy_doc_fix]
-- ===========================================================================================
--
-- 📌 [문제]
--   nvim-treesitter 가 쓰는 Groovy 파서(github.com/murtaza64/tree-sitter-groovy, 확인 커밋 2a6ddd5 = 2026-10 기준 최신)는
--   "/**" 로 시작하면 문서 주석(groovy_doc)으로 읽고, 그 다음 줄 끝까지를 첫 줄(first_line)로 한 번에 가져갑니다.
--   이때 줄 끝의 "*/" 까지 가져가 버려서 주석의 끝을 "다음에 나오는 */" 에서 찾습니다. 그래서
--     /** 짧은 설명 */            ← 다음 줄 코드까지 주석으로 강조됨
--     /*****egovframe*****/       ← 다음 "*/" 가 나올 때까지(예: 여러 줄 아래 /*===*/) 전부 주석으로 강조됨
--   처럼 한 줄 문서 주석이나 별표 띠 주석 아래 코드가 주석 색으로 보입니다 (build.gradle 에서 발견 — Goono-ELN).
--   빈 문서 주석(/** */, /***/, /**/)도 같은 이유로 깨집니다.
--
-- 📌 [이 모듈이 하는 일 — 문제가 있을 때만 끼어듦]
--   Groovy 파일(build.gradle 포함)을 세션에서 처음 열 때:
--   1. 설치된 groovy 파서로 짧은 코드 조각(SELF_TEST)을 읽어 버그가 있는지 확인 (1ms 미만, 버전 번호가 아닌 실제 동작으로 판단)
--   2. 정상이면 아무것도 안 함 — 원본에서 고쳐졌거나, 이미 이 모듈이 고친 파서가 설치된 경우
--   3. 버그가 있으면 백그라운드(화면 안 멈춤, 수 초)에서:
--      ① 지금 설치된 것과 "같은 커밋"의 원본 grammar.js 를 받고
--      ② 아래 PATCHES 의 몇 줄만 바꿔서(고친 문법 파일을 통째로 들고 있지 않음 → 원본이 업데이트돼도 그 버전에 맞춰 고침,
--         nvim-treesitter 의 강조 규칙(queries)과 노드 이름이 어긋나지 않음)
--      ③ tree-sitter generate / build 로 파서를 만든 뒤, 만든 파서로 다시 SELF_TEST 를 통과할 때만
--      ④ 설치된 groovy.so 를 교체 (적용은 Neovim 재시작 후 — 이미 불러온 파서는 실행 중에 바꿀 수 없음)
--   4. 고칠 수 없으면(원본 문법이 크게 바뀌어 바꿀 부분을 못 찾음, 다운로드·빌드 실패) 원본을 그대로 쓰고 한 번만 알림.
--      같은 커밋으로는 다시 시도하지 않습니다(STATE_FILE 에 기록).
--
-- 📌 [업데이트·재설치 때]
--   parser-info/groovy.revision 은 원본 커밋 그대로 두므로 nvim-treesitter 의 업데이트 판단은 원래대로 동작합니다.
--   :TSUpdate / :TSInstall! / 다른 PC 새 설치로 원본 파서가 다시 깔리면, 다음에 Groovy 파일을 열 때 1번 검사가
--   다시 버그를 찾아 자동으로 고칩니다. 원본에서 버그가 고쳐지면 검사를 통과하므로 저절로 아무 일도 하지 않습니다.
--
-- 📌 [필요한 도구] curl, tree-sitter CLI(Mason), C 컴파일러, Node.js — 모두 DevTools2 설치 때 들어감.
--
-- 🗑️ [제거 방법 — 원본(tree-sitter-groovy)에서 고쳐져 nvim-treesitter 가 그 버전으로 올라가면]
--   1. 이 파일(lua/util/ts_groovy_doc_fix.lua) 삭제
--   2. plugins/treesitter.lua 의 "require('util.ts_groovy_doc_fix').setup()" 한 줄(과 그 위 주석) 삭제
--   3. (선택) ~/.cache/nvim/dt2-ts-groovy-fix, ~/.local/state/nvim/dt2-ts-groovy-fix.json 삭제
--   4. :TSInstall! groovy 로 원본 파서 재설치
-- ===========================================================================================

local M = {}

local TITLE = 'Groovy 파서 주석 수정'
local WORK_DIR = vim.fn.stdpath('cache') .. '/dt2-ts-groovy-fix'
local STATE_FILE = vim.fn.stdpath('state') .. '/dt2-ts-groovy-fix.json'

-- 버그 확인용 코드 조각: 정상 파서라면 마지막 줄 "def b = 2" 가 코드(declaration)로 읽혀야 함
local SELF_TEST = 'def a = 1\n/** x */\ndef b = 2\n/*****x*****/\ndef c = 3\n/** */\ndef d = 4\n'
-- 고친 파서가 원래 되던 것(여러 줄 문서 주석의 첫 줄·@param 노드)을 망가뜨리지 않았는지 확인하는 조각 (교체 전 검사에만 사용)
local KEEP_TEST = '/**\n * First line.\n * @param y v\n */\ndef a = 1\n'
local KEEP_SEXPR = '(source_file (groovy_doc (first_line) (groovy_doc_param (identifier))) (declaration'

-- 원본 grammar.js 에서 바꿀 부분 (old 가 원본에 정확히 한 번 있어야 적용 — 없으면 원본 문법이 바뀐 것이라 수정 포기)
local PATCHES = {
  {
    -- groovy_doc 규칙 전체를 바꿈 (노드 이름 groovy_doc · first_line · groovy_doc_param 등은 그대로 → 강조 규칙과 호환)
    --   ① 첫 줄(first_line)이 "*/" 를 먹지 않게: 별표는 뒤에 "/" 가 아닌 글자가 올 때만 첫 줄에 포함
    --   ② 주석 끝으로 "*/" 뿐 아니라 "***/" (별표 띠) 도 인정
    --   ③ 빈 문서 주석(/** */, /***/, /*****/): 앞의 공백·별표 묶음이 닫는 "*/" 의 별표까지 먹고 "/" 만 남는 경우,
    --      그 바로 뒤의 "/" 를 주석 끝으로 인정 (공백·별표 묶음 부분은 원본 그대로 — 생략 가능하게 바꾸면 파서가
    --      그 공백을 일반 공백으로 건너뛰어 여러 줄 문서 주석의 첫 줄 강조가 사라짐, 실측)
    desc = 'groovy_doc 규칙 (첫 줄이 */ 를 먹지 않게, 별표 띠·빈 문서 주석 닫기)',
    old = [[
      seq(
        '/**',
        // optional(
          token.immediate(/[*\n\s]+/),
          alias(token.immediate(/[^\n\.]+[\.]?/), $.first_line),
        // ),
        repeat(
          choice(
            // /[^*\s]*(\*[^/][^*\s]+)*/
            $.groovy_doc_param,
            $.groovy_doc_throws,
            $.groovy_doc_tag,
            $.groovy_doc_at_text,
            /([^@*]|\*[^/])([^*\s@]|[^\s\n]@|\*[^/])+/,
          ),
        ),
        '*/'
      ),]],
    new = [[
      seq(
        '/**',
        token.immediate(/[*\n\s]+/),
        choice(
          token.immediate('/'),
          seq(
            alias(token.immediate(/([^\n\.*]|\*+[^\n\.*\/])+[\.]?/), $.first_line),
            repeat(
              choice(
                $.groovy_doc_param,
                $.groovy_doc_throws,
                $.groovy_doc_tag,
                $.groovy_doc_at_text,
                /([^@*]|\*[^/])([^*\s@]|[^\s\n]@|\*[^/])+/,
              ),
            ),
            token(prec(1, /\*+\//)),
          ),
        ),
      ),]],
  },
  {
    -- "/**/" (빈 일반 주석): '/**' 토큰이 먼저 잡혀 문서 주석으로 시작되는 것을 막음
    desc = '/**/ 를 일반 주석으로',
    old = [[
      seq('/*', /[^*]*\*+([^/*][^*]*\*+)*\//), // not sure why comments work better as seq]],
    new = [[
      seq('/*', /[^*]*\*+([^/*][^*]*\*+)*\//), // not sure why comments work better as seq
      '/**/',]],
  },
}

local function notify(msg, level)
  vim.schedule(function()
    vim.notify(msg, level or vim.log.levels.INFO, { title = TITLE })
  end)
end

local function read_state()
  local f = io.open(STATE_FILE, 'r')
  if not f then
    return {}
  end
  local ok, data = pcall(vim.json.decode, f:read('*a') or '')
  f:close()
  return (ok and type(data) == 'table') and data or {}
end

local function write_state(data)
  vim.fn.mkdir(vim.fs.dirname(STATE_FILE), 'p')
  local f = io.open(STATE_FILE, 'w')
  if f then
    f:write(vim.json.encode(data))
    f:close()
  end
end

--- 주어진 언어 이름의 파서로 SELF_TEST 를 읽어 버그가 없는지
--- @return boolean|nil ok  nil = 파서를 쓸 수 없음(미설치 등)
local function parser_ok(lang)
  local ok, parser = pcall(vim.treesitter.get_string_parser, SELF_TEST, lang)
  if not ok or not parser then
    return nil
  end
  local root = parser:parse()[1]:root()
  if root:has_error() then
    return false
  end
  -- 코드 줄(def ...)이 모두 declaration 으로 남아 있어야 함 (주석에 먹히면 개수가 줄어듦)
  local decls = 0
  for child in root:iter_children() do
    if child:type() == 'declaration' then
      decls = decls + 1
    end
  end
  return decls == 4
end

-- 설치된 groovy 파서의 원본 커밋과 저장소 주소
local function installed_info()
  local ok_cfg, config = pcall(require, 'nvim-treesitter.config')
  local ok_p, parsers = pcall(require, 'nvim-treesitter.parsers')
  if not ok_cfg or not ok_p or not parsers.groovy or not parsers.groovy.install_info then
    return nil
  end
  local info = parsers.groovy.install_info
  local rev = info.revision
  -- 설치 기록 파일이 있으면 그 커밋(실제로 깔린 버전)을 우선
  local f2 = io.open(vim.fs.joinpath(config.get_install_dir('parser-info'), 'groovy.revision'), 'r')
  if f2 then
    local r = vim.trim(f2:read('*a') or '')
    f2:close()
    if r ~= '' then
      rev = r
    end
  end
  local so = vim.fs.joinpath(config.get_install_dir('parser'), 'groovy.so')
  return { url = info.url, revision = rev, so = so }
end

local function tree_sitter_bin()
  local p = vim.fn.exepath('tree-sitter')
  if p ~= '' then
    return p
  end
  local mason = (_G.NVIM_SHARED_DIR or (vim.fn.stdpath('data'))) .. '/mason/bin/tree-sitter'
  return vim.fn.executable(mason) == 1 and mason or nil
end

-- 명령을 차례로 실행 (하나라도 실패하면 on_fail(단계 설명, 출력))
local function run_steps(steps, cwd, on_done, on_fail)
  local i = 0
  local function next_step()
    i = i + 1
    local step = steps[i]
    if not step then
      return on_done()
    end
    vim.system(step.cmd, { cwd = cwd, text = true }, function(r)
      if r.code ~= 0 then
        return on_fail(step.desc, (r.stderr ~= '' and r.stderr or r.stdout or ''):sub(1, 300))
      end
      next_step()
    end)
  end
  next_step()
end

local running = false

--- 버그가 있으면 고친 파서를 만들어 교체 (백그라운드)
local function build_fixed(info)
  local ts = tree_sitter_bin()
  if not ts or vim.fn.executable('curl') == 0 or not info.url:match('github%.com') then
    return -- 도구가 없으면 조용히 포기 (원본 그대로 사용)
  end
  running = true
  local dir = WORK_DIR .. '/' .. info.revision
  vim.fn.delete(dir, 'rf')
  vim.fn.mkdir(dir, 'p')
  local raw = info.url:gsub('^https://github%.com/', 'https://raw.githubusercontent.com/'):gsub('%.git$', '')
    .. '/' .. info.revision .. '/'

  local function fail(stage, detail)
    running = false
    local st = read_state()
    st.failed_revision = info.revision
    write_state(st)
    notify(string.format('Groovy 주석 강조 자동 수정 실패 (%s) — 원본 파서를 그대로 씁니다.\n  %s\n  (이 버전으로는 다시 시도하지 않음, 작업 폴더: %s)',
      stage, vim.trim(detail or ''), vim.fn.fnamemodify(dir, ':~')), vim.log.levels.WARN)
  end

  run_steps({
    { desc = '원본 문법 다운로드', cmd = { 'curl', '-sSfL', raw .. 'grammar.js', '-o', 'grammar.js' } },
    { desc = '원본 설정 다운로드', cmd = { 'curl', '-sSfL', raw .. 'tree-sitter.json', '-o', 'tree-sitter.json' } },
  }, dir, function()
    vim.schedule(function()
      -- ② 원본 문법에 PATCHES 적용
      local path = dir .. '/grammar.js'
      local f = io.open(path, 'r')
      local src = f and f:read('*a') or ''
      if f then
        f:close()
      end
      for _, p in ipairs(PATCHES) do
        local s, e = src:find(p.old, 1, true)
        if not s or src:find(p.old, e + 1, true) then
          return fail('원본 문법이 바뀌어 수정할 부분을 찾지 못함: ' .. p.desc, '원본에서 이미 고쳐졌는지 확인 후 이 모듈 제거 검토')
        end
        src = src:sub(1, s - 1) .. p.new .. src:sub(e + 1)
      end
      local fw = io.open(path, 'w')
      if not fw then
        return fail('고친 문법 저장', path)
      end
      fw:write(src)
      fw:close()

      -- ③ 파서 생성·빌드
      run_steps({
        { desc = 'tree-sitter generate', cmd = { ts, 'generate' } },
        { desc = 'tree-sitter build', cmd = { ts, 'build', '-o', 'groovy.so', '.' } },
      }, dir, function()
        vim.schedule(function()
          local new_so = dir .. '/groovy.so'
          -- 만든 파서를 다른 이름으로 불러와 다시 검사 (통과할 때만 교체)
          local lang_name = 'groovy_dt2fix_' .. info.revision:sub(1, 7)
          pcall(vim.treesitter.language.add, lang_name, { path = new_so, symbol_name = 'groovy' })
          if parser_ok(lang_name) ~= true then
            return fail('고친 파서 검사 실패', '고친 파서도 SELF_TEST 를 통과하지 못함 — PATCHES 확인 필요')
          end
          local okk, kp = pcall(vim.treesitter.get_string_parser, KEEP_TEST, lang_name)
          if not okk or not vim.startswith(kp:parse()[1]:root():sexpr(), KEEP_SEXPR) then
            return fail('고친 파서 검사 실패', '여러 줄 문서 주석 구조(첫 줄·@param)가 원본과 달라짐 — PATCHES 확인 필요')
          end
          -- ④ 설치된 groovy.so 교체 (임시 파일에 복사한 뒤 이름 바꾸기 — 다른 Neovim 이 쓰는 중이어도 안전)
          local tmp = info.so .. '.dt2fix.tmp'
          local okc = vim.uv.fs_copyfile(new_so, tmp)
          if not okc or not vim.uv.fs_rename(tmp, info.so) then
            pcall(vim.uv.fs_unlink, tmp)
            return fail('파서 교체', info.so)
          end
          running = false
          local st = read_state()
          st.failed_revision = nil
          st.fixed_revision = info.revision
          write_state(st)
          notify('Groovy 파서의 문서 주석(/** */) 강조 버그를 고친 파서로 교체했습니다.\n'
            .. '  Neovim 을 다시 시작하면 적용됩니다. (util/ts_groovy_doc_fix.lua)')
        end)
      end, fail)
    end)
  end, fail)
end

--- 설치된 groovy 파서를 검사하고 버그가 있으면 고침
function M.check()
  if running then
    return
  end
  local ok = parser_ok('groovy')
  if ok ~= false then
    return -- 정상(true)이거나 아직 파서가 없음(nil — 설치 후 다음에 열 때 다시 검사)
  end
  local info = installed_info()
  if not info or not info.revision then
    return
  end
  if read_state().failed_revision == info.revision then
    return -- 이 버전은 이미 실패함 (같은 실패 반복 방지)
  end
  build_fixed(info)
end

--- Groovy 파일을 세션에서 처음 열 때 한 번 검사하도록 등록
function M.setup()
  vim.api.nvim_create_autocmd('FileType', {
    group = vim.api.nvim_create_augroup('devtools2_ts_groovy_doc_fix', { clear = true }),
    pattern = 'groovy',
    once = true,
    callback = function()
      -- 파서 자동 설치(try_auto_install_parser)가 먼저 끝나도록 잠시 뒤 검사
      vim.defer_fn(function()
        pcall(M.check)
      end, 3000)
    end,
  })
end

return M
