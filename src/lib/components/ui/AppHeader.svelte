<script lang="ts">
	import type { Snippet } from 'svelte';
	import BrandMark from './BrandMark.svelte';

	let { title, right }: { title?: string; right?: Snippet } = $props();
</script>

<header
	class="sticky top-0 z-30 flex h-[calc(60px+env(safe-area-inset-top))] shrink-0 items-center justify-between gap-3 border-b border-line-subtle bg-surface-canvas px-4 pt-[env(safe-area-inset-top)]"
>
	<div class="flex min-w-0 items-center gap-3">
		<a href="/" class="text-inherit no-underline"><BrandMark withName /></a>
		{#if title}
			<span class="h-5 w-px bg-line-strong"></span>
			<span class="text-body-sm font-bold text-fg-secondary">{title}</span>
		{/if}
	</div>
	{#if right}<div class="flex items-center gap-2">{@render right()}</div>{/if}
</header>
