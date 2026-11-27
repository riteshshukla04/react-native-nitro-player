import { StyleSheet } from 'react-native';

export const colors = {
  primary: '#1DB954',
  secondary: '#FF9F0A',
  danger: '#FF453A',
  success: '#30D158',
  background: '#0B0B12',
  white: '#ffffff',
  cardBackground: '#1C1C28',
  surface: '#14141E',
  text: '#F5F5F7',
  textSecondary: '#A1A1B5',
  textTertiary: '#6E6E85',
  border: '#2A2A3A',
  progressBackground: '#34344A',
  activeBackground: '#1B3A2A',
  activeBorder: '#1DB954',
  infoBackground: '#2E2A17',
  infoBorder: '#FFC107',
  onPrimary: '#06130B',
};

export const spacing = {
  xs: 4,
  sm: 8,
  md: 12,
  lg: 16,
  xl: 20,
};

export const borderRadius = {
  sm: 6,
  md: 8,
  lg: 12,
  xl: 25,
  xxl: 35,
  card: 20,
};

export const typography = {
  h1: {
    fontSize: 20,
    fontWeight: '700' as const,
  },
  h2: {
    fontSize: 18,
    fontWeight: '600' as const,
  },
  h3: {
    fontSize: 16,
    fontWeight: '600' as const,
  },
  body: {
    fontSize: 15,
    fontWeight: '400' as const,
  },
  bodySmall: {
    fontSize: 14,
    fontWeight: '400' as const,
  },
  caption: {
    fontSize: 13,
    fontWeight: '400' as const,
  },
  small: {
    fontSize: 12,
    fontWeight: '400' as const,
  },
  button: {
    fontSize: 14,
    fontWeight: '600' as const,
  },
};

export const commonStyles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  scrollView: {
    flex: 1,
  },
  section: {
    backgroundColor: colors.surface,
    marginHorizontal: spacing.lg,
    marginVertical: spacing.sm,
    padding: spacing.lg,
    borderRadius: borderRadius.card,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
  },
  sectionTitle: {
    ...typography.h2,
    color: colors.text,
    marginBottom: spacing.md,
  },
  card: {
    backgroundColor: colors.cardBackground,
    padding: spacing.lg,
    borderRadius: borderRadius.md,
  },
  button: {
    backgroundColor: colors.primary,
    padding: spacing.md,
    borderRadius: borderRadius.md,
    alignItems: 'center',
    marginVertical: spacing.xs,
  },
  smallButton: {
    backgroundColor: colors.primary,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    borderRadius: borderRadius.xl,
    marginHorizontal: spacing.xs,
  },
  buttonText: {
    color: colors.onPrimary,
    ...typography.button,
  },
  infoText: {
    ...typography.bodySmall,
    color: colors.textSecondary,
    marginBottom: spacing.xs,
    lineHeight: 20,
  },
});
