package com.retailx.store_manager.data.api

import java.util.concurrent.TimeUnit
import okhttp3.OkHttpClient
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory

/**
 * Builds a short-lived [NotificationApiService] pointed at whatever server the
 * signed-in Flutter session is currently using. Cheap enough (a handful of
 * calls per app session — login, token refresh, logout) that there's no need
 * to cache the Retrofit instance across a base URL / token that can change
 * whenever the user switches servers or signs in as someone else.
 */
object NotificationApiClient {
    fun create(baseUrl: String, accessToken: String): NotificationApiService {
        val client = OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(20, TimeUnit.SECONDS)
            .addInterceptor { chain ->
                val request = chain.request().newBuilder()
                    .addHeader("Authorization", "Bearer $accessToken")
                    .build()
                chain.proceed(request)
            }
            .build()

        return Retrofit.Builder()
            .baseUrl(baseUrl)
            .client(client)
            .addConverterFactory(GsonConverterFactory.create())
            .build()
            .create(NotificationApiService::class.java)
    }
}
