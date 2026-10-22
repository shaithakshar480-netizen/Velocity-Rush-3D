import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.zip.ZipFile
import java.util.zip.ZipInputStream
import java.security.MessageDigest

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}
android {
    namespace = "com.velocityrush3d.firebase"
    compileSdk = providers.gradleProperty("bridgeCompileSdk").orElse("34").get().toInt()
    defaultConfig {
        minSdk = 23 // Android Keystore AES/GCM; no app target/applicationId override.
        consumerProguardFiles("consumer-rules.pro")
    }
    buildTypes { getByName("release") { isMinifyEnabled = false } }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}
val godotAar = providers.gradleProperty("godotAar").orNull
    ?: throw GradleException("Pass -PgodotAar=/absolute/path/to/the/matching/Godot-4.7.2.aar")
check(file(godotAar).isFile) { "Matching Godot Android library not found" }
dependencies {
    compileOnly(files(godotAar)) // Use the supplied engine, not an invented Maven release.
    implementation("androidx.credentials:credentials:1.3.0")
    implementation("androidx.credentials:credentials-play-services-auth:1.3.0")
    implementation("com.google.android.libraries.identity.googleid:googleid:1.1.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}

val releaseAar = layout.buildDirectory.file("outputs/aar/bridge-release.aar")
val bridgeClass = "com/velocityrush3d/firebase/RushFirebaseBridge.class"
fun containsBridge(aar: File): Boolean = ZipFile(aar).use { zip ->
    if (zip.getEntry(bridgeClass) != null) return@use true
    val jars = zip.entries().asSequence().filter { it.name.endsWith(".jar") }.toList()
    jars.any { entry ->
        ZipInputStream(zip.getInputStream(entry)).use { jar ->
            var found = false
            var item = jar.nextEntry
            while (item != null) {
                if (item.name == bridgeClass) found = true
                item = jar.nextEntry
            }
            found
        }
    }
}
fun sha256(file: File): String = MessageDigest.getInstance("SHA-256")
    .digest(file.readBytes()).joinToString("") { "%02x".format(it.toInt() and 255) }
val verifyBridge = tasks.register("verifyBridge") {
    dependsOn("assembleRelease")
    // Inspect actual output on every installation, including incremental builds.
    doLast {
        val aar = releaseAar.get().asFile
        check(aar.isFile && containsBridge(aar)) { "Current release AAR lacks RushFirebaseBridge" }
        val inspection = layout.buildDirectory.dir("bridge-inspection").get().asFile
        inspection.mkdirs()
        val classes = File(inspection, "classes.jar")
        ZipFile(aar).use { zip ->
            val entry = zip.getEntry("classes.jar") ?: error("Missing classes.jar")
            zip.getInputStream(entry).use { input -> classes.outputStream().use { input.copyTo(it) } }
        }
        val suffix = if (System.getProperty("os.name").startsWith("Windows")) ".exe" else ""
        val javap = File(System.getProperty("java.home"), "bin/javap$suffix")
        check(javap.isFile) { "Run Gradle with a full JDK 17 (javap required)" }
        val process = ProcessBuilder(javap.absolutePath, "-v", "-p", "-classpath",
            classes.absolutePath, "com.velocityrush3d.firebase.RushFirebaseBridge")
            .redirectErrorStream(true).start()
        val dump = process.inputStream.bufferedReader().use { it.readText() }
        check(process.waitFor() == 0) { "javap failed; inspect bridge-inspection" }
        File(inspection, "RushFirebaseBridge.javap.txt").writeText(dump)
        // Inspect the exact user-supplied engine AAR, not a guessed Maven version.
        val engineClasses = File(inspection, "godot-classes.jar")
        ZipFile(file(godotAar)).use { zip ->
            val entry = zip.getEntry("classes.jar") ?: error("Godot AAR missing classes.jar")
            zip.getInputStream(entry).use { input -> engineClasses.outputStream().use { input.copyTo(it) } }
        }
        for (type in listOf("GodotPlugin", "UsedByGodot")) {
            val inspectEngine = ProcessBuilder(javap.absolutePath, "-v", "-p", "-classpath",
                engineClasses.absolutePath, "org.godotengine.godot.plugin.$type")
                .redirectErrorStream(true).start()
            val engineDump = inspectEngine.inputStream.bufferedReader().use { it.readText() }
            check(inspectEngine.waitFor() == 0) { "Engine plugin API absent: $type" }
            File(inspection, "$type.javap.txt").writeText(engineDump)
            if (type == "UsedByGodot") check(engineDump.contains("RUNTIME")) {
                "Engine UsedByGodot annotation is not runtime-retained"
            }
            if (type == "GodotPlugin") check(engineDump.contains("UsedByGodot")) {
                "Engine plugin does not reference UsedByGodot; inspect engine API report"
            }
        }
        val required = mapOf(
            "getBridgeCapabilities" to "()Ljava/lang/String;",
            "configure" to "(Ljava/lang/String;Ljava/lang/String;)Z",
            "requestGoogleToken" to "(I)V", "cancelPicker" to "()V",
            "secureLoad" to "()Ljava/lang/String;", "secureSave" to "(Ljava/lang/String;)Z",
            "secureClear" to "()Z", "clearGoogleSession" to "()V")
        val blocks = dump.split(Regex("(?m)(?=^  (?:public|private|protected) )"))
        for ((name, descriptor) in required) {
            val block = blocks.singleOrNull { Regex("^  public [^\n]*\\b" + name + "\\(").containsMatchIn(it) }
                ?: error("Public method missing/duplicated: $name")
            check(block.contains("descriptor: $descriptor")) { "Wrong JVM signature: $name" }
            val runtimeAnnotations = block.substringAfter("RuntimeVisibleAnnotations:", "")
                .substringBefore("RuntimeInvisibleAnnotations:")
            check(runtimeAnnotations.contains("org.godotengine.godot.plugin.UsedByGodot")) {
                "Missing runtime @UsedByGodot: $name"
            }
        }
        check(dump.contains("org.godotengine.godot.plugin.GodotPlugin")) { "Wrong superclass" }
        logger.lifecycle("BRIDGE_BYTECODE_VERIFIED: eight annotated public methods; SHA256=${sha256(aar)}")
    }
}
tasks.register("installBridge") {
    dependsOn(verifyBridge)
    doLast {
        val gameRoot = rootProject.file("../..").canonicalFile
        val target = File(gameRoot, "addons/rush_firebase/bin/RushFirebaseBridge.aar")
        // Fail rather than silently choosing between multiple plugin bytecodes.
        for (root in listOf(File(gameRoot, "addons"), File(gameRoot, "android/build/libs"))) {
            if (!root.exists()) continue
            for (candidate in root.walkTopDown().filter { it.isFile && it.extension.lowercase() in setOf("aar", "jar") }) {
                if (candidate.canonicalFile != target.canonicalFile && containsBridge(candidate)) {
                    error("Duplicate RushFirebaseBridge class in: ${candidate.absolutePath}")
                }
            }
        }
        val source = releaseAar.get().asFile
        check(source.isFile) { "New release AAR missing; install aborted" }
        target.parentFile.mkdirs()
        val staging = File(target.parentFile, "RushFirebaseBridge.aar.pending")
        source.copyTo(staging, overwrite = true)
        check(sha256(source) == sha256(staging)) { "Bridge copy verification failed" }
        Files.move(
            staging.toPath(),
            target.toPath(),
            StandardCopyOption.REPLACE_EXISTING
        )
        check(sha256(source) == sha256(target)) { "Installed bridge hash mismatch" }
        logger.lifecycle("BRIDGE_INSTALLED: ${target.absolutePath}; SHA256=${sha256(target)}")
    }
}
