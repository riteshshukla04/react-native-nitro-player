import Link from 'next/link';
import { WaveformBackground } from '@/components/waveform';
import { InstallCommand } from '@/components/install-command';

const features = [
  {
    title: 'Nitro Powered',
    description:
      'Built on Nitro Modules with native Kotlin & Swift implementations. Zero bridge overhead — direct native bindings to JS.',
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
        <path d="M13 2L3 14h9l-1 8 10-12h-9l1-8z" />
      </svg>
    ),
  },
  {
    title: 'Smart Queue System',
    description:
      'playNext stack (LIFO) + upNext queue (FIFO) + playlists. Full CRUD with reordering and persistence.',
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
        <line x1="8" y1="6" x2="21" y2="6" />
        <line x1="8" y1="12" x2="21" y2="12" />
        <line x1="8" y1="18" x2="21" y2="18" />
        <line x1="3" y1="6" x2="3.01" y2="6" />
        <line x1="3" y1="12" x2="3.01" y2="12" />
        <line x1="3" y1="18" x2="3.01" y2="18" />
      </svg>
    ),
  },
  {
    title: 'Offline Downloads',
    description:
      'Full download manager with progress tracking, pause/resume, retry, storage management, and smart playback source.',
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
        <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
        <polyline points="7 10 12 15 17 10" />
        <line x1="12" y1="15" x2="12" y2="3" />
      </svg>
    ),
  },
  {
    title: '10-Band Equalizer',
    description:
      '19 built-in presets from Rock to Headphones. Create custom presets. Per-band gain control with -12 to +12 dB range.',
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
        <line x1="4" y1="21" x2="4" y2="14" />
        <line x1="4" y1="10" x2="4" y2="3" />
        <line x1="12" y1="21" x2="12" y2="12" />
        <line x1="12" y1="8" x2="12" y2="3" />
        <line x1="20" y1="21" x2="20" y2="16" />
        <line x1="20" y1="12" x2="20" y2="3" />
        <line x1="1" y1="14" x2="7" y2="14" />
        <line x1="9" y1="8" x2="15" y2="8" />
        <line x1="17" y1="16" x2="23" y2="16" />
      </svg>
    ),
  },
  {
    title: 'Car Integration',
    description:
      'First-class Android Auto support with custom media browsing, plus CarPlay. Control Center and lock screen controls.',
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
        <rect x="2" y="7" width="20" height="14" rx="2" />
        <path d="M17 2l-5 5-5-5" />
      </svg>
    ),
  },
];


export default function HomePage() {
  return (
    <main className="relative min-h-screen overflow-hidden bg-fd-background">
      <WaveformBackground />

      {/* Hero Section */}
      <section className="relative z-10 flex flex-col items-center justify-center px-6 pt-32 pb-20 text-center">
        {/* Version badge */}
        <div className="mb-6">
          <span
            className="inline-flex items-center gap-2 px-3 py-1 text-xs rounded-full border border-violet-500/30 bg-violet-500/10 text-violet-600 dark:text-violet-300"
            style={{ fontFamily: 'var(--font-jetbrains)' }}
          >
            <span className="w-2 h-2 rounded-full bg-green-400 animate-pulse" />
            v1.2.1 — Stable Release
          </span>
        </div>

        {/* Headline */}
        <h1
          className="max-w-4xl text-4xl sm:text-5xl md:text-6xl lg:text-7xl font-bold leading-[1.1] tracking-tight"
          style={{ fontFamily: 'var(--font-jetbrains)' }}
        >
          <span className="text-fd-foreground">The Audio Player</span>
          <br />
          <span
            className="bg-clip-text text-transparent"
            style={{
              backgroundImage: 'linear-gradient(135deg, #7c3aed 0%, #22c55e 50%, #7c3aed 100%)',
              backgroundSize: '200% 200%',
            }}
          >
            React Native Deserves
          </span>
        </h1>

        {/* Subtitle */}
        <p className="mt-6 max-w-2xl text-lg text-fd-muted-foreground leading-relaxed">
          Native performance powered by Nitro Modules. Full playback control, playlist management,
          offline downloads, equalizer, and car integration — all with type-safe APIs.
        </p>

        {/* CTAs */}
        <div className="flex flex-wrap items-center justify-center gap-4 mt-10">
          <Link
            href="/docs"
            className="inline-flex items-center gap-2 px-6 py-3 text-sm font-semibold rounded-lg text-white transition-all hover:scale-[1.02] cursor-pointer"
            style={{
              background: 'linear-gradient(135deg, #22c55e 0%, #16a34a 100%)',
              boxShadow: '0 0 20px rgba(34, 197, 94, 0.3)',
              fontFamily: 'var(--font-jetbrains)',
            }}
          >
            Get Started
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <line x1="5" y1="12" x2="19" y2="12" />
              <polyline points="12 5 19 12 12 19" />
            </svg>
          </Link>
          <a
            href="https://github.com/riteshshukla04/react-native-nitro-player"
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-2 px-6 py-3 text-sm font-semibold rounded-lg text-violet-600 dark:text-violet-300 border border-violet-500/30 transition-all hover:bg-violet-500/10 hover:border-violet-500/50 cursor-pointer"
            style={{ fontFamily: 'var(--font-jetbrains)' }}
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
              <path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z" />
            </svg>
            GitHub
          </a>
        </div>

        {/* Install command */}
        <div className="mt-12 w-full max-w-lg">
          <InstallCommand />
        </div>

      </section>

      {/* Features Section */}
      <section className="relative z-10 px-6 pb-32">
        <div className="max-w-6xl mx-auto">
          <h2
            className="text-2xl font-bold text-center text-fd-foreground mb-12"
            style={{ fontFamily: 'var(--font-jetbrains)' }}
          >
            Everything you need for audio
          </h2>

          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-5">
            {features.map((feature) => (
              <div
                key={feature.title}
                className="gradient-border group cursor-pointer"
              >
                <div className="relative z-10 p-6 rounded-xl bg-fd-card">
                  <div className="flex items-center gap-3 mb-3">
                    <div className="text-violet-600 dark:text-violet-400 group-hover:text-green-500 dark:group-hover:text-green-400 transition-colors">
                      {feature.icon}
                    </div>
                    <h3
                      className="font-semibold text-fd-foreground"
                      style={{ fontFamily: 'var(--font-jetbrains)' }}
                    >
                      {feature.title}
                    </h3>
                  </div>
                  <p className="text-sm text-fd-muted-foreground leading-relaxed">
                    {feature.description}
                  </p>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Bottom CTA */}
      <section className="relative z-10 px-6 pb-24">
        <div className="max-w-2xl mx-auto text-center">
          <p className="text-fd-muted-foreground text-sm" style={{ fontFamily: 'var(--font-jetbrains)' }}>
            Built with Nitro Modules by{' '}
            <a
              href="https://github.com/riteshshukla04"
              className="text-violet-600 dark:text-violet-400 hover:text-violet-500 dark:hover:text-violet-300 transition-colors"
              target="_blank"
              rel="noopener noreferrer"
            >
              Ritesh Shukla
            </a>
          </p>
        </div>
      </section>
    </main>
  );
}
