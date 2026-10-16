import { fail, redirect } from '@sveltejs/kit';
import {
	adminConfig,
	clearAdminSession,
	credentialsMatch,
	getSiteAlert,
	hasAdminSession,
	listIncidents,
	setAdminSession,
	setIncidentHidden,
	setSiteAlert
} from '$lib/server/admin';
import { DEFAULT_SITE_ALERT, isSeverity } from '$lib/types';
import type { Actions, PageServerLoad } from './$types';

const ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function secure(url: URL) {
	return url.protocol === 'https:';
}

export const load: PageServerLoad = async ({ cookies }) => {
	const configured = adminConfig() !== null;
	const authed = configured && hasAdminSession(cookies);
	if (!authed) return { configured, authed: false, incidents: [], error: '', alert: null, alertReady: false };
	let incidents: Awaited<ReturnType<typeof listIncidents>> = [];
	let error = '';
	try {
		incidents = await listIncidents();
	} catch (cause) {
		error = cause instanceof Error ? cause.message : 'Could not load reports.';
	}
	let alert = DEFAULT_SITE_ALERT;
	let alertReady = false;
	try {
		const notice = await getSiteAlert();
		alert = notice.alert;
		alertReady = notice.ready;
	} catch (cause) {
		const message = cause instanceof Error ? cause.message : 'Could not load the notice.';
		error = error ? `${error} ${message}` : message;
	}
	return { configured, authed: true, incidents, error, alert, alertReady };
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
	},
	alert: async ({ request, cookies }) => {
		if (!hasAdminSession(cookies) || !adminConfig()) return fail(401, { error: 'Sign in again.' });
		const form = await request.formData();
		const message = String(form.get('message') ?? '');
		const severity = String(form.get('severity') ?? '');
		const active = String(form.get('active') ?? '') === 'true';
		if (!isSeverity(severity)) return fail(400, { error: 'That severity is not valid.' });
		try {
			await setSiteAlert({ active, message, severity });
		} catch (cause) {
			return fail(400, {
				error: cause instanceof Error ? cause.message : 'Could not update the notice.'
			});
		}
		return { alertSaved: true };
	}
};
