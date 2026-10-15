--[[
===========================================================================================
[프로젝트 설정 통합 로더: util.project_config]
===========================================================================================
프로젝트 설정(settings.json) 및 디버깅 실행 구성(launch.json)의 단일 원본(SSOT) 관리자입니다.
Neovim과 VS Code 간의 완벽한 설정 일원화를 위해 공통 탐색 우선순위를 제공합니다:

탐색 우선순위:
  1. 프로젝트 루트의 `.nvim/` 디렉토리 (Neovim 전용 설정 최우선)
     - `.nvim/settings.json`
     - `.nvim/launch.json`
  2. 프로젝트 루트의 `.vscode/` 디렉토리 (VS Code와 공통 공유)
     - `.vscode/settings.json`
     - `.vscode/launch.json`
  3. 설정 파일이 없는 경우: 시스템 기본값 및 자동 탐색으로 안전하게 폴백

지원하는 주요 키:
  - settings.json:
    - nvim.projectRoot (string)        : 프로젝트 루트 수동 지정 (옵션)
    - java.import.gradle.java.home     : Gradle 데몬 및 JDTLS 구동용 JDK 경로 (VS Code 표준)
    - java.configuration.runtimes      : 프로젝트 빌드 런타임 목록 및 default 지정 (VS Code 표준)
  - launch.json:
    - configurations[].mainClass       : Java 실행 구성의 메인 클래스 (자동 기동 및 DAP 디버깅 공통)
===========================================================================================
--]]

local M = {}

-- 캐시 테이블 (불필요한 반복 디스크 I/O 방지)
local _cache = {}

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

--- 설정 파일 경로 탐색 (.nvim/ 1순위 -> .vscode/ 2순위)
--- @param filename string 'settings.json' 또는 'launch.json'
--- @param root_path string|nil 탐색 기준 루트 (nil이면 CWD)
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

--- settings.json의 nvim.projectRoot 커스텀 설정을 확인하는 내부 헬퍼
--- @param path string|nil 파일 경로 또는 디렉토리
--- @return string|nil
local function check_custom_root(path)
  if not path or path == '' then
    return nil
  end
  local target_dir = vim.fn.isdirectory(path) == 1 and path or vim.fs.dirname(path)
  if not target_dir or target_dir == '' then
    return nil
  end
  target_dir = vim.fs.normalize(target_dir):gsub('/+$', '')

  for _, folder in ipairs({ '.nvim', '.vscode' }) do
    local sp = target_dir .. '/' .. folder .. '/settings.json'
    local data = read_json_file(sp)
    if data and data['nvim.projectRoot'] then
      local custom_path = vim.fn.fnamemodify(target_dir .. '/' .. tostring(data['nvim.projectRoot']), ':p')
      return vim.fs.normalize(custom_path):gsub('/+$', '')
    end
  end
  return nil
end

--- 프로젝트 루트 디렉토리 결정 (재귀적/멀티모듈 완전 대응)
--- 단일 모듈뿐만 아니라 Gradle Composite Build, 재귀적 Maven 멀티모듈(<modules> 계층 구조),
--- Git Monorepo 환경에서도 오차 없이 최상위 프로젝트 루트를 정확히 확정합니다.
---
--- 핵심 설계 원칙 (Recursive Multi-Module Principles):
---   1. CWD 일치 우선 원칙 (CWD Enclosure):
---      개발자가 최상위 루트에서 nvim을 열었다면, 하위에 또 다른 중첩 settings.gradle이나 pom.xml이 있더라도
---      사용자의 명확한 작업 범위(CWD)를 프로젝트 루트로 최우선 확정합니다.
---   2. 부모 폴더 실행 시 하향 탐색 (Top-down First Enclosing):
---      CWD가 ~/workspaces 등 상위 디렉토리인 경우, 파일 경로상 가장 먼저 만나는 최상위 프로젝트 컨테이너를 포착합니다.
---   3. 상향 탐색 시 최상위 마커 우선 (Topmost Marker Search):
---      하위 모듈에 국지적 pom.xml이나 서브 settings.gradle이 있더라도, 상위로 거슬러 올라가며
---      발견되는 '가장 높은(Topmost)' 부모 프로젝트 마커를 찾아 재귀적 구조를 완벽히 포괄합니다.
---
--- @param start_path string|nil 탐색 시작 경로 (파일 경로 또는 디렉토리)
--- @return string 정규화된 루트 경로
function M.get_project_root(start_path)
  local current_path = start_path or vim.api.nvim_buf_get_name(0)
  if current_path == '' then
    current_path = vim.fn.getcwd()
  end
  current_path = vim.fs.normalize(current_path)
  local cwd = vim.fs.normalize(vim.fn.getcwd())

  -- [Tier 0: 명시적 커스텀 루트 (최우선)]
  -- CWD 또는 current_path 상위에서 nvim.projectRoot 설정이 발견되면 즉시 확정
  local custom_from_cwd = check_custom_root(cwd)
  if custom_from_cwd then
    return custom_from_cwd
  end
  local custom_from_file = check_custom_root(current_path)
  if custom_from_file then
    return custom_from_file
  end

  -- 핵심 워크스페이스 식별 마커 목록
  local top_markers = { 'settings.gradle', 'settings.gradle.kts', 'gradlew', 'mvnw', '.git' }
  local single_markers = { 'build.gradle', 'build.gradle.kts', 'pom.xml' }

  -- 디렉토리에 대상 마커가 하나라도 존재하는지 확인하는 헬퍼
  local function has_any_marker(dir, markers)
    for _, m in ipairs(markers) do
      if vim.fn.filereadable(dir .. '/' .. m) == 1 or vim.fn.isdirectory(dir .. '/' .. m) == 1 then
        return true
      end
    end
    return false
  end

  -- ===========================================================================================
  -- 1. nvim 실행 디렉토리(CWD) 기준 탐색 우선 (CWD Enclosure)
  -- 현재 파일이 nvim이 실행된 위치(또는 그 상위 루트)의 하위에 있다면 해당 루트를 선택
  -- (CWD 자체가 프로젝트 루트인 경우, 하위에 또 다른 중첩 settings.gradle이 있더라도 CWD를 최우선 확정)
  -- ===========================================================================================
  if has_any_marker(cwd, top_markers) or has_any_marker(cwd, single_markers) then
    if current_path == cwd or current_path:find(cwd .. '/', 1, true) == 1 then
      return check_custom_root(cwd) or cwd
    end
  end

  -- ===========================================================================================
  -- 2. nvim 실행 디렉토리(CWD) 기준 하위(파일 방향)로 탐색
  -- CWD가 워크스페이스의 부모(예: ~/workspaces)인 경우, 파일 경로상 가장 먼저 만나는 프로젝트 루트를 선택
  -- (중첩 모듈 내부로 깊이 들어가지 않고, 최상위 컨테이너 프로젝트를 먼저 포착)
  -- ===========================================================================================
  if current_path:find(cwd .. '/', 1, true) == 1 then
    local rel_path = current_path:sub(#cwd + 2)
    local segment_acc = cwd
    for segment in rel_path:gmatch('[^/]+') do
      segment_acc = segment_acc .. '/' .. segment
      if vim.fn.isdirectory(segment_acc) == 1 then
        if has_any_marker(segment_acc, top_markers) or has_any_marker(segment_acc, single_markers) then
          return check_custom_root(segment_acc) or segment_acc
        end
      end
    end
  end

  -- ===========================================================================================
  -- 3. 파일 위치 기준 상향 탐색: 최상위 마커 우선 탐색 (Topmost Search)
  -- 중첩된 복합 빌드(Composite Build) 또는 재귀적 멀티모듈 환경에서
  -- 하위 모듈에서 멈추지 않고 상위로 거슬러 올라가며 가장 높은(Topmost) 프로젝트 루트를 확정
  -- ===========================================================================================
  local topmost_root = nil
  for dir in vim.fs.parents(current_path) do
    if has_any_marker(dir, top_markers) then
      topmost_root = dir
    end
  end
  if topmost_root then
    return check_custom_root(topmost_root) or vim.fs.normalize(topmost_root):gsub('/+$', '')
  end

  -- ===========================================================================================
  -- 4. 폴백: 단일 모듈 빌드 마커 중 최상위 부모 탐색 (Topmost Maven POM / Gradle Build)
  -- Maven 재귀 멀티모듈의 경우 말단 모듈의 pom.xml이 아닌 최상위 부모 pom.xml을 포착
  -- ===========================================================================================
  local topmost_single = nil
  for dir in vim.fs.parents(current_path) do
    if has_any_marker(dir, single_markers) then
      topmost_single = dir
    end
  end
  if topmost_single then
    return check_custom_root(topmost_single) or vim.fs.normalize(topmost_single):gsub('/+$', '')
  end

  return cwd
end

--- settings.json 로드 (.nvim/ 1순위 -> .vscode/ 2순위)
--- @param root_path string|nil
--- @return table settings 데이터 (없으면 빈 테이블)
--- @return string|nil 파일 경로
function M.get_settings(root_path)
  local root = root_path or M.get_project_root()
  local path = M.find_file('settings.json', root)
  if path then
    return read_json_file(path) or {}, path
  end
  return {}, nil
end

--- launch.json 로드 (.nvim/ 1순위 -> .vscode/ 2순위)
--- @param root_path string|nil
--- @return table launch 데이터 (없으면 빈 테이블)
--- @return string|nil 파일 경로
function M.get_launch(root_path)
  local root = root_path or M.get_project_root()
  local path = M.find_file('launch.json', root)
  if path then
    return read_json_file(path) or {}, path
  end
  return {}, nil
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

--- 캐시 초기화
function M.clear_cache()
  _cache = {}
end

return M
