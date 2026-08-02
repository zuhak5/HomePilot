# WorkManager uses Room-generated classes through reflection during
# AndroidX Startup initialization. Keep those implementations intact in
# minified release builds so the app can launch before Flutter starts.
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class androidx.work.impl.model.** { *; }
-keep class androidx.room.** { *; }
-keep class androidx.sqlite.** { *; }
-keep class * extends androidx.room.RoomDatabase { *; }
