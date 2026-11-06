# Plugins reached from Dart at run time: keep them whole.
-keep class io.flutter.plugins.** { *; }
-keep class dev.fluttercommunity.** { *; }
-keep class kotlin.coroutines.** { *; }
-keep class kotlinx.coroutines.** { *; }
-dontwarn io.flutter.embedding.**
