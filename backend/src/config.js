'use strict';
// Configuración leída de variables de entorno. Ningún secreto vive en el APK.

const crypto = require('node:crypto');

function int(name, def) {
  const v = parseInt(process.env[name] ?? '', 10);
  return Number.isFinite(v) ? v : def;
}

function str(name, def = '') {
  const v = process.env[name];
  return v === undefined || v === '' ? def : v;
}

function load() {
  const cfg = {
    port: int('PORT', 8787),
    host: str('HOST', '0.0.0.0'),
    accessCode: str('APP_ACCESS_CODE'),
    tokenSecret: str('TOKEN_SECRET') || crypto.randomBytes(32).toString('hex'),
    tokenTtlSec: int('TOKEN_TTL_SEC', 6 * 3600),

    llmProvider: str('LLM_PROVIDER', 'anthropic'), // anthropic | mock
    anthropicKey: str('ANTHROPIC_API_KEY'),
    anthropicModel: str('ANTHROPIC_MODEL', 'claude-haiku-5-5'),
    anthropicBaseUrl: str('ANTHROPIC_BASE_URL', 'https://api.anthropic.com'),
    maxReplyTokens: int('MAX_REPLY_TOKENS', 400),

    sttProvider: str('STT_PROVIDER', 'openai'), // openai | none | mock
    ttsProvider: str('TTS_PROVIDER', 'openai'), // openai | none | mock
    openaiKey: str('OPENAI_API_KEY'),
    openaiBaseUrl: str('OPENAI_BASE_URL', 'https://api.openai.com/v1'),
    openaiSttModel: str('OPENAI_STT_MODEL', 'gpt-4o-mini-transcribe'),
    openaiTtsModel: str('OPENAI_TTS_MODEL', 'gpt-4o-mini-tts'),

    upstreamTimeoutMs: int('UPSTREAM_TIMEOUT_MS', 12000),
    ratePerMinute: int('RATE_LIMIT_PER_MIN', 40),
    dailyPerDevice: int('DAILY_REQUESTS_PER_DEVICE', 800),
    dailyTtsCharsPerDevice: int('DAILY_TTS_CHARS_PER_DEVICE', 40000),
    dailySttSecondsPerDevice: int('DAILY_STT_SECONDS_PER_DEVICE', 1800),
    maxJsonBytes: int('MAX_JSON_BYTES', 32 * 1024),
    maxAudioBytes: int('MAX_AUDIO_BYTES', 1024 * 1024),
    logRequests: str('LOG_REQUESTS', '1') === '1',
  };
  cfg.tokenSecretGenerated = !process.env.TOKEN_SECRET;
  return cfg;
}

function status(cfg) {
  const llm = cfg.llmProvider === 'mock' ? 'mock' : (cfg.anthropicKey ? `anthropic:${cfg.anthropicModel}` : 'sin configurar');
  const stt = cfg.sttProvider === 'none' ? 'desactivado' : cfg.sttProvider === 'mock' ? 'mock' : (cfg.openaiKey ? `openai:${cfg.openaiSttModel}` : 'sin configurar');
  const tts = cfg.ttsProvider === 'none' ? 'desactivado' : cfg.ttsProvider === 'mock' ? 'mock' : (cfg.openaiKey ? `openai:${cfg.openaiTtsModel}` : 'sin configurar');
  return { llm, stt, tts };
}

module.exports = { load, status };
