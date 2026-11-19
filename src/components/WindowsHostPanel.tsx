import { useState } from 'react';
import { ArrowLeftRight, Check, Laptop, Mic, MicOff, Volume2 } from 'lucide-react';
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
  loopbackEnabled: boolean;
  onToggleLoopback: (enabled: boolean) => void;
  inputLevels: { rms: number; peak: number; dbfs: number };
  outputRms: number;
  isMuted: boolean;
  onToggleMute: () => void;
  onTriggerHostBeep: () => void;
}

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
  loopbackEnabled,
  onToggleLoopback,
  inputLevels,
  outputRms,
  isMuted,
  onToggleMute,
  onTriggerHostBeep,
}: WindowsHostPanelProps) {
  const [micDraft, setMicDraft] = useState(virtualMicName);
  const [spkDraft, setSpkDraft] = useState(virtualSpkName);
  const [applied, setApplied] = useState(false);

  const handleApplyNames = () => {
    onChangeVirtualMic(micDraft.trim() || 'AudioPro Virtual Mic');
    onChangeVirtualSpk(spkDraft.trim() || 'AudioPro Virtual Speaker');
    setApplied(true);
    window.setTimeout(() => setApplied(false), 1800);
  };

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

        <span className="font-mono text-xs text-slate-400">{desktopName} · TCP:38900</span>
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
            {applied && (
              <p className="mt-0.5 inline-flex items-center gap-1 text-[11px] font-medium text-emerald-400">
                <Check className="h-3 w-3" aria-hidden="true" />
                Virtual device names applied
              </p>
            )}
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

      {/* Virtual Microphone Naming (Phone -> Windows) */}
      <div className="space-y-2.5 border-t border-white/[0.06] py-4">
        <div className="flex items-center justify-between gap-2">
          <div className="flex items-center gap-2">
            <ArrowLeftRight className="h-3.5 w-3.5 text-cyan-400" aria-hidden="true" />
            <p className="text-xs font-medium text-slate-300">
              Virtual Microphone Name (Phone Mic → Windows)
            </p>
          </div>

          <button
            type="button"
            onClick={onToggleMute}
            aria-label={isMuted ? 'Unmute virtual microphone' : 'Mute virtual microphone'}
            className={`inline-flex items-center justify-center rounded-md border px-2 py-1 text-xs font-medium transition-colors ${
              isMuted
                ? 'border-rose-500/40 bg-rose-500/15 text-rose-300'
                : 'border-white/[0.08] bg-[#161D2C] text-slate-200 hover:border-cyan-400/50'
            }`}
          >
            {isMuted ? (
              <MicOff className="h-3.5 w-3.5" aria-hidden="true" />
            ) : (
              <Mic className="h-3.5 w-3.5 text-cyan-400" aria-hidden="true" />
            )}
          </button>
        </div>

        <div className="flex items-center gap-2">
          <label htmlFor="win-virtual-mic" className="sr-only">
            Virtual microphone device name
          </label>
          <input
            id="win-virtual-mic"
            type="text"
            value={micDraft}
            onChange={(e) => setMicDraft(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') handleApplyNames();
            }}
            placeholder="e.g. AudioPro Virtual Mic"
            className="w-full rounded-lg border border-white/[0.1] bg-[#090C12] px-3 py-2 text-xs text-slate-100 placeholder:text-slate-500 focus:border-cyan-400 focus:outline-none"
          />
          <button
            type="button"
            onClick={handleApplyNames}
            className="rounded-lg border border-white/[0.1] bg-[#161D2C] px-3 py-2 text-xs font-medium text-cyan-300 hover:border-cyan-400/50 whitespace-nowrap shrink-0"
          >
            Apply
          </button>
        </div>

        <p className="text-[11px] text-slate-400">
          Active Virtual Mic: <span className="font-mono text-slate-200">{virtualMicName}</span>
        </p>

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
            Virtual Speaker Name (Windows Audio → Phone)
          </p>
          <button
            type="button"
            onClick={onTriggerHostBeep}
            className="inline-flex items-center gap-1.5 rounded-md border border-white/[0.08] bg-[#161D2C] px-2.5 py-1 text-xs font-medium text-cyan-300 hover:border-cyan-400/50 whitespace-nowrap shrink-0"
          >
            <Volume2 className="h-3.5 w-3.5" aria-hidden="true" />
            Send Test Pulse
          </button>
        </div>

        <div className="flex items-center gap-2">
          <label htmlFor="win-virtual-spk" className="sr-only">
            Virtual speaker device name
          </label>
          <input
            id="win-virtual-spk"
            type="text"
            value={spkDraft}
            onChange={(e) => setSpkDraft(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') handleApplyNames();
            }}
            placeholder="e.g. AudioPro Virtual Speaker"
            className="w-full rounded-lg border border-white/[0.1] bg-[#090C12] px-3 py-2 text-xs text-slate-100 placeholder:text-slate-500 focus:border-cyan-400 focus:outline-none"
          />
          <button
            type="button"
            onClick={handleApplyNames}
            className="rounded-lg border border-white/[0.1] bg-[#161D2C] px-3 py-2 text-xs font-medium text-cyan-300 hover:border-cyan-400/50 whitespace-nowrap shrink-0"
          >
            Apply
          </button>
        </div>

        <label className="flex cursor-pointer items-center gap-2 text-xs text-slate-300">
          <input
            type="checkbox"
            checked={loopbackEnabled}
            onChange={(e) => onToggleLoopback(e.target.checked)}
            className="h-3.5 w-3.5 rounded border-slate-600 bg-slate-900 text-cyan-400 focus:ring-cyan-400"
          />
          Stream Windows System Audio (WASAPI Loopback)
        </label>

        <VuWaveform
          rms={loopbackEnabled ? outputRms : 0}
          peak={loopbackEnabled ? Math.min(1, outputRms * 1.15) : 0}
          dbfs={
            !loopbackEnabled || outputRms <= 0.001 || status !== 'connected'
              ? -96
              : 20 * Math.log10(outputRms)
          }
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
