#Requires AutoHotkey v2.0
#SingleInstance Force

; ==============================================================================
; WezTerm 전역 단축키 스크립트 (Ctrl + Alt + T)
; WezTerm 실행 후 창을 최상단(Foreground)으로 무조건 활성화
; ==============================================================================

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
        Run('"' exe '"')
        ; 새 창이 생성되면 최상단으로 가져오고 즉시 포커스 활성화
        if WinWait("ahk_exe wezterm-gui.exe", , 2) {
            WinActivate("ahk_exe wezterm-gui.exe")
        }
    } else {
        MsgBox("WezTerm 실행 파일을 찾을 수 없습니다.", "WezTerm Hotkey Error", 0x10)
    }
}
