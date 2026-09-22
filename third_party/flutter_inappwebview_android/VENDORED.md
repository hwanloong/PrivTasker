本目录是 flutter_inappwebview_android 1.1.3 的 vendored 副本。

原因：该插件 android/build.gradle 使用了
    getDefaultProguardFile('proguard-android.txt')
而 AGP 9.0+ 已移除对它的支持，会直接让构建失败：

    `getDefaultProguardFile('proguard-android.txt')` is no longer supported
    since it includes `-dontoptimize` ...

上游暂无兼容 AGP 9 的版本（6.1.5 已是最新稳定版），也没有更新 AGP 的余地
（本项目构建链沿用 pj1 已验证的 AGP 9.1.0），因此把插件 vendor 进来。

补丁只有一处：
    android/build.gradle 里两处 proguard-android.txt
    → proguard-android-optimize.txt

升级该插件时请重新应用同样的补丁（或确认上游已修复后删除本目录，
并移除 pubspec.yaml 中的 dependency_overrides）。
