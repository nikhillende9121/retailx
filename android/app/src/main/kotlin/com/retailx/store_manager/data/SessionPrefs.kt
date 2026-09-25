package com.retailx.store_manager.data

import android.content.Context
import androidx.core.content.edit

/**
 * Native-side mirror of just enough of the Flutter session (server address,
 * access token, device id) to authenticate the FCM device-token
 * register/unregister calls. Flutter remains the source of truth — this is
 * populated via the `com.retailx.store_manager/push` MethodChannel and never
 * outlives what Flutter last pushed down.
 */
object SessionPrefs {
    private const val PREFS_NAME = "push_session_prefs"
    private const val KEY_BASE_URL = "base_url"
    private const val KEY_ACCESS_TOKEN = "access_token"
    private const val KEY_DEVICE_ID = "device_id"
    private const val KEY_FCM_TOKEN = "fcm_token"
    private const val KEY_REGISTERED_TOKEN = "registered_fcm_token"

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun saveSession(context: Context, baseUrl: String, accessToken: String, deviceId: String) {
        prefs(context).edit {
            putString(KEY_BASE_URL, baseUrl)
            putString(KEY_ACCESS_TOKEN, accessToken)
            putString(KEY_DEVICE_ID, deviceId)
        }
    }

    fun clearSession(context: Context) {
        prefs(context).edit {
            remove(KEY_BASE_URL)
            remove(KEY_ACCESS_TOKEN)
            remove(KEY_DEVICE_ID)
            remove(KEY_REGISTERED_TOKEN)
        }
    }

    fun saveFcmToken(context: Context, token: String) {
        prefs(context).edit { putString(KEY_FCM_TOKEN, token) }
    }

    /** Empty string forces the next registration attempt even if the FCM token is unchanged. */
    fun markRegistered(context: Context, token: String) {
        prefs(context).edit { putString(KEY_REGISTERED_TOKEN, token) }
    }

    fun baseUrl(context: Context): String? = prefs(context).getString(KEY_BASE_URL, null)
    fun accessToken(context: Context): String? = prefs(context).getString(KEY_ACCESS_TOKEN, null)
    fun deviceId(context: Context): String? = prefs(context).getString(KEY_DEVICE_ID, null)
    fun fcmToken(context: Context): String? = prefs(context).getString(KEY_FCM_TOKEN, null)
    fun registeredToken(context: Context): String? = prefs(context).getString(KEY_REGISTERED_TOKEN, null)
}
