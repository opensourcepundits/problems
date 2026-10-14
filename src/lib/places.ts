// Place search for the pin picker. Photon is a public OpenStreetMap geocoder;
// results are biased toward the current map centre but not limited to it.

export type PlaceHit = {
	id: string;
	name: string;
	/** Name plus locality, ready for the landmark field. */
	label: string;
	lng: number;
	lat: number;
	zoom: number;
	bounds: [[number, number], [number, number]] | null;
};

type PhotonFeature = {
	geometry?: { coordinates?: number[] };
	properties?: {
		osm_type?: string;
		osm_id?: number;
		osm_value?: string;
		name?: string;
		housenumber?: string;
		street?: string;
		district?: string;
		city?: string;
		state?: string;
		country?: string;
		extent?: number[];
	};
};

const ZOOM: Record<string, number> = {
	house: 18,
	building: 18,
	address: 17,
	street: 16,
	road: 16,
	pedestrian: 17,
	neighbourhood: 15,
	suburb: 15,
	quarter: 15,
	hamlet: 15,
	village: 14,
	town: 13,
	city: 12,
	municipality: 12,
	county: 10,
	state: 8,
	country: 5
};

export function photonLang(locale: string): string {
	if (locale === 'de' || locale === 'fr' || locale === 'it') return locale;
	if (locale === 'mfe') return 'fr';
	return 'en';
}

function detail(props: NonNullable<PhotonFeature['properties']>, name: string): string {
	const street = [props.housenumber, props.street].filter(Boolean).join(' ');
	const seen = new Set<string>([name.toLowerCase()]);
	const parts: string[] = [];
	for (const part of [street, props.city, props.state, props.country]) {
		if (!part) continue;
		const key = part.toLowerCase();
		if (seen.has(key)) continue;
		seen.add(key);
		parts.push(part);
	}
	return parts.join(', ');
}

function boundsOf(extent: number[] | undefined): PlaceHit['bounds'] {
	if (!extent || extent.length < 4) return null;
	const [west, north, east, south] = extent;
	if (![west, north, east, south].every((value) => Number.isFinite(value))) return null;
	if (Math.abs(east - west) < 0.0008 && Math.abs(north - south) < 0.0008) return null;
	return [
		[west, south],
		[east, north]
	];
}

function toPlace(feature: PhotonFeature): PlaceHit | null {
	const props = feature.properties;
	const coords = feature.geometry?.coordinates;
	if (!props || !coords || coords.length < 2) return null;
	const [lng, lat] = coords;
	if (!Number.isFinite(lng) || !Number.isFinite(lat)) return null;
	const street = [props.housenumber, props.street].filter(Boolean).join(' ');
	const name = props.name || street || props.city || props.state || props.country || '';
	if (!name) return null;
	const extra = detail(props, name);
	const kind = props.osm_value ?? '';
	return {
		id: `${props.osm_type ?? 'x'}:${props.osm_id ?? name}`,
		name,
		label: extra ? `${name}, ${extra}` : name,
		lng,
		lat,
		zoom: ZOOM[kind] ?? 15,
		bounds: boundsOf(props.extent)
	};
}

export async function queryPhoton(
	fetchFn: typeof fetch,
	query: string,
	bias: { lng: number; lat: number },
	lang: string,
	signal?: AbortSignal
): Promise<PlaceHit[]> {
	const url = new URL('https://photon.komoot.io/api/');
	url.searchParams.set('q', query);
	url.searchParams.set('limit', '6');
	url.searchParams.set('lat', String(bias.lat));
	url.searchParams.set('lon', String(bias.lng));
	url.searchParams.set('lang', lang);
	const response = await fetchFn(url, {
		signal,
		headers: { Accept: 'application/json', 'User-Agent': 'CrisisReport/1.0 (place search)' }
	});
	if (!response.ok) throw new Error(`Place search failed: ${response.status}`);
	const body = (await response.json()) as { features?: PhotonFeature[] };
	const seen = new Set<string>();
	const places: PlaceHit[] = [];
	for (const feature of body.features ?? []) {
		const place = toPlace(feature);
		if (!place || seen.has(place.id)) continue;
		seen.add(place.id);
		places.push(place);
	}
	return places;
}

/** Browser lookup. Goes through our server so the geocoder is not a cross-origin call. */
export async function searchPlaces(
	query: string,
	bias: { lng: number; lat: number },
	lang: string,
	signal: AbortSignal
): Promise<PlaceHit[]> {
	const params = new URLSearchParams({
		q: query,
		lat: String(bias.lat),
		lng: String(bias.lng),
		lang
	});
	const response = await fetch(`/api/places?${params}`, { signal });
	if (!response.ok) throw new Error(`Place search failed: ${response.status}`);
	const body = (await response.json()) as unknown;
	return Array.isArray(body) ? (body as PlaceHit[]) : [];
}
