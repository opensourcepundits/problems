<script lang="ts">
	import { t } from '$lib/i18n/index.svelte';
	import type { Severity } from '$lib/types';
	import SeverityMeter from './SeverityMeter.svelte';

	let { severity }: { severity: Severity } = $props();
	const critical = $derived(severity === 'critical');
</script>

<span
	class="inline-flex h-[26px] w-fit items-center gap-1.5 rounded-sm border pr-[9px] pl-2 text-caption font-bold whitespace-nowrap {critical
		? 'border-[rgba(255,77,77,.45)] bg-[var(--alarm-tint)] text-alarm-400'
		: 'border-line-subtle bg-surface-raised text-fg'}"
>
	<SeverityMeter {severity} />{t(`sev_${severity}`)}
</span>
