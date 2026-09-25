package com.retailx.store_manager.data

import android.content.Context
import android.os.Build
import android.util.Log
import com.retailx.store_manager.data.api.NotificationApiClient
import com.retailx.store_manager.data.api.RegisterDeviceTokenRequest
import com.retailx.store_manager.data.api.UnregisterDeviceTokenRequest
import com.google.firebase.messaging.FirebaseMessaging
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * Keeps the backend's `user_devices` row for this device in sync with FCM.
 * Flutter owns the session (server address, access token) and pushes it down
 * through the `com.retailx.store_manager/push` MethodChannel; this object just
 * reacts to whichever of {session, FCM token} changed most recently and
 * (re)registers when both are known.
 */
object DeviceTokenSync {
    private const val TAG = "DeviceTokenSync"

    fun onFcmTokenReceived(context: Context, token: String) {
        SessionPrefs.saveFcmToken(context, token)
        registerIfPossible(context)
    }

    /** Call once a signed-in session becomes available: after login, and on a cold start that restores one. */
    fun onSessionStarted(context: Context, baseUrl: String, accessToken: String, deviceId: String) {
        SessionPrefs.saveSession(context, baseUrl, accessToken, deviceId)
        // A different user may have signed in on this device with the FCM token
        // unchanged — force a re-register rather than trusting the old "already sent" mark.
        SessionPrefs.markRegistered(context, "")

        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
            // task.result throws if the task failed — isSuccessful must be checked first.
            if (!task.isSuccessful) {
                Log.w(TAG, "Could not fetch FCM token", task.exception)
                return@addOnCompleteListener
            }
            val token = task.result
            if (!token.isNullOrEmpty()) {
                SessionPrefs.saveFcmToken(context, token)
                registerIfPossible(context)
            }
        }
    }

    /** Unregisters with the credentials still on hand, then drops the cached session. */
    fun onSessionEnded(context: Context) {
        val baseUrl = SessionPrefs.baseUrl(context)
        val accessToken = SessionPrefs.accessToken(context)
        val fcmToken = SessionPrefs.fcmToken(context)

        CoroutineScope(Dispatchers.IO).launch {
            if (!baseUrl.isNullOrEmpty() && !accessToken.isNullOrEmpty() && !fcmToken.isNullOrEmpty()) {
                try {
                    NotificationApiClient.create(baseUrl, accessToken)
                        .unregisterDeviceToken(UnregisterDeviceTokenRequest(fcmToken))
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to unregister device token", e)
                }
            }
            SessionPrefs.clearSession(context)
        }
    }

    private fun registerIfPossible(context: Context) {
        val baseUrl = SessionPrefs.baseUrl(context) ?: return
        val accessToken = SessionPrefs.accessToken(context) ?: return
        val deviceId = SessionPrefs.deviceId(context) ?: return
        val fcmToken = SessionPrefs.fcmToken(context) ?: return
        if (SessionPrefs.registeredToken(context) == fcmToken) return

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val deviceModel = "${Build.MANUFACTURER} ${Build.MODEL}"
                val response = NotificationApiClient.create(baseUrl, accessToken).registerDeviceToken(
                    RegisterDeviceTokenRequest(
                        deviceId = deviceId,
                        fcmToken = fcmToken,
                        deviceModel = deviceModel
                    )
                )
                if (response.isSuccessful) {
                    SessionPrefs.markRegistered(context, fcmToken)
                } else {
                    Log.w(TAG, "Device token registration failed: HTTP ${response.code()}")
                }
            } catch (e: Exception) {
                Log.w(TAG, "Device token registration failed", e)
            }
        }
    }
}
