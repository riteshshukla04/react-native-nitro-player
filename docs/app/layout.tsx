import './global.css';
import { RootProvider } from 'fumadocs-ui/provider';
import DefaultSearchDialog from 'fumadocs-ui/components/dialog/search-default';
import { JetBrains_Mono, IBM_Plex_Sans } from 'next/font/google';
import type { ReactNode } from 'react';
import type { Metadata } from 'next';

const jetbrainsMono = JetBrains_Mono({
  subsets: ['latin'],
  variable: '--font-jetbrains',
});

const ibmPlexSans = IBM_Plex_Sans({
  subsets: ['latin'],
  weight: ['300', '400', '500', '600', '700'],
  variable: '--font-ibm-plex',
});

export const metadata: Metadata = {
  title: {
    default: 'Nitro Player',
    template: '%s | Nitro Player',
  },
  description:
    'A powerful audio player library for React Native with playlist management, playback controls, and support for Android Auto and CarPlay.',
};

export default function Layout({ children }: { children: ReactNode }) {
  return (
    <html
      lang="en"
      className={`${jetbrainsMono.variable} ${ibmPlexSans.variable}`}
      suppressHydrationWarning
    >
      <body className="antialiased">
        <RootProvider
          theme={{
            defaultTheme: 'dark',
          }}
          search={{
            SearchDialog: DefaultSearchDialog,
          }}
        >
          {children}
        </RootProvider>
      </body>
    </html>
  );
}
