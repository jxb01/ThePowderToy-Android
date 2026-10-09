// ---------------------------------------------------------------------------
// The Powder Toy —— Android 模块
//
// 原生库由 scripts/build-native.ps1（meson + Android NDK）预编译到
// app/src/main/jniLibs/<abi>/libpowder.so，Gradle 只负责打包 / 签名 / 安装。
// ---------------------------------------------------------------------------
plugins {
    id("com.android.application")
}

// 上游源码位置：默认就是本机 clone 的 The-Powder-Toy。
// 换机器时用 -PtptSource=D:/path/to/The-Powder-Toy 覆盖，或直接改这里。
val tptSourceDir: String = (findProperty("tptSource") as String?)
    ?: "C:/Users/JG/Downloads/The-Powder-Toy"

// 默认同时打包 arm64-v8a（真机）和 x86_64（模拟器）。
// 只要真机包：-PtptAbis=arm64-v8a
val tptAbis: List<String> = ((findProperty("tptAbis") as String?) ?: "arm64-v8a,x86_64")
    .split(",").map { it.trim() }.filter { it.isNotEmpty() }

// ---------------------------------------------------------------------------
// 多版本支持：官方英文版和汉化版装在同一台手机上也不会互相覆盖。
//
//   官方版（默认，The-Powder-Toy 源码）：
//     .\gradlew.bat :app:assembleRelease
//
//   汉化版（The-Powder-Toy-Chinese-zh_CN 源码）：
//     .\gradlew.bat :app:assembleRelease -PtptZhcn=true
//
// 汉化版的应用名直接写成 Kotlin 常量，不走命令行参数 ——
// 本机控制台是 cp936，命令行传中文会被转坏。
// ---------------------------------------------------------------------------
val tptZhcn: Boolean = ((findProperty("tptZhcn") as String?) ?: "false").toBoolean()

val tptJniLibs: String = (findProperty("tptJniLibs") as String?)
    ?: if (tptZhcn) "src/main/jniLibs-zhcn" else "src/main/jniLibs"
val tptAppId: String = (findProperty("tptAppId") as String?)
    ?: if (tptZhcn) "uk.co.powdertoy.tpt.zhcn" else "uk.co.powdertoy.tpt"
val tptLabel: String = (findProperty("tptLabel") as String?)
    ?: if (tptZhcn) "粉末游戏" else "The Powder Toy"
val tptVersionName: String = (findProperty("tptVersionName") as String?)
    ?: if (tptZhcn) "99.3.389" else "100.1.400"
val tptVersionCode: Int = ((findProperty("tptVersionCode") as String?) ?: if (tptZhcn) "389" else "400").toInt()

// ---------------------------------------------------------------------------
// 签名
//   仓库里不放 keystore（.gitignore 挡着），所以这里必须能"没有也编得动"：
//     1. -PtptKeystore=xxx.jks（配 -PtptStorePass / -PtptKeyAlias / -PtptKeyPass）优先
//     2. 工程根目录的 tpt-dev.jks —— 本机开发用的固定签名
//     3. 都没有 → 退回 AGP 自动生成的 debug 签名，clone 下来直接就能编、能装
//   想要"覆盖安装不换签名"，照 scripts/make-keystore.ps1 生成一个放根目录即可。
// ---------------------------------------------------------------------------
val tptKeystoreFile: java.io.File? = run {
    val prop = findProperty("tptKeystore") as String?
    when {
        prop != null && file(prop).exists() -> file(prop)
        rootProject.file("tpt-dev.jks").exists() -> rootProject.file("tpt-dev.jks")
        else -> null
    }
}

android {
    namespace = "uk.co.powdertoy.tpt"
    compileSdk { version = release(37) }

    defaultConfig {
        applicationId = tptAppId
        // 原生库按 API 21 的 sysroot 编译，Gradle 侧抬到 24 以贴合 AGP 9 的下限
        minSdk = 24
        targetSdk = 37
        versionCode = tptVersionCode
        versionName = tptVersionName

        // 应用名由构建参数决定，这样一份代码就能出「The Powder Toy」和「粉末游戏」两个包。
        // res/values/strings.xml 里就不要再定义 app_name 了，否则重名冲突。
        resValue("string", "app_name", tptLabel)

        ndk {
            // 只把真正编好的 ABI 打进包里
            abiFilters.addAll(tptAbis)
        }
    }

    signingConfigs {
        if (tptKeystoreFile != null) {
            create("tpt") {
                storeFile = tptKeystoreFile
                storePassword = (findProperty("tptStorePass") as String?) ?: "bagelsbagels"
                keyAlias = (findProperty("tptKeyAlias") as String?) ?: "androidkey"
                keyPassword = (findProperty("tptKeyPass") as String?) ?: "bagelsbagels"
            }
        }
    }

    buildTypes {
        debug {
            isMinifyEnabled = false
            isJniDebuggable = true
            optimization { enable = false }
        }
        release {
            // 原生库那边已经是 -O3 + ThinLTO + fast-math；
            // Java 层只有薄薄一层 SDL 胶水，靠 JNI 名字回调，
            // 开 R8 反而可能把 org.libsdl.app.SDLActivity 的 native 绑定裁掉 —— 所以关掉。
            isMinifyEnabled = false
            isShrinkResources = false
            optimization { enable = false }
            // 有 keystore 用固定签名（反复覆盖安装不会因换签名失败），
            // 没有就退回 debug 签名 —— 保证 clone 下来什么都不配也能出包。
            signingConfig = if (tptKeystoreFile != null) {
                signingConfigs.getByName("tpt")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    packaging {
        jniLibs {
            // .so 不压缩、按页对齐直接塞进 APK：
            // 安装体积更小，dlopen 时不用先解压到 /data，冷启动更快。
            useLegacyPackaging = false
        }
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }

    // 原生库目录：默认 app/src/main/jniLibs/<abi>/，可用 -PtptJniLibs 指到别处。
    // 汉化版编到 src/main/jniLibs-zhcn，这样官方版和汉化版能同时存在、互不覆盖。
    sourceSets {
        getByName("main") {
            // 必须用 setSrcDirs（替换）而不是 srcDir（追加）：
            // 追加的话默认的 src/main/jniLibs 也还在，两个目录里都有 libpowder.so，
            // mergeJniLibs 会直接报 Duplicate resources。
            jniLibs.setSrcDirs(listOf(tptJniLibs))
        }
    }

    buildFeatures {
        buildConfig = false
        // 应用名靠 resValue 生成（同一份代码出英文版/汉化版两个包），
        // AGP 9 起这个能力默认关着，必须显式打开。
        resValues = true
    }

    lint {
        abortOnError = false
        checkReleaseBuilds = false
    }
}

dependencies {
    // SDL2 的 Java 层（org.libsdl.app.SDLActivity），取自 tpt-libs 的预编译包
    implementation(files("libs/sdl2.jar"))
}

// ---------------------------------------------------------------------------
// 便利任务
// ---------------------------------------------------------------------------

/** 用 meson + NDK 重新编译原生库，并同步到 jniLibs。 */
val buildNativeLibs by tasks.registering(Exec::class) {
    group = "thepowdertoy"
    description = "用 meson + Android NDK 重新交叉编译 libpowder.so 并同步到 jniLibs"
    workingDir = rootProject.projectDir
    commandLine(
        "pwsh", "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", File(rootProject.projectDir, "scripts/build-native.ps1").absolutePath,
        "-Abis", tptAbis.joinToString(","),
        "-SourceDir", tptSourceDir,
        "-JniLibsDir", tptJniLibs
    )
}

/** 打包前确认每个 ABI 的 libpowder.so 都在，避免出一个「没有引擎」的 APK。 */
val checkNativeLibs by tasks.registering {
    group = "thepowdertoy"
    description = "检查各 ABI 的 libpowder.so 是否已就位"
    doLast {
        val missing = tptAbis.filter { !File(projectDir, "$tptJniLibs/$it/libpowder.so").exists() }
        if (missing.isNotEmpty()) {
            throw GradleException(
                "缺少原生库：${missing.joinToString(", ")}\n" +
                "先执行： .\\scripts\\build-native.ps1 -Abis ${tptAbis.joinToString(",")}\n" +
                "当前找的是 $tptJniLibs\n" +
                "或在 Android Studio 的 Gradle 面板里运行 :app:buildNativeLibs"
            )
        }
        tptAbis.forEach {
            val f = File(projectDir, "$tptJniLibs/$it/libpowder.so")
            logger.lifecycle("  $it : ${f.length() / 1024 / 1024} MB")
        }
    }
}

tasks.named("preBuild") { dependsOn(checkNativeLibs) }
