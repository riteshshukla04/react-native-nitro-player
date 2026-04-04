'use client';

export function Waveform({ className = '' }: { className?: string }) {
  const bars = [
    { delay: '0s', minH: 15, maxH: 85 },
    { delay: '0.15s', minH: 25, maxH: 100 },
    { delay: '0.3s', minH: 10, maxH: 70 },
    { delay: '0.1s', minH: 30, maxH: 95 },
    { delay: '0.25s', minH: 20, maxH: 60 },
    { delay: '0.05s', minH: 35, maxH: 90 },
    { delay: '0.2s', minH: 15, maxH: 75 },
    { delay: '0.35s', minH: 25, maxH: 80 },
    { delay: '0.12s', minH: 20, maxH: 95 },
    { delay: '0.28s', minH: 30, maxH: 70 },
    { delay: '0.08s', minH: 15, maxH: 85 },
    { delay: '0.22s', minH: 35, maxH: 100 },
    { delay: '0.18s', minH: 10, maxH: 65 },
    { delay: '0.32s', minH: 25, maxH: 90 },
    { delay: '0.02s', minH: 20, maxH: 80 },
    { delay: '0.26s', minH: 30, maxH: 75 },
  ];

  return (
    <div
      className={`flex items-end gap-[3px] ${className}`}
      aria-hidden="true"
    >
      {bars.map((bar, i) => (
        <div
          key={i}
          className="w-[4px] rounded-full"
          style={{
            background: 'linear-gradient(to top, #7c3aed, #22c55e)',
            animation: `waveform-bar 1.2s ease-in-out ${bar.delay} infinite`,
            height: `${bar.maxH}%`,
            minHeight: '4px',
            opacity: 0.6 + (i % 3) * 0.15,
          }}
        />
      ))}
    </div>
  );
}

export function WaveformBackground() {
  return (
    <div className="absolute inset-0 overflow-hidden pointer-events-none">
      {/* Radial gradient backdrop */}
      <div
        className="absolute inset-0"
        style={{
          background:
            'radial-gradient(ellipse 80% 60% at 50% 40%, rgba(124, 58, 237, 0.12) 0%, transparent 70%)',
        }}
      />
      {/* Floating waveform left */}
      <div className="absolute left-[5%] bottom-[10%] h-32 opacity-20">
        <Waveform className="h-full" />
      </div>
      {/* Floating waveform right */}
      <div className="absolute right-[5%] top-[20%] h-24 opacity-15 rotate-180">
        <Waveform className="h-full" />
      </div>
      {/* Grid overlay */}
      <div
        className="absolute inset-0 opacity-[0.03]"
        style={{
          backgroundImage: `linear-gradient(rgba(124, 58, 237, 0.5) 1px, transparent 1px),
            linear-gradient(90deg, rgba(124, 58, 237, 0.5) 1px, transparent 1px)`,
          backgroundSize: '60px 60px',
        }}
      />
    </div>
  );
}
