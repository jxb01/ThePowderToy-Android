<#
.SYNOPSIS
    一次性准备构建环境：工程内的 meson/ninja 虚拟环境 +（可选）Android NDK。

.DESCRIPTION
    1. 在 <工程>\.toolchain\venv 里装好 meson 和 ninja（工程自带，不污染系统 Python）；
    2. 检查 Android NDK，没有就用 sdkmanager 装。

.EXAMPLE
    .\scripts\bootstrap.ps1
#>
[CmdletBinding()]
param(
    [string] $NdkVersion = '27.2.12479018'
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$projectRoot = Split-Path -Parent $PSScriptRoot
$venvDir = Join-Path $projectRoot '.toolchain\venv'

function Read-SdkDir([string] $propsFile) {
    if (-not (Test-Path $propsFile)) { return $null }
    $line = Get-Content $propsFile | Where-Object { $_ -match '^\s*sdk\.dir\s*=' } | Select-Object -First 1
    if (-not $line) { return $null }
    return (($line -replace '^\s*sdk\.dir\s*=', '').Trim() -replace '\\\\', '\' -replace '\\:', ':')
}

# ---------------------------------------------------------------------------
# 1. meson + ninja
# ---------------------------------------------------------------------------
if (-not (Test-Path (Join-Path $venvDir 'Scripts\meson.exe'))) {
    Write-Host "[bootstrap] 创建 Python 虚拟环境：$venvDir"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $venvDir) | Out-Null

    $pythonCmd = $null
    $pythonArgs = @()
    if (Get-Command py -ErrorAction SilentlyContinue) { $pythonCmd = 'py'; $pythonArgs = @('-3') }
    elseif (Get-Command python -ErrorAction SilentlyContinue) { $pythonCmd = 'python'; $pythonArgs = @() }
    if (-not $pythonCmd) { throw '找不到 Python（3.8+），无法创建 meson 虚拟环境' }

    & $pythonCmd @pythonArgs -m venv $venvDir
    if (-not (Test-Path (Join-Path $venvDir 'Scripts\python.exe'))) { throw "创建虚拟环境失败：$venvDir" }
}

Write-Host '[bootstrap] 安装 / 更新 meson 与 ninja'
& (Join-Path $venvDir 'Scripts\python.exe') -m pip install --disable-pip-version-check --quiet --upgrade meson ninja
if ($LASTEXITCODE -ne 0) { throw 'pip 安装 meson / ninja 失败' }
Write-Host "  meson $(& (Join-Path $venvDir 'Scripts\meson.exe') --version)"

# ---------------------------------------------------------------------------
# 2. Android NDK
# ---------------------------------------------------------------------------
$sdk = $env:ANDROID_HOME
if (-not $sdk) { $sdk = $env:ANDROID_SDK_ROOT }
$fromProps = Read-SdkDir (Join-Path $projectRoot 'local.properties')
if ($fromProps) { $sdk = $fromProps }
if (-not $sdk -or -not (Test-Path $sdk)) { throw '找不到 Android SDK，请在 local.properties 里写 sdk.dir' }

$ndkDir = Join-Path $sdk "ndk\$NdkVersion"
if (Test-Path $ndkDir) {
    Write-Host "[bootstrap] NDK 已就绪：$ndkDir"
} else {
    Write-Host "[bootstrap] 安装 Android NDK $NdkVersion（约 700 MB，请耐心等待）"
    $sdkmanager = Join-Path $sdk 'cmdline-tools\latest\bin\sdkmanager.bat'
    if (-not (Test-Path $sdkmanager)) { throw "找不到 sdkmanager：$sdkmanager" }
    & $sdkmanager --install "ndk;$NdkVersion"
    if ($LASTEXITCODE -ne 0) { throw 'NDK 安装失败' }
    Write-Host "[bootstrap] NDK 安装完成：$ndkDir"
}

Write-Host ''
Write-Host '[bootstrap] 环境就绪。下一步：'
Write-Host '    .\scripts\build-native.ps1 -Abis arm64-v8a,x86_64'
