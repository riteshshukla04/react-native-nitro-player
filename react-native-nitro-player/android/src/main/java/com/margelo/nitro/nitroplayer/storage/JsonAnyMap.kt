package com.margelo.nitro.nitroplayer.storage

import com.margelo.nitro.core.AnyMap
import org.json.JSONArray
import org.json.JSONObject

/**
 * Restores an `extraPayload` saved as JSON, nested objects and arrays included,
 * so values like `extraPayload.headers` survive a restart. Numbers stay doubles,
 * as JS numbers are.
 */
internal fun JSONObject.toAnyMap(): AnyMap = AnyMap.fromMap(toPlainMap(), true)

private fun JSONObject.toPlainMap(): Map<String, Any?> = keys().asSequence().associateWith { key -> toPlainValue(get(key)) }

private fun toPlainValue(value: Any?): Any? =
    when (value) {
        is JSONObject -> value.toPlainMap()
        is JSONArray -> List(value.length()) { index -> toPlainValue(value.get(index)) }
        is Number -> value.toDouble()
        JSONObject.NULL -> null
        else -> value
    }
