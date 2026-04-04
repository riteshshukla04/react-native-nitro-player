'use client';

import { useState } from 'react';

const managers = [
  { name: 'npm', command: 'npm install react-native-nitro-player' },
  { name: 'yarn', command: 'yarn add react-native-nitro-player' },
  { name: 'bun', command: 'bun add react-native-nitro-player' },
] as const;

export function InstallCommand() {
  const [active, setActive] = useState(0);
  const [copied, setCopied] = useState(false);

  const copy = async () => {
    await navigator.clipboard.writeText(managers[active].command);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="w-full max-w-lg mx-auto rounded-lg border border-fd-border bg-fd-card overflow-hidden">
      {/* Tab bar */}
      <div className="flex border-b border-fd-border">
        {managers.map((m, i) => (
          <button
            key={m.name}
            onClick={() => setActive(i)}
            className={`px-4 py-2 text-sm font-medium transition-colors cursor-pointer ${
              i === active
                ? 'text-violet-600 dark:text-violet-400 border-b-2 border-violet-600 dark:border-violet-400'
                : 'text-fd-muted-foreground hover:text-fd-foreground'
            }`}
            style={{ fontFamily: 'var(--font-jetbrains)' }}
          >
            {m.name}
          </button>
        ))}
      </div>
      {/* Command display */}
      <div className="flex items-center gap-3 px-4 py-3">
        <span className="text-violet-600 dark:text-violet-500 select-none">$</span>
        <code
          className="text-sm text-fd-foreground flex-1"
          style={{ fontFamily: 'var(--font-jetbrains)' }}
        >
          {managers[active].command}
        </code>
        <button
          onClick={copy}
          className="text-fd-muted-foreground hover:text-violet-600 dark:hover:text-violet-400 transition-colors cursor-pointer"
          aria-label="Copy command"
        >
          {copied ? (
            <svg
              width="16"
              height="16"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
            >
              <polyline points="20 6 9 17 4 12" />
            </svg>
          ) : (
            <svg
              width="16"
              height="16"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
            >
              <rect x="9" y="9" width="13" height="13" rx="2" ry="2" />
              <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
            </svg>
          )}
        </button>
      </div>
    </div>
  );
}
