--[[
===========================================================================================
[프로젝트 설정 통합 로더: util.project_config]
===========================================================================================
프로젝트 설정(settings.json) 및 디버깅 실행 구성(launch.json)의 단일 원본(SSOT) 관리자입니다.
Neovim과 VS Code 간의 설정 일원화를 위해 공통 탐색 우선순위를 제공합니다:

탐색 우선순위:
  1. 프로젝트 루트의 `.nvim/` 디렉토리 (Neovim 전용 설정 최우선)
     - `.nvim/settings.json`
     - `.nvim/launch.json`
  2. 프로젝트 루트의 `.vscode/` 디렉토리 (VS Code와 공통 공유)
     - `.vscode/settings.json`
     - `.vscode/launch.json`
  3. 설정 파일이 없는 경우: 시스템 기본값 및 자동 탐색으로 안전하게 폴백

병합 규칙 (get_settings / get_launch):
  .vscode/ 파일을 바탕으로 읽고, 그 위에 .nvim/ 파일을 병합합니다. 한쪽만 있으면 그 파일 그대로 사용.
    - settings.json: 객체는 깊은 병합, 배열/스칼라는 .nvim 값으로 교체
    - launch.json  : configurations / compounds 는 name 기준 병합
                     (같은 name 은 .nvim 항목으로 교체, 새 name 은 추가, 나머지 .vscode 항목 유지)

지원하는 주요 키:
  - settings.json:
    - nvim.projectRoot (string)        : 프로젝트 루트 수동 지정 (옵션)
                                         설정 파일이 있는 디렉토리 기준 상대경로 / 절대경로 / ~ /
                                         ${workspaceFolder} 지원
    - java.import.gradle.java.home     : Gradle 데몬 및 JDTLS 구동용 JDK 경로 (VS Code 표준)
                                         (21 미만이면 jdtls 실행에는 21 이상 JDK 를 따로 씀 — plugins/java.lua)
    - java.configuration.runtimes      : 프로젝트 빌드 런타임 목록 및 default 지정 (VS Code 표준)
  - launch.json:
    - configurations[].mainClass       : Java 실행 구성의 메인 클래스 (자동 기동 및 DAP 디버깅 공통)

옵션 (M.config):
  - cwd_priority (bool, 기본 false) : true면 CWD가 마커를 가진 프로젝트 디렉토리이고 파일을 포함할 때
                                      CWD를 루트로 확정 (과거 동작). 기본값 false는 같은 파일이
                                      어디서 실행했든 항상 같은 루트로 해석되도록(LSP 인스턴스 중복 방지) 합니다.
  - ceilings (string[])            : 이 디렉토리 이상으로는 올라가지 않음 ($HOME, / 는 항상 포함)
===========================================================================================
--]]

--[[
===========================================================================================
[불변 원칙 — 이 파일을 수정하기 전에 반드시 읽을 것]
===========================================================================================
아래 원칙은 실제 오작동(오버슈트, 죽은 코드, LSP 중복, 설정 증발)을 겪고 검증을 거쳐 확정된 것입니다.
"더 단순하게", "더 똑똑하게", "리팩터링" 명목으로 되돌리지 마십시오. 원칙을 바꿔야 한다면
코드를 고치기 전에 반드시 사용자에게 먼저 물어보십시오.

[루트 탐색 — get_project_root]
  1. "가장 높은(Topmost) 마커를 무조건 선택"하지 말 것.
     상위 빌드 파일이 하위를 "실제로 포함"하는 것이 검증될 때만 위로 올라간다.
       - Maven : 상위 pom.xml 의 <module> 목록(주석 제외)이 하위 디렉토리를 가리킬 때
       - Gradle: 상위 settings 가 includeBuild / include 로 하위 디렉토리를 가리킬 때
     포함 관계가 없으면 무관한(독립) 중첩 프로젝트이므로 멈춘다.
     (어기면: 모노레포의 무관한 하위 프로젝트가 상위 루트로 잘못 묶이거나 jdtls 가 전부 import 한다)
  2. 루트 판정은 "파일 경로만으로 결정되는 순수 함수"여야 한다. 기본 경로에서 CWD 를 쓰지 말 것.
     CWD 는 opt-in(M.config.cwd_priority)에서만 허용.
     (어기면: 같은 파일이 실행 위치에 따라 다른 루트가 되어 jdtls 인스턴스/workspace 캐시가
      중복되고, 하위 모듈에서 실행하면 형제 모듈 소스 참조가 깨진다)
  3. $HOME 과 / 이상으로는 절대 올라가지 말 것 (천장, M.config.ceilings 로 확장만 가능).
     (어기면: ~/.git 으로 dotfiles 를 관리하는 환경에서 모든 프로젝트 루트가 ~ 가 된다)
  4. .git 은 "빌드 파일(pom.xml / settings.gradle* / build.gradle*)이 전혀 없을 때만" 쓰는
     마지막 폴백이다. 빌드 마커 검사보다 앞에 두지 말 것.
     (어기면: 실무 Maven 프로젝트는 거의 .git 이 있어 Maven 분기가 죽은 코드가 된다)
     .git 은 디렉토리가 아니라 "파일"일 수 있다(submodule/worktree). isdirectory 로 검사하지 말고
     fs_stat 존재 여부로 확인한다.
  5. 래퍼 마커(.mvn / mvnw / gradlew)와 .project/.classpath 는 빌드 파일이 없을 때의 폴백일 뿐,
     최우선 규칙으로 올리지 말 것.
     (어기면: 저장소 루트에 mvnw 가 있을 때 그 안의 독립 프로젝트가 상위 루트로 잘못 잡힌다)
  6. Gradle 은 "가장 가까운 settings" 에서 시작한다(Gradle 의 실제 동작). 하위 프로젝트에
     settings 가 없으면 상위의 가장 가까운 settings 가 루트다.
  7. nvim.projectRoot 는 항상 최우선이다. 파일 위치에서 위로 올라가며 가장 가까운 지정을 사용하고,
     키가 없는 settings.json 은 무시한다(하위 폴더에 파편화된 .vscode 가 루트를 가로채면 안 됨).
  8. jdt://, jar: 등 URI 버퍼는 디렉토리를 탐색하지 말고 기존 LSP root_dir 을 재사용한다.
  9. 경로는 항상 realpath + vim.fs.normalize 로 정규화한다(심볼릭 링크, 말미 슬래시, ..).
 10. start_dir 자신도 탐색 대상에 포함한다(vim.fs.parents 는 자신을 순회하지 않음 — off-by-one 주의).

[설정 로드 — get_settings / get_launch]
 11. "먼저 발견된 파일 하나만 사용(Shadowing)" 방식으로 되돌리지 말 것.
     .vscode 를 베이스로 읽고 그 위에 .nvim 을 병합한다.
       - settings.json: 객체는 깊은 병합, 배열/스칼라는 .nvim 값으로 교체
       - launch.json  : configurations / compounds 는 name 기준 병합
     (어기면: .nvim/settings.json 에 nvim.projectRoot 한 줄만 써도 .vscode 의 JDK/런타임/실행 구성이
      전부 증발한다)
 12. 반환하는 경로(두 번째 반환값)는 .nvim 이 있으면 .nvim, 없으면 .vscode 를 유지한다(호출부 호환).

[기타]
 13. Lua 의 string.gsub 은 값을 2개 반환한다. return 문이나 인자 위치에서 그대로 쓰면 치환 횟수가
     섞이므로 변수에 담거나 괄호로 감쌀 것.
 14. 루트 결과는 디렉토리 단위로 캐시한다. 프로젝트 구조/설정을 바꾼 뒤에는 clear_cache() 를 호출한다.

[수정 후 반드시 검증할 시나리오 — 하나라도 깨지면 수정 금지]
  - .git 이 있는 Maven 3계층 멀티모듈 -> 최상위 aggregator 루트 (말단/중간 파일에서 모두)
  - 상위 <modules> 에 없는 무관한 중첩 Maven / Gradle 프로젝트 -> 중첩 프로젝트 자신이 루트
  - 주석 처리된 <module> 은 포함으로 보지 않음
  - Gradle includeBuild composite -> 상위 루트 / settings 없는 하위 프로젝트 -> 상위 settings
  - settings.gradle.kts, .git 이 파일인 submodule, 래퍼만 있는 루트
  - $HOME 에 .git 이 있어도 하위 프로젝트가 홈으로 새지 않음
  - 같은 파일을 CWD 만 바꿔 열어도 루트가 동일
  - .vscode 파편화(키 없는 settings.json) 무시 + nvim.projectRoot 최우선
  - .nvim 에 키 하나만 있어도 .vscode 의 나머지 설정이 유지됨 / launch name 기준 병합
===========================================================================================
--]]

local M = {}

local uv = vim.uv or vim.loop

-- 루트 탐색 결과 캐시 (불필요한 반복 디스크 I/O 방지). 프로젝트 구조를 바꿨다면 clear_cache() 호출
local _cache = {}

M.config = {
  cwd_priority = false,
  ceilings = {},
}

-- ===========================================================================================
-- 공통 유틸
-- ===========================================================================================

--- 경로 정규화 (~ 확장, . / .. 해소, 말미 슬래시 제거)
local function norm(p)
  local s = vim.fs.normalize(p)
  if #s > 1 then
    s = s:gsub('/+$', '')
  end
  return s
end

--- 파일/디렉토리/심볼릭 링크 존재 여부 (.git 이 파일인 submodule/worktree 도 허용)
local function exists(dir, name)
  return uv.fs_stat(dir .. '/' .. name) ~= nil
end

local function is_dir(path)
  local st = uv.fs_stat(path)
  return st ~= nil and st.type == 'directory'
end

local function read_text(path)
  local f = io.open(path, 'r')
  if not f then
    return nil
  end
  local s = f:read(2 * 1024 * 1024)
  f:close()
  return s
end

-- JSONC (주석 //, /* */ 및 후행 콤마) 정리 헬퍼
local function strip_jsonc(text)
  if not text or text == '' then
    return ''
  end
  local out = {}
  local i, n = 1, #text
  local in_str = false
  while i <= n do
    local c = text:sub(i, i)
    if in_str then
      out[#out + 1] = c
      if c == '\\' then
        out[#out + 1] = text:sub(i + 1, i + 1)
        i = i + 1
      elseif c == '"' then
        in_str = false
      end
      i = i + 1
    elseif c == '"' then
      in_str = true
      out[#out + 1] = c
      i = i + 1
    elseif c == '/' and text:sub(i + 1, i + 1) == '/' then
      local nl = text:find('\n', i, true)
      i = nl or (n + 1)
    elseif c == '/' and text:sub(i + 1, i + 1) == '*' then
      local close = text:find('*/', i + 2, true)
      i = close and (close + 2) or (n + 1)
    elseif c == ',' then
      local j = i + 1
      while j <= n and text:sub(j, j):match('%s') do
        j = j + 1
      end
      local nxt = text:sub(j, j)
      if nxt ~= ']' and nxt ~= '}' then
        out[#out + 1] = c
      end
      i = i + 1
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

--- JSON 파일 안전 읽기
--- @param file_path string
--- @return table|nil
local function read_json_file(file_path)
  if not file_path or vim.fn.filereadable(file_path) ~= 1 then
    return nil
  end
  local ok, lines = pcall(vim.fn.readfile, file_path)
  if not ok or not lines then
    return nil
  end
  local raw_text = table.concat(lines, '\n')
  local clean_text = strip_jsonc(raw_text)

  local ok_json, data = pcall(vim.json.decode, clean_text)
  if ok_json and type(data) == 'table' then
    return data
  end

  local ok_raw, data_raw = pcall(vim.json.decode, raw_text)
  if ok_raw and type(data_raw) == 'table' then
    return data_raw
  end

  return nil
end

-- ===========================================================================================
-- 프로젝트 루트 탐색
--
-- 설계 원칙 (기존 "무조건 Topmost" 방식의 오버슈트 문제를 해결):
--   0. nvim.projectRoot 수동 지정이 있으면 최우선.
--   1. 파일 경로만으로 결정되는 순수 함수 (CWD 비의존, 기본값). 같은 파일은 항상 같은 루트.
--   2. 가장 가까운 빌드 마커에서 시작해, 상위 빌드 파일이 하위를 "실제로 포함"하는 것이
--      검증될 때만 위로 올라간다.
--        - Maven : 상위 pom.xml 의 <module> 목록이 하위 디렉토리를 가리킬 때
--        - Gradle: 상위 settings 가 includeBuild / include 로 하위 디렉토리를 가리킬 때
--      포함 관계가 없으면 무관한(독립) 중첩 프로젝트로 보고 멈춘다.
--   3. $HOME / 파일시스템 루트 이상으로는 올라가지 않는다 (홈 dotfiles .git 오버슈트 방지).
--   4. 빌드 파일이 전혀 없을 때만 래퍼(.mvn, mvnw, gradlew), Eclipse(.project/.classpath),
--      .git(디렉토리 또는 submodule 파일) 순으로 가장 가까운 마커를 사용한다.
-- ===========================================================================================

--- start_dir 자신부터 위로 올라가는 디렉토리 목록 (stop 에 포함된 디렉토리는 제외하고 중단)
local function ancestors(start_dir, stop)
  local list, dir = {}, start_dir
  while dir and dir ~= '' do
    if stop[dir] then
      break
    end
    list[#list + 1] = dir
    local parent = vim.fs.dirname(dir)
    if not parent or parent == dir then
      break
    end
    dir = parent
  end
  return list
end

--- 올라가지 않을 천장 디렉토리 집합 ($HOME, /, M.config.ceilings)
local function ceiling_set()
  local set = { ['/'] = true }
  local home = uv.os_homedir()
  if home and home ~= '' then
    set[norm(uv.fs_realpath(home) or home)] = true
  end
  for _, c in ipairs(M.config.ceilings or {}) do
    local p = vim.fs.normalize(c)
    set[norm(uv.fs_realpath(p) or p)] = true
  end
  return set
end

--- URI 형태 버퍼 (jdt://, jar:file:..., zipfile:// 등) 여부
local function is_uri(p)
  return p:match('^%a[%w+.-]+:') ~= nil
end

--- 현재 버퍼에 붙은 LSP 클라이언트의 root_dir (URI 버퍼에서 기존 루트를 재사용하기 위함)
local function lsp_root()
  local ok, clients = pcall(vim.lsp.get_clients, { bufnr = 0 })
  if not ok or type(clients) ~= 'table' then
    return nil
  end
  for _, c in ipairs(clients) do
    local r = c.root_dir or (c.config and c.config.root_dir)
    if type(r) == 'string' and r ~= '' then
      return norm(r)
    end
  end
  return nil
end

-- ---- nvim.projectRoot (수동 지정) -------------------------------------------------------

local function resolve_custom(base, value)
  value = value:gsub('%${workspaceFolder}', function()
    return base
  end)
  local full
  if value:sub(1, 1) == '/' or value:sub(1, 1) == '~' or value:match('^%a:[/\\]') then
    full = value
  else
    full = base .. '/' .. value
  end
  full = norm(full)
  if is_dir(full) then
    return full
  end
  return nil
end

--- 파일 위치에서 위로 올라가며 가장 가까운 nvim.projectRoot 지정을 탐색
--- (키가 없는 .vscode/settings.json 은 무시하므로 하위 폴더의 파편화된 설정에 낚이지 않음)
local function find_custom_root(dirs)
  for _, d in ipairs(dirs) do
    for _, folder in ipairs({ '.nvim', '.vscode' }) do
      local data = read_json_file(d .. '/' .. folder .. '/settings.json')
      local v = data and data['nvim.projectRoot']
      if type(v) == 'string' and v ~= '' then
        local resolved = resolve_custom(d, v)
        if resolved then
          return resolved
        end
      end
    end
  end
  return nil
end

-- ---- Maven ------------------------------------------------------------------------------

--- parent_dir/pom.xml 의 <module> 가 child_dir 을 가리키는지 (주석 처리된 module 제외)
local function maven_includes(parent_dir, child_dir)
  local pom = read_text(parent_dir .. '/pom.xml')
  if not pom then
    return false
  end
  pom = pom:gsub('<!%-%-.-%-%->', '')
  for m in pom:gmatch('<module>%s*(.-)%s*</module>') do
    m = m:gsub('^%./', '')
    m = m:gsub('/pom%.xml$', '')
    m = m:gsub('/+$', '')
    local p = parent_dir .. '/' .. m
    if norm(uv.fs_realpath(p) or p) == child_dir then
      return true
    end
  end
  return false
end

-- ---- Gradle -----------------------------------------------------------------------------

local function gradle_settings_file(dir)
  for _, n in ipairs({ 'settings.gradle.kts', 'settings.gradle' }) do
    local p = dir .. '/' .. n
    if uv.fs_stat(p) then
      return p
    end
  end
  return nil
end

--- parent_dir 의 settings 가 child_dir 을 includeBuild / include 로 가리키는지 (휴리스틱)
--- settings 는 Groovy/Kotlin 코드이므로 완전한 파싱 대신, 문자열 리터럴이 하위 상대경로
--- (또는 콜론 표기 :a:b) 와 같은지 확인한다.
local function gradle_includes(parent_dir, child_dir)
  local file = gradle_settings_file(parent_dir)
  local text = file and read_text(file)
  if not text then
    return false
  end
  text = text:gsub('/%*.-%*/', '')
  text = text:gsub('//[^\n]*', '')

  local rel = child_dir:sub(#parent_dir + 2)
  if rel == '' then
    return false
  end
  local colon = rel:gsub('/', ':')
  for s in text:gmatch('["\']([^"\'\n]+)["\']') do
    s = s:gsub('^%./', ''):gsub('/+$', '')
    if s == rel or s == colon or s == (':' .. colon) then
      return true
    end
  end
  return false
end

-- ---- 루트 결정 --------------------------------------------------------------------------

--- 가장 가까운 빌드 도구 마커 탐지: settings.gradle(.kts) > pom.xml > build.gradle(.kts)
local function detect_build(dirs)
  for _, d in ipairs(dirs) do
    if gradle_settings_file(d) then
      return 'gradle', d
    end
    if exists(d, 'pom.xml') then
      return 'maven', d
    end
    if exists(d, 'build.gradle') or exists(d, 'build.gradle.kts') then
      return 'gradle', d
    end
  end
  return nil, nil
end

local function maven_root(dirs, d0)
  local root, started = d0, false
  for _, d in ipairs(dirs) do
    if d == d0 then
      started = true
    elseif started and exists(d, 'pom.xml') then
      if maven_includes(d, root) then
        root = d
      else
        break -- 포함 관계가 없는 상위 pom: 무관한 프로젝트이므로 중단
      end
    end
  end
  return root
end

local function gradle_root(dirs, d0)
  local root, started = nil, false
  for _, d in ipairs(dirs) do
    if d == d0 then
      started = true
    end
    if started and gradle_settings_file(d) then
      if not root then
        root = d -- 가장 가까운 settings (Gradle 의 실제 동작과 동일)
      elseif gradle_includes(d, root) then
        root = d
      else
        break
      end
    end
  end
  return root or d0 -- settings 없는 단일 build.gradle 프로젝트
end

local function nearest_with(dirs, markers)
  for _, d in ipairs(dirs) do
    for _, m in ipairs(markers) do
      if exists(d, m) then
        return d
      end
    end
  end
  return nil
end

local any_markers = {
  'pom.xml', 'settings.gradle', 'settings.gradle.kts', 'build.gradle', 'build.gradle.kts',
  '.mvn', 'mvnw', 'gradlew', '.git',
}

local function resolve(dir, cwd)
  local dirs = ancestors(dir, ceiling_set())
  if #dirs == 0 then
    return dir -- 홈/루트 자체에서 연 경우: 올라갈 곳이 없음
  end

  -- [0] 수동 지정
  local custom = find_custom_root(dirs)
  if custom then
    return custom
  end

  -- (옵션) 과거 동작: CWD 가 마커를 가진 프로젝트이고 파일을 포함하면 CWD 확정
  if M.config.cwd_priority then
    for _, d in ipairs(dirs) do
      if d == cwd and nearest_with({ d }, any_markers) then
        return cwd
      end
    end
  end

  -- [1] 빌드 도구 마커 + 포함 관계 검증 상승
  local tool, d0 = detect_build(dirs)
  if tool == 'maven' then
    return maven_root(dirs, d0)
  elseif tool == 'gradle' then
    return gradle_root(dirs, d0)
  end

  -- [2] 빌드 파일 없음: 래퍼 / Eclipse / .git 중 가장 가까운 것
  local fallback = nearest_with(dirs, { '.mvn', 'mvnw', 'gradlew' })
    or nearest_with(dirs, { '.project', '.classpath' })
    or nearest_with(dirs, { '.git' })
  return fallback or dir
end

--- 프로젝트 루트 디렉토리 결정 (재귀적/멀티모듈 대응)
--- @param start_path string|nil 탐색 시작 경로 (파일 경로 또는 디렉토리, nil이면 현재 버퍼)
--- @return string 정규화된 루트 경로
function M.get_project_root(start_path)
  local cwd = norm(vim.fn.getcwd())

  local path = start_path
  if not path or path == '' then
    path = vim.api.nvim_buf_get_name(0)
  end
  if path == '' then
    path = cwd
  end

  -- jdt://, jar:file:... 같은 비파일 버퍼는 탐색하지 않고 기존 LSP 루트를 재사용
  if is_uri(path) then
    return lsp_root() or cwd
  end

  path = norm(path)
  local dir = is_dir(path) and path or vim.fs.dirname(path)
  if not dir or dir == '' then
    return cwd
  end
  dir = norm(uv.fs_realpath(dir) or dir) -- 심볼릭 링크 정규화

  local key = dir .. '\0' .. (M.config.cwd_priority and cwd or '')
  local cached = _cache[key]
  if cached then
    return cached
  end

  local root = resolve(dir, cwd)
  _cache[key] = root
  return root
end

-- ===========================================================================================
-- 설정 파일 로드
-- ===========================================================================================

--- 설정 파일 경로 탐색 (.nvim/ 1순위 -> .vscode/ 2순위)
--- @param filename string 'settings.json' 또는 'launch.json'
--- @param root_path string|nil 탐색 기준 루트 (nil이면 현재 파일 기준 프로젝트 루트)
--- @return string|nil 찾은 파일의 절대 경로
function M.find_file(filename, root_path)
  local root = root_path or M.get_project_root()
  if not root or root == '' then
    root = vim.fn.getcwd()
  end
  root = root:gsub('/+$', '')

  for _, folder in ipairs({ '.nvim', '.vscode' }) do
    local p = root .. '/' .. folder .. '/' .. filename
    if vim.fn.filereadable(p) == 1 then
      return p
    end
  end
  return nil
end

--- name 기준 배열 병합 (launch.json 의 configurations / compounds 용)
--- base 항목을 유지하고, over 에 같은 name 이 있으면 그 항목으로 통째로 교체, 새 name 이면 뒤에 추가
local function merge_named(base, over)
  local out, idx = {}, {}
  for _, item in ipairs(base) do
    out[#out + 1] = item
    if type(item) == 'table' and item.name ~= nil then
      idx[item.name] = #out
    end
  end
  for _, item in ipairs(over) do
    local name = type(item) == 'table' and item.name or nil
    if name ~= nil and idx[name] then
      out[idx[name]] = item
    else
      out[#out + 1] = item
      if name ~= nil then
        idx[name] = #out
      end
    end
  end
  return out
end

--- base 위에 over 를 병합한다.
---   - named_keys 에 지정된 키(배열): name 기준 병합
---   - 객체(딕셔너리) 값: 재귀적으로 깊은 병합 (vim.tbl_deep_extend 'force')
---   - 배열/스칼라 값: over 값으로 통째로 교체
---   - over 의 빈 객체 {} 는 "덮어쓸 것이 없음"으로 보고 base 의 객체를 유지
local function merge_data(base, over, named_keys)
  local out = vim.deepcopy(base)
  for k, v in pairs(over) do
    local cur = out[k]
    if named_keys[k] and vim.islist(cur or {}) and type(cur) == 'table' and type(v) == 'table' and vim.islist(v) then
      out[k] = merge_named(cur, v)
    elseif type(cur) == 'table' and type(v) == 'table' and not vim.islist(cur) then
      if next(v) == nil then
        out[k] = cur
      elseif vim.islist(v) then
        out[k] = v
      else
        out[k] = vim.tbl_deep_extend('force', cur, v)
      end
    else
      out[k] = v
    end
  end
  return out
end

--- .vscode/<filename> 을 바탕으로 읽고 .nvim/<filename> 을 위에 덮어써 병합한다.
--- @param filename string 'settings.json' 또는 'launch.json'
--- @param root_path string|nil
--- @param named_keys table<string, boolean> name 기준으로 병합할 배열 키 집합
--- @return table 병합된 데이터 (파일이 없으면 빈 테이블)
--- @return string|nil 주된 파일 경로 (.nvim 이 있으면 .nvim, 없으면 .vscode)
local function load_merged(filename, root_path, named_keys)
  local root = root_path or M.get_project_root()
  if not root or root == '' then
    root = vim.fn.getcwd()
  end
  root = root:gsub('/+$', '')

  local merged, primary = {}, nil
  for _, folder in ipairs({ '.vscode', '.nvim' }) do -- 낮은 우선순위부터 적용
    local p = root .. '/' .. folder .. '/' .. filename
    if vim.fn.filereadable(p) == 1 then
      local data = read_json_file(p)
      if type(data) == 'table' then
        merged = merge_data(merged, data, named_keys or {})
      end
      primary = p
    end
  end
  return merged, primary
end

--- settings.json 로드: .vscode/settings.json 위에 .nvim/settings.json 을 병합
--- (객체는 깊은 병합, 배열/스칼라는 .nvim 값으로 교체)
--- @param root_path string|nil
--- @return table settings 데이터 (없으면 빈 테이블)
--- @return string|nil 파일 경로
function M.get_settings(root_path)
  return load_merged('settings.json', root_path)
end

--- launch.json 로드: .vscode/launch.json 위에 .nvim/launch.json 을 병합
--- configurations / compounds 는 name 기준 병합 (같은 name 은 .nvim 항목으로 교체, 새 name 은 추가)
--- @param root_path string|nil
--- @return table launch 데이터 (없으면 빈 테이블)
--- @return string|nil 파일 경로
function M.get_launch(root_path)
  return load_merged('launch.json', root_path, { configurations = true, compounds = true })
end

--- launch.json의 첫 번째 Java 메인 실행 클래스(mainClass) 획득
--- @param root_path string|nil
--- @return string|nil mainClass
--- @return string|nil launch.json 파일 경로
function M.get_main_class(root_path)
  local data, path = M.get_launch(root_path)
  if type(data.configurations) == 'table' then
    for _, cfg in ipairs(data.configurations) do
      local cfg_type = type(cfg.type) == 'string' and cfg.type:lower() or ''
      if cfg_type == 'java' and cfg.mainClass and cfg.mainClass ~= '' then
        return vim.trim(tostring(cfg.mainClass)), path
      end
    end
  end
  return nil, path
end

--- 캐시 초기화 (프로젝트 구조/설정 변경 후 호출)
function M.clear_cache()
  _cache = {}
end

return M
