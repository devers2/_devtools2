#Requires AutoHotkey v2.0
#SingleInstance Force

; ==============================================================================
; keyboard-remap.ahk — CapsLock 키보드 리매핑 (keyd overload 와 동일 동작)
;
; [동작 정의]
;   CapsLock 단독 탭           → ESC
;   CapsLock + 다른 키 조합    → Ctrl (LCtrl 역할)
;   Shift + CapsLock           → 대문자 고정 ON
;   (대문자 고정 ON) CapsLock  → 대문자 고정 OFF + ESC
;   (대문자 고정 ON) ESC       → 대문자 고정 OFF (ESC pass-through)
;
; [구현 방식 - InputHook 활용]
;   - CapsLock 누름 시 LCtrl down 전송 및 InputHook(V 모드) 시작
;   - CapsLock 누른 상태에서 임의의 키(알파벳, 숫자, Numpad, F키 등 전 키)나
;     마우스(클릭, 휠) 입력 발생 시 _capsUsedAsCtrl 플래그를 true 로 설정
;   - CapsLock 뗄 때 InputHook 중단 및 LCtrl up 전송
;   - 플래그가 false 면 단독 탭으로 판단하여 ESC 전송
; ==============================================================================

global _capsDown := false
global _capsUsedAsCtrl := false
global _ih := InputHook("V")

; InputHook 설정: 키보드의 임의 키 입력 시 조합키 플래그 설정
_ih.OnKeyDown := (ih, vk, sc) => (global _capsUsedAsCtrl := true)

; ── 스크립트 종료/리로드 시 정리 ─────────────────────────────────────────────
OnExit(_CleanupOnExit)
_CleanupOnExit(reason, code) {
    global _capsDown, _ih
    try _ih.Stop()
    if _capsDown {
        Send "{Blind}{LCtrl up}"
        _capsDown := false
    }
}

; ── CapsLock 누름: Ctrl 활성화 ───────────────────────────────────────────────
*CapsLock:: {
    global _capsDown, _capsUsedAsCtrl, _ih

    ; ── 키보드 자동 반복(Auto-repeat) 발생 시 중복 실행 방지 ────────────────
    if _capsDown
        return

    ; ── 1. CapsLock이 이미 ON 상태 → 대문자 고정 OFF + ESC ───────────────────
    ; (keyd caps 레이어의 capslock = toggle(caps) 와 동일)
    if GetKeyState("CapsLock", "T") {
        SetCapsLockState "Off"
        Send "{Esc}"
        return
    }

    ; ── 2. Shift + CapsLock → 대문자 고정 ON ─────────────────────────────────
    if GetKeyState("Shift") {
        SetCapsLockState "On"
        return
    }

    ; ── 3. overload(control, esc): Ctrl 활성화 + InputHook 시작 ──────────────
    _capsDown := true
    _capsUsedAsCtrl := false
    _ih.Start()
    Send "{Blind}{LCtrl down}"
}

; ── CapsLock 뗌: Ctrl 해제 + 단독 탭이면 ESC 전송 ───────────────────────────
*CapsLock up:: {
    global _capsDown, _capsUsedAsCtrl, _ih
    if !_capsDown    ; CapsLock ON/OFF 변경 경로는 _capsDown 미설정 → 무시
        return

    _ih.Stop()
    _capsDown := false
    Send "{Blind}{LCtrl up}"

    ; 다른 키/마우스와 조합되지 않은 단독 탭 → ESC
    if !_capsUsedAsCtrl
        Send "{Esc}"

    _capsUsedAsCtrl := false
}

; ── CapsLock 누른 상태에서 마우스 입력 감지 ──────────────────────────────────
#HotIf _capsDown
~*LButton::   global _capsUsedAsCtrl := true
~*RButton::   global _capsUsedAsCtrl := true
~*MButton::   global _capsUsedAsCtrl := true
~*WheelUp::   global _capsUsedAsCtrl := true
~*WheelDown:: global _capsUsedAsCtrl := true
#HotIf

; ── ESC: 대문자 고정 ON 상태이면 함께 해제 (pass-through) ────────────────────
; ~ (tilde): ESC를 앱에도 그대로 전달하면서 CapsLock 상태도 해제
; (keyd caps 레이어의 esc = toggle(caps) 와 동일)
~Esc:: {
    if GetKeyState("CapsLock", "T")
        SetCapsLockState "Off"
}
