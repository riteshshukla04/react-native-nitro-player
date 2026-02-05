import React, { useState } from 'react';
import {
    StyleSheet,
    View,
    Text,
    ScrollView,
    TouchableOpacity,
    Switch,
    ActivityIndicator,
    SafeAreaView,
    Alert,
} from 'react-native';
import { useEqualizer, useEqualizerPresets } from 'react-native-nitro-player';
import { colors, commonStyles, spacing, borderRadius, typography } from '../styles/theme';
import { VerticalSlider } from '../components/VerticalSlider';

export default function EqualizerScreen() {
    const {
        isEnabled,
        bands,
        currentPreset,
        setEnabled,
        setBandGain,
        reset,
        isLoading,
        gainRange,
    } = useEqualizer();
    console.log('bands', bands);
    const {
        presets,
        isLoading: presetsLoading,
        applyPreset,
        saveCustomPreset,
        deleteCustomPreset,
    } = useEqualizerPresets();

    const [customPresetName, setCustomPresetName] = useState('');

    if (isLoading || presetsLoading) {
        return (
            <View style={[commonStyles.container, styles.center]}>
                <ActivityIndicator size="large" color={colors.primary} />
            </View>
        );
    }

    // Check if bands are available (TrackPlayer initialized)
    const hasNoBands = bands.length === 0;



    const handleSavePreset = () => {
        Alert.prompt(
            'Save Preset',
            'Enter a name for your custom preset:',
            [
                {
                    text: 'Cancel',
                    style: 'cancel',
                },
                {
                    text: 'Save',
                    onPress: (name?: string) => {
                        if (name) {
                            const success = saveCustomPreset(name);
                            if (!success) {
                                Alert.alert('Error', 'Failed to save preset');
                            }
                        }
                    },
                },
            ],
            'plain-text'
        );
    };

    const handleDeletePreset = (name: string) => {
        Alert.alert(
            'Delete Preset',
            `Are you sure you want to delete "${name}"?`,
            [
                { text: 'Cancel', style: 'cancel' },
                {
                    text: 'Delete',
                    style: 'destructive',
                    onPress: () => deleteCustomPreset(name),
                },
            ]
        );
    };

    return (
        <SafeAreaView style={commonStyles.container}>
            <ScrollView style={commonStyles.scrollView} contentContainerStyle={{ paddingBottom: 50 }}>
                {/* Warning when TrackPlayer not initialized */}
                {hasNoBands && (
                    <View style={styles.warningBanner}>
                        <Text style={styles.warningText}>
                            ⚠️ Please load and play a track first to use the equalizer
                        </Text>
                    </View>
                )}

                {/* Enable/Disable Switch */}
                <View style={commonStyles.section}>
                    <View style={styles.row}>
                        <Text style={commonStyles.sectionTitle}>Enable Equalizer</Text>
                        <Switch
                            value={isEnabled}
                            onValueChange={(val) => {
                                try {
                                    const success = setEnabled(val);
                                    if (!success && val) {
                                        Alert.alert(
                                            'Cannot Enable Equalizer',
                                            'Please load and play a track first before enabling the equalizer.'
                                        );
                                    }
                                } catch (error) {
                                    Alert.alert(
                                        'Cannot Enable Equalizer',
                                        'Please load and play a track first before enabling the equalizer.'
                                    );
                                }
                            }}
                            trackColor={{ false: '#767577', true: colors.primary }}
                            thumbColor={colors.white}
                        />
                    </View>
                    <Text style={commonStyles.infoText}>
                        {isEnabled ? 'Equalizer is currently active.' : 'Equalizer is bypassed.'}
                    </Text>
                </View>

                {/* Presets */}
                <View style={commonStyles.section}>
                    <View style={styles.headerRow}>
                        <Text style={commonStyles.sectionTitle}>Presets</Text>
                        <TouchableOpacity onPress={handleSavePreset} disabled={!isEnabled}>
                            <Text style={[styles.actionText, !isEnabled && styles.disabledText]}>
                                + Save Custom
                            </Text>
                        </TouchableOpacity>
                    </View>

                    <ScrollView horizontal showsHorizontalScrollIndicator={false} style={styles.presetScroll}>
                        {presets.map((preset) => {
                            const isActive = currentPreset === preset.name;
                            const isCustom = preset.type === 'custom';

                            return (
                                <TouchableOpacity
                                    key={preset.name}
                                    style={[
                                        styles.presetBadge,
                                        isActive && styles.activePresetBadge,
                                        !isEnabled && styles.disabledBadge
                                    ]}
                                    onPress={() => isEnabled && applyPreset(preset.name)}
                                    onLongPress={() => isEnabled && isCustom && handleDeletePreset(preset.name)}
                                    disabled={!isEnabled}
                                >
                                    <Text
                                        style={[
                                            styles.presetText,
                                            isActive && styles.activePresetText,
                                            !isEnabled && styles.disabledText
                                        ]}
                                    >
                                        {preset.name}
                                    </Text>
                                </TouchableOpacity>
                            );
                        })}
                    </ScrollView>
                    <Text style={styles.hintText}>
                        {isEnabled ? 'Tap to apply. Long press custom presets to delete.' : 'Enable equalizer to select presets.'}
                    </Text>
                </View>

                {/* Bands */}
                <View style={commonStyles.section}>
                    <View style={styles.headerRow}>
                        <Text style={commonStyles.sectionTitle}>Bands ({gainRange.min}dB to +{gainRange.max}dB)</Text>
                        <TouchableOpacity onPress={reset} disabled={!isEnabled}>
                            <Text style={[styles.actionText, !isEnabled && styles.disabledText]}>Reset</Text>
                        </TouchableOpacity>
                    </View>

                    <View style={styles.bandsContainer}>
                        {bands.map((band) => (
                            <View key={band.index} style={styles.sliderColumn}>
                                <Text style={styles.gainText}>
                                    {band.gainDb > 0 ? '+' : ''}{band.gainDb.toFixed(1)}
                                </Text>

                                <VerticalSlider
                                    value={band.gainDb}
                                    min={gainRange.min}
                                    max={gainRange.max}
                                    onChange={(val) => setBandGain(band.index, val)}
                                    disabled={!isEnabled}
                                    height={200}
                                />

                                <Text style={styles.freqText}>{band.frequencyLabel}</Text>
                            </View>
                        ))}
                    </View>
                </View>
            </ScrollView>
        </SafeAreaView>
    );
}

const styles = StyleSheet.create({
    center: {
        justifyContent: 'center',
        alignItems: 'center',
    },
    row: {
        flexDirection: 'row',
        justifyContent: 'space-between',
        alignItems: 'center',
        marginBottom: spacing.xs,
    },
    headerRow: {
        flexDirection: 'row',
        justifyContent: 'space-between',
        alignItems: 'center',
        marginBottom: spacing.md,
    },
    actionText: {
        color: colors.primary,
        fontSize: 14,
        fontWeight: '600',
    },
    disabledText: {
        color: colors.textTertiary,
    },
    presetScroll: {
        flexDirection: 'row',
        marginBottom: spacing.sm,
    },
    presetBadge: {
        paddingHorizontal: spacing.md,
        paddingVertical: spacing.sm,
        backgroundColor: colors.background,
        borderRadius: borderRadius.xl,
        marginRight: spacing.sm,
        borderWidth: 1,
        borderColor: colors.border,
    },
    activePresetBadge: {
        backgroundColor: colors.primary,
        borderColor: colors.primary,
    },
    disabledBadge: {
        opacity: 0.5,
    },
    presetText: {
        fontSize: 13,
        color: colors.textSecondary,
        fontWeight: '500',
    },
    activePresetText: {
        color: colors.white,
        fontWeight: '700',
    },
    hintText: {
        fontSize: 11,
        color: colors.textTertiary,
        fontStyle: 'italic',
    },
    bandsContainer: {
        flexDirection: 'row',
        justifyContent: 'space-between',
        paddingVertical: spacing.md,
    },
    sliderColumn: {
        alignItems: 'center',
        gap: spacing.sm,
        flex: 1,
    },
    gainText: {
        fontSize: 12,
        color: colors.textSecondary,
        fontVariant: ['tabular-nums'],
    },
    freqText: {
        fontSize: 11,
        fontWeight: '600',
        color: colors.text,
        marginTop: spacing.xs,
    },
    warningBanner: {
        backgroundColor: '#FFF3CD',
        padding: spacing.md,
        borderRadius: borderRadius.md,
        marginBottom: spacing.md,
        borderLeftWidth: 4,
        borderLeftColor: '#FFC107',
    },
    warningText: {
        fontSize: 14,
        color: '#856404',
        textAlign: 'center',
        fontWeight: '500',
    },
});
