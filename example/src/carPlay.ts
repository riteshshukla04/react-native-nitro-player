import { Platform } from 'react-native';
import {
  CarPlayHelper,
  PlayerQueue,
  TrackPlayer,
  type CarPlayListItem,
  type CarPlayTemplate,
  type TrackItem,
} from 'react-native-nitro-player';
import { sampleTracks1, sampleTracks2 } from './data/sampleTracks';

const GENRES = [
  { name: 'Lofi', icon: 'headphones' },
  { name: 'Synthwave', icon: 'waveform' },
  { name: 'Ambient', icon: 'cloud' },
  { name: 'Jazz', icon: 'music.quarternote.3' },
  { name: 'Piano', icon: 'pianokeys' },
  { name: 'Rock', icon: 'guitars' },
];
const LOOKAHEAD = 'CarPlay Lookahead';

// No URLs: fetchStreamUrl hands them out while the player looks ahead, even with no screen open
const lookaheadTracks: TrackItem[] = Array.from({ length: 12 }, (_, i) => ({
  id: `cp-${i + 1}`,
  title: `${GENRES[i % GENRES.length]!.name} Session ${
    Math.floor(i / GENRES.length) + 1
  }`,
  artist: GENRES[i % GENRES.length]!.name,
  album: 'Fetched at runtime',
  duration: 0,
  url: '',
  artwork: '',
}));

// Stands in for the app's backend
const fetchStreamUrl = (track: TrackItem) =>
  new Promise<string>(resolve =>
    setTimeout(
      () =>
        resolve(
          `https://www.soundhelix.com/examples/mp3/SoundHelix-Song-${
            (Number(track.id.slice(3)) % 16) + 1
          }.mp3`,
        ),
      2000,
    ),
  );

const delay = (ms: number) =>
  new Promise<void>(resolve => setTimeout(resolve, ms));

async function ensurePlaylist(
  name: string,
  description: string,
  tracks: TrackItem[],
) {
  const existing = PlayerQueue.getAllPlaylists().find(p => p.name === name);
  if (existing) return existing.id;
  const id = await PlayerQueue.createPlaylist(
    name,
    description,
    tracks[0]?.artwork ?? undefined,
  );
  await PlayerQueue.addTracksToPlaylist(id, tracks);
  return id;
}

async function ensureLookaheadPlaylist() {
  const existing = PlayerQueue.getAllPlaylists().find(
    p => p.name === LOOKAHEAD,
  );
  if (!existing) {
    const id = await PlayerQueue.createPlaylist(
      LOOKAHEAD,
      'URLs fetched while you listen',
    );
    await PlayerQueue.addTracksToPlaylist(id, lookaheadTracks);
    return id;
  }
  // Emptied each launch so URLs arrive at runtime again; same id, so CarPlay keeps its screens
  const { currentPlaylistId } = await TrackPlayer.getState();
  if (existing.id !== currentPlaylistId) {
    await PlayerQueue.removeTracksFromPlaylist(
      existing.id,
      existing.tracks.map(t => t.id),
    );
    await PlayerQueue.addTracksToPlaylist(existing.id, lookaheadTracks);
  }
  return existing.id;
}

const trackRow = (playlistId: string, track: TrackItem): CarPlayListItem => ({
  id: `${playlistId}:${track.id}`,
  title: track.title,
  subtitle: track.artist,
  image: track.artwork ?? undefined,
  playlistId,
  trackId: track.id,
});

async function playRandom(playlistIds: string[]) {
  const candidates = playlistIds.flatMap(
    id =>
      PlayerQueue.getPlaylist(id)?.tracks.map(track => ({ id, track })) ?? [],
  );
  const pick = candidates[Math.floor(Math.random() * candidates.length)];
  if (!pick) return;
  await TrackPlayer.playSong(pick.track.id, pick.id);
  await TrackPlayer.play();
  CarPlayHelper.showNowPlaying();
}

// Module scope, not a component: CarPlay can start the app without any UI
export async function registerCarPlay() {
  if (Platform.OS !== 'ios') return;

  TrackPlayer.onTracksNeedUpdate(async tracks => {
    const ours = tracks.filter(t => t.id.startsWith('cp-'));
    if (ours.length === 0) return;
    const urls = await Promise.all(ours.map(fetchStreamUrl));
    await TrackPlayer.updateTracks(
      ours.map((t, i) => ({ ...t, url: urls[i]! })),
    );
  });

  const chillId = await ensurePlaylist(
    'Chill Vibes',
    'Relaxing music',
    sampleTracks1,
  );
  const natureId = await ensurePlaylist(
    'Nature Sounds',
    'Sounds of nature',
    sampleTracks2,
  );
  const lookaheadId = await ensureLookaheadPlaylist();

  CarPlayHelper.set({
    templates: [
      {
        type: 'list',
        id: 'home',
        title: 'Home',
        tab: { title: 'Home', image: 'house' },
        barButtons: [{ id: 'shuffle-all', image: 'shuffle' }],
        sections: [
          {
            header: 'Jump back in',
            items: [
              {
                type: 'imageRow',
                style: 'card',
                id: 'mixes',
                title: 'Your mixes',
                elements: [
                  {
                    id: 'mix-chill',
                    title: 'Chill',
                    subtitle: 'Lofi and downtempo',
                    image: sampleTracks1[0]!.artwork!,
                    fillImage: true,
                    tintColor: '#3A2A5C',
                    playlistId: chillId,
                    playPlaylist: true,
                  },
                  {
                    id: 'mix-nature',
                    title: 'Nature',
                    subtitle: 'Rain, birds and wind',
                    image: 'leaf',
                    tintColor: '#1F5C3A',
                    playlistId: natureId,
                    playPlaylist: true,
                  },
                  {
                    id: 'mix-lookahead',
                    title: 'Lookahead',
                    subtitle: 'URLs fetched while you listen',
                    image: 'antenna.radiowaves.left.and.right',
                    tintColor: '#5C3A1F',
                    playlistId: lookaheadId,
                    playPlaylist: true,
                  },
                ],
              },
              {
                type: 'imageRow',
                style: 'image-grid',
                id: 'artists',
                title: 'Artists',
                elements: sampleTracks1.slice(0, 4).map(t => ({
                  id: `artist:${t.artist}`,
                  title: t.artist,
                  image: t.artwork ?? 'music.mic',
                  imageShape: 'circle',
                })),
              },
            ],
          },
          {
            header: 'Playlists',
            items: [
              {
                id: 'chill',
                title: 'Chill Vibes',
                subtitle: 'Relaxing music',
                image: sampleTracks1[0]!.artwork!,
                playlistId: chillId,
              },
              {
                id: 'nature',
                title: 'Nature Sounds',
                subtitle: 'Sounds of nature',
                image: 'leaf',
                playlistId: natureId,
              },
              {
                id: 'lookahead',
                title: LOOKAHEAD,
                subtitle: 'URLs fetched while you listen',
                image: 'antenna.radiowaves.left.and.right',
                playlistId: lookaheadId,
              },
            ],
          },
          {
            items: [
              {
                type: 'imageRow',
                id: 'quick-picks',
                title: 'Quick picks',
                multipleLines: true,
                elements: sampleTracks1.map(t => ({
                  id: `quick:${t.id}`,
                  image: t.artwork ?? 'music.note',
                  title: t.title,
                  subtitle: t.artist,
                  playlistId: chillId,
                  trackId: t.id,
                })),
              },
            ],
          },
        ],
      },
      // Filled by the loader below, also on a cold start from the car
      {
        type: 'grid',
        id: 'browse',
        title: 'Browse',
        tab: { systemItem: 'featured' },
        lazy: true,
      },
      {
        type: 'list',
        id: 'library',
        title: 'Library',
        source: 'playlists',
        tab: { systemItem: 'favorites' },
      },
      {
        type: 'list',
        id: 'queue',
        title: 'Queue',
        source: 'queue',
        tab: { title: 'Queue', image: 'list.bullet' },
      },
    ],
    nowPlaying: { upNextTitle: 'Queue', albumArtist: true },
    texts: { trackCount: { one: '{count} song', other: '{count} songs' } },
    placeholders: { artwork: 'music.quarternote.3' },
  });

  CarPlayHelper.setTemplateLoader(
    async (itemId): Promise<CarPlayTemplate | null> => {
      if (itemId === 'browse') {
        await delay(800);
        return {
          type: 'grid',
          id: 'browse',
          title: 'Browse',
          barButtons: [{ id: 'refresh-browse', image: 'arrow.clockwise' }],
          buttons: [
            ...GENRES.map(g => ({
              id: `genre:${g.name}`,
              title: g.name,
              image: g.icon,
              loadTemplate: true,
            })),
            { id: 'surprise', title: 'Surprise me', image: 'dice' },
          ],
        };
      }
      if (!itemId.startsWith('genre:')) return null;
      const genre = itemId.slice('genre:'.length);
      await delay(400);
      return {
        type: 'list',
        id: itemId,
        title: genre,
        emptyTitle: `No ${genre} yet`,
        sections: [
          {
            items: lookaheadTracks
              .filter(t => t.artist === genre)
              .map(t => trackRow(lookaheadId, t)),
          },
        ],
      };
    },
  );

  CarPlayHelper.onSelect(id => {
    if (id === 'shuffle-all' || id === 'surprise')
      playRandom([chillId, natureId, lookaheadId]);
    if (id === 'refresh-browse') CarPlayHelper.reload('browse');
    if (id.startsWith('artist:')) showArtist(id.slice('artist:'.length));
  });

  CarPlayHelper.onAlbumArtistPress(track => showArtist(track.artist));
}

function showArtist(artist: string) {
  const seen = new Set<string>();
  const items = PlayerQueue.getAllPlaylists()
    .flatMap(p =>
      p.tracks.filter(t => t.artist === artist).map(t => trackRow(p.id, t)),
    )
    .filter(row => !seen.has(row.trackId!) && !!seen.add(row.trackId!));
  CarPlayHelper.push({
    type: 'list',
    id: `artist:${artist}`,
    title: artist,
    sections: [{ items }],
  });
}
