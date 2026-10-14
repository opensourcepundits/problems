<script lang="ts">
	import { LoaderCircle } from 'lucide-svelte';
	import { t } from '$lib/i18n/index.svelte';

	let {
		state = 'live',
		count = 0,
		windowLabel,
		updated,
		class: extra = ''
	}: {
		state?: 'live' | 'updating' | 'offline' | 'error';
		count?: number;
		windowLabel: string;
		updated: string;
		class?: string;
	} = $props();

	const dot = $derived(
		{
			live: 'var(--color-success-400)',
			updating: 'var(--accent)',
			offline: 'var(--color-warning-400)',
			error: 'var(--color-alarm-400)'
		}[state]
	);
	const line = $derived(
		state === 'offline'
			? t('offline_saved')
			: state === 'error'
				? t('could_not_update')
				: state === 'updating'
					? t('updating')
					: t('updated', { t: updated })
	);
	const lineColor = $derived(
		state === 'error' ? 'text-alarm-400' : state === 'offline' ? 'text-warning-400' : 'text-fg-tertiary'
	);
</script>

<div role="status" aria-live="polite" class="flex min-w-0 items-center gap-2 {extra}">
	{#if state === 'updating'}
		<LoaderCircle size={14} class="spin shrink-0 text-accent" />
	{:else}
		<span
			class="h-2 w-2 shrink-0 rounded-full {state === 'live' ? 'live-dot' : ''}"
			style="background:{dot};box-shadow:0 0 0 3px {state === 'live' ? 'rgba(62,207,142,.18)' : 'transparent'}"
		></span>
	{/if}
	<div class="min-w-0">
		<p class="flex min-w-0 text-body-sm font-bold whitespace-nowrap text-fg">
			<span class="truncate"><span class="num">{count}</span> {t('reports', { n: count })}</span>
			<span class="shrink-0 font-semibold text-fg-tertiary max-[399px]:hidden lg:inline">&nbsp;· <span class="num">{windowLabel}</span></span>
		</p>
		<p class="truncate text-micro font-normal {lineColor}">{line}</p>
	</div>
</div>
