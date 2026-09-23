plugins {
    id("com.android.application")
    // 必须有这一行：下面的 `kotlin { compilerOptions { ... } }` 依赖 Kotlin 插件提供的
    // 扩展，漏掉就会报 "Unresolved reference 'compilerOptions'"。
    // 版本在 settings.gradle.kts 的 plugins 块里声明。
    id("org.jetbrains.kotlin.android")
    // Chaquopy 要放在 Android 插件之后、Flutter 插件之前
    id("com.chaquo.python")
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

        // 只出 64 位。**刻意砍掉 armeabi-v7a**：
        // Chaquopy 从 Python 3.12 起不再支持 32 位 ABI，而我们要用 3.13 ——
        // 它对 16KB 页设备（Android 15+ 新机）的 wheel 兼容性最好。
        // 二者不可兼得，32 位设备在 2026 年已无保留价值。
        //
        // ⚠️ **不要试图用 splits 出分架构包**。AGP 9 默认启用新 DSL
        // （android.newDsl=true），`splits` 在这个层级已不被支持 ——
        // 用它会让整个 build.gradle.kts 脚本编译失败
        // （报 "android{} is deprecated" 然后连锁失败）。
        // 所以只能用 ndk.abiFilters，代价是产出一个含两个 ABI 的包。
        ndk {
            abiFilters.clear()
            abiFilters.addAll(listOf("arm64-v8a", "x86_64"))
        }
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

// ============================================================ Chaquopy
//
// 把 CPython 嵌进应用 —— 用户零配置就有完整的 Python。
//
// 版本选 3.13 而不是更高的 3.14，原因是 **wheel 供给**：
// Chaquopy 明确说 3.14 目前 "very few Android wheels available"，
// 而我们要用的 python-docx / python-pptx **都依赖 lxml（C 扩展）**——
// 没有 wheel 就装不上，Word 和 PPT 功能直接废掉。
// 3.13 是目前 wheel 覆盖最好的版本，而且对 16KB 页设备兼容性也好。
//
// buildPython 必须写**绝对路径**：
// 本机默认的 `python` 是 3.14，版本对不上会直接构建失败；
// 而 `py` launcher 在 WindowsApps 里，Gradle 的 PATH 看不到它
// （实测报 "Couldn't find 'py' on the PATH"）。所以只能写死路径。
// 这台机器的工具链本来就是固定位置，写在注释里说明来源即可。
chaquopy {
    defaultConfig {
        version = "3.13"
        buildPython("C:\\Users\\lmqhw\\AppData\\Local\\Programs\\Python\\Python313\\python.exe")
        pip {
            // ⚠️ **Chaquopy 没有运行时的 pip。**
            // 这里列的包在**构建时**装进 APK，用户装不了任何东西 ——
            // 想加包必须改这里 + 重新构建。所以一次装够。
            //
            // 分工：
            // · 固定能力（Office、数据处理）→ 在这里烤进去，用户零配置
            // · 任意/临时需求 → termux 工具，用户随时 pkg install
            // · 把能力组合成新工具 → 插件（shell/HTTP/python），运行时加
            install("openpyxl")        // Excel（纯 Python，已验证）
            install("python-docx")     // Word
            install("python-pptx")     // PPT
            install("lxml")            // 上面两个的依赖，C 扩展 —— 关键考验
            install("pillow")          // 图像处理
            install("requests")        // HTTP
            install("beautifulsoup4")  // 网页解析
        }
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
