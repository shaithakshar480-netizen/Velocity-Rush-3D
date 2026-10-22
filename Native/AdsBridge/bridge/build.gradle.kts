import groovy.json.JsonSlurper
import java.security.MessageDigest
plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}
val godotAar = providers.gradleProperty("godotAar").orNull
    ?: throw GradleException("Supply -PgodotAar=<matching Godot Android release AAR>")
val configFile = rootProject.file("../../Data/AdsConfig.json")
val config = JsonSlurper().parse(configFile) as Map<*, *>
val mode = config["mode"] as? String ?: ""
require(mode in listOf("TEST", "PRODUCTION")) { "Invalid AdsConfig mode" }
val ids = config[if (mode == "TEST") "test" else "production"] as? Map<*, *>
    ?: throw GradleException("AdsConfig section missing")
val appId = ids["app_id"] as? String ?: ""
val rewardId = ids["rewarded_id"] as? String ?: ""
val interstitialId = ids["interstitial_id"] as? String ?: ""
require(Regex("ca-app-pub-[0-9]{16}~[0-9]{10}").matches(appId)) { "Ads app ID required" }
require(listOf(rewardId, interstitialId).all { Regex("ca-app-pub-[0-9]{16}/[0-9]{10}").matches(it) }) { "Ads unit IDs required" }
if (mode == "TEST") {
    require(appId == "ca-app-pub-3940256099942544~3347511713" && rewardId == "ca-app-pub-3940256099942544/5224354917" && interstitialId == "ca-app-pub-3940256099942544/1033173712") { "TEST requires official demo IDs" }
} else {
    require(ids["privacy_setup_complete"] == true && listOf(appId, rewardId, interstitialId).none { it.contains("3940256099942544") }) { "Production IDs/privacy configuration required" }
}
android {
    namespace = "com.velocityrush3d.ads"
    compileSdk = providers.gradleProperty("bridgeCompileSdk").orElse("34").get().toInt()
    defaultConfig {
        minSdk = 23
        consumerProguardFiles("consumer-rules.pro")
        resValue("string", "rush_ads_app_id", appId)
    }
    buildTypes { getByName("release") { isMinifyEnabled = false } }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
}
dependencies {
    compileOnly(files(godotAar))
    implementation("com.google.android.gms:play-services-ads:24.1.0")
    implementation("com.google.android.ump:user-messaging-platform:3.1.0")
}
tasks.register<Copy>("installBridge") {
    dependsOn("assembleRelease")
    inputs.file(configFile)
    outputs.file(rootProject.file("../../addons/rush_ads/bin/RushAdsBridge.config.sha256"))
    from(layout.buildDirectory.file("outputs/aar/bridge-release.aar"))
    into(rootProject.file("../../addons/rush_ads/bin"))
    rename { "RushAdsBridge.aar" }
    doLast {
        val digest = MessageDigest.getInstance("SHA-256").digest(configFile.readBytes()).joinToString("") { "%02x".format(it) }
        rootProject.file("../../addons/rush_ads/bin/RushAdsBridge.config.sha256").writeText(digest)
    }
    doFirst {
        val output = layout.buildDirectory.file("outputs/aar/bridge-release.aar").get().asFile
        require(output.isFile && output.length() > 0) { "Missing fresh ads AAR" }
    }
}
