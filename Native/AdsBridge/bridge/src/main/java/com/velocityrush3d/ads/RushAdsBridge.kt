package com.velocityrush3d.ads

import android.app.Activity
import android.app.Application
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.ads.mediation.admob.AdMobAdapter
import com.google.android.gms.ads.AdError
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.FullScreenContentCallback
import com.google.android.gms.ads.LoadAdError
import com.google.android.gms.ads.MobileAds
import com.google.android.gms.ads.interstitial.InterstitialAd
import com.google.android.gms.ads.interstitial.InterstitialAdLoadCallback
import com.google.android.gms.ads.rewarded.RewardedAd
import com.google.android.gms.ads.rewarded.RewardedAdLoadCallback
import com.google.android.ump.ConsentInformation
import com.google.android.ump.ConsentRequestParameters
import com.google.android.ump.UserMessagingPlatform
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

/** Events only: no reward amounts, account identifiers, currency or Firebase dependencies. */
class RushAdsBridge(godot: Godot) : GodotPlugin(godot) {
    private val main = Handler(Looper.getMainLooper())
    private var host: Activity? = null
    private var initialized = false
    private var initializing = false
    private var sdkStarted = false
    private var destroyed = false
    private var foreground = true
    private var mode = ""
    private var rewardedId = ""
    private var interstitialId = ""
    private var rewarded: RewardedAd? = null
    private var interstitial: InterstitialAd? = null
    private var rewardLoading = false
    private var interstitialLoading = false
    private var rewardEpoch = 0
    private var interstitialEpoch = 0
    private var rewardedAt = 0L
    private var interstitialAt = 0L
    private var busy = false
    private var activeTicket = 0
    private var activePlacement = ""
    private var invalid = false
    private var emittedReward = false
    private var lastTicket = 0
    private var privacyBusy = false
    private val allowed = setOf("TURBO_REFILL", "STORE_turbo", "STORE_repair", "STORE_magnet", "STORE_shield",
        "POWERUP_turbo", "POWERUP_repair", "POWERUP_magnet", "POWERUP_shield", "POWERUP_double", "POWERUP_revive", "POWERUP_trial", "GARAGE_UPGRADE")
    private fun now() = android.os.SystemClock.elapsedRealtime()
    private fun event(ticket: Int = 0, placement: String = "", state: String) {
        if (!destroyed) emitSignal("ad_event", ticket, placement, state)
    }
    override fun getPluginName() = "RushAdsBridge"
    override fun getPluginSignals(): Set<SignalInfo> = setOf(
        SignalInfo("ad_event", Int::class.javaObjectType, String::class.java, String::class.java))
    @UsedByGodot
    fun getBridgeCapabilities(): String = "rushads:v1:initialize,preload,showAd,invalidate,showPrivacyOptions,ad_event"

    @UsedByGodot
    fun initialize(requestedMode: String, appId: String, rewardUnit: String, interstitialUnit: String) {
        main.post {
            if (destroyed) { event(state = "UNAVAILABLE"); return@post }
            if (initialized) { event(state = if (consentAllows()) "READY" else "UNAVAILABLE"); return@post }
            if (initializing) return@post
            val current = activity ?: run { event(state = "UNAVAILABLE"); return@post }
            val validIds = Regex("ca-app-pub-[0-9]{16}~[0-9]{10}").matches(appId) &&
                Regex("ca-app-pub-[0-9]{16}/[0-9]{10}").matches(rewardUnit) &&
                Regex("ca-app-pub-[0-9]{16}/[0-9]{10}").matches(interstitialUnit)
            val test = requestedMode == "TEST" && appId == "ca-app-pub-3940256099942544~3347511713" &&
                rewardUnit == "ca-app-pub-3940256099942544/5224354917" && interstitialUnit == "ca-app-pub-3940256099942544/1033173712"
            val production = requestedMode == "PRODUCTION" && listOf(appId, rewardUnit, interstitialUnit).none { it.contains("3940256099942544") }
            val metadata = current.packageManager.getApplicationInfo(current.packageName, android.content.pm.PackageManager.GET_META_DATA).metaData
            val packagedId = metadata?.getString("com.google.android.gms.ads.APPLICATION_ID") ?: ""
            if (!validIds || (!test && !production) || packagedId != appId) {
                Log.i("VelocityRushAds", "CONFIG_REJECTED")
                event(state = "UNAVAILABLE")
                return@post
            }
            mode = requestedMode
            rewardedId = rewardUnit
            interstitialId = interstitialUnit
            if (host == null) current.application.registerActivityLifecycleCallbacks(lifecycle)
            host = current
            initializing = true
            Log.i("VelocityRushAds", "MODE_$requestedMode")
            if (test) {
                // Official demo units ONLY. This is not a production consent grant.
                startSdk(current)
            } else {
                privacyBusy = true
                event(state = "PRIVACY_OPENED")
                val consent = UserMessagingPlatform.getConsentInformation(current)
                consent.requestConsentInfoUpdate(current, ConsentRequestParameters.Builder().build(), {
                    UserMessagingPlatform.loadAndShowConsentFormIfRequired(current) {
                        privacyBusy = false
                        event(state = "PRIVACY_CLOSED")
                        publishPrivacy()
                        if (consent.canRequestAds()) startSdk(current) else failInitialization()
                    }
                }, {
                    privacyBusy = false
                    event(state = "PRIVACY_CLOSED")
                    publishPrivacy()
                    if (consent.canRequestAds()) startSdk(current) else failInitialization()
                })
            }
        }
    }
    private fun failInitialization() {
        initializing = false
        event(state = "UNAVAILABLE")
    }
    private fun startSdk(current: Activity) {
        if (destroyed || initialized || sdkStarted) return
        sdkStarted = true
        MobileAds.initialize(current) {
            main.post {
                if (!destroyed) {
                    initialized = true
                    initializing = false
                    event(state = "READY")
                }
            }
        }
    }
    private fun consentAllows(): Boolean {
        val current = host ?: return false
        return mode == "TEST" || UserMessagingPlatform.getConsentInformation(current).canRequestAds()
    }
    private fun request(): AdRequest {
        // Conservative NPA request. UMP eligibility is ALSO required in production.
        // Future mediation privacy configuration belongs in the SDK/provider, never gameplay.
        val extras = Bundle().apply { putString("npa", "1") }
        return AdRequest.Builder().addNetworkExtrasBundle(AdMobAdapter::class.java, extras).build()
    }
    @UsedByGodot
    fun preload() {
        main.post {
            val current = host ?: return@post
            if (!initialized || destroyed || !foreground || busy || privacyBusy || !consentAllows()) return@post
            if (rewarded != null && now() - rewardedAt > 3000000) rewarded = null
            if (interstitial != null && now() - interstitialAt > 3000000) interstitial = null
            if (rewarded == null && !rewardLoading) {
                rewardLoading = true
                val epoch = ++rewardEpoch
                RewardedAd.load(current, rewardedId, request(), object : RewardedAdLoadCallback() {
                    override fun onAdLoaded(ad: RewardedAd) {
                        if (destroyed || epoch != rewardEpoch) return
                        rewardLoading = false; rewarded = ad; rewardedAt = now()
                        event(state = "REWARDED_READY")
                    }
                    override fun onAdFailedToLoad(error: LoadAdError) {
                        if (destroyed || epoch != rewardEpoch) return
                        rewardLoading = false; rewarded = null
                        event(state = "REWARDED_UNAVAILABLE")
                    }
                })
                main.postDelayed({ if (rewardLoading && epoch == rewardEpoch) { rewardEpoch++; rewardLoading = false; event(state = "REWARDED_UNAVAILABLE") } }, 30000)
            }
            if (interstitial == null && !interstitialLoading) {
                interstitialLoading = true
                val epoch = ++interstitialEpoch
                InterstitialAd.load(current, interstitialId, request(), object : InterstitialAdLoadCallback() {
                    override fun onAdLoaded(ad: InterstitialAd) {
                        if (destroyed || epoch != interstitialEpoch) return
                        interstitialLoading = false; interstitial = ad; interstitialAt = now()
                        event(state = "INTERSTITIAL_READY")
                    }
                    override fun onAdFailedToLoad(error: LoadAdError) {
                        if (destroyed || epoch != interstitialEpoch) return
                        interstitialLoading = false; interstitial = null
                        event(state = "INTERSTITIAL_UNAVAILABLE")
                    }
                })
                main.postDelayed({ if (interstitialLoading && epoch == interstitialEpoch) { interstitialEpoch++; interstitialLoading = false; event(state = "INTERSTITIAL_UNAVAILABLE") } }, 30000)
            }
        }
    }
    @UsedByGodot
    fun showAd(ticket: Int, placement: String, isRewarded: Boolean) {
        main.post {
            val current = host
            val legalPlacement = if (isRewarded) placement in allowed else placement == "RESULTS_INTERSTITIAL"
            if (destroyed || current == null || current.isFinishing || current.isDestroyed || !initialized || !foreground || busy || privacyBusy || !consentAllows() || ticket <= lastTicket || !legalPlacement) {
                event(ticket, placement, "SHOW_FAILED"); return@post
            }
            lastTicket = ticket
            val rewardAd = rewarded
            val fullAd = interstitial
            if ((isRewarded && (rewardAd == null || now() - rewardedAt > 3000000)) || (!isRewarded && (fullAd == null || now() - interstitialAt > 3000000))) {
                if (isRewarded) rewarded = null else interstitial = null
                event(ticket, placement, "SHOW_FAILED"); return@post
            }
            busy = true; activeTicket = ticket; activePlacement = placement; invalid = false; emittedReward = false
            val callback = object : FullScreenContentCallback() {
                override fun onAdShowedFullScreenContent() { event(ticket, placement, "OPENED") }
                override fun onAdDismissedFullScreenContent() { finish(ticket, placement, "CLOSED") }
                override fun onAdFailedToShowFullScreenContent(error: AdError) { finish(ticket, placement, "SHOW_FAILED") }
            }
            try {
                if (isRewarded) {
                    rewarded = null
                    rewardAd!!.fullScreenContentCallback = callback
                    rewardAd.show(current) {
                        // Ignore SDK quantity/type. A current earned callback is the ONLY reward event.
                        if (!destroyed && busy && activeTicket == ticket && !invalid && !emittedReward) {
                            emittedReward = true
                            event(ticket, placement, "EARNED")
                        }
                    }
                } else {
                    interstitial = null
                    fullAd!!.fullScreenContentCallback = callback
                    fullAd.show(current)
                }
            } catch (_: RuntimeException) { finish(ticket, placement, "SHOW_FAILED") }
        }
    }
    private fun finish(ticket: Int, placement: String, state: String) {
        if (!busy || activeTicket != ticket) return
        busy = false; activeTicket = 0; activePlacement = ""; invalid = true
        event(ticket, placement, state)
        // Next preload is explicitly scheduled by game policy on a safe screen.
    }
    @UsedByGodot
    fun invalidate(ticket: Int) {
        main.post { if (busy && activeTicket == ticket) invalid = true }
    }
    private fun publishPrivacy() {
        val current = host ?: return
        val required = UserMessagingPlatform.getConsentInformation(current).privacyOptionsRequirementStatus == ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED
        event(state = if (required) "PRIVACY_REQUIRED" else "PRIVACY_NOT_REQUIRED")
    }
    @UsedByGodot
    fun showPrivacyOptions() {
        main.post {
            val current = host ?: return@post
            if (destroyed || initializing || busy || privacyBusy || !foreground || mode != "PRODUCTION") { event(state = "PRIVACY_CLOSED"); return@post }
            rewarded = null; interstitial = null; rewardEpoch++; interstitialEpoch++
            rewardLoading = false; interstitialLoading = false
            privacyBusy = true
            event(state = "PRIVACY_OPENED")
            UserMessagingPlatform.showPrivacyOptionsForm(current) {
                privacyBusy = false
                publishPrivacy()
                event(state = "PRIVACY_CLOSED")
                if (consentAllows()) {
                    if (!initialized) startSdk(current) else event(state = "READY")
                } else event(state = "UNAVAILABLE")
            }
        }
    }
    private val lifecycle = object : Application.ActivityLifecycleCallbacks {
        override fun onActivityResumed(a: Activity) { if (a === host) foreground = true }
        override fun onActivityPaused(a: Activity) { if (a === host) foreground = false }
        override fun onActivityDestroyed(a: Activity) {
            if (a !== host) return
            if (busy) finish(activeTicket, activePlacement, "SHOW_FAILED")
            event(state = "UNAVAILABLE")
            destroyed = true; rewarded = null; interstitial = null
            rewardEpoch++; interstitialEpoch++; main.removeCallbacksAndMessages(null)
            a.application.unregisterActivityLifecycleCallbacks(this)
            host = null
        }
        override fun onActivityCreated(a: Activity, state: Bundle?) = Unit
        override fun onActivityStarted(a: Activity) = Unit
        override fun onActivityStopped(a: Activity) = Unit
        override fun onActivitySaveInstanceState(a: Activity, state: Bundle) = Unit
    }
}
