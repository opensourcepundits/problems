<script lang="ts">
	import { goto } from '$app/navigation';
	import { createSupabaseBrowserClient } from '$lib/supabaseClient';
	import { pushToast } from '$lib/ui.svelte';

	let fullName = $state('');
	let phone = $state('');
	let email = $state('');
	let password = $state('');
	let busy = $state(false);
	let error = $state('');
	let pendingEmail = $state(false);

	async function submit(event: SubmitEvent) {
		event.preventDefault();
		const supabase = createSupabaseBrowserClient();
		if (!supabase) {
			error = 'Supabase is not configured.';
			return;
		}
		busy = true;
		error = '';
		const { data: result, error: signUpError } = await supabase.auth.signUp({
			email: email.trim(),
			password,
			options: {
				data: {
					full_name: fullName.trim(),
					phone_number: phone.trim()
				}
			}
		});
		busy = false;
		if (signUpError) {
			error = signUpError.message;
			return;
		}
		if (!result.session) {
			pendingEmail = true;
			return;
		}
		pushToast('Account created.');
		await goto('/');
	}
</script>

<svelte:head><title>Create account · Crisis Report</title></svelte:head>

<section class="grid min-h-full place-items-center px-4 py-10">
	<form class="w-full max-w-md rounded-3xl border border-white/10 bg-slate-900 p-6 shadow-2xl" onsubmit={submit}>
		<p class="text-xs font-semibold tracking-[0.16em] text-red-300 uppercase">Account</p>
		<h1 class="mt-1 text-2xl font-semibold">Create an account</h1>
		{#if pendingEmail}
			<p class="mt-4 rounded-2xl bg-emerald-950 px-3 py-3 text-sm text-emerald-100">
				Check {email} to confirm the account, then sign in.
			</p>
		{:else}
			<label class="mt-5 block text-sm text-slate-300">
				Full name
				<input class="mt-1 w-full rounded-xl border border-slate-700 bg-slate-950 px-3 py-2" required maxlength="120" autocomplete="name" bind:value={fullName} />
			</label>
			<label class="mt-3 block text-sm text-slate-300">
				Phone
				<input class="mt-1 w-full rounded-xl border border-slate-700 bg-slate-950 px-3 py-2" maxlength="32" autocomplete="tel" bind:value={phone} />
			</label>
			<label class="mt-3 block text-sm text-slate-300">
				Email
				<input class="mt-1 w-full rounded-xl border border-slate-700 bg-slate-950 px-3 py-2" type="email" autocomplete="email" required bind:value={email} />
			</label>
			<label class="mt-3 block text-sm text-slate-300">
				Password
				<input class="mt-1 w-full rounded-xl border border-slate-700 bg-slate-950 px-3 py-2" type="password" autocomplete="new-password" required minlength="8" bind:value={password} />
			</label>
			{#if error}<p class="mt-3 text-sm text-red-300">{error}</p>{/if}
			<button class="mt-5 w-full rounded-2xl bg-red-600 py-3 font-semibold disabled:opacity-60" disabled={busy}>
				{busy ? 'Creating…' : 'Create account'}
			</button>
		{/if}
		<p class="mt-4 text-sm text-slate-400">
			Already registered? <a class="text-white underline" href="/auth/login">Sign in</a>
		</p>
	</form>
</section>
