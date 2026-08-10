import React from 'react'
import {
  Pressable,
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
 * rectangle (with its bottom-left corner open) and a broadcast signal — a dot
 * and two concentric arcs — radiating from the bottom-left. Drawn purely with
 * `View`s so the library stays dependency-free.
 */
function CastGlyph({
  size,
  color,
}: {
  size: number
  color: string
}): React.ReactElement {
  const stroke = Math.max(1.5, Math.round(size / 13))
  const inset = Math.round(size * 0.14)
  const dotSize = stroke * 1.5
  // Origin of the broadcast signal — the screen's bottom-left corner.
  const cx = inset + stroke / 2
  const cy = size - inset - stroke / 2
  // Leave the screen's bottom-left corner open so the signal reads clearly.
  const gap = size * 0.46

  return (
    <View style={{ width: size, height: size }}>
      {/* Screen: top + right + most of bottom + most of left, leaving the
          bottom-left corner open (composed from edges for a clean cast look). */}
      {/* Top edge */}
      <View
        style={{
          position: 'absolute',
          left: inset,
          top: inset,
          right: inset,
          height: stroke,
          backgroundColor: color,
          borderRadius: stroke,
        }}
      />
      {/* Right edge */}
      <View
        style={{
          position: 'absolute',
          top: inset,
          bottom: inset,
          right: inset,
          width: stroke,
          backgroundColor: color,
          borderRadius: stroke,
        }}
      />
      {/* Bottom edge (stops short of the bottom-left corner) */}
      <View
        style={{
          position: 'absolute',
          left: inset + gap,
          bottom: inset,
          right: inset,
          height: stroke,
          backgroundColor: color,
          borderRadius: stroke,
        }}
      />
      {/* Left edge (stops short of the bottom-left corner) */}
      <View
        style={{
          position: 'absolute',
          left: inset,
          top: inset,
          height: size - 2 * inset - gap,
          width: stroke,
          backgroundColor: color,
          borderRadius: stroke,
        }}
      />
      {/* Two concentric broadcast arcs radiating from the corner dot */}
      <RippleArc
        cx={cx}
        cy={cy}
        radius={size * 0.2}
        stroke={stroke}
        color={color}
      />
      <RippleArc
        cx={cx}
        cy={cy}
        radius={size * 0.34}
        stroke={stroke}
        color={color}
      />
      {/* Broadcast dot */}
      <View
        style={{
          position: 'absolute',
          left: cx - dotSize / 2,
          top: cy - dotSize / 2,
          width: dotSize,
          height: dotSize,
          borderRadius: dotSize / 2,
          backgroundColor: color,
        }}
      />
    </View>
  )
}

/**
 * A quarter-circle arc (the up-right quadrant) centered at (cx, cy). Rendered as
 * a circle with only its top border colored, rotated 45° so the visible cap
 * faces up-and-to-the-right — i.e. radiating from the bottom-left dot.
 */
function RippleArc({
  cx,
  cy,
  radius,
  stroke,
  color,
}: {
  cx: number
  cy: number
  radius: number
  stroke: number
  color: string
}): React.ReactElement {
  return (
    <View
      style={{
        position: 'absolute',
        left: cx - radius,
        top: cy - radius,
        width: radius * 2,
        height: radius * 2,
        borderRadius: radius,
        borderWidth: stroke,
        borderTopColor: color,
        borderRightColor: 'transparent',
        borderBottomColor: 'transparent',
        borderLeftColor: 'transparent',
        transform: [{ rotate: '45deg' }],
      }}
    />
  )
}
