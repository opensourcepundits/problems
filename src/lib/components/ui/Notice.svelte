<script lang="ts">
	import { CircleAlert, CircleCheck, Info, ShieldCheck, TriangleAlert, WifiOff } from 'lucide-svelte';
	import type { Snippet } from 'svelte';

	type Tone = 'info' | 'privacy' | 'warning' | 'danger' | 'success' | 'offline';

	let {
		tone = 'info',
		title,
		action,
		children,
		class: extra = ''
	}: { tone?: Tone; title?: string; action?: Snippet; children?: Snippet; class?: string } = $props();

	const looks = {
		info: [Info, 'var(--accent-tint)', 'var(--text-accent)'],
		privacy: [ShieldCheck, 'var(--accent-tint)', 'var(--text-accent)'],
		warning: [TriangleAlert, 'rgba(245,184,61,.12)', 'var(--color-warning-400)'],
		danger: [CircleAlert, 'var(--alarm-tint)', 'var(--color-alarm-400)'],
		success: [CircleCheck, 'rgba(62,207,142,.12)', 'var(--color-status-verified)'],
		offline: [WifiOff, 'rgba(245,184,61,.12)', 'var(--color-warning-400)']
	} as const;
	const look = $derived(looks[tone]);
	const Glyph = $derived(look[0]);
</script>

<div
	role={tone === 'danger' ? 'alert' : undefined}
	class="flex items-start gap-2.5 rounded-md px-3 py-2.5 {extra}"
	style="background:{look[1]}"
>
	<span class="mt-px shrink-0" style="color:{look[2]}"><Glyph size={18} /></span>
	<div class="min-w-0 flex-1 text-label font-normal text-fg-secondary">
		{#if title}<p class="font-bold text-fg">{title}</p>{/if}
		{@render children?.()}
	</div>
	{#if action}<div class="shrink-0 self-center">{@render action()}</div>{/if}
</div>
