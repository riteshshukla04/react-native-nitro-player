package com.margelo.nitro.nitroplayer.download

import com.margelo.nitro.nitroplayer.TrackItem
import com.margelo.nitro.nitroplayer.Variant_NullType_String
import com.margelo.nitro.nitroplayer.toAnyJSONMap
import com.margelo.nitro.nitroplayer.toJSONObject
import org.json.JSONObject

// Survives process death inside the worker's inputData so a completed
// download can be recorded even when the in-memory metadata maps are gone.
internal object TrackItemJson {
    fun toJson(track: TrackItem): String =
        JSONObject()
            .apply {
                put("id", track.id)
                put("title", track.title)
                put("artist", track.artist)
                put("album", track.album)
                put("duration", track.duration)
                put("url", track.url)
                track.artwork?.asSecondOrNull()?.let { put("artwork", it) }
                track.extraPayload?.let { put("extraPayload", it.toJSONObject()) }
            }.toString()

    fun fromJson(json: String): TrackItem? =
        try {
            val obj = JSONObject(json)
            val artworkStr = obj.optString("artwork")
            val extraPayload =
                if (obj.has("extraPayload")) obj.getJSONObject("extraPayload").toAnyJSONMap() else null
            TrackItem(
                id = obj.getString("id"),
                title = obj.getString("title"),
                artist = obj.getString("artist"),
                album = obj.getString("album"),
                duration = obj.getDouble("duration"),
                url = obj.getString("url"),
                artwork = if (artworkStr.isNullOrEmpty()) null else Variant_NullType_String.create(artworkStr),
                extraPayload = extraPayload,
            )
        } catch (e: Exception) {
            null
        }
}
