import { Download } from 'lucide-react';

export type StudioTab = 'bridge' | 'codebase' | 'github';

interface TopBarProps {
  activeTab: StudioTab;
  onSelectTab: (tab: StudioTab) => void;
}

export function TopBar({ activeTab, onSelectTab }: TopBarProps) {
  const navItems: { id: StudioTab; label: string }[] = [
    { id: 'bridge', label: 'Bridge Studio' },
    { id: 'codebase', label: 'Codebase' },
    { id: 'github', label: 'GitHub CI' },
  ];

  return (
    <header className="border-b border-white/[0.08] bg-[#090C12]">
      <div className="mx-auto flex max-w-[1380px] items-center justify-between gap-3 px-4 py-3.5 sm:gap-8 sm:px-6 sm:py-4">
        <a
          href="#bridge"
          onClick={(e) => {
            e.preventDefault();
            onSelectTab('bridge');
          }}
          className="font-display text-base font-bold tracking-tight text-slate-100 whitespace-nowrap shrink-0 sm:text-lg"
        >
          AudioPro
        </a>

        <nav aria-label="Primary navigation" className="flex items-center gap-3 sm:gap-6">
          {navItems.map((item) => {
            const isActive = activeTab === item.id;
            return (
              <button
                key={item.id}
                type="button"
                onClick={() => onSelectTab(item.id)}
                className={`relative py-1 text-xs font-medium transition-colors whitespace-nowrap shrink-0 sm:text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-400 rounded ${
                  isActive
                    ? 'text-cyan-300'
                    : 'text-slate-400 hover:text-slate-100'
                }`}
              >
                {item.label}
                {isActive && (
                  <span
                    aria-hidden="true"
                    className="absolute inset-x-0 -bottom-[15px] h-[2px] bg-cyan-400 sm:-bottom-[17px]"
                  />
                )}
              </button>
            );
          })}
        </nav>

        <a
          href="/api/repo/download"
          download="audio_pro.zip"
          aria-label="Download Repo"
          className="inline-flex items-center gap-2 rounded-lg bg-cyan-400 px-2.5 py-2 text-xs font-semibold text-slate-950 transition-colors hover:bg-cyan-300 whitespace-nowrap shrink-0 sm:px-4 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-300"
        >
          <Download className="h-3.5 w-3.5" aria-hidden="true" />
          <span className="hidden sm:inline">Download Repo</span>
        </a>
      </div>
    </header>
  );
}
