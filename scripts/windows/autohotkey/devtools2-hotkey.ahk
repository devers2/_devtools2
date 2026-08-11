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
; wt.exe -w -1 : "-1"(=new)은 기존 창을 절대 재사용하지 않고 항상 새 창을 만들라는
; 공식 옵션이라(Microsoft Learn 문서 확인), WezTerm 때처럼 "새로 생긴 창만 골라
; 활성화"하는 HWND 스냅샷/폴링 로직이 필요 없다 — 새로 만들어진 창은 OS가 기본으로
; 포그라운드를 준다.
; wt.exe는 실행 별칭(App Execution Alias)이라 PATH로 바로 실행 가능하지만,
; 별칭이 꺼져있는 예외 상황을 대비해 실제 설치 경로도 폴백으로 시도한다.
^!t::
{
    try {
        Run('wt.exe -w -1 new-tab wsl.exe -d devtools2 --cd ~')
    } catch {
        try {
            wtFallback := EnvGet("LOCALAPPDATA") "\Microsoft\WindowsApps\wt.exe"
            Run('"' wtFallback '" -w -1 new-tab wsl.exe -d devtools2 --cd ~')
        } catch {
            TrayTip("Windows Terminal 실행", "Windows Terminal 실행 중 오류가 발생했습니다.", 0x3)
        }
    }
}
