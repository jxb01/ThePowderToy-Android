<#
.SYNOPSIS
    用 meson + Android NDK 交叉编译 The Powder Toy 的原生库 libpowder.so。

.DESCRIPTION
    产物（strip 之后）会同步到 app/src/main/jniLibs/<abi>/libpowder.so，
    Gradle 接着负责打包 / 签名 / 安装。

    Android 版 TPT 依赖 tpt-libs 提供的预编译静态库
    （SDL2 / libcurl / luajit / libpng / bzip2 / jsoncpp / fftw），
    meson 会按 .wrap 文件自动从 GitHub 下载到 <源码>/subprojects/ 下。

    相比上游 CI 的配置，这里额外打开了：
      * -O3（上游用 debugoptimized，即 -O2）
      * 可选 ThinLTO（-Lto）
      * -ffunction-sections / -fdata-sections + --gc-sections（丢死代码）
      * -z max-page-size=16384（Android 15+ 的 16 KB 内存页要求）

.EXAMPLE
    .\scripts\build-native.ps1 -Abis arm64-v8a,x86_64

.EXAMPLE
    # 真机包开 ThinLTO，体积更小、热路径更快（链接会慢一些）
    .\scripts\build-native.ps1 -Abis arm64-v8a -Lto
#>
[CmdletBinding()]
param(
    [string[]] $Abis = @('arm64-v8a'),
    [ValidateSet('release', 'debug')] [string] $BuildType = 'release',
    [switch] $Lto,
    [switch] $Icf,
    [switch] $Clean,
    [int] $Jobs = 0,
    [string] $SourceDir = '',
    [string] $NdkVersion = '27.2.12479018',
    [string] $AndroidPlatform = 'android-31',
    [ValidateSet('auto', 'none', 'sse2', 'sse3', 'sse4.1', 'sse4.2', 'avx', 'avx2')] [string] $X86Sse = 'auto',
    # ARM 指令集档位。默认 baseline（armv8-a）能装在所有 64 位手机上；
    # v8.2 / v8.4 会多开 dotprod / crc / crypto，只有 2019 年以后的 SoC 才保证支持 ——
    # 给自己那台真机出包时可以用，别拿去做通用包，否则老机会直接非法指令。
    [ValidateSet('baseline', 'v8.2', 'v8.4')] [string] $ArmArch = 'baseline',
    # 产物落地的 jniLibs 目录（相对工程根）。汉化版可以指到别处，两个版本互不覆盖。
    [string] $JniLibsDir = 'app/src/main/jniLibs',
    # meson 构建目录的后缀。上游和汉化版是不同的源码树，不能共用同一个构建目录，
    # 用这个把它们区分开（比如 -BuildTag zhcn）。
    [string] $BuildTag = ''
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$projectRoot = Split-Path -Parent $PSScriptRoot

# ---------------------------------------------------------------------------
# ABI 表：Android ABI 名 -> meson 交叉文件 / clang target triple
# ---------------------------------------------------------------------------
$AbiTable = @{
    'arm64-v8a'   = @{ Arch = 'aarch64'; Triple = 'aarch64-linux-android21' }
    'armeabi-v7a' = @{ Arch = 'arm';     Triple = 'armv7a-linux-androideabi21' }
    'x86_64'      = @{ Arch = 'x86_64';  Triple = 'x86_64-linux-android21' }
    'x86'         = @{ Arch = 'x86';     Triple = 'i686-linux-android21' }
}

# Gradle 会把 -Abis arm64-v8a,x86_64 当一整个字符串传进来
$Abis = $Abis | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }
if ($Abis.Count -eq 0) { throw '至少要指定一个 ABI' }
foreach ($abi in $Abis) {
    if (-not $AbiTable.ContainsKey($abi)) {
        throw "不认识的 ABI '$abi'，可用：$($AbiTable.Keys -join ', ')"
    }
}

function To-MesonPath([string] $p) { return ($p -replace '\\', '/') }

function Read-SdkDir([string] $propsFile) {
    if (-not (Test-Path $propsFile)) { return $null }
    $line = Get-Content $propsFile | Where-Object { $_ -match '^\s*sdk\.dir\s*=' } | Select-Object -First 1
    if (-not $line) { return $null }
    return (($line -replace '^\s*sdk\.dir\s*=', '').Trim() -replace '\\\\', '\' -replace '\\:', ':')
}

# ---------------------------------------------------------------------------
# 解析各种路径
# ---------------------------------------------------------------------------
$sdk = $env:ANDROID_HOME
if (-not $sdk) { $sdk = $env:ANDROID_SDK_ROOT }
$fromProps = Read-SdkDir (Join-Path $projectRoot 'local.properties')
if ($fromProps) { $sdk = $fromProps }
if (-not $sdk -or -not (Test-Path $sdk)) { throw '找不到 Android SDK：请在 local.properties 写 sdk.dir，或设置 ANDROID_HOME' }

$ndkRoot = Join-Path $sdk 'ndk'
if (-not (Test-Path (Join-Path $ndkRoot $NdkVersion))) {
    $available = @()
    if (Test-Path $ndkRoot) { $available = @(Get-ChildItem $ndkRoot -Directory | Select-Object -ExpandProperty Name) }
    if ($available.Count -eq 0) {
        throw "没有安装 NDK。先跑 .\scripts\bootstrap.ps1，或执行 sdkmanager --install ndk;$NdkVersion"
    }
    Write-Warning "没有 NDK $NdkVersion，改用已安装的 $($available[-1])"
    $NdkVersion = $available[-1]
}
$ndk = Join-Path $ndkRoot $NdkVersion
$ndkBin = Join-Path $ndk 'toolchains\llvm\prebuilt\windows-x86_64\bin'
if (-not (Test-Path (Join-Path $ndkBin 'clang++.exe'))) { throw "NDK 工具链不完整：$ndkBin" }
$llvmStrip = Join-Path $ndkBin 'llvm-strip.exe'
$llvmReadelf = Join-Path $ndkBin 'llvm-readelf.exe'

# TPT 源码
if (-not $SourceDir) { $SourceDir = 'C:/Users/JG/Downloads/The-Powder-Toy' }
$source = (Resolve-Path -Path $SourceDir).Path
if (-not (Test-Path (Join-Path $source 'meson.build'))) { throw "看起来不是 The Powder Toy 源码目录：$source" }

# tpt-libs 的预编译包里写死了它当初编译用的 android_platform，
# meson 会拿它跟 -Dandroid_platform 比对，对不上直接报 "platform mismatch"。
# 优先从已经解压出来的包里读出真实值，读不到就用默认值。
$detectedPlatform = $null
Get-ChildItem (Join-Path $source 'subprojects') -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like 'tpt-libs-prebuilt-*-android-*' } | ForEach-Object {
        if (-not $detectedPlatform) {
            $mb = Join-Path $_.FullName 'meson.build'
            if (Test-Path $mb) {
                $hit = Select-String -Path $mb -Pattern "^android_platform = '([^']+)'" | Select-Object -First 1
                if ($hit) { $detectedPlatform = $hit.Matches[0].Groups[1].Value }
            }
        }
    }
if ($detectedPlatform -and $detectedPlatform -ne $AndroidPlatform) {
    Write-Host "   tpt-libs 声明的 android_platform = $detectedPlatform （覆盖默认的 $AndroidPlatform）"
    $AndroidPlatform = $detectedPlatform
}

# JDK（meson 配置阶段要能找到 javac / jar）
$jdk = $null
$jdkCandidates = @($env:JAVA_HOME, 'D:\androd studio\jbr', (Join-Path $env:ProgramFiles 'Android\Android Studio\jbr'))
foreach ($cand in $jdkCandidates) {
    if ($cand -and (Test-Path (Join-Path $cand 'bin\javac.exe'))) { $jdk = $cand; break }
}

# build-tools（aapt2 / d8 / apksigner ... 只在 meson 配置期被查找，本流程不实际使用它们）
$buildTools = Get-ChildItem (Join-Path $sdk 'build-tools') -Directory -ErrorAction SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.FullName 'aapt2.exe') } |
    Sort-Object { try { [version]$_.Name } catch { [version]'0.0.0' } } |
    Select-Object -Last 1
if (-not $buildTools) { throw 'Android SDK 里没有可用的 build-tools' }

# meson / ninja：优先工程内的 .toolchain
$venvScripts = Join-Path $projectRoot '.toolchain\venv\Scripts'
if (-not (Test-Path (Join-Path $venvScripts 'meson.exe'))) {
    $fallback = 'D:\动态安卓软件\.tpt-tools\venv\Scripts'
    if (Test-Path (Join-Path $fallback 'meson.exe')) { $venvScripts = $fallback }
    else { throw '没有找到 meson。先跑 .\scripts\bootstrap.ps1' }
}
$meson = Join-Path $venvScripts 'meson.exe'
$ninja = Join-Path $venvScripts 'ninja.exe'

# meson 需要 python（resources/meson.build 里要跑 to-array.py 等）
if (Test-Path (Join-Path $venvScripts 'python.exe')) {
    $pythonDir = $venvScripts
} elseif (Test-Path 'C:\Users\JG\AppData\Local\Programs\Python\Python312') {
    $pythonDir = 'C:\Users\JG\AppData\Local\Programs\Python\Python312'
} else {
    $pythonDir = $null
}

# 让 meson 的 find_program('javac' / 'd8' / 'aapt2' / 'zipalign' / 'apksigner' / 'adb') 都能命中
$pathParts = @($venvScripts)
if ($pythonDir) { $pathParts += $pythonDir }
if ($jdk) { $pathParts += (Join-Path $jdk 'bin') }
$pathParts += $buildTools.FullName
$pathParts += (Join-Path $sdk 'platform-tools')
$env:PATH = ($pathParts -join ';') + ';' + $env:PATH

$ltoState = if ($Lto) { 'ThinLTO 开' } else { 'ThinLTO 关' }
Write-Host '== The Powder Toy / Android 原生构建 =='
Write-Host "   源码       : $source"
Write-Host "   NDK        : $ndk"
Write-Host "   build-tools: $($buildTools.Name)"
Write-Host "   meson      : $(& $meson --version)"
Write-Host "   ABI        : $($Abis -join ', ')   ($BuildType, $ltoState)"
Write-Host ''

$buildRoot = Join-Path $projectRoot 'build\native'
New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null

# 注意：这里千万不要加 -Wl,--exclude-libs,ALL。
# SDL2 的 JNI 入口（Java_org_libsdl_app_SDLActivity_native*）是在 libSDL2.a 里实现的，
# 一旦把静态库的符号从动态符号表里抹掉，Java 侧 nativeGetVersion() 就会抛
# UnsatisfiedLinkError，应用启动即崩。
$linkArgs = @(
    '-Wl,--gc-sections',
    '-Wl,-O2',
    '-Wl,-z,max-page-size=16384'
)
if ($Icf) { $linkArgs += '-Wl,--icf=all' }
$linkArgsMeson = ($linkArgs | ForEach-Object { "'$_'" }) -join ', '

$failed = @()

foreach ($abi in $Abis) {
    $info = $AbiTable[$abi]
    $buildTag = if ($BuildTag) { '-' + $BuildTag } else { '' }
    $buildDir = Join-Path $buildRoot "$abi-$BuildType$buildTag"
    # 注意：生成的交叉文件不能放在 buildDir 里面 —— -Clean 会传 --wipe 把它一起删掉，
    # 然后 meson 就找不到这个文件了。
    $genDir = Join-Path $buildRoot 'generated'
    $genIni = Join-Path $genDir "android-toolchain-$abi-$BuildType$buildTag.ini"
    $jniLibDir = Join-Path (Join-Path $projectRoot $JniLibsDir) $abi
    New-Item -ItemType Directory -Force -Path $buildDir, $genDir, $jniLibDir | Out-Null

    Write-Host '----------------------------------------------------------------'
    Write-Host "[$abi] 配置交叉编译环境"

    $archCross = Join-Path $source "android\cross\$($info.Arch).ini"
    if (-not (Test-Path $archCross)) { Write-Warning "[$abi] 缺少交叉文件 $archCross"; $failed += $abi; continue }

    # 这个 jar 只在 meson 配置期被当作字符串收下（我们不走 meson 打 APK 那条路），
    # 所以哪个平台装了就用哪个，不必为它专门下载 android-31。
    $platformJar = Join-Path $sdk "platforms\$AndroidPlatform\android.jar"
    if (-not (Test-Path $platformJar)) {
        $installed = Get-ChildItem (Join-Path $sdk 'platforms') -Directory -ErrorAction SilentlyContinue |
            Where-Object { Test-Path (Join-Path $_.FullName 'android.jar') } |
            Sort-Object { try { [version]($_.Name -replace '^android-', '') } catch { [version]'0.0.0' } }
        if (-not $installed) { throw "SDK 里一个 platforms\*\android.jar 都没有，先装 platforms;$AndroidPlatform" }
        $platformJar = Join-Path $installed[-1].FullName 'android.jar'
        Write-Host "   （本机没装 $AndroidPlatform，android_platform_jar 借用 $($installed[-1].Name)）"
    }

    # ARM 侧指令集：arm64 默认就是 armv8-a + NEON，不用额外开；
    # 想压榨新 SoC 才需要显式提高档位（代价是不再兼容老设备）。
    $archFlags = @()
    if ($info.Arch -eq 'aarch64') {
        switch ($ArmArch) {
            'v8.2' { $archFlags = @('-march=armv8.2-a+dotprod+crc+crypto') }
            'v8.4' { $archFlags = @('-march=armv8.4-a+dotprod+crc+crypto') }
        }
    } elseif ($info.Arch -eq 'arm') {
        # 32 位 arm 的 NDK 默认只给 VFPv3-D16，显式打开 NEON
        $archFlags = @('-mfpu=neon-vfpv4')
    }
    $commonCppArgs = @('-ffunction-sections', '-fdata-sections', '-fomit-frame-pointer') + $archFlags
    $commonCppArgsMeson = ($commonCppArgs | ForEach-Object { "'$_'" }) -join ', '
    if ($archFlags.Count -gt 0) { Write-Host "   指令集: $($archFlags -join ' ')" }

    $ini = @"
# 本文件由 scripts/build-native.ps1 自动生成，请勿手改。
[constants]
# android_ndk_toolchain_prefix 由 android/cross/$($info.Arch).ini 提供
android_ndk_bin = '$(To-MesonPath $ndkBin)'

[properties]
android_ndk_toolchain_prefix = android_ndk_toolchain_prefix
android_platform = '$AndroidPlatform'
android_platform_jar = '$(To-MesonPath $platformJar)'
# 只编 .so、不编 APK；这个属性仅在 meson 配置期被读取
java_runtime_jar = '$(To-MesonPath $platformJar)'

[binaries]
# 直接用 NDK 的 clang，用 --target 顶替 aarch64-linux-android21-clang++ 那层 .cmd 包装
cpp = [ android_ndk_bin / 'clang++.exe', '--target=$($info.Triple)' ]
c = [ android_ndk_bin / 'clang.exe', '--target=$($info.Triple)' ]
ar = android_ndk_bin / 'llvm-ar.exe'
strip = android_ndk_bin / 'llvm-strip.exe'

[built-in options]
c_args = [$commonCppArgsMeson]
cpp_args = [$commonCppArgsMeson]
c_link_args = [$linkArgsMeson]
cpp_link_args = [$linkArgsMeson]
"@
    Set-Content -Path $genIni -Value $ini -Encoding utf8

    $ltoValue = if ($Lto) { 'true' } else { 'false' }
    $setupArgs = @(
        'setup', $buildDir, $source,
        '--cross-file', (To-MesonPath $archCross),
        '--cross-file', (To-MesonPath $genIni),
        "--buildtype=$BuildType",
        '-Dstrip=false'
    )

    # 不同 fork 的 meson_options.txt 不完全一样（汉化版就没有 enforce_https、http 这类选项），
    # 传了不存在的 -D 选项 meson 会直接报错，所以先读一遍选项表再决定传什么。
    $declaredOptions = @()
    $optFile = Join-Path $source 'meson_options.txt'
    if (Test-Path $optFile) {
        $optText = Get-Content $optFile -Raw
        foreach ($m in [regex]::Matches($optText, "'([a-zA-Z0-9_]+)'\s*,")) { $declaredOptions += $m.Groups[1].Value }
    } else {
        Write-Warning '找不到 meson_options.txt，跳过选项探测'
    }

    $wanted = [ordered]@{
        'lto'           = $ltoValue
        'x86_sse'       = $X86Sse
        'enforce_https' = 'true'
    }
    foreach ($k in $wanted.Keys) {
        if ($declaredOptions -contains $k) {
            $setupArgs += "-D$k=$($wanted[$k])"
        } else {
            Write-Host "   （源码里没有 $k 选项，跳过）"
        }
    }
    if ($Clean -and (Test-Path (Join-Path $buildDir 'build.ninja'))) { $setupArgs += '--wipe' }

    & $meson @setupArgs
    if ($LASTEXITCODE -ne 0) { Write-Warning "[$abi] meson 配置失败"; $failed += $abi; continue }

    # tpt-libs 里的 sdl.jar 是改过的：SDLActivity.getLibraries() 返回 {"powder"}，
    # 正好去加载 libpowder.so，所以 Java 层不用自己写包装。
    $sdlJar = Get-ChildItem (Join-Path $source 'subprojects') -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'tpt-libs-prebuilt-*-android-*' } |
        ForEach-Object { Join-Path $_.FullName 'lib\sdl.jar' } |
        Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($sdlJar) {
        $libsDir = Join-Path $projectRoot 'app\libs'
        New-Item -ItemType Directory -Force -Path $libsDir | Out-Null
        Copy-Item $sdlJar (Join-Path $libsDir 'sdl2.jar') -Force
        Write-Host "[$abi] SDL Java 层已同步 -> app\libs\sdl2.jar"
    } else {
        Write-Warning "[$abi] 没找到 tpt-libs 的 sdl.jar，Gradle 链接 SDLActivity 会失败"
    }

    Write-Host "[$abi] 编译（这一步最慢，几分钟到十几分钟）"
    $ninjaArgs = @('-C', $buildDir)
    if ($Jobs -gt 0) { $ninjaArgs += @('-j', "$Jobs") }
    $ninjaArgs += 'libpowder.so'
    & $ninja @ninjaArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "[$abi] 直接编 libpowder.so 失败，回退到 meson 目标名 libpowder"
        & $ninja -C $buildDir libpowder
        if ($LASTEXITCODE -ne 0) { Write-Warning "[$abi] 编译失败"; $failed += $abi; continue }
    }

    $soSource = Join-Path $buildDir 'libpowder.so'
    if (-not (Test-Path $soSource)) { Write-Warning "[$abi] 没找到 $soSource"; $failed += $abi; continue }

    # 留一份没剥符号的，方便以后用 ndk-stack / llvm-symbolizer 查崩溃
    $dbgDir = Join-Path $buildRoot "symbols\$abi$buildTag"
    New-Item -ItemType Directory -Force -Path $dbgDir | Out-Null
    Copy-Item $soSource (Join-Path $dbgDir 'libpowder.so') -Force

    $dst = Join-Path $jniLibDir 'libpowder.so'
    Copy-Item $soSource $dst -Force
    & $llvmStrip --strip-unneeded $dst
    $stripFailed = ($LASTEXITCODE -ne 0)

    $size = (Get-Item $dst).Length
    $rawSize = (Get-Item $soSource).Length
    $stripNote = if ($stripFailed) { '（strip 失败，保留符号）' } else { '' }
    Write-Host ("[$abi] 完成 -> {0}" -f $dst)
    Write-Host ("        {0:N1} MB（strip 前 {1:N1} MB）{2}" -f ($size / 1MB), ($rawSize / 1MB), $stripNote)
    Write-Host ("        符号表另存：{0}" -f $dbgDir)
    if ($llvmReadelf -and (Test-Path $llvmReadelf)) {
        & $llvmReadelf -h $dst 2>$null | Select-String 'Machine:' | ForEach-Object { Write-Host ("        " + $_.Line.Trim()) }
    }
}

Write-Host ''
if ($failed.Count -gt 0) {
    Write-Host "失败的 ABI：$($failed -join ', ')"
    exit 1
}
Write-Host '全部 ABI 编译完成。'
Get-ChildItem (Join-Path $projectRoot $JniLibsDir) -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $f = Join-Path $_.FullName 'libpowder.so'
    if (Test-Path $f) { Write-Host ("   {0,-12} {1,8:N1} MB" -f $_.Name, ((Get-Item $f).Length / 1MB)) }
}
Write-Host ''
Write-Host '下一步： .\gradlew.bat :app:assembleDebug'
