package com.retailx.store_manager.service

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.core.graphics.drawable.IconCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.retailx.store_manager.MainActivity
import com.retailx.store_manager.R
import com.retailx.store_manager.data.DeviceTokenSync
import com.retailx.store_manager.util.NotificationHelper

class MyFirebaseMessagingService : FirebaseMessagingService() {

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d("FCM", "New FCM registration token received: $token")
        DeviceTokenSync.onFcmTokenReceived(applicationContext, token)
    }

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        super.onMessageReceived(remoteMessage)

        val title = remoteMessage.notification?.title 
            ?: remoteMessage.data["title"] 
            ?: "Store Alert"
            
        val body = remoteMessage.notification?.body 
            ?: remoteMessage.data["message"] 
            ?: ""

        val type = remoteMessage.data["type"] ?: "GENERAL"
        val entityId = remoteMessage.data["entityId"] ?: ""
        val route = remoteMessage.data["route"] ?: ""

        showNativeNotification(title, body, type, entityId, route)
    }

    private fun showNativeNotification(
        title: String,
        body: String,
        type: String,
        entityId: String,
        route: String
    ) {
        val channelId = when (type) {
            "LOW_STOCK" -> NotificationHelper.CHANNEL_INVENTORY
            "STOCK_TRANSFER" -> NotificationHelper.CHANNEL_TRANSFERS
            else -> NotificationHelper.CHANNEL_SALES
        }

        // Intent to launch app and navigate to specific screen
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("EXTRA_TARGET_ROUTE", route)
            putExtra("EXTRA_ENTITY_ID", entityId)
            putExtra("EXTRA_NOTIFICATION_TYPE", type)
        }

        val pendingIntent = PendingIntent.getActivity(
            this,
            System.currentTimeMillis().toInt(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notificationBuilder = NotificationCompat.Builder(this, channelId)
            // A resource-id small icon (setSmallIcon(R.drawable.x)) is what
            // some OEM skins intercept and replace with their own generic
            // graphic — confirmed on this device by setLargeIcon(Bitmap)
            // rendering correctly while the resource-based small icon never
            // did, even after a full uninstall/reinstall. Passing the same
            // glyph as a raw bitmap instead leaves no resource reference for
            // anything to substitute.
            .setSmallIcon(IconCompat.createWithBitmap(buildSmallIcon()))
            // Without this, the icon's background badge falls back to
            // whatever default tint the OS/OEM skin picks — which is where
            // the stray green some devices showed was coming from. Reusing
            // ic_launcher_background (not a separate hardcoded hex) keeps
            // this one color definition as the single source of truth.
            .setColor(getColor(R.color.ic_launcher_background))
            // Deliberately no setLargeIcon(): the small icon is mandatory
            // and this OEM overrides it regardless of what we declare, so
            // adding a large icon on top just produced two icons in the row
            // (one correct, one not) instead of one. One icon slot, even an
            // OS-overridden one, beats a row with two different icons in it.
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(pendingIntent)

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(System.currentTimeMillis().toInt(), notificationBuilder.build())
    }

    /** Rasterizes ic_notification (white glyph, transparent background — the
     * alpha-mask silhouette convention a small icon is supposed to be) into
     * a bitmap, so setSmallIcon gets no resource id to intercept. */
    private fun buildSmallIcon(): Bitmap {
        val size = 96
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        ContextCompat.getDrawable(this, R.drawable.ic_notification)?.apply {
            setBounds(0, 0, size, size)
            draw(canvas)
        }
        return bitmap
    }
}
