export function PlatformBadge({
  platform,
}: {
  platform: 'ios' | 'android' | 'both';
}) {
  const config = {
    ios: {
      label: 'iOS',
      bg: 'bg-blue-500/10',
      text: 'text-blue-400',
      border: 'border-blue-500/20',
    },
    android: {
      label: 'Android',
      bg: 'bg-green-500/10',
      text: 'text-green-400',
      border: 'border-green-500/20',
    },
    both: {
      label: 'iOS & Android',
      bg: 'bg-violet-500/10',
      text: 'text-violet-400',
      border: 'border-violet-500/20',
    },
  };

  const { label, bg, text, border } = config[platform];

  return (
    <span
      className={`inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium border ${bg} ${text} ${border}`}
      style={{ fontFamily: 'var(--font-jetbrains)' }}
    >
      {label}
    </span>
  );
}
