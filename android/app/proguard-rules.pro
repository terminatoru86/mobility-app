# Plugins reached from Dart at run time: keep them whole.
-keep class io.flutter.plugins.** { *; }
-keep class dev.fluttercommunity.** { *; }
-keep class kotlin.coroutines.** { *; }
-keep class kotlinx.coroutines.** { *; }
-dontwarn io.flutter.embedding.**

# shared_preferences 2.5 (Pigeon JNI): Kotlin classes looked up by name through JNI.
# Without these, release builds crash with NoSuchMethodError ...SharedPreferencesApiRegistrar.getAll
-keep class kotlin.Unit { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$Failure { *; }
-keep class kotlin.coroutines.Continuation { *; }
-keep class kotlin.coroutines.intrinsics.CoroutineSingletons { *; }
-keep class kotlin.coroutines.intrinsics.IntrinsicsKt { *; }
-keep class com.github.dart_lang.jni.** { *; }
