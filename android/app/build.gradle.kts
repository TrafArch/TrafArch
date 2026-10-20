import java.io.FileInputStream
import java.io.RandomAccessFile
import java.security.MessageDigest
import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") apply false
}

// Public source checkouts do not include the private Firebase configuration.
// A repair APK is independent of the production Firebase application.
val repairBuild = providers.gradleProperty("repairBuild").orNull == "true"
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
// - 构建开始前同步 lib/core/app_info.dart，保证产物内 UI 显示的即本次号；
// - debug 构建（flutter run 等）不递增、不修改任何文件。
val pubspecFile = rootProject.file("../pubspec.yaml")
val appInfoFile = rootProject.file("../lib/core/app_info.dart")
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
if (isReleaseBuild) {
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

// ===================== 交通数据库自动同步 =====================
// 把 transitDbMasterDir 下的 TrafArch_Database_CU/TU.sqlite 同步进
// assets/data，并强制刷新修改时间戳——使 Flutter 按 mtime 判断的资产
// 增量打包缓存失效，保证 compileFlutterBuild*（flutter assemble）
// 读取到的永远是最新库。debug / release 构建均生效；属性未配置或
// 目录不存在时静默跳过，直接使用仓库内资产。
val transitDbMasterDirPath =
    providers.gradleProperty("transitDbMasterDir").orNull?.trim().orEmpty()
val transitDbAssetsDir = rootProject.file("../assets/data")
val transitDbNames = listOf("TrafArch_Database_CU.sqlite", "TrafArch_Database_TU.sqlite")

fun transitDbSha256(f: File): String =
    MessageDigest.getInstance("SHA-256")
        .digest(f.readBytes()).joinToString("") { "%02x".format(it) }

fun transitDbUserVersion(f: File): Int? =
    if (f.length() > 64) {
        val b = ByteArray(4)
        RandomAccessFile(f, "r").use { it.seek(60); it.readFully(b) }
        ((b[0].toInt() and 0xFF) shl 24) or ((b[1].toInt() and 0xFF) shl 16) or
            ((b[2].toInt() and 0xFF) shl 8) or (b[3].toInt() and 0xFF)
    } else null

val syncTransitDatabases = tasks.register("syncTransitDatabases") {
    description = "Sync latest TrafArch_Database_*.sqlite into assets/data before packaging"
    // 每次执行都做内容比对与 touch，不接受 up-to-date 判定
    outputs.upToDateWhen { false }
    doLast {
        if (transitDbMasterDirPath.isEmpty()) {
            logger.info("transitDbMasterDir 未配置，跳过交通数据库同步")
            return@doLast
        }
        val masterDir = File(transitDbMasterDirPath)
        if (!masterDir.isDirectory) {
            logger.warn("transitDbMasterDir 不存在: $transitDbMasterDirPath，跳过同步")
            return@doLast
        }
        for (name in transitDbNames) {
            val src = masterDir.resolve(name)
            if (!src.isFile) continue
            val dst = transitDbAssetsDir.resolve(name)
            if (!dst.isFile || dst.length() != src.length() ||
                transitDbSha256(dst) != transitDbSha256(src)
            ) {
                dst.parentFile.mkdirs()
                src.copyTo(dst, overwrite = true)
                logger.lifecycle("Transit database synced: $name (user_version=${transitDbUserVersion(dst)})")
            }
            // 无论是否刚复制，都刷新 mtime，打破 Flutter 资产增量缓存
            dst.setLastModified(System.currentTimeMillis())
        }
    }
}

// Flutter 资产打包（flutter assemble）所在的 Gradle 任务：
// 同步必须先于它执行，APK 内的 SQLite 才是同步后的版本
tasks.matching { it.name.startsWith("compileFlutterBuild") }.configureEach {
    dependsOn(syncTransitDatabases)
}
// ==========================================================

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
        manifestPlaceholders["appLabel"] = if (repairBuild) "TrafArch 修复验证版" else "TrafArch"
    }

    buildTypes {
        debug {
            if (repairBuild) {
                applicationIdSuffix = ".repair"
                versionNameSuffix = "-repair"
            }
        }
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

    // Google Code Scanner（GMS 扫码）：扫码界面与相机由 Google Play 服务提供，
    // 应用无需申请相机权限；无 GMS 设备由 Dart 端回退应用内相机扫码
    implementation("com.google.android.gms:play-services-code-scanner:16.1.0")

}
