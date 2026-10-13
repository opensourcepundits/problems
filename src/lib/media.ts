import imageCompression from 'browser-image-compression';

const MAX_BYTES = 25 * 1024 * 1024;

function renamed(name: string, extension: string) {
	const base = name.replace(/\.[^.]+$/, '').replace(/[^\w.-]+/g, '-').slice(0, 60) || 'evidence';
	return `${base}.${extension}`;
}

async function canvasJpeg(file: File): Promise<File> {
	const bitmap = await createImageBitmap(file);
	const maxEdge = 1600;
	const scale = Math.min(1, maxEdge / Math.max(bitmap.width, bitmap.height));
	const canvas = document.createElement('canvas');
	canvas.width = Math.max(1, Math.round(bitmap.width * scale));
	canvas.height = Math.max(1, Math.round(bitmap.height * scale));
	const context = canvas.getContext('2d');
	if (!context) {
		bitmap.close();
		throw new Error('This browser could not re-encode the photo.');
	}
	context.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
	bitmap.close();
	const blob = await new Promise<Blob>((resolve, reject) => {
		canvas.toBlob(
			(value) => (value ? resolve(value) : reject(new Error('Could not strip photo metadata.'))),
			'image/jpeg',
			0.82
		);
	});
	return new File([blob], renamed(file.name, 'jpg'), { type: 'image/jpeg', lastModified: Date.now() });
}

export async function prepareMedia(file: File): Promise<{ file: File; videoMayContainLocation: boolean }> {
	if (file.size > MAX_BYTES) {
		throw new Error('Each file must be 25MB or smaller.');
	}

	if (file.type.startsWith('image/')) {
		let stripped: File;
		try {
			stripped = await canvasJpeg(file);
		} catch {
			throw new Error('Use a JPEG, PNG, or WebP photo so location data can be removed before upload.');
		}
		const compressed = await imageCompression(stripped, {
			maxSizeMB: 1.2,
			maxWidthOrHeight: 1600,
			useWebWorker: true,
			preserveExif: false,
			fileType: 'image/jpeg'
		});
		return {
			file: new File([compressed], renamed(file.name, 'jpg'), {
				type: 'image/jpeg',
				lastModified: Date.now()
			}),
			videoMayContainLocation: false
		};
	}

	if (file.type === 'video/mp4' || file.type === 'video/webm' || file.type === 'video/quicktime') {
		const extension = file.type === 'video/webm' ? 'webm' : file.type === 'video/quicktime' ? 'mov' : 'mp4';
		return {
			file: new File([await file.arrayBuffer()], renamed(file.name, extension), {
				type: file.type,
				lastModified: Date.now()
			}),
			videoMayContainLocation: true
		};
	}

	throw new Error('Upload a photo or an MP4, WebM, or QuickTime video.');
}
