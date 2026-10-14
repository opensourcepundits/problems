<script lang="ts">
	import { Eye, EyeOff, Lock, LogOut } from 'lucide-svelte';
	import AppHeader from '$lib/components/ui/AppHeader.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import CategoryTile from '$lib/components/ui/CategoryTile.svelte';
	import Notice from '$lib/components/ui/Notice.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import SeverityBadge from '$lib/components/ui/SeverityBadge.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import { CATEGORY_LABEL, isCategory, isSeverity, isStatus, type Category } from '$lib/types';

	// Admin stays in English.
	let { data, form } = $props();
	let show = $state<'all' | 'visible' | 'hidden'>('all');
	let query = $state('');

	const hiddenCount = $derived(data.incidents.filter((incident) => incident.hidden).length);
	const rows = $derived(
		data.incidents.filter((incident) => {
			if (show === 'hidden' && !incident.hidden) return false;
			if (show === 'visible' && incident.hidden) return false;
			return !query.trim() || incident.title.toLowerCase().includes(query.trim().toLowerCase());
		})
	);

	function categoryOf(incident: { category: string; is_sos: boolean }): Category {
		if (incident.is_sos) return 'sos';
		return isCategory(incident.category) ? incident.category : 'other';
	}

	function when(value: string) {
		const minutes = (Date.now() - new Date(value).getTime()) / 60000;
		if (minutes < 1) return 'just now';
		if (minutes < 60) return `${Math.round(minutes)} min ago`;
		if (minutes < 60 * 24) return `${Math.round(minutes / 60)} h ago`;
		return new Date(value).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
	}

	const input =
		'h-12 w-full rounded-md border border-line-input bg-surface-input px-3.5 text-body text-fg outline-none placeholder:text-fg-tertiary focus:border-[var(--border-focus)] focus:shadow-[0_0_0_3px_var(--accent-tint-strong)]';
	const grid = 'grid grid-cols-[minmax(0,1fr)_130px_120px_130px_80px_100px_150px] gap-3';
</script>

<svelte:head>
	<title>Admin · Crisis Report</title>
</svelte:head>

<div class="flex h-full flex-col">
	<AppHeader title="Admin">
		{#snippet right()}
			{#if data.authed}
				<form method="POST" action="?/logout">
					<Button variant="ghost" type="submit" icon={LogOut}>Sign out</Button>
				</form>
			{/if}
		{/snippet}
	</AppHeader>

	<div class="min-h-0 flex-1 overflow-y-auto">
		{#if !data.configured}
			<div class="mx-auto max-w-[720px] px-3 py-4">
				<Notice tone="warning" title="Admin is not configured">
					Set ADMIN_USERNAME, ADMIN_PASSWORD and SUPABASE_SECRET_KEY in the server environment, then run
					supabase/admin.sql once in the Supabase SQL editor.
				</Notice>
			</div>
		{:else if !data.authed}
			<div class="grid min-h-full place-items-center p-4">
				<form
					method="POST"
					action="?/login"
					class="flex w-full max-w-[380px] flex-col gap-3.5 rounded-xl border border-line-subtle bg-surface-sheet p-5"
				>
					<div class="flex items-center gap-3">
						<span class="grid h-10 w-10 place-items-center rounded-md bg-surface-raised text-fg-accent"><Lock size={20} /></span>
						<div>
							<h1 class="text-title-lg font-heavy">Moderator sign in</h1>
							<p class="text-label font-normal text-fg-tertiary">Hide or restore public reports.</p>
						</div>
					</div>
					{#if form?.error}<Notice tone="danger">{form.error}</Notice>{/if}
					<label class="flex flex-col gap-1.5 text-label font-bold text-fg-secondary">
						Username
						<input class={input} name="username" autocomplete="username" required />
					</label>
					<label class="flex flex-col gap-1.5 text-label font-bold text-fg-secondary">
						Password
						<input class={input} name="password" type="password" autocomplete="current-password" required />
					</label>
					<Button type="submit" size="lg" fullWidth>Sign in</Button>
				</form>
			</div>
		{:else}
			<div class="mx-auto flex max-w-[720px] flex-col gap-3.5 px-3 pt-4 pb-8 lg:max-w-[1120px] lg:px-6 lg:pt-6 lg:pb-10">
				<div class="flex flex-wrap items-end justify-between gap-3">
					<div>
						<h1 class="text-title-lg font-heavy lg:text-[28px] lg:leading-[34px]">Reports</h1>
						<p class="mt-0.5 text-label font-normal text-fg-tertiary">
							Hidden reports stay saved and are left off the public map.
						</p>
					</div>
					<input class="{input} !h-11 hidden lg:block lg:w-[280px]" placeholder="Search titles" aria-label="Search titles" bind:value={query} />
				</div>
				{#if form?.error || data.error}
					<Notice tone="danger">{form?.error || data.error}</Notice>
				{/if}
				<SegmentedControl
					label="Filter"
					value={show}
					onchange={(value) => (show = value)}
					class="w-full lg:w-fit [&>button]:flex-1 lg:[&>button]:flex-none"
					options={[
						{ value: 'all', label: `All · ${data.incidents.length}` },
						{ value: 'visible', label: `On map · ${data.incidents.length - hiddenCount}` },
						{ value: 'hidden', label: `Hidden · ${hiddenCount}` }
					]}
				/>

				{#snippet toggle(incident: (typeof rows)[number], extra = '')}
					<form method="POST" action="?/visibility" class={extra}>
						<input type="hidden" name="id" value={incident.id} />
						<input type="hidden" name="hidden" value={incident.hidden ? 'false' : 'true'} />
						<Button variant="secondary" size="sm" type="submit" icon={incident.hidden ? Eye : EyeOff}>
							{incident.hidden ? 'Show' : 'Hide'}
						</Button>
					</form>
				{/snippet}

				<!-- Mobile: cards -->
				<ul class="flex flex-col gap-2 lg:hidden">
					{#each rows as incident (incident.id)}
						<li class="flex gap-3 rounded-lg border border-line-subtle bg-surface-sheet p-3 {incident.hidden ? 'opacity-65' : ''}">
							<CategoryTile category={categoryOf(incident)} size={36} />
							<div class="min-w-0 flex-1">
								<p class="leading-[22px] font-bold">{incident.title}</p>
								<p class="mt-0.5 mb-2 text-caption text-fg-tertiary">
									{incident.address_hint ? `${incident.address_hint} · ` : ''}{when(incident.created_at)}
								</p>
								<div class="flex flex-wrap gap-1.5">
									{#if isSeverity(incident.severity)}<SeverityBadge severity={incident.severity} />{/if}
									{#if isStatus(incident.status)}<StatusBadge status={incident.status} />{/if}
									{#if incident.hidden}<Badge icon={EyeOff}>Hidden</Badge>{/if}
								</div>
							</div>
							{@render toggle(incident, 'self-center')}
						</li>
					{:else}
						<li class="p-6 text-center text-fg-tertiary">No reports in this list.</li>
					{/each}
				</ul>

				<!-- Desktop: table -->
				<div class="hidden overflow-hidden rounded-lg border border-line-subtle bg-surface-sheet lg:block">
					<div class="{grid} border-b border-line-subtle px-4 py-2.5 text-micro font-bold tracking-caps text-fg-tertiary uppercase">
						<span>Report</span><span>Category</span><span>Severity</span><span>Status</span><span>Votes</span><span>Reported</span><span class="text-right">Map</span>
					</div>
					{#each rows as incident (incident.id)}
						{@const category = categoryOf(incident)}
						<div class="{grid} items-center border-b border-line-subtle px-4 py-2.5 last:border-b-0 {incident.hidden ? 'opacity-60' : ''}">
							<div class="min-w-0">
								<p class="truncate font-bold">{incident.title}</p>
								<p class="truncate text-caption text-fg-tertiary">{incident.address_hint || incident.description || ''}</p>
							</div>
							<span class="flex items-center gap-2 text-label font-normal"><CategoryTile {category} size={26} />{CATEGORY_LABEL[category]}</span>
							<span>{#if isSeverity(incident.severity)}<SeverityBadge severity={incident.severity} />{/if}</span>
							<span>{#if isStatus(incident.status)}<StatusBadge status={incident.status} />{/if}</span>
							<span class="num text-label font-normal text-fg-secondary">+{incident.confirm_count} −{incident.deny_count}</span>
							<span class="text-label font-normal text-fg-secondary" title={new Date(incident.created_at).toLocaleString('en-GB')}>{when(incident.created_at)}</span>
							<div class="flex items-center justify-end gap-2">
								{#if incident.hidden}<Badge icon={EyeOff}>Hidden</Badge>{/if}
								{@render toggle(incident)}
							</div>
						</div>
					{:else}
						<p class="p-6 text-center text-fg-tertiary">No reports in this list.</p>
					{/each}
				</div>
			</div>
		{/if}
	</div>
</div>
