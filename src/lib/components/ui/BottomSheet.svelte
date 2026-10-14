<script lang="ts">
	import type { Snippet } from 'svelte';
	import { t } from '$lib/i18n/index.svelte';

	type Snap = 'peek' | 'full';

	let {
		snap = $bindable('peek'),
		onClose,
		label,
		scrim = true,
		lockFull = false,
		header,
		footer,
		children
	}: {
		snap?: Snap;
		onClose: () => void;
		label: string;
		scrim?: boolean;
		lockFull?: boolean;
		header?: Snippet;
		footer?: Snippet;
		children: Snippet;
	} = $props();

	const SNAP: Record<Snap, number> = { peek: 0.5, full: 0.94 };
	let section = $state<HTMLDivElement | undefined>(undefined);
	let drag = $state<number | null>(null);
	const fraction = $derived(drag ?? SNAP[lockFull ? 'full' : snap]);
	const reduced =
		typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

	function parentHeight() {
		return section?.parentElement?.clientHeight ?? window.innerHeight;
	}

	function down(event: PointerEvent) {
		const height = parentHeight();
		const y0 = event.clientY;
		const f0 = SNAP[lockFull ? 'full' : snap];
		const clamp = (y: number) => Math.max(0.15, Math.min(0.96, f0 + (y0 - y) / height));
		(event.currentTarget as HTMLElement).setPointerCapture(event.pointerId);
		const move = (next: PointerEvent) => (drag = clamp(next.clientY));
		const up = (next: PointerEvent) => {
			const f = clamp(next.clientY);
			drag = null;
			window.removeEventListener('pointermove', move);
			window.removeEventListener('pointerup', up);
			if (Math.abs(next.clientY - y0) < 6) {
				if (!lockFull) snap = snap === 'peek' ? 'full' : 'peek';
				return;
			}
			if (f < 0.32) onClose();
			else if (!lockFull) snap = f > 0.72 ? 'full' : 'peek';
		};
		window.addEventListener('pointermove', move);
		window.addEventListener('pointerup', up);
	}

	function key(event: KeyboardEvent) {
		if ((event.key === 'Enter' || event.key === ' ') && !lockFull) {
			event.preventDefault();
			snap = snap === 'peek' ? 'full' : 'peek';
		}
	}
</script>

{#if scrim}
	<button
		type="button"
		tabindex="-1"
		aria-label={t('close')}
		class="fixed inset-0 z-[49] bg-[var(--scrim)]"
		style="opacity:{Math.max(0, (fraction - 0.45) / 0.5)};transition:{drag !== null || reduced
			? 'none'
			: 'opacity 280ms'};pointer-events:{fraction > 0.72 ? 'auto' : 'none'}"
		onclick={onClose}
	></button>
{/if}
<div
	bind:this={section}
	role="dialog"
	aria-label={label}
	class="fixed inset-x-0 bottom-0 z-50 flex flex-col rounded-t-xl border-t border-line-strong bg-surface-sheet shadow-sheet"
	style="height:{fraction * 100}dvh;transition:{drag !== null || reduced ? 'none' : 'height 280ms var(--ease-sheet)'}"
>
	<div
		role="button"
		tabindex="0"
		aria-label={snap === 'peek' && !lockFull ? t('expand') : t('collapse')}
		class="grid h-[22px] shrink-0 cursor-grab touch-none place-items-center"
		onpointerdown={down}
		onkeydown={key}
	>
		<span class="h-[5px] w-10 rounded-[3px] bg-line-strong"></span>
	</div>
	{@render header?.()}
	<div class="min-h-0 flex-1 overflow-y-auto overscroll-contain">{@render children()}</div>
	{#if footer}
		<div class="shrink-0 bg-surface-sheet pb-[env(safe-area-inset-bottom)]">{@render footer()}</div>
	{/if}
</div>
