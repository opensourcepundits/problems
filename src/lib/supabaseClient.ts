import { createBrowserClient, createServerClient } from '@supabase/ssr';
import type { Cookies } from '@sveltejs/kit';
import { env } from '$env/dynamic/public';
import type { Database } from '$lib/database.types';
import type { SupabaseClient } from '@supabase/supabase-js';

export function supabaseEnv(): { url: string; key: string } | null {
	const url = env.PUBLIC_SUPABASE_URL?.trim();
	const key = env.PUBLIC_SUPABASE_ANON_KEY?.trim();
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
