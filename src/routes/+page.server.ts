import { fetchSiteAlert } from '$lib/api';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ locals }) => {
	if (!locals.supabase) return { alert: null };
	try {
		return { alert: await fetchSiteAlert(locals.supabase) };
	} catch {
		return { alert: null };
	}
};
