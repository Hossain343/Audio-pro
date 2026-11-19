import express from 'express';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createServer as createViteServer } from 'vite';
import { buildZipArchive, type ZipEntryInput } from './src/audio/protocol.ts';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REPO_ROOT = path.resolve(__dirname, 'audio_pro');
const WORKFLOW_FILE = path.resolve(__dirname, '.github/workflows/build.yml');

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

function walkRepoFiles(dir: string, baseDir: string): string[] {
  if (!fs.existsSync(dir)) return [];
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  const results: string[] = [];
  for (const entry of entries) {
    if (entry.name === '.git') continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      results.push(...walkRepoFiles(full, baseDir));
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
      const relPaths = walkRepoFiles(REPO_ROOT, REPO_ROOT);
      const files: RepoFileEntry[] = relPaths.map((rel) => {
        const full = path.join(REPO_ROOT, rel);
        const ext = path.extname(rel).toLowerCase();
        const isBinary = ['.png', '.ico', '.jpg', '.jpeg', '.webp', '.jar', '.zip'].includes(ext);
        const stat = fs.statSync(full);
        const content = isBinary
          ? `[Binary asset: ${rel} (${stat.size} bytes)]`
          : fs.readFileSync(full, 'utf8');
        return {
          path: `audio_pro/${rel}`,
          category: classifyPath(rel),
          sizeBytes: stat.size,
          lines: isBinary ? 1 : content.split('\n').length,
          content,
        };
      });

      if (fs.existsSync(WORKFLOW_FILE)) {
        const wfContent = fs.readFileSync(WORKFLOW_FILE, 'utf8');
        files.unshift({
          path: '.github/workflows/build.yml',
          category: 'CI/CD',
          sizeBytes: Buffer.byteLength(wfContent, 'utf8'),
          lines: wfContent.split('\n').length,
          content: wfContent,
        });
      }

      res.json({ repoName: 'audio_pro', fileCount: files.length, files });
    } catch (err) {
      res.status(500).json({ error: (err as Error).message });
    }
  });

  app.get('/api/repo/git', (_req, res) => {
    try {
      const relPaths = walkRepoFiles(REPO_ROOT, REPO_ROOT);
      const hasWorkflow = fs.existsSync(WORKFLOW_FILE);
      res.json({
        initialized: true,
        syncMode: 'AI Studio GitHub Sync (Clean Workspace Tree)',
        branch: 'main',
        workflowPath: hasWorkflow ? '.github/workflows/build.yml' : 'Missing',
        nestedGitPresent: fs.existsSync(path.join(REPO_ROOT, '.git')),
        trackedFiles: relPaths.length + (hasWorkflow ? 1 : 0),
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
      const relPaths = walkRepoFiles(REPO_ROOT, REPO_ROOT);
      const entries: ZipEntryInput[] = relPaths.map((rel) => ({
        path: `audio_pro/${rel}`,
        content: new Uint8Array(fs.readFileSync(path.join(REPO_ROOT, rel))),
      }));

      if (fs.existsSync(WORKFLOW_FILE)) {
        entries.push({
          path: '.github/workflows/build.yml',
          content: new Uint8Array(fs.readFileSync(WORKFLOW_FILE)),
        });
      }

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
