<script lang="ts">
	import { MapPin } from 'lucide-svelte';

	let { size = 32, withName = false }: { size?: number; withName?: boolean } = $props();
	const dot = $derived(Math.max(5, Math.round(size * 0.18)));
</script>

<span class="inline-flex items-center gap-2.5">
	<span
		role={withName ? undefined : 'img'}
		aria-label={withName ? undefined : 'Crisis Report'}
		aria-hidden={withName || undefined}
		class="relative grid shrink-0 place-items-center bg-beacon-400 text-ink-0"
		style="width:{size}px;height:{size}px;border-radius:{Math.round(size * 0.28)}px"
	>
		<MapPin size={Math.round(size * 0.56)} strokeWidth={2.5} />
		<span
			class="absolute rounded-full bg-alarm-600"
			style="right:{Math.round(size * 0.14)}px;top:{Math.round(size * 0.14)}px;width:{dot}px;height:{dot}px;box-shadow:0 0 0 {Math.max(1.5, size * 0.05)}px var(--color-beacon-400)"
		></span>
	</span>
	{#if withName}
		<span class="text-[17px] leading-[22px] font-heavy tracking-tight whitespace-nowrap text-fg">Crisis Report</span>
	{/if}
</span>
