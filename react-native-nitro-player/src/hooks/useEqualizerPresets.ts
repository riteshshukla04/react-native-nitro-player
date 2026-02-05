import { useEffect, useState, useCallback, useRef } from 'react'
import { Equalizer } from '../index'
import type { EqualizerPreset } from '../types/EqualizerTypes'
import { equalizerCallbackManager } from './equalizerCallbackManager'

export interface UseEqualizerPresetsResult {
  /** All available presets */
  presets: EqualizerPreset[]
  /** Built-in presets only */
  builtInPresets: EqualizerPreset[]
  /** Custom user presets */
  customPresets: EqualizerPreset[]
  /** Apply a preset by name */
  applyPreset: (name: string) => boolean
  /** Save current settings as custom preset */
  saveCustomPreset: (name: string) => boolean
  /** Delete a custom preset */
  deleteCustomPreset: (name: string) => boolean
  /** Currently applied preset name */
  currentPreset: string | null
  /** Whether presets are loading */
  isLoading: boolean
  /** Refresh presets from native */
  refreshPresets: () => void
}

export function useEqualizerPresets(): UseEqualizerPresetsResult {
  const [presets, setPresets] = useState<EqualizerPreset[]>([])
  const [builtInPresets, setBuiltInPresets] = useState<EqualizerPreset[]>([])
  const [customPresets, setCustomPresets] = useState<EqualizerPreset[]>([])
  const [currentPreset, setCurrentPreset] = useState<string | null>(null)
  const [isLoading, setIsLoading] = useState(true)
  const isMounted = useRef(true)

  const refreshPresets = useCallback(() => {
    try {
      const allPresets = Equalizer.getPresets()
      const builtIn = Equalizer.getBuiltInPresets()
      const custom = Equalizer.getCustomPresets()
      const current = Equalizer.getCurrentPresetName()

      if (isMounted.current) {
        setPresets(allPresets)
        setBuiltInPresets(builtIn)
        setCustomPresets(custom)
        setCurrentPreset(current)
      }
    } catch (error) {
      console.error('[useEqualizerPresets] Error refreshing presets:', error)
    }
  }, [])

  // Load initial presets
  useEffect(() => {
    isMounted.current = true

    refreshPresets()
    setIsLoading(false)

    return () => {
      isMounted.current = false
    }
  }, [refreshPresets])

  // Subscribe to preset changes
  useEffect(() => {
    const unsubscribe = equalizerCallbackManager.subscribeToPresetChange(
      (presetName) => {
        if (isMounted.current) {
          setCurrentPreset(presetName)
        }
      }
    )

    return unsubscribe
  }, [])

  const applyPreset = useCallback((name: string): boolean => {
    try {
      const success = Equalizer.applyPreset(name)
      if (success) {
        setCurrentPreset(name)
      }
      return success
    } catch (error) {
      console.error('[useEqualizerPresets] Error applying preset:', error)
      return false
    }
  }, [])

  const saveCustomPreset = useCallback(
    (name: string): boolean => {
      try {
        const success = Equalizer.saveCustomPreset(name)
        if (success) {
          refreshPresets()
        }
        return success
      } catch (error) {
        console.error(
          '[useEqualizerPresets] Error saving custom preset:',
          error
        )
        return false
      }
    },
    [refreshPresets]
  )

  const deleteCustomPreset = useCallback(
    (name: string): boolean => {
      try {
        const success = Equalizer.deleteCustomPreset(name)
        if (success) {
          refreshPresets()
        }
        return success
      } catch (error) {
        console.error(
          '[useEqualizerPresets] Error deleting custom preset:',
          error
        )
        return false
      }
    },
    [refreshPresets]
  )

  return {
    presets,
    builtInPresets,
    customPresets,
    applyPreset,
    saveCustomPreset,
    deleteCustomPreset,
    currentPreset,
    isLoading,
    refreshPresets,
  }
}
