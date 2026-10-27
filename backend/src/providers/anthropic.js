'use strict';
// Proveedor LLM: Claude Messages API (POST /v1/messages).
// Documentación: https://docs.claude.com/en/api/messages
// Cabeceras: x-api-key, anthropic-version: 2023-06-01. Respuesta: content[] con
// bloques {type: "text", text}. Se ignoran otros tipos de bloque (p. ej. thinking).

class UpstreamError extends Error {
  constructor(msg, status = 502) {
    super(msg);
    this.status = status;
  }
}

async function callMessages(cfg, { system, user, maxTokens }, fetchImpl = fetch, signal) {
  if (!cfg.anthropicKey) throw new UpstreamError('ANTHROPIC_API_KEY no configurada', 503);
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), cfg.upstreamTimeoutMs);
  if (signal) signal.addEventListener('abort', () => ctrl.abort(), { once: true });
  let res;
  try {
    res = await fetchImpl(`${cfg.anthropicBaseUrl}/v1/messages`, {
      method: 'POST',
      headers: {
        'x-api-key': cfg.anthropicKey,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        model: cfg.anthropicModel,
        max_tokens: maxTokens,
        system,
        messages: [{ role: 'user', content: user }],
      }),
      signal: ctrl.signal,
    });
  } catch (e) {
    throw new UpstreamError(e.name === 'AbortError' ? 'Tiempo de espera del LLM agotado' : 'No se pudo contactar con el LLM', 504);
  } finally {
    clearTimeout(timer);
  }
  const txt = await res.text();
  if (!res.ok) {
    throw new UpstreamError(`LLM respondió ${res.status}`, res.status === 429 ? 429 : 502);
  }
  let data;
  try {
    data = JSON.parse(txt);
  } catch {
    throw new UpstreamError('Respuesta del LLM ilegible');
  }
  const text = (Array.isArray(data.content) ? data.content : [])
    .filter((b) => b && b.type === 'text' && typeof b.text === 'string')
    .map((b) => b.text)
    .join('\n')
    .trim();
  if (!text) throw new UpstreamError('El LLM no devolvió texto');
  const usage = data.usage || {};
  return { text, usage: { input_tokens: usage.input_tokens || 0, output_tokens: usage.output_tokens || 0 } };
}

module.exports = { callMessages, UpstreamError };
