<script lang="ts">
	import { SEVERITY_META } from '$lib/tokens';
	import type { Severity } from '$lib/types';

	let { severity, size = 12 }: { severity: Severity; size?: number } = $props();
	const level = $derived(SEVERITY_META[severity]?.rank ?? 1);
</script>

<span aria-hidden="true" class="inline-flex items-end gap-0.5" style="height:{size}px">
	{#each [1, 2, 3, 4] as step (step)}
		<span
			class="w-[3px] rounded-[1px]"
			style="height:{Math.round(size * (0.35 + step * 0.1625))}px;background:{step <= level
				? `var(--color-sev-${severity})`
				: 'var(--border-strong)'}"
		></span>
	{/each}
</span>
