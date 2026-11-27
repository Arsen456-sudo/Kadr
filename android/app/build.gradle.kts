plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}
android {
    namespace = "app.kadr.android"
    compileSdk { version = release(37) { minorApiLevel = 2 } }
    defaultConfig {
        applicationId = "app.kadr.android"
        minSdk = 26
        targetSdk = 37
        versionCode = 7
        versionName = "0.1.6"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    buildFeatures { compose = true }
    // AGP 9.2.1 UAST hangs in KotlinUFile.getAllCommentsInFile during this detector.
    // Keep the remaining lint checks; checkSourceText below rejects bidi controls directly.
    lint { disable += "BidiSpoofing" }
    val developmentKey = rootProject.file(".signing/debug.keystore")
    if (developmentKey.exists()) signingConfigs.getByName("debug") {
        storeFile = developmentKey; storePassword = "android"; keyAlias = "androiddebugkey"; keyPassword = "android"
    }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    buildTypes { release { isMinifyEnabled = false } }
    sourceSets["main"].assets.srcDir("../../ios/Media")
}
val checkSourceText by tasks.registering {
    val sources = fileTree("src") { include("**/*.kt", "**/*.xml", "**/*.json") }
    inputs.files(sources)
    doLast {
        sources.forEach { file ->
            check(file.readText(Charsets.UTF_8).none { it in '\u202A'..'\u202E' || it in '\u2066'..'\u2069' || it == '\u061C' || it == '\u200E' || it == '\u200F' }) {
                "Unexpected Unicode bidi control in ${file.relativeTo(projectDir)}"
            }
        }
    }
}
tasks.named("preBuild") { dependsOn(checkSourceText) }
dependencies {
    implementation("androidx.activity:activity-compose:1.12.3")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.10.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.10.0")
    implementation("androidx.compose.ui:ui:1.10.6")
    implementation("androidx.compose.foundation:foundation:1.10.6")
    implementation("androidx.compose.animation:animation:1.10.6")
    implementation("androidx.compose.material3:material3:1.6.0-alpha01")
    implementation("androidx.compose.material:material-icons-extended:1.7.8")
    implementation("androidx.media3:media3-exoplayer:1.11.1")
    implementation("androidx.media3:media3-ui:1.11.1")
    implementation("androidx.media3:media3-exoplayer-hls:1.11.1")
    implementation("io.coil-kt.coil3:coil-compose:3.3.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    implementation("com.google.zxing:core:3.5.3")
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation("androidx.compose.ui:ui-test-junit4:1.10.6")
    debugImplementation("androidx.compose.ui:ui-test-manifest:1.10.6")
}
