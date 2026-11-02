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
import type { PlayerState } from './types/PlayerQueue'
import type {
  DownloadQueueStatus,
  DownloadStorageInfo,
} from './types/DownloadTypes'

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

// Args come from the property they are assigned to, so call assertions stay typed
const resolved = <T, A extends any[]>(value: T): jest.Mock<Promise<T>, A> =>
  jest.fn<Promise<T>, A>(async () => value)
const returns = <T, A extends any[]>(value: T): jest.Mock<T, A> =>
  jest.fn<T, A>(() => value)

const DEFAULT_PLAYER_STATE: PlayerState = {
  currentTrack: null,
  currentPosition: 0,
  totalDuration: 0,
  currentState: 'stopped',
  currentPlaylistId: null,
  currentIndex: -1,
  currentPlayingType: 'not-playing',
}

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
  onPlaylistsChanged: jest.fn(),
  onPlaylistChanged: jest.fn(),
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
  getActualQueue: resolved([]),
  getState: jest.fn(() => Promise.resolve({ ...DEFAULT_PLAYER_STATE })),
  setRepeatMode: resolved(undefined),
  getRepeatMode: returns('off'),
  configure: resolved(undefined),
  onChangeTrack: jest.fn(),
  onPlaybackStateChange: jest.fn(),
  onSeek: jest.fn(),
  onPlaybackProgressChange: jest.fn(),
  onTimedMetadata: jest.fn(),
  appStartedWithNotification: jest.fn(),
  onAndroidAutoConnectionChange: jest.fn(),
  isAndroidAutoConnected: returns(false),
  setNotificationButtonState: jest.fn(),
  onNotificationButtonPress: jest.fn(),
  setVolume: resolved(undefined),
  updateTracks: resolved(undefined),
  getTracksById: resolved([]),
  getTracksNeedingUrls: resolved([]),
  getNextTracks: resolved([]),
  getCurrentTrackIndex: resolved(-1),
  onTracksNeedUpdate: jest.fn(),
  setPlaybackSpeed: resolved(undefined),
  getPlaybackSpeed: resolved(1),
  removeFromPlayNext: resolved(true),
  removeFromUpNext: resolved(true),
  clearPlayNext: resolved(undefined),
  clearUpNext: resolved(undefined),
  reorderTemporaryTrack: resolved(true),
  getPlayNextQueue: resolved([]),
  getUpNextQueue: resolved([]),
  onTemporaryQueueChange: jest.fn(),
}

// Platform-only modules are always present here so tests on either platform can assert on them
export const AndroidAutoMediaLibrary: MockedHybridObject<AndroidAutoMediaLibraryType> =
  {
    setMediaLibrary: resolved(undefined),
    clearMediaLibrary: resolved(undefined),
    onLoadChildren: jest.fn(),
    onSearch: jest.fn(),
    resolveRequest: jest.fn(),
    setSessionButtons: jest.fn(),
    onSessionButtonPress: jest.fn(),
    onPlaybackResumption: jest.fn(),
  }

export const AudioDevices: MockedHybridObject<AudioDevicesType> = {
  getAudioDevices: returns([]),
  setAudioDevice: resolved(undefined),
}

export const AudioRoutePicker: MockedHybridObject<AudioRoutePickerType> = {
  showRoutePicker: jest.fn(),
}

export const Cast: MockedHybridObject<CastType> = {
  configure: resolved(undefined),
  isCasting: returns(false),
  getCastState: returns('no_devices_available'),
  getCastDeviceName: returns(null),
  showCastPicker: jest.fn(),
  endCastSession: resolved(undefined),
  onCastStateChange: jest.fn(),
}

export const DownloadManager: MockedHybridObject<DownloadManagerType> = {
  configure: jest.fn(),
  getConfig: jest.fn(() => ({})),
  downloadTrack: resolved(''),
  downloadPlaylist: resolved([]),
  pauseDownload: resolved(undefined),
  resumeDownload: resolved(undefined),
  cancelDownload: resolved(undefined),
  retryDownload: resolved(undefined),
  pauseAllDownloads: resolved(undefined),
  resumeAllDownloads: resolved(undefined),
  cancelAllDownloads: resolved(undefined),
  getDownloadTask: returns(null),
  getActiveDownloads: returns([]),
  getQueueStatus: jest.fn(() => ({ ...EMPTY_QUEUE_STATUS })),
  isDownloading: returns(false),
  getDownloadState: returns(null),
  isTrackDownloaded: resolved(false),
  isPlaylistDownloaded: resolved(false),
  isPlaylistPartiallyDownloaded: resolved(false),
  getDownloadedTrack: resolved(null),
  getAllDownloadedTracks: resolved([]),
  getDownloadedPlaylist: resolved(null),
  getAllDownloadedPlaylists: resolved([]),
  getLocalPath: resolved(null),
  deleteDownloadedTrack: resolved(undefined),
  deleteDownloadedPlaylist: resolved(undefined),
  deleteAllDownloads: resolved(undefined),
  getStorageInfo: jest.fn(() => Promise.resolve({ ...EMPTY_STORAGE_INFO })),
  syncDownloads: resolved(0),
  setPlaybackSourcePreference: jest.fn(),
  getPlaybackSourcePreference: returns('auto'),
  getEffectiveUrl: jest.fn((track) => Promise.resolve(track.url)),
  onDownloadProgress: jest.fn(),
  onDownloadStateChange: jest.fn(),
  onDownloadComplete: jest.fn(),
}

export const Equalizer: MockedHybridObject<EqualizerType> = {
  setEnabled: resolved(undefined),
  isEnabled: returns(false),
  getBands: resolved([]),
  setBandGain: resolved(undefined),
  setAllBandGains: resolved(undefined),
  getBandRange: jest.fn(() => ({ ...GAIN_RANGE })),
  getPresets: returns([]),
  getBuiltInPresets: returns([]),
  getCustomPresets: returns([]),
  applyPreset: resolved(undefined),
  getCurrentPresetName: returns(null),
  saveCustomPreset: resolved(undefined),
  deleteCustomPreset: resolved(undefined),
  getState: jest.fn(() =>
    Promise.resolve({ enabled: false, bands: [], currentPreset: null })
  ),
  reset: resolved(undefined),
  onEnabledChange: jest.fn(),
  onBandChange: jest.fn(),
  onPresetChange: jest.fn(),
}

// Hooks return their initial state; mockReturnValue to drive a component into another one
export const useOnChangeTrack: MockedExport<'useOnChangeTrack'> = jest.fn(
  () => ({ track: null, reason: undefined, isReady: false })
)

export const useOnPlaybackStateChange: MockedExport<'useOnPlaybackStateChange'> =
  jest.fn(() => ({ state: 'stopped', reason: undefined, isReady: false }))

export const useOnSeek: MockedExport<'useOnSeek'> = jest.fn(() => ({
  position: undefined,
  totalDuration: undefined,
}))

export const useOnPlaybackProgressChange: MockedExport<'useOnPlaybackProgressChange'> =
  jest.fn(() => ({
    position: 0,
    totalDuration: 0,
    isManuallySeeked: undefined,
  }))

export const useTimedMetadata: MockedExport<'useTimedMetadata'> = jest.fn(
  () => undefined
)

export const useOnNotificationButtonPress: MockedExport<'useOnNotificationButtonPress'> =
  jest.fn()

export const useAndroidAutoConnection: MockedExport<'useAndroidAutoConnection'> =
  jest.fn(() => ({ isConnected: false }))

export const useAudioDevices: MockedExport<'useAudioDevices'> = jest.fn(() => ({
  devices: [],
}))

export const useNowPlaying: MockedExport<'useNowPlaying'> = jest.fn(() => ({
  ...DEFAULT_PLAYER_STATE,
}))

export const usePlaylist: MockedExport<'usePlaylist'> = jest.fn(() => ({
  currentPlaylist: null,
  currentPlaylistId: null,
  allPlaylists: [],
  allTracks: [],
  isLoading: false,
  refreshPlaylists: jest.fn(),
}))

export const useActualQueue: MockedExport<'useActualQueue'> = jest.fn(() => ({
  queue: [],
  refreshQueue: jest.fn(),
  isLoading: false,
}))

export const useIsCasting: MockedExport<'useIsCasting'> = jest.fn(() => false)

export const useCastState: MockedExport<'useCastState'> = jest.fn(() => ({
  state: 'no_devices_available',
  deviceName: null,
  isCasting: false,
  isReady: false,
}))

export const useDownloadProgress: MockedExport<'useDownloadProgress'> = jest.fn(
  () => ({
    progressMap: new Map(),
    progressList: [],
    overallProgress: 0,
    isDownloading: false,
    getProgress: jest.fn(() => undefined),
  })
)

export const useDownloadedTracks: MockedExport<'useDownloadedTracks'> = jest.fn(
  () => ({
    downloadedTracks: [],
    downloadedPlaylists: [],
    isTrackDownloaded: jest.fn(() => false),
    isPlaylistDownloaded: jest.fn(() => false),
    isPlaylistPartiallyDownloaded: jest.fn(() => false),
    getDownloadedTrack: jest.fn(() => undefined),
    getDownloadedPlaylist: jest.fn(() => undefined),
    refresh: jest.fn(),
    isLoading: false,
  })
)

export const useDownloadActions: MockedExport<'useDownloadActions'> = jest.fn(
  () => ({
    downloadTrack: resolved(''),
    downloadPlaylist: resolved([]),
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
    configure: jest.fn(),
    setPlaybackSourcePreference: jest.fn(),
    getPlaybackSourcePreference: returns('auto'),
    isDownloading: false,
    isDeleting: false,
    error: null,
  })
)

export const useDownloadStorage: MockedExport<'useDownloadStorage'> = jest.fn(
  () => ({
    storageInfo: null,
    isLoading: false,
    refresh: resolved(undefined),
    formattedSize: '0 B',
    formattedAvailable: '0 B',
    usagePercentage: 0,
  })
)

export const useEqualizer: MockedExport<'useEqualizer'> = jest.fn(() => ({
  isEnabled: false,
  bands: [],
  currentPreset: null,
  setEnabled: resolved(true),
  setBandGain: resolved(true),
  setAllBandGains: resolved(true),
  reset: resolved(undefined),
  isLoading: false,
  gainRange: { ...GAIN_RANGE },
}))

export const useEqualizerPresets: MockedExport<'useEqualizerPresets'> = jest.fn(
  () => ({
    presets: [],
    builtInPresets: [],
    customPresets: [],
    applyPreset: resolved(true),
    saveCustomPreset: resolved(true),
    deleteCustomPreset: resolved(true),
    currentPreset: null,
    isLoading: false,
    refreshPresets: jest.fn(),
  })
)

export const CastButton: MockedExport<'CastButton'> = jest.fn(
  (_props: NitroPlayer.CastButtonProps) => null
)

export const AndroidAutoMediaLibraryHelper: {
  [K in keyof typeof NitroPlayer.AndroidAutoMediaLibraryHelper]: jest.MockedFunction<
    (typeof NitroPlayer.AndroidAutoMediaLibraryHelper)[K]
  >
} = {
  set: jest.fn(),
  clear: jest.fn(),
  setChildrenLoader: jest.fn(),
  setSearchHandler: jest.fn(),
  setSessionButtons: jest.fn(),
  onSessionButtonPress: jest.fn(),
  onPlaybackResumption: jest.fn(),
  isAvailable: returns(true),
}

type AssertNever<T extends never> = T
/** Fails to compile when the package gains a runtime export this mock lacks */
export type MissingMockExports = AssertNever<
  Exclude<keyof typeof NitroPlayer, keyof typeof Mock>
>
