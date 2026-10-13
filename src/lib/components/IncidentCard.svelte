<script lang="ts">
	import { ThumbsDown, ThumbsUp, X } from 'lucide-svelte';
	import { addComment, fetchComments, vote } from '$lib/api';
	import { createSupabaseBrowserClient } from '$lib/supabaseClient';
	import { CATEGORY_LABEL, type Incident, type IncidentComment, type VoteType } from '$lib/types';
	import { pushToast } from '$lib/ui.svelte';

	let {
		incident,
		onClose,
		onChanged
	}: {
		incident: Incident;
		onClose: () => void;
		onChanged: () => void;
	} = $props();

	let comments = $state<IncidentComment[]>([]);
	let draft = $state('');
	let busy = $state(false);
	let mediaIndex = $state(0);
	let syncedId = '';

	const media = $derived(incident.media_urls);
	const activeMedia = $derived(media[mediaIndex] ?? null);

	$effect(() => {
		const incidentId = incident.id;
		if (syncedId !== incidentId) {
			syncedId = incidentId;
			mediaIndex = 0;
		}
		void loadComments(incidentId, incident.comment_count);
	});

	function isVideo(url: string) {
		return /\.(mp4|webm|mov)(\?|$)/i.test(url);
	}

	function when(value: string) {
		return new Date(value).toLocaleString();
	}

	async function loadComments(incidentId: string, _count: number) {
		const supabase = createSupabaseBrowserClient();
		if (!supabase) return;
		try {
			const rows = await fetchComments(supabase, incidentId);
			if (incident.id === incidentId) comments = rows;
		} catch (cause) {
			pushToast(cause instanceof Error ? cause.message : 'Could not load comments.', 'err');
		}
	}

	async function castVote(voteType: VoteType) {
		const supabase = createSupabaseBrowserClient();
		if (!supabase) return;
		busy = true;
		try {
			await vote(supabase, incident.id, voteType);
			onChanged();
		} catch (cause) {
			pushToast(cause instanceof Error ? cause.message : 'Could not save the vote.', 'err');
		} finally {
			busy = false;
		}
	}

	async function publishComment(event: SubmitEvent) {
		event.preventDefault();
		const text = draft.trim();
		if (!text) return;
		const supabase = createSupabaseBrowserClient();
		if (!supabase) return;
		busy = true;
		try {
			await addComment(supabase, incident.id, text);
			draft = '';
			onChanged();
			await loadComments(incident.id, incident.comment_count + 1);
		} catch (cause) {
			pushToast(cause instanceof Error ? cause.message : 'Could not post the comment.', 'err');
		} finally {
			busy = false;
		}
	}
</script>

<div class="fixed inset-0 z-50 flex items-end justify-center bg-slate-950/50 sm:justify-end">
	<button type="button" class="absolute inset-0" aria-label="Close incident" onclick={onClose}></button>
	<article class="relative max-h-[88dvh] w-full overflow-y-auto rounded-t-3xl bg-slate-900 p-5 shadow-2xl sm:h-full sm:max-h-none sm:max-w-md sm:rounded-none">
		<div class="mb-3 flex items-start justify-between gap-3">
			<div>
				<p class="text-xs font-semibold tracking-[0.16em] text-red-300 uppercase">
					{CATEGORY_LABEL[incident.category]} · {incident.severity}
				</p>
				<h2 class="text-2xl font-semibold text-white">{incident.title}</h2>
				<p class="mt-1 text-sm text-slate-400">
					{incident.author_name || 'Reporter'} · {when(incident.created_at)}
				</p>
			</div>
			<button type="button" class="rounded-full p-2 text-slate-300 hover:bg-slate-800" onclick={onClose} aria-label="Close">
				<X size={18} />
			</button>
		</div>

		<p class="mb-3 inline-flex rounded-full bg-slate-800 px-2 py-1 text-xs text-slate-200 capitalize">{incident.status}</p>

		{#if activeMedia}
			<div class="relative mb-4 overflow-hidden rounded-2xl bg-black">
				{#if isVideo(activeMedia)}
					<!-- svelte-ignore a11y_media_has_caption -->
					<video class="max-h-64 w-full" src={activeMedia} controls></video>
				{:else}
					<img class="max-h-64 w-full object-cover" src={activeMedia} alt="" />
				{/if}
				{#if media.length > 1}
					<div class="absolute right-2 bottom-2 rounded-full bg-slate-950/80 px-2 py-1 text-xs">
						{mediaIndex + 1} / {media.length}
					</div>
					<button type="button" class="absolute top-1/2 left-2 -translate-y-1/2 rounded-full bg-slate-950/80 px-2 py-1" onclick={() => (mediaIndex = (mediaIndex + media.length - 1) % media.length)} aria-label="Previous media">‹</button>
					<button type="button" class="absolute top-1/2 right-2 -translate-y-1/2 rounded-full bg-slate-950/80 px-2 py-1" onclick={() => (mediaIndex = (mediaIndex + 1) % media.length)} aria-label="Next media">›</button>
				{/if}
			</div>
		{/if}

		<p class="mb-3 whitespace-pre-wrap text-sm leading-6 text-slate-200">{incident.description || 'No description.'}</p>
		{#if incident.address_hint}
			<p class="mb-4 text-sm text-slate-400">{incident.address_hint}</p>
		{/if}

		<div class="mb-4 flex gap-2">
			<button type="button" class="inline-flex flex-1 items-center justify-center gap-2 rounded-xl bg-slate-800 py-2 text-sm" disabled={busy} onclick={() => castVote('confirm')}>
				<ThumbsUp size={16} /> Confirm {incident.confirm_count}
			</button>
			<button type="button" class="inline-flex flex-1 items-center justify-center gap-2 rounded-xl bg-slate-800 py-2 text-sm" disabled={busy} onclick={() => castVote('deny')}>
				<ThumbsDown size={16} /> Deny {incident.deny_count}
			</button>
		</div>

		<h3 class="mb-2 text-sm font-semibold text-slate-300">Comments</h3>
		<ul class="mb-3 space-y-2">
			{#each comments as comment (comment.id)}
				<li class="rounded-xl bg-slate-950 px-3 py-2">
					<p class="text-xs text-slate-400">{comment.author_name || 'Reporter'} · {when(comment.created_at)}</p>
					<p class="mt-1 text-sm text-slate-100">{comment.comment}</p>
				</li>
			{:else}
				<li class="text-sm text-slate-500">No comments yet.</li>
			{/each}
		</ul>

		<form class="flex gap-2" onsubmit={publishComment}>
			<input
				class="min-w-0 flex-1 rounded-xl border border-slate-700 bg-slate-950 px-3 py-2 text-sm"
				placeholder="Add a comment"
				maxlength="2000"
				bind:value={draft}
			/>
			<button class="rounded-xl bg-red-600 px-3 py-2 text-sm font-semibold" disabled={busy}>Post</button>
		</form>
	</article>
</div>
