import { StyleSheet } from 'react-native';

export const colors = {
  primary: '#007AFF',
  secondary: '#FF9500',
  danger: '#FF3B30',
  success: '#34C759',
  background: '#f5f5f5',
  white: '#ffffff',
  cardBackground: '#f8f9fa',
  text: '#000000',
  textSecondary: '#666666',
  textTertiary: '#999999',
  border: '#e0e0e0',
  progressBackground: '#e0e0e0',
  activeBackground: '#e3f2fd',
  activeBorder: '#007AFF',
  infoBackground: '#fff3cd',
  infoBorder: '#ffc107',
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
    backgroundColor: colors.white,
    marginHorizontal: spacing.lg,
    marginVertical: spacing.sm,
    padding: spacing.lg,
    borderRadius: borderRadius.lg,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 3,
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
    borderRadius: borderRadius.sm,
    marginHorizontal: spacing.xs,
  },
  buttonText: {
    color: colors.white,
    ...typography.button,
  },
  infoText: {
    ...typography.bodySmall,
    color: colors.textSecondary,
    marginBottom: spacing.xs,
    lineHeight: 20,
  },
});
