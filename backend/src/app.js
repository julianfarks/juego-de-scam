'use strict';
// Servidor HTTP sin dependencias externas (Node.js ≥ 20).
// Endpoints:
//   GET  /health        estado y proveedores configurados (sin secretos)
//   POST /v1/session    {device_id, access_code} → {token, expires_in}
//   POST /v1/chat       turno de conversación del cliente virtual
//   POST /v1/stt        multipart (file=voz.wav, language) → {text}
//   POST /v1/tts        {text, voice, instructions} → audio/mpeg
//   POST /v1/boss       {stats} → {comment}
//   GET  /v1/usage      consumo del dispositivo hoy

const http = require('node:http');
const crypto = require('node:crypto');
const config = require('./config');
const auth = require('./auth');
const { Limiter } = require('./limits');
const V = require('./validate');
const prompts = require('./prompts');
const anthropic = require('./providers/anthropic');
const openai = require('./providers/openai');
const mock = require('./providers/mock');
const multipart = require('./multipart');

const VERSION = '0.1.0';

function createApp(cfg = config.load(), deps = {}) {
  const fetchImpl = deps.fetch || fetch;
  const limiter = deps.limiter || new Limiter(cfg);
  const log = deps.log || ((...a) => console.log(new Date().toISOString(), ...a));

  function send(res, status, obj, headers = {}) {
    const body = Buffer.from(JSON.stringify(obj));
    res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'content-length': body.length, 'cache-control': 'no-store', ...headers });
    res.end(body);
  }

  function readBody(req, limit) {
    return new Promise((resolve, reject) => {
      const chunks = [];
      let size = 0;
      req.on('data', (c) => {
        size += c.length;
        if (size > limit) {
          reject(Object.assign(new Error('Cuerpo demasiado grande'), { status: 413 }));
          req.destroy();
          return;
        }
        chunks.push(c);
      });
      req.on('end', () => resolve(Buffer.concat(chunks)));
      req.on('error', reject);
    });
  }

  async function readJson(req) {
    const buf = await readBody(req, cfg.maxJsonBytes);
    try {
      return JSON.parse(buf.toString('utf8') || '{}');
    } catch {
      throw new V.BadRequest('JSON inválido');
    }
  }

  function requireAuth(req) {
    const h = req.headers.authorization || '';
    const tok = h.startsWith('Bearer ') ? h.slice(7) : '';
    const p = auth.verify(tok, cfg.tokenSecret);
    if (!p) throw Object.assign(new Error('No autorizado'), { status: 401 });
    return p.dev;
  }

  function limit(dev, kind, amount = 0) {
    const why = limiter.check(dev, kind, amount);
    if (why) throw Object.assign(new Error(why), { status: 429 });
  }

  async function llm(system, user, maxTokens, signal) {
    if (cfg.llmProvider === 'mock') return null;
    return anthropic.callMessages(cfg, { system, user, maxTokens }, fetchImpl, signal);
  }

  const routes = {
    'GET /health': async (req, res) => {
      send(res, 200, { ok: true, version: VERSION, ...config.status(cfg), auth: cfg.accessCode ? 'código requerido' : 'sin código (no recomendado)' });
    },

    'POST /v1/session': async (req, res) => {
      const body = await readJson(req);
      const dev = String(body.device_id || '').replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 64);
      if (dev.length < 8) throw new V.BadRequest('device_id inválido');
      if (cfg.accessCode && !auth.safeEqual(String(body.access_code || ''), cfg.accessCode)) {
        throw Object.assign(new Error('Código de acceso incorrecto'), { status: 401 });
      }
      limit(dev, 'session');
      send(res, 200, auth.issue(dev, cfg));
    },

    'POST /v1/chat': async (req, res, ctx) => {
      const dev = requireAuth(req);
      const body = V.chatRequest(await readJson(req));
      limit(dev, 'chat');
      const key = crypto.createHash('sha256').update(dev + JSON.stringify(body)).digest('hex');
      const out = await limiter.dedupeRun(key, async () => {
        const r = cfg.llmProvider === 'mock' ? mock.chat(body) : await llm(prompts.clientSystem(body), prompts.clientUser(body), cfg.maxReplyTokens, ctx.signal);
        return { ...V.parseModelReply(r.text), usage: r.usage, provider: cfg.llmProvider };
      });
      send(res, 200, out);
    },

    'POST /v1/boss': async (req, res, ctx) => {
      const dev = requireAuth(req);
      const body = V.bossRequest(await readJson(req));
      limit(dev, 'boss');
      const r = cfg.llmProvider === 'mock' ? mock.boss(body.stats) : await llm(prompts.bossSystem(body.language), prompts.bossUser(body.stats), 300, ctx.signal);
      const comment = V.scrubDigits(r.text).replace(/\s+/g, ' ').trim().slice(0, 600);
      send(res, 200, { comment, usage: r.usage });
    },

    'POST /v1/stt': async (req, res) => {
      const dev = requireAuth(req);
      if (cfg.sttProvider === 'none') throw Object.assign(new Error('Transcripción desactivada en el servidor'), { status: 503 });
      const buf = await readBody(req, cfg.maxAudioBytes + 4096);
      let parsed;
      try {
        parsed = multipart.parse(buf, req.headers['content-type']);
      } catch (e) {
        throw new V.BadRequest('Formulario de audio inválido: ' + e.message);
      }
      const file = parsed.files.file;
      if (!file || file.data.length < 1000) throw new V.BadRequest('Falta el audio o es demasiado corto');
      const secs = multipart.wavSeconds(file.data);
      if (secs < 0) throw new V.BadRequest('El audio debe ser WAV PCM');
      if (secs > 30) throw new V.BadRequest('Audio demasiado largo (máx. 30 s)');
      limit(dev, 'stt', Math.ceil(secs));
      const lang = ['es', 'en'].includes(parsed.fields.language) ? parsed.fields.language : 'es';
      const r = cfg.sttProvider === 'mock' ? mock.transcribe() : await openai.transcribe(cfg, file.data, lang, fetchImpl);
      send(res, 200, { text: V.scrubDigits(r.text).slice(0, 600), seconds: Math.round(secs * 10) / 10 });
    },

    'POST /v1/tts': async (req, res) => {
      const dev = requireAuth(req);
      if (cfg.ttsProvider === 'none' || cfg.ttsProvider === 'mock') throw Object.assign(new Error('Voz remota desactivada en el servidor'), { status: 503 });
      const body = V.ttsRequest(await readJson(req));
      limit(dev, 'tts', body.text.length);
      const r = await openai.speak(cfg, body, fetchImpl);
      res.writeHead(200, { 'content-type': r.contentType, 'content-length': r.audio.length, 'cache-control': 'no-store' });
      res.end(r.audio);
    },

    'GET /v1/usage': async (req, res) => {
      const dev = requireAuth(req);
      send(res, 200, limiter.usage(dev));
    },
  };

  async function handler(req, res) {
    const started = Date.now();
    const url = new URL(req.url, 'http://x');
    const key = `${req.method} ${url.pathname}`;
    const route = routes[key];
    const ac = new AbortController();
    res.on('close', () => {
      if (!res.writableEnded) ac.abort(); // el cliente canceló: se aborta la llamada al proveedor
    });
    let status = 200;
    try {
      if (!route) {
        status = 404;
        send(res, 404, { error: 'No encontrado' });
        return;
      }
      await route(req, res, { signal: ac.signal });
      status = res.statusCode;
    } catch (e) {
      status = e.status || 500;
      if (!e.status) log('ERROR', key, e.stack || e.message);
      else if (status >= 500) log('AVISO', key, e.message);
      if (!res.headersSent) send(res, status, { error: status === 500 ? 'Error interno' : e.message });
    } finally {
      if (cfg.logRequests) log(key, status, `${Date.now() - started}ms`);
    }
  }

  return { handler, limiter, cfg };
}

function start() {
  const cfg = config.load();
  const app = createApp(cfg);
  const server = http.createServer(app.handler);
  server.requestTimeout = 45000;
  server.headersTimeout = 15000;
  server.listen(cfg.port, cfg.host, () => {
    const st = config.status(cfg);
    console.log(`TeleTimo backend ${VERSION} en http://${cfg.host}:${cfg.port}  LLM=${st.llm} STT=${st.stt} TTS=${st.tts}`);
    if (!cfg.accessCode) console.warn('AVISO: APP_ACCESS_CODE vacío: cualquiera con la URL podrá usar (y gastar) tu IA.');
    if (cfg.tokenSecretGenerated) console.warn('AVISO: TOKEN_SECRET no definido; se generó uno temporal (las sesiones caducan al reiniciar).');
  });
  return server;
}

module.exports = { createApp, start, VERSION };
