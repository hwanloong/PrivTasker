pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        // Flutter 引擎制品（io.flutter:*-debug）只在 download.flutter.io 有，必须放最前：
        // 否则 Gradle 会先试后面那些握手超时的源，卡在那里根本轮不到它。
        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
        // 其余全部走阿里云镜像（实测制品 200 / 0.15s）。
        // 刻意不再列 google()/mavenCentral()：在当前网络下它们会握手超时。
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")
