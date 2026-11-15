export function playWordAcceptedSound() {
  try {
    if (globalThis.localStorage?.getItem('scrabble:sound-enabled') !== 'true') return false;
    const AudioContextClass = globalThis.AudioContext || globalThis.webkitAudioContext;
    if (!AudioContextClass) return false;
    const context = new AudioContextClass();
    const now = context.currentTime;
    const notes = [659.25, 783.99, 987.77];
    notes.forEach((frequency, index) => {
      const oscillator = context.createOscillator();
      const gain = context.createGain();
      oscillator.type = 'sine';
      oscillator.frequency.setValueAtTime(frequency, now + index * 0.11);
      gain.gain.setValueAtTime(0.0001, now + index * 0.11);
      gain.gain.exponentialRampToValueAtTime(0.12, now + index * 0.11 + 0.015);
      gain.gain.exponentialRampToValueAtTime(0.0001, now + index * 0.11 + 0.18);
      oscillator.connect(gain);
      gain.connect(context.destination);
      oscillator.start(now + index * 0.11);
      oscillator.stop(now + index * 0.11 + 0.19);
    });
    globalThis.setTimeout?.(() => context.close().catch(() => {}), 650);
    return true;
  } catch {
    return false;
  }
}
