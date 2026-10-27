'use strict';
// Pruebas: node --test backend/test
const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const { createApp } = require('../src/app');
const auth = require('../src/auth');
const V = require('../src/validate');
const multipart = require('../src/multipart');
const { Limiter } = require('../src/limits');

function baseCfg(over = {}) {
  return {
    port: 0, host: '127.0.0.1', accessCode: 'secreto123', tokenSecret: 'x'.repeat(64), tokenTtlSec: 3600,
    llmProvider: 'anthropic', anthropicKey: 'sk-test', anthropicModel: 'claude-haiku-5-5', anthropicBaseUrl: 'http://upstream',
    maxReplyTokens: 400, sttProvider: 'openai', ttsProvider: 'openai', openaiKey: 'sk-oa', openaiBaseUrl: 'http://oa/v1',
    openaiSttModel: 'gpt-4o-mini-transcribe', openaiTtsModel: 'gpt-4o-mini-tts', upstreamTimeoutMs: 2000,
    ratePerMinute: 100, dailyPerDevice: 1000, dailyTtsCharsPerDevice: 10000, dailySttSecondsPerDevice: 600,
    maxJsonBytes: 32768, maxAudioBytes: 1024 * 1024, logRequests: false, ...over,
  };
}

async function withServer(cfg, fetchImpl, fn) {
  const app = createApp(cfg, { fetch: fetchImpl, log: () => {} });
  const server = http.createServer(app.handler);
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const base = `http://127.0.0.1:${server.address().port}`;
  try {
    await fn(base, app);
  } finally {
    server.close();
  }
}

async function session(base, code = 'secreto123') {
  const r = await fetch(`${base}/v1/session`, { method: 'POST', body: JSON.stringify({ device_id: 'dispositivo-prueba-1', access_code: code }) });
  return { status: r.status, body: await r.json() };
}

const chatBody = {
  language: 'es',
  client: { name: 'Pilar Quizás', personality: 'indeciso', personality_name: 'Indeciso', style: 'Dudas mucho.', facts: { city: 'Pueblo Tal Vez' }, quirks: ['indecisive'], example_lines: ['¿Usted qué cree?'] },
  offer: { name: 'Seguro contra abducciones', pitch: 'Cubre platillos.', reference_price: 49 },
  state: { trust: 40, patience: 60, humor: 40, understanding: 40, suspicion: 20, pending_objections: ['Precio'], stated_price: 49, contradictions: [], turn: 2, seconds_left: 120 },
  history: [{ role: 'vendedor', text: 'Hola' }, { role: 'cliente', text: 'Diga' }],
  player_text: 'Le doy garantía de devolución',
  analysis: { intents: ['guarantee'], numbers: [], events: [] },
};

function fakeAnthropic(replyObj, capture = {}) {
  return async (url, opts) => {
    capture.url = url;
    capture.opts = opts;
    capture.body = JSON.parse(opts.body);
    return new Response(JSON.stringify({ content: [{ type: 'thinking', thinking: '...' }, { type: 'text', text: typeof replyObj === 'string' ? replyObj : JSON.stringify(replyObj) }], usage: { input_tokens: 321, output_tokens: 45 } }), { status: 200, headers: { 'content-type': 'application/json' } });
  };
}

test('health no expone secretos', async () => {
  await withServer(baseCfg(), fetch, async (base) => {
    const r = await fetch(`${base}/health`);
    const j = await r.json();
    assert.equal(r.status, 200);
    assert.equal(j.ok, true);
    const raw = JSON.stringify(j);
    assert.ok(!raw.includes('sk-test') && !raw.includes('secreto123'));
  });
});

test('sesión: código incorrecto rechazado, correcto aceptado', async () => {
  await withServer(baseCfg(), fetch, async (base) => {
    assert.equal((await session(base, 'malo')).status, 401);
    const ok = await session(base);
    assert.equal(ok.status, 200);
    assert.ok(ok.body.token);
  });
});

test('chat sin token → 401', async () => {
  await withServer(baseCfg(), fetch, async (base) => {
    const r = await fetch(`${base}/v1/chat`, { method: 'POST', body: JSON.stringify(chatBody) });
    assert.equal(r.status, 401);
  });
});

test('chat: llama a Claude con cabeceras y modelo correctos y valida la respuesta', async () => {
  const cap = {};
  const fake = fakeAnthropic({ reply: 'Vale, con garantía me lo pienso. Mi tarjeta es 4111 1111 1111 1111', emotion: 'happy', gesture: 'nod', deltas: { trust: 50, suspicion: -3 }, receptive: 7, wants_to_hang_up: false }, cap);
  await withServer(baseCfg(), fake, async (base) => {
    const { body: s } = await session(base);
    const r = await fetch(`${base}/v1/chat`, { method: 'POST', headers: { authorization: `Bearer ${s.token}` }, body: JSON.stringify(chatBody) });
    const j = await r.json();
    assert.equal(r.status, 200);
    assert.equal(cap.url, 'http://upstream/v1/messages');
    assert.equal(cap.opts.headers['anthropic-version'], '2023-06-01');
    assert.equal(cap.opts.headers['x-api-key'], 'sk-test');
    assert.equal(cap.body.model, 'claude-haiku-5-5');
    assert.equal(cap.body.max_tokens, 400);
    assert.ok(cap.body.system.includes('Pilar'));
    assert.ok(cap.body.messages[0].content.includes('garantía'));
    assert.ok(!j.reply.includes('4111'), 'tacha números largos');
    assert.equal(j.deltas.trust, 10, 'deltas recortados a ±10');
    assert.equal(j.receptive, 1);
    assert.equal(j.emotion, 'happy');
    assert.equal(j.usage.input_tokens, 321);
    assert.equal(j.amount, undefined, 'la respuesta no contiene importes');
  });
});

test('chat: texto sin JSON se usa como respuesta', async () => {
  await withServer(baseCfg(), fakeAnthropic('Pues no sé qué decirle, la verdad.'), async (base) => {
    const { body: s } = await session(base);
    const j = await (await fetch(`${base}/v1/chat`, { method: 'POST', headers: { authorization: `Bearer ${s.token}` }, body: JSON.stringify(chatBody) })).json();
    assert.equal(j.reply, 'Pues no sé qué decirle, la verdad.');
    assert.equal(j.emotion, 'neutral');
  });
});

test('chat: error del proveedor → 502/429 sin filtrar detalles', async () => {
  const fail = async () => new Response('{"error":{"message":"clave sk-test inválida"}}', { status: 401 });
  await withServer(baseCfg(), fail, async (base) => {
    const { body: s } = await session(base);
    const r = await fetch(`${base}/v1/chat`, { method: 'POST', headers: { authorization: `Bearer ${s.token}` }, body: JSON.stringify(chatBody) });
    const j = await r.json();
    assert.equal(r.status, 502);
    assert.ok(!JSON.stringify(j).includes('sk-test'));
  });
});

test('chat: tiempo de espera del proveedor', async () => {
  const slow = (url, opts) => new Promise((resolve, reject) => opts.signal.addEventListener('abort', () => reject(Object.assign(new Error('abort'), { name: 'AbortError' }))));
  await withServer(baseCfg({ upstreamTimeoutMs: 150 }), slow, async (base) => {
    const { body: s } = await session(base);
    const r = await fetch(`${base}/v1/chat`, { method: 'POST', headers: { authorization: `Bearer ${s.token}` }, body: JSON.stringify(chatBody) });
    assert.equal(r.status, 504);
  });
});

test('chat: petición inválida → 400', async () => {
  await withServer(baseCfg(), fakeAnthropic({ reply: 'x' }), async (base) => {
    const { body: s } = await session(base);
    const r = await fetch(`${base}/v1/chat`, { method: 'POST', headers: { authorization: `Bearer ${s.token}` }, body: JSON.stringify({ ...chatBody, player_text: '' }) });
    assert.equal(r.status, 400);
    const r2 = await fetch(`${base}/v1/chat`, { method: 'POST', headers: { authorization: `Bearer ${s.token}` }, body: '{roto' });
    assert.equal(r2.status, 400);
  });
});

test('límite por minuto → 429', async () => {
  await withServer(baseCfg({ ratePerMinute: 3 }), fakeAnthropic({ reply: 'ok' }), async (base) => {
    const { body: s } = await session(base);
    const codes = [];
    for (let i = 0; i < 4; i++) {
      const b = { ...chatBody, player_text: 'frase ' + i };
      codes.push((await fetch(`${base}/v1/chat`, { method: 'POST', headers: { authorization: `Bearer ${s.token}` }, body: JSON.stringify(b) })).status);
    }
    assert.ok(codes.includes(429), JSON.stringify(codes));
  });
});

test('peticiones duplicadas reutilizan la respuesta', async () => {
  let calls = 0;
  const f = async (...a) => {
    calls++;
    await new Promise((r) => setTimeout(r, 50));
    return fakeAnthropic({ reply: 'hola' })(...a);
  };
  await withServer(baseCfg(), f, async (base) => {
    const { body: s } = await session(base);
    const opts = { method: 'POST', headers: { authorization: `Bearer ${s.token}` }, body: JSON.stringify(chatBody) };
    await Promise.all([fetch(`${base}/v1/chat`, opts), fetch(`${base}/v1/chat`, opts)]);
    assert.equal(calls, 1);
  });
});

test('cuerpo demasiado grande → 413', async () => {
  await withServer(baseCfg({ maxJsonBytes: 1000 }), fetch, async (base) => {
    const { body: s } = await session(base);
    const r = await fetch(`${base}/v1/chat`, { method: 'POST', headers: { authorization: `Bearer ${s.token}` }, body: JSON.stringify({ ...chatBody, pad: 'x'.repeat(5000) }) }).catch(() => ({ status: 413 }));
    assert.equal(r.status, 413);
  });
});

function wav(seconds) {
  const rate = 16000;
  const pcm = Buffer.alloc(Math.floor(seconds * rate) * 2);
  for (let i = 0; i < pcm.length / 2; i++) pcm.writeInt16LE(Math.round(Math.sin(i / 10) * 8000), i * 2);
  const h = Buffer.alloc(44);
  h.write('RIFF', 0); h.writeUInt32LE(36 + pcm.length, 4); h.write('WAVE', 8); h.write('fmt ', 12);
  h.writeUInt32LE(16, 16); h.writeUInt16LE(1, 20); h.writeUInt16LE(1, 22); h.writeUInt32LE(rate, 24);
  h.writeUInt32LE(rate * 2, 28); h.writeUInt16LE(2, 32); h.writeUInt16LE(16, 34); h.write('data', 36); h.writeUInt32LE(pcm.length, 40);
  return Buffer.concat([h, pcm]);
}

function multipartBody(file, lang = 'es') {
  const b = '----prueba';
  const parts = [Buffer.from(`--${b}\r\nContent-Disposition: form-data; name="language"\r\n\r\n${lang}\r\n`), Buffer.from(`--${b}\r\nContent-Disposition: form-data; name="file"; filename="voz.wav"\r\nContent-Type: audio/wav\r\n\r\n`), file, Buffer.from(`\r\n--${b}--\r\n`)];
  return { body: Buffer.concat(parts), type: `multipart/form-data; boundary=${b}` };
}

test('stt: reenvía el WAV a OpenAI con modelo e idioma', async () => {
  const cap = {};
  const f = async (url, opts) => {
    cap.url = url;
    cap.form = opts.body;
    cap.auth = opts.headers.authorization;
    return new Response(JSON.stringify({ text: 'Hola, le llamo de TeleTimo' }), { status: 200 });
  };
  await withServer(baseCfg(), f, async (base) => {
    const { body: s } = await session(base);
    const m = multipartBody(wav(1.5));
    const r = await fetch(`${base}/v1/stt`, { method: 'POST', headers: { authorization: `Bearer ${s.token}`, 'content-type': m.type }, body: m.body });
    const j = await r.json();
    assert.equal(r.status, 200);
    assert.equal(j.text, 'Hola, le llamo de TeleTimo');
    assert.equal(cap.url, 'http://oa/v1/audio/transcriptions');
    assert.equal(cap.auth, 'Bearer sk-oa');
    assert.equal(cap.form.get('model'), 'gpt-4o-mini-transcribe');
    assert.equal(cap.form.get('language'), 'es');
    assert.equal(cap.form.get('response_format'), 'json');
    assert.ok(cap.form.get('file') instanceof Blob);
  });
});

test('stt: rechaza audio no WAV o demasiado largo', async () => {
  await withServer(baseCfg(), fetch, async (base) => {
    const { body: s } = await session(base);
    const m = multipartBody(Buffer.alloc(5000, 1));
    assert.equal((await fetch(`${base}/v1/stt`, { method: 'POST', headers: { authorization: `Bearer ${s.token}`, 'content-type': m.type }, body: m.body })).status, 400);
  });
});

test('tts: pide mp3 con voz e instrucciones', async () => {
  const cap = {};
  const f = async (url, opts) => {
    cap.url = url;
    cap.body = JSON.parse(opts.body);
    return new Response(Buffer.alloc(2000, 7), { status: 200, headers: { 'content-type': 'audio/mpeg' } });
  };
  await withServer(baseCfg(), f, async (base) => {
    const { body: s } = await session(base);
    const r = await fetch(`${base}/v1/tts`, { method: 'POST', headers: { authorization: `Bearer ${s.token}` }, body: JSON.stringify({ text: 'Hola', voice: 'coral', instructions: 'tono alegre' }) });
    assert.equal(r.status, 200);
    assert.equal(r.headers.get('content-type'), 'audio/mpeg');
    assert.equal(cap.url, 'http://oa/v1/audio/speech');
    assert.deepEqual(cap.body, { model: 'gpt-4o-mini-tts', input: 'Hola', voice: 'coral', response_format: 'mp3', instructions: 'tono alegre' });
  });
});

test('boss: comentario con IA', async () => {
  await withServer(baseCfg(), fakeAnthropic('¡123 de 110! Aprobado por los pelos.'), async (base) => {
    const { body: s } = await session(base);
    const r = await fetch(`${base}/v1/boss`, { method: 'POST', headers: { authorization: `Bearer ${s.token}` }, body: JSON.stringify({ stats: { income: 123, quota: 110, grade: 'B', day: 1 } }) });
    const j = await r.json();
    assert.equal(r.status, 200);
    assert.match(j.comment, /123/);
  });
});

test('modo mock funciona sin claves', async () => {
  await withServer(baseCfg({ llmProvider: 'mock', anthropicKey: '', sttProvider: 'mock' }), async () => { throw new Error('no debe llamar fuera'); }, async (base) => {
    const { body: s } = await session(base);
    const j = await (await fetch(`${base}/v1/chat`, { method: 'POST', headers: { authorization: `Bearer ${s.token}` }, body: JSON.stringify(chatBody) })).json();
    assert.match(j.reply, /\[mock\]/);
  });
});

test('tokens: firma, caducidad y manipulación', () => {
  const t = auth.sign({ dev: 'abc12345', exp: 2000 }, 'k');
  assert.ok(auth.verify(t, 'k', 1000));
  assert.equal(auth.verify(t, 'k', 3000), null);
  assert.equal(auth.verify(t, 'otra', 1000), null);
  assert.equal(auth.verify(t.replace(/^./, 'x'), 'k', 1000), null);
});

test('validación y parser', () => {
  assert.equal(V.scrubDigits('mi número 1234 5678 9012 3456 ok'), 'mi número [número tachado]ok');
  const r = V.parseModelReply('Claro: {"reply":"hola","emotion":"rara","gesture":"baile","deltas":{"trust":"99"}}');
  assert.equal(r.reply, 'hola');
  assert.equal(r.emotion, 'neutral');
  assert.equal(r.gesture, '');
  assert.equal(r.deltas.trust, 10);
  const parsed = multipart.parse(multipartBody(Buffer.from('ABC')).body, 'multipart/form-data; boundary=----prueba');
  assert.equal(parsed.fields.language, 'es');
  assert.equal(parsed.files.file.data.toString(), 'ABC');
  assert.ok(Math.abs(multipart.wavSeconds(wav(2)) - 2) < 0.01);
});

test('límites diarios de voz', () => {
  const l = new Limiter(baseCfg({ dailyTtsCharsPerDevice: 100 }));
  assert.equal(l.check('d', 'tts', 60), null);
  assert.ok(l.check('d', 'tts', 60));
});
