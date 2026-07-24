#Requires AutoHotkey v2.0
#SingleInstance Force

; ==============================================================================
; WezTerm 전역 단축키 스크립트 (Ctrl + Alt + T)
; 관리자 권한 자동 승격 및 키보드 훅 우선권 확보로 VSCode/IDE 포커스 시에도 100% 작동
; ==============================================================================

; 1. 관리자 권한 자동 승격 (VSCode/터미널이 관리자 권한으로 실행 중이어도 단축키 보장)
if not A_IsAdmin {
    try {
        Run '*RunAs "' A_ScriptFullPath '"'
    }
    ExitApp
}

; 2. 물리 키보드 훅 활성화 (모든 앱의 키 바인딩보다 우선권 확보)
#UseHook True

; 3. Ctrl + Alt + T 단축키 ($ = 물리 키보드 훅 감지)
$^!t::
{
    if FileExist("C:\Program Files\WezTerm\wezterm-gui.exe")
        Run('"C:\Program Files\WezTerm\wezterm-gui.exe"')
    else if FileExist("C:\Program Files\WezTerm\wezterm.exe")
        Run('"C:\Program Files\WezTerm\wezterm.exe"')
    else if FileExist(EnvGet("LOCALAPPDATA") "\Programs\WezTerm\wezterm-gui.exe")
        Run('"' EnvGet("LOCALAPPDATA") '\Programs\WezTerm\wezterm-gui.exe"')
    else if FileExist(EnvGet("LOCALAPPDATA") "\Programs\WezTerm\wezterm.exe")
        Run('"' EnvGet("LOCALAPPDATA") '\Programs\WezTerm\wezterm.exe"')
    else
        MsgBox("WezTerm 실행 파일을 찾을 수 없습니다.", "WezTerm Hotkey Error", 0x10)
}
