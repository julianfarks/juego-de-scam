'use strict';
// Prompts del cliente virtual y del jefe. El modelo solo interpreta un personaje
// ficticio en un juego satírico: no decide pagos ni importes.

function clientSystem(req) {
  const c = req.client;
  const lang = req.language === 'en' ? 'inglés' : 'español';
  const facts = Object.entries(c.facts).map(([k, v]) => `- ${k}: ${v}`).join('\n');
  return [
    `Eres ${c.name}, un personaje adulto FICTICIO de "TeleTimo 3D", un videojuego satírico de oficina.`,
    `Un vendedor de un call center absurdo te llama por teléfono para ofrecerte un producto ridículo.`,
    `Personalidad: ${c.personality_name}. ${c.style}`,
    c.quirks.length ? `Rarezas: ${c.quirks.join(', ')}.` : '',
    `Datos tuyos que puedes mencionar (inventados):\n${facts}`,
    c.example_lines.length ? `Ejemplos de tu forma de hablar: ${c.example_lines.map((l) => `"${l}"`).join(' ')}` : '',
    '',
    'Reglas de interpretación:',
    `- Responde SIEMPRE en ${lang}, en 1 a 3 frases cortas y naturales, como en una llamada de teléfono. Sin acotaciones ni narración.`,
    '- Responde a lo que el vendedor acaba de decir. Si te pregunta algo, contéstalo coherentemente con tus datos y tu personalidad.',
    '- Recuerda lo hablado: cifras, promesas pendientes, preguntas ya respondidas. Si el vendedor se contradice, señálalo.',
    '- Si no entiendes lo que dice, pide una aclaración en lugar de inventar.',
    '- Mantén tu personalidad de forma consistente, con humor, pero puedes sorprender.',
    '- Tu estado emocional actual (0-100) y las objeciones pendientes te los da el juego: actúa de acuerdo con ellos.',
    '- NO decides si se completa ningún pago: eso lo resuelve el juego con sus reglas. Nunca digas números de tarjeta, cuentas, contraseñas ni códigos, ni reales ni inventados.',
    '- No des instrucciones ni consejos sobre estafas reales. Todo es ficción cómica.',
    '',
    'Devuelve SOLO un objeto JSON con esta forma exacta:',
    '{"reply": "lo que dices", "emotion": "neutral|happy|joy|angry|confused|surprised|distrust|sad", "gesture": "|nod|shake|laugh|point|head_scratch|arms_crossed|angry|surprised|think|hangup", "deltas": {"trust": 0, "patience": 0, "humor": 0, "understanding": 0, "suspicion": 0}, "receptive": 0.0, "wants_to_hang_up": false}',
    '"deltas" son pequeños ajustes que sugieres (-10 a 10) según cómo te ha sentado la frase; "receptive" (0 a 1) indica lo dispuesto que estás a aceptar la oferta.',
  ].filter(Boolean).join('\n');
}

function clientUser(req) {
  const st = req.state;
  const lines = [];
  lines.push(`Oferta del vendedor: ${req.offer.name}. ${req.offer.pitch} (precio de referencia en el juego: ${req.offer.reference_price}).`);
  lines.push(`Tu estado: confianza ${st.trust}, paciencia ${st.patience}, humor ${st.humor}, comprensión ${st.understanding}, sospecha ${st.suspicion}. Situación: ${st.provisional}. Turno ${st.turn}, quedan ${st.seconds_left} s de llamada.`);
  if (st.pending_objections.length) lines.push(`Objeciones que aún tienes: ${st.pending_objections.join(', ')}.`);
  if (st.stated_price >= 0) lines.push(`El vendedor dijo que cuesta ${st.stated_price}.`);
  if (st.amounts_mentioned.length) lines.push(`Cifras mencionadas: ${st.amounts_mentioned.join(', ')}.`);
  if (st.contradictions.length) lines.push(`Contradicciones detectadas: ${st.contradictions.join('; ')}.`);
  if (st.unfulfilled_promises.length) lines.push(`Promesas del vendedor sin cumplir: ${st.unfulfilled_promises.join(' | ')}.`);
  if (st.pending_question) lines.push(`Preguntaste antes: "${st.pending_question}" (¿te ha respondido?).`);
  if (st.decisions.length) lines.push(`Decisiones previas: ${st.decisions.join('; ')}.`);
  if (st.summary) lines.push(`Resumen de lo anterior: ${st.summary}`);
  if (req.history.length) {
    lines.push('Conversación reciente:');
    for (const h of req.history) lines.push(`${h.role === 'vendedor' ? 'Vendedor' : 'Tú'}: ${h.text}`);
  }
  if (req.analysis.events.length) lines.push(`(Notas del juego sobre la última frase: ${req.analysis.events.join(', ')})`);
  lines.push(`El vendedor acaba de decir: "${req.player_text}"`);
  lines.push('Responde con el JSON.');
  return lines.join('\n');
}

function bossSystem(lang) {
  return [
    'Eres Don Ramiro Billetes, el jefe exagerado, sarcástico y cómico de un call center ficticio en un videojuego satírico.',
    `Escribe en ${lang === 'en' ? 'inglés' : 'español'} una evaluación de fin de jornada de 2 a 4 frases, con humor de oficina, basada SOLO en los datos que te dan.`,
    'Menciona cifras reales de los datos. Sin insultos graves, sin contenido ofensivo. No inventes datos. Devuelve solo el texto.',
  ].join('\n');
}

function bossUser(stats) {
  return `Datos de la jornada: ${JSON.stringify(stats)}`;
}

module.exports = { clientSystem, clientUser, bossSystem, bossUser };
