<script lang="ts">
	import { browser } from '$app/environment';
	import { Grid3x3, MapPin, Plus } from 'lucide-svelte';
	import { onMount } from 'svelte';
	import IncidentCard from '$lib/components/IncidentCard.svelte';
	import MapGridHeatmap from '$lib/components/MapGridHeatmap.svelte';
	import MapPinView from '$lib/components/MapPinView.svelte';
	import ReportModal from '$lib/components/ReportModal.svelte';
	import { fetchIncidents } from '$lib/api';
	import { createSupabaseBrowserClient } from '$lib/supabaseClient';
	import {
		CATEGORIES,
		CATEGORY_LABEL,
		HOME_VIEWPORT,
		TIME_WINDOWS,
		type Category,
		type Incident,
		type TileBounds,
		type Viewport
	} from '$lib/types';
	import { mapCommand } from '$lib/ui.svelte';

	let mode = $state<'pins' | 'grid'>('pins');
	let hours = $state(24);
	let categories = $state<Category[]>([]);
	let cellKm = $state(5);
	let viewport = $state<Viewport>({ center: HOME_VIEWPORT.center, zoom: HOME_VIEWPORT.zoom });
	let bounds = $state<TileBounds | null>(null);
	let focusNonce = $state(0);
	let focusBounds = $state<[[number, number], [number, number]] | null>(null);
	let incidents = $state<Incident[]>([]);
	let selectedId = $state<string | null>(null);
	let reportOpen = $state(false);
	let pickingPin = $state(false);
	let draftPin = $state<{ lng: number; lat: number } | null>(null);
	let loading = $state(false);
	let error = $state('');
	let seenCommand = 0;

	const selected = $derived(incidents.find((incident) => incident.id === selectedId) ?? null);

	async function load() {
		const supabase = createSupabaseBrowserClient();
		if (!supabase) {
			error = '';
			incidents = [];
			return;
		}
		loading = true;
		error = '';
		try {
			incidents = await fetchIncidents(supabase, hours, categories, mode === 'pins' ? bounds : null);
			if (selectedId && !incidents.some((incident) => incident.id === selectedId)) selectedId = null;
		} catch (cause) {
			error = cause instanceof Error ? cause.message : 'Could not load incidents.';
		} finally {
			loading = false;
		}
	}

	function openReport() {
		draftPin = null;
		pickingPin = false;
		reportOpen = true;
	}

	function drillDown(tile: TileBounds) {
		bounds = tile;
		focusBounds = [
			[tile.minLng, tile.minLat],
			[tile.maxLng, tile.maxLat]
		];
		focusNonce += 1;
		mode = 'pins';
	}

	function onCreated(id: string, lng: number, lat: number) {
		reportOpen = false;
		pickingPin = false;
		draftPin = null;
		mode = 'pins';
		bounds = null;
		viewport = { center: [lng, lat], zoom: 15 };
		selectedId = id;
		void load();
	}

	$effect(() => {
		void hours;
		void categories;
		void bounds;
		void mode;
		if (browser) void load();
	});

	$effect(() => {
		if (!browser || mapCommand.nonce === 0 || mapCommand.nonce === seenCommand) return;
		seenCommand = mapCommand.nonce;
		mode = 'pins';
		categories = [];
		bounds = null;
		viewport = { center: [mapCommand.lng, mapCommand.lat], zoom: 15 };
		selectedId = mapCommand.incidentId;
		void load();
	});

	onMount(() => {
		const supabase = createSupabaseBrowserClient();
		if (!supabase) return;
		const refresh = () => void load();
		const channel = supabase
			.channel('crisis-feed')
			.on('postgres_changes', { event: '*', schema: 'public', table: 'incidents' }, refresh)
			.on('postgres_changes', { event: '*', schema: 'public', table: 'incident_comments' }, refresh)
			.on('postgres_changes', { event: '*', schema: 'public', table: 'incident_confirmations' }, refresh)
			.subscribe();
		return () => {
			void supabase.removeChannel(channel);
		};
	});
</script>

<svelte:window
	onkeydown={(event) => {
		if (event.key === 'Escape') {
			reportOpen = false;
			selectedId = null;
		}
	}}
/>

<div class="absolute inset-0">
	{#if mode === 'pins'}
		<MapPinView
			{incidents}
			{viewport}
			{focusNonce}
			{focusBounds}
			picking={pickingPin}
			{draftPin}
			onViewport={(next) => (viewport = next)}
			onSelect={(id) => (selectedId = id)}
			onPick={(lng, lat) => {
				draftPin = { lng, lat };
				pickingPin = false;
				viewport = { center: [lng, lat], zoom: Math.max(viewport.zoom, 14) };
			}}
		/>
	{:else}
		<MapGridHeatmap {hours} {categories} {cellKm} {viewport} onViewport={(next) => (viewport = next)} onDrillDown={drillDown} />
	{/if}
</div>

<div class="pointer-events-none absolute inset-x-0 top-0 z-10 flex flex-col gap-2 p-3 pr-16">
	<div class="pointer-events-auto flex flex-wrap items-center gap-2">
		<div class="flex rounded-full bg-slate-950/90 p-1 text-sm shadow-lg">
			<button
				type="button"
				class="inline-flex items-center gap-1 rounded-full px-3 py-1.5 {mode === 'pins' ? 'bg-white text-slate-950' : 'text-slate-200'}"
				aria-pressed={mode === 'pins'}
				onclick={() => (mode = 'pins')}
			>
				<MapPin size={14} /> Exact pins
			</button>
			<button
				type="button"
				class="inline-flex items-center gap-1 rounded-full px-3 py-1.5 {mode === 'grid' ? 'bg-white text-slate-950' : 'text-slate-200'}"
				aria-pressed={mode === 'grid'}
				onclick={() => (mode = 'grid')}
			>
				<Grid3x3 size={14} /> {cellKm} km zones
			</button>
		</div>
		<div class="flex rounded-full bg-slate-950/90 p-1 text-sm shadow-lg">
			{#each TIME_WINDOWS as window (window.hours)}
				<button
					type="button"
					class="rounded-full px-2.5 py-1.5 {hours === window.hours ? 'bg-red-600 text-white' : 'text-slate-200'}"
					onclick={() => (hours = window.hours)}
				>
					{window.label}
				</button>
			{/each}
		</div>
		<button type="button" class="inline-flex items-center gap-1 rounded-full bg-red-600 px-3 py-2 text-sm font-semibold shadow-lg" onclick={openReport}>
			<Plus size={16} /> Report
		</button>
		<span class="rounded-full bg-slate-950/80 px-3 py-1.5 text-xs text-slate-300">
			{loading ? 'Updating…' : `${incidents.length} reports`}
		</span>
	</div>

	<div class="pointer-events-auto flex gap-2 overflow-x-auto pb-1">
		<button
			type="button"
			class="shrink-0 rounded-full px-3 py-1 text-sm {categories.length === 0 ? 'bg-white text-slate-950' : 'bg-slate-950/85 text-slate-200'}"
			aria-pressed={categories.length === 0}
			onclick={() => (categories = [])}
		>
			All
		</button>
		{#each CATEGORIES as item (item)}
			<button
				type="button"
				class="shrink-0 rounded-full px-3 py-1 text-sm {categories.includes(item) ? 'bg-white text-slate-950' : 'bg-slate-950/85 text-slate-200'}"
				aria-pressed={categories.includes(item)}
				onclick={() => {
					categories = categories.includes(item)
						? categories.filter((value) => value !== item)
						: [...categories, item];
				}}
			>
				{CATEGORY_LABEL[item]}
			</button>
		{/each}
	</div>

	{#if bounds && mode === 'pins'}
		<button
			type="button"
			class="pointer-events-auto w-fit rounded-full bg-amber-400 px-3 py-1 text-sm font-medium text-slate-950"
			onclick={() => {
				bounds = null;
				focusBounds = null;
			}}
		>
			Showing one zone · Clear
		</button>
	{/if}
	{#if error}
		<p class="pointer-events-auto w-fit max-w-md rounded-xl bg-red-950/90 px-3 py-2 text-sm text-red-100">{error}</p>
	{/if}
</div>

{#if mode === 'grid'}
	<div class="pointer-events-auto absolute bottom-6 left-3 z-10 w-56 rounded-2xl bg-slate-950/90 px-3 py-3 text-xs text-slate-200 shadow-lg">
		<label class="block font-medium">
			Hexagon size · {cellKm} km
			<input
				class="mt-2 w-full accent-red-500"
				type="range"
				min="1"
				max="10"
				step="1"
				value={cellKm}
				oninput={(event) => (cellKm = Number(event.currentTarget.value))}
			/>
		</label>
		<p class="mt-2 mb-1">Reports in each hexagon</p>
		<div class="flex items-center gap-1">
			<span class="h-2 flex-1 rounded bg-white"></span>
			<span class="h-2 flex-1 rounded bg-amber-200"></span>
			<span class="h-2 flex-1 rounded bg-yellow-400"></span>
			<span class="h-2 flex-1 rounded bg-orange-500"></span>
			<span class="h-2 flex-1 rounded bg-red-600"></span>
			<span class="h-2 flex-1 rounded bg-purple-700"></span>
		</div>
		<p class="mt-1 flex justify-between text-[10px] text-slate-400"><span>None</span><span>Many</span></p>
	</div>
{/if}

{#if pickingPin}
	<div class="pointer-events-none absolute inset-x-0 bottom-28 z-20 flex justify-center px-3">
		<div class="pointer-events-auto flex items-center gap-3 rounded-full bg-white px-4 py-2 text-sm font-medium text-slate-950 shadow-xl">
			Tap the map to drop the pin
			<button type="button" class="rounded-full bg-slate-900 px-3 py-1 text-white" onclick={() => (pickingPin = false)}>
				Back
			</button>
		</div>
	</div>
{/if}

{#if reportOpen}
	<ReportModal
		picking={pickingPin}
		lat={draftPin?.lat ?? null}
		lng={draftPin?.lng ?? null}
		onClose={() => {
			reportOpen = false;
			pickingPin = false;
		}}
		{onCreated}
		onDropPin={() => {
			mode = 'pins';
			pickingPin = true;
		}}
		onUseGps={(lat, lng) => {
			draftPin = { lng, lat };
			viewport = { center: [lng, lat], zoom: Math.max(viewport.zoom, 14) };
		}}
	/>
{/if}

{#if selected && !pickingPin}
	<IncidentCard incident={selected} onClose={() => (selectedId = null)} onChanged={() => void load()} />
{/if}
