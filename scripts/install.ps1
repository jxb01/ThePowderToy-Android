<#
.SYNOPSIS
    编译好的 APK 装到已连接的 Android 设备（真机或模拟器）。

.DESCRIPTION
    默认装 release 包；没有 release 就退到 debug 包。
    如果设备上已经装了官方签名版本的 uk.co.powdertoy.tpt，会提示先卸载。

.EXAMPLE
    .\scripts\install.ps1
    .\scripts\install.ps1 -DebugBuild
    .\scripts\install.ps1 -Launch
#>
[CmdletBinding()]
param(
    # 注意：不能叫 -Debug —— [CmdletBinding()] 已经自带了公共参数 -Debug，
    # 重名会让整个脚本在解析阶段就报"已为命令多次定义名为 Debug 的参数"。
    [switch] $DebugBuild,
    [switch] $Launch,
    [string] $Serial = ''
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$projectRoot = Split-Path -Parent $PSScriptRoot

function Read-SdkDir([string] $propsFile) {
    if (-not (Test-Path $propsFile)) { return $null }
    $line = Get-Content $propsFile | Where-Object { $_ -match '^\s*sdk\.dir\s*=' } | Select-Object -First 1
    if (-not $line) { return $null }
    return (($line -replace '^\s*sdk\.dir\s*=', '').Trim() -replace '\\\\', '\' -replace '\\:', ':')
}

$sdk = Read-SdkDir (Join-Path $projectRoot 'local.properties')
if (-not $sdk) { $sdk = $env:ANDROID_HOME }
if (-not $sdk) { $sdk = $env:ANDROID_SDK_ROOT }
if (-not $sdk) { throw '找不到 Android SDK' }

$adb = Join-Path $sdk 'platform-tools\adb.exe'
if (-not (Test-Path $adb)) { throw "找不到 adb：$adb" }

$kind = if ($DebugBuild) { 'debug' } else { 'release' }
$apk = Join-Path $projectRoot "app\build\outputs\apk\$kind\app-$kind.apk"
if (-not (Test-Path $apk)) {
    $other = if ($DebugBuild) { 'release' } else { 'debug' }
    $alt = Join-Path $projectRoot "app\build\outputs\apk\$other\app-$other.apk"
    if (Test-Path $alt) { Write-Warning "没有 $kind 包，改用 $other 包"; $apk = $alt }
    else { throw "没有找到 APK。先执行 .\gradlew.bat :app:assembleDebug" }
}

$adbArgs = @()
if ($Serial) { $adbArgs += @('-s', $Serial) }

Write-Host "== 已连接设备 =="
& $adb @adbArgs devices -l
Write-Host ''
Write-Host "安装 $apk"

$out = & $adb @adbArgs install -r $apk 2>&1
$out | ForEach-Object { Write-Host $_ }

if ($LASTEXITCODE -ne 0) {
    # 设备上如果留着别处编的包（debug 签名、官方签名），覆盖安装会因为签名不一致被拒。
    # 这种情况直接卸掉重装，省得用户自己跑去 adb uninstall。
    if (($out -join ' ') -match 'INSTALL_FAILED_UPDATE_INCOMPATIBLE|signatures do not match') {
        Write-Host ''
        Write-Warning '设备上有同包名但签名不同的旧版本，先卸载再装。'
        & $adb @adbArgs uninstall uk.co.powdertoy.tpt | ForEach-Object { Write-Host $_ }
        Write-Host '重新安装 ...'
        & $adb @adbArgs install -r $apk | ForEach-Object { Write-Host $_ }
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Warning '安装失败。'
        exit 1
    }
}

if ($Launch) {
    Write-Host '启动 The Powder Toy ...'
    & $adb @adbArgs shell am start -n 'uk.co.powdertoy.tpt/.PowderActivity'
}
