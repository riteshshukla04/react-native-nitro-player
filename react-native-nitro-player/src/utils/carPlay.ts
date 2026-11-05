import type { TrackItem } from '../types/PlayerQueue'
import type { CarPlayRoot, CarPlayTemplate } from '../types/CarPlay'
import { CarPlay as CarPlayModule } from '../index'

type TemplateLoader = (
  itemId: string
) => Promise<CarPlayTemplate | null | undefined>

const connectionListeners = new Set<(connected: boolean) => void>()
let connectionRegistered = false

const ensureConnectionRegistered = () => {
  if (connectionRegistered || !CarPlayModule) return
  connectionRegistered = true
  CarPlayModule.onConnectionChange((connected) =>
    connectionListeners.forEach((listener) => listener(connected))
  )
}

/**
 * CarPlay for audio apps, iOS only; does nothing elsewhere.
 * Call it at module scope: CarPlay can start the app without any UI, and the
 * last root is shown on the next cold start before JS runs.
 *
 * @example
 * ```ts
 * CarPlayHelper.set({
 *   templates: [
 *     { type: 'list', id: 'library', title: 'Library', source: 'playlists', tab: { systemItem: 'favorites' } },
 *     { type: 'list', id: 'queue', title: 'Queue', source: 'queue', tab: { title: 'Queue', image: 'list.bullet' } },
 *   ],
 * })
 * ```
 */
export const CarPlayHelper = {
  set: (root: CarPlayRoot): void => {
    CarPlayModule?.setRoot(JSON.stringify(root))
  },

  push: (template: CarPlayTemplate): void => {
    CarPlayModule?.pushTemplate(JSON.stringify(template))
  },

  pop: (): void => {
    CarPlayModule?.popTemplate()
  },

  popToRoot: (): void => {
    CarPlayModule?.popToRoot()
  },

  showNowPlaying: (): void => {
    CarPlayModule?.showNowPlaying()
  },

  /** Redraws every shown template with the same `id`, e.g. after new data arrives */
  update: (template: CarPlayTemplate): void => {
    CarPlayModule?.updateTemplate(JSON.stringify(template))
  },

  /** Asks the loader again for lazy templates with `templateId`, or for every shown lazy template */
  reload: (templateId?: string): void => {
    CarPlayModule?.reload(templateId)
  },

  /**
   * Answers rows with `loadTemplate` (gets the row's `id`) and `lazy` templates (gets the template's `id`).
   * Resolving `null` opens nothing for a row and shows the error for a lazy template; rows wait up to 15s, lazy templates 30s.
   */
  setTemplateLoader: (loader: TemplateLoader): void => {
    CarPlayModule?.onLoadTemplate((requestId, itemId) => {
      loader(itemId)
        .catch(() => null)
        .then((template) =>
          CarPlayModule?.resolveTemplate(
            requestId,
            template ? JSON.stringify(template) : ''
          )
        )
    })
  },

  /** Rows, grid buttons, images and bar buttons without a built-in action; presses before registration are delivered on registration */
  onSelect: (callback: (id: string, templateId: string) => void): void => {
    CarPlayModule?.onSelect(callback)
  },

  /** Needs `nowPlaying.albumArtist` */
  onAlbumArtistPress: (callback: (track: TrackItem) => void): void => {
    CarPlayModule?.onAlbumArtistPress(callback)
  },

  /** @returns Unsubscribe function */
  onConnectionChange: (
    callback: (connected: boolean) => void
  ): (() => void) => {
    connectionListeners.add(callback)
    ensureConnectionRegistered()
    return () => {
      connectionListeners.delete(callback)
    }
  },

  isConnected: (): boolean => CarPlayModule?.isConnected() ?? false,

  isAvailable: (): boolean => CarPlayModule !== null,
}
