# Onyx (Boox) SDK: used only on ONYX e-readers (OnyxBridge.kt). It reaches the
# e-reader framework through reflection, so keep it whole.
-keep class com.onyx.** { *; }
-keep interface com.onyx.** { *; }
-dontwarn com.onyx.**
-keep class org.lsposed.hiddenapibypass.** { *; }

# Optional classes the SDK's dependencies refer to but never need here
# (fastjson 1.x compatibility in fastjson2, joda-convert annotations).
-dontwarn com.alibaba.fastjson.JSONArray
-dontwarn com.alibaba.fastjson.JSONObject
-dontwarn org.joda.convert.FromString
-dontwarn org.joda.convert.ToString
