allprojects {
    repositories {
        google()
        mavenCentral()
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

// flutter_js 0.8.7 still declares a Kotlin 1.8 JVM target. Keep all plugin
// Kotlin tasks aligned with the Java target used by the Android toolchain.
subprojects {
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(
                if (project.name == "flutter_js") {
                    org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11
                } else {
                    org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
                }
            )
        }
    }
    tasks.withType<org.gradle.api.tasks.compile.JavaCompile>().configureEach {
        sourceCompatibility = if (project.name == "flutter_js") "11" else "17"
        targetCompatibility = if (project.name == "flutter_js") "11" else "17"
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
