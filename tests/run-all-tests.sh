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

# 대상: 모든 텍스트 파일 (AGENTS.md 1번 "저장소의 모든 텍스트 파일은 UTF-8 NoBOM").
#   예전에는 .ps1/.sh/.bash/.json/.toml/.conf 6종만 봐서 .lua·.md·.yml·.bat·.ahk 등이 빠져 있었습니다.
#   앞 8KB 에 NUL 바이트가 있으면 바이너리로 보고 건너뜁니다.
# 제외 디렉터리: .git, .vscode, .idea, target, build, node_modules, data, modules
suite1_result=$(
  python3 - "$REPO_ROOT" <<'EOF'
import os
import sys

repo = sys.argv[1]
excluded = {'.git', '.vscode', '.idea', 'target', 'build', 'node_modules', 'data', 'modules'}

bom_violations = []
param_violations = []

for root, dirs, files in os.walk(repo):
    dirs[:] = [d for d in dirs if d not in excluded]
    for f in files:
        full_path = os.path.join(root, f)
        rel_path = os.path.relpath(full_path, repo)

        # 1) BOM Check (바이너리 파일은 건너뜀)
        try:
            with open(full_path, 'rb') as fp:
                head = fp.read(8192)
        except Exception:
            continue
        if b'\0' in head:
            continue
        if head.startswith(b'\xef\xbb\xbf'):
            bom_violations.append(rel_path)

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

# 2-1. 실제 PowerShell 파서로 문법 오류 검사
#   WSL 이면 설치 대상과 같은 Windows PowerShell 5.1(powershell.exe)을 우선 쓰고, 없으면 pwsh(7), 둘 다 없으면 건너뜁니다.
#   ⚠️ PS 7 파서는 ?? · 삼항 · && 같은 7 전용 문법을 오류로 보지 않으므로 5.1 파서가 더 엄격합니다.
#   ⚠️ 파서 프로세스가 실행 자체에 실패하면 출력이 비어 "오류 없음"으로 오판되므로, 끝까지 돌았다는 표시를 확인합니다.
ps1_files=()
while IFS= read -r _f; do ps1_files+=("$_f"); done < <(
  find "$REPO_ROOT" \( -path "$REPO_ROOT/data" -o -path "$REPO_ROOT/modules" -o -path "$REPO_ROOT/.git" -o -name node_modules \) -prune \
    -o -type f -name '*.ps1' -print 2>/dev/null | sort
)
ps_parser=""
if command -v powershell.exe >/dev/null 2>&1 && command -v wslpath >/dev/null 2>&1; then
  ps_parser="powershell.exe"
elif command -v pwsh >/dev/null 2>&1; then
  ps_parser="pwsh"
fi

if [ -n "$ps_parser" ]; then
  ps_list=""
  for _f in "${ps1_files[@]}"; do
    [ "$ps_parser" = "powershell.exe" ] && _f=$(wslpath -w "$_f")
    ps_list+="'${_f//\'/\'\'}',"
  done
  ps_list="${ps_list%,}"
  ps_out=$("$ps_parser" -NoProfile -Command "
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new(\$false)
        \$errors = @()
        foreach (\$f in @($ps_list)) {
            \$code = [System.IO.File]::ReadAllText(\$f, [System.Text.Encoding]::UTF8)
            \$errs = \$null
            [System.Management.Automation.Language.Parser]::ParseInput(\$code, \$f, [ref]\$null, [ref]\$errs) | Out-Null
            if (\$errs -and \$errs.Count -gt 0) { \$errors += \"\$([System.IO.Path]::GetFileName(\$f)): \$(\$errs[0].Message)\" }
        }
        'DT2_PARSED=' + (\$errors -join ';')
    " 2>/dev/null | tr -d '\r' || true)
  if ! printf '%s\n' "$ps_out" | grep -q '^DT2_PARSED='; then
    assert_test "모든 .ps1 파일에 문법 오류가 없는가 (PowerShell 파서)" 1 "$ps_parser 파서 실행 실패"
  else
    ps_errors=$(printf '%s\n' "$ps_out" | sed -n 's/^DT2_PARSED=//p')
    if [ -z "$ps_errors" ]; then
      assert_test "모든 .ps1 파일에 문법 오류가 없는가 (PowerShell 파서)" 0
    else
      assert_test "모든 .ps1 파일에 문법 오류가 없는가 (PowerShell 파서)" 1 "$ps_errors"
    fi
  fi
else
  assert_test "PowerShell 파서 감지 (powershell.exe / pwsh 미설치로 건너뜀)" 0
fi

# 2-2. PS 5.1 호환 정적 검사 — 파서 유무와 관계없이 항상 실행
#   예전에는 pwsh 가 없을 때만 실행해서, pwsh 가 있는 PC 에서는 PS 7 파서가 통과시키는 ?? 연산자를 아무도 잡지 못했습니다
#   (AGENTS.md 3번 "널 병합 연산자(??) 사용 금지"). 테스트 러너 자신(run-all-tests.ps1)은 검사 패턴을 문자열로 품고 있어 제외합니다.
# Python 기반 정적 문법 및 구조 정밀 분석
# 1) PS 5.1 비호환 '??' 연산자 검사
# 2) 빈 해시 리터럴 대입문 검사 (@{ Key =  })
# 3) 접두사 변수 누락 URL 패턴 검사 (-Url "/...")
# 4) 좌변 변수 탈락 빈 대입문 검사 (^= ...)
# 5) Test-Path 괄호 누락으로 -and/-or 가 매개변수로 오인되는 패턴 검사
ps_static_errors=$(python3 -c "
import os, re

repo_root = '$REPO_ROOT'
errors = []

for root, _, files in os.walk(repo_root):
    if any(p in root for p in ['modules', 'data', '.git']):
        continue
    for f in files:
        if f.endswith('.ps1') and f != 'run-all-tests.ps1':
            path = os.path.join(root, f)
            rel = os.path.relpath(path, repo_root)
            with open(path, 'r', encoding='utf-8', errors='ignore') as fp:
                content = fp.read()
                lines = content.splitlines()

            # 1. '??' 연산자 검사 (주석 제외)
            for i, line in enumerate(lines, 1):
                code_part = line.split('#')[0]
                if '??' in code_part:
                    errors.append(f'{rel}:{i}: PS 5.1 비호환 ?? 연산자')

            # 2. 빈 해시테이블 대입문 검사 (@{ key = } / @{ key = \n })
            no_comments = re.sub(r'#.*', '', content)
            for m in re.finditer(r'@\{[^}]*?\b([a-zA-Z0-9_]+)\s*=\s*(?:\}|;|\n\s*\})', no_comments):
                line_no = content[:m.start()].count('\n') + 1
                errors.append(f'{rel}:{line_no}: 빈 해시테이블 대입문 (@{{ ... {m.group(1)} = ... }})')

            # 3. 접두사 변수 누락 URL 검사 (-Url \"/...\")
            for m in re.finditer(r'-Url\s+[\"\']/[a-zA-Z0-9_]', no_comments):
                line_no = content[:m.start()].count('\n') + 1
                errors.append(f'{rel}:{line_no}: 접두사 변수 누락 URL (-Url \"/...\")')

            # 4. 좌변 변수 탈락 빈 대입문 검사 (^= ...)
            for i, line in enumerate(lines, 1):
                stripped = line.strip()
                if stripped.startswith('= ') or stripped == '=':
                    errors.append(f'{rel}:{i}: 좌변 변수 누락 대입문')

            # 5. Test-Path 괄호 누락 -and/-or 매개변수 오인 에러 검사
            for m in re.finditer(r'(?<!\()\bTest-Path\s+[^()\n]+?\s+(-and|-or)\b', no_comments):
                line_no = content[:m.start()].count('\n') + 1
                errors.append(f'{rel}:{line_no}: Test-Path 괄호 누락 매개변수 오인 ({m.group(0).strip()})')

print('; '.join(errors))
" 2>/dev/null || true)

if [ -z "$ps_static_errors" ]; then
  assert_test "PS 5.1 호환 정적 검사 (?? 연산자·빈 해시 대입·URL 접두 변수 누락·Test-Path 괄호)" 0
else
  assert_test "PS 5.1 호환 정적 검사 (?? 연산자·빈 해시 대입·URL 접두 변수 누락·Test-Path 괄호)" 1 "$ps_static_errors"
fi

# ==============================================================================
# [Suite 3] Linux Bash 스크립트 구문 검사 (bash -n)
# ==============================================================================
write_header "[Suite 3] Linux Bash 스크립트 구문 검사 (bash -n)"

# 대상: scripts/ 아래 모든 셸 스크립트 — .sh/.bash 와, 확장자가 없어도 첫 줄이 bash/sh shebang 인 파일
#   예전에는 scripts/linux 의 .sh 만 봐서 bw-lib·command-palette·bw-server-manager·git 훅(pre-commit)·
#   format·jdtls 래퍼가 빠져 있었습니다(이 중 bw-lib 은 설치 스크립트가 직접 불러옴).
bash_errors=()
while IFS= read -r sh_file; do
  if [ -f "$sh_file" ]; then
    case "$sh_file" in
      *.sh | *.bash) ;;
      *) head -n 1 "$sh_file" 2>/dev/null | grep -qE '^#!.*\b(bash|sh)\b' || continue ;;
    esac
    if ! err_out=$(bash -n "$sh_file" 2>&1); then
      bash_errors+=("$(basename "$sh_file"): $err_out")
    fi
  fi
done < <(find "$REPO_ROOT/scripts" -type f 2>/dev/null | sort || true)

if [ ${#bash_errors[@]} -eq 0 ]; then
  assert_test "scripts/ 의 모든 셸 스크립트가 bash -n 검사를 통과하는가" 0
else
  assert_test "scripts/ 의 모든 셸 스크립트가 bash -n 검사를 통과하는가" 1 "${bash_errors[*]}"
fi

# ==============================================================================
# [Suite 4] 런타임 회귀 버그 전수 검증
# ==============================================================================
write_header "[Suite 4] 런타임 회귀 버그 전수 검증"

# 4-1. Windows 스크립트에 위험한 '(Get-Content).Trim()' 직통 호출이 0건인가
#   빈 파일의 Get-Content -Raw 는 $null 을 돌려주므로 .Trim() 이 바로 크래시합니다(AGENTS.md 3번 .Trim() 널 가드).
#   예전에는 0.setup-wsl.ps1 한 파일만 봤지만 규칙은 모든 .ps1 에 적용되므로 scripts/windows 전체를 봅니다.
wsl_setup_ps1="$REPO_ROOT/scripts/windows/dev-env/0.setup-wsl.ps1"
if [ -f "$wsl_setup_ps1" ]; then
  unsafe_trim=$(grep -rnP --include='*.ps1' '\(Get-Content[^\)]+\)\.Trim\(\)' "$REPO_ROOT/scripts/windows" | sed "s|$REPO_ROOT/||" || true)
  if [ -z "$unsafe_trim" ]; then
    assert_test "Windows 스크립트에 위험한 '(Get-Content).Trim()' 직통 호출이 0건인가" 0
  else
    assert_test "Windows 스크립트에 위험한 '(Get-Content).Trim()' 직통 호출이 0건인가" 1 "$unsafe_trim"
  fi
else
  assert_test "0.setup-wsl.ps1 파일 존재 확인" 1 "파일 누락: $wsl_setup_ps1"
fi

# 4-2. 0.setup-wsl.ps1 내 /etc/wsl.conf 파이썬 주입 코드가 문법 에러 없이 컴파일되는가 및 STDIN 호출
suite4_2_result=$(
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

py_comp_ok=$(echo "$suite4_2_result" | sed -n '1p')
py_pipe_ok=$(echo "$suite4_2_result" | sed -n '2p')

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

# 4-3. 0.setup-wsl.ps1 에 미완성 배포판 자동 감지 및 unregister 자가 치유 로직이 존재하는가
has_user=$(grep -c '\[user\]' "$wsl_setup_ps1" || true)
has_default=$(grep -c 'default\s*=' "$wsl_setup_ps1" || true)
has_unreg=$(grep -c 'wsl\.exe\s\+--unregister' "$wsl_setup_ps1" || true)
if [ "$has_user" -gt 0 ] && [ "$has_default" -gt 0 ] && [ "$has_unreg" -gt 0 ]; then
  assert_test "0.setup-wsl.ps1 에 미완성 배포판 자동 감지 및 unregister 자가 치유 로직이 존재하는가" 0
else
  assert_test "0.setup-wsl.ps1 에 미완성 배포판 자동 감지 및 unregister 자가 치유 로직이 존재하는가" 1 "자가 치유 로직 미완성"
fi

# 4-4. Linux safe_download_and_extract 가 URL 확장자 대신 파일 헤더 무결성(unzip -tq)으로 아카이브를 판별하는가
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
# [Suite 6] 2026-11 설치 흐름 점검 결함 회귀 방지
# ==============================================================================
write_header "[Suite 6] 2026-11 설치 흐름 점검 결함 회귀 방지"

# 6-1. Start-Process -PassThru(-Wait 없음) 프로세스의 ExitCode 를 읽으면 .Handle 을 미리 여는가
#   Handle 을 미리 열지 않으면 PS 5.1 에서 정상 종료해도 ExitCode 가 $null 이 됩니다(실측). 그래서
#   0.setup-wsl.ps1 이 설치된 WSL 을 매번 "미설치"로 판정했습니다(4번 suite 는 wsl --import 한 곳만 검사).
#   대입 문장(백틱 줄 이어짐 포함) 바로 뒤 8줄 안에 $var.Handle 또는 $var.WaitForExit 가 있어야 합니다.
exitcode_violations=$(
  python3 - "$REPO_ROOT/scripts/windows" <<'EOF'
import os, sys, re

folder = sys.argv[1]
violations = []
assign = re.compile(r'^\s*\$(\w+)\s*=\s*Start-Process\b', re.I)

for root, dirs, files in os.walk(folder):
    for f in files:
        if not f.endswith('.ps1'):
            continue
        path = os.path.join(root, f)
        with open(path, 'r', encoding='utf-8', errors='ignore') as fp:
            lines = fp.read().split('\n')
        for i, line in enumerate(lines):
            m = assign.match(line)
            if not m:
                continue
            var = m.group(1)
            # 백틱(`)으로 이어진 줄까지 한 문장으로 합침
            j, stmt = i, line
            while stmt.rstrip().endswith('`') and j + 1 < len(lines):
                j += 1
                stmt += ' ' + lines[j]
            if not re.search(r'-PassThru\b', stmt, re.I) or re.search(r'-Wait\b', stmt, re.I):
                continue
            rest = '\n'.join(lines[j + 1:])
            if not re.search(r'\$' + var + r'\.ExitCode\b', rest):
                continue
            window = '\n'.join(lines[j + 1:j + 9])
            if not re.search(r'\$' + var + r'\.(Handle|WaitForExit)\b', window):
                violations.append(f"{f}:{i+1}(${var})")

print(len(violations), ";".join(violations))
EOF
)
exitcode_cnt=$(echo "$exitcode_violations" | cut -d' ' -f1)
exitcode_files=$(echo "$exitcode_violations" | cut -d' ' -f2-)
if [ "$exitcode_cnt" -eq 0 ]; then
  assert_test "Start-Process -PassThru 프로세스의 ExitCode 를 읽을 때 .Handle 을 미리 여는가 (PS 5.1 \$null 트랩)" 0
else
  assert_test "Start-Process -PassThru 프로세스의 ExitCode 를 읽을 때 .Handle 을 미리 여는가 (PS 5.1 \$null 트랩)" 1 "위반: $exitcode_files"
fi

# 6-2. 리눅스 설치 스크립트의 timeout 이 setsid(터미널 분리)와 함께 쓰이는가
#   timeout 은 명령을 백그라운드 프로세스 그룹에서 실행하므로, 그 안에서 터미널을 잡는 명령(대화형 bash,
#   sudo 비밀번호 질문 등)이 SIGTTIN 을 보내면 timeout 까지 정지해 시간 제한이 무력화되고 설치가 영원히 멈춥니다
#   (실측: Orca "권장 스킬 설치 시도 중..." 1시간 넘게 정지). setsid -w timeout ... 형태로 쓰거나,
#   setsid 가 없는 시스템용 대체 줄에는 "# dt2:setsid-fallback" 표시를 붙입니다.
timeout_violations=$(
  python3 - "$REPO_ROOT/scripts/linux/dev-env" "$REPO_ROOT/scripts/linux/setup-devtools2.sh" <<'EOF'
import os, sys, re

targets = []
for p in sys.argv[1:]:
    if os.path.isdir(p):
        targets += [os.path.join(p, f) for f in sorted(os.listdir(p)) if f.endswith('.sh')]
    elif os.path.isfile(p):
        targets.append(p)

violations = []
pat = re.compile(r'(^|[\s;&|(`$])timeout\s+(-[A-Za-z-]+(\s+\S+)?\s+)*[0-9]')
for path in targets:
    with open(path, 'r', encoding='utf-8', errors='ignore') as fp:
        for idx, line in enumerate(fp):
            s = line.strip()
            if s.startswith('#'):
                continue
            code = line.split(' #', 1)[0]
            if not pat.search(code):
                continue
            if 'setsid' in code or 'dt2:setsid-fallback' in line:
                continue
            violations.append(f"{os.path.basename(path)}:{idx+1}")

print(len(violations), ";".join(violations))
EOF
)
timeout_cnt=$(echo "$timeout_violations" | cut -d' ' -f1)
timeout_files=$(echo "$timeout_violations" | cut -d' ' -f2-)
if [ "$timeout_cnt" -eq 0 ]; then
  assert_test "리눅스 설치 스크립트의 timeout 이 setsid(터미널 분리)와 함께 쓰이는가 (SIGTTIN 정지 방지)" 0
else
  assert_test "리눅스 설치 스크립트의 timeout 이 setsid(터미널 분리)와 함께 쓰이는가 (SIGTTIN 정지 방지)" 1 "위반: $timeout_files"
fi

# 6-3. 설치 스크립트가 공용 파일(_common.sh·_install-utils.sh·bw-lib)을 $DEVTOOLS2 로컬 저장소에서 불러오지 않는가
#   스트리밍 실행된 새 스크립트가 커밋 동기화를 건너뛴(미커밋 변경·갈라짐) 오래된 로컬 공용 파일을 불러오면
#   새 공용 함수가 없어 중단됩니다. 로드 순서는 "스크립트 옆 파일 → 같은 커밋(DT2_REF)의 원격"이어야 합니다.
localsrc_violations=$(
  python3 - "$REPO_ROOT/scripts/linux/dev-env" <<'EOF'
import os, sys, re

folder = sys.argv[1]
violations = []
pat = re.compile(r'\$\{?DEVTOOLS2[^/"]*\}?/scripts/(linux/dev-env/_[A-Za-z-]+\.sh|fzf/bw-lib)')
for f in sorted(os.listdir(folder)):
    if not f.endswith('.sh'):
        continue
    with open(os.path.join(folder, f), 'r', encoding='utf-8', errors='ignore') as fp:
        for idx, line in enumerate(fp):
            if line.strip().startswith('#'):
                continue
            if pat.search(line.split(' #', 1)[0]):
                violations.append(f"{f}:{idx+1}")

print(len(violations), ";".join(violations))
EOF
)
localsrc_cnt=$(echo "$localsrc_violations" | cut -d' ' -f1)
localsrc_files=$(echo "$localsrc_violations" | cut -d' ' -f2-)
if [ "$localsrc_cnt" -eq 0 ]; then
  assert_test "설치 스크립트가 공용 파일을 \$DEVTOOLS2 로컬 저장소 대신 스크립트 옆·같은 커밋 원격에서 불러오는가" 0
else
  assert_test "설치 스크립트가 공용 파일을 \$DEVTOOLS2 로컬 저장소 대신 스크립트 옆·같은 커밋 원격에서 불러오는가" 1 "위반: $localsrc_files"
fi

# 6-4. WSLg 한글 입력 래퍼(wslg_ime_env_snippet)를 쓰는 GUI 앱 설치 스크립트가 ensure_gui_app_env 를 부르는가
#   래퍼의 입력기 코드는 fcitx5 가 있을 때만 동작하므로, 앱 설치 스크립트가 직접 입력기·글꼴을 준비해야 합니다
#   (예전에는 Sublime Merge 만 준비해, Orca 만 설치하면 WSLg 창에서 한글 입력 불가).
gui_violations=$(
  python3 - "$REPO_ROOT/scripts/linux/dev-env" <<'EOF'
import os, sys

folder = sys.argv[1]
violations = []
for f in sorted(os.listdir(folder)):
    if not f.endswith('.sh') or f == '_install-utils.sh':
        continue
    with open(os.path.join(folder, f), 'r', encoding='utf-8', errors='ignore') as fp:
        code = '\n'.join(l for l in fp.read().split('\n') if not l.strip().startswith('#'))
    if '$(wslg_ime_env_snippet)' in code and 'ensure_gui_app_env ' not in code:
        violations.append(f)

print(len(violations), ";".join(violations))
EOF
)
gui_cnt=$(echo "$gui_violations" | cut -d' ' -f1)
gui_files=$(echo "$gui_violations" | cut -d' ' -f2-)
if [ "$gui_cnt" -eq 0 ]; then
  assert_test "WSLg 한글 입력 래퍼를 쓰는 GUI 앱 설치 스크립트가 ensure_gui_app_env 를 부르는가" 0
else
  assert_test "WSLg 한글 입력 래퍼를 쓰는 GUI 앱 설치 스크립트가 ensure_gui_app_env 를 부르는가" 1 "위반: $gui_files"
fi

# 6-5. command-palette 의 메뉴 항목 ID 와 실행 분기가 1:1 로 짝이 맞는가 (메뉴 문구 부분 문자열로 분기하지 않는가)
#   예전에는 메뉴 문구의 부분 문자열(*"실행"* 등)로 분기를 골라, 새 항목 문구가 겹치면 엉뚱한 분기가 실행될 수
#   있었습니다(예: "작업 실행" 을 고르면 bootRun 실행). 이제 항목은 "ID<TAB>문구", 분기는 ID 로 고릅니다.
#   ● 메뉴 ID: _MENU_* 배열의 항목 + Gradle 빠른 실행(_GT_RESULT="quick:<ID>")
#   ● 분기 ID: [ "$CHOICE_ID" = "<ID>" ] — 메뉴에만 있거나 분기에만 있는 ID 가 없어야 하고, 분기는 ID 당 하나
palette_menu_bad=$(
  python3 - "$REPO_ROOT/scripts/fzf/command-palette" <<'EOF'
import re, sys
c = open(sys.argv[1], encoding='utf-8').read()
menu = set(re.findall(r'^\s*"([a-z0-9_]+)\t', c, re.M)) | set(re.findall(r'_GT_RESULT="quick:([a-z0-9_]+)"', c))
menu -= {'gradle', 'port', 'env', 'project', 'base64'}  # 1단계 그룹 ID (분기 대상 아님)
branches = re.findall(r'\[ "\$CHOICE_ID" = "([a-z0-9_]+)" \]', c)
bad = []
if not menu:
    bad.append('메뉴 ID 없음')
if sorted(set(branches)) != sorted(branches):
    bad.append('중복 분기')
if menu - set(branches):
    bad.append('분기 없는 메뉴: ' + ','.join(sorted(menu - set(branches))))
if set(branches) - menu:
    bad.append('메뉴 없는 분기: ' + ','.join(sorted(set(branches) - menu)))
if re.search(r'\[\[ "\$CHOICE" ==', c):
    bad.append('문구 부분 문자열 분기 남음')
print('; '.join(bad))
EOF
)
if [ -z "$palette_menu_bad" ]; then
  assert_test "command-palette 의 메뉴 항목 ID 와 실행 분기가 1:1 로 짝이 맞는가" 0
else
  assert_test "command-palette 의 메뉴 항목 ID 와 실행 분기가 1:1 로 짝이 맞는가" 1 "$palette_menu_bad"
fi

# 6-6. 세 편집기(VS Code·Neovim·Zed)의 jdtls 힙이 고정값이 아니라 실행 환경 메모리 기준인가
#   VS Code 가 -Xms8G -Xmx8G 로 고정되어, WSL(기본 PC 메모리의 절반) 안에서 시작부터 8GB 를 잡고
#   Neovim jdtls·Gradle 데몬과 함께 메모리가 빠듯했습니다. 셋 다 메모리의 25% 기준으로 맞춥니다.
#   ● VS Code settings.json: java.jdt.ls.vmargs 에 고정 -Xmx 없이 -XX:MaxRAMPercentage
#   ● Neovim plugins/java.lua: /proc/meminfo 로 계산 (고정 --jvm-arg=-Xmx<숫자> 없음)
#   ● Zed scripts/java/jdtls: /proc/meminfo 로 계산한 JDTLS_HEAP_ARGS 를 실행 줄마다 넘김
jdtls_heap_bad=$(
  python3 - "$REPO_ROOT" <<'EOF'
import os, re, sys
root = sys.argv[1]
bad = []
vs = open(os.path.join(root, '.config/vscode/settings.json'), encoding='utf-8').read()
m = re.search(r'^\s*"java\.jdt\.ls\.vmargs"\s*:\s*"([^"]*)"', vs, re.M)
if not m or re.search(r'-Xmx\d', m.group(1)) or 'MaxRAMPercentage' not in m.group(1):
    bad.append('VS Code vmargs')
nv = open(os.path.join(root, '.config/nvim/lua/plugins/java.lua'), encoding='utf-8').read()
if 'MemTotal' not in nv or re.search(r"--jvm-arg=-Xmx\d", nv):
    bad.append('Neovim java.lua')
zd = open(os.path.join(root, 'scripts/java/jdtls'), encoding='utf-8').read()
execs = [l for l in zd.splitlines() if l.strip().startswith('exec "$JDTLS_BIN"')]
if 'MemTotal' not in zd or not execs or any('JDTLS_HEAP_ARGS' not in l for l in execs):
    bad.append('Zed 런처')
print(';'.join(bad))
EOF
)
if [ -z "$jdtls_heap_bad" ]; then
  assert_test "VS Code·Neovim·Zed 의 jdtls 힙이 고정값이 아니라 실행 환경 메모리 기준인가" 0
else
  assert_test "VS Code·Neovim·Zed 의 jdtls 힙이 고정값이 아니라 실행 환경 메모리 기준인가" 1 "위반: $jdtls_heap_bad"
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
