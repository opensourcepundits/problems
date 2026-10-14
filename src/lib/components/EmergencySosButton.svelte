<script lang="ts">
	import { Check, LoaderCircle, RotateCcw, Siren } from 'lucide-svelte';
	import { onMount } from 'svelte';
	import { createIncident, currentPosition, RateLimitError } from '$lib/api';
	import { t } from '$lib/i18n/index.svelte';
	import { createSupabaseBrowserClient } from '$lib/supabaseClient';
	import { flyToIncident, pushToast, sosCalls } from '$lib/ui.svelte';

	const HOLD_MS = 1500;
	const QUICK_MS = 400;
	const RING = 2 * Math.PI * 33;

	type SosState = 'idle' | 'hint' | 'holding' | 'sending' | 'sent' | 'failed';

	let phase = $state<SosState>('idle');
	let progress = $state(0);
	let frame = 0;
	let started = 0;
	let timer: ReturnType<typeof setTimeout> | undefined;
	let fingerDown = false;
	let callReady = false;

	const label = $derived(
		{
			idle: t('sos_idle'),
			hint: t('sos_hint'),
			holding: t('sos_holding'),
			sending: t('sos_sending'),
			sent: t('sos_sent'),
			failed: t('sos_failed')
		}[phase]
	);
	const loud = $derived(phase === 'hint' || phase === 'holding');

	function vibrate(pattern: number | number[]) {
		try {
			navigator.vibrate?.(pattern);
		} catch {
			// unsupported (iOS)
		}
	}

	function settle(next: SosState, ms: number) {
		clearTimeout(timer);
		phase = next;
		timer = setTimeout(() => (phase = 'idle'), ms);
	}

	function locationMessage(cause: unknown) {
		if (cause instanceof RateLimitError) {
			return t('rate_limited_sos', { min: Math.ceil(cause.retryAfterSeconds / 60) });
		}
		if (cause && typeof cause === 'object' && 'code' in cause) {
			const code = Number((cause as { code: number }).code);
			if (code === 1) return t('loc_denied');
			if (code === 3) return t('loc_timeout');
		}
		return cause instanceof Error ? cause.message : t('loc_denied');
	}

	function revealCalls() {
		if (!callReady || fingerDown) return;
		sosCalls.open = true;
	}

	function startHold(event: PointerEvent) {
		if (phase === 'sending') return;
		fingerDown = true;
		callReady = false;
		sosCalls.open = false;
		try {
			(event.currentTarget as HTMLElement).setPointerCapture(event.pointerId);
		} catch {
			// capture can fail on synthetic events
		}
		clearTimeout(timer);
		phase = 'holding';
		progress = 0;
		started = performance.now();
		vibrate(10);
		const tick = (now: number) => {
			progress = Math.min(1, (now - started) / HOLD_MS);
			if (progress >= 1) {
				vibrate([30, 40, 30]);
				void trigger();
				return;
			}
			frame = requestAnimationFrame(tick);
		};
		frame = requestAnimationFrame(tick);
	}

	function endHold() {
		fingerDown = false;
		if (phase === 'holding') {
			cancelAnimationFrame(frame);
			progress = 0;
			if (performance.now() - started < QUICK_MS) settle('hint', 2400);
			else phase = 'idle';
			return;
		}
		// The hold already finished. Wait until the finger lifts so the release cannot dial.
		revealCalls();
	}

	async function trigger() {
		phase = 'sending';
		progress = 0;
		const supabase = createSupabaseBrowserClient();
		if (!supabase) {
			pushToast(t('not_configured'), 'err');
			settle('failed', 3000);
			return;
		}
		try {
			const position = await currentPosition();
			const lat = position.coords.latitude;
			const lng = position.coords.longitude;
			const id = await createIncident(supabase, {
				title: 'Emergency SOS',
				description: 'One-tap emergency SOS from the reporter’s current location.',
				category: 'sos',
				severity: 'critical',
				lng,
				lat,
				addressHint: '',
				mediaUrls: [],
				isSos: true
			});
			flyToIncident(lng, lat, id);
			callReady = true;
			revealCalls();
			settle('sent', 3200);
		} catch (cause) {
			pushToast(locationMessage(cause), 'err');
			settle('failed', 3000);
		}
	}

	onMount(() => () => {
		cancelAnimationFrame(frame);
		clearTimeout(timer);
	});
</script>

<div class="flex flex-col items-center gap-1.5">
	<span
		aria-live="polite"
		class="rounded-xs border border-line-subtle px-2 py-[3px] text-micro font-bold whitespace-nowrap {loud
			? 'bg-alarm-600 text-white'
			: phase === 'failed'
				? 'glass text-alarm-400'
				: 'glass text-fg'}">{label}</span
	>
	<button
		type="button"
		aria-label={t('sos_aria')}
		class="relative grid h-[72px] w-[72px] cursor-pointer touch-none place-items-center rounded-full p-0 shadow-[0_0_0_4px_rgba(7,9,12,.55),var(--shadow-sos)] transition-transform duration-200 ease-[var(--ease-out)] select-none [-webkit-touch-callout:none] {phase ===
		'failed'
			? 'bg-alarm-950 text-alarm-400'
			: 'bg-alarm-600 text-white'} {phase === 'holding' ? 'scale-[1.06]' : ''}"
		onpointerdown={startHold}
		onpointerup={endHold}
		onpointercancel={endHold}
		onpointerleave={endHold}
		oncontextmenu={(event) => event.preventDefault()}
	>
		<svg class="absolute inset-0 h-[72px] w-[72px] -rotate-90" viewBox="0 0 72 72" aria-hidden="true">
			<circle
				cx="36"
				cy="36"
				r="33"
				fill="none"
				stroke={phase === 'failed' ? 'rgba(255,107,107,.5)' : 'rgba(255,255,255,.28)'}
				stroke-width="3"
			/>
			<circle
				cx="36"
				cy="36"
				r="33"
				fill="none"
				stroke="#fff"
				stroke-width="3.5"
				stroke-linecap="round"
				stroke-dasharray={RING}
				stroke-dashoffset={(1 - (phase === 'sent' ? 1 : progress)) * RING}
			/>
		</svg>
		<span class="relative grid place-items-center gap-px">
			{#if phase === 'sending'}
				<LoaderCircle size={26} class="spin" />
			{:else if phase === 'sent'}
				<Check size={28} strokeWidth={3} />
			{:else if phase === 'failed'}
				<RotateCcw size={22} strokeWidth={2.5} />
			{:else}
				<Siren size={24} strokeWidth={2.25} />
			{/if}
			{#if phase !== 'sending' && phase !== 'sent'}
				<span class="text-micro leading-[14px] font-heavy tracking-[0.08em]">SOS</span>
			{/if}
		</span>
	</button>
</div>
