# 华为统一扫码（Scan Kit）/ HMS Core / AGC：避免 R8 混淆导致扫码或上架检测异常
-ignorewarnings
-keepattributes *Annotation*, Exceptions, InnerClasses, Signature
-keep class com.huawei.hms.** { *; }
-keep class com.huawei.hianalytics.** { *; }
-keep class com.huawei.agconnect.** { *; }
-keep class com.huawei.updatesdk.** { *; }
-dontwarn com.huawei.**