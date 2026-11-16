import type { HybridObject } from 'react-native-nitro-modules'
import type { TrackItem } from '../types/PlayerQueue'

/**
 * CarPlay templates for audio apps, iOS only. Use it through `CarPlayHelper`.
 * Templates travel as JSON because they nest.
 */
export interface CarPlay extends HybridObject<{ ios: 'swift' }> {
  /** JSON of a `CarPlayRoot`; kept across launches so a cold start shows it before JS runs */
  setRoot(rootJson: string): void
  /** JSON of a `CarPlayTemplate` */
  pushTemplate(templateJson: string): void
  popTemplate(): void
  popToRoot(): void
  showNowPlaying(): void
  /** JSON of a `CarPlayTemplate`; refreshes every shown template with its `id` */
  updateTemplate(templateJson: string): void
  /** Asks the loader again for lazy templates with `templateId`, or for every lazy template */
  reload(templateId?: string): void
  isConnected(): boolean
  onConnectionChange(callback: (connected: boolean) => void): void
  /** Rows, grid buttons, images and bar buttons without a built-in action */
  onSelect(callback: (id: string, templateId: string) => void): void
  /** A row with `loadTemplate` was selected; answer with {@link resolveTemplate} */
  onLoadTemplate(callback: (requestId: string, itemId: string) => void): void
  /** JSON of a `CarPlayTemplate`, or an empty string to open nothing */
  resolveTemplate(requestId: string, templateJson: string): void
  onAlbumArtistPress(callback: (track: TrackItem) => void): void
}
