import { afterEach, describe, expect, mock, test } from 'bun:test'
import React from 'react'
import { act, create, type ReactTestRenderer } from 'react-test-renderer'

const listeners = new Map<string, (...args: unknown[]) => void>()
const registrations = new Map<string, number>()
const register = (name: string) => (callback: (...args: unknown[]) => void) => {
  listeners.set(name, callback)
  registrations.set(name, (registrations.get(name) ?? 0) + 1)
}
const trackPlayer = {
  onChangeTrack: register('track'),
  onPlaybackStateChange: register('state'),
  onPlaybackProgressChange: register('progress'),
  onSeek: register('seek'),
  getState: async () => ({ currentTrack: null }),
}

mock.module('react-native', () => ({
  Platform: { OS: 'ios' },
  AppRegistry: { registerHeadlessTask: () => {} },
  AppState: { addEventListener: () => ({ remove: () => {} }) },
  Pressable: () => null,
  View: () => null,
}))
mock.module('react-native-nitro-modules', () => ({
  NitroModules: {
    createHybridObject: (name: string) =>
      name === 'TrackPlayer' ? trackPlayer : {},
  },
}))

// Import the real public entrypoint after mocking only the native boundary.
const { callbackManager, useOnChangeTrack } =
  await import('../react-native-nitro-player/src')
const internal =
  await import('../react-native-nitro-player/src/hooks/callbackManager')
;(
  globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }
).IS_REACT_ACT_ENVIRONMENT = true
let renderer: ReactTestRenderer | undefined
const cleanup: (() => void)[] = []

afterEach(async () => {
  if (renderer) await act(async () => renderer?.unmount())
  renderer = undefined
  cleanup.splice(0).forEach(unsubscribe => unsubscribe())
})

describe('public callback manager', () => {
  test('exports the singleton already used by hooks', () => {
    expect(callbackManager).toBeDefined()
    expect(callbackManager).toBe(internal.callbackManager)
  })

  test('a service and a mounted hook both receive the same native track change', async () => {
    const serviceEvents: unknown[] = []
    let hookTrack: unknown
    cleanup.push(
      callbackManager.subscribeToTrackChange(track => serviceEvents.push(track))
    )
    function Probe() {
      hookTrack = useOnChangeTrack().track
      return null
    }
    await act(async () => {
      renderer = create(<Probe />)
    })
    const track = {
      id: 'episode',
      title: 'Episode',
      artist: '',
      album: '',
      duration: 10,
      url: 'url',
    }

    await act(async () => listeners.get('track')?.(track, 'user'))

    expect(serviceEvents).toEqual([track])
    expect(hookTrack).toEqual(track)
    expect(registrations.get('track')).toBe(1)

    await act(async () => renderer?.unmount())
    renderer = undefined
    listeners.get('track')?.(track, 'end')
    expect(serviceEvents).toEqual([track, track])
  })

  test.each([
    ['state', 'subscribeToPlaybackState', ['playing', 'user']],
    ['progress', 'subscribeToPlaybackProgressChange', [12, 100, true]],
    ['seek', 'subscribeToSeek', [25, 100]],
  ] as const)(
    '%s fans out and unsubscribes independently',
    (event, method, values) => {
      const first = mock(() => {})
      const second = mock(() => {})
      const subscribe = callbackManager[method].bind(callbackManager) as (
        callback: (...args: unknown[]) => void
      ) => () => void
      const unsubscribe = subscribe(first)
      cleanup.push(unsubscribe, subscribe(second))

      listeners.get(event)?.(...values)
      expect(first.mock.calls).toEqual([values])
      expect(second.mock.calls).toEqual([values])
      expect(registrations.get(event)).toBe(1)

      unsubscribe()
      listeners.get(event)?.(...values)
      expect(first).toHaveBeenCalledTimes(1)
      expect(second).toHaveBeenCalledTimes(2)
    }
  )
})
