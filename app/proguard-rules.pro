# 没有开启 R8（见 build.gradle.kts 里的说明），这里留作以后需要时使用。
#
# 如果哪天要开 minify，务必保留 SDL 的 Java 层：
# native 代码通过 JNI 名字回调 SDLActivity，混淆后名字对不上就会崩。
-keep class org.libsdl.app.** { *; }
-keep class uk.co.powdertoy.tpt.** { *; }
