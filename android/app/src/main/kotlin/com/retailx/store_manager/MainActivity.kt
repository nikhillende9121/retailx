package com.retailx.store_manager

import android.content.Intent
import android.os.Bundle
import com.retailx.store_manager.data.DeviceTokenSync
import com.retailx.store_manager.util.NotificationHelper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val pushChannelName = "com.retailx.store_manager/push"
    private val notificationChannelName = "com.retailx.store_manager/notifications"

    private var notificationChannel: MethodChannel? = null

    /**
     * The most recent tapped-notification payload the Dart side hasn't picked up
     * yet. Needed because a cold start delivers the launch intent (in [onCreate])
     * before Dart has had a chance to call [MethodChannel.setMethodCallHandler] on
     * [notificationChannel] — an `invokeMethod` call that early would just be
     * dropped. Dart pulls this once via `getInitialNotificationRoute` instead.
     */
    private var pendingNotificationRoute: Map<String, String>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        NotificationHelper.createNotificationChannels(this)
        NotificationHelper.requestNotificationPermission(this)
        handleNotificationIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, pushChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "syncSession" -> {
                        val baseUrl = call.argument<String>("baseUrl")
                        val accessToken = call.argument<String>("accessToken")
                        val deviceId = call.argument<String>("deviceId")
                        if (baseUrl != null && accessToken != null && deviceId != null) {
                            DeviceTokenSync.onSessionStarted(applicationContext, baseUrl, accessToken, deviceId)
                        }
                        result.success(null)
                    }
                    "clearSession" -> {
                        DeviceTokenSync.onSessionEnded(applicationContext)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        notificationChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, notificationChannelName)
                .apply {
                    setMethodCallHandler { call, result ->
                        when (call.method) {
                            "getInitialNotificationRoute" -> {
                                result.success(pendingNotificationRoute)
                                pendingNotificationRoute = null
                            }
                            else -> result.notImplemented()
                        }
                    }
                }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // singleTop delivers the new intent here without replacing the cached one —
        // without this, a later getIntent() would still see the launcher intent.
        setIntent(intent)
        handleNotificationIntent(intent)
    }

    private fun handleNotificationIntent(intent: Intent?) {
        intent?.let {
            val route = it.getStringExtra("EXTRA_TARGET_ROUTE")
            val entityId = it.getStringExtra("EXTRA_ENTITY_ID")
            val type = it.getStringExtra("EXTRA_NOTIFICATION_TYPE")
            if (route.isNullOrEmpty()) return

            android.util.Log.d(
                "MainActivity",
                "Notification deep link route: $route, entityId: $entityId, type: $type"
            )
            val data = mapOf(
                "route" to route,
                "entityId" to (entityId ?: ""),
                "type" to (type ?: ""),
            )
            // Cached for a cold start (Dart pulls it once it's ready) and, harmlessly,
            // for a warm one too — consumeInitialRoute() clears it after reading.
            pendingNotificationRoute = data
            // Delivered live for a warm start; a cold start's Dart side isn't
            // listening yet, so this call is simply dropped — the cache above covers it.
            notificationChannel?.invokeMethod("onNotificationTap", data)
        }
    }
}
