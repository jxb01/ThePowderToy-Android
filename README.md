# 粉末游戏 · Android 特化版

**The Powder Toy（粉末游戏）的 Android 特化版本。**

原版 [The Powder Toy](https://github.com/The-Powder-Toy/The-Powder-Toy) 是 C++ / SDL2 写的开源
物理沙盒游戏（GPL-3.0），社区一直没有一个能直接用 Android Studio 编译、打包、装机的工程。
本项目把原版源码——以及社区简体中文汉化分支
[The-Powder-Toy-Chinese](https://github.com/Dragonrster/The-Powder-Toy-Chinese)——接进 Android Studio，
并针对现代手机做了一批编译期与运行期优化。

原生部分仍然走上游自己的 meson + Android NDK 交叉编译（这是上游唯一支持的 Android 构建路径），
Gradle 负责把它变成一个正经的 Android Studio 工程：打包、签名、装到手机。

---

## 〇、与上游的关系（务必先看）

| 角色 | 项目 | 协议 |
| --- | --- | --- |
| **原版（粉末游戏）** | [The-Powder-Toy/The-Powder-Toy](https://github.com/The-Powder-Toy/The-Powder-Toy) | GPL-3.0 |
| 简体中文汉化 | [Dragonrster/The-Powder-Toy-Chinese](https://github.com/Dragonrster/The-Powder-Toy-Chinese) | GPL-3.0 |
| **本项目** | Android 构建管线 + 手机特化优化 + 打包 | GPL-3.0 |

本项目**不修改游戏内核**（不含 `src/`），它做的是围绕原版的「特化」：

1. **Android 构建管线**：把上游 meson 工程接进 Gradle / Android Studio，
   用 NDK 交叉编译出 `libpowder.so`，再由 AGP 完成打包、签名、装机。
2. **手机特化优化**：`-O3` + ThinLTO、16 KB 内存页对齐、未压缩 .so 直载、
   申请屏幕最高刷新率、ARM 指令集档位可选（详见第六节）。
3. **中文打包**：把汉化分支编成独立的 `uk.co.powdertoy.tpt.zhcn`，应用名「粉末游戏」，
   与原版 APK 可在同一台手机上并存。
4. **一份代码出两个包**：`-PtptZhcn=true` 切换官方版 / 汉化版。

> 游戏本身的著作权、玩法、素材都属于上游作者；汉化文本与中文字体属于汉化分支作者
> DragonRSTER。本项目只提供 Android 侧的构建与优化，同样以 GPL-3.0 发布。

---

## 一、成果

| 项目 | 结果 |
| --- | --- |
| 原生库 | libpowder.so：arm64-v8a 8.2 MB / x86_64 9.5 MB（strip 后；-O3 + ThinLTO） |
| 发布包 | app-release.apk 18.45 MB（arm64-v8a + x86_64 两个 ABI 都在里面） |
| 运行验证 | **已在 Android 16（API 37，x86_64）模拟器上实测跑起来**：SDL_main 正常回调、DUST 模拟在跑、稳定 60 FPS、触屏 UI 完整 |
| 签名 | 有根目录 tpt-dev.jks 就用它；没有自动退回 debug 签名（clone 下来直接能出包） |

实测截图（模拟器 2424×1080 横屏，FPS 60.00）：

![Android 上运行中的 The Powder Toy](docs/screenshot-official.png)

---

## 二、目录结构

~~~
ThePowderToy-Android/
├── app/                                  Android 应用模块
│   ├── build.gradle.kts                  打包 / 签名 / ABI 配置
│   ├── libs/sdl2.jar                     SDL2 的 Java 层（编译原生库时自动同步过来）
│   └── src/main/
│       ├── AndroidManifest.xml
│       ├── java/uk/co/powdertoy/tpt/PowderActivity.java
│       ├── jniLibs/<abi>/libpowder.so     原生引擎（脚本生成）
│       └── res/                          图标（含自适应图标）、主题、字符串
├── scripts/
│   ├── bootstrap.ps1                     一次性装好 meson/ninja/NDK
│   ├── build-native.ps1                  交叉编译 libpowder.so
│   ├── make-keystore.ps1                 生成固定开发签名（可选，见第五节）
│   ├── make-icons.py                     从上游图标生成各密度启动图标
│   └── install.ps1                       adb 装机
├── build/native/<abi>-<type>/            meson 构建目录
├── build/native/symbols/<abi>/           未 strip 的 .so（查崩溃用）
├── gradle/, gradlew, gradlew.bat
├── settings.gradle.kts / build.gradle.kts / gradle.properties / local.properties
└── README.md
~~~

上游 The Powder Toy 源码保持在原处（默认 ~~~
C:\Users\JG\Downloads\The-Powder-Toy
~~~），本工程不复制、不修改它。
换机器时改 local.properties 旁边的 **tptSource**（见下文）即可。

---

## 三、环境要求

* Android Studio（自带 JBR 当 JDK 用）
* Android SDK：platform-tools、build-tools、platforms（任意一个 android.jar，脚本会借用）
* Android NDK：脚本会自动装 **27.2.12479018（r27c LTS）**
* Python 3.8+（只用来建 meson 虚拟环境；meson/ninja 会装在工程内，不动系统 Python）
* Windows + PowerShell 7（pwsh）

---

## 四、快速开始

### 1. 一次性准备环境

~~~powershell
.\scripts\bootstrap.ps1
~~~

做两件事：在工程内建 .toolchain/venv 并装 meson + ninja；检查/安装 NDK。

### 2. 编译原生库

~~~powershell
# 真机 + 模拟器都编，开 ThinLTO（推荐）
.\scripts\build-native.ps1 -Abis arm64-v8a,x86_64 -Lto

# 只要真机包，快一半
.\scripts\build-native.ps1 -Abis arm64-v8a -Lto
~~~

第一次运行 meson 会自动从 GitHub 下载 tpt-libs 的预编译静态库
（SDL2 / libcurl / luajit / libpng / bzip2 / jsoncpp / fftw，约 17 MB/ABI）到
~~~
<上游源码>\subprojects\
~~~
国内网络慢的话，把 zip 手动下好放进 subprojects/packagecache/ 也行（文件名和 SHA256 见 .wrap 文件）。

### 3. 打包 APK

~~~powershell
# 调试包
.\gradlew.bat :app:assembleDebug

# 发布包（用工程内固定签名）
.\gradlew.bat :app:assembleRelease

# 顺手把 APK 复制到「下载」目录
.\gradlew.bat deliverApk
~~~

只要真机包（体积减半）：

~~~powershell
.\gradlew.bat :app:assembleRelease -PtptAbis=arm64-v8a
~~~

### 4. 装到设备

~~~powershell
.\scripts\install.ps1 -Launch
~~~

或者手动：

~~~powershell
adb install -r app\build\outputs\apk\release\app-release.apk
~~~

---

### 5. 固定签名（可选，但推荐）

仓库里**故意不放 keystore**。release 包的签名按这个顺序决定：

1. \-PtptKeystore=xxx.jks（配合 -PtptStorePass / -PtptKeyAlias / -PtptKeyPass）
2. 工程根目录的 tpt-dev.jks（本机开发用）
3. 都没有 → 退回 AGP 自动生成的 debug 签名

第 3 种情况下包能编能装，但换台机器或清掉 debug.keystore 之后签名会变，
覆盖安装就会报 INSTALL_FAILED_UPDATE_INCOMPATIBLE。想避免就生成一个固定的：

~~~powershell
.\scripts\make-keystore.ps1
~~~

生成的 tpt-dev.jks 在 .gitignore 里，不会被提交。

---

## 五、用 Android Studio 打开

1. Android Studio → Open → 选到 **ThePowderToy-Android** 目录（不是上面的 DynaUI 工程）。
2. 首次同步前，先按前面第 1、2 步把原生库编出来 ——
   Gradle 的 :app:checkNativeLibs 会在打包前检查
   app/src/main/jniLibs/<abi>/libpowder.so 是否存在，
   缺了会直接报错并告诉你跑哪条命令，不会静默出一个「没有引擎」的空壳 APK。
3. 之后正常点 Run 即可。想重新编原生库，在 Gradle 面板跑 :app:buildNativeLibs。

换源码目录（比如把 The-Powder-Toy clone 到别处）：

~~~powershell
.\gradlew.bat :app:assembleDebug -PtptSource=D:/src/The-Powder-Toy
~~~

---

## 六、针对手机的专门优化

### 编译期（原生库）

| 优化 | 说明 |
| --- | --- |
| **-O3** | 上游 CI 用的是 debugoptimized（即 -O2）。这里换成 release（-O3）。 |
| **ThinLTO** | 加 -Lto 打开，跨编译单元内联。arm64 从 7.9 MB 降到 6.7 MB。 |
| **-ffunction-sections / -fdata-sections + -Wl,--gc-sections** | 每个函数/数据单独成节，链接时丢掉没人用的部分。 |
| **-Wl,-O2** | 让 lld 做更狠的链接期优化。 |
| **-Wl,-z,max-page-size=16384** | 按 16 KB 内存页对齐。Android 15 起有 16 KB 页的设备，不这么链接会直接装不上/起不来。 |
| **-ffast-math / -funsafe-math-optimizations / -ftree-vectorize** | 上游 release 就开了，粒子模拟这种数值密集代码收益明显。 |
| **strip（llvm-strip --strip-unneeded）** | 动态符号表保留、调试符号去掉。33.9 MB → 7.9 MB。未 strip 版本留在 build/native/symbols/ 以便查崩溃。 |
| **x86_64 只开 SSE2** | 模拟器 CPU 特性不可控，上 SSE4/AVX 会在部分 AVD 上直接非法指令。真机走 arm64，NEON 是基线不用额外开。 |
| **可选 -ArmArch v8.2 / v8.4** | arm64 基线是 armv8-a，NEON 默认就有。想再压榨新 SoC 可以开 dotprod/crc/crypto，但 2019 年前的老机会非法指令 —— 所以默认关，只给自己那台机器出包时用。 |

### 打包期

| 优化 | 说明 |
| --- | --- |
| **jniLibs.useLegacyPackaging = false** | libpowder.so 不压缩、按页对齐直接放在 APK 里。安装时不用先解压到 /data，冷启动更快，占用的存储也更少。zipalign -c -P 16 -v 4 已验证通过。 |
| **关闭 R8 / 资源裁剪** | Java 层只有薄薄一层 SDL 胶水，全靠 JNI 名字回调（nativeRunMain 等）。混淆会把名字改掉直接崩，而它能省的空间相对于 7 MB 的原生库可以忽略，所以关掉更划算。 |
| **固定开发签名** | 反复覆盖安装不会因为换签名失败。 |

### 运行期 / 体验

| 优化 | 说明 |
| --- | --- |
| **largeHeap + hardwareAccelerated** | 给模拟和资源留足堆，渲染走硬件。 |
| **sensorLandscape 横屏** | 横屏两个方向都支持，不再限制成单一 landscape。 |
| **configChanges 补全 density / fontScale / smallestScreenSize** | 改字体大小、折叠屏展开时不会把 Activity 重启掉，存档和正在跑的模拟不丢。 |
| **FLAG_KEEP_SCREEN_ON** | 沙盒是长时间挂着看的，不让系统中途熄屏。 |
| **全屏深色主题 + windowBackground** | 启动不再闪一下白屏。 |
| **自适应启动图标（mipmap-anydpi-v26）+ 五档密度图标** | 上游只有一张 mdpi 图标；这里按 48/72/96/144/192 生成，并做了 Android 8+ 的自适应图标。 |
| **触屏 UI 默认开启** | 上游在 android 平台会打开 DEFAULT_TOUCH_UI，这里沿用。 |
| **申请屏幕最高刷新率** | PowderActivity 启动时读 Display.getSupportedModes()，把 preferredRefreshRate 顶到最高档。模拟仍限 60 FPS，但在 90/120/144 Hz 屏上「手指划过去 → 沙子出现」的延迟明显更低。读不到多模式（模拟器）就静默跳过。 |
| **preferMinimalPostProcessing** | 清单里打开，让系统合成器少做一层后处理，进一步压低显示延迟。 |

### 关于 GPU / NPU / AI 加速（说点实话）

这台模拟器的 LLNDK 里能看到 `libneuralnetworks.so`、`libnpumanager.so`，
真机上还有高通 Hexagon NPU、联发科 APU、Google Edge TPU 这类加速器。但它们**帮不上 TPT**，原因很实在：

* **NPU / NNAPI 只吃规整的张量算子。** TPT 的模拟核心是一个逐格子的整数元胞自动机
  （每个像素读几个邻居、按元素规则分支决定下一步），是**访存 + 分支**密集，不是矩阵乘。
  把"元素规则"改写成张量运算要么不可能，要么每帧主机↔NPU 同步的开销就吃掉全部收益。
* **TPT 的瓶颈在 CPU，不在 GPU。** 每一帧是在 CPU 上算完粒子、写进一张纹理再由 GPU 贴出来。
  GPU 只负责最后那次 blit，换 Vulkan 也不会更快 —— 真正要优化的是那个逐格子循环。
* **所以这里的优化全落在"让 CPU 少干活、让系统少挡路"上**：
  `-O3` + ThinLTO + `--gc-sections`（少算、少载入）、16 KB 页对齐（新 SoC 上必须）、
  未压缩 .so（冷启动不解压）、最高刷新率 + 最小后处理（降延迟）。

如果哪天真要做 AI 加速，那得是**另一个功能**（比如用 NPU 跑"根据草图猜你要画什么"），
而不是加速模拟本身。

---

## 七、和上游构建的差异（重要）

1. **只编 libpowder.so，不编 APK。** 上游 android/meson.build 会用 aapt2/d8/apksigner
   自己撸一个 APK；这个流程和 Android Studio 冲突。这里只用 meson 产 libpowder.so，
   剩下的交给 AGP。
2. **直接用 NDK 的 clang++.exe 加 --target=aarch64-linux-android21**，
   绕开 aarch64-linux-android21-clang++.cmd 那层批处理包装（meson 在 Windows 上对 .cmd 处理不稳）。
3. **android_platform 取 tpt-libs 声明值（当前 android-31）。**
   meson 会比对 tpt-libs 里写死的 android_platform，不一致直接报 platform mismatch。
   这个值脚本会自动从解压出的 subprojects/tpt-libs-prebuilt-*-android-* 里读出来。
   android_platform_jar 只在 meson 配置期当字符串收下（我们不走打包那条路），
   所以借用本机已装的任意 android.jar 就行。
4. **不用 -Wl,--exclude-libs,ALL。** SDL2 的 JNI 入口
   （Java_org_libsdl_app_SDLActivity_nativeGetVersion 等）实现于 libSDL2.a，
   一旦把静态库符号从动态符号表里抹掉，Java 侧一调用就抛 UnsatisfiedLinkError，启动即崩。
   这个坑已经踩过一次，脚本里写了注释。

---

## 八、汉化版（粉末游戏）

汉化用的是社区完整汉化分支
[The-Powder-Toy-Chinese](https://github.com/Dragonrster/The-Powder-Toy-Chinese)
（本机在 C:/Users/JG/Downloads/The-Powder-Toy-Chinese-zh_CN/）。
它是 **v99.3.389** 的完整源码树，改了 682 个源文件，并且换了一套带中文字形的 TPT 位图字体
（resources/font.bz2 380 KB，上游只有 57 KB；由 resources/zpix.bdf 用 fonttool.py 生成）。

### 编译 + 打包

~~~powershell
# 1. 编汉化版的原生库（注意 -JniLibsDir / -BuildTag，和官方版分开）
.\scripts\build-native.ps1 -Abis arm64-v8a,x86_64 -Lto ^
    -SourceDir "C:/Users/JG/Downloads/The-Powder-Toy-Chinese-zh_CN/The-Powder-Toy-Chinese-zh_CN" ^
    -JniLibsDir app/src/main/jniLibs-zhcn -BuildTag zhcn

# 2. 打汉化版 APK（一条 -PtptZhcn=true 就够）
.\gradlew.bat :app:assembleRelease -PtptZhcn=true
~~~

汉化版自带这些差异（都在 app/build.gradle.kts 里定义）：

| 项 | 官方版 | 汉化版 |
| --- | --- | --- |
| applicationId | uk.co.powdertoy.tpt | uk.co.powdertoy.tpt.zhcn |
| 应用名 | The Powder Toy | 粉末游戏 |
| 版本 | 100.1.400 | 99.3.389 |
| 原生库 | app/src/main/jniLibs | app/src/main/jniLibs-zhcn |

包名不同，所以**两个版本能装在同一台手机上互不干扰**（存档目录也是分开的）。

产物：app-release.apk 19.16 MB（arm64-v8a + x86_64），已实测运行：

![汉化版运行截图](docs/screenshot-zhcn.png)

### 注意

* 汉化分支停在 v99.3.389（2025 年初），比上游 100.1.400 旧，没有新版功能。
* 汉化用的 tpt-libs vtag 是 v20250901181559，和上游的 v20260821222421 不同 ——
  build-native.ps1 会自动从源码的 .wrap 里读，不用手工改。
* 应用名走 resValue 生成（AGP 9 需要 buildFeatures 里打开 resValues），
  res/values/strings.xml 里不要再写 app_name，否则资源重名。

---

## 九、常见问题

**装不上，报 INSTALL_FAILED_UPDATE_INCOMPATIBLE**
设备上已有官方签名版本的 uk.co.powdertoy.tpt。先卸载：
~~~powershell
adb uninstall uk.co.powdertoy.tpt
~~~

**Gradle 报「缺少原生库」**
原生库还没编。跑：
~~~powershell
.\scripts\build-native.ps1 -Abis arm64-v8a,x86_64 -Lto
~~~

**启动闪退，日志里是 UnsatisfiedLinkError: nativeGetVersion**
链接参数里混进了 --exclude-libs。删掉它重新编（见第七节第 4 条）。

**mergeReleaseJniLibFolders 报 libpowder.so Duplicate resources**
sourceSets 里用了 jniLibs.srcDir(...)（追加）。必须用 setSrcDirs(listOf(...))（替换），
否则默认的 src/main/jniLibs 和新目录会同时被收进去。

**脚本报「已为命令多次定义名为 Debug 的参数」**
参数不能叫 -Debug，[CmdletBinding()] 已经自带了同名公共参数，改用 -DebugBuild。

**meson 报 tpt-libs android platform mismatch**
tpt-libs 的 vtag 变了。build-native.ps1 会自动读取实际值；
如果 subprojects 下还没解压，先随便跑一次让它解压，再跑第二次。

**tpt-libs 下载太慢**
见第四节第 2 步，手动放进 subprojects/packagecache/。

**修改源码目录**
gradle -PtptSource=... 或改 app/build.gradle.kts 里的 tptSourceDir；
build-native.ps1 用 -SourceDir 参数。

---

## 九、下一步可以做的

* ABI 分包（-PtptAbis 已经能只出单 ABI 包），要上架的话可以再加 splits。
* 高刷屏适配：在 SDL 的 surface 上调用 setFrameRate 对齐 120 Hz 屏幕。
* 用 baseline profile 优化 Java 侧冷启动（收益有限，Java 层很薄）。
* 把 -Wl,--icf=all 打开试试更小的体积（脚本里是 -Icf 开关，默认关）。
