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
; ==============================================================================

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

    if !_capsUsedAsCtrl
        Send "{Esc}"

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
}

; ------------------------------------------------------------------------------
; Part 2. WSL 터미널 전역 단축키 (Ctrl + Alt + T)
; ------------------------------------------------------------------------------
; ⚠️ "새 창은 OS가 알아서 포그라운드를 준다"는 가정은 틀렸음(실측) — 다른 창(브라우저 등)에
;   포커스가 있을 때 Ctrl+Alt+T를 누르면 Windows Terminal이 뒤에서 열리고 포커스는 안 옮겨감.
;   WezTerm 때와 동일한 HWND 스냅샷/활성화 로직을 WindowsTerminal.exe 대상으로 복원함.
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
