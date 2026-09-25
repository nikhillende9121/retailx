package com.retailx.store_manager.util

import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

object NotificationHelper {

    const val CHANNEL_INVENTORY = "channel_inventory"
    const val CHANNEL_TRANSFERS = "channel_transfers"
    const val CHANNEL_SALES = "channel_sales"

    private const val PREFS_NAME = "notification_helper"
    private const val KEY_CHANNELS_RESET_V1 = "channels_reset_v1"

    fun createNotificationChannels(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

            // createNotificationChannel(s) is a no-op for a channel id that
            // already exists — Android won't let you change most properties
            // of a live channel this way. These channels were first created
            // hours before today's icon fixes, and some OEM skins cache a
            // per-channel badge/icon snapshot from that original creation
            // that a plain re-create never refreshes. Deleting first forces
            // a genuinely new channel object, invalidating any such cache.
            //
            // Gated to run once, ever: doing this on every launch would also
            // silently wipe out a user's own channel customization (muting
            // one, lowering its importance) every time the app restarts.
            if (!prefs.getBoolean(KEY_CHANNELS_RESET_V1, false)) {
                for (id in listOf(CHANNEL_INVENTORY, CHANNEL_TRANSFERS, CHANNEL_SALES)) {
                    manager.deleteNotificationChannel(id)
                }
                prefs.edit().putBoolean(KEY_CHANNELS_RESET_V1, true).apply()
            }

            // Low Stock & Inventory Alerts (High Importance)
            val inventoryChannel = NotificationChannel(
                CHANNEL_INVENTORY,
                "Inventory & Low Stock Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifications when stock levels drop below reorder thresholds"
                enableVibration(true)
            }

            // Stock Transfers (High Importance)
            val transferChannel = NotificationChannel(
                CHANNEL_TRANSFERS,
                "Stock Transfers",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifications for incoming and outgoing stock transfer updates"
                enableVibration(true)
            }

            // Sales & Orders (Default Importance)
            val salesChannel = NotificationChannel(
                CHANNEL_SALES,
                "Sales & Order Updates",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Lifecycle updates for sales orders"
            }

            manager.createNotificationChannels(listOf(inventoryChannel, transferChannel, salesChannel))
        }
    }

    fun requestNotificationPermission(activity: Activity) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val permission = android.Manifest.permission.POST_NOTIFICATIONS
            if (ContextCompat.checkSelfPermission(activity, permission) != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(activity, arrayOf(permission), 1001)
            }
        }
    }
}
