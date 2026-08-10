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
global _weztermExeCache := ""

; WezTerm 창(래처 exe 종류 무관)을 하나의 그룹으로 묶어서
; WinWait / WinActivate 시 "ahk_exe wezterm-gui.exe" / "ahk_exe wezterm.exe" 둘 다 인식하도록 함
GroupAdd("WezTermGroup", "ahk_exe wezterm-gui.exe")
GroupAdd("WezTermGroup", "ahk_exe wezterm.exe")

_GetWeztermExe() {
    global _weztermExeCache
    if _weztermExeCache != "" && FileExist(_weztermExeCache)
        return _weztermExeCache

    paths := [
        "C:\Program Files\WezTerm\wezterm-gui.exe",
        "C:\Program Files\WezTerm\wezterm.exe",
        EnvGet("LOCALAPPDATA") "\Programs\WezTerm\wezterm-gui.exe",
        EnvGet("LOCALAPPDATA") "\Programs\WezTerm\wezterm.exe"
    ]
    for p in paths {
        if FileExist(p) {
            _weztermExeCache := p
            return p
        }
    }
    return ""
}

^!t::
{
    exe := _GetWeztermExe()
    if exe != "" {
        try {
            Run('"' exe '"')
        } catch {
            try {
                Run('cmd.exe /c start "" "' exe '"', , "Hide")
            } catch {
                TrayTip("WezTerm 실행", "WezTerm 실행 중 오류가 발생했습니다.", 0x3)
                return
            }
        }
        _ActivateWezterm()
    } else {
        TrayTip("WezTerm 실행", "WezTerm 실행 파일을 찾을 수 없습니다.", 0x2)
    }
}

; 새로 뜬(또는 이미 떠 있던) WezTerm 창을 다른 창들보다 위로 강제 노출
; WinActivate만으로는 Windows 포그라운드 잠금 때문에 실패할 수 있어
; AlwaysOnTop을 순간적으로 켰다 끄는 방식으로 z-order를 확실히 최상단으로 올림
_ActivateWezterm() {
    if !WinWait("ahk_group WezTermGroup", , 5)
        return

    if WinGetMinMax("ahk_group WezTermGroup") = -1
        WinRestore("ahk_group WezTermGroup")

    WinActivate("ahk_group WezTermGroup")
    WinSetAlwaysOnTop(true, "ahk_group WezTermGroup")
    WinSetAlwaysOnTop(false, "ahk_group WezTermGroup")
}
