import express from 'express';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createServer as createViteServer } from 'vite';
import { buildZipArchive, type ZipEntryInput } from './src/audio/protocol.ts';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REPO_ROOT = path.resolve(__dirname, 'audio_pro');

interface RepoFileEntry {
  path: string;
  category: 'Flutter' | 'Android' | 'iOS' | 'Windows' | 'CI/CD' | 'Root';
  sizeBytes: number;
  lines: number;
  content: string;
}

function classifyPath(relPath: string): RepoFileEntry['category'] {
  if (relPath.startsWith('.github/')) return 'CI/CD';
  if (relPath.startsWith('android/')) return 'Android';
  if (relPath.startsWith('ios/')) return 'iOS';
  if (relPath.startsWith('windows/')) return 'Windows';
  if (relPath.startsWith('lib/') || relPath.startsWith('test/') || relPath === 'pubspec.yaml') {
    return 'Flutter';
  }
  return 'Root';
}

function walkRepoFiles(dir: string, baseDir: string, includeGit = false): string[] {
  if (!fs.existsSync(dir)) return [];
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  const results: string[] = [];
  for (const entry of entries) {
    if (!includeGit && entry.name === '.git') continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      results.push(...walkRepoFiles(full, baseDir, includeGit));
    } else if (entry.isFile()) {
      results.push(path.relative(baseDir, full).replace(/\\/g, '/'));
    }
  }
  return results.sort();
}

async function startServer() {
  const app = express();
  const port = 3000;

  app.get('/api/repo/files', (_req, res) => {
    try {
      const relPaths = walkRepoFiles(REPO_ROOT, REPO_ROOT, false);
      const files: RepoFileEntry[] = relPaths.map((rel) => {
        const full = path.join(REPO_ROOT, rel);
        const content = fs.readFileSync(full, 'utf8');
        return {
          path: rel,
          category: classifyPath(rel),
          sizeBytes: Buffer.byteLength(content, 'utf8'),
          lines: content.split('\n').length,
          content,
        };
      });
      res.json({ repoName: 'audio_pro', fileCount: files.length, files });
    } catch (err) {
      res.status(500).json({ error: (err as Error).message });
    }
  });

  app.get('/api/repo/git', (_req, res) => {
    try {
      const branch = execFileSync('git', ['-C', REPO_ROOT, 'rev-parse', '--abbrev-ref', 'HEAD'], {
        encoding: 'utf8',
      }).trim();
      const commitHash = execFileSync('git', ['-C', REPO_ROOT, 'rev-parse', '--short', 'HEAD'], {
        encoding: 'utf8',
      }).trim();
      const commitMessage = execFileSync('git', ['-C', REPO_ROOT, 'log', '-1', '--pretty=%s'], {
        encoding: 'utf8',
      }).trim();
      const remoteOrigin = execFileSync('git', ['-C', REPO_ROOT, 'remote', 'get-url', 'origin'], {
        encoding: 'utf8',
      }).trim();
      const trackedFiles = execFileSync('git', ['-C', REPO_ROOT, 'ls-files'], {
        encoding: 'utf8',
      })
        .trim()
        .split('\n')
        .filter(Boolean).length;

      res.json({
        initialized: true,
        branch,
        commitHash,
        commitMessage,
        remoteOrigin,
        trackedFiles,
      });
    } catch (err) {
      res.json({
        initialized: false,
        error: (err as Error).message,
      });
    }
  });

  app.get('/api/repo/download', (_req, res) => {
    try {
      const relPaths = walkRepoFiles(REPO_ROOT, REPO_ROOT, false);
      const entries: ZipEntryInput[] = relPaths.map((rel) => ({
        path: `audio_pro/${rel}`,
        content: new Uint8Array(fs.readFileSync(path.join(REPO_ROOT, rel))),
      }));
      const zipBuffer = Buffer.from(buildZipArchive(entries));
      res.setHeader('Content-Type', 'application/zip');
      res.setHeader('Content-Disposition', 'attachment; filename="audio_pro.zip"');
      res.setHeader('Content-Length', String(zipBuffer.length));
      res.send(zipBuffer);
    } catch (err) {
      res.status(500).json({ error: (err as Error).message });
    }
  });

  if (process.env.NODE_ENV === 'production') {
    const distDir = path.resolve(__dirname, 'dist');
    app.use(express.static(distDir));
    app.get('*', (_req, res) => {
      res.sendFile(path.join(distDir, 'index.html'));
    });
  } else {
    const vite = await createViteServer({
      server: { middlewareMode: true },
      appType: 'spa',
    });
    app.use(vite.middlewares);
  }

  app.listen(port, '0.0.0.0', () => {
    console.log(`AudioPro Studio listening on http://0.0.0.0:${port}`);
  });
}

startServer();
