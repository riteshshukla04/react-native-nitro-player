import { describe, it, expect } from 'react-native-harness';
import { durationLabel } from '../../src/utils/durationLabel';

const fmt = (s: number) => `${s}s`;

describe('live radio duration label', () => {
  it('does not throw before any stream metadata has arrived', () => {
    expect(() => durationLabel(0, undefined, 0, fmt)).not.toThrow();
    expect(durationLabel(0, undefined, 0, fmt)).toBe('LIVE');
  });

  it('shows the stream title once metadata arrives', () => {
    expect(durationLabel(0, { title: 'Song' }, 0, fmt)).toBe('LIVE · Song');
  });

  it('formats normal tracks', () => {
    expect(durationLabel(182, undefined, 182, fmt)).toBe('182s');
  });
});
