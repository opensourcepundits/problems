<script lang="ts">
	import { page } from '$app/state';
	import { CircleAlert, CircleCheck, Download, Info, Share, Siren, SquarePlus, WifiOff, X } from 'lucide-svelte';
	import { onMount } from 'svelte';
	import BrandMark from '$lib/components/ui/BrandMark.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import { initLocale, t } from '$lib/i18n/index.svelte';
	import { chrome, dismissToast, initTheme, toaster, watchBreakpoint } from '$lib/ui.svelte';
	import '../app.css';

	interface BeforeInstallPromptEvent extends Event {
		prompt: () => Promise<void>;
		userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>;
	}

	let { children } = $props();

	let showInstall = $state(false);
	let iosHint = $state(false);
	let deferredInstall = $state<BeforeInstallPromptEvent | null>(null);
	const onMap = $derived(page.url.pathname === '/');

	const toneIcon = { ok: CircleCheck, err: CircleAlert, info: Info, sos: Siren, offline: WifiOff };
	const toneColor = {
		ok: 'var(--color-success-400)',
		err: 'var(--color-alarm-400)',
		info: 'var(--accent)',
		sos: '#fff',
		offline: 'var(--color-warning-400)'
	};

	onMount(() => {
		initTheme();
		initLocale();
		const stopBreakpoint = watchBreakpoint();

		const standalone = window.matchMedia('(display-mode: standalone)').matches;
		let dismissed = false;
		try {
			dismissed = sessionStorage.getItem('install-dismissed') === '1';
		} catch {
			dismissed = false;
		}
		const ios = /iphone|ipad|ipod/i.test(window.navigator.userAgent);
		// In-app browsers (Instagram, Facebook) cannot install, so they get no prompt.
		const inApp = /FBAN|FBAV|Instagram/i.test(window.navigator.userAgent);
		if (!standalone && !dismissed && ios && !inApp) {
			iosHint = true;
			showInstall = true;
		}

		const onPrompt = (event: Event) => {
			event.preventDefault();
			deferredInstall = event as BeforeInstallPromptEvent;
			if (!dismissed) showInstall = true;
		};
		window.addEventListener('beforeinstallprompt', onPrompt);

		void import('virtual:pwa-register')
			.then(({ registerSW }) => registerSW({ immediate: true }))
			.catch(() => undefined);

		return () => {
			stopBreakpoint();
			window.removeEventListener('beforeinstallprompt', onPrompt);
		};
	});

	async function install() {
		if (!deferredInstall) return;
		await deferredInstall.prompt();
		showInstall = false;
		deferredInstall = null;
	}

	function dismissInstall() {
		try {
			sessionStorage.setItem('install-dismissed', '1');
		} catch {
			// non-fatal
		}
		showInstall = false;
	}
</script>

<svelte:head>
	<title>Crisis Report</title>
</svelte:head>

<div class="flex h-dvh flex-col bg-surface-canvas text-fg">
	<main class="relative min-h-0 flex-1">
		{@render children()}
	</main>
</div>

{#if showInstall && onMap && !chrome.sheetOpen}
	<div
		class="rise fixed inset-x-3 bottom-[calc(118px+env(safe-area-inset-bottom))] z-[25] flex flex-col gap-3 rounded-lg border border-line-strong bg-surface-sheet p-3.5 shadow-pop lg:right-[120px] lg:bottom-6 lg:left-auto lg:w-[380px]"
	>
		<div class="flex items-start gap-3">
			<BrandMark size={44} />
			<div class="min-w-0 flex-1">
				<p class="text-body leading-[22px] font-bold">{t('install_title')}</p>
				<p class="mt-0.5 text-label font-normal text-fg-secondary">{t('install_body')}</p>
			</div>
		</div>
		{#if iosHint && !deferredInstall}
			<ol class="flex flex-col gap-2 text-label font-normal text-fg-secondary">
				{#each [[Share, t('ios_step1')], [SquarePlus, t('ios_step2')]] as const as [Glyph, label], index (index)}
					<li class="flex items-center gap-2.5">
						<span class="num w-[22px] font-bold text-fg-tertiary">{index + 1}</span>
						<span class="grid h-8 w-8 place-items-center rounded-sm bg-surface-raised text-fg-accent"><Glyph size={18} /></span>
						{label}
					</li>
				{/each}
			</ol>
		{/if}
		<div class="flex justify-end gap-2">
			<Button variant="ghost" size="sm" onclick={dismissInstall}>{t('not_now')}</Button>
			{#if deferredInstall}
				<Button size="sm" icon={Download} onclick={install}>{t('install')}</Button>
			{:else}
				<Button variant="secondary" size="sm" onclick={dismissInstall}>{t('got_it')}</Button>
			{/if}
		</div>
	</div>
{/if}

<div
	class="pointer-events-none fixed inset-x-3 z-[70] flex flex-col-reverse gap-2 lg:top-[76px] lg:right-4 lg:bottom-auto lg:left-auto lg:w-[380px] lg:flex-col {chrome.sheetOpen
		? 'bottom-[calc(16px+env(safe-area-inset-bottom))]'
		: 'bottom-[calc(112px+env(safe-area-inset-bottom))]'}"
>
	{#each toaster.items as toast (toast.id)}
		{@const Glyph = toneIcon[toast.tone]}
		{@const sos = toast.tone === 'sos'}
		<div
			role="status"
			aria-live="polite"
			class="rise pointer-events-auto flex items-start gap-3 rounded-lg border py-3 pr-3 pl-3.5 shadow-pop {sos
				? 'border-transparent bg-alarm-600 text-white'
				: 'border-[rgba(255,255,255,.1)] bg-ink-250 text-ink-900'}"
		>
			<span class="mt-0.5 shrink-0" style="color:{toneColor[toast.tone]}"><Glyph size={20} /></span>
			<div class="min-w-0 flex-1 text-body-sm">
				{#if toast.title}<p class="font-bold">{toast.title}</p>{/if}
				<p class={sos ? 'text-white/90' : toast.title ? 'text-ink-700' : ''}>{toast.message}</p>
			</div>
			{#if toast.action}
				<button
					type="button"
					class="h-9 self-center rounded-[10px] px-2.5 text-label font-bold {sos ? 'text-white underline' : 'text-beacon-300'}"
					onclick={() => {
						toast.action?.run();
						dismissToast(toast.id);
					}}>{toast.action.label}</button
				>
			{/if}
			<button
				type="button"
				aria-label={t('dismiss')}
				class="-mt-1 -mr-1 grid h-8 w-8 shrink-0 place-items-center rounded-sm opacity-70 hover:opacity-100"
				onclick={() => dismissToast(toast.id)}
			>
				<X size={16} />
			</button>
		</div>
	{/each}
</div>
