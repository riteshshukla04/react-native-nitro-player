import { TrackPlayer } from 'react-native-nitro-player';

// Stands in for the app's own backend
const favorites = new Set<string>(['2']);

// Module scope, not a component: the buttons work while no screen is mounted
export async function registerNotificationButtons() {
  await TrackPlayer.configure({
    notificationButtons: {
      android: [
        { id: 'favorite', title: 'Favorite', icon: 'heart', activeIcon: 'heart_filled' },
        { id: 'refresh', title: 'Refresh track', icon: 'sync' },
      ],
      ios: {
        lockScreen: [{ id: 'favorite', title: 'Favorite', command: 'like' }],
        carPlay: [
          { id: 'favorite', icon: 'heart', activeIcon: 'heart.fill' },
          { id: 'repeat', type: 'repeat' },
          { id: 'speed', type: 'playbackRate' },
          { id: 'refresh', icon: 'arrow.clockwise' },
        ],
      },
    },
  });

  // Tell the player what the backend already knows, so skipping shows each track's heart
  TrackPlayer.setNotificationButtonState({
    buttonId: 'favorite',
    trackIds: [...favorites],
    isActive: true,
  });

  TrackPlayer.onNotificationButtonPress((buttonId, track, event) => {
    console.info(`🔘 ${buttonId} pressed for ${track.id}`, event);
    if (buttonId === 'favorite') {
      // The icon already flipped; a failed save would undo it with setNotificationButtonState
      if (event.isActive) favorites.add(track.id);
      else favorites.delete(track.id);
    }
    if (buttonId === 'refresh') {
      void TrackPlayer.updateTracks([{ ...track, title: `${track.title.replace(/ ↻\d+$/, '')} ↻${Date.now() % 1000}` }]);
    }
  });
}
