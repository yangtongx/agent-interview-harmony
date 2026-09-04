export function pcm16LeToWav(pcm: Uint8Array, sampleRate: number): Uint8Array {
  const dataSize = pcm.length;
  const buffer = new ArrayBuffer(44 + dataSize);
  const view = new DataView(buffer);
  const out = new Uint8Array(buffer);
  writeAscii(out, 0, 'RIFF');
  view.setUint32(4, 36 + dataSize, true);
  writeAscii(out, 8, 'WAVE');
  writeAscii(out, 12, 'fmt ');
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, 1, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate * 2, true);
  view.setUint16(32, 2, true);
  view.setUint16(34, 16, true);
  writeAscii(out, 36, 'data');
  view.setUint32(40, dataSize, true);
  out.set(pcm, 44);
  return out;
}

function writeAscii(bytes: Uint8Array, offset: number, text: string): void {
  for (let i = 0; i < text.length; i++) {
    bytes[offset + i] = text.charCodeAt(i);
  }
}

export function concatBytes(chunks: Uint8Array[]): Uint8Array {
  let total = 0;
  for (let i = 0; i < chunks.length; i++) {
    total += chunks[i].length;
  }
  const out = new Uint8Array(total);
  let offset = 0;
  for (let i = 0; i < chunks.length; i++) {
    out.set(chunks[i], offset);
    offset += chunks[i].length;
  }
  return out;
}
