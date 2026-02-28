## Gson rules for flutter_local_notifications scheduled payload decoding.
## Keep generic signatures so TypeToken<NotificationDetails> survives R8.
-keepattributes Signature
-keepattributes *Annotation*

-dontwarn sun.misc.**

-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}

-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken

-keep class com.dexterous.flutterlocalnotifications.models.** { *; }

## Keep XmlPullParser interfaces stable for Android framework parser interop.
## Prevents release-only IncompatibleClassChangeError in image_picker/FileProvider
## where framework XmlBlock$Parser is cast to obfuscated app-side interfaces.
-keep class org.xmlpull.v1.** { *; }
-keep interface org.xmlpull.v1.** { *; }
