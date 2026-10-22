package com.margelo.nitro.nitroplayer

import com.margelo.nitro.core.AnyJSON
import org.json.JSONObject
import org.json.JSONTokener

// `TrackItem.extraPayload` crosses the bridge as one JSON value per key.
// Persistence and header parsing work on org.json objects instead.

/** Decodes each value into org.json types, skipping values that are not valid JSON. */
internal fun Map<String, AnyJSON>.toJSONObject(): JSONObject {
    val obj = JSONObject()
    for ((key, json) in this) {
        runCatching { JSONTokener(json.stringRepresentation).nextValue() }
            .onSuccess { obj.put(key, it) }
    }
    return obj
}

/** Encodes each org.json value (`JSONObject`, `JSONArray`, `String`, `Number`, `Boolean` or `JSONObject.NULL`). */
internal fun JSONObject.toAnyJSONMap(): Map<String, AnyJSON> {
    val map = HashMap<String, AnyJSON>()
    for (key in keys()) {
        val value = get(key)
        map[key] = AnyJSON(if (value is String) JSONObject.quote(value) else value.toString())
    }
    return map
}
