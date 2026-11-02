package com.margelo.nitro.nitroplayer.media

/** Cast-free build: keeps `Cast.configure(...)` a harmless no-op. */
object NitroCastConfig {
    @Volatile
    var receiverApplicationId: String? = null
}
