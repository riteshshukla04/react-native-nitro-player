# Google Cast: the OptionsProvider is named in AndroidManifest meta-data and
# instantiated by the Cast framework via reflection, so R8 must not remove/rename it.
-keep class com.margelo.nitro.nitroplayer.media.NitroCastOptionsProvider { *; }
-keep class * implements com.google.android.gms.cast.framework.OptionsProvider { *; }
