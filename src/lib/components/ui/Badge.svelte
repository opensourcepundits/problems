<script lang="ts">
	import type { Snippet } from 'svelte';
	import type { IconComponent } from './icons';

	let { icon, children }: { icon?: IconComponent; children: Snippet } = $props();
</script>

<span
	class="inline-flex h-[26px] w-fit items-center gap-[5px] rounded-sm border border-line-subtle bg-surface-raised px-[9px] text-caption font-bold whitespace-nowrap text-fg-secondary"
>
	{#if icon}
		{@const Glyph = icon}
		<Glyph size={14} strokeWidth={2.25} />
	{/if}
	{@render children()}
</span>
