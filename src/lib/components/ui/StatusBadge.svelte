<script lang="ts">
	import { t } from '$lib/i18n/index.svelte';
	import type { Status } from '$lib/types';
	import { STATUS_ICON } from './icons';

	let { status }: { status: Status } = $props();
	const Glyph = $derived(STATUS_ICON[status] ?? STATUS_ICON.unverified);
	const look = $derived(
		{
			unverified: 'border-dashed border-line-strong bg-surface-raised text-fg-secondary',
			verified: 'border-transparent bg-[rgba(62,207,142,.14)] text-[var(--color-status-verified)]',
			resolved: 'border-line-subtle bg-surface-raised text-fg-secondary',
			debunked: 'border-line-subtle bg-surface-raised text-fg-tertiary'
		}[status]
	);
</script>

<span
	class="inline-flex h-[26px] w-fit items-center gap-[5px] rounded-sm border pr-[9px] pl-[7px] text-caption font-bold whitespace-nowrap {look}"
>
	<Glyph size={14} strokeWidth={2.25} />{t(`st_${status}`)}
</span>
