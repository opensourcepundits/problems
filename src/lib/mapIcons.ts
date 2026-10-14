// Lantern markers rasterised from Lucide icon nodes. One 64×64 image per category × status,
// added at pixelRatio 2 (32 css px base); MapLibre's icon-size scales them by severity.
import type { Map } from 'maplibre-gl';
import {
	CarFront,
	Check,
	CircleDot,
	Construction,
	Flame,
	HeartPulse,
	Siren,
	Store,
	X,
	type IconNode
} from 'lucide';
import type { Category, Status } from '$lib/types';
import { CATEGORY_META, MAP } from '$lib/tokens';

const SIZE = 64;
const RADIUS = 26;

export const GLYPH: Record<Category, IconNode> = {
	fire: Flame,
	looting: Store,
	casualty: HeartPulse,
	accident: CarFront,
	roadblock: Construction,
	sos: Siren,
	other: CircleDot
};

type Ring = 'dashed' | 'solid' | 'muted';

function drawNode(
	ctx: CanvasRenderingContext2D,
	node: IconNode,
	cx: number,
	cy: number,
	size: number,
	stroke: string,
	width: number
) {
	const k = size / 24;
	ctx.save();
	ctx.translate(cx - size / 2, cy - size / 2);
	ctx.scale(k, k);
	ctx.strokeStyle = stroke;
	ctx.lineWidth = width / k;
	ctx.lineCap = 'round';
	ctx.lineJoin = 'round';
	for (const [tag, raw] of node) {
		const a = raw as Record<string, string | number | undefined>;
		ctx.beginPath();
		if (tag === 'path') ctx.stroke(new Path2D(String(a.d)));
		else if (tag === 'circle') {
			ctx.arc(+a.cx!, +a.cy!, +a.r!, 0, Math.PI * 2);
			ctx.stroke();
		} else if (tag === 'rect') {
			ctx.roundRect(+a.x!, +a.y!, +a.width!, +a.height!, +(a.rx ?? 0));
			ctx.stroke();
		} else if (tag === 'line') {
			ctx.moveTo(+a.x1!, +a.y1!);
			ctx.lineTo(+a.x2!, +a.y2!);
			ctx.stroke();
		} else if (tag === 'polyline' || tag === 'polygon') {
			const pts = String(a.points).trim().split(/[\s,]+/).map(Number);
			ctx.moveTo(pts[0], pts[1]);
			for (let i = 2; i < pts.length; i += 2) ctx.lineTo(pts[i], pts[i + 1]);
			if (tag === 'polygon') ctx.closePath();
			ctx.stroke();
		}
	}
	ctx.restore();
}

function badge(ctx: CanvasRenderingContext2D, fill: string, icon: IconNode) {
	ctx.beginPath();
	ctx.arc(50, 50, 10, 0, Math.PI * 2);
	ctx.fillStyle = fill;
	ctx.fill();
	ctx.lineWidth = 3;
	ctx.strokeStyle = '#0e1116';
	ctx.stroke();
	drawNode(ctx, icon, 50, 50, 12, MAP.glyph, 3.5);
}

function canvas(size = SIZE) {
	const element = document.createElement('canvas');
	element.width = size;
	element.height = size;
	const ctx = element.getContext('2d');
	if (!ctx) throw new Error('Could not draw a map icon.');
	return ctx;
}

export function markerImage(category: Category, ring: Ring, status: Status): ImageData {
	const ctx = canvas();
	const sos = category === 'sos';
	// Drop shadow separates the disc from the basemap.
	ctx.shadowColor = 'rgba(0,0,0,.55)';
	ctx.shadowBlur = 6;
	ctx.shadowOffsetY = 2;
	ctx.beginPath();
	ctx.arc(32, 32, RADIUS, 0, Math.PI * 2);
	ctx.fillStyle = sos ? MAP.sos : status === 'resolved' ? MAP.resolvedFill : CATEGORY_META[category].color;
	ctx.fill();
	ctx.shadowColor = 'transparent';
	// Status ring: dashed = unverified, solid = verified, muted = resolved/debunked.
	ctx.lineWidth = sos ? 5 : 3.5;
	ctx.strokeStyle = ring === 'muted' ? 'rgba(255,255,255,.4)' : MAP.ring;
	ctx.setLineDash(ring === 'dashed' && !sos ? [6, 4.5] : []);
	ctx.stroke();
	ctx.setLineDash([]);
	const glyph = sos ? '#ffffff' : status === 'resolved' ? '#eef1f5' : MAP.glyph;
	drawNode(ctx, GLYPH[category], 32, 32, 28, glyph, 2.75);
	if (!sos && status === 'verified') badge(ctx, MAP.verifiedBadge, Check);
	if (status === 'resolved') badge(ctx, '#b1b9c5', Check);
	if (status === 'debunked') badge(ctx, '#8c96a5', X);
	return ctx.getImageData(0, 0, SIZE, SIZE);
}

/** Beacon disc (28 css px) with a white ring, a short stem and a ground shadow. Anchor at the bottom. */
function draftImage(): ImageData {
	const ctx = canvas(SIZE * 2);
	ctx.scale(2, 2);
	ctx.beginPath();
	ctx.ellipse(32, 60, 8, 3, 0, 0, Math.PI * 2);
	ctx.fillStyle = 'rgba(0,0,0,.45)';
	ctx.fill();
	ctx.fillStyle = '#ffffff';
	ctx.fillRect(30.5, 34, 3, 26);
	ctx.beginPath();
	ctx.arc(32, 22, 14, 0, Math.PI * 2);
	ctx.fillStyle = MAP.draft;
	ctx.fill();
	ctx.lineWidth = 3;
	ctx.strokeStyle = '#ffffff';
	ctx.stroke();
	ctx.beginPath();
	ctx.arc(32, 22, 4, 0, Math.PI * 2);
	ctx.fillStyle = '#ffffff';
	ctx.fill();
	return ctx.getImageData(0, 0, SIZE * 2, SIZE * 2);
}

export const DRAFT_ICON = 'm-draft';

export const iconId = (category: string, status: string) => `m-${category}-${status}`;

export function addIncidentIcons(map: Map) {
	const statuses = [
		['unverified', 'dashed'],
		['verified', 'solid'],
		['resolved', 'muted'],
		['debunked', 'muted']
	] as const;
	for (const category of Object.keys(GLYPH) as Category[]) {
		for (const [status, ring] of statuses) {
			const id = iconId(category, status);
			if (!map.hasImage(id)) map.addImage(id, markerImage(category, ring, status), { pixelRatio: 2 });
		}
	}
	if (!map.hasImage(DRAFT_ICON)) map.addImage(DRAFT_ICON, draftImage(), { pixelRatio: 2 });
}

/** Inline SVG markup for a Lucide node, for popups built as HTML strings. */
export function iconSvg(node: IconNode, size = 16, strokeWidth = 2): string {
	const children = node
		.map(([tag, attrs]) => {
			const body = Object.entries(attrs)
				.filter(([key]) => key !== 'key')
				.map(([key, value]) => `${key}="${String(value)}"`)
				.join(' ');
			return `<${tag} ${body}/>`;
		})
		.join('');
	return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="${strokeWidth}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" style="display:block">${children}</svg>`;
}
