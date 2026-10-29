#Requires AutoHotkey v2.0
#SingleInstance Force

; ==============================================================================
; devtools2-hotkey.ahk — DevTools2 통합 AutoHotkey 스크립트
;
; [주요 기능]
;   1. CapsLock 키보드 리매핑 (Linux keyd overload 와 동일 동작)
;      - CapsLock 단독 탭           → ESC
;      - CapsLock + 다른 키 조합    → Ctrl (LCtrl 역할)
;      - Shift + CapsLock           → 대문자 고정 ON
;      - (대문자 고정 ON) CapsLock  → 대문자 고정 OFF + ESC
;      - (대문자 고정 ON) ESC       → 대문자 고정 OFF (ESC pass-through)
;
;   2. WSL 터미널 전역 단축키 (Ctrl + Alt + T)
;      - Windows Terminal을 통해 WSL(devtools2)을 새 창으로 열기
;
;   3. Sublime Merge 전역 단축키 (Ctrl + Alt + G)
;      - WSL2 Linux 판 Sublime Merge(WSLg 창) 실행 또는 기존 창 즉시 포그라운드 활성화
;      - WSLg 창에서는 한/영 키를 WSL fcitx5 전용 전환 키(Ctrl+Alt+Shift+F12)로 전달 (Part 5)
;
;   4. 전역 IME 자동 영문 전환 (0ms 무지연)
;      - Esc, CapsLock(탭), Ctrl+[ 입력 시 Windows IME를 즉시 영문으로 자동 전환
;      - Linux 네이티브의 im-select.nvim + fcitx5 와 동일한 경험 제공
;      - Normal 모드 진입 및 작업 전환 시 항상 영문 보장
;      - WSLg 창(Linux GUI 앱)에서는 Windows IME 대신 WSL fcitx5 를 영문으로 전환 (Part 5)
; ==============================================================================

; ------------------------------------------------------------------------------
; [공통 헬퍼] Win32 IMM API를 통해 현재 활성 창의 IME를 즉시 영문으로 전환
; WM_IME_CONTROL(0x0283) + IMC_GETCONVERSIONMODE(0x0001) / IMC_SETCONVERSIONMODE(0x0002)
; convMode & 1 이 1이면 한글(CJK) 모드 → 0(영문 Alphanumeric)으로 전환
; [WSLg 보충] 활성 창이 WSLg(msrdc.exe)이면 한글 입력은 Windows IME 가 아니라 WSL 의 fcitx5 가
; 담당하므로, fcitx5 '입력기 비활성화(영문)' 키 Ctrl+Alt+Shift+F11 을 추가로 보냅니다 (Part 5 참조).
; Esc / CapsLock 탭 / Ctrl+[ 가 모두 이 함수를 거치므로 세 경로 모두 WSLg 에서도 동일하게 동작합니다.
; ------------------------------------------------------------------------------
_SetImeToEnglish() {
    if WinActive("ahk_exe msrdc.exe")
        Send("^!+{F11}")
    try {
        hwnd := WinExist("A")
        if !hwnd
            return
        imeWnd := DllCall("imm32\ImmGetDefaultIMEWnd", "Ptr", hwnd, "Ptr")
        if !imeWnd
            return
        convMode := DllCall("SendMessage", "Ptr", imeWnd, "UInt", 0x0283, "Ptr", 0x0001, "Ptr", 0, "Ptr")
        if (convMode & 1)
            DllCall("SendMessage", "Ptr", imeWnd, "UInt", 0x0283, "Ptr", 0x0002, "Ptr", 0, "Ptr")
    }
}

; ------------------------------------------------------------------------------
; Part 1. CapsLock 키보드 리매핑
; ------------------------------------------------------------------------------
global _capsDown := false
global _capsUsedAsCtrl := false
global _ih := InputHook("V")

_MarkUsed(ih := 0, vk := 0, sc := 0) {
    global _capsUsedAsCtrl
    _capsUsedAsCtrl := true
}

_ih.OnKeyDown := _MarkUsed

OnExit(_CleanupOnExit)
_CleanupOnExit(reason, code) {
    global _capsDown, _ih
    try _ih.Stop()
    if _capsDown {
        Send "{Blind}{LCtrl up}"
        _capsDown := false
    }
}

*CapsLock:: {
    global _capsDown, _capsUsedAsCtrl, _ih

    if _capsDown
        return

    if GetKeyState("CapsLock", "T") {
        SetCapsLockState "Off"
        Send "{Esc}"
        _SetImeToEnglish()
        return
    }

    if GetKeyState("Shift") {
        SetCapsLockState "On"
        return
    }

    _capsDown := true
    _capsUsedAsCtrl := false
    _ih.Start()
    Send "{Blind}{LCtrl down}"
}

*CapsLock up:: {
    global _capsDown, _capsUsedAsCtrl, _ih
    if !_capsDown
        return

    _ih.Stop()
    _capsDown := false
    Send "{Blind}{LCtrl up}"

    if !_capsUsedAsCtrl {
        Send "{Esc}"
        _SetImeToEnglish()
    }

    _capsUsedAsCtrl := false
}

#HotIf _capsDown
~*LButton::
~*RButton::
~*MButton::
~*WheelUp::
~*WheelDown:: _MarkUsed()
#HotIf

~Esc:: {
    if GetKeyState("CapsLock", "T")
        SetCapsLockState "Off"
    _SetImeToEnglish()
}

; ------------------------------------------------------------------------------
; Part 3. IME 자동 영문 전환 (Ctrl+[)
; Vim 표준 Esc 대체키 Ctrl+[ 에도 동일하게 적용
; ------------------------------------------------------------------------------
~^[:: {
    _SetImeToEnglish()
}

; ------------------------------------------------------------------------------
; Part 2. WSL 터미널 전역 단축키 (Ctrl + Alt + T)
; ------------------------------------------------------------------------------
; ⚠️ "새 창은 OS가 알아서 포그라운드를 준다"는 가정은 틀렸음(실측) — 다른 창(브라우저 등)에
;   포커스가 있을 때 Ctrl+Alt+T를 누르면 Windows Terminal이 뒤에서 열리고 포커스는 안 옮겨감.
;   기존 창 스냅샷/활성화 로직을 WindowsTerminal.exe 대상으로 적용함.
; wt.exe는 실행 별칭(App Execution Alias)이라 PATH로 바로 실행 가능하지만,
; 별칭이 꺼져있는 예외 상황을 대비해 실제 설치 경로도 폴백으로 시도한다.
^!t::
{
    existingHwnds := WinGetList("ahk_exe WindowsTerminal.exe")

    try {
        Run('wt.exe -w -1 new-tab wsl.exe -d devtools2 --cd ~')
    } catch {
        try {
            wtFallback := EnvGet("LOCALAPPDATA") "\Microsoft\WindowsApps\wt.exe"
            Run('"' wtFallback '" -w -1 new-tab wsl.exe -d devtools2 --cd ~')
        } catch {
            TrayTip("Windows Terminal 실행", "Windows Terminal 실행 중 오류가 발생했습니다.", 0x3)
            return
        }
    }
    _ActivateNewTerminal(existingHwnds)
}

; existingHwnds(실행 전 스냅샷)에 없던 새 창의 HWND를 찾을 때까지 폴링(최대 5초) 후 활성화.
; WinActivate만으로는 포그라운드 잠금 때문에 실패할 수 있어 AlwaysOnTop을 순간 켰다 끈다.
_ActivateNewTerminal(existingHwnds) {
    newHwnd := 0
    startTime := A_TickCount
    while (A_TickCount - startTime < 5000) {
        for hwnd in WinGetList("ahk_exe WindowsTerminal.exe") {
            isOld := false
            for oldHwnd in existingHwnds {
                if (hwnd = oldHwnd) {
                    isOld := true
                    break
                }
            }
            if !isOld {
                newHwnd := hwnd
                break
            }
        }
        if newHwnd
            break
        Sleep(30)
    }

    if !newHwnd
        return

    newWin := "ahk_id " newHwnd
    if WinGetMinMax(newWin) = -1
        WinRestore(newWin)
    WinActivate(newWin)
    WinSetAlwaysOnTop(true, newWin)
    WinSetAlwaysOnTop(false, newWin)
}

; ------------------------------------------------------------------------------
; Part 4. Sublime Merge 전역 단축키 (Ctrl + Alt + G) 및 상단 타이틀 바 다크 모드 적용
; ------------------------------------------------------------------------------
_SetDarkTitleBar(hwnd) {
    if !hwnd
        return
    try {
        ; DWMWA_USE_IMMERSIVE_DARK_MODE = 20 (Windows 10 20H1+ 및 Windows 11)
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 20, "Int*", 1, "UInt", 4)
    }
}

; 이미 실행 중이면 최상단 활성화(포커스), 없으면 새 프로세스 실행
; - Sublime Merge 는 WSL2 의 Linux 판을 WSLg 로 실행합니다(Windows 판은 \\wsl.localhost 9P 경로 때문에
;   심볼릭 링크/실행 권한 오탐, 전체 재해시 지연 등이 반복되어 전환함 — tool.setup-sublime-merge.sh 상단 참조).
; - WSLg 창은 msrdc.exe 가 호스팅하며, 창 제목에 "Sublime Merge" 가 포함됩니다
;   (예: "/var/opt/_devtools2 - Sublime Merge (devtools2)"). v2 기본 SetTitleMatchMode 2(부분 일치) 사용.
; (최상위 변수는 자동 실행 구간 순서에 따라 단축키보다 늦게 초기화될 수 있어 함수로 정의)
_SmergeWin() => "Sublime Merge ahk_exe msrdc.exe"

^!g::
{
    if WinExist(_SmergeWin()) {
        if WinGetMinMax(_SmergeWin()) = -1
            WinRestore(_SmergeWin())
        hwnd := WinExist(_SmergeWin())
        _SetDarkTitleBar(hwnd)
        WinActivate(_SmergeWin())
        WinSetAlwaysOnTop(true, _SmergeWin())
        WinSetAlwaysOnTop(false, _SmergeWin())
        return
    }

    _LaunchSublimeMerge()
}

_LaunchSublimeMerge() {
    ; WSL 의 smerge 래퍼(modules/sublime-merge/bin/smerge)를 로그인 셸(bash -l)로 실행해 env.sh 의 PATH 를 적용합니다.
    ; 래퍼가 fcitx5 한글 입력기 환경변수와 데몬도 함께 준비합니다.
    ; sublime_merge 는 실행 즉시 백그라운드로 분리되므로, 숨겨진 wsl.exe 가 창이 닫힐 때까지 대기하여
    ; 열린 WSL 터미널이 하나도 없을 때 배포판이 유휴 종료되며 앱이 함께 꺼지는 것을 방지합니다.
    try {
        Run('wsl.exe -d devtools2 --cd ~ -e bash -lc "smerge; while pgrep -x sublime_merge >/dev/null; do sleep 5; done"', , "Hide")
        if WinWait(_SmergeWin(), , 15) {
            _SetDarkTitleBar(WinExist(_SmergeWin()))
            WinActivate(_SmergeWin())
        }
    } catch {
        TrayTip("Sublime Merge 실행", "WSL(devtools2)에서 Sublime Merge 를 실행하지 못했습니다. WSL 에서 tool.setup-sublime-merge.sh 설치 여부를 확인하세요.", 0x3)
    }
}

; ------------------------------------------------------------------------------
; Part 5. WSLg(Linux GUI 앱) 창 한/영 전환
; - WSLg 창에는 Windows IME 가 적용되지 않으므로 한글은 WSL 의 fcitx5-hangul 로 입력합니다.
; - 한/영 키(VK_HANGUL, 0x15)를 Windows IME 가 가로채면 fcitx5 로 전달되지 않으므로,
;   WSLg 창이 활성일 때만 이 키를 가로채(Windows IME 로 전달 안 됨) fcitx5 전용 키를 대신 보냅니다.
;   (오른쪽 Alt 가 한/영 키인 한국어 키보드도 Windows 에서는 VK_HANGUL 로 들어오므로 동일하게 동작)
; - [안전한 전환 키를 쓰는 이유]
;   예전에는 Shift+Space 를 보냈는데, fcitx5 가 설치되지 않았거나 꺼져 있으면 키가 앱에 그대로 전달되어
;   커밋 메시지에 공백이 입력되는 부작용이 있었습니다. 그래서 어떤 앱에서도 쓰지 않는 조합을 씁니다.
;     ● Ctrl+Alt+Shift+F12 → fcitx5 한/영 전환(TriggerKeys)
;     ● Ctrl+Alt+Shift+F11 → fcitx5 입력기 비활성화 = 영문(DeactivateKeys) — _SetImeToEnglish 가 사용
;   Sublime Merge/Text 기본 키맵에 Alt 가 포함된 F10~F12 바인딩이 없음을 확인했습니다
;   (Ctrl+Shift+F12 는 goto_reference 로 사용 중이라 제외). fcitx5 가 없으면 아무 동작도 하지 않습니다.
; - fcitx5 쪽 키 등록: _install-utils.sh 의 ensure_korean_ime 가 ~/.config/fcitx5/config 에 기록합니다.
;   두 쪽의 키 조합은 반드시 함께 바꿔야 합니다.
; ------------------------------------------------------------------------------
#HotIf WinActive("ahk_exe msrdc.exe")
vk15::
{
    Send("^!+{F12}")
}
#HotIf
