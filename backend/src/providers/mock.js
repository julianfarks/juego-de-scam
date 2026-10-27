'use strict';
// Proveedor de PRUEBA (LLM_PROVIDER=mock). No es inteligencia artificial: genera
// respuestas deterministas a partir de la petición para poder probar el flujo
// completo (juego ↔ servidor) sin claves ni coste. Nunca usarlo en producción.

function chat(req) {
  const p = req.player_text.toLowerCase();
  let reply = `[mock] ${req.client.name.split(' ')[0]} ha oído: "${req.player_text.slice(0, 60)}".`;
  let emotion = 'neutral';
  const deltas = { trust: 0, patience: -1, humor: 0, understanding: 0, suspicion: 0 };
  if (p.includes('garant')) {
    reply += ' Con garantía me quedo más tranquilo.';
    emotion = 'happy';
    deltas.trust = 4;
  } else if (p.includes('?')) {
    reply += ` Le respondo: vivo en ${req.client.facts.city || 'mi casa'}.`;
  }
  if (req.state.contradictions.length) reply += ' Por cierto, se ha contradicho con las cifras.';
  return {
    text: JSON.stringify({ reply, emotion, gesture: 'nod', deltas, receptive: 0.3, wants_to_hang_up: false }),
    usage: { input_tokens: 0, output_tokens: 0 },
  };
}

function boss(stats) {
  return { text: `[mock] Día ${stats.day}: ${stats.income} de ${stats.quota}. Nota ${stats.grade}. Sigue así… o no.`, usage: { input_tokens: 0, output_tokens: 0 } };
}

function transcribe() {
  return { text: 'Hola, le llamo de TeleTimo (transcripción de prueba)' };
}

// Un MP3 mínimo no es trivial de fabricar: el mock de TTS devuelve 503 para que el
// juego use la voz del sistema, igual que si el servicio no estuviera disponible.

module.exports = { chat, boss, transcribe };
