#Requires AutoHotkey v2.0
#SingleInstance Force

; ==============================================================================
; WezTerm 전역 단축키 스크립트
; Ctrl+Alt+T → WezTerm 새 창 열기
;
; 이 파일은 DevTools2 설치 스크립트(1.setup-wezterm.ps1)가 자동 관리합니다.
; 설치 시마다 최신 버전으로 덮어씁니다.
; ==============================================================================

; WezTerm 실행 파일 경로 후보 목록 (설치 위치에 따라 자동 탐색)
_FindWezTerm() {
    candidates := [
        A_ProgramFiles "\WezTerm\wezterm-gui.exe",
        A_ProgramFiles "\WezTerm\wezterm.exe",
        A_LocalAppData "\Programs\WezTerm\wezterm-gui.exe",
        A_LocalAppData "\Programs\WezTerm\wezterm.exe"
    ]
    for path in candidates {
        if FileExist(path)
            return path
    }
    return ""
}

; Ctrl+Alt+T → WezTerm 새 창 열기
^!t:: {
    exe := _FindWezTerm()
    if exe != "" {
        Run exe
    } else {
        MsgBox(
            "WezTerm 실행 파일을 찾을 수 없습니다.`n`n"
            "수동 설치 후 이 스크립트를 재시작해 주세요.",
            "WezTerm Hotkey",
            "Icon! 0x40"
        )
    }
}
