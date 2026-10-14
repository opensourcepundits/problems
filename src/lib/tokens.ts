// One source of truth for JS consumers (types.ts, mapIcons.ts, MapPinView.svelte). Values mirror app.css.
import type { Category, Severity, Status } from '$lib/types';

export function cssVar(name: string, fallback: string): string {
	if (typeof window === 'undefined') return fallback;
	const value = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
	return value || fallback;
}

export const CATEGORY_META: Record<Category, { label: string; icon: string; color: string }> = {
	fire: { label: 'Fire', icon: 'Flame', color: '#ff8a3d' },
	looting: { label: 'Looting', icon: 'Store', color: '#b48cff' },
	casualty: { label: 'Casualty', icon: 'HeartPulse', color: '#ff6fa8' },
	accident: { label: 'Accident', icon: 'CarFront', color: '#3fd0c9' },
	roadblock: { label: 'Roadblock', icon: 'Construction', color: '#f2c94c' },
	sos: { label: 'SOS', icon: 'Siren', color: '#dc2626' },
	other: { label: 'Other', icon: 'CircleDot', color: '#9aa4b2' }
};

export const CATEGORY_LABEL = Object.fromEntries(
	Object.entries(CATEGORY_META).map(([key, meta]) => [key, meta.label])
) as Record<Category, string>;

export const SEVERITY_META: Record<
	Severity,
	{ label: string; rank: 1 | 2 | 3 | 4; color: string; iconSize: number }
> = {
	// Marker images are 64px at pixelRatio 2 (32 css px base), so these give 26 / 30 / 34 / 38 px.
	low: { label: 'Low', rank: 1, color: '#7fb2d9', iconSize: 0.82 },
	medium: { label: 'Medium', rank: 2, color: '#f5b83d', iconSize: 0.94 },
	high: { label: 'High', rank: 3, color: '#ff7a3d', iconSize: 1.06 },
	critical: { label: 'Critical', rank: 4, color: '#ff4d4d', iconSize: 1.19 }
};

export const SEVERITY_COLOR = Object.fromEntries(
	Object.entries(SEVERITY_META).map(([key, meta]) => [key, meta.color])
) as Record<Severity, string>;

export const STATUS_META: Record<
	Status,
	{ label: string; icon: string; ring: 'dashed' | 'solid' | 'muted'; opacity: number }
> = {
	unverified: { label: 'Unverified', icon: 'CircleDashed', ring: 'dashed', opacity: 1 },
	verified: { label: 'Verified', icon: 'BadgeCheck', ring: 'solid', opacity: 1 },
	resolved: { label: 'Resolved', icon: 'CircleCheck', ring: 'muted', opacity: 0.85 },
	debunked: { label: 'Debunked', icon: 'Ban', ring: 'muted', opacity: 0.45 }
};

export const MAP = {
	glyph: '#07090c',
	ring: '#ffffff',
	sos: '#dc2626',
	sosHalo: 'rgba(255,77,77,.45)',
	criticalRing: '#ff4d4d',
	verifiedBadge: '#3ecf8e',
	resolvedFill: '#6b7585',
	draft: '#6aaeff',
	clusterFill: '#171d25',
	clusterText: '#eef1f5',
	heat: [
		[1, 'rgba(245,184,61,.20)'],
		[3, 'rgba(245,160,50,.32)'],
		[8, 'rgba(255,122,61,.44)'],
		[20, 'rgba(255,77,77,.54)'],
		[50, 'rgba(226,48,110,.64)']
	] as const,
	heatLine: 'rgba(255,184,120,.55)',
	heatLineEmpty: 'rgba(255,255,255,.05)',
	zoneHover: '#ffffff',
	zoneSelected: '#6aaeff'
};
