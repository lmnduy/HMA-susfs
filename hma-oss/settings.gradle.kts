import kotlin.io.path.Path

enableFeaturePreview("TYPESAFE_PROJECT_ACCESSORS")

pluginManagement {
    repositories {
        // NOTE: mirrors are put first because dl.google.com is not reachable in this environment
        maven("https://maven.aliyun.com/repository/google")
        maven("https://maven.aliyun.com/repository/public")
        maven("https://mirrors.cloud.tencent.com/nexus/repository/maven-public")
        gradlePluginPortal()
        google()
        mavenCentral()
        mavenLocal()
        maven("https://jitpack.io")
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        // NOTE: mirrors are put first because dl.google.com is not reachable in this environment
        maven("https://maven.aliyun.com/repository/google")
        maven("https://maven.aliyun.com/repository/public")
        maven("https://mirrors.cloud.tencent.com/nexus/repository/maven-public")
        google()
        mavenCentral()
        mavenLocal()
        maven("https://jitpack.io")
    }

    versionCatalogs {
        create("androidvmtools") {
            from(files(
                Path(rootDir.path, "external", "AndroidVMTools", "gradle", "libs.versions.toml")))
        }
    }
}

rootProject.name = "HMA-OSS"

include(
    ":app",
    ":common",
    ":stub",
    ":zygote",
)
