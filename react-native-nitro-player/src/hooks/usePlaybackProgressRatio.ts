import { useOnPlaybackProgressChange } from './useOnPlaybackProgressChange'

/**
 * Hook that returns how far playback has progressed through the current track.
 *
 * Built on {@link useOnPlaybackProgressChange}, so it updates on every progress
 * event. Useful for progress bars that need a fraction rather than seconds.
 *
 * @returns Progress between `0` and `1`. Returns `0` while the track's duration
 * is unknown (zero, negative or `NaN`), and is clamped to `[0, 1]` so a position
 * reported slightly past the duration never overflows a progress bar.
 *
 * @example
 * ```tsx
 * function ProgressBar() {
 *   const progress = usePlaybackProgressRatio()
 *   return <View style={{ width: `${progress * 100}%`, height: 4 }} />
 * }
 * ```
 */
export function usePlaybackProgressRatio(): number {
  const { position, totalDuration } = useOnPlaybackProgressChange()

  if (!(totalDuration > 0)) {
    return 0
  }

  return Math.min(Math.max(position / totalDuration, 0), 1)
}
