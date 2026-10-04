import { Platform } from 'react-native';
import {
  AndroidAutoMediaLibraryHelper,
  PlayerQueue,
  TrackPlayer,
  type MediaItem,
  type TrackItem,
} from 'react-native-nitro-player';

const DEMO_PLAYLIST = 'Car demo';
const ARTISTS = ['Aurora', 'Beacon', 'Cascade'];

// Empty URLs: resolved on demand by onTracksNeedUpdate in App.tsx
const tracks: TrackItem[] = Array.from({ length: 12 }, (_, i) => ({
  id: `car-${i + 1}`,
  title: `Car Track ${i + 1}`,
  artist: ARTISTS[i % ARTISTS.length],
  album: 'Car Demo',
  duration: 200,
  url: '',
  artwork: '',
}));

const playable = (playlistId: string, track: TrackItem): MediaItem => ({
  id: `${playlistId}:${track.id}`,
  title: track.title,
  subtitle: track.artist,
  isPlayable: true,
  mediaType: 'audio',
});

let favourite = false;
const showHeart = () =>
  AndroidAutoMediaLibraryHelper.setSessionButtons([
    {
      action: 'favourite',
      title: 'Favourite',
      icon: favourite ? 'heart_filled' : 'heart',
    },
  ]);

async function demoPlaylistId(): Promise<string> {
  const { currentPlaylistId } = await TrackPlayer.getState();
  const existing = PlayerQueue.getAllPlaylists().find(
    (p) => p.name === DEMO_PLAYLIST
  );
  if (existing && existing.id === currentPlaylistId) return existing.id;
  // Recreated each launch so its URLs start out lazy again
  if (existing) await PlayerQueue.deletePlaylist(existing.id);
  const id = await PlayerQueue.createPlaylist(DEMO_PLAYLIST);
  await PlayerQueue.addTracksToPlaylist(id, tracks);
  return id;
}

export async function registerAndroidAuto() {
  if (Platform.OS !== 'android') return;
  const playlistId = await demoPlaylistId();

  AndroidAutoMediaLibraryHelper.set({
    layoutType: 'list',
    rootItems: [
      {
        id: 'demo',
        title: DEMO_PLAYLIST,
        isPlayable: false,
        mediaType: 'playlist',
        playlistId,
      },
      {
        id: 'artists',
        title: 'Artists',
        isPlayable: false,
        mediaType: 'folder',
        children: [],
      },
    ],
  });

  AndroidAutoMediaLibraryHelper.setChildrenLoader(async (parentId) => {
    if (parentId === 'artists') {
      return ARTISTS.map((name): MediaItem => ({
        id: `artist:${name}`,
        title: name,
        isPlayable: false,
        mediaType: 'folder',
        children: [],
        groupTitle: 'Artists',
      }));
    }
    const name = parentId.startsWith('artist:') ? parentId.slice(7) : null;
    if (!name) return null;
    return tracks
      .filter((t) => t.artist === name)
      .map((t) => playable(playlistId, t));
  });

  AndroidAutoMediaLibraryHelper.setSearchHandler(async (query) =>
    tracks
      .filter((t) =>
        `${t.title} ${t.artist}`.toLowerCase().includes(query.toLowerCase())
      )
      .map((t) => playable(playlistId, t))
  );

  AndroidAutoMediaLibraryHelper.onSessionButtonPress(() => {
    favourite = !favourite;
    showHeart();
  });
  showHeart();
}
