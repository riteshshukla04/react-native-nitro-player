/**
 * Label shown at the right end of the progress bar.
 * Live streams report duration 0; their ICY stream metadata (and so its
 * title) is undefined until the first timed-metadata event arrives.
 */
export function durationLabel(
  duration: number | undefined,
  streamMetadata: {title?: string} | null | undefined,
  totalDuration: number,
  formatTime: (s: number) => string
): string {
  if (duration !== 0) return formatTime(totalDuration);
  const title = streamMetadata?.title;
  return title ? `LIVE · ${title}` : 'LIVE';
}
