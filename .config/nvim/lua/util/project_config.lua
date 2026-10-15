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
--- @param dir string|nil
--- @return string|nil
local function check_custom_root(dir)
  if not dir or dir == '' then
    return nil
  end
  for _, folder in ipairs({ '.nvim', '.vscode' }) do
    local sp = dir .. '/' .. folder .. '/settings.json'
    local data = read_json_file(sp)
    if data and data['nvim.projectRoot'] then
      return vim.fn.fnamemodify(dir .. '/' .. tostring(data['nvim.projectRoot']), ':p'):gsub('/+$', '')
    end
  end
  return nil
end

--- 프로젝트 루트 디렉토리 결정
--- 파일 위치에서 위로 거슬러 올라가며 프로젝트 최상위 루트를 검색합니다.
--- 멀티 모듈(settings.gradle / settings.gradle.kts / parent pom.xml)과 일반 프로젝트 모두 자동 인식합니다.
--- @param start_path string|nil 탐색 시작 경로 (파일 경로 또는 디렉토리)
--- @return string 정규화된 루트 경로
function M.get_project_root(start_path)
  local current_path = start_path or vim.api.nvim_buf_get_name(0)
  if current_path == '' then
    current_path = vim.fn.getcwd()
  end
  local cwd = vim.fn.getcwd()

  -- 0. .nvim/settings.json 또는 .vscode/settings.json 의 nvim.projectRoot 커스텀 설정 확인 (최우선)
  local custom_from_cwd = check_custom_root(cwd)
  if custom_from_cwd then
    return custom_from_cwd
  end

  -- 워크스페이스를 식별하는 핵심 마커 (.nvim -> .vscode 최우선)
  local root_markers = { '.nvim', '.vscode', '.git', 'settings.gradle', 'settings.gradle.kts', 'gradlew', 'mvnw' }

  -- 1. nvim 실행 디렉토리(CWD) 기준 탐색 우선
  -- 현재 파일이 nvim이 실행된 위치(또는 그 상위 루트)의 하위에 있다면 해당 루트를 선택
  local cwd_root = vim.fs.root(cwd, root_markers)
  if cwd_root and current_path:find(cwd_root, 1, true) == 1 then
    return check_custom_root(cwd_root) or cwd_root
  end

  -- 2. nvim 실행 디렉토리(CWD) 기준 하위(파일 방향)로 탐색
  -- CWD가 워크스페이스의 부모(예: ~/workspaces)인 경우, 파일 경로상 가장 먼저 만나는 프로젝트 루트를 선택
  if current_path:find(cwd, 1, true) == 1 then
    local rel_path = current_path:sub(#cwd + 1)
    local segment_acc = cwd
    for segment in rel_path:gmatch('[^/]+') do
      segment_acc = segment_acc .. '/' .. segment
      if vim.fn.isdirectory(segment_acc) == 1 then
        for _, marker in ipairs(root_markers) do
          if
            vim.fn.filereadable(segment_acc .. '/' .. marker) == 1
            or vim.fn.isdirectory(segment_acc .. '/' .. marker) == 1
          then
            return check_custom_root(segment_acc) or segment_acc
          end
        end
      end
    end
  end

  -- 3. 파일 위치 기준 상향 탐색 (파일이 CWD 밖에 있는 경우 등)
  local root = vim.fs.root(current_path, root_markers)
  if root then
    return check_custom_root(root) or root
  end

  -- 4. 폴백: 일반 프로젝트 또는 개별 모듈 마커 탐색
  local fallback_markers = { 'build.gradle', 'build.gradle.kts', 'pom.xml' }
  local fallback_root = vim.fs.root(current_path, fallback_markers) or cwd
  return check_custom_root(fallback_root) or fallback_root
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
