package com.retailx.store_manager.data.api

import retrofit2.Response
import retrofit2.http.Body
import retrofit2.http.HTTP
import retrofit2.http.POST

// Request DTOs
data class RegisterDeviceTokenRequest(
    val deviceId: String,
    val fcmToken: String,
    val platform: String = "ANDROID",
    val deviceModel: String
)

data class UnregisterDeviceTokenRequest(
    val fcmToken: String
)

data class ApiResponse<T>(
    val success: Boolean,
    val data: T?,
    val message: String?
)

interface NotificationApiService {

    @POST("/api/v1/notifications/device-token")
    suspend fun registerDeviceToken(
        @Body request: RegisterDeviceTokenRequest
    ): Response<ApiResponse<Map<String, Boolean>>>

    @HTTP(method = "DELETE", path = "/api/v1/notifications/device-token", hasBody = true)
    suspend fun unregisterDeviceToken(
        @Body request: UnregisterDeviceTokenRequest
    ): Response<ApiResponse<Map<String, Boolean>>>
}
