# Flutter 引擎与核心插件规则
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# 原生方法与 JNI 符号保持
-keepclasseswithmembernames class * {
    native <methods>;
}

# 自定义插件防混淆
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-keep class io.flutter.plugins.imagepicker.** { *; }
-keep class io.flutter.plugins.videoplayer.** { *; }
-keep class io.flutter.plugins.webviewflutter.** { *; }
-keep class com.baseflow.permissionhandler.** { *; }
-keep class io.github.crow_misia.gal.** { *; }

# 依赖警告抑制
-dontwarn com.google.android.play.core.**
-dontwarn androidx.**
-dontwarn com.google.android.material.**
-dontwarn okio.**
-dontwarn javax.annotation.**
