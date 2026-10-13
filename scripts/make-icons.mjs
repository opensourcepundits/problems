import fs from 'node:fs';
import zlib from 'node:zlib';

function crc32(buffer) {
	let crc = ~0;
	for (const byte of buffer) {
		crc ^= byte;
		for (let bit = 0; bit < 8; bit += 1) crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
	}
	return ~crc >>> 0;
}

function chunk(type, data) {
	const length = Buffer.alloc(4);
	length.writeUInt32BE(data.length);
	const body = Buffer.concat([Buffer.from(type), data]);
	const checksum = Buffer.alloc(4);
	checksum.writeUInt32BE(crc32(body));
	return Buffer.concat([length, body, checksum]);
}

function png(size) {
	const raw = Buffer.alloc((size * 4 + 1) * size);
	const cx = size / 2;
	const cy = size * 0.42;
	const pinRadius = size * 0.13;
	const left = size * 0.1;
	const right = size * 0.9;
	const top = size * 0.1;
	const bottom = size * 0.9;
	const corner = size * 0.18;
	const tailTop = cy + pinRadius * 0.35;
	const tailBottom = size * 0.76;

	for (let y = 0; y < size; y += 1) {
		const row = y * (size * 4 + 1);
		raw[row] = 0;
		for (let x = 0; x < size; x += 1) {
			const px = x + 0.5;
			const py = y + 0.5;
			let inside = px >= left && px <= right && py >= top && py <= bottom;
			const inCorner =
				(px < left + corner || px > right - corner) && (py < top + corner || py > bottom - corner);
			if (inside && inCorner) {
				const cornerX = px < left + corner ? left + corner : right - corner;
				const cornerY = py < top + corner ? top + corner : bottom - corner;
				const dx = px - cornerX;
				const dy = py - cornerY;
				inside = dx * dx + dy * dy <= corner * corner;
			}
			const index = row + 1 + x * 4;
			if (!inside) {
				raw[index + 3] = 0;
				continue;
			}
			raw[index] = 220;
			raw[index + 1] = 38;
			raw[index + 2] = 38;
			raw[index + 3] = 255;
			const dx = px - cx;
			const dy = py - cy;
			const onHead = dx * dx + dy * dy <= pinRadius * pinRadius;
			let onTail = false;
			if (py > tailTop && py < tailBottom) {
				const progress = (py - tailTop) / (tailBottom - tailTop);
				onTail = Math.abs(px - cx) < pinRadius * (1 - progress) * 0.9;
			}
			if (onHead || onTail) {
				raw[index] = 255;
				raw[index + 1] = 255;
				raw[index + 2] = 255;
			}
		}
	}

	const header = Buffer.alloc(13);
	header.writeUInt32BE(size, 0);
	header.writeUInt32BE(size, 4);
	header[8] = 8;
	header[9] = 6;
	return Buffer.concat([
		Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
		chunk('IHDR', header),
		chunk('IDAT', zlib.deflateSync(raw)),
		chunk('IEND', Buffer.alloc(0))
	]);
}

fs.writeFileSync('static/pwa-192.png', png(192));
fs.writeFileSync('static/pwa-512.png', png(512));
