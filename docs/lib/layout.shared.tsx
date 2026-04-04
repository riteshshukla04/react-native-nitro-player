import type { BaseLayoutProps } from 'fumadocs-ui/layouts/shared';

export function baseOptions(): BaseLayoutProps {
  return {
    nav: {
      title: (
        <div className="flex items-center gap-2.5">
          <div className="flex items-end gap-[2px] h-5">
            {[0.6, 1, 0.7, 0.9, 0.5].map((scale, i) => (
              <div
                key={i}
                className="w-[3px] rounded-full"
                style={{
                  height: `${scale * 100}%`,
                  background: `linear-gradient(to top, #7c3aed, #22c55e)`,
                  opacity: 0.9,
                }}
              />
            ))}
          </div>
          <span
            className="font-bold text-base tracking-tight"
            style={{ fontFamily: 'var(--font-jetbrains)' }}
          >
            Nitro Player
          </span>
        </div>
      ),
    },
    links: [
      {
        text: 'Docs',
        url: '/docs',
        active: 'nested-url',
      },
      {
        text: 'API',
        url: '/docs/api/track-player',
        active: 'nested-url',
      },
    ],
    githubUrl:
      'https://github.com/riteshshukla04/react-native-nitro-player',
  };
}
