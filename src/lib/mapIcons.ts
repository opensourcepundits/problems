import type { Map } from 'maplibre-gl';
import type { Category } from '$lib/types';

const SIZE = 64;

export const CATEGORY_ICON: Record<Category, string> = {
	fire: 'incident-fire',
	looting: 'incident-looting',
	casualty: 'incident-casualty',
	accident: 'incident-accident',
	roadblock: 'incident-roadblock',
	sos: 'incident-sos',
	other: 'incident-other'
};

function canvasIcon(fill: string, draw: (ctx: CanvasRenderingContext2D) => void): ImageData {
	const canvas = document.createElement('canvas');
	canvas.width = SIZE;
	canvas.height = SIZE;
	const ctx = canvas.getContext('2d');
	if (!ctx) throw new Error('Could not draw a map icon.');
	ctx.clearRect(0, 0, SIZE, SIZE);
	ctx.beginPath();
	ctx.arc(32, 32, 28, 0, Math.PI * 2);
	ctx.fillStyle = fill;
	ctx.fill();
	ctx.lineWidth = 4;
	ctx.strokeStyle = '#ffffff';
	ctx.stroke();
	ctx.fillStyle = '#ffffff';
	ctx.strokeStyle = '#ffffff';
	ctx.lineWidth = 3.5;
	ctx.lineCap = 'round';
	ctx.lineJoin = 'round';
	draw(ctx);
	return ctx.getImageData(0, 0, SIZE, SIZE);
}

function flame(ctx: CanvasRenderingContext2D) {
	ctx.beginPath();
	ctx.moveTo(32, 14);
	ctx.bezierCurveTo(46, 28, 44, 40, 32, 50);
	ctx.bezierCurveTo(20, 40, 18, 28, 32, 14);
	ctx.fill();
	ctx.fillStyle = '#ffedd5';
	ctx.beginPath();
	ctx.moveTo(32, 28);
	ctx.bezierCurveTo(38, 36, 36, 42, 32, 46);
	ctx.bezierCurveTo(28, 42, 26, 36, 32, 28);
	ctx.fill();
}

function bag(ctx: CanvasRenderingContext2D) {
	ctx.beginPath();
	ctx.moveTo(24, 26);
	ctx.lineTo(22, 48);
	ctx.lineTo(42, 48);
	ctx.lineTo(40, 26);
	ctx.closePath();
	ctx.stroke();
	ctx.beginPath();
	ctx.arc(32, 26, 8, Math.PI, 0);
	ctx.stroke();
}

function cross(ctx: CanvasRenderingContext2D) {
	ctx.fillRect(28, 16, 8, 32);
	ctx.fillRect(16, 28, 32, 8);
}

function crash(ctx: CanvasRenderingContext2D) {
	ctx.beginPath();
	ctx.arc(24, 36, 9, 0, Math.PI * 2);
	ctx.fill();
	ctx.beginPath();
	ctx.arc(40, 28, 9, 0, Math.PI * 2);
	ctx.fill();
}

function barrier(ctx: CanvasRenderingContext2D) {
	ctx.fillRect(16, 18, 32, 7);
	ctx.fillRect(16, 29, 32, 7);
	ctx.fillRect(16, 40, 32, 7);
}

function alertMark(ctx: CanvasRenderingContext2D) {
	ctx.fillRect(29, 14, 6, 22);
	ctx.beginPath();
	ctx.arc(32, 46, 4, 0, Math.PI * 2);
	ctx.fill();
}

function dot(ctx: CanvasRenderingContext2D) {
	ctx.beginPath();
	ctx.arc(32, 32, 7, 0, Math.PI * 2);
	ctx.fill();
}

export function addIncidentIcons(map: Map) {
	const icons: Array<[string, string, (ctx: CanvasRenderingContext2D) => void]> = [
		['incident-fire', '#ea580c', flame],
		['incident-looting', '#7c3aed', bag],
		['incident-casualty', '#dc2626', cross],
		['incident-accident', '#d97706', crash],
		['incident-roadblock', '#ca8a04', barrier],
		['incident-sos', '#be123c', alertMark],
		['incident-other', '#334155', dot]
	];
	for (const [name, color, draw] of icons) {
		if (!map.hasImage(name)) map.addImage(name, canvasIcon(color, draw));
	}
}
