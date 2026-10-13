import { createBrowserClient, createServerClient } from '@supabase/ssr';
import type { Cookies } from '@sveltejs/kit';
import { env } from '$env/dynamic/public';
import type { Database } from '$lib/database.types';
import type { SupabaseClient } from '@supabase/supabase-js';

function unquote(value: string | undefined) {
	return value?.trim().replace(/^['"]|['"]$/g, '') ?? '';
}

/** Keep only https://<project>.supabase.co. A pasted /rest/v1 path makes every API call 404. */
function projectOrigin(value: string): string | null {
	if (!/^https?:\/\//i.test(value)) return null;
	try {
		const url = new URL(value);
		if (url.protocol !== 'https:' && url.protocol !== 'http:') return null;
		return url.origin;
	} catch {
		return null;
	}
}

export function supabaseConfigProblem(): string | null {
	const url = unquote(env.PUBLIC_SUPABASE_URL);
	const key = unquote(env.PUBLIC_SUPABASE_ANON_KEY);
	if (!url || !key) {
		return 'Add PUBLIC_SUPABASE_URL and the publishable key to .env.';
	}
	if (!projectOrigin(url)) {
		return 'PUBLIC_SUPABASE_URL must be the project URL and start with https://.';
	}
	if (key.startsWith('sb_secret_')) {
		return 'The secret key cannot be used in the browser. Set PUBLIC_SUPABASE_ANON_KEY to the publishable key (sb_publishable_…).';
	}
	return null;
}

export function supabaseEnv(): { url: string; key: string } | null {
	if (supabaseConfigProblem()) return null;
	const url = projectOrigin(unquote(env.PUBLIC_SUPABASE_URL));
	const key = unquote(env.PUBLIC_SUPABASE_ANON_KEY);
	if (!url || !key) return null;
	return { url, key };
}

let browserClient: SupabaseClient<Database> | null = null;

export function createSupabaseBrowserClient(): SupabaseClient<Database> | null {
	const cfg = supabaseEnv();
	if (!cfg) return null;
	if (!browserClient) {
		browserClient = createBrowserClient<Database>(cfg.url, cfg.key);
	}
	return browserClient;
}

export function createSupabaseServerClient(cookies: Cookies): SupabaseClient<Database> | null {
	const cfg = supabaseEnv();
	if (!cfg) return null;
	return createServerClient<Database>(cfg.url, cfg.key, {
		cookies: {
			getAll: () => cookies.getAll(),
			setAll: (cookiesToSet) => {
				cookiesToSet.forEach(({ name, value, options }) => {
					try {
						cookies.set(name, value, { ...options, path: '/' });
					} catch {
						// Token refresh can run after the response headers are already committed.
					}
				});
			}
		}
	});
}
