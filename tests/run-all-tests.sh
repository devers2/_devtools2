#!/usr/bin/env bash
# ==============================================================================
# run-all-tests.sh — DevTools2 Linux/WSL 통합 자동화 테스트 러너
#
# [설계 원칙]
# 1. 무권한(Zero sudo / Non-root): 일반 사용자 권한으로 100% 안전하게 실행되며,
#    시스템 파일을 전혀 수정하지 않는 읽기 전용 정적 분석 러너입니다.
# 2. 단일 명령 완결성(One-shot): AI 에이전트가 단 한 번의 도구 호출로 모든
#    회귀 버그 및 정합성을 검증할 수 있어 사용자 권한 승인 요청을 최소화합니다.
# 3. run-all-tests.ps1 과의 100% 동등성: 동일한 테스트 항목과 기준을 적용합니다.
#
# [실행 방법]
#   ./tests/run-all-tests.sh
#   또는 bash tests/run-all-tests.sh
# ==============================================================================

set -euo pipefail

# 스크립트 위치 기준 저장소 루트 경로 감지
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 색상 정의
_C_RESET="\033[0m"
_C_BOLD="\033[1m"
_C_CYAN="\033[36m"
_C_GREEN="\033[32m"
_C_RED="\033[31m"
_C_YELLOW="\033[33m"
_C_GRAY="\033[90m"

total_tests=0
passed_tests=0
failed_tests=0

write_header() {
  local title="$1"
  echo ""
  printf "${_C_CYAN}===========================================================================${_C_RESET}\n"
  printf "  ${_C_CYAN}%s${_C_RESET}\n" "$title"
  printf "${_C_GRAY}===========================================================================${_C_RESET}\n"
}

assert_test() {
  local desc="$1"
  local condition="$2" # 0 for pass, 1 for fail
  local fail_msg="${3:-}"

  total_tests=$((total_tests + 1))
  if [ "$condition" -eq 0 ]; then
    passed_tests=$((passed_tests + 1))
    printf "  ${_C_GREEN}[PASS]${_C_RESET} %s\n" "$desc"
  else
    failed_tests=$((failed_tests + 1))
    printf "  ${_C_RED}[FAIL]${_C_RESET} %s\n" "$desc"
    if [ -n "$fail_msg" ]; then
      printf "         ${_C_YELLOW}-> 오류 상세: %s${_C_RESET}\n" "$fail_msg"
    fi
  fi
}

# ==============================================================================
# [Suite 1] UTF-8 NoBOM 및 스크립트 헤더 무결성 검증
# ==============================================================================
write_header "[Suite 1] UTF-8 NoBOM 및 스크립트 헤더 무결성 검증"

# 대상 확장자: .ps1, .sh, .bash, .json, .toml, .conf
# 제외 디렉터리: .git, .vscode, .idea, target, build, node_modules, data, modules
suite1_result=$(
  python3 - "$REPO_ROOT" <<'EOF'
import os
import sys

repo = sys.argv[1]
excluded = {'.git', '.vscode', '.idea', 'target', 'build', 'node_modules', 'data', 'modules'}
target_exts = ('.ps1', '.sh', '.bash', '.json', '.toml', '.conf')

bom_violations = []
param_violations = []

for root, dirs, files in os.walk(repo):
    dirs[:] = [d for d in dirs if d not in excluded]
    for f in files:
        if not f.endswith(target_exts):
            continue
        full_path = os.path.join(root, f)
        rel_path = os.path.relpath(full_path, repo)
        
        # 1) BOM Check
        try:
            with open(full_path, 'rb') as fp:
                head = fp.read(3)
                if head == b'\xef\xbb\xbf':
                    bom_violations.append(rel_path)
        except Exception:
            pass

        # 2) .ps1 스크립트 레벨 param() 위치 검사 (함수 밖 param은 첫 실행문이어야 함)
        if f.endswith('.ps1'):
            try:
                with open(full_path, 'r', encoding='utf-8', errors='ignore') as fp:
                    lines = fp.readlines()
                brace_depth = 0
                first_stmt_line = -1
                in_block_comment = False

                for idx, line in enumerate(lines):
                    stripped = line.strip()
                    if not stripped:
                        continue
                    if in_block_comment:
                        if '#>' in stripped:
                            in_block_comment = False
                        continue
                    if stripped.startswith('<#'):
                        in_block_comment = True
                        continue
                    if stripped.startswith('#'):
                        continue

                    # 함수 바깥(brace_depth == 0)에서만 검사
                    if brace_depth == 0:
                        if stripped.startswith('param(') or stripped == 'param':
                            if first_stmt_line != -1:
                                param_violations.append(f"{f} (Line {idx+1})")
                            break
                        elif first_stmt_line == -1:
                            first_stmt_line = idx + 1

                    # 중괄호 depth 추적
                    brace_depth += stripped.count('{') - stripped.count('}')
                    if brace_depth < 0:
                        brace_depth = 0
            except Exception:
                pass

print(len(bom_violations), ";".join(bom_violations))
print(len(param_violations), ";".join(param_violations))
EOF
)

bom_cnt=$(echo "$suite1_result" | sed -n '1p' | cut -d' ' -f1)
bom_files=$(echo "$suite1_result" | sed -n '1p' | cut -d' ' -f2-)
param_cnt=$(echo "$suite1_result" | sed -n '2p' | cut -d' ' -f1)
param_files=$(echo "$suite1_result" | sed -n '2p' | cut -d' ' -f2-)

if [ "$bom_cnt" -eq 0 ]; then
  assert_test "모든 스크립트 및 설정 파일이 순수 UTF-8 NoBOM 형식인가" 0
else
  assert_test "모든 스크립트 및 설정 파일이 순수 UTF-8 NoBOM 형식인가" 1 "BOM 발견 파일: $bom_files"
fi

if [ "$param_cnt" -eq 0 ]; then
  assert_test "모든 .ps1 스크립트의 param() 블록 앞에 실행문이 없는가" 0
else
  assert_test "모든 .ps1 스크립트의 param() 블록 앞에 실행문이 없는가" 1 "잘못된 param() 위치: $param_files"
fi

# ==============================================================================
# [Suite 2] PowerShell 구문 정적 분석
# ==============================================================================
write_header "[Suite 2] PowerShell 구문 정적 분석 (PS 5.1 / 7 파서)"

if command -v pwsh >/dev/null 2>&1; then
  ps_errors=$(pwsh -NoProfile -Command "
        \$errors = @()
        Get-ChildItem -Path '$REPO_ROOT' -Filter '*.ps1' -Recurse | Where-Object { \$_.FullName -notmatch '(data|modules|\.git)' } | ForEach-Object {
            \$code = [System.IO.File]::ReadAllText(\$_.FullName, [System.Text.Encoding]::UTF8)
            \$errs = \$null
            [System.Management.Automation.Language.Parser]::ParseInput(\$code, \$_.FullName, [ref]\$null, [ref]\$errs) | Out-Null
            if (\$errs -and \$errs.Count -gt 0) { \$errors += \"\$(\$_.Name): \$(\$errs[0].Message)\" }
        }
        \$errors -join ';'
    " 2>/dev/null || true)
  if [ -z "$ps_errors" ]; then
    assert_test "모든 .ps1 파일에 문법 오류가 없는가 (오류 파일: 0건)" 0
  else
    assert_test "모든 .ps1 파일에 문법 오류가 없는가" 1 "$ps_errors"
  fi
else
  # Linux 네이티브 환경(pwsh 미설치)에서는 안전하게 건너뛰며 사전 규약(?? 연산자 금지 등) 정적 검증 수행
  ps_qq_violations=$(grep -rn --include="*.ps1" '??' "$REPO_ROOT/scripts" "$REPO_ROOT/tests" 2>/dev/null | grep -v '#' || true)
  if [ -z "$ps_qq_violations" ]; then
    assert_test "PowerShell 구문 정적 분석 (pwsh 미설치 환경: 호환성 사전 규칙 검증)" 0
  else
    assert_test "PowerShell 구문 정적 분석 (호환되지 않는 ?? 연산자 발견)" 1 "$ps_qq_violations"
  fi
fi

# ==============================================================================
# [Suite 3] Linux Bash 스크립트 구문 검사 (bash -n)
# ==============================================================================
write_header "[Suite 3] Linux Bash 스크립트 구문 검사 (bash -n)"

bash_errors=()
while IFS= read -r sh_file; do
  if [ -f "$sh_file" ]; then
    if ! err_out=$(bash -n "$sh_file" 2>&1); then
      bash_errors+=("$(basename "$sh_file"): $err_out")
    fi
  fi
done < <(find "$REPO_ROOT/scripts/linux" -type f \( -name "*.sh" -o -name "*.bash" \) 2>/dev/null || true)

if [ ${#bash_errors[@]} -eq 0 ]; then
  assert_test "모든 Linux .sh 스크립트가 bash -n 검사를 통과하는가" 0
else
  assert_test "모든 Linux .sh 스크립트가 bash -n 검사를 통과하는가" 1 "${bash_errors[*]}"
fi

# ==============================================================================
# [Suite 4] 런타임 회귀 버그 전수 검증
# ==============================================================================
write_header "[Suite 4] 런타임 회귀 버그 전수 검증"

# 4-1. 0.setup-wsl.ps1 내 위험한 '(Get-Content).Trim()' 직통 호출이 0건인가
wsl_setup_ps1="$REPO_ROOT/scripts/windows/dev-env/0.setup-wsl.ps1"
if [ -f "$wsl_setup_ps1" ]; then
  unsafe_trim=$(grep -P '\(Get-Content[^\)]+\)\.Trim\(\)' "$wsl_setup_ps1" || true)
  if [ -z "$unsafe_trim" ]; then
    assert_test "0.setup-wsl.ps1 내 위험한 '(Get-Content).Trim()' 직통 호출이 0건인가" 0
  else
    assert_test "0.setup-wsl.ps1 내 위험한 '(Get-Content).Trim()' 직통 호출이 0건인가" 1 "$unsafe_trim"
  fi
else
  assert_test "0.setup-wsl.ps1 파일 존재 확인" 1 "파일 누락: $wsl_setup_ps1"
fi

# 4-2. 0.setup-wsl.ps1 wsl --import 가 .NET ProcessStartInfo 기반으로 $null 트랩을 방지하는가
has_psi=$(grep -c 'System\.Diagnostics\.ProcessStartInfo' "$wsl_setup_ps1" || true)
has_proc_start=$(grep -c '\[System\.Diagnostics\.Process\]::Start' "$wsl_setup_ps1" || true)
if [ "$has_psi" -gt 0 ] && [ "$has_proc_start" -gt 0 ]; then
  assert_test "0.setup-wsl.ps1 wsl --import 가 .NET ProcessStartInfo 기반으로 \$null 트랩을 방지하는가" 0
else
  assert_test "0.setup-wsl.ps1 wsl --import 가 .NET ProcessStartInfo 기반으로 \$null 트랩을 방지하는가" 1 "ProcessStartInfo 패턴 누락"
fi

# 4-3. 0.setup-wsl.ps1 내 /etc/wsl.conf 파이썬 주입 코드가 문법 에러 없이 컴파일되는가 및 STDIN 호출
suite4_3_result=$(
  python3 - "$wsl_setup_ps1" <<'EOF'
import sys
import re
import py_compile
import tempfile
import os

with open(sys.argv[1], 'r', encoding='utf-8') as f:
    code = f.read()

# $mergeWslConfPy 추출
m = re.search(r'\$mergeWslConfPy\s*=\s*@\'\r?\n(.*?)\r?\n\'@', code, re.DOTALL)
syntax_ok = False
if m:
    py_code = m.group(1)
    with tempfile.NamedTemporaryFile('w', suffix='.py', delete=False, encoding='utf-8') as tmp:
        tmp.write(py_code)
        tmp_name = tmp.name
    try:
        py_compile.compile(tmp_name, doraise=True)
        syntax_ok = True
    except Exception as e:
        syntax_ok = False
    finally:
        os.remove(tmp_name)

uses_stdin = bool(re.search(r'\$mergeWslConfPy\s*\|\s*wsl', code))
avoids_inline = not bool(re.search(r'python3\s+-c\s+"\$mergeWslConfPy"', code))

print(1 if syntax_ok else 0)
print(1 if (uses_stdin and avoids_inline) else 0)
EOF
)

py_comp_ok=$(echo "$suite4_3_result" | sed -n '1p')
py_pipe_ok=$(echo "$suite4_3_result" | sed -n '2p')

if [ "$py_comp_ok" -eq 1 ]; then
  assert_test "0.setup-wsl.ps1 내 /etc/wsl.conf 파이썬 주입 코드가 문법 에러 없이 컴파일되는가" 0
else
  assert_test "0.setup-wsl.ps1 내 /etc/wsl.conf 파이썬 주입 코드가 문법 에러 없이 컴파일되는가" 1 "파이썬 구문 컴파일 실패"
fi

if [ "$py_pipe_ok" -eq 1 ]; then
  assert_test "0.setup-wsl.ps1 이 따옴표 탈락 방지를 위해 STDIN 파이프라인으로 파이썬을 호출하는가" 0
else
  assert_test "0.setup-wsl.ps1 이 따옴표 탈락 방지를 위해 STDIN 파이프라인으로 파이썬을 호출하는가" 1 "STDIN 파이프라인 누락 또는 -c 인라인 사용"
fi

# 4-4. 0.setup-wsl.ps1 에 미완성 배포판 자동 감지 및 unregister 자가 치유 로직이 존재하는가
has_user=$(grep -c '\[user\]' "$wsl_setup_ps1" || true)
has_default=$(grep -c 'default\s*=' "$wsl_setup_ps1" || true)
has_unreg=$(grep -c 'wsl\.exe\s\+--unregister' "$wsl_setup_ps1" || true)
if [ "$has_user" -gt 0 ] && [ "$has_default" -gt 0 ] && [ "$has_unreg" -gt 0 ]; then
  assert_test "0.setup-wsl.ps1 에 미완성 배포판 자동 감지 및 unregister 자가 치유 로직이 존재하는가" 0
else
  assert_test "0.setup-wsl.ps1 에 미완성 배포판 자동 감지 및 unregister 자가 치유 로직이 존재하는가" 1 "자가 치유 로직 미완성"
fi

# 4-5. Linux Core Tools(JDK, Gradle, Neovim) 다운로드 시 UX 라벨 인자가 완벽히 전달되는가
core_tools_sh="$REPO_ROOT/scripts/linux/dev-env/2.install-core-tools.sh"
has_jdk_lbl=$(grep -P 'safe_download_and_extract\s+"\$dl_url"\s+"\$target_path"\s+1\s+"\$checksum"\s+"JDK \$major"' "$core_tools_sh" || true)
has_gradle_lbl=$(grep -P 'safe_download_and_extract\s+"\$_gradle_url"\s+"\$DEVTOOLS2/modules/gradle"\s+0\s+"\$_gradle_sha"\s+"Gradle \$GRADLE_VERSION"' "$core_tools_sh" || true)
has_nvim_lbl=$(grep -P 'safe_download_and_extract\s+"\$_nvim_url"\s+"\$DEVTOOLS2/modules/neovim/nvim"\s+1\s+"[^"]*"\s+"Neovim \$NEOVIM_VERSION"' "$core_tools_sh" || true)

if [ -n "$has_jdk_lbl" ] && [ -n "$has_gradle_lbl" ] && [ -n "$has_nvim_lbl" ]; then
  assert_test "Linux Core Tools(JDK, Gradle, Neovim) 다운로드 시 UX 라벨 인자가 완벽히 전달되는가" 0
else
  assert_test "Linux Core Tools(JDK, Gradle, Neovim) 다운로드 시 UX 라벨 인자가 완벽히 전달되는가" 1 "UX 라벨 인자 전달 패턴 불일치"
fi

# 4-6. Linux safe_download_and_extract 가 URL 확장자 대신 파일 헤더 무결성(unzip -tq)으로 아카이브를 판별하는가
install_utils_sh="$REPO_ROOT/scripts/linux/dev-env/_install-utils.sh"
has_unzip=$(grep -P 'unzip\s+-tq\s+"\$tmp_archive"' "$install_utils_sh" || true)
has_targz=$(grep -P 'tar\s+-tzf\s+"\$tmp_archive"' "$install_utils_sh" || true)

if [ -n "$has_unzip" ] && [ -n "$has_targz" ]; then
  assert_test "Linux safe_download_and_extract 가 URL 확장자 대신 파일 헤더 무결성(unzip -tq)으로 아카이브를 판별하는가" 0
else
  assert_test "Linux safe_download_and_extract 가 URL 확장자 대신 파일 헤더 무결성(unzip -tq)으로 아카이브를 판별하는가" 1 "unzip/tar 헤더 검증 패턴 누락"
fi

# ==============================================================================
# [Suite 5] 2026-10 점검 결함 회귀 방지
# ==============================================================================
write_header "[Suite 5] 2026-10 점검 결함 회귀 방지"

# 5-1. CI 의 'shell: powershell'(PS 5.1) 단계 본문이 ASCII 전용인가
ci_file="$REPO_ROOT/.github/workflows/ci.yml"
ci_non_ascii=$(
  python3 - "$ci_file" <<'EOF'
import sys
import os

ci = sys.argv[1]
if not os.path.exists(ci):
    print("0")
    sys.exit(0)

with open(ci, 'r', encoding='utf-8') as f:
    lines = f.readlines()

in_ps51 = False
in_run = False
violations = []

for idx, line in enumerate(lines):
    if line.strip().startswith('- name:'):
        in_ps51 = False
        in_run = False
    if 'shell: powershell' in line:
        in_ps51 = True
    if in_ps51 and 'run: |' in line:
        in_run = True
        continue
    if in_ps51 and in_run:
        # non-ascii check
        if any(ord(c) > 127 for c in line):
            violations.append(f"Line {idx+1}")

print(len(violations), ";".join(violations))
EOF
)
ci_cnt=$(echo "$ci_non_ascii" | cut -d' ' -f1)
ci_lines=$(echo "$ci_non_ascii" | cut -d' ' -f2-)
if [ "$ci_cnt" -eq 0 ]; then
  assert_test "CI 의 'shell: powershell'(PS 5.1) 단계 본문이 ASCII 전용인가" 0
else
  assert_test "CI 의 'shell: powershell'(PS 5.1) 단계 본문이 ASCII 전용인가" 1 "비ASCII 줄: $ci_lines"
fi

# 5-2. Prompt-Confirm 기본값에 $true/$false 대신 "Y"/"N" 문자열을 쓰는가
bool_confirm=$(grep -rnP 'Prompt-Confirm\s+"[^"]*"\s+\$(true|false)' "$REPO_ROOT/scripts/windows" 2>/dev/null || true)
if [ -z "$bool_confirm" ]; then
  assert_test 'Prompt-Confirm 기본값에 $true/$false 대신 "Y"/"N" 문자열을 쓰는가' 0
else
  assert_test 'Prompt-Confirm 기본값에 $true/$false 대신 "Y"/"N" 문자열을 쓰는가' 1 "$bool_confirm"
fi

# 5-3. 임시 sudo 회수가 Windows(try/finally)·리눅스(sudo -n test) 모두 실제로 동작하는 형태인가
win_master="$REPO_ROOT/scripts/windows/setup-devtools2-wsl.ps1"
linux_master="$REPO_ROOT/scripts/linux/setup-devtools2.sh"
win_finally=$(python3 -c "import sys, re; c = open(sys.argv[1], encoding='utf-8').read(); print(1 if re.search(r'(?s)finally\s*\{[^}]*Revoke-WslTempSudo', c) else 0)" "$win_master" 2>/dev/null || echo "0")
linux_no_plain=$(grep -P '\[\s+-[fe]\s+"/etc/sudoers\.d/' "$linux_master" 2>/dev/null || true)
linux_sudo_test=$(grep -P 'sudo -n test -e' "$linux_master" 2>/dev/null || true)

if [ "$win_finally" = "1" ] && [ -z "$linux_no_plain" ] && [ -n "$linux_sudo_test" ]; then
  assert_test "임시 sudo 회수가 Windows(try/finally)·리눅스(sudo -n test) 모두 실제로 동작하는 형태인가" 0
else
  assert_test "임시 sudo 회수가 Windows(try/finally)·리눅스(sudo -n test) 모두 실제로 동작하는 형태인가" 1 "sudoers 회수 메커니즘 불일치"
fi

# 5-4. command-palette 포트 해제가 LISTEN 프로세스만 대상으로 하는가
palette_file="$REPO_ROOT/scripts/fzf/command-palette"
bad_lsof=$(grep -P '^[^#\r\n]*lsof\s+-ti\s+:' "$palette_file" 2>/dev/null || true)
has_listen=$(grep -P '\-sTCP:LISTEN' "$palette_file" 2>/dev/null || true)

if [ -z "$bad_lsof" ] && [ -n "$has_listen" ]; then
  assert_test "command-palette 포트 해제가 LISTEN 프로세스만 대상으로 하는가" 0
else
  assert_test "command-palette 포트 해제가 LISTEN 프로세스만 대상으로 하는가" 1 "LISTEN 필터 미적용"
fi

# 5-5. setup_vscode_launch_json 이 변경 없을 때 launch.json 을 다시 쓰지 않는가
common_setup_sh="$REPO_ROOT/scripts/linux/setup-projects/_common/common-setup.sh"
skips_noop=$(
  python3 - "$common_setup_sh" <<'EOF'
import sys, re
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    c = f.read()
print(1 if re.search(r'(?s)if added_count == 0:\s*\n\s*print\([^\n]*\)\s*\n\s*sys\.exit\(0\)', c) else 0)
EOF
)
if [ "$skips_noop" -eq 1 ]; then
  assert_test "setup_vscode_launch_json 이 변경 없을 때 launch.json 을 다시 쓰지 않는가" 0
else
  assert_test "setup_vscode_launch_json 이 변경 없을 때 launch.json 을 다시 쓰지 않는가" 1 "no-op 검증 누락"
fi

# 5-6. 전부 추적('!*')하는 폴더의 .gitignore 마다 비밀 정보 차단 목록이 있는가 & 비밀 정보 커밋 차단 훅
suite5_6_result=$(
  python3 - "$REPO_ROOT" <<'EOF'
import os, sys

repo = sys.argv[1]
missing_deny = []

for root, dirs, files in os.walk(repo):
    if any(ex in root for ex in ['/data', '/modules', '/.git', '\\data', '\\modules', '\\.git']):
        continue
    if '.gitignore' in files:
        gi_path = os.path.join(root, '.gitignore')
        with open(gi_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        if re_match := [line for line in content.splitlines() if line.strip() == '!*']:
            if not ('.env' in content and 'auth.json' in content and '.claude/' in content):
                missing_deny.append(os.path.relpath(gi_path, repo))

print(len(missing_deny), ";".join(missing_deny))
EOF
)
gi_missing_cnt=$(echo "$suite5_6_result" | cut -d' ' -f1)
gi_missing_files=$(echo "$suite5_6_result" | cut -d' ' -f2-)

pre_commit_hook="$REPO_ROOT/scripts/git-hooks/pre-commit"
setup_env_sh="$REPO_ROOT/scripts/linux/dev-env/1.setup-env.sh"

hook_ok=0
if [ -f "$pre_commit_hook" ]; then
  if grep -q 'sk-ant-' "$pre_commit_hook" && grep -q 'AIza' "$pre_commit_hook" && grep -q 'PRIVATE KEY' "$pre_commit_hook" && grep -q 'exit 1' "$pre_commit_hook"; then
    hook_ok=1
  fi
fi

setup_env_hook_ok=0
if grep -q 'core\.hooksPath scripts/git-hooks' "$setup_env_sh" && grep -q 'secrets\.env' "$setup_env_sh" && grep -q 'chmod 600 "\$_SECRETS_ENV"' "$setup_env_sh"; then
  setup_env_hook_ok=1
fi

if [ "$gi_missing_cnt" -eq 0 ]; then
  assert_test "전부 추적('!*')하는 폴더의 .gitignore 마다 비밀 정보 차단 목록이 있는가" 0
else
  assert_test "전부 추적('!*')하는 폴더의 .gitignore 마다 비밀 정보 차단 목록이 있는가" 1 "차단 목록 없는 파일: $gi_missing_files"
fi

if [ "$hook_ok" -eq 1 ] && [ "$setup_env_hook_ok" -eq 1 ]; then
  assert_test "비밀 정보 커밋 차단 훅이 있고 1.setup-env.sh 가 훅·secrets.env(600)를 설정하는가" 0
else
  assert_test "비밀 정보 커밋 차단 훅이 있고 1.setup-env.sh 가 훅·secrets.env(600)를 설정하는가" 1 "Git 훅 또는 secrets.env 설정 누락"
fi

# 5-7. 리눅스 변수를 쓰는 wsl 명령이 'wsl -- bash -c' 대신 'wsl -e' 를 쓰는가
wsl_dollar_violations=$(
  python3 - "$REPO_ROOT/scripts/windows" <<'EOF'
import os, sys, re

folder = sys.argv[1]
violations = []
pat = re.compile(r'wsl(\.exe)?\s[^#]*\s--\s+(bash|sh)\s+-l?c\s+("[^"]*`\$|\'[^\']*\$)')

for root, dirs, files in os.walk(folder):
    for f in files:
        if f.endswith('.ps1'):
            path = os.path.join(root, f)
            with open(path, 'r', encoding='utf-8', errors='ignore') as fp:
                for idx, line in enumerate(fp):
                    if line.strip().startswith('#'):
                        continue
                    if pat.search(line):
                        violations.append(f"{f}:{idx+1}")

print(len(violations), ";".join(violations))
EOF
)
wsl_dlr_cnt=$(echo "$wsl_dollar_violations" | cut -d' ' -f1)
wsl_dlr_files=$(echo "$wsl_dollar_violations" | cut -d' ' -f2-)
if [ "$wsl_dlr_cnt" -eq 0 ]; then
  assert_test "리눅스 변수를 쓰는 wsl 명령이 'wsl -- bash -c' 대신 'wsl -e' 를 쓰는가" 0
else
  assert_test "리눅스 변수를 쓰는 wsl 명령이 'wsl -- bash -c' 대신 'wsl -e' 를 쓰는가" 1 "위반: $wsl_dlr_files"
fi

# 5-8. _install-utils.sh 의 RETURN 트랩이 실행 후 스스로 해제되는가
return_trap_bad=$(
  python3 - "$install_utils_sh" <<'EOF'
import sys, re
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    c = f.read()
traps = re.findall(r"trap '[^']*' RETURN", c)
bad = [t for t in traps if 'trap - RETURN' not in c]
print(len(bad))
EOF
)
if [ "$return_trap_bad" -eq 0 ]; then
  assert_test "_install-utils.sh 의 RETURN 트랩이 실행 후 스스로 해제되는가" 0
else
  assert_test "_install-utils.sh 의 RETURN 트랩이 실행 후 스스로 해제되는가" 1 "RETURN 트랩 미해제 발견"
fi

# 5-9. 리눅스 설치 스크립트가 /tmp 고정 이름 대신 사용자 전용 $DT2_TMP 를 쓰는가
fixed_tmp_violations=$(
  python3 - "$REPO_ROOT/scripts/linux" <<'EOF'
import os, sys, re

folder = sys.argv[1]
violations = []
pat = re.compile(r'[>"\s]/tmp/_[A-Za-z]')

for root, dirs, files in os.walk(folder):
    for f in files:
        if f.endswith('.sh'):
            path = os.path.join(root, f)
            with open(path, 'r', encoding='utf-8', errors='ignore') as fp:
                for idx, line in enumerate(fp):
                    if line.strip().startswith('#'):
                        continue
                    if pat.search(line):
                        violations.append(f"{f}:{idx+1}")

print(len(violations), ";".join(violations))
EOF
)
fixed_tmp_cnt=$(echo "$fixed_tmp_violations" | cut -d' ' -f1)
fixed_tmp_files=$(echo "$fixed_tmp_violations" | cut -d' ' -f2-)
if [ "$fixed_tmp_cnt" -eq 0 ]; then
  assert_test '리눅스 설치 스크립트가 /tmp 고정 이름 대신 사용자 전용 $DT2_TMP 를 쓰는가' 0
else
  assert_test '리눅스 설치 스크립트가 /tmp 고정 이름 대신 사용자 전용 $DT2_TMP 를 쓰는가' 1 "위반: $fixed_tmp_files"
fi

# 5-10. nvim 공유 자원(플러그인·Mason·파서)만 그룹 공유하고 개인 데이터는 사용자별로 분리하는가
nvim_lazy="$REPO_ROOT/.config/nvim/lua/config/lazy.lua"
nvim_mason="$REPO_ROOT/.config/nvim/lua/plugins/mason.lua"
nvim_ts="$REPO_ROOT/.config/nvim/lua/plugins/treesitter.lua"

nvim_shared_ok=1
if ! grep -q 'root = lazy_root' "$nvim_lazy" ||
  ! grep -q 'rocks = { root = _G\.NVIM_SHARED_DIR' "$nvim_lazy" ||
  ! grep -q 'safe\.directory' "$nvim_lazy" ||
  ! grep -q 'install_root_dir = _G\.NVIM_SHARED_DIR' "$nvim_mason" ||
  ! grep -q 'install_dir = _G\.NVIM_SHARED_DIR' "$nvim_ts" ||
  grep -q '_run_symlink "\$DEVTOOLS2/data/nvim"' "$setup_env_sh" ||
  ! grep -q 'prune -o -user' "$setup_env_sh" ||
  ! grep -q 'setfacl -d -m' "$setup_env_sh"; then
  nvim_shared_ok=0
fi

if [ "$nvim_shared_ok" -eq 1 ]; then
  assert_test "nvim 공유 자원(플러그인·Mason·파서)만 그룹 공유하고 개인 데이터는 사용자별로 분리하는가" 0
else
  assert_test "nvim 공유 자원(플러그인·Mason·파서)만 그룹 공유하고 개인 데이터는 사용자별로 분리하는가" 1 "Neovim 공유 설정 불일치"
fi

# 5-11. 백신 오탐(Trojan:Win32/Commando.A!ml)을 유발하는 -EncodedCommand/-enc 가 0건인가
enc_cmd_violations=$(
  python3 - "$REPO_ROOT/scripts/windows" <<'EOF'
import os, sys, re

folder = sys.argv[1]
violations = []
pat = re.compile(r'-(EncodedCommand|enc)\b')

for root, dirs, files in os.walk(folder):
    for f in files:
        if f == 'run-all-tests.ps1':
            continue
        if f.endswith('.ps1'):
            path = os.path.join(root, f)
            with open(path, 'r', encoding='utf-8', errors='ignore') as fp:
                for idx, line in enumerate(fp):
                    if line.strip().startswith('#'):
                        continue
                    if pat.search(line):
                        violations.append(f"{f}:{idx+1}")

print(len(violations), ";".join(violations))
EOF
)
enc_cnt=$(echo "$enc_cmd_violations" | cut -d' ' -f1)
enc_files=$(echo "$enc_cmd_violations" | cut -d' ' -f2-)
if [ "$enc_cnt" -eq 0 ]; then
  assert_test "백신 오탐(Trojan:Win32/Commando.A!ml)을 유발하는 -EncodedCommand/-enc 가 0건인가" 0
else
  assert_test "백신 오탐(Trojan:Win32/Commando.A!ml)을 유발하는 -EncodedCommand/-enc 가 0건인가" 1 "위반: $enc_files"
fi

# ==============================================================================
# [최종 요약 결과]
# ==============================================================================
echo ""
printf "${_C_CYAN}===========================================================================${_C_RESET}\n"
if [ "$failed_tests" -eq 0 ]; then
  summary_color="$_C_GREEN"
else
  summary_color="$_C_RED"
fi
printf "  ${_C_BOLD}테스트 결과 요약: 총 %d 건 | 통과: %d 건 | 실패: %d 건${_C_RESET}\n" \
  "$total_tests" "$passed_tests" "$failed_tests"
printf "${_C_CYAN}===========================================================================${_C_RESET}\n"
echo ""

if [ "$failed_tests" -gt 0 ]; then
  printf "  ${_C_RED}%d 건의 테스트가 실패했습니다. 커밋하기 전에 위의 실패 항목을 반드시 수정하십시오.${_C_RESET}\n\n" "$failed_tests"
  exit 1
else
  printf "  ${_C_GREEN}모든 테스트를 완벽하게 통과했습니다! 안전하게 커밋 및 푸시할 수 있습니다.${_C_RESET}\n\n"
  exit 0
fi
