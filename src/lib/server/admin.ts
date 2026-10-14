import { createHash, createHmac, timingSafeEqual } from 'node:crypto';
import { env as privateEnv } from '$env/dynamic/private';
import { env as publicEnv } from '$env/dynamic/public';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { Cookies } from '@sveltejs/kit';
import type { Database } from '$lib/database.types';

const COOKIE = 'crisis_admin';
const MAX_AGE = 60 * 60 * 12;

export type AdminIncident = {
	id: string;
	title: string;
	description: string | null;
	category: string;
	severity: string;
	status: string;
	hidden: boolean;
	created_at: string;
};

function digest(value: string) {
	return createHash('sha256').update(value).digest();
}

function same(left: string, right: string) {
	return timingSafeEqual(digest(left), digest(right));
}

export function adminConfig() {
	const username = privateEnv.ADMIN_USERNAME?.trim() ?? '';
	const password = privateEnv.ADMIN_PASSWORD ?? '';
	const url = projectOrigin(publicEnv.PUBLIC_SUPABASE_URL ?? '');
	const secret = (privateEnv.SUPABASE_SECRET_KEY || privateEnv.SUPABASE_SERVICE_ROLE_KEY || '').trim();
	if (!username || !password || !url || !secret || secret.startsWith('sb_publishable_')) return null;
	return { username, password, url, secret };
}

function projectOrigin(value: string) {
	const trimmed = value.trim().replace(/^['"]|['"]$/g, '');
	if (!/^https?:\/\//i.test(trimmed)) return '';
	try {
		return new URL(trimmed).origin;
	} catch {
		return '';
	}
}

export function credentialsMatch(username: string, password: string) {
	const config = adminConfig();
	if (!config) return false;
	return same(username.trim(), config.username) && same(password, config.password);
}

function cookieOptions(secure: boolean) {
	return {
		path: '/',
		httpOnly: true,
		sameSite: 'lax' as const,
		secure,
		maxAge: MAX_AGE
	};
}

export function setAdminSession(cookies: Cookies, secure: boolean) {
	const config = adminConfig();
	if (!config) return;
	const payload = String(Date.now() + MAX_AGE * 1000);
	const signature = createHmac('sha256', config.password).update(payload).digest('base64url');
	cookies.set(COOKIE, `${payload}.${signature}`, cookieOptions(secure));
}

export function clearAdminSession(cookies: Cookies, secure: boolean) {
	cookies.delete(COOKIE, cookieOptions(secure));
}

export function hasAdminSession(cookies: Cookies) {
	const config = adminConfig();
	const raw = cookies.get(COOKIE);
	if (!config || !raw) return false;
	const dot = raw.lastIndexOf('.');
	if (dot <= 0) return false;
	const payload = raw.slice(0, dot);
	const signature = raw.slice(dot + 1);
	const expires = Number(payload);
	if (!Number.isFinite(expires) || expires < Date.now()) return false;
	const expected = createHmac('sha256', config.password).update(payload).digest('base64url');
	const given = Buffer.from(signature);
	const wanted = Buffer.from(expected);
	if (given.length !== wanted.length) return false;
	return timingSafeEqual(given, wanted);
}

function adminClient(): SupabaseClient<Database> | null {
	const config = adminConfig();
	if (!config) return null;
	return createClient<Database>(config.url, config.secret, {
		auth: { persistSession: false, autoRefreshToken: false }
	});
}

export async function listIncidents(): Promise<AdminIncident[]> {
	const supabase = adminClient();
	if (!supabase) throw new Error('Admin database access is not configured.');
	const { data, error } = await supabase
		.from('incidents')
		.select('id, title, description, category, severity, status, hidden, created_at')
		.order('created_at', { ascending: false })
		.limit(500);
	if (error) throw new Error(error.message);
	return data ?? [];
}

export async function setIncidentHidden(id: string, hidden: boolean) {
	const supabase = adminClient();
	if (!supabase) throw new Error('Admin database access is not configured.');
	const { error } = await supabase.from('incidents').update({ hidden }).eq('id', id);
	if (error) throw new Error(error.message);
}
