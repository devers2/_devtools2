<#
.SYNOPSIS
    심볼릭 링크(Junction)를 안전하게 생성하거나 갱신합니다.

.DESCRIPTION
    지정한 원본 폴더(Source)를 가리키는 정션(Junction) 바로가기를 생성합니다.
    - 타겟이나 소스 디렉터리가 없으면 자동으로 생성합니다.
    - 이미 대상 위치에 잘못된 타겟을 가리키는 링크가 있거나, 일반 파일/폴더가 있으면
      안전을 위해 강제 삭제 후 올바른 링크로 교체(복구)합니다.
    - 끊어진 링크(Broken Symlink) 방지를 보장하는 안전한 유틸리티입니다.

.PARAMETER Source
    원본 폴더의 절대 경로입니다. (예: C:\data\my_target)

.PARAMETER Target
    생성할 바로가기(Junction)의 절대 경로입니다. (예: C:\Users\user\my_link)

.EXAMPLE
    .\create-symbolic-link.ps1 -Source "C:\data\my_target" -Target "C:\Users\user\my_link"
#>

param (
    [Parameter(Mandatory=$true, HelpMessage="원본 폴더 경로를 입력하세요.")]
    [string]$Source,

    [Parameter(Mandatory=$true, HelpMessage="생성할 바로가기 경로를 입력하세요.")]
    [string]$Target
)

# 1. 타겟 부모 폴더 및 원본 소스 폴더 보장
if (-not (Test-Path (Split-Path $Target))) { New-Item (Split-Path $Target) -ItemType Directory | Out-Null }
if (-not (Test-Path $Source)) { New-Item $Source -ItemType Directory | Out-Null }

if (Test-Path $Target) {
    $item = Get-Item $Target -Force
    if (-not $item.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint)) {
        # 일반 디렉터리나 파일인 경우 백업 후 정션으로 교체
        $timestamp = [Math]::Floor([double](Get-Date -UFormat %s))
        $bak = "${Target}.backup.${timestamp}"
        Move-Item -Path $Target -Destination $bak -Force

        New-Item -ItemType Junction -Path $Target -Value $Source | Out-Null
        Write-Host "[복구] $Target 위치에 일반 파일/폴더가 있어 백업($bak) 후 정션으로 교체했습니다."
    } else {
        # 기존 정션(Junction)의 실제 타겟 경로 확인
        $currentTarget = ""
        if ($item.Target) {
            $currentTarget = $item.Target
        }
        
        # PowerShell 구버전 대비 (Target 속성이 없을 경우 fsutil로 파싱)
        if ([string]::IsNullOrEmpty($currentTarget)) {
            $fsutilOutput = fsutil reparsepoint query "$Target" 2>&1 | Select-String "Print Name:"
            if ($fsutilOutput) {
                $currentTarget = ($fsutilOutput -split "Print Name:")[1].Trim()
            }
        }
        
        # 경로 불일치 비교 (대소문자 무시, 절대경로 기준)
        if (-not [string]::IsNullOrEmpty($currentTarget)) {
            $ctStr = [System.IO.Path]::GetFullPath($currentTarget).ToLower()
            $srcStr = [System.IO.Path]::GetFullPath($Source).ToLower()
            
            if ($ctStr -eq $srcStr) {
                Write-Host "[확인] $Target 이미 올바른 정션(Junction)입니다."
            } else {
                Write-Host "[복구] $Target 대상이 잘못되어($currentTarget) 기존 정션 삭제 후 재연결합니다."
                Remove-Item $Target -Recurse -Force
                New-Item -ItemType Junction -Path $Target -Value $Source | Out-Null
                Write-Host "[성공] $Target -> $Source"
            }
        } else {
            # 경로 파싱 실패 시 안전을 위해 덮어쓰기
            Write-Host "[복구] $Target 타겟 경로 확인 불가로 기존 정션 삭제 후 재연결합니다."
            Remove-Item $Target -Recurse -Force
            New-Item -ItemType Junction -Path $Target -Value $Source | Out-Null
            Write-Host "[성공] $Target -> $Source"
        }
    }
} else {
    New-Item -ItemType Junction -Path $Target -Value $Source | Out-Null
    Write-Host "[성공] $Target -> $Source 정션을 생성했습니다."
}
