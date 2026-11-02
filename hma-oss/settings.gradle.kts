import kotlin.io.path.Path

enableFeaturePreview("TYPESAFE_PROJECT_ACCESSORS")

pluginManagement {
    repositories {
        // Official repositories first: the Aliyun/Tencent mirrors regularly
        // answer 502, and a single 502 makes Gradle disable that repository
        // for the rest of the build (see the HMA CI failures).
        google()
        mavenCentral()
        gradlePluginPortal()
        maven("https://jitpack.io")
        // Fallbacks for networks that cannot reach the official hosts.
        maven("https://maven.aliyun.com/repository/google")
        maven("https://maven.aliyun.com/repository/public")
        maven("https://mirrors.cloud.tencent.com/nexus/repository/maven-public")
        mavenLocal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        // Official repositories first: the Aliyun/Tencent mirrors regularly
        // answer 502, and a single 502 makes Gradle disable that repository
        // for the rest of the build (see the HMA CI failures).
        google()
        mavenCentral()
        maven("https://jitpack.io")
        // Fallbacks for networks that cannot reach the official hosts.
        maven("https://maven.aliyun.com/repository/google")
        maven("https://maven.aliyun.com/repository/public")
        maven("https://mirrors.cloud.tencent.com/nexus/repository/maven-public")
        mavenLocal()
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
