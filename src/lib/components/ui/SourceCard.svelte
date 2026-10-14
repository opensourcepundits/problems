<script lang="ts">
	import { ExternalLink, Facebook, Instagram, Link, Newspaper, Play, SquarePlay, Twitter, X, Youtube } from 'lucide-svelte';
	import { t } from '$lib/i18n/index.svelte';
	import type { SourceInfo } from '$lib/sources';

	let {
		source,
		onRemove,
		embeddable = true
	}: {
		source: SourceInfo;
		/** Set in the report form: shows a remove button instead of the embed. */
		onRemove?: () => void;
		embeddable?: boolean;
	} = $props();

	let playing = $state(false);

	const Glyph = $derived(
		{
			Facebook: Facebook,
			Instagram: Instagram,
			YouTube: Youtube,
			X: Twitter,
			TikTok: SquarePlay
		}[source.site] ?? (source.kind === 'article' ? Newspaper : Link)
	);
	const heading = $derived(t(`source_${source.kind}`, { site: source.site }));
	const showEmbed = $derived(embeddable && !onRemove && !!source.embed);

	$effect(() => {
		void source.url;
		playing = false;
	});
</script>

<section aria-label={t('source_title')} class="overflow-hidden rounded-lg border border-line-subtle bg-surface-raised">
	<div class="flex min-h-[64px] items-center gap-3 py-2.5 pr-1.5 pl-3">
		<span class="grid h-10 w-10 shrink-0 place-items-center rounded-md border border-line-subtle bg-surface-sheet text-fg">
			<Glyph size={20} />
		</span>
		<div class="min-w-0 flex-1">
			<p class="truncate text-body-sm font-bold text-fg">{heading}</p>
			<p class="truncate text-caption text-fg-tertiary">
				{#if source.publisher}<span class="font-bold text-fg-secondary">{source.publisher}</span>{' · '}{/if}{source.display}
			</p>
		</div>
		{#if onRemove}
			<button
				type="button"
				aria-label={t('remove_link')}
				title={t('remove_link')}
				class="press grid h-11 w-11 shrink-0 place-items-center rounded-md text-fg-secondary hover:bg-surface-raised-hover"
				onclick={onRemove}
			>
				<X size={20} />
			</button>
		{/if}
	</div>

	{#if showEmbed && source.embed}
		<div class="relative border-t border-line-subtle bg-[#000] transition-[aspect-ratio] duration-200 {playing ? 'aspect-[4/5] lg:aspect-[16/11]' : 'aspect-video'}">
			{#if playing}
				<iframe
					src={source.embed}
					title={heading}
					class="absolute inset-0 h-full w-full border-0"
					allow="autoplay; clipboard-write; encrypted-media; picture-in-picture; web-share"
					allowfullscreen
					loading="lazy"
				></iframe>
			{:else}
				<div class="absolute inset-0 grid place-items-center bg-[repeating-linear-gradient(135deg,var(--color-ink-100)_0_12px,var(--color-ink-150)_12px_24px)]">
					<div class="flex flex-col items-center gap-3 px-6 text-center">
						<button
							type="button"
							class="press inline-flex h-13 items-center gap-2 rounded-[14px] bg-accent px-5 font-bold text-fg-on-accent shadow-pop hover:bg-accent-hover"
							onclick={() => (playing = true)}
						>
							<Play size={20} fill="currentColor" />{t('play_here')}
						</button>
						<p class="max-w-[260px] text-caption text-ink-600">{t('embed_note')}</p>
					</div>
				</div>
			{/if}
		</div>
	{/if}

	{#if !onRemove}
		<a
			href={source.url}
			target="_blank"
			rel="noopener noreferrer nofollow"
			class="flex h-11 items-center justify-center gap-2 border-t border-line-subtle text-label font-bold text-fg-accent hover:bg-surface-raised-hover"
		>
			{t('open_on', { site: source.site })}<ExternalLink size={16} />
		</a>
	{/if}
</section>
