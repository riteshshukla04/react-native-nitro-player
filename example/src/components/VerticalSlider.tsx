import React, { useRef, useMemo, useCallback } from 'react';
import {
    StyleSheet,
    View,
    PanResponder,
    PanResponderGestureState,
} from 'react-native';
import { colors } from '../styles/theme';

interface VerticalSliderProps {
    value: number;
    min: number;
    max: number;
    onChange: (value: number) => void;
    width?: number;
    height?: number;
    disabled?: boolean;
}

export const VerticalSlider = ({
    value,
    min,
    max,
    onChange,
    width = 40,
    height = 200,
    disabled = false,
}: VerticalSliderProps) => {
    const range = max - min;
    const [localValue, setLocalValue] = React.useState<number | null>(null);
    const isDragging = useRef(false);
    const startValue = useRef(value);
    // Use refs to avoid recreating PanResponder on every value change
    const currentValueRef = useRef(value);
    const onChangeRef = useRef(onChange);

    // Keep refs in sync
    currentValueRef.current = value;
    onChangeRef.current = onChange;

    // Sync local value with prop only when NOT dragging
    React.useEffect(() => {
        if (!isDragging.current) {
            setLocalValue(null);
        }
    }, [value]);

    const displayValue = localValue !== null ? localValue : value;

    // Calculate position from value because Y goes down
    // Max value (top) -> Y=0
    // Min value (bottom) -> Y=height
    const getPositionFromValue = useCallback(
        (val: number) => {
            // Safety check for NaN or infinite values
            if (!Number.isFinite(val)) return height / 2;

            const clamped = Math.min(Math.max(val, min), max);
            const percentage = (clamped - min) / range;
            return height * (1 - percentage); // Invert: 1.0 (max) -> 0 (top)
        },
        [height, min, max, range]
    );

    // Stable PanResponder - only depends on stable values
    const panResponder = useMemo(
        () =>
            PanResponder.create({
                onStartShouldSetPanResponder: () => !disabled,
                onMoveShouldSetPanResponder: () => !disabled,
                onPanResponderGrant: () => {
                    isDragging.current = true;
                    // Capture the current value at gesture start from ref
                    const currentVal = currentValueRef.current;
                    startValue.current = currentVal;
                    setLocalValue(currentVal);
                },
                onPanResponderMove: (_evt, gestureState: PanResponderGestureState) => {
                    // dy is positive when moving down (decreasing value)
                    // dy is negative when moving up (increasing value)

                    // Calculate change in value
                    // Delta Y / Height = Delta Value / Range
                    // But Y is inverted: Positive dy (down) -> Negative value change
                    const deltaValue = -(gestureState.dy / height) * range;

                    const newValue = Math.min(Math.max(startValue.current + deltaValue, min), max);

                    // Update local state immediately for smooth UI
                    setLocalValue(newValue);

                    // Propagate change to parent via ref
                    onChangeRef.current(newValue);
                },
                onPanResponderTerminationRequest: () => false,
                onPanResponderRelease: () => {
                    isDragging.current = false;
                    setLocalValue(null);
                },
                onPanResponderTerminate: () => {
                    isDragging.current = false;
                    setLocalValue(null);
                },
            }),
        [disabled, height, max, min, range] // Removed displayValue - use refs instead
    );

    // Update render based on local or prop value
    const thumbY = getPositionFromValue(displayValue);

    return (
        <View
            style={[styles.container, { width, height, opacity: disabled ? 0.5 : 1 }]}
            {...panResponder.panHandlers}>
            {/* Track Background */}
            <View style={[styles.track, { backgroundColor: colors.border }]} />

            {/* Filled Track (from bottom to thumb) */}
            <View
                style={[
                    styles.fill,
                    {
                        backgroundColor: colors.primary,
                        height: height - thumbY, // Distance from bottom
                        bottom: 0,
                    },
                ]}
            />

            {/* Thumb */}
            <View
                style={[
                    styles.thumb,
                    {
                        top: thumbY - 12, // Center thumb (24px / 2 = 12)
                    },
                ]}
            />
        </View>
    );
};

const styles = StyleSheet.create({
    container: {
        justifyContent: 'center',
        alignItems: 'center',
        position: 'relative',
    },
    track: {
        width: 4,
        height: '100%',
        borderRadius: 2,
        position: 'absolute',
    },
    fill: {
        width: 4,
        borderRadius: 2,
        position: 'absolute',
    },
    thumb: {
        width: 24,
        height: 24,
        borderRadius: 12,
        backgroundColor: '#fff',
        position: 'absolute',
        borderWidth: 1,
        borderColor: 'rgba(0,0,0,0.1)',
        shadowColor: '#000',
        shadowOffset: { width: 0, height: 2 },
        shadowOpacity: 0.2,
        shadowRadius: 2,
        elevation: 3,
    },
});
