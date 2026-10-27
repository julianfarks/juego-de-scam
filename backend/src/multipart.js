'use strict';
// Analizador multipart/form-data mínimo (campos de texto y un archivo), suficiente
// para el audio que envía el juego. Rechaza cuerpos malformados.

function parse(buffer, contentType) {
  const m = /boundary=(?:"([^"]+)"|([^;]+))/i.exec(contentType || '');
  if (!m) throw new Error('Falta boundary');
  const boundary = Buffer.from('--' + (m[1] || m[2]).trim());
  const fields = {};
  const files = {};
  let pos = buffer.indexOf(boundary);
  if (pos < 0) throw new Error('Boundary no encontrado');
  while (true) {
    pos += boundary.length;
    if (buffer.slice(pos, pos + 2).toString() === '--') break;
    if (buffer.slice(pos, pos + 2).toString() === '\r\n') pos += 2;
    const headerEnd = buffer.indexOf('\r\n\r\n', pos);
    if (headerEnd < 0) throw new Error('Cabecera de parte incompleta');
    const headers = buffer.slice(pos, headerEnd).toString('utf8');
    const next = buffer.indexOf(boundary, headerEnd + 4);
    if (next < 0) throw new Error('Parte sin cierre');
    let dataEnd = next;
    if (buffer[dataEnd - 2] === 13 && buffer[dataEnd - 1] === 10) dataEnd -= 2;
    const data = buffer.slice(headerEnd + 4, dataEnd);
    const name = /name="([^"]*)"/i.exec(headers);
    const filename = /filename="([^"]*)"/i.exec(headers);
    const ctype = /content-type:\s*([^\r\n]+)/i.exec(headers);
    if (name) {
      if (filename) files[name[1]] = { filename: filename[1], contentType: ctype ? ctype[1].trim() : 'application/octet-stream', data };
      else fields[name[1]] = data.toString('utf8').slice(0, 200);
    }
    pos = next;
  }
  return { fields, files };
}

// Duración aproximada de un WAV PCM (para límites de uso).
function wavSeconds(buf) {
  if (buf.length < 44 || buf.slice(0, 4).toString() !== 'RIFF' || buf.slice(8, 12).toString() !== 'WAVE') return -1;
  const byteRate = buf.readUInt32LE(28);
  if (!byteRate) return -1;
  return (buf.length - 44) / byteRate;
}

module.exports = { parse, wavSeconds };
