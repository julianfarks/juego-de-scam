'use strict';
// Tokens de sesión firmados con HMAC (sin base de datos). El juego obtiene uno
// presentando el código de acceso que el dueño del servidor reparte.

const crypto = require('node:crypto');

function b64url(buf) {
  return Buffer.from(buf).toString('base64').replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
}

function fromB64url(s) {
  return Buffer.from(s.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
}

function safeEqual(a, b) {
  const ba = Buffer.from(String(a));
  const bb = Buffer.from(String(b));
  if (ba.length !== bb.length) {
    crypto.timingSafeEqual(ba, ba); // tiempo constante aproximado
    return false;
  }
  return crypto.timingSafeEqual(ba, bb);
}

function sign(payload, secret) {
  const body = b64url(JSON.stringify(payload));
  const mac = b64url(crypto.createHmac('sha256', secret).update(body).digest());
  return `${body}.${mac}`;
}

function verify(token, secret, nowSec = Math.floor(Date.now() / 1000)) {
  if (typeof token !== 'string' || token.length > 600 || !token.includes('.')) return null;
  const [body, mac] = token.split('.');
  const expected = b64url(crypto.createHmac('sha256', secret).update(body).digest());
  if (!safeEqual(mac, expected)) return null;
  try {
    const p = JSON.parse(fromB64url(body).toString('utf8'));
    if (typeof p.exp !== 'number' || p.exp < nowSec) return null;
    if (typeof p.dev !== 'string') return null;
    return p;
  } catch {
    return null;
  }
}

function issue(deviceId, cfg) {
  const now = Math.floor(Date.now() / 1000);
  return { token: sign({ dev: deviceId, iat: now, exp: now + cfg.tokenTtlSec }, cfg.tokenSecret), expires_in: cfg.tokenTtlSec };
}

module.exports = { sign, verify, issue, safeEqual };
