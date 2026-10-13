<script lang="ts">
	import { page } from '$app/state';
	import { Download, Siren } from 'lucide-svelte';
	import { onMount } from 'svelte';
	import EmergencySosButton from '$lib/components/EmergencySosButton.svelte';
	import { supabaseConfigProblem } from '$lib/supabaseClient';
	import { toaster } from '$lib/ui.svelte';
	import '../app.css';

	interface BeforeInstallPromptEvent extends Event {
		prompt: () => Promise<void>;
		userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>;
	}

	let { children } = $props();

	let showInstall = $state(false);
	let iosHint = $state(false);
	let deferredInstall = $state<BeforeInstallPromptEvent | null>(null);
	const configProblem = supabaseConfigProblem();
	const onMap = $derived(page.url.pathname === '/');

	onMount(() => {
		const standalone = window.matchMedia('(display-mode: standalone)').matches;
		const dismissed = sessionStorage.getItem('install-dismissed') === '1';
		const ios = /iphone|ipad|ipod/i.test(window.navigator.userAgent);
		if (!standalone && !dismissed && ios) {
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

		return () => window.removeEventListener('beforeinstallprompt', onPrompt);
	});

	async function install() {
		if (!deferredInstall) return;
		await deferredInstall.prompt();
		showInstall = false;
		deferredInstall = null;
	}

	function dismissInstall() {
		sessionStorage.setItem('install-dismissed', '1');
		showInstall = false;
	}
</script>

<svelte:head>
	<title>Crisis Report</title>
</svelte:head>

<div class="flex h-dvh flex-col bg-[#0b1220] text-slate-100">
	<header class="sticky top-0 z-30 flex items-center justify-between gap-3 border-b border-white/10 bg-[#0b1220]/95 px-4 py-3 backdrop-blur">
		<a href="/" class="inline-flex items-center gap-2 font-semibold tracking-tight">
			<span class="grid h-8 w-8 place-items-center rounded-lg bg-red-600 text-white"><Siren size={16} /></span>
			Crisis Report
		</a>
	</header>

	{#if configProblem}
		<p class="bg-amber-950 px-4 py-2 text-sm text-amber-100">{configProblem}</p>
	{/if}

	{#if showInstall}
		<div class="flex items-center justify-between gap-3 bg-red-950 px-4 py-2 text-sm text-red-50">
			<p>
				{#if iosHint && !deferredInstall}
					Install this app from the browser share menu, then Add to Home Screen.
				{:else}
					Install Crisis Report so the map shell stays available on a bad connection.
				{/if}
			</p>
			<div class="flex shrink-0 gap-2">
				{#if deferredInstall}
					<button type="button" class="inline-flex items-center gap-1 rounded-full bg-white px-3 py-1 font-medium text-red-700" onclick={install}>
						<Download size={14} /> Install
					</button>
				{/if}
				<button type="button" class="rounded-full px-2 py-1 text-red-100" onclick={dismissInstall}>Not now</button>
			</div>
		</div>
	{/if}

	<main class="relative min-h-0 flex-1">
		{@render children()}
	</main>
</div>

{#if onMap}
	<EmergencySosButton />
{/if}

<div class="pointer-events-none fixed top-20 right-3 z-[70] flex w-[min(100%-1.5rem,22rem)] flex-col gap-2">
	{#each toaster.items as toast (toast.id)}
		<p class="pointer-events-auto rounded-2xl px-4 py-3 text-sm shadow-xl {toast.tone === 'err' ? 'bg-red-700 text-white' : 'bg-white text-slate-950'}">
			{toast.message}
		</p>
	{/each}
</div>
