plugins {
    id("com.android.application")
    // 必须有这一行：下面的 `kotlin { compilerOptions { ... } }` 依赖 Kotlin 插件提供的
    // 扩展，漏掉就会报 "Unresolved reference 'compilerOptions'"。
    // 版本在 settings.gradle.kts 的 plugins 块里声明。
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.dsh.dsh_agent"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.dsh.dsh_agent"
        // Shizuku 需要 API 23+；这里抬到 26 (Android 8.0)，因为用到了
        // foreground service 与 MediaProjection 相关的新行为。
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // 沿用 pj1 已验证的方案：release 用 debug 签名。
            // 自用场景（不分发、不上架）足够，且 `flutter run --release` 可直接跑。
            signingConfig = signingConfigs.getByName("debug")
            // 自用包，不做混淆/裁剪：Shizuku 用反射拿 API，混淆反而容易出玄学问题。
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Shizuku：api 提供 Shizuku 类与权限/监听 API，provider 负责跨进程权限传递。
    implementation("dev.rikka.shizuku:api:13.1.5")
    implementation("dev.rikka.shizuku:provider:13.1.5")
    // aidl 提供 IShizukuService —— 必须显式依赖：
    // Shizuku.newProcess 在 13.1.5 里是 private，执行命令只能走这层 AIDL 接口。
    implementation("dev.rikka.shizuku:aidl:13.1.5")
    implementation("androidx.core:core-ktx:1.13.1")
}

flutter {
    source = "../.."
}
