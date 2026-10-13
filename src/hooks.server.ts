import type { Handle } from '@sveltejs/kit';
import { createSupabaseServerClient, supabaseEnv } from '$lib/supabaseClient';

export const handle: Handle = async ({ event, resolve }) => {
	if (!supabaseEnv()) {
		event.locals.supabase = null;
		event.locals.safeGetSession = async () => ({ session: null, user: null });
		return resolve(event);
	}

	event.locals.supabase = createSupabaseServerClient(event.cookies);
	event.locals.safeGetSession = async () => {
		if (!event.locals.supabase) return { session: null, user: null };
		const {
			data: { user },
			error
		} = await event.locals.supabase.auth.getUser();
		if (error || !user) return { session: null, user: null };
		const {
			data: { session }
		} = await event.locals.supabase.auth.getSession();
		return { session, user };
	};

	return resolve(event, {
		filterSerializedResponseHeaders: (name) =>
			name === 'content-range' || name === 'x-supabase-api-version'
	});
};
