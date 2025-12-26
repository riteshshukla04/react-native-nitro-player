/**
 * Sample React Native App
 * https://github.com/facebook/react-native
 *
 * @format
 */

import { useEffect, useState } from 'react';
import {
  StyleSheet,
  View,
  Text,
  ScrollView,
  TouchableOpacity,
} from 'react-native';
import {
  PlayerQueue,
  TrackPlayer,
  useOnChangeTrack,
  useOnPlaybackStateChange,
  useOnSeek,
  useOnPlaybackProgressChange,
  useAndroidAutoConnection,
} from 'react-native-nitro-player';
import type {
  TrackItem,
  QueueOperation,
  PlayerState,
  Playlist,
} from '../react-native-nitro-player/src/types/PlayerQueue';

function App() {
  return <AppContent />;
}

TrackPlayer.configure({
  androidAutoEnabled: true,
  carPlayEnabled: false,
  showInNotification: true,
});

const sampleTracks1: TrackItem[] = [
  {
    id: '1',
    title: 'Sunset Drive',
    artist: 'Lofi Beats',
    album: 'Chill Vibes',
    duration: 182.0,
    url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
    artwork:
      'https://img.freepik.com/free-photo/sunset-time-tropical-beach-sea-with-coconut-palm-tree_74190-1075.jpg?semt=ais_hybrid&w=740&q=80',
  },
  {
    id: '2',
    title: 'Midnight Rain',
    artist: 'Nightfall',
    album: 'Dreamscapes',
    duration: 204.0,
    url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
    artwork: 'https://via.placeholder.com/150/FF0000/FFFFFF?Text=Midnight',
  },
  {
    id: '3',
    title: 'City Lights',
    artist: 'Synthwave Lab',
    album: 'Neon Streets',
    duration: 195.5,
    url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3',
    artwork: 'https://via.placeholder.com/150/00FF00/000000?Text=City',
  },
];

const sampleTracks2: TrackItem[] = [
  {
    id: '4',
    title: 'Ocean Waves',
    artist: 'Nature Sounds',
    album: 'Relaxation',
    duration: 300.0,
    url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-4.mp3',
    artwork: 'https://via.placeholder.com/150/0000FF/FFFFFF?Text=Ocean',
  },
  {
    id: '5',
    title: 'Forest Walk',
    artist: 'Nature Sounds',
    album: 'Relaxation',
    duration: 280.0,
    url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-5.mp3',
    artwork: 'https://via.placeholder.com/150/008000/FFFFFF?Text=Forest',
  },
];

function AppContent() {
  const [playlists, setPlaylists] = useState<Playlist[]>([]);
  const [currentPlaylist, setCurrentPlaylist] = useState<Playlist | null>(null);
  const [currentPlaylistId, setCurrentPlaylistId] = useState<string | null>(
    null,
  );
  const [lastOperation, setLastOperation] = useState<
    QueueOperation | undefined
  >(undefined);
  const [playerState, setPlayerState] = useState<PlayerState | undefined>(
    undefined,
  );

  // Use hooks to get player state directly
  const { track: currentTrack, reason: trackChangeReason } = useOnChangeTrack();
  const { state: playbackState, reason: stateChangeReason } =
    useOnPlaybackStateChange();
  const { position: lastSeekPosition, totalDuration: lastSeekDuration } =
    useOnSeek();
  const {
    position: playbackPosition,
    totalDuration,
    isManuallySeeked,
  } = useOnPlaybackProgressChange();
  const { isConnected: isAndroidAutoConnected } = useAndroidAutoConnection();

  // Log changes for debugging
  useEffect(() => {
    if (currentTrack) {
      console.log('Track changed:', currentTrack, trackChangeReason);
    }
  }, [currentTrack, trackChangeReason]);

  useEffect(() => {
    if (playbackState !== undefined) {
      console.log('Playback state changed:', playbackState, stateChangeReason);
    }
  }, [playbackState, stateChangeReason]);

  useEffect(() => {
    if (lastSeekPosition !== undefined) {
      console.log('Seek:', lastSeekPosition, lastSeekDuration);
    }
  }, [lastSeekPosition, lastSeekDuration]);

  useEffect(() => {
    console.log('Initializing player');

    // Get initial playlists
    const initialPlaylists = PlayerQueue.getAllPlaylists();
    setPlaylists(initialPlaylists);

    // Get current playlist ID
    const currentId = PlayerQueue.getCurrentPlaylistId();
    setCurrentPlaylistId(currentId);
    if (currentId) {
      const playlist = PlayerQueue.getPlaylist(currentId);
      setCurrentPlaylist(playlist);
    }

    // Listen to playlist changes
    PlayerQueue.onPlaylistsChanged((updatedPlaylists, operation) => {
      console.log('Playlists changed:', operation, updatedPlaylists);
      setPlaylists(updatedPlaylists);
      setLastOperation(operation);

      // Update current playlist if it changed
      const updatedCurrentId = PlayerQueue.getCurrentPlaylistId();
      setCurrentPlaylistId(updatedCurrentId);
      if (updatedCurrentId) {
        const playlist = PlayerQueue.getPlaylist(updatedCurrentId);
        setCurrentPlaylist(playlist);
      }
    });
  }, []);

  const handleCreatePlaylist1 = () => {
    console.log('Creating playlist 1');
    const playlistId = PlayerQueue.createPlaylist(
      'Chill Vibes',
      'Relaxing music for your day',
      sampleTracks1[0].artwork || undefined,
    );
    PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks1);
    const updatedPlaylists1 = PlayerQueue.getAllPlaylists();
    setPlaylists(updatedPlaylists1);
  };

  const handleCreatePlaylist2 = () => {
    console.log('Creating playlist 2');
    const playlistId = PlayerQueue.createPlaylist(
      'Nature Sounds',
      'Sounds of nature',
      sampleTracks2[0].artwork || undefined,
    );
    PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks2);
    const updatedPlaylists2 = PlayerQueue.getAllPlaylists();
    setPlaylists(updatedPlaylists2);
  };

  const handleLoadPlaylist = (playlistId: string) => {
    console.log('Loading playlist:', playlistId);
    PlayerQueue.loadPlaylist(playlistId);
    const playlist = PlayerQueue.getPlaylist(playlistId);
    setCurrentPlaylist(playlist);
    setCurrentPlaylistId(playlistId);
  };

  const handleAddTracksToPlaylist = (playlistId: string) => {
    console.log('Adding tracks to playlist:', playlistId);
    const newTracks: TrackItem[] = [
      {
        id: `${Date.now()}_1`,
        title: 'New Track 1',
        artist: 'Unknown Artist',
        album: 'Unknown Album',
        duration: 180.0,
        url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
        artwork: 'https://via.placeholder.com/150/FFFF00/000000?Text=New1',
      },
      {
        id: `${Date.now()}_2`,
        title: 'New Track 2',
        artist: 'Unknown Artist',
        album: 'Unknown Album',
        duration: 200.0,
        url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
        artwork: 'https://via.placeholder.com/150/00FFFF/000000?Text=New2',
      },
    ];
    PlayerQueue.addTracksToPlaylist(playlistId, newTracks);
    const updatedPlaylists3 = PlayerQueue.getAllPlaylists();
    setPlaylists(updatedPlaylists3);
  };

  const handleAddTrackToPlaylist = (playlistId: string) => {
    console.log('Adding track to playlist:', playlistId);
    const newTrack: TrackItem = {
      id: `${Date.now()}`,
      title: 'Single New Track',
      artist: 'Unknown Artist',
      album: 'Unknown Album',
      duration: 190.0,
      url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3',
      artwork: 'https://via.placeholder.com/150/FF00FF/000000?Text=Single',
    };
    PlayerQueue.addTrackToPlaylist(playlistId, newTrack);
    const updatedPlaylists4 = PlayerQueue.getAllPlaylists();
    setPlaylists(updatedPlaylists4);
  };

  const handleDeletePlaylist = (playlistId: string) => {
    console.log('Deleting playlist:', playlistId);
    PlayerQueue.deletePlaylist(playlistId);
    const updatedPlaylists5 = PlayerQueue.getAllPlaylists();
    setPlaylists(updatedPlaylists5);
    if (currentPlaylistId === playlistId) {
      setCurrentPlaylist(null);
      setCurrentPlaylistId(null);
    }
  };

  const handleRemoveTrack = (playlistId: string, trackId: string) => {
    console.log('Removing track:', trackId, 'from playlist:', playlistId);
    PlayerQueue.removeTrackFromPlaylist(playlistId, trackId);
    const updatedPlaylists6 = PlayerQueue.getAllPlaylists();
    setPlaylists(updatedPlaylists6);
    if (currentPlaylistId === playlistId) {
      const playlist = PlayerQueue.getPlaylist(playlistId);
      setCurrentPlaylist(playlist);
    }
  };

  const handlePlay = () => TrackPlayer.play();
  const handlePause = () => TrackPlayer.pause();
  const handleSkipNext = () => TrackPlayer.skipToNext();
  const handleSkipPrevious = () => TrackPlayer.skipToPrevious();
  const handleSeekTo30 = () => TrackPlayer.seek(30);
  const handleSeekTo60 = () => TrackPlayer.seek(60);
  const handleSeekToLast10 = () => {
    if (totalDuration > 10) {
      TrackPlayer.seek(totalDuration - 10);
    }
  };

  const handleGetState = () => {
    const state = TrackPlayer.getState();
    console.log('Player State:', state);
    setPlayerState(state);
  };

  const handlePlaySongFromPlaylist = (songId: string, playlistId: string) => {
    console.log('Playing song:', songId, 'from playlist:', playlistId);
    TrackPlayer.playSong(songId, playlistId);
  };

  const handlePlaySongAuto = (songId: string) => {
    console.log('Playing song:', songId, '(auto-find playlist)');
    TrackPlayer.playSong(songId);
  };

  return (
    <View style={styles.container}>
      <ScrollView
        style={styles.scrollView}
        contentContainerStyle={styles.content}
      >
        <Text style={styles.title}>Nitro Player Example</Text>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Player Controls</Text>

          <View style={styles.infoBox}>
            <Text style={styles.infoText}>
              💡 Tip: Click on any track in the playlists below to play it!
            </Text>
            <Text style={styles.infoSubText}>
              • Click track name = Play from that playlist
            </Text>
            <Text style={styles.infoSubText}>
              • Click 🎵 = Auto-find and play
            </Text>
          </View>

          {/* Android Auto Connection Indicator */}
          <View
            style={[
              styles.connectionIndicator,
              isAndroidAutoConnected && styles.connectionIndicatorConnected,
            ]}
          >
            <Text style={styles.connectionText}>
              Android Auto:{' '}
              {isAndroidAutoConnected ? '🚗 CONNECTED' : '📱 Disconnected'}
            </Text>
          </View>

          <View style={styles.controlsRow}>
            <TouchableOpacity
              style={styles.controlButton}
              onPress={handleSkipPrevious}
            >
              <Text style={styles.buttonText}>Prev</Text>
            </TouchableOpacity>
            <TouchableOpacity style={styles.controlButton} onPress={handlePlay}>
              <Text style={styles.buttonText}>Play</Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={styles.controlButton}
              onPress={handlePause}
            >
              <Text style={styles.buttonText}>Pause</Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={styles.controlButton}
              onPress={handleSkipNext}
            >
              <Text style={styles.buttonText}>Next</Text>
            </TouchableOpacity>
          </View>
          <View style={styles.controlsRow}>
            <TouchableOpacity
              style={styles.controlButton}
              onPress={handleSeekTo30}
            >
              <Text style={styles.buttonText}>Seek 30s</Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={styles.controlButton}
              onPress={handleSeekTo60}
            >
              <Text style={styles.buttonText}>Seek 60s</Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={styles.controlButton}
              onPress={handleSeekToLast10}
            >
              <Text style={styles.buttonText}>Last 10s</Text>
            </TouchableOpacity>
          </View>
          <View style={styles.controlsRow}>
            <TouchableOpacity
              style={styles.controlButton}
              onPress={handleGetState}
            >
              <Text style={styles.buttonText}>Get State</Text>
            </TouchableOpacity>
          </View>

          <Text style={styles.statusText}>
            State: {playbackState !== undefined ? playbackState : 'None'}
          </Text>
          {currentTrack && (
            <View style={styles.currentTrack}>
              <Text style={styles.currentTrackTitle}>
                Now Playing: {currentTrack.title}
              </Text>
              <Text style={styles.currentTrackArtist}>
                {currentTrack.artist}
              </Text>
            </View>
          )}

          <View style={styles.progressSection}>
            <Text style={styles.progressLabel}>Playback Progress</Text>
            <Text style={styles.progressText}>
              {formatTime(playbackPosition)} / {formatTime(totalDuration)}
            </Text>
            {totalDuration > 0 && (
              <View style={styles.progressBarContainer}>
                <View
                  style={[
                    styles.progressBar,
                    { width: `${(playbackPosition / totalDuration) * 100}%` },
                  ]}
                />
              </View>
            )}
            {isManuallySeeked !== undefined && (
              <Text style={styles.seekIndicator}>
                {isManuallySeeked ? '⏩ Manual Seek' : '▶️ Playing'}
              </Text>
            )}
          </View>

          {lastSeekPosition !== undefined && lastSeekDuration !== undefined && (
            <View style={styles.seekInfo}>
              <Text style={styles.seekLabel}>Last Seek Event:</Text>
              <Text style={styles.seekText}>
                Position: {formatTime(lastSeekPosition)} / Duration:{' '}
                {formatTime(lastSeekDuration)}
              </Text>
            </View>
          )}
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Playlist Management</Text>

          <TouchableOpacity
            style={styles.button}
            onPress={handleCreatePlaylist1}
          >
            <Text style={styles.buttonText}>Create "Chill Vibes" Playlist</Text>
          </TouchableOpacity>

          <TouchableOpacity
            style={styles.button}
            onPress={handleCreatePlaylist2}
          >
            <Text style={styles.buttonText}>
              Create "Nature Sounds" Playlist
            </Text>
          </TouchableOpacity>

          {lastOperation && (
            <Text style={styles.operationText}>
              Last operation: {lastOperation}
            </Text>
          )}
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>
            All Playlists ({playlists.length})
          </Text>
          {playlists.length === 0 ? (
            <Text style={styles.emptyText}>No playlists created yet</Text>
          ) : (
            playlists.map(playlist => (
              <View key={playlist.id} style={styles.playlistItem}>
                <View style={styles.playlistHeader}>
                  <View style={styles.playlistInfo}>
                    <Text style={styles.playlistName}>{playlist.name}</Text>
                    <Text style={styles.playlistDescription}>
                      {playlist.description || 'No description'}
                    </Text>
                    <Text style={styles.playlistTracksCount}>
                      {playlist.tracks.length} tracks
                    </Text>
                  </View>
                  <View style={styles.playlistActions}>
                    <TouchableOpacity
                      style={[
                        styles.smallButton,
                        currentPlaylistId === playlist.id &&
                          styles.activeButton,
                      ]}
                      onPress={() => handleLoadPlaylist(playlist.id)}
                    >
                      <Text style={styles.smallButtonText}>
                        {currentPlaylistId === playlist.id
                          ? '✓ Playing'
                          : 'Play'}
                      </Text>
                    </TouchableOpacity>
                    <TouchableOpacity
                      style={styles.smallButton}
                      onPress={() => handleAddTracksToPlaylist(playlist.id)}
                    >
                      <Text style={styles.smallButtonText}>+ Multiple</Text>
                    </TouchableOpacity>
                    <TouchableOpacity
                      style={styles.smallButton}
                      onPress={() => handleAddTrackToPlaylist(playlist.id)}
                    >
                      <Text style={styles.smallButtonText}>+ One</Text>
                    </TouchableOpacity>
                    <TouchableOpacity
                      style={[styles.smallButton, styles.deleteButton]}
                      onPress={() => handleDeletePlaylist(playlist.id)}
                    >
                      <Text style={styles.smallButtonText}>Delete</Text>
                    </TouchableOpacity>
                  </View>
                </View>
                {playlist.tracks.length > 0 && (
                  <View style={styles.tracksList}>
                    <Text style={styles.tracksListHeader}>
                      Tracks (tap to play):
                    </Text>
                    {playlist.tracks.map((track, index) => (
                      <View key={track.id} style={styles.trackItem}>
                        <Text style={styles.trackIndex}>{index + 1}.</Text>
                        <TouchableOpacity
                          style={styles.trackInfo}
                          onPress={() =>
                            handlePlaySongFromPlaylist(track.id, playlist.id)
                          }
                        >
                          <Text style={styles.trackTitle}>{track.title}</Text>
                          <Text style={styles.trackArtist}>{track.artist}</Text>
                        </TouchableOpacity>
                        <TouchableOpacity
                          style={styles.playTrackButton}
                          onPress={() => handlePlaySongAuto(track.id)}
                        >
                          <Text style={styles.playTrackButtonText}>🎵</Text>
                        </TouchableOpacity>
                        <TouchableOpacity
                          style={styles.removeButton}
                          onPress={() =>
                            handleRemoveTrack(playlist.id, track.id)
                          }
                        >
                          <Text style={styles.removeButtonText}>×</Text>
                        </TouchableOpacity>
                      </View>
                    ))}
                  </View>
                )}
              </View>
            ))
          )}
        </View>

        {currentPlaylist && (
          <View style={styles.section}>
            <Text style={styles.sectionTitle}>Current Playlist</Text>
            <Text style={styles.currentPlaylistName}>
              {currentPlaylist.name}
            </Text>
            <Text style={styles.currentPlaylistTracks}>
              {currentPlaylist.tracks.length} tracks
            </Text>
          </View>
        )}

        {playerState && (
          <View style={styles.section}>
            <Text style={styles.sectionTitle}>
              Player State (from getState())
            </Text>
            <View style={styles.stateInfo}>
              <Text style={styles.stateLabel}>Current State:</Text>
              <Text style={styles.stateValue}>{playerState.currentState}</Text>
            </View>
            <View style={styles.stateInfo}>
              <Text style={styles.stateLabel}>Current Position:</Text>
              <Text style={styles.stateValue}>
                {formatTime(playerState.currentPosition)}
              </Text>
            </View>
            <View style={styles.stateInfo}>
              <Text style={styles.stateLabel}>Total Duration:</Text>
              <Text style={styles.stateValue}>
                {formatTime(playerState.totalDuration)}
              </Text>
            </View>
            <View style={styles.stateInfo}>
              <Text style={styles.stateLabel}>Current Index:</Text>
              <Text style={styles.stateValue}>
                {playerState.currentIndex >= 0
                  ? playerState.currentIndex
                  : 'None'}
              </Text>
            </View>
            {playerState.currentTrack && (
              <View style={styles.stateInfo}>
                <Text style={styles.stateLabel}>Current Track:</Text>
                <View style={styles.stateTrackInfo}>
                  <Text style={styles.stateValue}>
                    {playerState.currentTrack.title}
                  </Text>
                  <Text style={styles.stateSubValue}>
                    {playerState.currentTrack.artist}
                  </Text>
                </View>
              </View>
            )}
            <View style={styles.stateInfo}>
              <Text style={styles.stateLabel}>Current Playlist ID:</Text>
              <Text style={styles.stateValue}>
                {playerState.currentPlaylistId || 'None'}
              </Text>
            </View>
          </View>
        )}
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f5f5f5',
  },
  scrollView: {
    flex: 1,
  },
  content: {
    padding: 20,
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    marginBottom: 20,
    textAlign: 'center',
  },
  section: {
    marginBottom: 30,
    backgroundColor: '#fff',
    padding: 15,
    borderRadius: 8,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 3,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '600',
    marginBottom: 15,
    color: '#333',
  },
  button: {
    backgroundColor: '#007AFF',
    padding: 12,
    borderRadius: 8,
    marginBottom: 10,
    alignItems: 'center',
  },
  buttonDisabled: {
    backgroundColor: '#ccc',
    opacity: 0.6,
  },
  buttonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '500',
  },
  smallButton: {
    backgroundColor: '#007AFF',
    padding: 6,
    borderRadius: 4,
    marginLeft: 5,
    minWidth: 60,
    alignItems: 'center',
  },
  activeButton: {
    backgroundColor: '#28a745',
  },
  deleteButton: {
    backgroundColor: '#dc3545',
  },
  smallButtonText: {
    color: '#fff',
    fontSize: 12,
    fontWeight: '500',
  },
  operationText: {
    fontSize: 14,
    color: '#666',
    fontStyle: 'italic',
    marginTop: 5,
  },
  emptyText: {
    fontSize: 14,
    color: '#999',
    fontStyle: 'italic',
  },
  playlistItem: {
    marginBottom: 15,
    padding: 12,
    backgroundColor: '#f9f9f9',
    borderRadius: 6,
    borderWidth: 1,
    borderColor: '#e0e0e0',
  },
  playlistHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    marginBottom: 10,
  },
  playlistInfo: {
    flex: 1,
  },
  playlistName: {
    fontSize: 16,
    fontWeight: '600',
    color: '#333',
    marginBottom: 4,
  },
  playlistDescription: {
    fontSize: 12,
    color: '#666',
    marginBottom: 4,
  },
  playlistTracksCount: {
    fontSize: 12,
    color: '#999',
  },
  playlistActions: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  tracksList: {
    marginTop: 10,
    paddingTop: 10,
    borderTopWidth: 1,
    borderTopColor: '#e0e0e0',
  },
  tracksListHeader: {
    fontSize: 13,
    fontWeight: '600',
    color: '#666',
    marginBottom: 8,
  },
  trackItem: {
    flexDirection: 'row',
    padding: 8,
    marginBottom: 6,
    backgroundColor: '#fff',
    borderRadius: 4,
    alignItems: 'center',
  },
  trackIndex: {
    fontSize: 14,
    fontWeight: 'bold',
    marginRight: 10,
    color: '#666',
    minWidth: 25,
  },
  trackInfo: {
    flex: 1,
    paddingRight: 8,
  },
  trackTitle: {
    fontSize: 14,
    fontWeight: '600',
    color: '#007AFF',
  },
  trackArtist: {
    fontSize: 12,
    color: '#666',
    marginTop: 2,
  },
  playTrackButton: {
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: '#28a745',
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: 6,
  },
  playTrackButtonText: {
    fontSize: 16,
  },
  removeButton: {
    width: 24,
    height: 24,
    borderRadius: 12,
    backgroundColor: '#dc3545',
    alignItems: 'center',
    justifyContent: 'center',
  },
  removeButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: 'bold',
  },
  controlsRow: {
    flexDirection: 'row',
    justifyContent: 'space-around',
    marginBottom: 10,
  },
  controlButton: {
    backgroundColor: '#007AFF',
    padding: 10,
    borderRadius: 5,
    minWidth: 60,
    alignItems: 'center',
  },
  connectionIndicator: {
    padding: 8,
    marginBottom: 10,
    backgroundColor: '#f8d7da',
    borderRadius: 5,
    borderWidth: 1,
    borderColor: '#f5c6cb',
  },
  connectionIndicatorConnected: {
    backgroundColor: '#d4edda',
    borderColor: '#c3e6cb',
  },
  connectionText: {
    textAlign: 'center',
    fontSize: 14,
    fontWeight: '600',
    color: '#333',
  },
  statusText: {
    textAlign: 'center',
    marginBottom: 5,
    fontWeight: 'bold',
  },
  currentTrack: {
    marginTop: 10,
    padding: 10,
    backgroundColor: '#eee',
    borderRadius: 5,
  },
  currentTrackTitle: {
    fontWeight: 'bold',
    fontSize: 16,
  },
  currentTrackArtist: {
    fontSize: 14,
    color: '#666',
  },
  currentPlaylistName: {
    fontSize: 16,
    fontWeight: '600',
    color: '#333',
    marginBottom: 5,
  },
  currentPlaylistTracks: {
    fontSize: 14,
    color: '#666',
  },
  progressSection: {
    marginTop: 15,
    padding: 10,
    backgroundColor: '#f0f0f0',
    borderRadius: 5,
  },
  progressLabel: {
    fontSize: 14,
    fontWeight: '600',
    color: '#333',
    marginBottom: 5,
  },
  progressText: {
    fontSize: 16,
    fontWeight: 'bold',
    color: '#007AFF',
    textAlign: 'center',
    marginBottom: 8,
  },
  progressBarContainer: {
    height: 6,
    backgroundColor: '#ddd',
    borderRadius: 3,
    overflow: 'hidden',
    marginBottom: 5,
  },
  progressBar: {
    height: '100%',
    backgroundColor: '#007AFF',
    borderRadius: 3,
  },
  seekIndicator: {
    fontSize: 12,
    color: '#666',
    textAlign: 'center',
    marginTop: 5,
  },
  seekInfo: {
    marginTop: 10,
    padding: 8,
    backgroundColor: '#fff3cd',
    borderRadius: 5,
    borderWidth: 1,
    borderColor: '#ffc107',
  },
  seekLabel: {
    fontSize: 12,
    fontWeight: '600',
    color: '#856404',
    marginBottom: 3,
  },
  seekText: {
    fontSize: 12,
    color: '#856404',
  },
  stateInfo: {
    marginBottom: 12,
    paddingBottom: 12,
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
  },
  stateLabel: {
    fontSize: 12,
    fontWeight: '600',
    color: '#666',
    marginBottom: 4,
  },
  stateValue: {
    fontSize: 14,
    color: '#333',
    fontWeight: '500',
  },
  stateSubValue: {
    fontSize: 12,
    color: '#666',
    marginTop: 2,
  },
  stateTrackInfo: {
    marginTop: 4,
  },
  infoBox: {
    backgroundColor: '#e3f2fd',
    padding: 12,
    borderRadius: 6,
    marginBottom: 15,
    borderLeftWidth: 4,
    borderLeftColor: '#2196F3',
  },
  infoText: {
    fontSize: 14,
    fontWeight: '600',
    color: '#1565C0',
    marginBottom: 8,
  },
  infoSubText: {
    fontSize: 12,
    color: '#1976D2',
    marginLeft: 8,
    marginBottom: 2,
  },
});

// Helper function to format time
function formatTime(seconds: number): string {
  if (!isFinite(seconds) || seconds < 0) return '0:00';
  const mins = Math.floor(seconds / 60);
  const secs = Math.floor(seconds % 60);
  return `${mins}:${secs.toString().padStart(2, '0')}`;
}

export default App;
