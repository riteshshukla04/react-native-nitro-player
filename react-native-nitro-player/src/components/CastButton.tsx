import React from 'react'
import {
  Pressable,
  StyleSheet,
  View,
  type PressableProps,
  type StyleProp,
  type ViewStyle,
} from 'react-native'
import { Cast } from '../index'
import { useCastState } from '../hooks/useCastState'
import type { CastState } from '../specs/Cast.nitro'

export interface CastButtonProps extends Omit<PressableProps, 'children'> {
  /** Icon size in points. Defaults to `24`. */
  size?: number
  /** Glyph color when not connected. Defaults to `#000000`. */
  color?: string
  /** Glyph color while connecting / connected. Defaults to `#1E88E5`. */
  activeColor?: string
  /** Style applied to the pressable container. */
  style?: StyleProp<ViewStyle>
  /**
   * Hide the button entirely when no Cast devices are available on the network,
   * matching standard platform Cast-button behaviour. Defaults to `true`.
   */
  hideWhenNoDevices?: boolean
  /**
   * Render a custom icon instead of the built-in Cast glyph. Receives the live
   * connection state so you can theme it yourself.
   */
  renderIcon?: (info: {
    state: CastState
    isCasting: boolean
    size: number
    color: string
  }) => React.ReactNode
}

/**
 * A ready-to-use Google Cast button.
 *
 * Reflects the live connection state, hides itself when no devices are available
 * (configurable), and presents the native Cast dialog on press. For full control
 * over the icon, pass `renderIcon`; for custom press handling, pass `onPress`
 * (the default opens the system Cast picker).
 *
 * @example
 * ```tsx
 * import { CastButton } from 'react-native-nitro-player'
 *
 * <CastButton size={28} activeColor="#1DB954" />
 * ```
 */
export function CastButton({
  size = 24,
  color = '#000000',
  activeColor = '#1E88E5',
  hideWhenNoDevices = true,
  renderIcon,
  onPress,
  style,
  ...rest
}: CastButtonProps): React.ReactElement | null {
  const { state, isCasting } = useCastState()

  if (hideWhenNoDevices && state === 'no_devices_available') {
    return null
  }

  const active = state === 'connected' || state === 'connecting'
  const glyphColor = active ? activeColor : color

  const handlePress: PressableProps['onPress'] = (event) => {
    if (onPress) {
      onPress(event)
      return
    }
    try {
      Cast.showCastPicker()
    } catch (error) {
      console.error('[CastButton] Failed to present cast picker:', error)
    }
  }

  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={isCasting ? 'Casting' : 'Cast'}
      accessibilityState={{ selected: isCasting }}
      hitSlop={8}
      onPress={handlePress}
      style={style}
      {...rest}
    >
      {renderIcon ? (
        renderIcon({ state, isCasting, size, color: glyphColor })
      ) : (
        <CastGlyph size={size} color={glyphColor} />
      )}
    </Pressable>
  )
}

/**
 * Dependency-free rendition of the standard Cast glyph: a rounded "screen"
 * rectangle with a broadcast signal (dot + two arcs) in the bottom-left corner.
 * Drawn purely with `View`s so the library stays dependency-free.
 */
function CastGlyph({
  size,
  color,
}: {
  size: number
  color: string
}): React.ReactElement {
  const stroke = Math.max(1.5, Math.round(size * 0.083))
  const inset = stroke
  const dotSize = stroke * 1.7
  const r1 = size * 0.28 // inner arc radius
  const r2 = size * 0.46 // outer arc radius

  return (
    <View style={{ width: size, height: size }}>
      {/* Screen outline */}
      <View
        style={[
          StyleSheet.absoluteFill,
          {
            borderWidth: stroke,
            borderColor: color,
            borderRadius: Math.max(2, size * 0.12),
          },
        ]}
      />
      {/* Broadcast dot */}
      <View
        style={{
          position: 'absolute',
          left: inset,
          bottom: inset,
          width: dotSize,
          height: dotSize,
          borderRadius: dotSize / 2,
          backgroundColor: color,
        }}
      />
      {/* Two concentric quarter arcs radiating from the dot */}
      <Arc origin={inset + dotSize / 2} radius={r1} stroke={stroke} color={color} />
      <Arc origin={inset + dotSize / 2} radius={r2} stroke={stroke} color={color} />
    </View>
  )
}

/**
 * A quarter-circle arc (the top-right quadrant) centered at the bottom-left
 * `origin` point. Produced by clipping a full bordered circle to one quadrant.
 */
function Arc({
  origin,
  radius,
  stroke,
  color,
}: {
  origin: number
  radius: number
  stroke: number
  color: string
}): React.ReactElement {
  return (
    <View
      // Clip box reveals only the quadrant facing up-and-right from the origin.
      style={{
        position: 'absolute',
        left: origin,
        bottom: origin - radius,
        width: radius,
        height: radius,
        overflow: 'hidden',
      }}
    >
      <View
        style={{
          position: 'absolute',
          left: -radius,
          top: 0,
          width: radius * 2,
          height: radius * 2,
          borderRadius: radius,
          borderWidth: stroke,
          borderColor: color,
        }}
      />
    </View>
  )
}
