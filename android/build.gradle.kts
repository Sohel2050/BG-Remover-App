allprojects {
    repositories {
        google()
        mavenCentral()

        // Extra Maven repositories required by the LevelPlay ad network SDKs.
        maven { url = uri("https://cboost.jfrog.io/artifactory/chartboost-ads/") }
        maven { url = uri("https://dl-maven-android.mintegral.com/repository/mbridge_android_sdk_oversea") }
        maven { url = uri("https://maven.ogury.co") }
        maven { url = uri("https://repo.pubmatic.com/artifactory/public-repos") }
        maven { url = uri("https://s3.amazonaws.com/smaato-sdk-releases/") }
        maven { url = uri("https://verve.jfrog.io/artifactory/verve-gradle-release") }
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
