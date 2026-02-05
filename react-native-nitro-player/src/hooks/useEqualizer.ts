import { useEffect, useState, useCallback, useRef } from 'react'
import { Equalizer } from '../index'
import type { EqualizerBand } from '../types/EqualizerTypes'
import { equalizerCallbackManager } from './equalizerCallbackManager'

export interface UseEqualizerResult {
  /** Whether the equalizer is enabled */
  isEnabled: boolean
  /** Current band settings */
  bands: EqualizerBand[]
  /** Currently applied preset name */
  currentPreset: string | null
  /** Toggle equalizer on/off */
  setEnabled: (enabled: boolean) => boolean
  /** Set gain for a specific band */
  setBandGain: (bandIndex: number, gainDb: number) => boolean
  /** Set all band gains at once */
  setAllBandGains: (gains: number[]) => boolean
  /** Reset to flat response */
  reset: () => void
  /** Whether equalizer is loading */
  isLoading: boolean
  /** Gain range (min/max in dB) */
  gainRange: { min: number; max: number }
}

const DEFAULT_BANDS: EqualizerBand[] = [
  { index: 0, centerFrequency: 60, gainDb: 0, frequencyLabel: '60 Hz' },
  { index: 1, centerFrequency: 230, gainDb: 0, frequencyLabel: '230 Hz' },
  { index: 2, centerFrequency: 910, gainDb: 0, frequencyLabel: '910 Hz' },
  { index: 3, centerFrequency: 3600, gainDb: 0, frequencyLabel: '3.6 kHz' },
  { index: 4, centerFrequency: 14000, gainDb: 0, frequencyLabel: '14 kHz' },
]

export function useEqualizer(): UseEqualizerResult {
  const [isEnabled, setIsEnabledState] = useState(false)
  const [bands, setBands] = useState<EqualizerBand[]>(DEFAULT_BANDS)
  const [currentPreset, setCurrentPreset] = useState<string | null>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [gainRange, setGainRange] = useState({ min: -12, max: 12 })
  const isMounted = useRef(true)

  // Load initial state
  useEffect(() => {
    isMounted.current = true

    const loadState = async () => {
      try {
        const state = Equalizer.getState()
        if (isMounted.current) {
          setIsEnabledState(state.enabled)
          setBands(state.bands)
          setCurrentPreset(state.currentPreset)

          const range = Equalizer.getBandRange()
          setGainRange({ min: range.min, max: range.max })

          setIsLoading(false)
        }
      } catch (error) {
        console.error('[useEqualizer] Error loading state:', error)
        if (isMounted.current) {
          setIsLoading(false)
        }
      }
    }

    loadState()

    return () => {
      isMounted.current = false
    }
  }, [])

  // Subscribe to enabled changes
  useEffect(() => {
    const unsubscribe = equalizerCallbackManager.subscribeToEnabledChange(
      (enabled) => {
        if (isMounted.current) {
          setIsEnabledState(enabled)
        }
      }
    )

    return unsubscribe
  }, [])

  // Subscribe to band changes
  useEffect(() => {
    const unsubscribe = equalizerCallbackManager.subscribeToBandChange(
      (newBands) => {
        if (isMounted.current) {
          setBands(newBands)
        }
      }
    )

    return unsubscribe
  }, [])

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

  const setEnabled = useCallback((enabled: boolean): boolean => {
    try {
      return Equalizer.setEnabled(enabled)
    } catch (error) {
      console.error('[useEqualizer] Error setting enabled:', error)
      return false
    }
  }, [])

  const setBandGain = useCallback(
    (bandIndex: number, gainDb: number): boolean => {
      // Optimistic update
      setBands((prevBands) =>
        prevBands.map((b) => (b.index === bandIndex ? { ...b, gainDb } : b))
      )
      try {
        return Equalizer.setBandGain(bandIndex, gainDb)
      } catch (error) {
        console.error('[useEqualizer] Error setting band gain:', error)
        return false
      }
    },
    []
  )

  const setAllBandGains = useCallback((gains: number[]): boolean => {
    // Optimistic update
    setBands((prevBands) =>
      prevBands.map((b, i) => ({ ...b, gainDb: gains[i] ?? b.gainDb }))
    )
    try {
      return Equalizer.setAllBandGains(gains)
    } catch (error) {
      console.error('[useEqualizer] Error setting all band gains:', error)
      return false
    }
  }, [])

  const reset = useCallback(() => {
    // Optimistic update
    setBands((prevBands) => prevBands.map((b) => ({ ...b, gainDb: 0 })))
    try {
      Equalizer.reset()
    } catch (error) {
      console.error('[useEqualizer] Error resetting equalizer:', error)
    }
  }, [])

  return {
    isEnabled,
    bands,
    currentPreset,
    setEnabled,
    setBandGain,
    setAllBandGains,
    reset,
    isLoading,
    gainRange,
  }
}
