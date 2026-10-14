<script lang="ts">
	import {
		Ban,
		Check,
		ChevronLeft,
		ChevronRight,
		Clock,
		Download,
		MapPin,
		Maximize2,
		SendHorizontal,
		ThumbsDown,
		ThumbsUp,
		User,
		Users,
		X
	} from 'lucide-svelte';
	import { addComment, fetchComments, fetchMyVote, vote } from '$lib/api';
	import { absoluteTime, t, timeAgo } from '$lib/i18n/index.svelte';
	import { createSupabaseBrowserClient } from '$lib/supabaseClient';
	import type { Incident, IncidentComment, VoteType } from '$lib/types';
	import { chrome, pushToast } from '$lib/ui.svelte';
	import BottomSheet from './ui/BottomSheet.svelte';
	import CategoryTile from './ui/CategoryTile.svelte';
	import IconButton from './ui/IconButton.svelte';
	import SeverityBadge from './ui/SeverityBadge.svelte';
	import SourceCard from './ui/SourceCard.svelte';
	import StatusBadge from './ui/StatusBadge.svelte';
	import { parseSource } from '$lib/sources';

	let {
		incident,
		snap = $bindable('peek'),
		onClose,
		onChanged
	}: {
		incident: Incident;
		snap?: 'peek' | 'full';
		onClose: () => void;
		onChanged: () => void;
	} = $props();

	let comments = $state<IncidentComment[]>([]);
	let myVote = $state<VoteType | null>(null);
	let draft = $state('');
	let busy = $state(false);
	let mediaIndex = $state(0);
	let viewer = $state<number | null>(null);
	let showAbsolute = $state(false);
	let rail = $state<HTMLDivElement | undefined>(undefined);
	let syncedId = '';

	const media = $derived(incident.media_urls);
	const source = $derived(parseSource(incident.source_url));
	const category = $derived(incident.is_sos ? 'sos' : incident.category);
	const debunked = $derived(incident.status === 'debunked');
	const total = $derived(incident.confirm_count + incident.deny_count);
	const pct = $derived(total ? Math.round((incident.confirm_count / total) * 100) : 0);

	$effect(() => {
		const incidentId = incident.id;
		if (syncedId !== incidentId) {
			syncedId = incidentId;
			mediaIndex = 0;
			viewer = null;
			showAbsolute = false;
			myVote = null;
			comments = [];
		}
		void loadComments(incidentId, incident.comment_count);
		void loadVote(incidentId);
	});

	function isVideo(url: string) {
		return /\.(mp4|webm|mov)(\?|$)/i.test(url);
	}

	async function loadComments(incidentId: string, _count: number) {
		const supabase = createSupabaseBrowserClient();
		if (!supabase) return;
		try {
			const rows = await fetchComments(supabase, incidentId);
			if (incident.id === incidentId) comments = rows;
		} catch (cause) {
			pushToast(cause instanceof Error ? cause.message : t('could_not_update'), 'err');
		}
	}

	async function loadVote(incidentId: string) {
		const supabase = createSupabaseBrowserClient();
		if (!supabase) return;
		try {
			const voteType = await fetchMyVote(supabase, incidentId);
			if (incident.id === incidentId) myVote = voteType;
		} catch (cause) {
			pushToast(cause instanceof Error ? cause.message : t('vote_failed'), 'err');
		}
	}

	async function castVote(voteType: VoteType) {
		const supabase = createSupabaseBrowserClient();
		if (!supabase) return;
		const next = myVote === voteType ? null : voteType;
		busy = true;
		try {
			await vote(supabase, incident.id, next);
			myVote = next;
			onChanged();
		} catch (cause) {
			pushToast(cause instanceof Error ? cause.message : t('vote_failed'), 'err');
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
			pushToast(cause instanceof Error ? cause.message : t('comment_failed'), 'err');
		} finally {
			busy = false;
		}
	}

	function goTo(index: number) {
		const next = (index + media.length) % media.length;
		rail?.scrollTo({ left: next * rail.clientWidth, behavior: 'smooth' });
		mediaIndex = next;
	}
</script>

{#snippet header()}
	<div class="border-b border-line-subtle px-4 pt-0.5 pb-3 lg:px-5 lg:pt-[18px]">
		<div class="flex items-start gap-3">
			<CategoryTile {category} size={44} />
			<div class="min-w-0 flex-1">
				<div class="mb-1.5 flex flex-wrap gap-1.5">
					<SeverityBadge severity={incident.severity} />
					<StatusBadge status={incident.status} />
				</div>
				<h2
					class="text-title-lg font-heavy tracking-tight text-pretty text-fg {debunked
						? 'line-through decoration-[var(--text-tertiary)]'
						: ''}"
				>
					{incident.title}
				</h2>
				<button
					type="button"
					title={absoluteTime(incident.created_at)}
					class="mt-1 text-left text-label font-normal text-fg-tertiary"
					onclick={() => (showAbsolute = !showAbsolute)}
				>
					<Clock size={14} class="mr-1 inline align-[-2px]" /><span class={showAbsolute ? 'num' : ''}
						>{showAbsolute ? absoluteTime(incident.created_at) : timeAgo(incident.created_at)}</span
					>
					· {t(`cat_${category}`)} · {incident.author_name || t('anonymous_reporter')}
				</button>
			</div>
			<IconButton icon={X} label={t('close')} class="-mt-1 -mr-1.5" onclick={onClose} />
		</div>
	</div>
{/snippet}

{#snippet body()}
	<div class="flex flex-col gap-[18px] px-4 pt-3.5 pb-6 lg:px-5 lg:pt-4">
		{#if debunked}
			<div class="flex items-center gap-2 rounded-md bg-surface-raised px-3 py-2.5 text-label font-normal text-fg-secondary">
				<Ban size={16} class="shrink-0" />{t('debunked_note')}
			</div>
		{/if}

		<div class="flex items-start gap-2.5">
			<MapPin size={18} class="mt-0.5 shrink-0 text-fg-tertiary" />
			<div class="min-w-0">
				<p class="text-body leading-[22px] font-bold text-fg">{incident.address_hint || t('dropped_pin')}</p>
				<p class="num text-caption text-fg-tertiary">{incident.lat.toFixed(4)}, {incident.lng.toFixed(4)}</p>
			</div>
		</div>

		<p class="text-body whitespace-pre-wrap text-fg-secondary">{incident.description || t('no_description')}</p>

		{#if source}<SourceCard {source} />{/if}

		{#if media.length}
			<div class="relative aspect-[4/3] overflow-hidden rounded-[14px] bg-[#000]">
				<div
					bind:this={rail}
					class="noscroll flex h-full w-full snap-x snap-mandatory overflow-x-auto"
					onscroll={(event) => (mediaIndex = Math.round(event.currentTarget.scrollLeft / event.currentTarget.clientWidth))}
				>
					{#each media as url, index (url)}
						<button
							type="button"
							class="h-full w-full shrink-0 snap-start cursor-zoom-in"
							aria-label={t('view_fullscreen')}
							onclick={() => (viewer = index)}
						>
							{#if isVideo(url)}
								<!-- svelte-ignore a11y_media_has_caption -->
								<video class="h-full w-full object-cover" src={url} muted playsinline preload="metadata"></video>
							{:else}
								<img class="h-full w-full object-cover" src={url} alt={incident.title} loading="lazy" />
							{/if}
						</button>
					{/each}
				</div>
				{#if media.length > 1}
					<span class="num absolute bottom-2.5 left-2.5 rounded-xs bg-[rgba(7,9,12,.72)] px-2 py-[3px] text-micro font-bold text-white">
						{mediaIndex + 1} / {media.length}
					</span>
					<div class="pointer-events-none absolute inset-x-0 bottom-3.5 flex justify-center gap-[5px]">
						{#each media as url, index (url)}
							<span class="h-1.5 rounded-[3px] transition-[width] duration-200 {index === mediaIndex ? 'w-4 bg-white' : 'w-1.5 bg-white/45'}"></span>
						{/each}
					</div>
					<IconButton icon={ChevronLeft} label={t('previous')} variant="media" class="absolute top-[calc(50%-22px)] left-2 !hidden lg:!grid" onclick={() => goTo(mediaIndex - 1)} />
					<IconButton icon={ChevronRight} label={t('next')} variant="media" class="absolute top-[calc(50%-22px)] right-2 !hidden lg:!grid" onclick={() => goTo(mediaIndex + 1)} />
				{/if}
				<IconButton icon={Maximize2} label={t('view_fullscreen')} variant="media" size="sm" class="absolute right-2 bottom-2" onclick={() => (viewer = mediaIndex)} />
			</div>
		{/if}

		<section aria-label={t('verification')} class="rounded-lg border border-line-subtle bg-surface-raised p-3.5">
			<div class="flex items-baseline justify-between gap-2">
				<p class="text-body-sm text-fg">
					{#if total}
						<Users size={16} class="mr-1.5 inline align-[-3px] text-fg-tertiary" />
						<b class="num">{incident.confirm_count}</b>
						{t('confirmed')} <span class="text-fg-tertiary">·</span>
						<b class="num">{incident.deny_count}</b>
						{t('denied')}
					{:else}
						<span class="text-fg-secondary">{t('no_confirm_yet')}</span>
					{/if}
				</p>
				{#if total}<span class="num text-caption text-fg-tertiary">{pct}%</span>{/if}
			</div>
			<div aria-hidden="true" class="mt-2.5 mb-3 flex h-1.5 gap-0.5 overflow-hidden rounded-[3px] bg-line-subtle">
				{#if total}
					<span class="bg-success-400" style="width:{pct}%"></span>
					<span class="flex-1 bg-ink-500"></span>
				{/if}
			</div>
			<div class="flex gap-2" role="group" aria-label={t('verification')}>
				{#each ['confirm', 'deny'] as const as kind (kind)}
					{@const on = myVote === kind}
					{@const confirm = kind === 'confirm'}
					<button
						type="button"
						aria-pressed={on}
						disabled={busy}
						class="press flex h-12 flex-1 items-center justify-center gap-2 rounded-md text-[15px] font-bold disabled:opacity-60 {on
							? confirm
								? 'border-2 border-success-400 bg-[rgba(62,207,142,.16)] text-fg'
								: 'border-2 border-fg-secondary bg-surface-raised-hover text-fg'
							: 'border border-line-input bg-surface-input text-fg-secondary hover:text-fg'}"
						onclick={() => castVote(kind)}
					>
						{#if on}
							<Check size={18} strokeWidth={3} class={confirm ? 'text-success-400' : ''} />
						{:else if confirm}
							<ThumbsUp size={18} />
						{:else}
							<ThumbsDown size={18} />
						{/if}
						{confirm ? (on ? t('you_confirmed') : t('confirm')) : on ? t('you_denied') : t('deny')}
					</button>
				{/each}
			</div>
			<p class="mx-0.5 mt-2 text-caption text-fg-tertiary">
				{myVote ? t('vote_hint_set') : t('vote_hint_none')}
			</p>
		</section>

		<section aria-label={t('updates')}>
			<h3 class="mb-3 text-body leading-[22px] font-bold text-fg">
				{t('updates')} <span class="num font-semibold text-fg-tertiary">{comments.length}</span>
			</h3>
			{#if comments.length}
				<ul class="flex flex-col gap-3.5">
					{#each comments as comment (comment.id)}
						<li class="flex gap-2.5">
							<span class="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-surface-raised text-fg-tertiary">
								<User size={16} />
							</span>
							<div class="min-w-0 flex-1">
								<p class="text-caption text-fg-tertiary">
									<b class="text-fg-secondary">{comment.author_name || t('anonymous')}</b>
									· <span title={absoluteTime(comment.created_at)}>{timeAgo(comment.created_at)}</span>
								</p>
								<p class="mt-0.5 text-body-sm break-words text-fg">{comment.comment}</p>
							</div>
						</li>
					{/each}
				</ul>
			{:else}
				<p class="text-label font-normal text-fg-tertiary">{t('no_updates')}</p>
			{/if}
		</section>
	</div>
{/snippet}

{#snippet footer()}
	<form class="flex gap-2 border-t border-line-subtle bg-surface-sheet px-3 py-2.5" onsubmit={publishComment}>
		<input
			class="h-11 min-w-0 flex-1 rounded-md border border-line-input bg-surface-input px-3.5 text-body text-fg outline-none placeholder:text-fg-tertiary focus:border-[var(--border-focus)] focus:shadow-[0_0_0_3px_var(--accent-tint-strong)]"
			placeholder={t('add_update')}
			aria-label={t('add_update')}
			maxlength="2000"
			bind:value={draft}
		/>
		<button
			type="submit"
			aria-label={t('post_update')}
			title={t('post_update')}
			disabled={busy || !draft.trim()}
			class="press grid h-11 w-11 shrink-0 place-items-center rounded-md bg-accent text-fg-on-accent hover:bg-accent-hover disabled:opacity-45"
		>
			<SendHorizontal size={20} />
		</button>
	</form>
{/snippet}

{#if chrome.desktop}
	<aside
		aria-label={incident.title}
		class="rise fixed top-16 right-0 bottom-0 z-50 flex w-[420px] flex-col border-l border-line-subtle bg-surface-sheet shadow-[-12px_0_40px_rgba(0,0,0,.35)]"
	>
		{@render header()}
		<div class="min-h-0 flex-1 overflow-y-auto overscroll-contain">{@render body()}</div>
		{@render footer()}
	</aside>
{:else}
	<BottomSheet bind:snap {onClose} label={incident.title} {header} {footer}>
		{@render body()}
	</BottomSheet>
{/if}

{#if viewer !== null && media[viewer]}
	{@const url = media[viewer]}
	<div role="dialog" aria-label={incident.title} class="fixed inset-0 z-[80] flex flex-col bg-[#000] text-white">
		<div class="flex items-center justify-between px-2 pt-[calc(env(safe-area-inset-top)+8px)] pb-2">
			<IconButton icon={X} label={t('close')} variant="media" onclick={() => (viewer = null)} />
			<span class="num text-body-sm font-bold">{viewer + 1} / {media.length}</span>
			<a
				href={url}
				download
				target="_blank"
				rel="noopener"
				aria-label={t('save')}
				title={t('save')}
				class="grid h-11 w-11 place-items-center rounded-md border border-[rgba(255,255,255,.12)] bg-[rgba(7,9,12,.66)] text-white"
			>
				<Download size={20} />
			</a>
		</div>
		<div class="relative min-h-0 flex-1">
			{#if isVideo(url)}
				<!-- svelte-ignore a11y_media_has_caption -->
				<video class="h-full w-full object-contain" src={url} controls playsinline></video>
			{:else}
				<img class="h-full w-full object-contain" src={url} alt={incident.title} />
			{/if}
			{#if media.length > 1}
				<IconButton icon={ChevronLeft} label={t('previous')} variant="media" class="absolute top-[calc(50%-22px)] left-2" onclick={() => (viewer = ((viewer ?? 0) - 1 + media.length) % media.length)} />
				<IconButton icon={ChevronRight} label={t('next')} variant="media" class="absolute top-[calc(50%-22px)] right-2" onclick={() => (viewer = ((viewer ?? 0) + 1) % media.length)} />
			{/if}
		</div>
		<p class="px-4 pt-3 pb-[calc(env(safe-area-inset-bottom)+16px)] text-label font-normal text-white/75">{incident.title}</p>
	</div>
{/if}
