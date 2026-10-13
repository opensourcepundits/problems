<script lang="ts">
	import { goto } from '$app/navigation';
	import { Siren } from 'lucide-svelte';
	import { createIncident, currentPosition } from '$lib/api';
	import { createSupabaseBrowserClient } from '$lib/supabaseClient';
	import { flyToIncident, pushToast } from '$lib/ui.svelte';

	let { userId }: { userId: string | null } = $props();

	const HOLD_MS = 1500;
	let progress = $state(0);
	let holding = $state(false);
	let busy = $state(false);
	let frame = 0;
	let fired = false;

	function locationMessage(cause: unknown) {
		if (cause && typeof cause === 'object' && 'code' in cause) {
			const code = Number((cause as { code: number }).code);
			if (code === 1) return 'Location permission was denied.';
			if (code === 3) return 'Location request timed out. Try again with a clear sky view.';
		}
		return cause instanceof Error ? cause.message : 'Could not read your location.';
	}

	function startHold(event: PointerEvent) {
		if (busy) return;
		fired = false;
		holding = true;
		progress = 0;
		(event.currentTarget as HTMLElement).setPointerCapture(event.pointerId);
		const started = performance.now();
		const tick = (now: number) => {
			progress = Math.min(1, (now - started) / HOLD_MS);
			if (progress >= 1) {
				fired = true;
				holding = false;
				cancelAnimationFrame(frame);
				void trigger();
				return;
			}
			frame = requestAnimationFrame(tick);
		};
		frame = requestAnimationFrame(tick);
	}

	function cancelHold() {
		if (fired || busy) return;
		holding = false;
		progress = 0;
		cancelAnimationFrame(frame);
	}

	async function trigger() {
		if (!userId) {
			progress = 0;
			pushToast('Sign in before sending an SOS.', 'err');
			await goto('/auth/login?next=/');
			return;
		}
		const supabase = createSupabaseBrowserClient();
		if (!supabase) {
			progress = 0;
			pushToast('Supabase is not configured.', 'err');
			return;
		}

		busy = true;
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
			pushToast('SOS sent. Your location is on the map and the action was logged.');
		} catch (cause) {
			pushToast(locationMessage(cause), 'err');
		} finally {
			busy = false;
			progress = 0;
			fired = false;
		}
	}
</script>

<button
	type="button"
	class="sos-pulse fixed bottom-[max(1.25rem,env(safe-area-inset-bottom))] left-1/2 z-40 grid h-[4.75rem] w-[4.75rem] -translate-x-1/2 place-items-center rounded-full bg-red-600 text-white shadow-[0_12px_40px_rgba(220,38,38,0.45)] select-none touch-none disabled:opacity-70"
	aria-label="Hold for 1.5 seconds to send an emergency SOS"
	disabled={busy}
	onpointerdown={startHold}
	onpointerup={cancelHold}
	onpointercancel={cancelHold}
	oncontextmenu={(event) => event.preventDefault()}
>
	<svg class="absolute inset-0 -rotate-90" viewBox="0 0 76 76" aria-hidden="true">
		<circle cx="38" cy="38" r="34" fill="none" stroke="rgba(255,255,255,0.28)" stroke-width="3" />
		<circle
			cx="38"
			cy="38"
			r="34"
			fill="none"
			stroke="white"
			stroke-width="3"
			stroke-linecap="round"
			stroke-dasharray={2 * Math.PI * 34}
			stroke-dashoffset={(1 - progress) * 2 * Math.PI * 34}
		/>
	</svg>
	<span class="relative grid place-items-center gap-0.5">
		<Siren size={22} />
		<span class="text-[10px] font-bold tracking-[0.16em]">{busy ? '…' : holding ? 'HOLD' : 'SOS'}</span>
	</span>
</button>
