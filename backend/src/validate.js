'use strict';
// Validación de entradas y salidas. Todo lo que no encaja se recorta o se rechaza.

const EMOTIONS = ['neutral', 'happy', 'joy', 'angry', 'confused', 'surprised', 'distrust', 'sad'];
const GESTURES = ['', 'nod', 'shake', 'laugh', 'point', 'head_scratch', 'arms_crossed', 'angry', 'surprised', 'think', 'hangup'];
const STATE_KEYS = ['trust', 'patience', 'humor', 'understanding', 'suspicion'];

class BadRequest extends Error {
  constructor(msg) {
    super(msg);
    this.status = 400;
  }
}

function s(v, max, def = '') {
  if (v === undefined || v === null) return def;
  return String(v).replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g, '').slice(0, max);
}

function num(v, min, max, def = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return def;
  return Math.min(max, Math.max(min, n));
}

function arr(v, maxItems, maxLen) {
  if (!Array.isArray(v)) return [];
  return v.slice(0, maxItems).map((x) => s(x, maxLen));
}

// Tacha secuencias largas de dígitos (posibles números de tarjeta o cuenta).
function scrubDigits(t) {
  return t.replace(/(?:\d[\s\-.]?){7,}/g, '[número tachado]');
}

function chatRequest(body) {
  if (!body || typeof body !== 'object') throw new BadRequest('JSON inválido');
  const c = body.client || {};
  const o = body.offer || {};
  const st = body.state || {};
  const playerText = s(body.player_text, 500).trim();
  if (!playerText) throw new BadRequest('player_text vacío');
  const facts = {};
  if (c.facts && typeof c.facts === 'object') {
    for (const k of Object.keys(c.facts).slice(0, 8)) facts[s(k, 20)] = s(c.facts[k], 120);
  }
  const history = Array.isArray(body.history)
    ? body.history.slice(-10).map((h) => ({ role: h && h.role === 'vendedor' ? 'vendedor' : 'cliente', text: scrubDigits(s(h && h.text, 300)) }))
    : [];
  const state = {};
  for (const k of STATE_KEYS) state[k] = num(st[k], 0, 100, 50);
  return {
    language: ['es', 'en'].includes(body.language) ? body.language : 'es',
    client: {
      name: s(c.name, 60, 'Cliente'),
      personality: s(c.personality, 30),
      personality_name: s(c.personality_name, 40),
      style: s(c.style, 400),
      facts,
      quirks: arr(c.quirks, 6, 30),
      example_lines: arr(c.example_lines, 4, 160),
    },
    offer: { name: s(o.name, 80), pitch: s(o.pitch, 200), reference_price: num(o.reference_price, 0, 100000, 0) },
    state: {
      ...state,
      pending_objections: arr(st.pending_objections, 4, 40),
      resolved_objections: num(st.resolved_objections, 0, 20, 0),
      amounts_mentioned: arr(st.amounts_mentioned, 6, 12),
      stated_price: num(st.stated_price, -1, 1000000, -1),
      unfulfilled_promises: arr(st.unfulfilled_promises, 3, 80).map(scrubDigits),
      contradictions: arr(st.contradictions, 4, 60),
      pending_question: s(st.pending_question, 160),
      decisions: arr(st.decisions, 4, 60),
      provisional: s(st.provisional, 20),
      turn: num(st.turn, 0, 200, 0),
      seconds_left: num(st.seconds_left, 0, 1000, 60),
      summary: scrubDigits(s(st.summary, 800)),
      intro_done: Boolean(st.intro_done),
      offer_explained: Boolean(st.offer_explained),
    },
    history,
    player_text: scrubDigits(playerText),
    analysis: {
      intents: arr(body.analysis && body.analysis.intents, 12, 30),
      numbers: arr(body.analysis && body.analysis.numbers, 6, 12),
      events: arr(body.analysis && body.analysis.events, 12, 40),
    },
    emotion_hint: EMOTIONS.includes(body.emotion_hint) ? body.emotion_hint : 'neutral',
  };
}

// Extrae el primer objeto JSON del texto del modelo y lo normaliza.
function parseModelReply(text) {
  let obj = null;
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start >= 0 && end > start) {
    try {
      obj = JSON.parse(text.slice(start, end + 1));
    } catch {
      obj = null;
    }
  }
  if (!obj || typeof obj !== 'object') {
    obj = { reply: text };
  }
  return normalizeReply(obj);
}

function normalizeReply(obj) {
  let reply = scrubDigits(s(obj.reply, 400)).replace(/\s+/g, ' ').trim();
  if (!reply) reply = '¿Perdone? No le he entendido bien.';
  const deltas = {};
  const d = obj.deltas && typeof obj.deltas === 'object' ? obj.deltas : {};
  for (const k of STATE_KEYS) deltas[k] = num(d[k], -10, 10, 0);
  return {
    reply,
    emotion: EMOTIONS.includes(obj.emotion) ? obj.emotion : 'neutral',
    gesture: GESTURES.includes(obj.gesture) ? obj.gesture : '',
    deltas,
    receptive: num(obj.receptive, 0, 1, 0),
    wants_to_hang_up: Boolean(obj.wants_to_hang_up),
  };
}

function ttsRequest(body) {
  if (!body || typeof body !== 'object') throw new BadRequest('JSON inválido');
  const text = scrubDigits(s(body.text, 500)).trim();
  if (!text) throw new BadRequest('text vacío');
  const voices = ['alloy', 'ash', 'ballad', 'coral', 'echo', 'fable', 'onyx', 'nova', 'sage', 'shimmer', 'verse', 'marin', 'cedar'];
  return { text, voice: voices.includes(body.voice) ? body.voice : 'alloy', instructions: s(body.instructions, 600) };
}

function bossRequest(body) {
  const st = (body && body.stats) || {};
  return {
    language: ['es', 'en'].includes(body && body.language) ? body.language : 'es',
    stats: {
      day: num(st.day, 1, 999, 1),
      income: num(st.income, -1e7, 1e7, 0),
      quota: num(st.quota, 0, 1e7, 0),
      grade: ['S', 'A', 'B', 'C', 'D', 'F'].includes(st.grade) ? st.grade : 'C',
      calls: num(st.calls, 0, 999, 0),
      successes: num(st.successes, 0, 999, 0),
      hangups: num(st.hangups, 0, 999, 0),
      contradictions: num(st.contradictions, 0, 999, 0),
      best_sale: num(st.best_sale, 0, 1e7, 0),
      incidents: num(st.incidents, 0, 99, 0),
      missed: num(st.missed, 0, 99, 0),
      passed: Boolean(st.passed),
    },
  };
}

module.exports = { chatRequest, parseModelReply, normalizeReply, ttsRequest, bossRequest, scrubDigits, BadRequest, EMOTIONS, GESTURES };
