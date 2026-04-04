import { ImageResponse } from 'next/og';
import type { NextRequest } from 'next/server';

export const runtime = 'edge';

export async function GET(req: NextRequest) {
  const { searchParams } = new URL(req.url);
  const title = searchParams.get('title') ?? 'Nitro Player';
  const description =
    searchParams.get('description') ??
    'A powerful audio player library for React Native';

  const bars = [
    { h: 55, d: 0 },
    { h: 85, d: 1 },
    { h: 65, d: 2 },
    { h: 95, d: 3 },
    { h: 50, d: 4 },
    { h: 75, d: 5 },
    { h: 90, d: 6 },
    { h: 60, d: 7 },
    { h: 80, d: 8 },
    { h: 45, d: 9 },
    { h: 70, d: 10 },
    { h: 100, d: 11 },
  ];

  return new ImageResponse(
    (
      <div
        style={{
          width: '100%',
          height: '100%',
          display: 'flex',
          flexDirection: 'column',
          justifyContent: 'center',
          alignItems: 'flex-start',
          background: '#0a0a1a',
          padding: '60px 80px',
          position: 'relative',
          overflow: 'hidden',
        }}
      >
        {/* Background waveform bars */}
        <div
          style={{
            position: 'absolute',
            right: 60,
            bottom: 40,
            display: 'flex',
            alignItems: 'flex-end',
            gap: 8,
            opacity: 0.15,
          }}
        >
          {bars.map((bar, i) => (
            <div
              key={i}
              style={{
                width: 16,
                height: `${bar.h * 3}px`,
                borderRadius: 8,
                background: 'linear-gradient(to top, #7c3aed, #22c55e)',
              }}
            />
          ))}
        </div>

        {/* Logo waveform */}
        <div
          style={{
            display: 'flex',
            alignItems: 'flex-end',
            gap: 4,
            marginBottom: 32,
          }}
        >
          {[60, 100, 70, 90, 50].map((h, i) => (
            <div
              key={i}
              style={{
                width: 8,
                height: `${h * 0.5}px`,
                borderRadius: 4,
                background: 'linear-gradient(to top, #7c3aed, #22c55e)',
              }}
            />
          ))}
        </div>

        {/* Title */}
        <div
          style={{
            fontSize: 56,
            fontWeight: 700,
            color: '#f8fafc',
            lineHeight: 1.1,
            marginBottom: 16,
            maxWidth: '80%',
          }}
        >
          {title}
        </div>

        {/* Description */}
        <div
          style={{
            fontSize: 24,
            color: '#94a3b8',
            lineHeight: 1.4,
            maxWidth: '70%',
          }}
        >
          {description}
        </div>

        {/* Bottom bar */}
        <div
          style={{
            position: 'absolute',
            bottom: 40,
            left: 80,
            display: 'flex',
            alignItems: 'center',
            gap: 12,
          }}
        >
          <div
            style={{
              fontSize: 18,
              color: '#7c3aed',
              fontWeight: 600,
            }}
          >
            react-native-nitro-player
          </div>
          <div style={{ fontSize: 18, color: '#475569' }}>|</div>
          <div style={{ fontSize: 18, color: '#475569' }}>v1.0.1</div>
        </div>
      </div>
    ),
    {
      width: 1200,
      height: 630,
    },
  );
}
