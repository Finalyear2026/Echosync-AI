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
    
    val configureCmake: (Project) -> Unit = { p ->
        try {
            val android = p.extensions.findByName("android")
            if (android != null) {
                val getExternalNativeBuild = android.javaClass.getMethod("getExternalNativeBuild")
                val externalNativeBuild = getExternalNativeBuild.invoke(android)
                val getCmake = externalNativeBuild.javaClass.getMethod("getCmake")
                val cmake = getCmake.invoke(externalNativeBuild)
                val setVersion = cmake.javaClass.getMethod("setVersion", String::class.java)
                setVersion.invoke(cmake, "3.22.1")
            }
        } catch (e: Exception) {
            // ignore
        }
    }

    if (project.state.executed) {
        configureCmake(project)
    } else {
        project.afterEvaluate {
            configureCmake(this)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
