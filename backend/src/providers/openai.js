'use strict';
// Voz con la API de OpenAI:
//  - Transcripción: POST /audio/transcriptions (multipart: file, model, language,
//    response_format=json) → {text}. Modelos: gpt-4o-mini-transcribe, gpt-4o-transcribe, whisper-1.
//  - Síntesis: POST /audio/speech (JSON: model, input ≤4096, voice, instructions,
//    response_format=mp3) → bytes de audio. Modelos: gpt-4o-mini-tts, tts-1, tts-1-hd.
// Referencia: https://developers.openai.com/api/reference/resources/audio

const { UpstreamError } = require('./anthropic');

async function withTimeout(cfg, fn) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), cfg.upstreamTimeoutMs + 6000);
  try {
    return await fn(ctrl.signal);
  } catch (e) {
    if (e instanceof UpstreamError) throw e;
    throw new UpstreamError(e.name === 'AbortError' ? 'Tiempo de espera de voz agotado' : 'No se pudo contactar con el servicio de voz', 504);
  } finally {
    clearTimeout(timer);
  }
}

async function transcribe(cfg, wavBuffer, language, fetchImpl = fetch) {
  if (!cfg.openaiKey) throw new UpstreamError('OPENAI_API_KEY no configurada', 503);
  return withTimeout(cfg, async (signal) => {
    const form = new FormData();
    form.append('file', new Blob([wavBuffer], { type: 'audio/wav' }), 'voz.wav');
    form.append('model', cfg.openaiSttModel);
    form.append('language', language);
    form.append('response_format', 'json');
    const res = await fetchImpl(`${cfg.openaiBaseUrl}/audio/transcriptions`, {
      method: 'POST',
      headers: { authorization: `Bearer ${cfg.openaiKey}` },
      body: form,
      signal,
    });
    const txt = await res.text();
    if (!res.ok) throw new UpstreamError(`STT respondió ${res.status}`, res.status === 429 ? 429 : 502);
    let data;
    try {
      data = JSON.parse(txt);
    } catch {
      throw new UpstreamError('Respuesta STT ilegible');
    }
    return { text: String(data.text || '').trim() };
  });
}

async function speak(cfg, { text, voice, instructions }, fetchImpl = fetch) {
  if (!cfg.openaiKey) throw new UpstreamError('OPENAI_API_KEY no configurada', 503);
  return withTimeout(cfg, async (signal) => {
    const body = { model: cfg.openaiTtsModel, input: text.slice(0, 4096), voice, response_format: 'mp3' };
    // "instructions" no funciona con tts-1 / tts-1-hd
    if (instructions && !cfg.openaiTtsModel.startsWith('tts-1')) body.instructions = instructions;
    const res = await fetchImpl(`${cfg.openaiBaseUrl}/audio/speech`, {
      method: 'POST',
      headers: { authorization: `Bearer ${cfg.openaiKey}`, 'content-type': 'application/json' },
      body: JSON.stringify(body),
      signal,
    });
    if (!res.ok) throw new UpstreamError(`TTS respondió ${res.status}`, res.status === 429 ? 429 : 502);
    const buf = Buffer.from(await res.arrayBuffer());
    if (buf.length < 100) throw new UpstreamError('Audio TTS vacío');
    return { audio: buf, contentType: 'audio/mpeg' };
  });
}

module.exports = { transcribe, speak };
