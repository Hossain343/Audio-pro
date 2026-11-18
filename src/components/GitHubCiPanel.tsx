import { Check, Copy, Download, GitBranch, PlayCircle, Terminal } from 'lucide-react';
import { useEffect, useState } from 'react';

interface GitStatusResponse {
  initialized: boolean;
  syncMode?: string;
  branch?: string;
  workflowPath?: string;
  nestedGitPresent?: boolean;
  trackedFiles?: number;
  error?: string;
}

const CI_JOBS = [
  {
    id: 'analyze_and_test',
    title: '01. Dart Analyze & Unit Tests',
    runner: 'ubuntu-latest',
    command: 'flutter analyze && flutter test',
    artifact: 'Lint & test gate',
  },
  {
    id: 'build_android',
    title: '02. Android Release Build',
    runner: 'ubuntu-latest · Java 17',
    command: 'flutter build apk --release --split-per-abi && flutter build appbundle --release',
    artifact: 'audio_pro-android-release (.apk + .aab)',
  },
  {
    id: 'build_windows',
    title: '03. Windows x64 Host Build',
    runner: 'windows-latest · MSVC',
    command: 'flutter build windows --release',
    artifact: 'audio_pro-windows-x64.zip',
  },
  {
    id: 'build_ios',
    title: '04. iOS Unsigned Archive',
    runner: 'macos-latest · Xcode',
    command: 'pod install && flutter build ios --release --no-codesign',
    artifact: 'audio_pro-ios-unsigned.ipa',
  },
];

export function GitHubCiPanel() {
  const [gitInfo, setGitInfo] = useState<GitStatusResponse | null>(null);
  const [copiedCmd, setCopiedCmd] = useState(false);

  useEffect(() => {
    fetch('/api/repo/git')
      .then((res) => res.json())
      .then((data: GitStatusResponse) => setGitInfo(data))
      .catch((err: Error) => setGitInfo({ initialized: false, error: err.message }));
  }, []);

  const pushCommands = [
    '# In AI Studio: Open GitHub Sync panel -> Push changes to main',
    '# Or locally from extracted audio_pro.zip:',
    'git init -b main && git add -A && git commit -m "feat: sync audio_pro + workflows"',
    'git remote add origin https://github.com/Hossain343/Audio-pro.git',
    'git push -u origin main',
  ].join('\n');

  const handleCopyCommands = async () => {
    try {
      await navigator.clipboard.writeText(pushCommands);
      setCopiedCmd(true);
      setTimeout(() => setCopiedCmd(false), 1800);
    } catch {
      // ignore
    }
  };

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-1 gap-5 lg:grid-cols-2">
        <section className="rounded-xl border border-white/[0.08] bg-[#111622] p-5">
          <div className="mb-4 flex items-center justify-between border-b border-white/[0.06] pb-3">
            <div className="flex items-center gap-2">
              <GitBranch className="h-4 w-4 text-cyan-400" aria-hidden="true" />
              <h2 className="font-display text-base font-semibold text-slate-100">
                GitHub Sync Readiness
              </h2>
            </div>
            <span className="font-mono text-xs text-emerald-400">
              {gitInfo?.initialized && !gitInfo.nestedGitPresent ? 'Ready to Sync' : 'Checking...'}
            </span>
          </div>

          {gitInfo?.initialized ? (
            <dl className="space-y-3 text-xs">
              <div className="flex items-center justify-between border-b border-white/[0.05] pb-2">
                <dt className="text-slate-400">Sync Mode</dt>
                <dd className="font-mono font-medium text-slate-100">{gitInfo.syncMode}</dd>
              </div>
              <div className="flex items-center justify-between border-b border-white/[0.05] pb-2">
                <dt className="text-slate-400">Target Branch</dt>
                <dd className="font-mono font-semibold text-slate-100">{gitInfo.branch}</dd>
              </div>
              <div className="flex items-center justify-between border-b border-white/[0.05] pb-2">
                <dt className="text-slate-400">Workflow File</dt>
                <dd className="font-mono text-cyan-300">{gitInfo.workflowPath}</dd>
              </div>
              <div className="flex items-center justify-between border-b border-white/[0.05] pb-2">
                <dt className="text-slate-400">Flutter + Native Files</dt>
                <dd className="font-mono tabular-nums text-slate-100">
                  {gitInfo.trackedFiles} files
                </dd>
              </div>
              <div className="flex items-center justify-between">
                <dt className="text-slate-400">Nested Submodule Lock</dt>
                <dd className="font-mono text-emerald-400">
                  {gitInfo.nestedGitPresent ? 'Detected (needs removal)' : 'Clean (Removed)'}
                </dd>
              </div>
            </dl>
          ) : (
            <p className="text-xs text-slate-400">
              {gitInfo?.error ?? 'Loading repository metadata...'}
            </p>
          )}
        </section>

        <section className="rounded-xl border border-white/[0.08] bg-[#111622] p-5">
          <div className="mb-3 flex items-center justify-between gap-2">
            <div className="flex items-center gap-2">
              <Terminal className="h-4 w-4 text-cyan-400" aria-hidden="true" />
              <h2 className="font-display text-base font-semibold text-slate-100">
                Sync & Trigger GitHub Actions
              </h2>
            </div>
            <button
              type="button"
              onClick={handleCopyCommands}
              className="inline-flex items-center gap-1.5 rounded-lg border border-white/[0.08] bg-[#0B0F18] px-3 py-1.5 text-xs font-medium text-slate-200 hover:border-cyan-400/50 whitespace-nowrap shrink-0"
            >
              {copiedCmd ? (
                <>
                  <Check className="h-3.5 w-3.5 text-emerald-400" aria-hidden="true" />
                  Copied
                </>
              ) : (
                <>
                  <Copy className="h-3.5 w-3.5 text-slate-400" aria-hidden="true" />
                  Copy Commands
                </>
              )}
            </button>
          </div>

          <p className="mb-3 text-xs leading-relaxed text-slate-300">
            The nested <span className="font-mono text-cyan-300">audio_pro/.git</span> folder was
            removed and <span className="font-mono text-cyan-300">.github/workflows/build.yml</span>{' '}
            is now at the repository root. Sync from the AI Studio GitHub panel to push all files
            and start the builds automatically.
          </p>

          <pre className="overflow-x-auto rounded-lg border border-white/[0.06] bg-[#090C12] p-3.5 font-mono text-xs leading-relaxed text-slate-200">
            {pushCommands}
          </pre>

          <div className="mt-4 flex items-center justify-end">
            <a
              href="/api/repo/download"
              download="audio_pro.zip"
              className="inline-flex items-center gap-2 rounded-lg bg-cyan-400 px-4 py-2 text-xs font-semibold text-slate-950 hover:bg-cyan-300"
            >
              <Download className="h-3.5 w-3.5" aria-hidden="true" />
              Download audio_pro.zip
            </a>
          </div>
        </section>
      </div>

      <section className="rounded-xl border border-white/[0.08] bg-[#111622] p-5">
        <div className="mb-4 flex flex-wrap items-center justify-between gap-2 border-b border-white/[0.06] pb-3">
          <div className="flex items-center gap-2">
            <PlayCircle className="h-4 w-4 text-cyan-400" aria-hidden="true" />
            <h2 className="font-display text-base font-semibold text-slate-100">
              GitHub Actions Matrix (.github/workflows/build.yml)
            </h2>
          </div>
          <span className="font-mono text-xs text-slate-400">
            Working directory: ./audio_pro · Triggers on push to main
          </span>
        </div>

        <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
          {CI_JOBS.map((job) => (
            <div
              key={job.id}
              className="rounded-lg border border-white/[0.06] bg-[#0B0F18] p-4"
            >
              <div className="flex items-center justify-between gap-2">
                <h3 className="font-display text-sm font-semibold text-slate-100">
                  {job.title}
                </h3>
                <span className="font-mono text-[11px] text-slate-400">{job.runner}</span>
              </div>
              <p className="mt-2 rounded bg-[#090C12] px-2.5 py-2 font-mono text-[11px] text-cyan-300">
                {job.command}
              </p>
              <p className="mt-2 text-xs text-slate-400">Artifact: {job.artifact}</p>
            </div>
          ))}
        </div>
      </section>
    </div>
  );
}
