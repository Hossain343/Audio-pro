import {
  Lock,
  Mic,
  MicOff,
  Radio,
  Smartphone,
  Usb,
  Volume2,
  Waves,
} from 'lucide-react';
import type { AudioEndpoint, ConnectionStatus } from '../audio/protocol';
import { VuWaveform } from './VuWaveform';

interface MobileClientPanelProps {
  mobilePlatform: 'Android' | 'iOS';
  onChangePlatform: (platform: 'Android' | 'iOS') => void;
  desktopName: string;
  status: ConnectionStatus;
  usbPlugged: boolean;
  autoConnect: boolean;
  onToggleUsb: () => void;
  onToggleAutoConnect: (enabled: boolean) => void;
  inputDevices: AudioEndpoint[];
  selectedInputId: string;
  onSelectInput: (id: string) => void;
  outputDevices: AudioEndpoint[];
  selectedOutputId: string;
  onSelectOutput: (id: string) => void;
  outputVolume: number;
  onChangeOutputVolume: (value: number) => void;
  isMuted: boolean;
  onToggleMute: () => void;
  inputLevels: { rms: number; peak: number; dbfs: number };
  outputRms: number;
  audioSourceMode: 'tone' | 'mic';
  micError: string | null;
  onToggleAudioSource: (mode: 'tone' | 'mic') => void;
  backgroundLock: boolean;
  onToggleBackgroundLock: (enabled: boolean) => void;
  screenLocked: boolean;
  onToggleScreenLock: (locked: boolean) => void;
}

export function MobileClientPanel({
  mobilePlatform,
  onChangePlatform,
  desktopName,
  status,
  usbPlugged,
  autoConnect,
  onToggleUsb,
  onToggleAutoConnect,
  inputDevices,
  selectedInputId,
  onSelectInput,
  outputDevices,
  selectedOutputId,
  onSelectOutput,
  outputVolume,
  onChangeOutputVolume,
  isMuted,
  onToggleMute,
  inputLevels,
  outputRms,
  audioSourceMode,
  micError,
  onToggleAudioSource,
  backgroundLock,
  onToggleBackgroundLock,
  screenLocked,
  onToggleScreenLock,
}: MobileClientPanelProps) {
  const activeInput = inputDevices.find((d) => d.id === selectedInputId) ?? inputDevices[0];
  const activeOutput = outputDevices.find((d) => d.id === selectedOutputId) ?? outputDevices[0];

  const statusMeta = {
    connected: {
      label: 'Connected via USB',
      color: 'text-emerald-400',
      dot: 'bg-emerald-400',
    },
    connecting: {
      label: 'Connecting (USB Handshake)...',
      color: 'text-amber-400',
      dot: 'bg-amber-400',
    },
    disconnected: {
      label: 'Disconnected',
      color: 'text-rose-400',
      dot: 'bg-rose-400',
    },
  }[status];

  return (
    <section
      aria-label="Mobile Transmitter Client"
      className="relative flex flex-col rounded-xl border border-white/[0.08] bg-[#111622] p-5"
    >
      {/* Header row */}
      <div className="flex flex-wrap items-center justify-between gap-3 pb-4">
        <div className="flex items-center gap-2.5">
          <Smartphone className="h-4 w-4 text-cyan-400" aria-hidden="true" />
          <h2 className="font-display text-base font-semibold text-slate-100">
            Mobile Transmitter
          </h2>
        </div>

        <div className="flex items-center gap-1 rounded-lg bg-[#090C12] p-1">
          {(['Android', 'iOS'] as const).map((plat) => (
            <button
              key={plat}
              type="button"
              onClick={() => onChangePlatform(plat)}
              className={`rounded-md px-3 py-1 text-xs font-medium transition-colors whitespace-nowrap shrink-0 ${
                mobilePlatform === plat
                  ? 'bg-[#1B2336] text-cyan-300'
                  : 'text-slate-400 hover:text-slate-200'
              }`}
            >
              {plat}
            </button>
          ))}
        </div>
      </div>

      {/* Desktop Target & USB Connection Status */}
      <div className="border-t border-white/[0.06] py-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <div>
            <p className="text-xs text-slate-400">Desktop Host</p>
            <p className="mt-0.5 font-display text-lg font-semibold text-slate-100">
              {desktopName}
            </p>
          </div>
          <div className="flex items-center gap-2 text-xs font-medium">
            <span
              aria-hidden="true"
              className={`h-2 w-2 rounded-full ${statusMeta.dot}`}
            />
            <span className={statusMeta.color}>{statusMeta.label}</span>
          </div>
        </div>

        <div className="mt-3 flex flex-wrap items-center justify-between gap-3">
          <button
            type="button"
            onClick={onToggleUsb}
            className={`inline-flex items-center gap-2 rounded-lg px-3.5 py-1.5 text-xs font-semibold transition-colors whitespace-nowrap shrink-0 ${
              usbPlugged
                ? 'border border-rose-500/30 bg-rose-500/10 text-rose-300 hover:bg-rose-500/20'
                : 'bg-cyan-400 text-slate-950 hover:bg-cyan-300'
            }`}
          >
            <Usb className="h-3.5 w-3.5" aria-hidden="true" />
            {usbPlugged ? 'Unplug USB Cable' : 'Plug USB Cable'}
          </button>

          <label className="flex cursor-pointer items-center gap-2 text-xs text-slate-300">
            <input
              type="checkbox"
              checked={autoConnect}
              onChange={(e) => onToggleAutoConnect(e.target.checked)}
              className="h-3.5 w-3.5 rounded border-slate-600 bg-slate-900 text-cyan-400 focus:ring-cyan-400"
            />
            Auto-connect on USB attach
          </label>
        </div>
      </div>

      {/* Active Microphone & Real-time VU Meter */}
      <div className="space-y-2.5 border-t border-white/[0.06] py-4">
        <div className="flex items-center justify-between gap-2">
          <div className="min-w-0">
            <p className="text-xs text-slate-400">Active Input Microphone</p>
            <p className="truncate text-sm font-semibold text-slate-100">
              {activeInput?.name ?? 'Default Mic'}
            </p>
          </div>

          <div className="flex items-center gap-2 shrink-0">
            <button
              type="button"
              onClick={() => onToggleAudioSource(audioSourceMode === 'tone' ? 'mic' : 'tone')}
              className="inline-flex items-center gap-1.5 rounded-md border border-white/[0.08] bg-[#161D2C] px-2.5 py-1.5 text-xs font-medium text-slate-200 hover:border-cyan-400/50"
            >
              {audioSourceMode === 'mic' ? (
                <>
                  <Radio className="h-3.5 w-3.5 text-cyan-400" aria-hidden="true" />
                  Live Mic
                </>
              ) : (
                <>
                  <Waves className="h-3.5 w-3.5 text-cyan-400" aria-hidden="true" />
                  Test Signal
                </>
              )}
            </button>

            <button
              type="button"
              onClick={onToggleMute}
              aria-label={isMuted ? 'Unmute microphone' : 'Mute microphone'}
              className={`inline-flex items-center justify-center rounded-md border px-2.5 py-1.5 text-xs font-medium transition-colors ${
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
        </div>

        <div>
          <label htmlFor="mobile-input-select" className="sr-only">
            Select input microphone
          </label>
          <select
            id="mobile-input-select"
            value={selectedInputId}
            onChange={(e) => onSelectInput(e.target.value)}
            className="w-full rounded-lg border border-white/[0.1] bg-[#090C12] px-3 py-2 text-xs text-slate-100 focus:border-cyan-400 focus:outline-none"
          >
            {inputDevices.map((dev) => (
              <option key={dev.id} value={dev.id}>
                {dev.name}
              </option>
            ))}
          </select>
        </div>

        {micError && (
          <p className="text-xs text-amber-300" role="status">
            {micError} (Fallback synthetic test signal active)
          </p>
        )}

        <VuWaveform
          rms={inputLevels.rms}
          peak={inputLevels.peak}
          dbfs={inputLevels.dbfs}
          isMuted={isMuted}
          isConnected={status === 'connected'}
          label="Mic Input Levelizer"
          height={52}
        />
      </div>

      {/* Output Device & Volume Control */}
      <div className="space-y-2.5 border-t border-white/[0.06] py-4">
        <div className="flex items-center justify-between gap-2">
          <div className="min-w-0">
            <p className="text-xs text-slate-400">Active Audio Output</p>
            <p className="truncate text-sm font-semibold text-slate-100">
              {activeOutput?.name ?? 'Speaker'}
            </p>
          </div>
          <span className="font-mono text-xs font-semibold tabular-nums text-cyan-300">
            {Math.round(outputVolume * 100)}%
          </span>
        </div>

        <div>
          <label htmlFor="mobile-output-select" className="sr-only">
            Select audio output device
          </label>
          <select
            id="mobile-output-select"
            value={selectedOutputId}
            onChange={(e) => onSelectOutput(e.target.value)}
            className="w-full rounded-lg border border-white/[0.1] bg-[#090C12] px-3 py-2 text-xs text-slate-100 focus:border-cyan-400 focus:outline-none"
          >
            {outputDevices.map((dev) => (
              <option key={dev.id} value={dev.id}>
                {dev.name}
              </option>
            ))}
          </select>
        </div>

        <div className="flex items-center gap-3">
          <Volume2 className="h-4 w-4 shrink-0 text-slate-400" aria-hidden="true" />
          <label htmlFor="mobile-output-volume" className="sr-only">
            Output volume
          </label>
          <input
            id="mobile-output-volume"
            type="range"
            min={0}
            max={100}
            value={Math.round(outputVolume * 100)}
            onChange={(e) => onChangeOutputVolume(Number(e.target.value) / 100)}
            className="h-1.5 w-full cursor-pointer accent-cyan-400"
          />
        </div>

        <div className="h-1.5 w-full overflow-hidden rounded-full bg-white/[0.06]">
          <div
            className="h-full bg-emerald-400 transition-[width] duration-75"
            style={{
              width: `${status === 'connected' ? Math.round(outputRms * outputVolume * 100) : 0}%`,
            }}
          />
        </div>
      </div>

      {/* Background Resilience Controls */}
      <div className="mt-auto flex flex-wrap items-center justify-between gap-3 border-t border-white/[0.06] pt-4 text-xs">
        <label className="flex cursor-pointer items-center gap-2 text-slate-200">
          <input
            type="checkbox"
            checked={backgroundLock}
            onChange={(e) => onToggleBackgroundLock(e.target.checked)}
            className="h-3.5 w-3.5 rounded border-slate-600 bg-slate-900 text-cyan-400 focus:ring-cyan-400"
          />
          Foreground Service + WakeLock
        </label>

        <button
          type="button"
          onClick={() => onToggleScreenLock(!screenLocked)}
          className="inline-flex items-center gap-1.5 rounded-md border border-white/[0.08] bg-[#161D2C] px-2.5 py-1.5 text-xs font-medium text-slate-200 hover:border-cyan-400/50 whitespace-nowrap shrink-0"
        >
          <Lock className="h-3.5 w-3.5 text-cyan-400" aria-hidden="true" />
          {screenLocked ? 'Unlock Screen' : 'Simulate Screen Off'}
        </button>
      </div>

      {screenLocked && (
        <div
          role="dialog"
          aria-label="Simulated device lock screen"
          className="absolute inset-0 z-10 flex flex-col items-center justify-center rounded-xl bg-[#06080D]/95 p-6 text-center backdrop-blur-sm"
        >
          <Lock className="mb-3 h-7 w-7 text-cyan-400" aria-hidden="true" />
          <p className="font-display text-base font-semibold text-slate-100">
            Screen Locked · {mobilePlatform}
          </p>
          <p className="mt-1 max-w-xs text-xs text-slate-300">
            {backgroundLock
              ? `Persistent ${mobilePlatform === 'Android' ? 'ForegroundService + PARTIAL_WAKE_LOCK' : 'AVAudioSession Background Mode'} active. USB stream uninterrupted.`
              : 'WakeLock disabled — audio stream paused when screen locked.'}
          </p>
          <p className="mt-3 font-mono text-xs tabular-nums text-emerald-400">
            {status === 'connected' && backgroundLock
              ? `TX Stream Active · ${(inputLevels.rms * 100).toFixed(0)}% RMS`
              : 'Stream Suspended'}
          </p>
          <button
            type="button"
            onClick={() => onToggleScreenLock(false)}
            className="mt-5 rounded-lg bg-cyan-400 px-4 py-2 text-xs font-semibold text-slate-950 hover:bg-cyan-300"
          >
            Wake Screen
          </button>
        </div>
      )}
    </section>
  );
}
