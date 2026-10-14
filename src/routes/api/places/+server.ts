import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { queryPhoton } from '$lib/places';

const LANG = new Set(['en', 'fr', 'de', 'it']);

export const GET: RequestHandler = async ({ url, fetch, request }) => {
	const q = url.searchParams.get('q')?.trim() ?? '';
	const lat = Number(url.searchParams.get('lat'));
	const lng = Number(url.searchParams.get('lng'));
	const requested = url.searchParams.get('lang') ?? 'en';
	if (q.length < 2 || q.length > 120 || !Number.isFinite(lat) || !Number.isFinite(lng)) return json([]);
	try {
		const places = await queryPhoton(fetch, q, { lng, lat }, LANG.has(requested) ? requested : 'en', request.signal);
		return json(places);
	} catch (cause) {
		if (cause instanceof Error && cause.name === 'AbortError') return json([]);
		return json({ error: 'search_failed' }, { status: 502 });
	}
};
