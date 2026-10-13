plugins {
    // Add the dependency for the Google services Gradle plugin
    id("com.google.gms.google-services") version "4.5.0" apply false
}

buildscript {
    repositories {
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/central") }
        google()
        mavenCentral()
        // 华为仓：AGC 插件（agcp）下载源
        maven { url = uri("https://developer.huawei.com/repo/") }
    }
    dependencies {
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.3.20")
        // [AGC] AppGallery Connect 插件：读取 android/app/agconnect-services.json
        // 并注入构建。注意：启用本行与 app 模块的 apply 行后，
        // 必须同时放置 agconnect-services.json，否则构建报错；
        // 暂不配置 AGC 时，将本行与 app 模块的 apply 行一并移除/注释。
        // 已停用：agcp → agconnect-apms-plugin 以 runtime 依赖引入 AGP 4.0.1，
        // 污染构建脚本类路径，导致 AGP 9 下 KTS 脚本解析到旧 DSL 类而报 Unresolved reference.

    }
}

allprojects {
    repositories {
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/central") }
        // 华为仓：HMS SDK（scanplus 等）依赖解析。前置于 google()/mavenCentral()，
        // 且仅服务 com.huawei.* 组——HMS 构件直连此仓命中，避免途经
        // dl.google.com 时的 TLS 失败干扰解析并浪费时间在重试上。
        maven {
            url = uri("https://developer.huawei.com/repo/")
            content {
                includeGroupByRegex("com\\.huawei\\..*")
            }
        }
        google()
        mavenCentral()
    }
}

rootProject.layout.buildDirectory = file("../build")
subprojects {
    project.layout.buildDirectory = file("${rootProject.layout.buildDirectory.get()}/${project.name}")
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}