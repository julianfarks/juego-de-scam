'use strict';
// Límites de uso en memoria: ventana deslizante por minuto, cuotas diarias por
// dispositivo y prevención de peticiones duplicadas.

class Limiter {
  constructor(cfg, now = () => Date.now()) {
    this.cfg = cfg;
    this.now = now;
    this.minute = new Map(); // key -> [timestamps]
    this.daily = new Map(); // dev -> {day, requests, ttsChars, sttSeconds}
    this.dedupe = new Map(); // hash -> {at, promise}
  }

  _day() {
    return new Date(this.now()).toISOString().slice(0, 10);
  }

  _dailyFor(dev) {
    const day = this._day();
    let d = this.daily.get(dev);
    if (!d || d.day !== day) {
      d = { day, requests: 0, ttsChars: 0, sttSeconds: 0 };
      this.daily.set(dev, d);
    }
    return d;
  }

  // Devuelve null si se permite, o un motivo si se rechaza.
  check(dev, kind = 'chat', amount = 0) {
    const t = this.now();
    const arr = (this.minute.get(dev) || []).filter((x) => t - x < 60000);
    if (arr.length >= this.cfg.ratePerMinute) {
      this.minute.set(dev, arr);
      return 'Demasiadas peticiones por minuto';
    }
    const d = this._dailyFor(dev);
    if (d.requests >= this.cfg.dailyPerDevice) return 'Límite diario de peticiones alcanzado';
    if (kind === 'tts' && d.ttsChars + amount > this.cfg.dailyTtsCharsPerDevice) return 'Límite diario de voz alcanzado';
    if (kind === 'stt' && d.sttSeconds + amount > this.cfg.dailySttSecondsPerDevice) return 'Límite diario de transcripción alcanzado';
    arr.push(t);
    this.minute.set(dev, arr);
    d.requests += 1;
    if (kind === 'tts') d.ttsChars += amount;
    if (kind === 'stt') d.sttSeconds += amount;
    return null;
  }

  usage(dev) {
    return { ...this._dailyFor(dev) };
  }

  // Si llega exactamente la misma petición en menos de 4 s, se reutiliza la respuesta.
  dedupeRun(key, fn) {
    const t = this.now();
    for (const [k, v] of this.dedupe) if (t - v.at > 4000) this.dedupe.delete(k);
    const hit = this.dedupe.get(key);
    if (hit) return hit.promise;
    const promise = fn();
    this.dedupe.set(key, { at: t, promise });
    promise.catch(() => this.dedupe.delete(key));
    return promise;
  }
}

module.exports = { Limiter };
