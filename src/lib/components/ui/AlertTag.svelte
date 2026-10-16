<script lang="ts" module>
	const HOLD_MS = 4000;

	let collapsed = $state(false);
	let remembered = '';
	let timer: ReturnType<typeof setTimeout> | undefined;

	function arm() {
		clearTimeout(timer);
		timer = setTimeout(() => {
			collapsed = true;
		}, HOLD_MS);
	}

	/** Show the full notice, then fold it. Shared so the mobile and desktop copies move together. */
	function present(message: string, severity: string) {
		const key = `${severity}:${message}`;
		if (remembered === key) return;
		remembered = key;
		collapsed = false;
		arm();
	}

	function toggleShared() {
		clearTimeout(timer);
		collapsed = !collapsed;
		if (!collapsed) arm();
	}
</script>

<script lang="ts">
	import { ChevronLeft, TriangleAlert } from 'lucide-svelte';
	import { t } from '$lib/i18n/index.svelte';
	import type { Severity } from '$lib/types';

	let {
		message,
		severity,
		preview = false,
		class: extra = ''
	}: {
		message: string;
		severity: Severity;
		/** Admin preview: fold on click, without the timer or saved state. */
		preview?: boolean;
		class?: string;
	} = $props();

	let previewCollapsed = $state(false);
	const folded = $derived(preview ? previewCollapsed : collapsed);
	const critical = $derived(severity === 'critical');

	$effect(() => {
		if (preview) return;
		present(message, severity);
	});

	function toggle() {
		if (preview) {
			previewCollapsed = !previewCollapsed;
			return;
		}
		toggleShared();
	}
</script>

<button
	type="button"
	aria-expanded={!folded}
	aria-label={folded ? `${t('alert_show')}: ${message}` : `${message}. ${t('alert_hide')}`}
	title={message}
	class="inline-flex h-11 min-w-11 max-w-full items-center overflow-hidden rounded-md border text-left transition-[max-width] duration-300 ease-out motion-reduce:transition-none {extra}"
	style="--sev: var(--color-sev-{severity}); color: var(--sev); background: color-mix(in oklab, var(--sev) 18%, transparent); border-color: color-mix(in oklab, var(--sev) 55%, transparent); max-width: {folded
		? '44px'
		: 'min(360px, 100%)'}"
	onclick={toggle}
>
	<span class="grid h-11 w-11 shrink-0 place-items-center" class:live-dot={folded && critical}>
		<TriangleAlert size={18} aria-hidden="true" />
	</span>
	<span class="min-w-0 flex-1 truncate text-label font-bold whitespace-nowrap">{message}</span>
	<ChevronLeft size={16} aria-hidden="true" class="mr-2.5 shrink-0 opacity-70" />
</button>
