#Requires AutoHotkey v2.0
#SingleInstance Force

; ==============================================================================
; WezTerm 전역 단축키 스크립트 (Ctrl + Alt + T)
; ==============================================================================

^!t::
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
