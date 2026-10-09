<#
.SYNOPSIS
    生成工程根目录下的开发签名 tpt-dev.jks。

.DESCRIPTION
    仓库里不携带 keystore，所以默认会用 AGP 的 debug 签名出包 —— 能装能用，
    但换台机器、或者清过 debug.keystore 之后签名就变了，覆盖安装会报
    INSTALL_FAILED_UPDATE_INCOMPATIBLE。

    跑一次这个脚本生成一个固定 keystore 放在工程根目录（已在 .gitignore 里），
    之后所有 release 包都用它签名，反复覆盖安装就不会出问题。

.EXAMPLE
    .\scripts\make-keystore.ps1
#>
[CmdletBinding()]
param(
    [string] $Path = '',
    [string] $Alias = 'androidkey',
    [string] $StorePass = 'bagelsbagels',
    [string] $KeyPass = 'bagelsbagels'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $Path) { $Path = Join-Path $projectRoot 'tpt-dev.jks' }

# 找一个带 keytool 的 JDK：优先 JAVA_HOME，其次 Android Studio 自带的 JBR
$keytool = $null
foreach ($jdk in @($env:JAVA_HOME, 'D:\androd studio\jbr', (Join-Path $env:ProgramFiles 'Android\Android Studio\jbr'))) {
    if ($jdk) {
        $cand = Join-Path $jdk 'bin\keytool.exe'
        if (Test-Path $cand) { $keytool = $cand; break }
    }
}
if (-not $keytool) {
    $found = Get-Command keytool.exe -ErrorAction SilentlyContinue
    if ($found) { $keytool = $found.Source }
}
if (-not $keytool) { throw '找不到 keytool，请把 JAVA_HOME 指向一个 JDK' }

if (Test-Path $Path) {
    Write-Host ('keystore 已存在，不覆盖：' + $Path)
    exit 0
}

$keytoolArgs = @(
    '-genkeypair',
    '-keystore', $Path,
    '-alias', $Alias,
    '-validity', '10000',
    '-keyalg', 'RSA',
    '-keysize', '2048',
    '-storepass', $StorePass,
    '-keypass', $KeyPass,
    '-storetype', 'PKCS12',
    '-dname', 'CN=The Powder Toy Android, OU=Port, O=TPT, L=NA, ST=NA, C=CN'
)
& $keytool @keytoolArgs
if ($LASTEXITCODE -ne 0) { throw 'keytool 生成 keystore 失败' }

Write-Host ('已生成：' + $Path)
Write-Host ('  alias = ' + $Alias)
Write-Host '  这个文件在 .gitignore 里，不会被提交。'
