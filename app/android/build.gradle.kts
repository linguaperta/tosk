allprojects {
    repositories {
        google()
        mavenCentral()
        // Onyx (Boox) e-reader SDK: pen raw drawing and e-ink refresh (v0.5,
        // only used on ONYX devices). See docs/release.md. The repository also
        // mirrors mmkv 1.0.19, an SDK dependency that was only ever on JCenter.
        maven {
            url = uri("https://repo.boox.com/repository/maven-public/")
            content {
                includeGroup("com.onyx.android.sdk")
                includeGroup("com.tencent") // mmkv 1.0.19
            }
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
