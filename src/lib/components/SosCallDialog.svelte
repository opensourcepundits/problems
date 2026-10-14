<script lang="ts">
	import { Ambulance, Flame, Phone, Shield, Siren, X } from 'lucide-svelte';
	import { t } from '$lib/i18n/index.svelte';
	import { sosCalls } from '$lib/ui.svelte';

	// Mauritius emergency services. The whole row is a tel: link so a tap dials.
	const SERVICES = [
		{ id: 'police', label: 'call_police', number: '999', icon: Shield, color: '#1f6fd6' },
		{ id: 'samu', label: 'call_samu', number: '114', icon: Ambulance, color: '#dc2626' },
		{ id: 'fire', label: 'call_fire', number: '115', icon: Flame, color: '#ff8a3d' }
	] as const;

	let dialog = $state<HTMLDivElement | undefined>(undefined);

	function close() {
		sosCalls.open = false;
	}

	$effect(() => {
		if (!sosCalls.open) return;
		queueMicrotask(() => dialog?.focus());
	});
</script>

<svelte:window
	onkeydown={(event) => {
		if (!sosCalls.open || event.key !== 'Escape') return;
		event.preventDefault();
		close();
	}}
/>

{#if sosCalls.open}
	<div class="fixed inset-0 z-[80] flex items-end justify-center p-3 pb-[calc(12px+env(safe-area-inset-bottom))] lg:items-center">
		<button type="button" class="absolute inset-0 bg-[var(--scrim)]" aria-label={t('close')} onclick={close}></button>
		<div
			bind:this={dialog}
			role="dialog"
			aria-modal="true"
			aria-labelledby="sos-call-title"
			tabindex="-1"
			class="rise relative w-full max-w-[420px] overflow-hidden rounded-xl border border-line-strong bg-surface-sheet shadow-pop outline-none"
		>
			<div class="flex items-start gap-3 bg-alarm-600 px-4 py-3.5 text-white">
				<span class="grid h-11 w-11 shrink-0 place-items-center rounded-full bg-white/15">
					<Siren size={22} />
				</span>
				<div class="min-w-0 flex-1">
					<h2 id="sos-call-title" class="text-title font-heavy">{t('call_title')}</h2>
					<p class="mt-0.5 text-body-sm text-white/90">{t('call_body')}</p>
				</div>
				<button
					type="button"
					class="grid h-11 w-11 shrink-0 place-items-center rounded-full text-white hover:bg-white/15"
					aria-label={t('close')}
					onclick={close}
				>
					<X size={20} />
				</button>
			</div>
			<div class="flex flex-col gap-2 p-3">
				{#each SERVICES as service (service.id)}
					{@const Glyph = service.icon}
					<a
						class="press flex min-h-[72px] items-center gap-3 rounded-lg border border-line-subtle bg-surface-raised px-3.5 text-fg hover:bg-surface-raised-hover"
						href="tel:{service.number}"
					>
						<span class="grid h-12 w-12 shrink-0 place-items-center rounded-full text-white" style="background:{service.color}">
							<Glyph size={22} strokeWidth={2.25} />
						</span>
						<span class="min-w-0 flex-1 text-body font-bold">{t(service.label)}</span>
						<span class="num text-title-lg font-heavy">{service.number}</span>
						<Phone size={18} class="shrink-0 text-fg-tertiary" />
					</a>
				{/each}
			</div>
		</div>
	</div>
{/if}
