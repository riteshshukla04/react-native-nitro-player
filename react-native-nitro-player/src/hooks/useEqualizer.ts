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
  setEnabled: (enabled: boolean) => Promise<boolean>
  /** Set gain for a specific band */
  setBandGain: (bandIndex: number, gainDb: number) => Promise<boolean>
  /** Set all band gains at once */
  setAllBandGains: (gains: number[]) => Promise<boolean>
  /** Reset to flat response */
  reset: () => Promise<void>
  /** Whether equalizer is loading */
  isLoading: boolean
  /** Gain range (min/max in dB) */
  gainRange: { min: number; max: number }
}

const DEFAULT_BANDS: EqualizerBand[] = [
  { index: 0, centerFrequency: 31, gainDb: 0, frequencyLabel: '31 Hz' },
  { index: 1, centerFrequency: 63, gainDb: 0, frequencyLabel: '63 Hz' },
  { index: 2, centerFrequency: 125, gainDb: 0, frequencyLabel: '125 Hz' },
  { index: 3, centerFrequency: 250, gainDb: 0, frequencyLabel: '250 Hz' },
  { index: 4, centerFrequency: 500, gainDb: 0, frequencyLabel: '500 Hz' },
  { index: 5, centerFrequency: 1000, gainDb: 0, frequencyLabel: '1 kHz' },
  { index: 6, centerFrequency: 2000, gainDb: 0, frequencyLabel: '2 kHz' },
  { index: 7, centerFrequency: 4000, gainDb: 0, frequencyLabel: '4 kHz' },
  { index: 8, centerFrequency: 8000, gainDb: 0, frequencyLabel: '8 kHz' },
  { index: 9, centerFrequency: 16000, gainDb: 0, frequencyLabel: '16 kHz' },
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
        const state = await Equalizer.getState()
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

  const setEnabled = useCallback(async (enabled: boolean): Promise<boolean> => {
    try {
      await Equalizer.setEnabled(enabled)
      return true
    } catch (error) {
      console.error('[useEqualizer] Error setting enabled:', error)
      return false
    }
  }, [])

  const setBandGain = useCallback(
    async (bandIndex: number, gainDb: number): Promise<boolean> => {
      setBands((prevBands) =>
        prevBands.map((b) => (b.index === bandIndex ? { ...b, gainDb } : b))
      )
      try {
        await Equalizer.setBandGain(bandIndex, gainDb)
        return true
      } catch (error) {
        console.error('[useEqualizer] Error setting band gain:', error)
        return false
      }
    },
    []
  )

  const setAllBandGains = useCallback(async (gains: number[]): Promise<boolean> => {
    setBands((prevBands) =>
      prevBands.map((b, i) => ({ ...b, gainDb: gains[i] ?? b.gainDb }))
    )
    try {
      await Equalizer.setAllBandGains(gains)
      return true
    } catch (error) {
      console.error('[useEqualizer] Error setting all band gains:', error)
      return false
    }
  }, [])

  const reset = useCallback(async () => {
    setBands((prevBands) => prevBands.map((b) => ({ ...b, gainDb: 0 })))
    try {
      await Equalizer.reset()
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
