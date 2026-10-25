import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") apply false
}

// Public source checkouts do not include the private Firebase configuration.
// The application ID below is the install identity; a debug-signed build cannot
// upgrade an installation that uses the developer's original signing key.
val repairBuild = providers.gradleProperty("repairBuild").orNull == "true"
// Hand an aligned APK to the developer for signing with the original key.
val unsignedApk = providers.gradleProperty("unsignedApk").orNull == "true"
val hasGoogleServicesConfig = fileTree(projectDir) {
    include("google-services.json", "src/**/google-services.json")
}.files.isNotEmpty()
if (hasGoogleServicesConfig && !repairBuild) {
    apply(plugin = "com.google.gms.google-services")
}

// ===================== 版本号自动递增 =====================
// pubspec.yaml 的 "version: x.y.z+N" 为版本唯一来源（N = 构建版本号，如 2003）：
// - release 构建（assembleRelease / bundleRelease）时，本次产物直接使用当前 N；
// - 构建成功后把 N 预分配为下一个号并写回 pubspec.yaml；构建失败不消耗号；
// - 构建开始前同步 lib/app/app_info.dart，保证产物内 UI 显示的即本次号；
// - debug 构建（flutter run 等）不递增、不修改任何文件。
val pubspecFile = rootProject.file("../pubspec.yaml")
val appInfoFile = rootProject.file("../lib/app/app_info.dart")
val versionRegex = Regex("""(?m)^version:\s*([^\s+]+)\+(\d+)""")

val pubspecText = pubspecFile.readText()
val versionMatch = versionRegex.find(pubspecText)
    ?: error("pubspec.yaml 中未找到 'version: x.y.z+N' 格式的版本号")
val appVersionName = versionMatch.groupValues[1]
val appVersionCode = versionMatch.groupValues[2].toInt()

val isReleaseBuild = gradle.startParameter.taskNames.any {
    val taskName = it.substringAfterLast(':')
    taskName == "assembleRelease" || taskName == "bundleRelease"
}
if (isReleaseBuild && !repairBuild) {
    // 同步 app_info（发生在 Dart 编译之前，本次产物内显示的就是本次号）
    if (appInfoFile.exists()) {
        val original = appInfoFile.readText()
        val updated = original
            .replace(Regex("static const String version = '[^']*'")) {
                "static const String version = '$appVersionName'"
            }
            .replace(Regex("static const String buildNumber = '[^']*'")) {
                "static const String buildNumber = '$appVersionCode'"
            }
        if (updated != original) {
            appInfoFile.writeText(updated)
        }
    }
    // 构建成功后预分配下一个号；失败则保留当前值，下次构建继续使用。
    // Gradle 9 起 gradle.buildFinished(Closure) 已废弃（配置缓存不兼容，Gradle 10 移除），
    // 且 Kotlin lambda 无法再隐式转换为 Groovy Closure；改为挂在发布产物任务的 doLast：
    // 任一依赖任务失败时 assembleRelease/bundleRelease 被跳过、不会执行到 doLast，
    // 与“构建成功才递增”语义一致。buildNumberBumped 防止同一次调用两个任务重复递增。
    var buildNumberBumped = false
    tasks.matching { it.name == "assembleRelease" || it.name == "bundleRelease" }.configureEach {
        doLast {
            if (!buildNumberBumped) {
                buildNumberBumped = true
                pubspecFile.writeText(
                    pubspecFile.readText().replaceFirst(
                        versionRegex,
                        "version: $appVersionName+${appVersionCode + 1}"
                    )
                )
                logger.lifecycle(
                    "Build number consumed: ${appVersionCode}; next release build will use ${appVersionCode + 1}"
                )
            }
        }
    }
}
// ==========================================================

// Published reference packages and reference_manifest.json are maintained as
// one verified set by tools/reference_data. Packaging never overwrites them
// from a machine-specific directory or rewrites their modification times.
check(!providers.gradleProperty("transitDbMasterDir").isPresent) {
    "transitDbMasterDir is retired. Run python -m tools.reference_data build/validate " +
        "and remove this Gradle property; see docs/MIGRATION.md."
}

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
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
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
        versionCode = appVersionCode
        versionName = appVersionName
        manifestPlaceholders["appLabel"] = "TrafArch"
    }

    buildTypes {
        debug {
            if (unsignedApk) {
                signingConfig = null
            }
        }
        release {
            signingConfig = if (unsignedApk) {
                null
            } else if (keystorePropertiesFile.exists()) {
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
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
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

}
