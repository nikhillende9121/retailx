# Standard Retrofit2 + Gson rules (retrofit2/converter-gson upstream docs) —
# without these, R8's release-mode shrinking/obfuscation breaks the
# device-token register/unregister calls silently at runtime: Retrofit and
# Gson both rely on reflection over generic signatures and field names that
# R8 would otherwise strip or rename.

-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod
-keepattributes RuntimeVisibleAnnotations, RuntimeVisibleParameterAnnotations
-keepattributes AnnotationDefault

-keepclassmembers,allowshrinking,allowobfuscation interface * {
    @retrofit2.http.* <methods>;
}

-dontwarn javax.annotation.**
-dontwarn kotlin.Unit
-dontwarn retrofit2.KotlinExtensions
-dontwarn retrofit2.KotlinExtensions$*
-dontwarn sun.misc.**

-keep,allowobfuscation,allowshrinking class retrofit2.Response
-keep,allowobfuscation,allowshrinking class kotlin.coroutines.Continuation

-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

-keepclassmembers,allowobfuscation class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Our own request/response DTOs have no @SerializedName annotations — Gson
# matches JSON keys to field names directly by reflection, so the fields (and
# the class itself) have to survive shrinking/renaming verbatim.
-keep class com.retailx.store_manager.data.api.** { *; }
