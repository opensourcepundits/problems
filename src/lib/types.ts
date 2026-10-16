export const CATEGORIES = [
	'fire',
	'looting',
	'casualty',
	'accident',
	'roadblock',
	'sos',
	'other'
] as const;

export const SEVERITIES = ['low', 'medium', 'high', 'critical'] as const;
export const STATUSES = ['unverified', 'verified', 'resolved', 'debunked'] as const;

export type Category = (typeof CATEGORIES)[number];
export type Severity = (typeof SEVERITIES)[number];
export type Status = (typeof STATUSES)[number];
export type VoteType = 'confirm' | 'deny';

export type Incident = {
	id: string;
	user_id: string | null;
	title: string;
	description: string | null;
	category: Category;
	severity: Severity;
	lng: number;
	lat: number;
	address_hint: string | null;
	media_urls: string[];
	status: Status;
	is_sos: boolean;
	created_at: string;
	updated_at: string;
	confirm_count: number;
	deny_count: number;
	comment_count: number;
	author_name: string | null;
	source_url: string | null;
};

export type IncidentComment = {
	id: string;
	incident_id: string;
	user_id: string | null;
	comment: string;
	media_url: string | null;
	created_at: string;
	author_name: string | null;
};

/** One public map notice. The message is free text so it can be a curfew, a storm, or anything else. */
export type SiteAlert = {
	active: boolean;
	message: string;
	severity: Severity;
};

export const DEFAULT_SITE_ALERT: SiteAlert = {
	active: false,
	message: 'Curfew in progress',
	severity: 'high'
};

export const SITE_ALERT_MAX = 120;

export type Viewport = {
	center: [number, number];
	zoom: number;
};

export const HOME_VIEWPORT: Viewport = {
	center: [57.5522, -20.275],
	zoom: 9.4
};

export type TileBounds = {
	minLng: number;
	minLat: number;
	maxLng: number;
	maxLat: number;
};

export type GridFeatureCollection = {
	type: 'FeatureCollection';
	features: Array<{
		type: 'Feature';
		geometry: { type: 'Polygon' | 'MultiPolygon'; coordinates: number[][][] | number[][][][] };
		properties: {
			total_count: number;
			critical_count: number;
			top_category: string | null;
			heat?: number;
		};
	}>;
};

export { CATEGORY_LABEL, SEVERITY_COLOR } from '$lib/tokens';

export const TIME_WINDOWS = [
	{ hours: 6, label: '6h' },
	{ hours: 24, label: '24h' },
	{ hours: 72, label: '72h' },
	{ hours: 168, label: '7d' }
] as const;

export function isCategory(value: string): value is Category {
	return (CATEGORIES as readonly string[]).includes(value);
}

export function isSeverity(value: string): value is Severity {
	return (SEVERITIES as readonly string[]).includes(value);
}

export function isStatus(value: string): value is Status {
	return (STATUSES as readonly string[]).includes(value);
}
