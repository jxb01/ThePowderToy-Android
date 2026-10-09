// 顶层构建脚本：只声明插件，具体配置在 app 模块里。
//
// 原生库（libpowder.so）不由 Gradle 直接编译，而是先用 meson + Android NDK
// 交叉编译好、放进 app/src/main/jniLibs/<abi>/，Gradle 负责打包 / 签名 / 安装。
// 重新编译原生库：
//     .\scripts\build-native.ps1 -Abis arm64-v8a,x86_64
plugins {
    id("com.android.application") version "9.3.0" apply false
}

/**
 * 把构建好的 APK 复制到「下载」目录，方便直接拿手机装。
 *
 *     .\gradlew.bat deliverApk
 *
 * 文件名带构建类型和时间戳，一眼能分出新旧包。
 */
tasks.register("deliverApk") {
    group = "build"
    description = "把 app 构建出的 APK 复制到下载目录的 ThePowderToy-APK 文件夹"

    doLast {
        val source = file("app/build/outputs/apk")
        if (!source.exists()) {
            logger.warn("还没有构建产物，先跑 :app:assembleDebug 或 :app:assembleRelease")
            return@doLast
        }
        val apks = source.walkTopDown().filter { it.extension == "apk" }.toList()
        if (apks.isEmpty()) {
            logger.warn("app/build/outputs/apk 下没有 APK")
            return@doLast
        }

        val stamp = java.text.SimpleDateFormat("yyyyMMdd-HHmm").format(java.util.Date())
        val home = System.getProperty("user.home") ?: ""
        val downloads = File(home, "Downloads")
        val dest = if (home.isNotEmpty() && downloads.exists()) File(downloads, "ThePowderToy-APK") else file("dist")
        dest.mkdirs()

        apks.forEach { apk ->
            val kind = if (apk.name.contains("release")) "release" else "debug"
            val target = File(dest, "ThePowderToy-$kind-$stamp.apk")
            apk.copyTo(target, overwrite = true)
            logger.lifecycle("APK -> " + target.absolutePath + "  (" + (apk.length() / 1024 / 1024) + " MB)")
        }
        logger.lifecycle("最新 APK 已送到：" + dest.absolutePath)
    }
}
