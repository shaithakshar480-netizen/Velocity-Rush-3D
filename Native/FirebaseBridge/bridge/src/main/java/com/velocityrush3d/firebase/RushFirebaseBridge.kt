package com.velocityrush3d.firebase

import android.app.Activity
import android.app.Application
import android.os.Bundle
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import android.util.Base64
import android.util.Log
import androidx.credentials.ClearCredentialStateRequest
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.NoCredentialException
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import java.io.File
import java.io.FileOutputStream
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import org.json.JSONObject

/** Credential transport only. Firebase REST remains the authentication authority. */
class RushFirebaseBridge(godot: Godot) : GodotPlugin(godot) {
    companion object {
        private const val AUTH_DIAGNOSTICS = true // TEMPORARY; disable after diagnosis.
        private const val AUTH_TAG = "VelocityRushAuth"
    }
    private fun diagnostic(stage: String) {
        if (AUTH_DIAGNOSTICS) Log.i(AUTH_TAG, stage)
    }
    @UsedByGodot
    fun logAuthStage(stage: String) {
        // GDScript passes only constructed stages. Reject payload-shaped input.
        val allowedPrefix = listOf("GODOT_GOOGLE_", "FIREBASE_IDP_", "AUTH_", "CLOUD_RECONCILIATION_")
        if (allowedPrefix.none { stage.startsWith(it) } || stage.length > 240
            || !stage.matches(Regex("[A-Za-z0-9_: .-]+"))) return
        diagnostic(stage)
    }
    private fun safeMessage(error: Exception): String {
        // Derive fixed hints; never output SDK message text, credentials or stack traces.
        val message = error.message.orEmpty().lowercase()
        val status = Regex("^\\s*([0-9]{1,5})\\s*:").find(message)?.groupValues?.get(1)
        val prefix = if (status in setOf("0", "4", "7", "8", "10", "13", "15", "16", "17", "12500", "12501", "12502", "28444"))
            "Provider status $status - " else ""
        return prefix + when {
            message == "unexpected credential type" -> "Unexpected credential type"
            message == "invalid credential" -> "Invalid token format"
            message == "empty id token" -> "Empty ID token"
            message == "nonce mismatch" -> "Nonce mismatch"
            message == "audience mismatch" -> "Audience mismatch"
            "developer" in message || "28444" in message || "configuration" in message -> "Developer or provider configuration error"
            "network" in message -> "Network unavailable"
            "cancel" in message -> "Request cancelled"
            "no credential" in message -> "No eligible credential"
            "unsupported" in message -> "Credential operation unsupported"
            else -> "SDK details omitted"
        }
    }
    private fun exceptionStage(stage: String, error: Exception) {
        val type = error.javaClass.simpleName.replace(Regex("[^A-Za-z0-9_$]"), "").take(96)
        diagnostic("$stage:$type:${safeMessage(error)}")
    }
    private fun failure(requestId: Int, reason: String) {
        diagnostic("CALLBACK_TO_GODOT_FAILURE:$reason")
        emitSignal("google_result", requestId, false, "", reason)
    }
    init {
        // Runs during plugin construction, even when no method reaches GDScript.
        diagnostic("BRIDGE_BINARY_REVISION:exposure-audit-1")
        val exposed = setOf("configure", "requestGoogleToken", "cancelPicker", "secureLoad",
            "secureSave", "secureClear", "clearGoogleSession")
        for (name in exposed) {
            val methods = javaClass.declaredMethods.filter { it.name == name }
            val visible = methods.size == 1 && java.lang.reflect.Modifier.isPublic(methods[0].modifiers)
            val annotated = visible && methods[0].isAnnotationPresent(UsedByGodot::class.java)
            diagnostic("BRIDGE_JVM_METHOD:$name:public=$visible:annotated=$annotated")
        }
    }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var picker: Job? = null
    private var ticket = 0
    private var webClientId = ""
    private var boundProject = ""
    private var lifecycleRegistered = false
    private val storageLock = Any()
    private val alias = "velocityrush.firebase.refresh.v1"
    private val lifecycle = object : Application.ActivityLifecycleCallbacks {
        override fun onActivityDestroyed(destroyed: Activity) {
            if (destroyed === activity) {
                cancelPicker()
                scope.cancel()
                destroyed.application.unregisterActivityLifecycleCallbacks(this)
            }
        }
        override fun onActivityCreated(a: Activity, state: Bundle?) = Unit
        override fun onActivityStarted(a: Activity) = Unit
        override fun onActivityResumed(a: Activity) = Unit
        override fun onActivityPaused(a: Activity) = Unit
        override fun onActivityStopped(a: Activity) = Unit
        override fun onActivitySaveInstanceState(a: Activity, state: Bundle) = Unit
    }
    override fun getPluginName() = "RushFirebaseBridge"
    override fun getPluginSignals(): Set<SignalInfo> = setOf(
        SignalInfo("google_result", Int::class.javaObjectType, Boolean::class.javaObjectType,
            String::class.java, String::class.java)
    )
    @UsedByGodot
    fun getBridgeCapabilities(): String =
        "rushfirebase:v1:configure,requestGoogleToken,cancelPicker,secureLoad,secureSave,secureClear,clearGoogleSession,google_result"

    @UsedByGodot
    fun configure(serverClientId: String, projectId: String): Boolean {
        val current = activity
        diagnostic("BRIDGE_CONFIGURE_ACTIVITY_AVAILABLE:${current != null}")
        if (current == null) return false
        val packageMatch = current.packageName == "com.velocityrush3d.game"
        val projectMatch = projectId == "velocity-rush-3d"
        val clientPresent = serverClientId.isNotEmpty()
        val clientSuffixValid = serverClientId.endsWith(".apps.googleusercontent.com")
        diagnostic("BRIDGE_CONFIGURE_PACKAGE_MATCH:$packageMatch")
        diagnostic("BRIDGE_CONFIGURE_PROJECT_MATCH:$projectMatch")
        diagnostic("BRIDGE_CONFIGURE_CLIENT_ID_PRESENT:$clientPresent")
        diagnostic("BRIDGE_CONFIGURE_CLIENT_ID_SUFFIX_VALID:$clientSuffixValid")
        if (!packageMatch || !projectMatch || !clientSuffixValid) return false
        // Same idempotent binding validation; never swap an existing identity.
        val alreadyBound = webClientId.isNotEmpty()
        diagnostic("BRIDGE_CONFIGURE_ALREADY_BOUND:$alreadyBound")
        if (alreadyBound) {
            val bindingMatch = webClientId == serverClientId && boundProject == projectId
            diagnostic("BRIDGE_CONFIGURE_EXISTING_BINDING_MATCH:$bindingMatch")
            if (bindingMatch) diagnostic("BRIDGE_CONFIGURE_ACCEPTED")
            return bindingMatch
        }
        webClientId = serverClientId
        boundProject = projectId
        if (!lifecycleRegistered) {
            current.application.registerActivityLifecycleCallbacks(lifecycle)
            lifecycleRegistered = true
        }
        diagnostic("BRIDGE_CONFIGURE_ACCEPTED")
        return true
    }
    @UsedByGodot
    fun requestGoogleToken(requestId: Int) {
        diagnostic("GOOGLE_SIGNIN_REQUEST_RECEIVED")
        val current = activity
        if (current == null || webClientId.isEmpty()) {
            failure(requestId, "UNAVAILABLE")
            return
        }
        current.runOnUiThread {
            if (picker?.isActive == true) {
                failure(requestId, "BUSY")
                return@runOnUiThread
            }
            ticket = requestId
            picker = scope.launch {
                try {
                    val nonceBytes = ByteArray(32).also { SecureRandom().nextBytes(it) }
                    val nonce = Base64.encodeToString(nonceBytes, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
                    val credential = try {
                        val option = GetSignInWithGoogleOption.Builder(webClientId).setNonce(nonce).build()
                        val request = GetCredentialRequest.Builder().addCredentialOption(option).build()
                        diagnostic("CREDENTIAL_MANAGER_REQUEST_START")
                        val result = CredentialManager.create(current).getCredential(current, request)
                        diagnostic("CREDENTIAL_MANAGER_SUCCESS")
                        result.credential
                    } catch (error: NoCredentialException) {
                        diagnostic("CREDENTIAL_MANAGER_NO_CREDENTIAL")
                        exceptionStage("CREDENTIAL_MANAGER_EXCEPTION", error)
                        if (ticket == requestId) failure(requestId, "NO_CREDENTIAL")
                        return@launch
                    } catch (_: GetCredentialCancellationException) {
                        diagnostic("CREDENTIAL_MANAGER_CANCELLED")
                        if (ticket == requestId) failure(requestId, "CANCELLED")
                        return@launch
                    } catch (_: CancellationException) {
                        diagnostic("CREDENTIAL_MANAGER_CANCELLED")
                        return@launch
                    } catch (error: Exception) {
                        exceptionStage("CREDENTIAL_MANAGER_EXCEPTION", error)
                        if (ticket == requestId) failure(requestId, "FAILED")
                        return@launch
                    }
                    try {
                        if (credential !is CustomCredential || credential.type != GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL)
                            throw IllegalArgumentException("Unexpected credential type")
                        val parsed = GoogleIdTokenCredential.createFrom(credential.data)
                        diagnostic("GOOGLE_ID_CREDENTIAL_PARSED")
                        val token = parsed.idToken
                        if (token.isEmpty()) throw IllegalArgumentException("Empty ID token")
                        diagnostic("ID_TOKEN_RECEIVED")
                        // Exact nonce/audience correlation retained; Firebase verifies signature.
                        val parts = token.split('.')
                        if (parts.size != 3) throw IllegalArgumentException("Invalid credential")
                        val claims = JSONObject(String(Base64.decode(parts[1], Base64.URL_SAFE), Charsets.UTF_8))
                        if (claims.optString("nonce") != nonce) throw IllegalArgumentException("Nonce mismatch")
                        if (claims.optString("aud") != webClientId) throw IllegalArgumentException("Audience mismatch")
                        if (ticket == requestId) {
                            diagnostic("CALLBACK_TO_GODOT_SUCCESS")
                            emitSignal("google_result", requestId, true, token, "")
                        }
                    } catch (error: Exception) {
                        exceptionStage("GOOGLE_ID_CREDENTIAL_PARSE_FAILED", error)
                        if (ticket == requestId) failure(requestId, "FAILED")
                    }
                } finally {
                    if (ticket == requestId) ticket = 0
                }
            }
        }
    }
    @UsedByGodot
    fun cancelPicker() {
        activity?.runOnUiThread {
            ticket = 0
            picker?.cancel()
            picker = null
        }
    }
    @UsedByGodot
    fun clearGoogleSession() {
        cancelPicker()
        val current = activity ?: return
        scope.launch {
            try { CredentialManager.create(current).clearCredentialState(ClearCredentialStateRequest()) }
            catch (_: Exception) { /* No tokens or SDK exception text are logged. */ }
        }
    }
    private fun key(create: Boolean): SecretKey? {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (store.containsAlias(alias)) return store.getKey(alias, null) as? SecretKey
        if (!create) return null
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256).setRandomizedEncryptionRequired(true).build())
        return generator.generateKey()
    }
    @UsedByGodot
    fun secureSave(value: String): Boolean = synchronized(storageLock) {
        val current = activity ?: return@synchronized false
        if (boundProject.isEmpty() || value.isEmpty() || value.length > 16384) return@synchronized false
        val file = AtomicFile(File(current.noBackupFilesDir, "firebase-refresh.enc"))
        var output: FileOutputStream? = null
        try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, key(true))
            cipher.updateAAD(boundProject.toByteArray(Charsets.UTF_8))
            val plain = value.toByteArray(Charsets.UTF_8)
            val encrypted = try { cipher.doFinal(plain) } finally { plain.fill(0) }
            output = file.startWrite()
            output.write(cipher.iv.size)
            output.write(cipher.iv)
            output.write(encrypted)
            file.finishWrite(output)
            output = null
            current.getSharedPreferences("firebase-session", 0).edit().putBoolean("revoked", false).commit()
        } catch (_: Exception) {
            if (output != null) file.failWrite(output)
            false
        }
    }
    @UsedByGodot
    fun secureLoad(): String = synchronized(storageLock) {
        val current = activity ?: return@synchronized ""
        if (boundProject.isEmpty() || current.getSharedPreferences("firebase-session", 0).getBoolean("revoked", false))
            return@synchronized ""
        try {
            val bytes = AtomicFile(File(current.noBackupFilesDir, "firebase-refresh.enc")).readFully()
            if (bytes.size !in 30..20000 || bytes[0].toInt() != 12) return@synchronized ""
            val secret = key(false) ?: return@synchronized ""
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, secret, GCMParameterSpec(128, bytes.copyOfRange(1, 13)))
            cipher.updateAAD(boundProject.toByteArray(Charsets.UTF_8))
            val plain = cipher.doFinal(bytes, 13, bytes.size - 13)
            try { String(plain, Charsets.UTF_8) } finally { plain.fill(0) }
        } catch (_: Exception) { "" }
    }
    @UsedByGodot
    fun secureClear(): Boolean = synchronized(storageLock) {
        val current = activity ?: return@synchronized false
        val marked = current.getSharedPreferences("firebase-session", 0).edit().putBoolean("revoked", true).commit()
        try {
            AtomicFile(File(current.noBackupFilesDir, "firebase-refresh.enc")).delete()
            val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            store.deleteEntry(alias)
            marked
        } catch (_: Exception) { false }
    }
}
