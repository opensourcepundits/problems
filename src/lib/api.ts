import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import {
	isCategory,
	isSeverity,
	isStatus,
	type Category,
	type GridFeatureCollection,
	type Incident,
	type IncidentComment,
	type Severity,
	type TileBounds,
	type VoteType
} from '$lib/types';

type Client = SupabaseClient<Database>;

function message(error: { message: string } | null, fallback: string) {
	return error?.message || fallback;
}

function asIncident(row: Database['public']['Functions']['get_incidents']['Returns'][number]): Incident {
	if (!isCategory(row.category) || !isSeverity(row.severity) || !isStatus(row.status)) {
		throw new Error('Incident row has an unknown category, severity, or status.');
	}
	return {
		id: row.id,
		user_id: row.user_id,
		title: row.title,
		description: row.description,
		category: row.category,
		severity: row.severity,
		lng: Number(row.lng),
		lat: Number(row.lat),
		address_hint: row.address_hint,
		media_urls: row.media_urls ?? [],
		status: row.status,
		is_sos: row.is_sos,
		created_at: row.created_at,
		updated_at: row.updated_at,
		confirm_count: Number(row.confirm_count),
		deny_count: Number(row.deny_count),
		comment_count: Number(row.comment_count),
		author_name: row.author_name
	};
}

export async function fetchIncidents(
	supabase: Client,
	hours: number,
	category: Category | 'all',
	bounds: TileBounds | null
): Promise<Incident[]> {
	const { data, error } = await supabase.rpc('get_incidents', {
		hours_back: hours,
		category_filter: category === 'all' ? null : category,
		min_lng: bounds?.minLng ?? null,
		min_lat: bounds?.minLat ?? null,
		max_lng: bounds?.maxLng ?? null,
		max_lat: bounds?.maxLat ?? null
	});
	if (error) throw new Error(message(error, 'Could not load incidents.'));
	return (data ?? []).map(asIncident);
}

export async function fetchGrid(
	supabase: Client,
	hours: number,
	category: Category | 'all'
): Promise<GridFeatureCollection> {
	const { data, error } = await supabase.rpc('get_5km_grid', {
		hours_back: hours,
		category_filter: category === 'all' ? null : category
	});
	if (error) throw new Error(message(error, 'Could not load the 5km grid.'));
	const collection = data as GridFeatureCollection | null;
	if (!collection || collection.type !== 'FeatureCollection' || !Array.isArray(collection.features)) {
		return { type: 'FeatureCollection', features: [] };
	}
	return collection;
}

export async function createIncident(
	supabase: Client,
	input: {
		title: string;
		description: string;
		category: Category;
		severity: Severity;
		lng: number;
		lat: number;
		addressHint: string;
		mediaUrls: string[];
		isSos: boolean;
	}
): Promise<string> {
	const { data, error } = await supabase.rpc('create_incident', {
		p_title: input.title,
		p_description: input.description || null,
		p_category: input.category,
		p_severity: input.severity,
		p_lng: input.lng,
		p_lat: input.lat,
		p_address_hint: input.addressHint || null,
		p_media_urls: input.mediaUrls,
		p_is_sos: input.isSos
	});
	if (error || !data) throw new Error(message(error, 'Could not save the incident.'));
	return data;
}

export async function uploadEvidence(supabase: Client, userId: string, file: File): Promise<string> {
	const extension = file.name.split('.').pop() || 'bin';
	const path = `${userId}/${crypto.randomUUID()}.${extension}`;
	const { error } = await supabase.storage.from('incident-media').upload(path, file, {
		contentType: file.type,
		upsert: false
	});
	if (error) throw new Error(message(error, 'Could not upload evidence.'));
	const { data } = supabase.storage.from('incident-media').getPublicUrl(path);
	return data.publicUrl;
}

export async function updateIncident(
	supabase: Client,
	id: string,
	patch: { description: string; severity: Severity; addressHint: string; status: Incident['status'] }
) {
	const { error } = await supabase
		.from('incidents')
		.update({
			description: patch.description || null,
			severity: patch.severity,
			address_hint: patch.addressHint || null,
			status: patch.status
		})
		.eq('id', id);
	if (error) throw new Error(message(error, 'Could not update the incident.'));
}

export async function fetchComments(supabase: Client, incidentId: string): Promise<IncidentComment[]> {
	const { data, error } = await supabase
		.from('incident_comments')
		.select('id, incident_id, user_id, comment, media_url, created_at, profiles(full_name)')
		.eq('incident_id', incidentId)
		.order('created_at', { ascending: true });
	if (error) throw new Error(message(error, 'Could not load comments.'));
	return (data ?? []).map((row) => {
		const profile = row.profiles as { full_name: string | null } | { full_name: string | null }[] | null;
		const author = Array.isArray(profile) ? profile[0]?.full_name : profile?.full_name;
		return {
			id: row.id,
			incident_id: row.incident_id,
			user_id: row.user_id,
			comment: row.comment,
			media_url: row.media_url,
			created_at: row.created_at,
			author_name: author ?? null
		};
	});
}

export async function addComment(supabase: Client, incidentId: string, userId: string, comment: string) {
	const { error } = await supabase.from('incident_comments').insert({
		incident_id: incidentId,
		user_id: userId,
		comment,
		media_url: null
	});
	if (error) throw new Error(message(error, 'Could not post the comment.'));
}

export async function deleteComment(supabase: Client, commentId: string) {
	const { error } = await supabase.from('incident_comments').delete().eq('id', commentId);
	if (error) throw new Error(message(error, 'Could not delete the comment.'));
}

export async function vote(supabase: Client, incidentId: string, userId: string, voteType: VoteType) {
	const { error } = await supabase.from('incident_confirmations').upsert(
		{
			incident_id: incidentId,
			user_id: userId,
			vote_type: voteType
		},
		{ onConflict: 'incident_id,user_id' }
	);
	if (error) throw new Error(message(error, 'Could not save the vote.'));
}

export function currentPosition(): Promise<GeolocationPosition> {
	if (!navigator.geolocation) {
		return Promise.reject(new Error('This browser cannot read your location.'));
	}
	return new Promise((resolve, reject) => {
		navigator.geolocation.getCurrentPosition(resolve, reject, {
			enableHighAccuracy: true,
			timeout: 12000,
			maximumAge: 0
		});
	});
}
