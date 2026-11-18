import { ArrowLeftRight, Laptop, Volume2 } from 'lucide-react';
import type { BridgeMetrics, ConnectionStatus } from '../audio/protocol';
import { VuWaveform } from './VuWaveform';

interface WindowsHostPanelProps {
  desktopName: string;
  phoneName: string;
  mobilePlatform: 'Android' | 'iOS';
  status: ConnectionStatus;
  metrics: BridgeMetrics;
  virtualMicName: string;
  onChangeVirtualMic: (name: string) => void;
  virtualSpkName: string;
  onChangeVirtualSpk: (name: string) => void;
  inputLevels: { rms: number; peak: number; dbfs: number };
  outputRms: number;
  isMuted: boolean;
  onTriggerHostBeep: () => void;
}

const VIRTUAL_MIC_OPTIONS = [
  'AudioPro Virtual Mic (WDM)',
  'CABLE Input (VB-Audio Virtual Cable)',
  'Line 1 (Virtual Audio Cable)',
];

const VIRTUAL_SPK_OPTIONS = [
  'AudioPro Virtual Speaker (WASAPI)',
  'CABLE Output (VB-Audio Virtual Cable)',
  'Speakers (System Loopback)',
];

export function WindowsHostPanel({
  desktopName,
  phoneName,
  mobilePlatform,
  status,
  metrics,
  virtualMicName,
  onChangeVirtualMic,
  virtualSpkName,
  onChangeVirtualSpk,
  inputLevels,
  outputRms,
  isMuted,
  onTriggerHostBeep,
}: WindowsHostPanelProps) {
  const transportLabel =
    mobilePlatform === 'Android' ? 'USB · ADB TCP:38900' : 'USB · iOS usbmuxd:38900';

  const statusColor =
    status === 'connected'
      ? 'text-emerald-400'
      : status === 'connecting'
        ? 'text-amber-400'
        : 'text-rose-400';

  const statusLabel =
    status === 'connected'
      ? 'Bridge Active'
      : status === 'connecting'
        ? 'Handshaking'
        : 'Awaiting USB';

  return (
    <section
      aria-label="Windows Receiver Host"
      className="flex flex-col rounded-xl border border-white/[0.08] bg-[#111622] p-5"
    >
      {/* Header row */}
      <div className="flex flex-wrap items-center justify-between gap-3 pb-4">
        <div className="flex items-center gap-2.5">
          <Laptop className="h-4 w-4 text-cyan-400" aria-hidden="true" />
          <h2 className="font-display text-base font-semibold text-slate-100">
            Windows Virtual Sound Card Host
          </h2>
        </div>

        <span className="font-mono text-xs text-slate-400">{desktopName}</span>
      </div>

      {/* Connected Phone Status Panel */}
      <div className="border-t border-white/[0.06] py-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <div>
            <p className="text-xs text-slate-400">Connected Phone</p>
            <p className="mt-0.5 font-display text-lg font-semibold text-slate-100">
              {status === 'disconnected' ? 'No Phone Attached' : phoneName}
            </p>
          </div>

          <div className="text-right">
            <p className={`text-xs font-semibold ${statusColor}`}>{statusLabel}</p>
            <p className="mt-0.5 font-mono text-xs text-slate-400">{transportLabel}</p>
          </div>
        </div>

        {/* Low-latency telemetry strip */}
        <div className="mt-3 grid grid-cols-3 gap-3">
          <div>
            <p className="text-[11px] text-slate-400">Total Latency</p>
            <p className="font-mono text-sm font-semibold tabular-nums text-cyan-300">
              {status === 'connected' ? `${metrics.latencyMs.toFixed(1)} ms` : '—'}
            </p>
          </div>
          <div>
            <p className="text-[11px] text-slate-400">Jitter Buffer</p>
            <p className="font-mono text-sm font-semibold tabular-nums text-slate-100">
              {status === 'connected' ? `${metrics.jitterMs.toFixed(1)} ms` : '—'}
            </p>
          </div>
          <div>
            <p className="text-[11px] text-slate-400">PCM Stream</p>
            <p className="font-mono text-sm font-semibold tabular-nums text-slate-100">
              {status === 'connected' ? `${metrics.packetsPerSecond} pkt/s` : '0 pkt/s'}
            </p>
          </div>
        </div>
      </div>

      {/* Virtual Microphone Routing (Phone -> Windows) */}
      <div className="space-y-2.5 border-t border-white/[0.06] py-4">
        <div className="flex items-center justify-between gap-2">
          <p className="text-xs font-medium text-slate-300">
            Virtual Microphone Endpoint (Phone Mic → Windows)
          </p>
          <ArrowLeftRight className="h-3.5 w-3.5 text-cyan-400" aria-hidden="true" />
        </div>

        <div>
          <label htmlFor="win-virtual-mic" className="sr-only">
            Windows virtual microphone endpoint
          </label>
          <select
            id="win-virtual-mic"
            value={virtualMicName}
            onChange={(e) => onChangeVirtualMic(e.target.value)}
            className="w-full rounded-lg border border-white/[0.1] bg-[#090C12] px-3 py-2 text-xs text-slate-100 focus:border-cyan-400 focus:outline-none"
          >
            {VIRTUAL_MIC_OPTIONS.map((opt) => (
              <option key={opt} value={opt}>
                {opt}
              </option>
            ))}
          </select>
        </div>

        <VuWaveform
          rms={inputLevels.rms}
          peak={inputLevels.peak}
          dbfs={inputLevels.dbfs}
          isMuted={isMuted}
          isConnected={status === 'connected'}
          label="WASAPI Virtual Mic Output"
          height={52}
        />
      </div>

      {/* Virtual Speaker Routing (Windows -> Phone) */}
      <div className="space-y-2.5 border-t border-white/[0.06] py-4">
        <div className="flex items-center justify-between gap-2">
          <p className="text-xs font-medium text-slate-300">
            Virtual Speaker Endpoint (Windows Audio → Phone)
          </p>
          <button
            type="button"
            onClick={onTriggerHostBeep}
            className="inline-flex items-center gap-1.5 rounded-md border border-white/[0.08] bg-[#161D2C] px-2.5 py-1 text-xs font-medium text-cyan-300 hover:border-cyan-400/50 whitespace-nowrap shrink-0"
          >
            <Volume2 className="h-3.5 w-3.5" aria-hidden="true" />
            Send System Audio Pulse
          </button>
        </div>

        <div>
          <label htmlFor="win-virtual-spk" className="sr-only">
            Windows virtual speaker endpoint
          </label>
          <select
            id="win-virtual-spk"
            value={virtualSpkName}
            onChange={(e) => onChangeVirtualSpk(e.target.value)}
            className="w-full rounded-lg border border-white/[0.1] bg-[#090C12] px-3 py-2 text-xs text-slate-100 focus:border-cyan-400 focus:outline-none"
          >
            {VIRTUAL_SPK_OPTIONS.map((opt) => (
              <option key={opt} value={opt}>
                {opt}
              </option>
            ))}
          </select>
        </div>

        <VuWaveform
          rms={outputRms}
          peak={Math.min(1, outputRms * 1.15)}
          dbfs={outputRms <= 0.001 || status !== 'connected' ? -96 : 20 * Math.log10(outputRms)}
          isMuted={false}
          isConnected={status === 'connected'}
          label="WASAPI Loopback Capture"
          height={52}
        />
      </div>

      {/* Driver Format Summary */}
      <div className="mt-auto flex flex-wrap items-center justify-between gap-2 border-t border-white/[0.06] pt-4 text-xs text-slate-400">
        <span>MMCSS Pro Audio Thread · Lock-Free SPSC Ring</span>
        <span className="font-mono tabular-nums text-slate-200">
          48,000 Hz · 16-bit PCM · 5 ms
        </span>
      </div>
    </section>
  );
}
