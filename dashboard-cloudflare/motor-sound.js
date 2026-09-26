(() => {
  'use strict';

  const STORAGE_KEY = 'iotmotor_motor_sound_v1';
  const DEFAULTS = { enabled: false, volume: 70 };
  const motorVisual = document.getElementById('motorVisual');
  const enabledInput = document.getElementById('motorSoundEnabled');
  const enabledText = document.getElementById('motorSoundEnabledText');
  const volumeInput = document.getElementById('motorSoundVolume');
  const volumeValue = document.getElementById('motorSoundVolumeValue');
  const testBtn = document.getElementById('motorSoundTestBtn');
  const feedback = document.getElementById('motorSoundFeedback');

  if (!motorVisual || !enabledInput || !volumeInput || !testBtn) return;

  let settings = loadSettings();
  let ctx = null;
  let active = null;
  let testTimer = null;
  let coasting = null;
  let unlocked = false;

  function clampVolume(value) {
    const n = Number(value);
    return Number.isFinite(n) ? Math.min(100, Math.max(0, Math.round(n))) : DEFAULTS.volume;
  }

  function loadSettings() {
    try {
      const raw = JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}');
      return {
        enabled: raw.enabled === true,
        volume: clampVolume(raw.volume ?? DEFAULTS.volume),
      };
    } catch (_) {
      return { ...DEFAULTS };
    }
  }

  function saveSettings() {
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify(settings)); } catch (_) {}
  }

  function setFeedback(message) {
    if (feedback) feedback.textContent = message;
  }

  function gainForVolume(volume) {
    // Curva simples: 70% fica próximo do volume aprovado no teste anterior.
    const normalized = clampVolume(volume) / 100;
    return Math.max(0.0001, 0.57 * normalized * normalized);
  }

  // Ruído rosa (filtro de Paul Kellet): mais natural que o branco para o ar
  // empurrado pela ventoinha e para o "corpo" do motor.
  function makeNoiseBuffer(audioCtx, seconds = 3) {
    const length = Math.max(1, Math.floor(audioCtx.sampleRate * seconds));
    const buffer = audioCtx.createBuffer(1, length, audioCtx.sampleRate);
    const data = buffer.getChannelData(0);
    let b0 = 0, b1 = 0, b2 = 0, b3 = 0, b4 = 0, b5 = 0, b6 = 0;
    for (let i = 0; i < length; i += 1) {
      const white = Math.random() * 2 - 1;
      b0 = 0.99886 * b0 + white * 0.0555179;
      b1 = 0.99332 * b1 + white * 0.0750759;
      b2 = 0.96900 * b2 + white * 0.1538520;
      b3 = 0.86650 * b3 + white * 0.3104856;
      b4 = 0.55000 * b4 + white * 0.5329522;
      b5 = -0.7616 * b5 - white * 0.0168980;
      data[i] = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362) * 0.11;
      b6 = white * 0.115926;
    }
    return buffer;
  }

  async function ensureAudio() {
    const AudioCtx = window.AudioContext || window.webkitAudioContext;
    if (!AudioCtx) {
      setFeedback('Este navegador não oferece suporte ao áudio usado pelo painel.');
      testBtn.disabled = true;
      enabledInput.disabled = true;
      return false;
    }

    ctx = ctx || new AudioCtx();
    loadSample(ctx);
    if (ctx.state === 'suspended') {
      try { await ctx.resume(); } catch (_) {}
    }
    unlocked = ctx.state === 'running';
    return unlocked;
  }

  function currentMotorState() {
    return motorVisual.dataset.state || 'offline';
  }

  function updateVolumeDisplay() {
    if (volumeValue) volumeValue.textContent = `${settings.volume}%`;
  }

  function updateEnabledText() {
    if (!enabledText) return;
    enabledText.textContent = settings.enabled ? 'Ativado' : 'Desativado';
    enabledText.dataset.state = settings.enabled ? 'on' : 'off';
  }

  // Motor de indução trifásico de 4 polos em rede de 60 Hz:
  // - zumbido magnético em 120 Hz (2× a rede) com harmônicos, presente assim
  //   que o motor é energizado e cortado na hora em que é desligado;
  // - rotor a ~1750 rpm (29,2 Hz) e ventoinha de 5 pás (~146 Hz de passagem);
  // - ar da ventoinha e rolamentos, que sobem e descem com a rotação.
  const ROTOR_HZ = 29.2;
  const FAN_BLADES = 5;
  const STARTUP_S = 1.8;
  const COAST_S = 3.4;
  const HUM_LEVEL = 0.14;
  const MIX_LEVEL = 0.42;

  const easeStartup = (x) => x * x * (3 - 2 * x);
  const easeCoast = (x) => (1 - Math.exp(-2.2 * x)) / (1 - Math.exp(-2.2));

  function holdParam(param, time) {
    if (typeof param.cancelAndHoldAtTime === 'function') {
      param.cancelAndHoldAtTime(time);
    } else {
      param.cancelScheduledValues(time);
      param.setValueAtTime(param.value, time);
    }
  }

  function makeHumWave(audioCtx) {
    // Fundamental de 120 Hz com harmônicos pares/ímpares decrescentes: dá o
    // "zumbido áspero" de transformador em vez de um tom puro.
    const harmonics = [0, 1, 0.55, 0.34, 0.22, 0.12, 0.09, 0.05, 0.03];
    const real = new Float32Array(harmonics.length);
    const imag = Float32Array.from(harmonics);
    return audioCtx.createPeriodicWave(real, imag);
  }

  // Parâmetros que acompanham a rotação ("speed": 0 parado, 1 nominal).
  // Começa parado e acelera em STARTUP_S; rampSpeed também faz a parada.
  function speedControl(driven, now, startup) {
    let segment = { t0: now, dur: 0, from: startup ? 0 : 1, to: startup ? 0 : 1, ease: easeStartup };

    function speedAt(time) {
      const { t0, dur, from, to, ease } = segment;
      if (time <= t0 || dur <= 0) return time <= t0 ? from : to;
      if (time >= t0 + dur) return to;
      return from + (to - from) * ease((time - t0) / dur);
    }

    function rampSpeed(to, dur, ease, time) {
      const from = speedAt(time);
      const start = time + 0.005;
      const points = 96;
      for (const [param, map] of driven) {
        holdParam(param, time);
        const curve = new Float32Array(points);
        for (let i = 0; i < points; i += 1) {
          curve[i] = map(from + (to - from) * ease(i / (points - 1)));
        }
        param.setValueCurveAtTime(curve, start, dur);
      }
      segment = { t0: start, dur, from, to, ease };
    }

    for (const [param, map] of driven) param.setValueAtTime(map(segment.from), now);
    if (startup) rampSpeed(1, STARTUP_S, easeStartup, now);
    return { speedAt, rampSpeed };
  }

  function buildMotorSound(audioCtx, destination, targetGain, { startup = true } = {}) {
    const now = audioCtx.currentTime;
    const master = audioCtx.createGain();
    master.gain.setValueAtTime(0.0001, now);
    master.gain.exponentialRampToValueAtTime(Math.max(targetGain, 0.0001), now + 0.06);
    master.connect(destination);
    // Nível da mistura: mantém o pico abaixo de 1 mesmo com volume em 100%.
    const bus = audioCtx.createGain();
    bus.gain.value = MIX_LEVEL;
    bus.connect(master);

    const noiseBuffer = makeNoiseBuffer(audioCtx, 3);
    const noiseSource = () => {
      const src = audioCtx.createBufferSource();
      src.buffer = noiseBuffer;
      src.loop = true;
      return src;
    };

    // Zumbido elétrico (frequência fixa: depende da rede, não da rotação).
    const hum = audioCtx.createOscillator();
    hum.setPeriodicWave(makeHumWave(audioCtx));
    hum.frequency.value = 120;
    const hum60 = audioCtx.createOscillator();
    hum60.type = 'sine';
    hum60.frequency.value = 60;
    const hum60Gain = audioCtx.createGain();
    hum60Gain.gain.value = 0.35;
    const humGain = audioCtx.createGain();
    humGain.gain.setValueAtTime(0, now);
    if (startup) {
      // Corrente de partida alta: o zumbido começa mais forte e assenta.
      humGain.gain.linearRampToValueAtTime(HUM_LEVEL * 1.7, now + 0.05);
      humGain.gain.setTargetAtTime(HUM_LEVEL, now + 0.5, 0.45);
    } else {
      humGain.gain.linearRampToValueAtTime(HUM_LEVEL, now + 0.05);
    }
    // "Energia": corta o zumbido inteiro (inclusive a modulação do rotor).
    const humPower = audioCtx.createGain();
    hum.connect(humGain);
    hum60.connect(hum60Gain).connect(humGain);
    humGain.connect(humPower).connect(bus);

    // Rotor: leve desbalanceamento que modula o zumbido e um ronco grave.
    const rotor = audioCtx.createOscillator();
    rotor.type = 'triangle';
    const rotorOut = audioCtx.createGain();
    rotor.connect(rotorOut).connect(bus);
    const rotorMod = audioCtx.createGain();
    rotor.connect(rotorMod).connect(humGain.gain);

    // Ar da ventoinha: ruído rosa filtrado, pulsando na passagem das pás.
    const fanNoise = noiseSource();
    const fanFilter = audioCtx.createBiquadFilter();
    fanFilter.type = 'lowpass';
    fanFilter.Q.value = 0.6;
    const fanBody = audioCtx.createBiquadFilter();
    fanBody.type = 'peaking';
    fanBody.Q.value = 1.2;
    fanBody.gain.value = 6;
    const fanAmp = audioCtx.createGain();
    fanNoise.connect(fanFilter).connect(fanBody).connect(fanAmp).connect(bus);
    const blade = audioCtx.createOscillator();
    blade.type = 'sine';
    const bladeDepth = audioCtx.createGain();
    blade.connect(bladeDepth).connect(fanAmp.gain);

    // Rolamentos: chiado agudo bem discreto.
    const bearingNoise = noiseSource();
    const bearingFilter = audioCtx.createBiquadFilter();
    bearingFilter.type = 'bandpass';
    bearingFilter.frequency.value = 5200;
    bearingFilter.Q.value = 0.9;
    const bearingGain = audioCtx.createGain();
    bearingNoise.connect(bearingFilter).connect(bearingGain).connect(bus);

    // Tudo que acompanha a rotação é derivado de "speed" (0 parado, 1 nominal).
    const driven = [
      [rotor.frequency, (s) => Math.max(0.5, ROTOR_HZ * s)],
      [rotorOut.gain, (s) => 0.10 * s],
      [rotorMod.gain, (s) => 0.05 * s],
      [blade.frequency, (s) => Math.max(0.5, ROTOR_HZ * FAN_BLADES * s)],
      [bladeDepth.gain, (s) => 1.1 * s * s],
      [fanAmp.gain, (s) => 2.4 * s ** 1.6],
      [fanFilter.frequency, (s) => 160 + 1300 * s],
      [fanBody.frequency, (s) => Math.max(40, ROTOR_HZ * FAN_BLADES * s)],
      [bearingGain.gain, (s) => 0.02 * s],
    ];

    const { speedAt, rampSpeed } = speedControl(driven, now, startup);

    const sources = [hum, hum60, rotor, blade, fanNoise, bearingNoise];
    for (const source of [hum, hum60, rotor, blade, fanNoise]) source.start(now);
    // Deslocado para o chiado dos rolamentos não ficar em fase com o do ar.
    bearingNoise.start(now, 1.3);

    function stop({ fade = true } = {}) {
      const time = audioCtx.currentTime;
      if (!fade) {
        holdParam(master.gain, time);
        master.gain.setTargetAtTime(0.0001, time, 0.01);
        return 0.05;
      }
      // Sem energia o zumbido some na hora; a parte mecânica desacelera.
      holdParam(humPower.gain, time);
      humPower.gain.setTargetAtTime(0, time, 0.03);
      const coast = COAST_S * Math.max(0.25, speedAt(time));
      rampSpeed(0, coast, easeCoast, time);
      holdParam(master.gain, time);
      master.gain.setTargetAtTime(0.0001, time + coast * 0.75, coast * 0.08);
      return coast + 0.1;
    }

    return { master, sources, stop };
  }

  // Gravação real de um motor (motor-ligado.mp3), usada inteira:
  // - início (0 a 1 s): estalo de ligar, que sinaliza a partida;
  // - trecho estável (1 a 3,55 s): repete enquanto o motor está ligado;
  // - final (3,70 s ao fim): estalos de desligar e o motor parando.
  const SAMPLE_URL = './motor-ligado.mp3';
  const LOOP_START_S = 1.0;
  const LOOP_END_S = 3.55;
  const LOOP_XFADE_S = 0.25;
  const OUTRO_START_S = 3.70;
  const SAMPLE_RMS = 0.25;  // Nível do trecho estável, próximo do som sintetizado.
  const CLICK_PEAK = 1.3;   // Pico dos estalos antes do volume (máx. 0,57 em 100%).
  let samplePromise = null;
  let sample = null;

  function loadSample(audioCtx) {
    if (!samplePromise) {
      samplePromise = fetch(SAMPLE_URL)
        .then((resposta) => {
          if (!resposta.ok) throw new Error(`HTTP ${resposta.status}`);
          return resposta.arrayBuffer();
        })
        .then((dados) => audioCtx.decodeAudioData(dados))
        .then((decoded) => { sample = makeSampleParts(audioCtx, decoded); return sample; })
        .catch(() => null);  // Sem o arquivo, fica o som sintetizado.
    }
    return samplePromise;
  }

  function copyRange(audioCtx, decoded, from, to) {
    const buffer = audioCtx.createBuffer(decoded.numberOfChannels, Math.max(1, to - from), decoded.sampleRate);
    for (let c = 0; c < decoded.numberOfChannels; c += 1) {
      buffer.getChannelData(c).set(decoded.getChannelData(c).subarray(from, to));
    }
    return buffer;
  }

  // "main" = início com o estalo + trecho estável. O fim do trecho estável
  // se funde no que vem logo antes dele (potência constante): ao voltar para
  // loopStart a onda continua sem clique. "outro" = desligamento.
  function makeSampleParts(audioCtx, decoded) {
    const rate = decoded.sampleRate;
    const loopStart = Math.floor(LOOP_START_S * rate);
    const loopEnd = Math.min(decoded.length, Math.floor(LOOP_END_S * rate));
    const fade = Math.floor(LOOP_XFADE_S * rate);
    const main = copyRange(audioCtx, decoded, 0, loopEnd);
    let squares = 0;
    for (let c = 0; c < decoded.numberOfChannels; c += 1) {
      const src = decoded.getChannelData(c);
      const dst = main.getChannelData(c);
      for (let i = 0; i < fade; i += 1) {
        const x = (i / fade) * Math.PI / 2;
        const j = loopEnd - fade + i;
        dst[j] = src[j] * Math.cos(x) + src[loopStart - fade + i] * Math.sin(x);
      }
      for (let i = loopStart; i < loopEnd; i += 1) squares += dst[i] * dst[i];
    }
    const outro = copyRange(audioCtx, decoded, Math.floor(OUTRO_START_S * rate), decoded.length);
    // Pontas do desligamento sem estalo digital (o estalo gravado continua).
    const ramp = Math.floor(0.01 * rate), tail = Math.floor(0.15 * rate);
    for (let c = 0; c < outro.numberOfChannels; c += 1) {
      const d = outro.getChannelData(c);
      for (let i = 0; i < ramp && i < d.length; i += 1) d[i] *= i / ramp;
      for (let i = 0; i < tail && i < d.length; i += 1) d[d.length - 1 - i] *= i / tail;
    }
    const rms = Math.sqrt(squares / ((loopEnd - loopStart) * decoded.numberOfChannels)) || 1;
    const level = SAMPLE_RMS / rms;
    // Os estalos foram gravados no máximo; com o ganho do trecho estável
    // estourariam. Compressão suave só nos picos: depois do ganho, nenhum
    // passa de CLICK_PEAK, e o som baixo fica igual.
    const knee = CLICK_PEAK / level;
    const soften = (d, from, to) => {
      for (let i = from; i < to; i += 1) d[i] = knee * Math.tanh(d[i] / knee);
    };
    for (let c = 0; c < decoded.numberOfChannels; c += 1) {
      soften(main.getChannelData(c), 0, loopStart);
      soften(outro.getChannelData(c), 0, outro.length);
    }
    return {
      main, outro, level,
      loopStart: loopStart / rate, loopEnd: loopEnd / rate,
    };
  }

  function buildSampleSound(audioCtx, destination, targetGain, parts) {
    const now = audioCtx.currentTime;
    const master = audioCtx.createGain();
    master.gain.value = Math.max(targetGain, 0.0001);
    master.connect(destination);
    const level = audioCtx.createGain();
    level.gain.value = parts.level;
    level.connect(master);

    const source = audioCtx.createBufferSource();
    source.buffer = parts.main;
    source.loop = true;
    source.loopStart = parts.loopStart;
    source.loopEnd = parts.loopEnd;
    const running = audioCtx.createGain();
    source.connect(running).connect(level);
    source.start(now);  // Começa pelo estalo de ligar.
    const sources = [source];

    function stop({ fade = true } = {}) {
      const time = audioCtx.currentTime;
      holdParam(running.gain, time);
      running.gain.setTargetAtTime(0, time, fade ? 0.01 : 0.005);
      if (!fade) {
        // Corte imediato (outro som vai começar): cala também o desligamento.
        holdParam(master.gain, time);
        master.gain.setTargetAtTime(0.0001, time, 0.005);
        return 0.05;
      }
      // Desligamento gravado: estalos do interruptor e o motor parando.
      const outro = audioCtx.createBufferSource();
      outro.buffer = parts.outro;
      outro.connect(level);
      outro.start(time);
      sources.push(outro);
      return parts.outro.duration + 0.05;
    }

    return { master, sources, stop };
  }

  function createMotorSound({ startup = true } = {}) {
    if (!ctx) return null;
    // Um som anterior ainda desacelerando não pode tocar junto com o novo.
    silenceCoasting();
    const target = gainForVolume(settings.volume);
    return sample
      ? buildSampleSound(ctx, ctx.destination, target, sample)
      : buildMotorSound(ctx, ctx.destination, target, { startup });
  }

  function releaseSound(playing, tail) {
    const timer = setTimeout(() => {
      if (coasting?.playing === playing) coasting = null;
      for (const source of playing.sources) {
        try { source.stop(); } catch (_) {}
      }
      try { playing.master.disconnect(); } catch (_) {}
    }, Math.ceil(tail * 1000) + 30);
    return timer;
  }

  function silenceCoasting() {
    if (!coasting) return;
    const { playing, timer } = coasting;
    coasting = null;
    clearTimeout(timer);
    let tail = 0.05;
    try { tail = playing.stop({ fade: false }); } catch (_) {}
    releaseSound(playing, tail);
  }

  function stopActive({ fade = true } = {}) {
    if (!active || !ctx) return;

    if (testTimer) {
      clearTimeout(testTimer);
      testTimer = null;
    }

    const playing = active;
    active = null;
    silenceCoasting();
    let tail = fade ? 0.9 : 0.05;
    try { tail = playing.stop({ fade }); } catch (_) {}
    const timer = releaseSound(playing, tail);
    if (fade) coasting = { playing, timer };

    testBtn.textContent = '🔊 Testar som do motor';
    testBtn.setAttribute('aria-pressed', 'false');
  }

  async function startAutomatic() {
    if (!settings.enabled || currentMotorState() !== 'running' || active?.mode === 'auto') return;
    if (!(await ensureAudio())) return;
    await loadSample(ctx);
    if (!settings.enabled || currentMotorState() !== 'running' || active?.mode === 'auto') return;

    stopActive({ fade: false });
    active = { mode: 'auto', ...createMotorSound({ startup: true }) };
    setFeedback(`Som automático ativo · volume ${settings.volume}%.`);
  }

  function stopAutomatic() {
    if (active?.mode === 'auto') stopActive({ fade: true });
    if (settings.enabled) {
      setFeedback(currentMotorState() === 'running'
        ? 'Som habilitado. Interaja com a página para liberar o áudio do navegador.'
        : 'Som habilitado. Aguardando o motor ligar.');
    } else {
      setFeedback('Som automático desativado.');
    }
  }

  async function syncWithMotor() {
    if (!settings.enabled) {
      stopAutomatic();
      return;
    }

    if (currentMotorState() === 'running') {
      if (unlocked || ctx?.state === 'running') await startAutomatic();
      else setFeedback('Som habilitado. Interaja com a página para liberar o áudio do navegador.');
    } else {
      stopAutomatic();
    }
  }

  async function toggleTest() {
    if (active?.mode === 'test') {
      stopActive({ fade: true });
      await syncWithMotor();
      return;
    }

    if (!(await ensureAudio())) return;
    await loadSample(ctx);
    if (active?.mode === 'test') return;  // Dois cliques enquanto a gravação carregava.
    stopActive({ fade: false });

    active = { mode: 'test', ...createMotorSound({ startup: true }) };
    testBtn.textContent = '■ Parar teste de som';
    testBtn.setAttribute('aria-pressed', 'true');
    setFeedback(`Teste local · volume ${settings.volume}% · não envia comando ao motor.`);

    testTimer = setTimeout(async () => {
      if (active?.mode === 'test') stopActive({ fade: true });
      await syncWithMotor();
    }, 5000);
  }

  function applyLiveVolume() {
    if (!active || !ctx) return;
    const now = ctx.currentTime;
    const target = gainForVolume(settings.volume);
    try {
      active.master.gain.cancelScheduledValues(now);
      active.master.gain.setTargetAtTime(Math.max(target, 0.0001), now, 0.04);
    } catch (_) {}
  }

  enabledInput.checked = settings.enabled;
  volumeInput.value = String(settings.volume);
  updateVolumeDisplay();
  updateEnabledText();
  testBtn.setAttribute('aria-pressed', 'false');

  enabledInput.addEventListener('change', async () => {
    settings.enabled = enabledInput.checked;
    saveSettings();
    updateEnabledText();

    if (settings.enabled) {
      await ensureAudio();
      await syncWithMotor();
    } else {
      if (active?.mode === 'auto') stopActive({ fade: true });
      setFeedback('Som automático desativado.');
    }
  });

  volumeInput.addEventListener('input', () => {
    settings.volume = clampVolume(volumeInput.value);
    updateVolumeDisplay();
    saveSettings();
    applyLiveVolume();

    if (active?.mode === 'auto') setFeedback(`Som automático ativo · volume ${settings.volume}%.`);
    if (active?.mode === 'test') setFeedback(`Teste local · volume ${settings.volume}% · não envia comando ao motor.`);
  });

  testBtn.addEventListener('click', toggleTest);

  const observer = new MutationObserver(() => { syncWithMotor(); });
  observer.observe(motorVisual, { attributes: true, attributeFilter: ['data-state'] });

  const unlock = async () => {
    if (!settings.enabled || unlocked) return;
    if (await ensureAudio()) await syncWithMotor();
  };
  window.addEventListener('pointerdown', unlock, { passive: true });
  window.addEventListener('keydown', unlock);

  if (settings.enabled) {
    setFeedback(currentMotorState() === 'running'
      ? 'Som habilitado. Interaja com a página para liberar o áudio do navegador.'
      : 'Som habilitado. Aguardando o motor ligar.');
  } else {
    setFeedback('Som automático desativado.');
  }

  window.iotmotorMotorSound = {
    sync: syncWithMotor,
    stop: () => stopActive({ fade: true }),
    settings: () => ({ ...settings }),
  };
})();