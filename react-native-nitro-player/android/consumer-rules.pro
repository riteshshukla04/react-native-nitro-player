# Google Cast: the OptionsProvider is named in AndroidManifest meta-data and
# instantiated by the Cast framework via reflection, so R8 must not remove/rename it.
-keep class com.margelo.nitro.nitroplayer.media.NitroCastOptionsProvider { *; }
-keep class * implements com.google.android.gms.cast.framework.OptionsProvider { *; }

# WorkManager 2.10 uses Room 2.6, whose keep rule omits the constructor Room calls
# by reflection. R8 strict full mode (the AGP 9 default) strips it without this rule.
# Same rule as Room 2.7 (AndroidX e4765e38); drop it once WorkManager >= 2.11.
-keep class * extends androidx.room.RoomDatabase { void <init>(); }
