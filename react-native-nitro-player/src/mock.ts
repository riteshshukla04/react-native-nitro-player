/// <reference types="jest" />
/**
 * Jest mock for react-native-nitro-player.
 *
 * Every native method is a `jest.fn()` that resolves to an empty, valid value,
 * and every hook returns its initial state, so tests run without native modules:
 *
 * ```ts
 * jest.mock('react-native-nitro-player', () =>
 *   require('react-native-nitro-player/mock')
 * )
 * ```
 *
 * Override per test with `mockResolvedValue` / `mockReturnValue` as usual.
 * With `resetMocks: true`, call `resetNitroPlayerMock()` in a `beforeEach`.
 */
import type { HybridObject } from 'react-native-nitro-modules'
import type * as NitroPlayer from './index'
import type * as Mock from './mock'
import type {
  PlayerQueue as PlayerQueueType,
  TrackPlayer as TrackPlayerType,
} from './specs/TrackPlayer.nitro'
import type { AndroidAutoMediaLibrary as AndroidAutoMediaLibraryType } from './specs/AndroidAutoMediaLibrary.nitro'
import type { AudioDevices as AudioDevicesType } from './specs/AudioDevices.nitro'
import type { AudioRoutePicker as AudioRoutePickerType } from './specs/AudioRoutePicker.nitro'
import type { Cast as CastType } from './specs/Cast.nitro'
import type { DownloadManager as DownloadManagerType } from './specs/DownloadManager.nitro'
import type { Equalizer as EqualizerType } from './specs/Equalizer.nitro'
import type { PlayerState, TrackItem } from './types/PlayerQueue'
import type {
  DownloadQueueStatus,
  DownloadStorageInfo,
} from './types/DownloadTypes'
import type {
  UseActualQueueResult,
  UseCastStateResult,
  UseDownloadActionsResult,
  UseDownloadedTracksResult,
  UseDownloadStorageResult,
  UseEqualizerPresetsResult,
  UseEqualizerResult,
  UsePlaylistResult,
} from './hooks'

/** A HybridObject's own methods as jest mocks; listing every method keeps the mock in step with the spec */
export type MockedHybridObject<T> = {
  [K in Exclude<keyof T, keyof HybridObject<{}>>]: T[K] extends (
    ...args: infer A
  ) => infer R
    ? jest.Mock<R, A>
    : T[K]
}

type MockedExport<K extends keyof typeof NitroPlayer> = jest.MockedFunction<
  Extract<(typeof NitroPlayer)[K], (...args: any[]) => any>
>

const defaults: Array<() => void> = []

// Every mock goes through here so resetNitroPlayerMock can re-arm it after jest.resetAllMocks()
const mock = <R, A extends any[]>(impl: (...args: A) => R): jest.Mock<R, A> => {
  const fn = jest.fn<R, A>()
  const arm = () => {
    fn.mockReset()
    fn.mockImplementation(impl)
  }
  arm()
  defaults.push(arm)
  return fn
}

// Args and return types come from the property they are assigned to, so a spec change fails typecheck
const resolved = <T, A extends any[]>(value: T): jest.Mock<Promise<T>, A> =>
  mock<Promise<T>, A>(async () => value)
const returns = <T, A extends any[]>(value: T): jest.Mock<T, A> =>
  mock<T, A>(() => value)
// A fresh array per call, so code that pushes onto a result can't leak into the next test
const resolvedEmpty = <A extends any[]>(): jest.Mock<Promise<never[]>, A> =>
  mock<Promise<never[]>, A>(async () => [])
const noop = <A extends any[]>(): jest.Mock<void, A> => mock<void, A>(() => {})

/** Clears every mock's calls and restores its default; call it in `beforeEach` when using `resetMocks: true` */
export function resetNitroPlayerMock(): void {
  defaults.forEach((arm) => arm())
}

// Object.freeze that keeps the annotated type as the inference target, so literals don't widen
const frozen = <T>(value: T): T => Object.freeze(value)

const DEFAULT_PLAYER_STATE: PlayerState = frozen({
  currentTrack: null,
  currentPosition: 0,
  totalDuration: 0,
  currentState: 'stopped',
  currentPlaylistId: null,
  currentIndex: -1,
  currentPlayingType: 'not-playing',
})

const EMPTY_STORAGE_INFO: DownloadStorageInfo = {
  totalDownloadedSize: 0,
  trackCount: 0,
  playlistCount: 0,
  availableSpace: 0,
  totalSpace: 0,
}

const EMPTY_QUEUE_STATUS: DownloadQueueStatus = {
  pendingCount: 0,
  activeCount: 0,
  completedCount: 0,
  failedCount: 0,
  totalBytesToDownload: 0,
  totalBytesDownloaded: 0,
  overallProgress: 0,
}

const GAIN_RANGE = { min: -12, max: 12 }

export const PlayerQueue: MockedHybridObject<PlayerQueueType> = {
  createPlaylist: resolved(''),
  deletePlaylist: resolved(undefined),
  updatePlaylist: resolved(undefined),
  getPlaylist: returns(null),
  getAllPlaylists: returns([]),
  addTrackToPlaylist: resolved(undefined),
  addTracksToPlaylist: resolved(undefined),
  removeTrackFromPlaylist: resolved(undefined),
  reorderTrackInPlaylist: resolved(undefined),
  removeTracksFromPlaylist: resolved(undefined),
  shufflePlaylist: resolved(undefined),
  loadPlaylist: resolved(undefined),
  getCurrentPlaylistId: returns(null),
  onPlaylistsChanged: noop(),
  onPlaylistChanged: noop(),
}

export const TrackPlayer: MockedHybridObject<TrackPlayerType> = {
  play: resolved(undefined),
  pause: resolved(undefined),
  playSong: resolved(undefined),
  skipToNext: resolved(undefined),
  skipToIndex: resolved(true),
  skipToPrevious: resolved(undefined),
  seek: resolved(undefined),
  addToUpNext: resolved(undefined),
  playNext: resolved(undefined),
  getActualQueue: resolvedEmpty(),
  getState: mock(async () => ({ ...DEFAULT_PLAYER_STATE })),
  setRepeatMode: resolved(undefined),
  getRepeatMode: returns('off'),
  configure: resolved(undefined),
  onChangeTrack: noop(),
  onPlaybackStateChange: noop(),
  onSeek: noop(),
  onPlaybackProgressChange: noop(),
  onTimedMetadata: noop(),
  appStartedWithNotification: noop(),
  onAndroidAutoConnectionChange: noop(),
  isAndroidAutoConnected: returns(false),
  setNotificationButtonState: noop(),
  onNotificationButtonPress: noop(),
  setVolume: resolved(undefined),
  updateTracks: resolved(undefined),
  getTracksById: resolvedEmpty(),
  getTracksNeedingUrls: resolvedEmpty(),
  getNextTracks: resolvedEmpty(),
  getCurrentTrackIndex: resolved(-1),
  onTracksNeedUpdate: noop(),
  setPlaybackSpeed: resolved(undefined),
  getPlaybackSpeed: resolved(1),
  removeFromPlayNext: resolved(true),
  removeFromUpNext: resolved(true),
  clearPlayNext: resolved(undefined),
  clearUpNext: resolved(undefined),
  reorderTemporaryTrack: resolved(true),
  getPlayNextQueue: resolvedEmpty(),
  getUpNextQueue: resolvedEmpty(),
  onTemporaryQueueChange: noop(),
}

// Platform-only modules are always present here so tests on either platform can assert on them
export const AndroidAutoMediaLibrary: MockedHybridObject<AndroidAutoMediaLibraryType> =
  {
    setMediaLibrary: resolved(undefined),
    clearMediaLibrary: resolved(undefined),
    onLoadChildren: noop(),
    onSearch: noop(),
    resolveRequest: noop(),
    setSessionButtons: noop(),
    onSessionButtonPress: noop(),
    onPlaybackResumption: noop(),
  }

export const AudioDevices: MockedHybridObject<AudioDevicesType> = {
  getAudioDevices: mock(() => []),
  setAudioDevice: resolved(undefined),
}

export const AudioRoutePicker: MockedHybridObject<AudioRoutePickerType> = {
  showRoutePicker: noop(),
}

export const Cast: MockedHybridObject<CastType> = {
  configure: resolved(undefined),
  isCasting: returns(false),
  getCastState: returns('no_devices_available'),
  getCastDeviceName: returns(null),
  showCastPicker: noop(),
  endCastSession: resolved(undefined),
  onCastStateChange: noop(),
}

export const DownloadManager: MockedHybridObject<DownloadManagerType> = {
  configure: noop(),
  getConfig: mock(() => ({})),
  downloadTrack: resolved(''),
  downloadPlaylist: resolvedEmpty(),
  pauseDownload: resolved(undefined),
  resumeDownload: resolved(undefined),
  cancelDownload: resolved(undefined),
  retryDownload: resolved(undefined),
  pauseAllDownloads: resolved(undefined),
  resumeAllDownloads: resolved(undefined),
  cancelAllDownloads: resolved(undefined),
  getDownloadTask: returns(null),
  getActiveDownloads: mock(() => []),
  getQueueStatus: mock(() => ({ ...EMPTY_QUEUE_STATUS })),
  isDownloading: returns(false),
  getDownloadState: returns(null),
  isTrackDownloaded: resolved(false),
  isPlaylistDownloaded: resolved(false),
  isPlaylistPartiallyDownloaded: resolved(false),
  getDownloadedTrack: resolved(null),
  getAllDownloadedTracks: resolvedEmpty(),
  getDownloadedPlaylist: resolved(null),
  getAllDownloadedPlaylists: resolvedEmpty(),
  getLocalPath: resolved(null),
  deleteDownloadedTrack: resolved(undefined),
  deleteDownloadedPlaylist: resolved(undefined),
  deleteAllDownloads: resolved(undefined),
  getStorageInfo: mock(async () => ({ ...EMPTY_STORAGE_INFO })),
  syncDownloads: resolved(0),
  setPlaybackSourcePreference: noop(),
  getPlaybackSourcePreference: returns('auto'),
  getEffectiveUrl: mock(async (track: TrackItem) => track.url),
  onDownloadProgress: noop(),
  onDownloadStateChange: noop(),
  onDownloadComplete: noop(),
}

export const Equalizer: MockedHybridObject<EqualizerType> = {
  setEnabled: resolved(undefined),
  isEnabled: returns(false),
  getBands: resolvedEmpty(),
  setBandGain: resolved(undefined),
  setAllBandGains: resolved(undefined),
  getBandRange: mock(() => ({ ...GAIN_RANGE })),
  getPresets: mock(() => []),
  getBuiltInPresets: mock(() => []),
  getCustomPresets: mock(() => []),
  applyPreset: resolved(undefined),
  getCurrentPresetName: returns(null),
  saveCustomPreset: resolved(undefined),
  deleteCustomPreset: resolved(undefined),
  getState: mock(async () => ({
    enabled: false,
    bands: [],
    currentPreset: null,
  })),
  reset: resolved(undefined),
  onEnabledChange: noop(),
  onBandChange: noop(),
  onPresetChange: noop(),
}

// Hooks return one frozen result each, like a hook that hasn't re-rendered: stable for effect deps and call assertions
const PLAYLIST_RESULT: UsePlaylistResult = frozen({
  currentPlaylist: null,
  currentPlaylistId: null,
  allPlaylists: [],
  allTracks: [],
  isLoading: false,
  refreshPlaylists: noop(),
})

const ACTUAL_QUEUE_RESULT: UseActualQueueResult = frozen({
  queue: [],
  refreshQueue: noop(),
  isLoading: false,
})

const CAST_STATE_RESULT: UseCastStateResult = frozen({
  state: 'no_devices_available',
  deviceName: null,
  isCasting: false,
  isReady: false,
})

const DOWNLOAD_PROGRESS_RESULT: ReturnType<
  typeof NitroPlayer.useDownloadProgress
> = frozen({
  progressMap: new Map(),
  progressList: [],
  overallProgress: 0,
  isDownloading: false,
  getProgress: returns(undefined),
})

const DOWNLOADED_TRACKS_RESULT: UseDownloadedTracksResult = frozen({
  downloadedTracks: [],
  downloadedPlaylists: [],
  isTrackDownloaded: returns(false),
  isPlaylistDownloaded: returns(false),
  isPlaylistPartiallyDownloaded: returns(false),
  getDownloadedTrack: returns(undefined),
  getDownloadedPlaylist: returns(undefined),
  refresh: noop(),
  isLoading: false,
})

const DOWNLOAD_ACTIONS_RESULT: UseDownloadActionsResult = frozen({
  downloadTrack: resolved(''),
  downloadPlaylist: resolvedEmpty(),
  pauseDownload: resolved(undefined),
  resumeDownload: resolved(undefined),
  cancelDownload: resolved(undefined),
  retryDownload: resolved(undefined),
  pauseAll: resolved(undefined),
  resumeAll: resolved(undefined),
  cancelAll: resolved(undefined),
  deleteTrack: resolved(undefined),
  deletePlaylist: resolved(undefined),
  deleteAll: resolved(undefined),
  configure: noop(),
  setPlaybackSourcePreference: noop(),
  getPlaybackSourcePreference: returns('auto'),
  isDownloading: false,
  isDeleting: false,
  error: null,
})

const DOWNLOAD_STORAGE_RESULT: UseDownloadStorageResult = frozen({
  storageInfo: null,
  isLoading: false,
  refresh: resolved(undefined),
  formattedSize: '0 B',
  formattedAvailable: '0 B',
  usagePercentage: 0,
})

const EQUALIZER_RESULT: UseEqualizerResult = frozen({
  isEnabled: false,
  bands: [],
  currentPreset: null,
  setEnabled: resolved(true),
  setBandGain: resolved(true),
  setAllBandGains: resolved(true),
  reset: resolved(undefined),
  isLoading: false,
  gainRange: GAIN_RANGE,
})

const EQUALIZER_PRESETS_RESULT: UseEqualizerPresetsResult = frozen({
  presets: [],
  builtInPresets: [],
  customPresets: [],
  applyPreset: resolved(true),
  saveCustomPreset: resolved(true),
  deleteCustomPreset: resolved(true),
  currentPreset: null,
  isLoading: false,
  refreshPresets: noop(),
})

// mockReturnValue / mockImplementation to drive a component into another state
export const useOnChangeTrack: MockedExport<'useOnChangeTrack'> = returns(
  frozen({ track: null, reason: undefined, isReady: false })
)

export const useOnPlaybackStateChange: MockedExport<'useOnPlaybackStateChange'> =
  returns(
    frozen({
      state: 'stopped',
      reason: undefined,
      isReady: false,
    })
  )

export const useOnSeek: MockedExport<'useOnSeek'> = returns(
  frozen({ position: undefined, totalDuration: undefined })
)

export const useOnPlaybackProgressChange: MockedExport<'useOnPlaybackProgressChange'> =
  returns(
    frozen({
      position: 0,
      totalDuration: 0,
      isManuallySeeked: undefined,
    })
  )

export const useTimedMetadata: MockedExport<'useTimedMetadata'> =
  returns(undefined)

export const useOnNotificationButtonPress: MockedExport<'useOnNotificationButtonPress'> =
  noop()

export const useAndroidAutoConnection: MockedExport<'useAndroidAutoConnection'> =
  returns(frozen({ isConnected: false }))

export const useAudioDevices: MockedExport<'useAudioDevices'> = returns(
  frozen({ devices: [] })
)

export const useNowPlaying: MockedExport<'useNowPlaying'> =
  returns(DEFAULT_PLAYER_STATE)

export const usePlaylist: MockedExport<'usePlaylist'> = returns(PLAYLIST_RESULT)

export const useActualQueue: MockedExport<'useActualQueue'> =
  returns(ACTUAL_QUEUE_RESULT)

export const useIsCasting: MockedExport<'useIsCasting'> = returns(false)

export const useCastState: MockedExport<'useCastState'> =
  returns(CAST_STATE_RESULT)

export const useDownloadProgress: MockedExport<'useDownloadProgress'> = returns(
  DOWNLOAD_PROGRESS_RESULT
)

export const useDownloadedTracks: MockedExport<'useDownloadedTracks'> = returns(
  DOWNLOADED_TRACKS_RESULT
)

export const useDownloadActions: MockedExport<'useDownloadActions'> = returns(
  DOWNLOAD_ACTIONS_RESULT
)

export const useDownloadStorage: MockedExport<'useDownloadStorage'> = returns(
  DOWNLOAD_STORAGE_RESULT
)

export const useEqualizer: MockedExport<'useEqualizer'> =
  returns(EQUALIZER_RESULT)

export const useEqualizerPresets: MockedExport<'useEqualizerPresets'> = returns(
  EQUALIZER_PRESETS_RESULT
)

export const CastButton: MockedExport<'CastButton'> = mock(
  (_props: NitroPlayer.CastButtonProps) => null
)

export const AndroidAutoMediaLibraryHelper: {
  [K in keyof typeof NitroPlayer.AndroidAutoMediaLibraryHelper]: jest.MockedFunction<
    (typeof NitroPlayer.AndroidAutoMediaLibraryHelper)[K]
  >
} = {
  set: noop(),
  clear: noop(),
  setChildrenLoader: noop(),
  setSearchHandler: noop(),
  setSessionButtons: noop(),
  onSessionButtonPress: noop(),
  onPlaybackResumption: noop(),
  // Opt in with mockReturnValue(true) so the Android Auto path doesn't run in every test
  isAvailable: returns(false),
}

type AssertNever<T extends never> = T
/** Fails to compile when the package gains a runtime export this mock lacks */
export type MissingMockExports = AssertNever<
  Exclude<keyof typeof NitroPlayer, keyof typeof Mock>
>
