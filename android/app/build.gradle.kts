import java.io.File
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
// - Debug / Profile / Release 的 APK / AAB 构建均使用当前 N，包括 repairBuild；
// - 生成安装包后把 N+1 预留为下一次构建号，写回 pubspec.yaml；
// - 构建开始前同步 lib/app/app_info.dart，保证产物内 UI 显示的即本次号；
// - test / lint / help / tasks 及 --dry-run 不递增；同次调用多个打包任务只递增一次。
val pubspecFile = rootProject.file("../pubspec.yaml")
val appInfoFile = rootProject.file("../lib/app/app_info.dart")
val versionRegex = Regex("""(?m)^version:\s*([^\s+]+)\+(\d+)""")

val pubspecText = pubspecFile.readText()
val versionMatch = versionRegex.find(pubspecText)
    ?: error("pubspec.yaml 中未找到 'version: x.y.z+N' 格式的版本号")
val appVersionName = versionMatch.groupValues[1]
val appVersionCode = versionMatch.groupValues[2].toInt()

val buildModes = listOf("Debug", "Profile", "Release")
val artifactTaskNames = buildModes.flatMap { mode ->
    listOf("package$mode", "assemble$mode", "bundle$mode")
}.toSet()
val buildEntryTaskNames = artifactTaskNames + setOf("assemble", "build", "bundle") +
    buildModes.map { "install$it" }
val isApplicationBuild = !gradle.startParameter.isDryRun &&
    gradle.startParameter.taskNames.any {
        val taskName = it.substringAfterLast(':')
        val taskProject = it.substringBeforeLast(':', "")
        (taskProject.isEmpty() || taskProject.removePrefix(":") == project.path.removePrefix(":")) &&
            taskName in buildEntryTaskNames
    }
if (isApplicationBuild) {
    // 每次打包必须重新读取源码版本并同步 Dart 信息，不复用配置缓存中的旧版本。
    tasks.matching { it.name in artifactTaskNames }.configureEach {
        notCompatibleWithConfigurationCache("Updates AppInfo and reserves the next build number")
    }
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
    // APK 包装 / AAB 构建任务成功后预留下一个号。
    // Gradle 9 起 gradle.buildFinished(Closure) 已废弃（配置缓存不兼容，Gradle 10 移除），
    // 且 Kotlin lambda 无法再隐式转换为 Groovy Closure；改为挂在发布产物任务的 doLast：
    // 包装之前失败不会执行 doLast；安装包已经生成时即消耗本次号。
    // buildNumberBumped 防止同一次调用经 package、assemble 或多个模式重复递增。
    var buildNumberBumped = false
    tasks.matching { it.name in artifactTaskNames }.configureEach {
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
                    "Build number consumed: ${appVersionCode}; next build will use ${appVersionCode + 1}"
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

// Signing secrets stay outside source checkouts. Explicit configuration must
// fail if invalid instead of silently producing an APK with the debug key.
val signingPropertiesPath = providers.gradleProperty("trafarchSigningProperties")
    .orElse(providers.environmentVariable("TRAFARCH_SIGNING_PROPERTIES")).orNull
val legacySigningFile = rootProject.file("key.properties")
val userSigningFile = File(System.getProperty("user.home"), ".config/TrafArch/signing/key.properties")
val keystorePropertiesFile = when {
    unsignedApk -> legacySigningFile
    signingPropertiesPath != null -> {
        require(signingPropertiesPath.isNotBlank()) { "Signing properties path is empty" }
        rootProject.file(signingPropertiesPath)
    }
    userSigningFile.exists() -> userSigningFile
    else -> legacySigningFile
}
val keystoreProperties = Properties()
var signingStoreFile: File? = null
if (!unsignedApk && (signingPropertiesPath != null || keystorePropertiesFile.exists())) {
    require(keystorePropertiesFile.isFile) { "Signing properties file is missing or not a file" }
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
    for (name in listOf("keyAlias", "keyPassword", "storeFile", "storePassword")) {
        require(!keystoreProperties.getProperty(name).isNullOrEmpty()) { "Missing signing property: $name" }
    }
    val configuredStore = File(keystoreProperties.getProperty("storeFile"))
    val resolvedStore = when {
        configuredStore.isAbsolute -> configuredStore
        keystorePropertiesFile.canonicalFile == legacySigningFile.canonicalFile -> file(configuredStore.path)
        else -> File(keystorePropertiesFile.parentFile, configuredStore.path)
    }
    require(resolvedStore.isFile) { "Configured signing keystore is missing or not a file" }
    signingStoreFile = resolvedStore
}

android {
    namespace = "com.kajolno.TrafArch"
    compileSdk = 37
    ndkVersion = "30.0.16248370"
    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        if (signingStoreFile != null) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = signingStoreFile
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
            manifestPlaceholders["appLabel"] = "TrafArch"
            if (unsignedApk) {
                signingConfig = null
            } else if (signingStoreFile != null) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
        release {
            signingConfig = if (unsignedApk) {
                null
            } else if (signingStoreFile != null) {
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
    // Match url_launcher_android's version; the application directly uses this API.
    implementation("androidx.browser:browser:1.9.0")
    testImplementation("junit:junit:4.13.2")

    // Import the Firebase BoM
    implementation(platform("com.google.firebase:firebase-bom:35.0.0"))

    // TODO: Add the dependencies for Firebase products you want to use
    // When using the BoM, don't specify versions in Firebase dependencies
    implementation("com.google.firebase:firebase-analytics")

    // Add the dependencies for any other desired Firebase products
    // https://firebase.google.com/docs/android/setup#available-libraries

}
