<script lang="ts" module>
	let collapsed = $state(false);
	let remembered = '';
	let timer: ReturnType<typeof setTimeout> | undefined;

	function storageKey(message: string, severity: string) {
		return `cr-alert:${severity}:${message}`;
	}

	function write(message: string, severity: string) {
		try {
			sessionStorage.setItem(storageKey(message, severity), collapsed ? '1' : '0');
		} catch {
			// non-fatal
		}
	}

	function arm(message: string, severity: string) {
		clearTimeout(timer);
		timer = setTimeout(() => {
			collapsed = true;
			write(message, severity);
		}, 6500);
	}

	/** Shared by the mobile and desktop copies so they fold together. */
	function sync(message: string, severity: string) {
		const key = storageKey(message, severity);
		if (remembered === key) return;
		remembered = key;
		clearTimeout(timer);
		try {
			collapsed = sessionStorage.getItem(key) === '1';
		} catch {
			collapsed = false;
		}
		if (!collapsed) arm(message, severity);
	}

	function toggleShared(message: string, severity: string) {
		clearTimeout(timer);
		collapsed = !collapsed;
		write(message, severity);
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
		sync(message, severity);
	});

	function toggle() {
		if (preview) {
			previewCollapsed = !previewCollapsed;
			return;
		}
		toggleShared(message, severity);
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
