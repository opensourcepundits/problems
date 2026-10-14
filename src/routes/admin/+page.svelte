<script lang="ts">
	let { data, form } = $props();
	let show = $state<'all' | 'visible' | 'hidden'>('all');

	const rows = $derived(
		data.incidents.filter((incident) => {
			if (show === 'hidden') return incident.hidden;
			if (show === 'visible') return !incident.hidden;
			return true;
		})
	);

	function when(value: string) {
		return new Date(value).toLocaleString();
	}
</script>

<section class="mx-auto flex h-full w-full max-w-3xl flex-col gap-4 overflow-y-auto px-4 py-6">
	<div class="flex items-start justify-between gap-3">
		<div>
			<p class="text-xs font-semibold tracking-[0.16em] text-red-300 uppercase">Admin</p>
			<h1 class="text-2xl font-semibold text-white">Reports</h1>
		</div>
		{#if data.authed}
			<form method="POST" action="?/logout">
				<button class="rounded-full border border-slate-600 px-3 py-1.5 text-sm text-slate-200" type="submit">
					Sign out
				</button>
			</form>
		{/if}
	</div>

	{#if !data.configured}
		<p class="rounded-2xl bg-amber-950 px-4 py-3 text-sm text-amber-100">
			Set ADMIN_USERNAME, ADMIN_PASSWORD, and SUPABASE_SECRET_KEY in the server environment. Then run
			supabase/admin.sql once in the Supabase SQL editor.
		</p>
	{:else if !data.authed}
		<form method="POST" action="?/login" class="max-w-sm space-y-3 rounded-3xl bg-slate-900 p-5">
			<label class="block text-sm text-slate-300">
				Username
				<input
					class="mt-1 w-full rounded-xl border border-slate-700 bg-slate-950 px-3 py-2 text-white outline-none focus:border-red-500"
					name="username"
					autocomplete="username"
					required
				/>
			</label>
			<label class="block text-sm text-slate-300">
				Password
				<input
					class="mt-1 w-full rounded-xl border border-slate-700 bg-slate-950 px-3 py-2 text-white outline-none focus:border-red-500"
					name="password"
					type="password"
					autocomplete="current-password"
					required
				/>
			</label>
			{#if form?.error}
				<p class="text-sm text-red-300">{form.error}</p>
			{/if}
			<button class="w-full rounded-2xl bg-red-600 py-3 font-semibold text-white" type="submit">Sign in</button>
		</form>
	{:else}
		{#if form?.error || data.error}
			<p class="rounded-2xl bg-red-950 px-4 py-3 text-sm text-red-100">{form?.error || data.error}</p>
		{/if}
		<p class="text-sm text-slate-400">
			Hidden reports stay saved and are left off the public map.
		</p>
		<div class="flex gap-2 text-sm">
			{#each ['all', 'visible', 'hidden'] as item (item)}
				<button
					type="button"
					class="rounded-full px-3 py-1.5 {show === item ? 'bg-white text-slate-950' : 'bg-slate-900 text-slate-200'}"
					aria-pressed={show === item}
					onclick={() => (show = item as typeof show)}
				>
					{item === 'all' ? 'All' : item === 'visible' ? 'On map' : 'Hidden'}
				</button>
			{/each}
		</div>
		<ul class="space-y-2 pb-8">
			{#each rows as incident (incident.id)}
				<li class="flex items-center justify-between gap-3 rounded-2xl bg-slate-900 px-4 py-3 {incident.hidden ? 'opacity-70' : ''}">
					<div class="min-w-0">
						<p class="truncate font-medium text-white">{incident.title}</p>
						<p class="mt-1 text-xs text-slate-400">
							{incident.category} · {incident.severity} · {incident.status} · {when(incident.created_at)}
						</p>
						{#if incident.description}
							<p class="mt-1 line-clamp-2 text-sm text-slate-300">{incident.description}</p>
						{/if}
					</div>
					<form method="POST" action="?/visibility">
						<input type="hidden" name="id" value={incident.id} />
						<input type="hidden" name="hidden" value={incident.hidden ? 'false' : 'true'} />
						<button
							class="shrink-0 rounded-full px-3 py-2 text-sm font-semibold {incident.hidden ? 'bg-white text-slate-950' : 'bg-red-600 text-white'}"
							type="submit"
						>
							{incident.hidden ? 'Show on map' : 'Hide from map'}
						</button>
					</form>
				</li>
			{:else}
				<li class="text-sm text-slate-500">No reports in this list.</li>
			{/each}
		</ul>
	{/if}
</section>
