import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  type AudioEndpoint,
  type ConnectionStatus,
  calculateAudioLevels,
  calculateBridgeMetrics,
} from './audio/protocol';
import { CodebaseExplorer } from './components/CodebaseExplorer';
import { GitHubCiPanel } from './components/GitHubCiPanel';
import { MobileClientPanel } from './components/MobileClientPanel';
import { type StudioTab, TopBar } from './components/TopBar';
import { WindowsHostPanel } from './components/WindowsHostPanel';

const ANDROID_INPUTS: AudioEndpoint[] = [
  { id: 'in-builtin', name: 'Built-in Studio Mic (Bottom Array)', type: 'builtInMic', isInput: true, isDefault: true },
  { id: 'in-airpods', name: 'AirPods Pro 2 (Bluetooth HFP/SCO)', type: 'bluetoothSco', isInput: true },
  { id: 'in-usbc', name: 'USB-C Condenser Mic', type: 'usbAudio', isInput: true },
  { id: 'in-wired', name: 'Wired TRRS Headset Mic', type: 'wiredHeadset', isInput: true },
];

const IOS_INPUTS: AudioEndpoint[] = [
  { id: 'in-iphone', name: 'iPhone Bottom Beamforming Mic', type: 'builtInMic', isInput: true, isDefault: true },
  { id: 'in-airpods', name: 'AirPods Pro 2 (Bluetooth HFP)', type: 'bluetoothSco', isInput: true },
  { id: 'in-lightning', name: 'USB-C / Lightning Interface', type: 'usbAudio', isInput: true },
];

const MOBILE_OUTPUTS: AudioEndpoint[] = [
  { id: 'out-airpods', name: 'AirPods Pro 2 (Bluetooth A2DP)', type: 'bluetoothA2dp', isInput: false },
  { id: 'out-speaker', name: 'Loudspeaker', type: 'speakerphone', isInput: false, isDefault: true },
  { id: 'out-earpiece', name: 'Phone Earpiece', type: 'earpiece', isInput: false },
  { id: 'out-dac', name: 'Wired 3.5mm / USB-C DAC', type: 'wiredHeadset', isInput: false },
];

export default function App() {
  const [activeTab, setActiveTab] = useState<StudioTab>('bridge');

  const [mobilePlatform, setMobilePlatform] = useState<'Android' | 'iOS'>('Android');
  const [usbPlugged, setUsbPlugged] = useState(true);
  const [autoConnect, setAutoConnect] = useState(true);
  const [status, setStatus] = useState<ConnectionStatus>('connected');

  const inputDevices = mobilePlatform === 'Android' ? ANDROID_INPUTS : IOS_INPUTS;
  const [selectedInputId, setSelectedInputId] = useState<string>(ANDROID_INPUTS[0].id);
  const [selectedOutputId, setSelectedOutputId] = useState<string>(MOBILE_OUTPUTS[0].id);
  const [outputVolume, setOutputVolume] = useState(0.85);
  const [isMuted, setIsMuted] = useState(false);

  const [audioSourceMode, setAudioSourceMode] = useState<'tone' | 'mic'>('tone');
  const [micError, setMicError] = useState<string | null>(null);

  const [backgroundLock, setBackgroundLock] = useState(true);
  const [screenLocked, setScreenLocked] = useState(false);

  const [virtualMicName, setVirtualMicName] = useState('AudioPro Virtual Mic (WDM)');
  const [virtualSpkName, setVirtualSpkName] = useState('AudioPro Virtual Speaker (WASAPI)');

  const [inputLevels, setInputLevels] = useState({ rms: 0.24, peak: 0.42, dbfs: -12.4 });
  const [outputRms, setOutputRms] = useState(0.18);

  const audioCtxRef = useRef<AudioContext | null>(null);
  const analyserRef = useRef<AnalyserNode | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const hostPulseRef = useRef(0);

  // Sync default mic when switching Android <-> iOS
  const handleChangePlatform = (platform: 'Android' | 'iOS') => {
    setMobilePlatform(platform);
    const nextList = platform === 'Android' ? ANDROID_INPUTS : IOS_INPUTS;
    setSelectedInputId(nextList[0].id);
  };

  // USB plug/unplug + auto-handshake simulation
  useEffect(() => {
    if (!usbPlugged) {
      setStatus('disconnected');
      return;
    }
    if (!autoConnect) {
      setStatus('disconnected');
      return;
    }
    setStatus('connecting');
    const timer = window.setTimeout(() => {
      setStatus('connected');
    }, 550);
    return () => window.clearTimeout(timer);
  }, [usbPlugged, autoConnect, mobilePlatform]);

  // Real Web Audio Microphone capture when 'mic' mode is selected
  const stopLiveMic = useCallback(() => {
    if (streamRef.current) {
      streamRef.current.getTracks().forEach((t) => t.stop());
      streamRef.current = null;
    }
    if (audioCtxRef.current) {
      audioCtxRef.current.close().catch(() => undefined);
      audioCtxRef.current = null;
    }
    analyserRef.current = null;
  }, []);

  const handleToggleAudioSource = async (mode: 'tone' | 'mic') => {
    setMicError(null);
    if (mode === 'tone') {
      stopLiveMic();
      setAudioSourceMode('tone');
      return;
    }

    try {
      if (!navigator.mediaDevices?.getUserMedia) {
        throw new Error('Microphone API unavailable in this browser context');
      }
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const ctx = new AudioContext();
      const source = ctx.createMediaStreamSource(stream);
      const analyser = ctx.createAnalyser();
      analyser.fftSize = 512;
      source.connect(analyser);

      streamRef.current = stream;
      audioCtxRef.current = ctx;
      analyserRef.current = analyser;
      setAudioSourceMode('mic');
    } catch (err) {
      stopLiveMic();
      setAudioSourceMode('tone');
      setMicError((err as Error).message || 'Microphone access denied');
    }
  };

  useEffect(() => stopLiveMic, [stopLiveMic]);

  // Real-time VU sampling loop (Web Audio AnalyserNode or realistic speech cadence)
  useEffect(() => {
    let rafId = 0;
    let tick = 0;
    const sampleBuffer = new Float32Array(512);

    const updateMeter = () => {
      tick += 0.06;
      const streamActive = status === 'connected' && (!screenLocked || backgroundLock);

      if (!streamActive || isMuted) {
        setInputLevels({ rms: 0, peak: 0, dbfs: -96 });
      } else if (audioSourceMode === 'mic' && analyserRef.current) {
        analyserRef.current.getFloatTimeDomainData(sampleBuffer);
        setInputLevels(calculateAudioLevels(sampleBuffer));
      } else {
        // Synthetic speech-like envelope for deterministic visual response
        const cadence =
          0.22 +
          0.18 * Math.abs(Math.sin(tick * 1.9)) +
          0.11 * Math.abs(Math.sin(tick * 4.7));
        const peak = Math.min(0.95, cadence * 1.45);
        const dbfs = 20 * Math.log10(Math.max(1e-4, cadence));
        setInputLevels({ rms: cadence, peak, dbfs });
      }

      if (streamActive) {
        hostPulseRef.current = Math.max(0, hostPulseRef.current - 0.015);
        const baseOut = 0.14 + 0.09 * Math.abs(Math.sin(tick * 1.3)) + hostPulseRef.current;
        setOutputRms(Math.min(1, baseOut));
      } else {
        setOutputRms(0);
      }

      rafId = requestAnimationFrame(updateMeter);
    };

    rafId = requestAnimationFrame(updateMeter);
    return () => cancelAnimationFrame(rafId);
  }, [status, isMuted, audioSourceMode, screenLocked, backgroundLock]);

  const handleTriggerHostBeep = () => {
    hostPulseRef.current = 0.65;
    try {
      const ctx = new AudioContext();
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.type = 'sine';
      osc.frequency.value = 528;
      gain.gain.setValueAtTime(0.08 * outputVolume, ctx.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.22);
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start();
      osc.stop(ctx.currentTime + 0.24);
      osc.onended = () => {
        ctx.close().catch(() => undefined);
      };
    } catch {
      // AudioContext blocked before gesture in headless env
    }
  };

  const selectedInput = inputDevices.find((d) => d.id === selectedInputId);
  const metrics = useMemo(
    () =>
      calculateBridgeMetrics({
        status,
        jitterBufferFrames: 1.3,
        bluetoothScoActive: selectedInput?.type === 'bluetoothSco',
      }),
    [status, selectedInput]
  );

  const phoneName =
    mobilePlatform === 'Android' ? 'Pixel 9 Pro (Android 15)' : 'iPhone 16 Pro (iOS 18)';

  return (
    <div className="min-h-screen bg-[#090C12] text-slate-100">
      <TopBar activeTab={activeTab} onSelectTab={setActiveTab} />

      <main className="mx-auto max-w-[1380px] px-6 py-5">
        {activeTab === 'bridge' && (
          <div className="space-y-4">
            <div className="flex flex-wrap items-end justify-between gap-4">
              <div>
                <h1 className="font-display text-2xl font-bold tracking-tight text-slate-100 text-balance">
                  USB Virtual Sound Card Studio
                </h1>
                <p className="mt-1 text-sm text-slate-400">
                  Full-duplex 48 kHz PCM bridge pairing mobile microphones and speakers with Windows WASAPI endpoints.
                </p>
              </div>
              <div className="font-mono text-xs tabular-nums text-slate-400">
                APRO v1 · TCP_NODELAY · Port 38900
              </div>
            </div>

            <div className="grid grid-cols-1 gap-6 lg:grid-cols-2 items-stretch">
              <MobileClientPanel
                mobilePlatform={mobilePlatform}
                onChangePlatform={handleChangePlatform}
                desktopName="WORKSTATION-WIN11"
                status={status}
                usbPlugged={usbPlugged}
                autoConnect={autoConnect}
                onToggleUsb={() => setUsbPlugged((v) => !v)}
                onToggleAutoConnect={setAutoConnect}
                inputDevices={inputDevices}
                selectedInputId={selectedInputId}
                onSelectInput={setSelectedInputId}
                outputDevices={MOBILE_OUTPUTS}
                selectedOutputId={selectedOutputId}
                onSelectOutput={setSelectedOutputId}
                outputVolume={outputVolume}
                onChangeOutputVolume={setOutputVolume}
                isMuted={isMuted}
                onToggleMute={() => setIsMuted((m) => !m)}
                inputLevels={inputLevels}
                outputRms={outputRms}
                audioSourceMode={audioSourceMode}
                micError={micError}
                onToggleAudioSource={handleToggleAudioSource}
                backgroundLock={backgroundLock}
                onToggleBackgroundLock={setBackgroundLock}
                screenLocked={screenLocked}
                onToggleScreenLock={setScreenLocked}
              />

              <WindowsHostPanel
                desktopName="WORKSTATION-WIN11"
                phoneName={phoneName}
                mobilePlatform={mobilePlatform}
                status={status}
                metrics={metrics}
                virtualMicName={virtualMicName}
                onChangeVirtualMic={setVirtualMicName}
                virtualSpkName={virtualSpkName}
                onChangeVirtualSpk={setVirtualSpkName}
                inputLevels={inputLevels}
                outputRms={outputRms}
                isMuted={isMuted}
                onTriggerHostBeep={handleTriggerHostBeep}
              />
            </div>
          </div>
        )}

        {activeTab === 'codebase' && <CodebaseExplorer />}
        {activeTab === 'github' && <GitHubCiPanel />}
      </main>
    </div>
  );
}
