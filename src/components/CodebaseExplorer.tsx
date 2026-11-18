import { Check, Copy, FileCode2, Search } from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';

export interface RepoFileEntry {
  path: string;
  category: 'Flutter' | 'Android' | 'iOS' | 'Windows' | 'CI/CD' | 'Root';
  sizeBytes: number;
  lines: number;
  content: string;
}

const CATEGORIES: Array<'All' | RepoFileEntry['category']> = [
  'All',
  'Flutter',
  'Android',
  'iOS',
  'Windows',
  'CI/CD',
];

export function CodebaseExplorer() {
  const [files, setFiles] = useState<RepoFileEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [category, setCategory] = useState<'All' | RepoFileEntry['category']>('All');
  const [query, setQuery] = useState('');
  const [selectedPath, setSelectedPath] = useState<string>('lib/main.dart');
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    fetch('/api/repo/files')
      .then((res) => {
        if (!res.ok) throw new Error(`Failed to load codebase (${res.status})`);
        return res.json();
      })
      .then((data: { files: RepoFileEntry[] }) => {
        if (cancelled) return;
        setFiles(data.files);
        if (data.files.length > 0 && !data.files.some((f) => f.path === selectedPath)) {
          setSelectedPath(data.files[0].path);
        }
        setLoading(false);
      })
      .catch((err: Error) => {
        if (cancelled) return;
        setError(err.message);
        setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const filteredFiles = useMemo(() => {
    const q = query.trim().toLowerCase();
    return files.filter((f) => {
      const catMatch = category === 'All' || f.category === category;
      const textMatch = q === '' || f.path.toLowerCase().includes(q);
      return catMatch && textMatch;
    });
  }, [files, category, query]);

  const activeFile = useMemo(
    () => files.find((f) => f.path === selectedPath) ?? filteredFiles[0] ?? null,
    [files, filteredFiles, selectedPath]
  );

  const handleCopy = async () => {
    if (!activeFile) return;
    try {
      await navigator.clipboard.writeText(activeFile.content);
      setCopied(true);
      setTimeout(() => setCopied(false), 1800);
    } catch {
      // Clipboard blocked in non-HTTPS contexts; ignore silently
    }
  };

  if (loading) {
    return (
      <div className="rounded-xl border border-white/[0.08] bg-[#111622] p-6">
        <div className="h-6 w-48 animate-pulse rounded bg-white/[0.06]" />
        <div className="mt-4 h-96 animate-pulse rounded-lg bg-white/[0.04]" />
      </div>
    );
  }

  if (error) {
    return (
      <div className="rounded-xl border border-rose-500/30 bg-[#111622] p-6 text-sm text-rose-300">
        {error}
      </div>
    );
  }

  return (
    <div className="grid grid-cols-1 gap-5 lg:grid-cols-[310px_1fr]">
      {/* Left sidebar: filter & file list */}
      <aside className="flex flex-col rounded-xl border border-white/[0.08] bg-[#111622] p-4">
        <div className="mb-3 flex items-center justify-between">
          <h2 className="font-display text-sm font-semibold text-slate-100">
            audio_pro Repository
          </h2>
          <span className="font-mono text-xs tabular-nums text-slate-400">
            {files.length} files
          </span>
        </div>

        <div className="relative mb-3">
          <Search
            className="pointer-events-none absolute left-3 top-2.5 h-3.5 w-3.5 text-slate-400"
            aria-hidden="true"
          />
          <label htmlFor="repo-search" className="sr-only">
            Filter repository files
          </label>
          <input
            id="repo-search"
            type="text"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Filter path (e.g. AudioProService)"
            className="w-full rounded-lg border border-white/[0.08] bg-[#090C12] py-2 pl-8 pr-3 text-xs text-slate-100 placeholder:text-slate-500 focus:border-cyan-400 focus:outline-none"
          />
        </div>

        <div className="mb-3 flex flex-wrap gap-1 rounded-lg bg-[#090C12] p-1 border border-white/[0.06]">
          {CATEGORIES.map((cat) => (
            <button
              key={cat}
              type="button"
              onClick={() => setCategory(cat)}
              className={`rounded-md px-2.5 py-1 text-[11px] font-medium transition-colors whitespace-nowrap shrink-0 ${
                category === cat
                  ? 'bg-[#1B2336] text-cyan-300'
                  : 'text-slate-400 hover:text-slate-200'
              }`}
            >
              {cat}
            </button>
          ))}
        </div>

        <div className="max-h-[540px] flex-1 space-y-0.5 overflow-y-auto pr-1">
          {filteredFiles.length === 0 ? (
            <div className="py-8 text-center text-xs text-slate-400">
              No files match your filter.
              <div className="mt-2">
                <button
                  type="button"
                  onClick={() => {
                    setCategory('All');
                    setQuery('');
                  }}
                  className="text-cyan-300 hover:underline"
                >
                  Reset filters
                </button>
              </div>
            </div>
          ) : (
            filteredFiles.map((file) => {
              const selected = activeFile?.path === file.path;
              return (
                <button
                  key={file.path}
                  type="button"
                  onClick={() => setSelectedPath(file.path)}
                  className={`flex w-full items-center justify-between gap-2 rounded-lg px-2.5 py-2 text-left text-xs transition-colors ${
                    selected
                      ? 'bg-cyan-400/10 text-cyan-200 border border-cyan-400/30'
                      : 'text-slate-300 hover:bg-white/[0.04] border border-transparent'
                  }`}
                >
                  <span className="flex min-w-0 items-center gap-2">
                    <FileCode2 className="h-3.5 w-3.5 shrink-0 text-slate-400" aria-hidden="true" />
                    <span className="truncate font-mono text-[11px]">{file.path}</span>
                  </span>
                  <span className="shrink-0 font-mono text-[10px] tabular-nums text-slate-500">
                    {file.lines}L
                  </span>
                </button>
              );
            })
          )}
        </div>
      </aside>

      {/* Right pane: code viewer */}
      <div className="flex min-w-0 flex-col rounded-xl border border-white/[0.08] bg-[#111622]">
        <div className="flex flex-wrap items-center justify-between gap-3 border-b border-white/[0.06] px-5 py-3.5">
          <div className="min-w-0">
            <p className="truncate font-mono text-xs font-medium text-slate-100">
              {activeFile?.path ?? 'No file selected'}
            </p>
            {activeFile && (
              <p className="mt-0.5 text-[11px] text-slate-400">
                {activeFile.category} · {activeFile.lines} lines ·{' '}
                {(activeFile.sizeBytes / 1024).toFixed(1)} KB
              </p>
            )}
          </div>

          {activeFile && (
            <button
              type="button"
              onClick={handleCopy}
              className="inline-flex items-center gap-1.5 rounded-lg border border-white/[0.08] bg-[#0B0F18] px-3 py-1.5 text-xs font-medium text-slate-200 hover:border-cyan-400/50 whitespace-nowrap shrink-0"
            >
              {copied ? (
                <>
                  <Check className="h-3.5 w-3.5 text-emerald-400" aria-hidden="true" />
                  Copied
                </>
              ) : (
                <>
                  <Copy className="h-3.5 w-3.5 text-slate-400" aria-hidden="true" />
                  Copy File
                </>
              )}
            </button>
          )}
        </div>

        <div className="max-h-[600px] overflow-auto bg-[#090C12] p-4 rounded-b-xl">
          <pre className="font-mono text-xs leading-relaxed text-slate-200">
            <code>{activeFile?.content ?? ''}</code>
          </pre>
        </div>
      </div>
    </div>
  );
}
