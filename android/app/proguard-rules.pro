# Release builds shrink and minify, and `flutter analyze`/`flutter test`
# never touch Gradle — so a broken release config sits invisible until
# someone actually builds one. Keep these rules honest by running
# `flutter build apk --release` after any change to the Android side.

# audioplayers reaches its Android implementation reflectively through the
# plugin registrant.
-keep class xyz.luan.audioplayers.** { *; }

# gal, likewise, for the MediaStore calls behind the gallery export.
-keep class studio.midoridesign.gal.** { *; }
