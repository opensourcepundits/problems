<script lang="ts">
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import { createSupabaseBrowserClient } from '$lib/supabaseClient';
	import { pushToast } from '$lib/ui.svelte';

	let email = $state('');
	let password = $state('');
	let busy = $state(false);
	let error = $state('');

	async function submit(event: SubmitEvent) {
		event.preventDefault();
		const supabase = createSupabaseBrowserClient();
		if (!supabase) {
			error = 'Supabase is not configured.';
			return;
		}
		busy = true;
		error = '';
		const { error: signInError } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
		busy = false;
		if (signInError) {
			error = signInError.message;
			return;
		}
		pushToast('Signed in.');
		const next = page.url.searchParams.get('next') || '/';
		await goto(next.startsWith('/') ? next : '/');
	}
</script>

<svelte:head><title>Sign in · Crisis Report</title></svelte:head>

<section class="grid min-h-full place-items-center px-4 py-10">
	<form class="w-full max-w-md rounded-3xl border border-white/10 bg-slate-900 p-6 shadow-2xl" onsubmit={submit}>
		<p class="text-xs font-semibold tracking-[0.16em] text-red-300 uppercase">Account</p>
		<h1 class="mt-1 text-2xl font-semibold">Sign in</h1>
		<p class="mt-2 text-sm text-slate-400">Reports, comments, votes, and SOS alerts are stored under your user id.</p>
		<label class="mt-5 block text-sm text-slate-300">
			Email
			<input class="mt-1 w-full rounded-xl border border-slate-700 bg-slate-950 px-3 py-2" type="email" autocomplete="email" required bind:value={email} />
		</label>
		<label class="mt-3 block text-sm text-slate-300">
			Password
			<input class="mt-1 w-full rounded-xl border border-slate-700 bg-slate-950 px-3 py-2" type="password" autocomplete="current-password" required minlength="8" bind:value={password} />
		</label>
		{#if error}<p class="mt-3 text-sm text-red-300">{error}</p>{/if}
		<button class="mt-5 w-full rounded-2xl bg-red-600 py-3 font-semibold disabled:opacity-60" disabled={busy}>
			{busy ? 'Signing in…' : 'Sign in'}
		</button>
		<p class="mt-4 text-sm text-slate-400">
			No account? <a class="text-white underline" href="/auth/signup">Create one</a>
		</p>
	</form>
</section>
