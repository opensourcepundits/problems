<script lang="ts">
	import { onMount } from 'svelte';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import { fetchGrid } from '$lib/api';
	import { osmStyle } from '$lib/mapStyle';
	import { createSupabaseBrowserClient } from '$lib/supabaseClient';
	import { CATEGORY_LABEL, isCategory, type Category, type TileBounds, type Viewport } from '$lib/types';
	import type { FeatureCollection, Polygon } from 'geojson';
	import type { ExpressionSpecification, GeoJSONSource, Map, Popup } from 'maplibre-gl';

	let {
		hours,
		categories,
		cellKm,
		viewport,
		onViewport,
		onDrillDown
	}: {
		hours: number;
		categories: Category[];
		cellKm: number;
		viewport: Viewport;
		onViewport: (viewport: Viewport) => void;
		onDrillDown: (bounds: TileBounds) => void;
	} = $props();

	let container = $state<HTMLDivElement | undefined>(undefined);
	let map: Map | undefined;
	let ready = $state(false);
	let applying = false;
	let loading = $state(false);
	let error = $state('');
	let popup: Popup | undefined;
	let requestId = 0;
	const view = { km: 5 };

	const heatValue: ExpressionSpecification = ['get', 'heat'];
	const heatColor: ExpressionSpecification = [
		'interpolate',
		['linear'],
		heatValue,
		0,
		'#ffffff',
		0.12,
		'#fde047',
		0.32,
		'#f59e0b',
		0.55,
		'#f97316',
		0.78,
		'#dc2626',
		1,
		'#6b21a8'
	];
	const heatOpacity: ExpressionSpecification = [
		'interpolate',
		['linear'],
		heatValue,
		0,
		0.28,
		0.12,
		0.72,
		1,
		0.9
	];

	function tileBounds(geometry: { coordinates: unknown }): TileBounds | null {
		let minLng = Infinity;
		let minLat = Infinity;
		let maxLng = -Infinity;
		let maxLat = -Infinity;
		const visit = (value: unknown) => {
			if (!Array.isArray(value) || value.length === 0) return;
			if (typeof value[0] === 'number' && typeof value[1] === 'number') {
				minLng = Math.min(minLng, value[0]);
				minLat = Math.min(minLat, value[1]);
				maxLng = Math.max(maxLng, value[0]);
				maxLat = Math.max(maxLat, value[1]);
				return;
			}
			for (const child of value) visit(child);
		};
		visit(geometry.coordinates);
		if (!Number.isFinite(minLng)) return null;
		return { minLng, minLat, maxLng, maxLat };
	}

	function applyHeat() {
		if (!map?.getLayer('grid-fill')) return;
		map.setPaintProperty('grid-fill', 'fill-color', heatColor);
		map.setPaintProperty('grid-fill', 'fill-opacity', heatOpacity);
		if (map.getLayer('grid-line')) {
			map.setPaintProperty('grid-line', 'line-color', [
				'interpolate',
				['linear'],
				heatValue,
				0,
				'#94a3b8',
				1,
				'#3b0764'
			]);
		}
	}

	function escapeHtml(value: string) {
		return value.replace(/[&<>"']/g, (char) => {
			const map: Record<string, string> = {
				'&': '&amp;',
				'<': '&lt;',
				'>': '&gt;',
				'"': '&quot;',
				"'": '&#39;'
			};
			return map[char] ?? char;
		});
	}

	async function loadGrid() {
		const current = ++requestId;
		const supabase = createSupabaseBrowserClient();
		if (!supabase) {
			error = 'Add Supabase keys in .env to load danger zones.';
			return;
		}
		loading = true;
		error = '';
		try {
			const collection = await fetchGrid(supabase, hours, categories, cellKm);
			if (current !== requestId) return;
			const counts = collection.features.map((feature) => Number(feature.properties.total_count) || 0);
			const maxCount = counts.reduce((highest, count) => Math.max(highest, count), 0);
			for (const feature of collection.features) {
				const count = Number(feature.properties.total_count) || 0;
				feature.properties.total_count = count;
				feature.properties.critical_count = Number(feature.properties.critical_count) || 0;
				feature.properties.heat = maxCount === 0 ? 0 : Math.sqrt(count / maxCount);
			}
			const source = map?.getSource('grid') as GeoJSONSource | undefined;
			source?.setData(collection as FeatureCollection<Polygon>);
			applyHeat();
		} catch (cause) {
			if (current !== requestId) return;
			error = cause instanceof Error ? cause.message : 'Could not load the grid.';
		} finally {
			if (current === requestId) loading = false;
		}
	}

	onMount(() => {
		const node = container;
		if (!node) return;
		let disposed = false;
		let local: Map | undefined;

		void (async () => {
			const maplibregl = (await import('maplibre-gl')).default;
			if (disposed) return;
			node.style.width = '100%';
			node.style.height = '100%';
			local = new maplibregl.Map({
				container: node,
				center: viewport.center,
				zoom: viewport.zoom,
				style: osmStyle(),
				dragRotate: false,
				pitchWithRotate: false
			});
			map = local;
			const observer = new ResizeObserver(() => local?.resize());
			observer.observe(node);
			local.on('remove', () => observer.disconnect());
			local.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'top-right');
			local.on('load', () => {
				if (!local) return;
				local.addSource('grid', {
					type: 'geojson',
					data: { type: 'FeatureCollection', features: [] }
				});
				local.addLayer({
					id: 'grid-fill',
					type: 'fill',
					source: 'grid',
					paint: {
						'fill-color': '#ffffff',
						'fill-opacity': 0.45
					}
				});
				local.addLayer({
					id: 'grid-line',
					type: 'line',
					source: 'grid',
					paint: { 'line-color': '#64748b', 'line-width': 1 }
				});
				ready = true;
			});

			local.on('moveend', () => {
				if (!local) return;
				if (applying) {
					applying = false;
					return;
				}
				const center = local.getCenter();
				onViewport({ center: [center.lng, center.lat], zoom: local.getZoom() });
			});

			local.on('click', 'grid-fill', (event) => {
				const feature = event.features?.[0];
				if (!feature || (feature.geometry.type !== 'Polygon' && feature.geometry.type !== 'MultiPolygon') || !local) return;
				const props = feature.properties ?? {};
				const total = Number(props.total_count ?? 0);
				const critical = Number(props.critical_count ?? 0);
				const categoryRaw = props.top_category == null ? '' : String(props.top_category);
				const category = isCategory(categoryRaw) ? CATEGORY_LABEL[categoryRaw] : total === 0 ? 'None' : escapeHtml(categoryRaw || 'Other');
				const bounds = tileBounds(feature.geometry);
				popup?.remove();
				popup = new maplibregl.Popup({ className: 'crisis-popup', maxWidth: '260px' })
					.setLngLat(event.lngLat)
					.setHTML(
						`<p class="text-xs uppercase tracking-wide text-slate-400">${view.km} km square</p>
						<p class="mt-1 text-lg font-semibold">${total} events</p>
						<p class="text-sm text-red-300">${critical} critical</p>
						<p class="mt-1 text-sm text-slate-300">Most common: ${category}</p>
						<button type="button" data-drill class="mt-3 w-full rounded-lg bg-red-600 px-3 py-2 text-sm font-semibold text-white">Show exact pins</button>`
					)
					.addTo(local);
				popup.getElement()?.querySelector('[data-drill]')?.addEventListener('click', () => {
					if (bounds) onDrillDown(bounds);
					popup?.remove();
				});
			});

			local.on('mouseenter', 'grid-fill', () => {
				local!.getCanvas().style.cursor = 'pointer';
			});
			local.on('mouseleave', 'grid-fill', () => {
				local!.getCanvas().style.cursor = '';
			});
		})();

		return () => {
			disposed = true;
			ready = false;
			popup?.remove();
			local?.remove();
			map = undefined;
		};
	});

	$effect(() => {
		view.km = cellKm;
		const selected = categories.join(',');
		void hours;
		void selected;
		if (!map || !ready) return;
		applyHeat();
		void loadGrid();
	});

	$effect(() => {
		const next = viewport;
		if (!map || !ready) return;
		const center = map.getCenter();
		const same =
			Math.abs(center.lng - next.center[0]) < 1e-5 &&
			Math.abs(center.lat - next.center[1]) < 1e-5 &&
			Math.abs(map.getZoom() - next.zoom) < 0.02;
		if (same) return;
		applying = true;
		map.jumpTo({ center: next.center, zoom: next.zoom });
	});
</script>

<div class="absolute inset-0">
	<div class="h-full w-full" bind:this={container}></div>
</div>
{#if loading}
	<p class="pointer-events-none absolute bottom-24 left-3 z-10 rounded-full bg-slate-950/80 px-3 py-1 text-xs text-slate-200">
		Loading {cellKm} km squares…
	</p>
{/if}
{#if error}
	<p class="absolute bottom-24 left-3 z-10 max-w-sm rounded-xl bg-red-950/90 px-3 py-2 text-sm text-red-100">{error}</p>
{/if}
