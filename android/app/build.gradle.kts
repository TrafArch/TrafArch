import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// [AGC] AppGallery Connect 插件（agcp 由根工程 buildscript classpath 提供）。
// 与上面 classpath 行成对启用/停用；启用后 agconnect-services.json 必须存在。

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.kajolno.TrafArch"
    compileSdk = 37
    ndkVersion = "30.0.16248370"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    defaultConfig {
        applicationId = "com.kajolno.TrafArch"
        minSdk = 26
        targetSdk = 37
        versionCode = 3
        versionName = "1.0.1-beta.2"
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // 体积优化：R8 代码压缩 + 资源收缩（仅 release 生效）
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Import the Firebase BoM
    implementation(platform("com.google.firebase:firebase-bom:35.0.0"))

    // TODO: Add the dependencies for Firebase products you want to use
    // When using the BoM, don't specify versions in Firebase dependencies
    implementation("com.google.firebase:firebase-analytics")

    // Add the dependencies for any other desired Firebase products
    // https://firebase.google.com/docs/android/setup#available-libraries

    // Google Code Scanner（GMS 扫码）：扫码界面与相机由 Google Play 服务提供，
    // 应用无需申请相机权限；无 GMS 设备由 Dart 端回退应用内相机扫码
    implementation("com.google.android.gms:play-services-code-scanner:16.1.0")

    // 华为统一扫码（Scan Kit）：默认扫码界面（自带相册导入入口）与位图识码
    // 均为纯端侧能力，无需 AGC 配置；鸿蒙 4.2 等无 GMS 的华为设备走此通道。
    // scanplus（约 3.3MB）内含增强识别模型；体积极敏感可换基础包 com.huawei.hms:scan
    // 注意：版本号必须存在于华为仓。2.12.0.302 实际不存在（解析 404），
    // 旧版可选 2.12.0.301，当前最新为 2.15.0.301（2026-04 发布）。
    implementation("com.huawei.hms:scanplus:2.15.0.301")
}
