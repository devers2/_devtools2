#Requires AutoHotkey v2.0
#SingleInstance Force

; ==============================================================================
; WezTerm 전역 단축키 스크립트 (Ctrl + Alt + T)
; 새 실행 창(PID) 1개만 무조건 최상단(Foreground)으로 포커스
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
        ; 새로 띄운 특정 PID의 창 정보만 가져옴
        Run('"' exe '"', , , &pid)

        ; 새로 실행한 특정 1개 창(ahk_pid)만 무조건 최상단으로 포커스 활성화
        if WinWait("ahk_pid " pid, , 3) {
            WinActivate("ahk_pid " pid)
        }
    } else {
        MsgBox("WezTerm 실행 파일을 찾을 수 없습니다.", "WezTerm Hotkey Error", 0x10)
    }
}
