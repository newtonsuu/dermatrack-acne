# DermaTrack — ProGuard / R8 keep rules
# ---------------------------------------------------------------------------
# NOTE: Release builds currently do NOT enable minification (see
# build.gradle.kts — no isMinifyEnabled), so these rules are INERT today.
# They are kept here so that IF code shrinking (R8) is ever turned on, the
# flutter_local_notifications "RuntimeException: Missing type parameter"
# (caused by R8 stripping Gson generic signatures used to (de)serialize the
# scheduled-notification cache) does not reappear.
#
# To enable minification later, in build.gradle.kts release { } add:
#   isMinifyEnabled = true
#   proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"),
#                 "proguard-rules.pro")
# ---------------------------------------------------------------------------

# flutter_local_notifications (uses Gson to persist scheduled notifications)
-keep class com.dexterous.** { *; }

# Gson: preserve generic signatures + annotations so TypeToken keeps its type
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.** { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}
