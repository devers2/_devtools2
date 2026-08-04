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
;   2. WezTerm 터미널 전역 단축키 (Ctrl + Alt + T)
;      - WezTerm 실행 및 최상단 포터블 창 활성화
;      - Windows 보안 정책/SmartScreen 차단 발생 시 안전 예외 처리 (try-catch)
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
; Part 2. WezTerm 전역 단축키 (Ctrl + Alt + T)
; ------------------------------------------------------------------------------
^!t::
{
    exe := ""
    if FileExist("C:\Program Files\WezTerm\wezterm-gui.exe")
        exe := "C:\Program Files\WezTerm\wezterm-gui.exe"
    else if FileExist("C:\Program Files\WezTerm\wezterm.exe")
        exe := "C:\Program Files\WezTerm\wezterm.exe"
    else if FileExist(EnvGet("LOCALAPPDATA") "\Programs\WezTerm\wezterm-gui.exe")
        exe := EnvGet("LOCALAPPDATA") "\Programs\WezTerm\wezterm-gui.exe"
    else if FileExist(EnvGet("LOCALAPPDATA") "\Programs\WezTerm\wezterm.exe")
        exe := EnvGet("LOCALAPPDATA") "\Programs\WezTerm\wezterm.exe"

    if exe != "" {
        try {
            Run('"' exe '"', , , &pid)
            if WinWait("ahk_pid " pid, , 3) {
                WinActivate("ahk_pid " pid)
            }
        } catch as err {
            try {
                ; 1차 Direct Run 실패 시 cmd shell start 로 2차 실행 시도 (SmartScreen / UAC 팝업 차단 우회)
                Run('cmd.exe /c start "" "' exe '"', , "Hide")
            } catch {
                ; 무음 예외 처리 (거슬리는 MsgBox 알림창 팝업 제거)
                TrayTip("WezTerm 실행", "WezTerm 실행 중 오류가 발생했습니다.", 0x3)
            }
        }
    } else {
        TrayTip("WezTerm 실행", "WezTerm 실행 파일을 찾을 수 없습니다.", 0x2)
    }
}
