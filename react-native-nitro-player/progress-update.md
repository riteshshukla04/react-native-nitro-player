# NitroPlayer v2 — Android Progress Update

## Status: Android complete ✓ | iOS + TS hooks pending

---

## What Changed vs v1

### Architecture
| Area | v1 | v2 |
|------|----|----|
| Thread safety | `CountDownLatch` (5s blocks) | `suspend fun withPlayerContext { }` on dedicated `HandlerThread` |
| Listener lifetime | `WeakCallbackBox` (GC-dependent) | `ListenerRegistry<T>` with stable `Long` IDs |
| Commands | Fire-and-forget, no error feedback | `Promise<T>` — errors propagate to JS |
| Temp queue APIs | Missing | `removeFromPlayNext`, `removeFromUpNext`, `clearPlayNext`, `clearUpNext`, `reorderTemporaryTrack`, `getPlayNextQueue`, `getUpNextQueue`, `onTemporaryQueueChange` |
| File structure | Single 1935-line `TrackPlayerCore.kt` | 10 focused files, none > 300 lines |
| ExoPlayer init | Created on whatever thread | Created with `setLooper(playerThread.looper)` — player-thread-owned |
| Save I/O | Main thread (blocked UI) | `Dispatchers.IO` coroutine scope |

---

## Completed Steps

### Step 1 — TypeScript Specs Updated
**Files changed:**
- `src/specs/TrackPlayer.nitro.ts` — `play/pause/seek/skipToNext/skipToPrevious/setRepeatMode/setVolume/configure` → `Promise<void>`; added 8 temp queue methods
- `src/specs/DownloadManager.nitro.ts` — 10 query methods → `Promise<T>`
- `src/specs/Equalizer.nitro.ts` — 9 mutation methods → `Promise<T>`
- `src/specs/AudioDevices.nitro.ts` — `setAudioDevice` → `Promise<void>`
- `src/specs/AndroidAutoMediaLibrary.nitro.ts` — both methods → `Promise<void>`
- `src/specs/PlayerQueue.nitro.ts` — all mutations → `Promise<T>`

### Step 2 — Nitrogen Codegen
Ran `npx nitrogen` — all `HybridXxxSpec.kt` regenerated with `abstract suspend fun` signatures.

### Step 3 — ListenerRegistry
**New file:** `android/.../core/ListenerRegistry.kt`
- `CopyOnWriteArrayList<Entry<T>>` + `AtomicLong` for stable IDs
- `add(callback): Long`, `remove(id): Boolean`, `clear()`, `forEach(action)`

### Steps 5–6 — Player Thread Infrastructure + ExoPlayer Migration
**New file:** `android/.../core/ExoPlayerCore.kt` — dumb wrapper, zero business logic
**Updated:** `android/.../core/TrackPlayerCore.kt`
- `playerThread: HandlerThread("NitroPlayer")`, `playerHandler`, `playerDispatcher`
- `private val scope = CoroutineScope(SupervisorJob() + playerDispatcher)`
- `internal suspend fun withPlayerContext(block: () -> T)` bridge
- 7× `ListenerRegistry<T>` replacing `synchronized(Collections.synchronizedList(WeakCallbackBox))`
- ExoPlayer created via `ExoPlayerCore(context, playerThread)` with correct looper
- `progressUpdateRunnable` posts on `playerHandler` not main looper

### Step 7 — CountDownLatch → withPlayerContext (all 9 sites)
All blocking patterns replaced with `suspend fun withPlayerContext { }`.
Removed: `import java.util.concurrent.CountDownLatch`, `import java.util.concurrent.TimeUnit`

### Step 8 — ListenerRegistry + Notify Functions
**New file:** `android/.../core/TrackPlayerNotify.kt`
- All `notifyXxx` extensions call `listenerRegistry.forEach { it(args) }` directly (player thread)
- `notifyTemporaryQueueChange()` snapshots `playNextStack.toList()` + `upNextQueue.toList()`

### Step 9 — Temp Queue APIs + Core Split
TrackPlayerCore split into 10 focused files:

| File | Responsibility |
|------|---------------|
| `TrackPlayerCore.kt` | State fields, coroutine infra, ListenerRegistry, lifecycle |
| `ExoPlayerCore.kt` | Dumb ExoPlayer wrapper |
| `TrackPlayerSetup.kt` | `initExoAndMedia()` — builds ExoPlayer, MediaSession, attaches listener |
| `TrackPlayerListener.kt` | `TrackPlayerEventListener` — all ExoPlayer callbacks |
| `TrackPlayerNotify.kt` | `notifyXxx` extension functions |
| `TrackPlayerQueueBuild.kt` | Queue rebuild helpers + `makeMediaItem` |
| `TrackPlayerPlayback.kt` | `play/pause/seek/skipToNext/skipToPrevious/setRepeatMode/setVolume/configure/playSong` |
| `TrackPlayerQueue.kt` | `getState/getActualQueue/skipToIndex/playFromIndex` |
| `TrackPlayerTempQueue.kt` | `loadPlaylist/updatePlaylist/playNext/addToUpNext` + all 7 new temp APIs |
| `TrackPlayerUrlLoader.kt` | `updateTracks/getTracksById/getTracksNeedingUrls/getNextTracks/checkUpcomingTracksForUrls` |
| `TrackPlayerAndroidAuto.kt` | `setupAndroidAutoDetector/playFromPlaylistTrack/setAndroidAutoMediaLibrary` |

New suspend functions added: `removeFromPlayNext`, `removeFromUpNext`, `clearPlayNext`, `clearUpNext`, `reorderTemporaryTrack`, `getPlayNextQueue`, `getUpNextQueue`
All temp mutations call `notifyTemporaryQueueChange()`.

### Step 10 — Supporting Classes
**PlaylistManager.kt**
- `MutableMap` → `ConcurrentHashMap<String, Playlist>` — lock-free reads
- Removed all `synchronized(playlists)` blocks
- `saveHandler`/`saveRunnable` (main thread) → `CoroutineScope(Dispatchers.IO)` + `Job`/`delay(300)` debounce

**DownloadDatabase.kt**
- Added `ioScope = CoroutineScope(Dispatchers.IO + SupervisorJob())`
- `saveToDisk()` now snapshots in-memory state then writes async on IO scope (no longer blocks caller thread)

**EqualizerCore.kt**
- Removed `WeakCallbackBox` data class + `Collections.synchronizedList`
- 3 listener lists replaced with `ListenerRegistry<T>`
- `notifyXxx` functions simplified to `listeners.forEach { it(args) }`

### Step 11 — Hybrid Bridge Files
All 6 bridge files updated:

| File | Changes |
|------|---------|
| `HybridTrackPlayer.kt` | All commands → `Promise.async { core.xxx() }`, listener ID tracking, `override fun dispose()` cleanup |
| `HybridPlayerQueue.kt` | All mutations → `Promise.async { }` |
| `HybridDownloadManager.kt` | 10 async query methods → `Promise.async { }` |
| `HybridEqualizer.kt` | 9 mutation methods → `Promise.async { }` |
| `HybridAudioDevices.kt` | `setAudioDevice` → `Promise<Unit>` |
| `HybridAndroidAutoMediaLibrary.kt` | Both methods → `Promise<Unit>` |

---

## What Remains

### iOS (Steps 12–16)
- Mirror the same architectural changes in `ios/core/TrackPlayerCore.swift`
- Move AVQueuePlayer to a dedicated serial `DispatchQueue`
- Replace callback arrays with `ListenerStore` (Swift equivalent)
- Add temp queue APIs to Swift side
- Update all iOS Hybrid bridge files

### TypeScript Hooks (Steps 17–19)
- Update `useActualQueue`, `useTrackPlayer`, etc. to handle `Promise`-based APIs
- Add `useTemporaryQueue` hook
- Update any hooks that assumed sync returns

---

## Breaking Changes (v1 → v2)

- `play()`, `pause()`, `seek()`, `skipToNext()`, `skipToPrevious()` now return `Promise<void>`
- `setRepeatMode()` returns `Promise<void>` (no longer returns `boolean`)
- `setVolume()` returns `Promise<void>` (no longer returns `boolean`)
- `setAudioDevice()` returns `Promise<void>` (no longer returns `boolean`)
- All download query methods (`isTrackDownloaded`, `getDownloadedTrack`, etc.) now return `Promise<T>`
- All equalizer mutations return `Promise<void>`
- Queue mutations (`createPlaylist`, `addTrackToPlaylist`, etc.) return `Promise<T>`
- New temp queue methods added to `TrackPlayer` interface
