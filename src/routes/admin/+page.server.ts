import { fail, redirect } from '@sveltejs/kit';
import {
	adminConfig,
	clearAdminSession,
	credentialsMatch,
	hasAdminSession,
	listIncidents,
	setAdminSession,
	setIncidentHidden
} from '$lib/server/admin';
import type { Actions, PageServerLoad } from './$types';

const ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function secure(url: URL) {
	return url.protocol === 'https:';
}

export const load: PageServerLoad = async ({ cookies }) => {
	const configured = adminConfig() !== null;
	const authed = configured && hasAdminSession(cookies);
	if (!authed) return { configured, authed: false, incidents: [], error: '' };
	try {
		const incidents = await listIncidents();
		return { configured, authed: true, incidents, error: '' };
	} catch (cause) {
		return {
			configured,
			authed: true,
			incidents: [],
			error: cause instanceof Error ? cause.message : 'Could not load reports.'
		};
	}
};

export const actions: Actions = {
	login: async ({ request, cookies, url }) => {
		if (!adminConfig()) return fail(500, { error: 'Admin login is not configured.' });
		const form = await request.formData();
		const username = String(form.get('username') ?? '');
		const password = String(form.get('password') ?? '');
		if (!credentialsMatch(username, password)) {
			return fail(401, { error: 'Those credentials are not valid.' });
		}
		setAdminSession(cookies, secure(url));
		redirect(303, '/admin');
	},
	logout: async ({ cookies, url }) => {
		clearAdminSession(cookies, secure(url));
		redirect(303, '/admin');
	},
	visibility: async ({ request, cookies }) => {
		if (!hasAdminSession(cookies) || !adminConfig()) return fail(401, { error: 'Sign in again.' });
		const form = await request.formData();
		const id = String(form.get('id') ?? '');
		const hidden = String(form.get('hidden') ?? '') === 'true';
		if (!ID.test(id)) return fail(400, { error: 'That report id is not valid.' });
		try {
			await setIncidentHidden(id, hidden);
		} catch (cause) {
			return fail(400, {
				error: cause instanceof Error ? cause.message : 'Could not update the report.'
			});
		}
	}
};
