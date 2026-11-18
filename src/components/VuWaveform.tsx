import { useEffect, useRef } from 'react';

interface VuWaveformProps {
  rms: number;
  peak: number;
  dbfs: number;
  isMuted: boolean;
  isConnected: boolean;
  label: string;
  height?: number;
}

export function VuWaveform({
  rms,
  peak,
  dbfs,
  isMuted,
  isConnected,
  label,
  height = 72,
}: VuWaveformProps) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const stateRef = useRef({ rms, peak, isMuted, isConnected });

  useEffect(() => {
    stateRef.current = { rms, peak, isMuted, isConnected };
  }, [rms, peak, isMuted, isConnected]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    let rafId = 0;
    let phase = 0;

    const render = () => {
      const { rms: curRms, peak: curPeak, isMuted: muted, isConnected: connected } =
        stateRef.current;

      const dpr = window.devicePixelRatio || 1;
      const width = canvas.clientWidth || 320;
      const h = canvas.clientHeight || height;
      if (canvas.width !== Math.floor(width * dpr) || canvas.height !== Math.floor(h * dpr)) {
        canvas.width = Math.floor(width * dpr);
        canvas.height = Math.floor(h * dpr);
      }

      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, width, h);

      const barCount = 32;
      const gap = 4;
      const barWidth = Math.max(2, (width - gap * (barCount - 1)) / barCount);
      const midY = h / 2;

      for (let i = 0; i < barCount; i++) {
        const norm = i / (barCount - 1);
        const envelope = Math.sin(norm * Math.PI);
        const ripple = 0.65 + 0.35 * Math.sin(phase + i * 0.52);

        const active = connected && !muted;
        const amp = active
          ? Math.min(1, Math.max(0.06, curRms * 1.65 * envelope * ripple + curPeak * 0.25 * envelope))
          : 0.06;

        const barH = amp * (h - 10);
        const x = i * (barWidth + gap);
        const y = midY - barH / 2;

        if (!active) {
          ctx.fillStyle = 'rgba(100, 116, 139, 0.35)';
        } else if (amp > 0.85) {
          ctx.fillStyle = '#EF4444';
        } else if (amp > 0.62) {
          ctx.fillStyle = '#F59E0B';
        } else {
          ctx.fillStyle = '#22D3EE';
        }

        ctx.beginPath();
        ctx.roundRect(x, y, barWidth, barH, 2.5);
        ctx.fill();
      }

      phase += 0.14;
      rafId = requestAnimationFrame(render);
    };

    rafId = requestAnimationFrame(render);
    return () => cancelAnimationFrame(rafId);
  }, [height]);

  return (
    <div className="rounded-lg bg-[#090C12] px-3 py-2">
      <div className="mb-1 flex items-center justify-between text-xs">
        <span className="text-slate-400">{label}</span>
        <span className="font-mono tabular-nums text-slate-300">
          {isMuted || !isConnected ? '-96.0 dBFS' : `${dbfs.toFixed(1)} dBFS`}
        </span>
      </div>
      <canvas
        ref={canvasRef}
        aria-label={`${label} real-time audio level meter`}
        style={{ height: `${height}px` }}
        className="block w-full"
      />
    </div>
  );
}
