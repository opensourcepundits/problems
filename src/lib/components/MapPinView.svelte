<script lang="ts">
	import { onMount } from 'svelte';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import { addIncidentIcons, CATEGORY_ICON } from '$lib/mapIcons';
	import { osmStyle } from '$lib/mapStyle';
	import { squareGrid } from '$lib/squares';
	import { CATEGORY_LABEL, isCategory, type Incident, type TileBounds, type Viewport } from '$lib/types';
	import type { FeatureCollection, Point } from 'geojson';
	import type { ExpressionSpecification, GeoJSONSource, Map, Popup } from 'maplibre-gl';

	let {
		incidents,
		viewport,
		focusNonce = 0,
		focusBounds = null,
		picking = false,
		draftPin = null,
		showZones = false,
		cellKm = 5,
		onViewport,
		onSelect,
		onPick,
		onDrillDown
	}: {
		incidents: Incident[];
		viewport: Viewport;
		focusNonce?: number;
		focusBounds?: [[number, number], [number, number]] | null;
		picking?: boolean;
		draftPin?: { lng: number; lat: number } | null;
		showZones?: boolean;
		cellKm?: number;
		onViewport: (viewport: Viewport) => void;
		onSelect: (id: string) => void;
		onPick?: (lng: number, lat: number) => void;
		onDrillDown?: (bounds: TileBounds) => void;
	} = $props();

	let container = $state<HTMLDivElement | undefined>(undefined);
	let map: Map | undefined;
	let ready = $state(false);
	let applying = false;
	let seenFocus = 0;
	let popup: Popup | undefined;
	const interaction = {
		picking: false,
		showZones: false,
		cellKm: 5,
		onPick: (_lng: number, _lat: number) => {},
		onDrillDown: (_bounds: TileBounds) => {}
	};

	const zoneCount: ExpressionSpecification = ['to-number', ['get', 'total_count']];
	const zoneColor: ExpressionSpecification = [
		'interpolate',
		['linear'],
		zoneCount,
		0,
		'#f1f5f9',
		1,
		'#fde047',
		2,
		'#facc15',
		3,
		'#fbbf24',
		5,
		'#f59e0b',
		8,
		'#fb923c',
		12,
		'#f97316',
		18,
		'#ea580c',
		26,
		'#ef4444',
		36,
		'#dc2626',
		50,
		'#b91c1c',
		70,
		'#7e22ce'
	];
	const zoneOpacity: ExpressionSpecification = [
		'interpolate',
		['linear'],
		zoneCount,
		0,
		0.45,
		1,
		0.58,
		5,
		0.66,
		18,
		0.76,
		50,
		0.88
	];

	function collection(): FeatureCollection<Point> {
		return {
			type: 'FeatureCollection',
			features: incidents.map((incident) => ({
				type: 'Feature',
				geometry: { type: 'Point', coordinates: [incident.lng, incident.lat] },
				properties: {
					id: incident.id,
					category: incident.category,
					severity: incident.severity,
					is_sos: incident.is_sos
				}
			}))
		};
	}

	function paint() {
		const source = map?.getSource('incidents') as GeoJSONSource | undefined;
		source?.setData(collection());
	}

	function escapeHtml(value: string) {
		return value.replace(/[&<>"']/g, (char) => {
			const named: Record<string, string> = {
				'&': '&amp;',
				'<': '&lt;',
				'>': '&gt;',
				'"': '&quot;',
				"'": '&#39;'
			};
			return named[char] ?? char;
		});
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
				local.addSource('zones', {
					type: 'geojson',
					data: { type: 'FeatureCollection', features: [] }
				});
				local.addLayer({
					id: 'zones-fill',
					type: 'fill',
					source: 'zones',
					layout: { visibility: 'none' },
					paint: {
						'fill-color': zoneColor,
						'fill-opacity': zoneOpacity
					}
				});
				local.addLayer({
					id: 'zones-line',
					type: 'line',
					source: 'zones',
					layout: { visibility: 'none' },
					paint: {
						'line-color': [
							'interpolate',
							['linear'],
							zoneCount,
							0,
							'#94a3b8',
							70,
							'#3b0764'
						],
						'line-width': 1
					}
				});
				local.addSource('incidents', {
					type: 'geojson',
					data: collection(),
					cluster: true,
					clusterRadius: 48,
					clusterMaxZoom: 14
				});
				local.addLayer({
					id: 'clusters',
					type: 'circle',
					source: 'incidents',
					filter: ['has', 'point_count'],
					paint: {
						'circle-color': ['step', ['get', 'point_count'], '#1e293b', 8, '#c2410c', 24, '#7f1d1d'],
						'circle-radius': ['step', ['get', 'point_count'], 16, 8, 22, 24, 28],
						'circle-stroke-width': 2,
						'circle-stroke-color': '#fff7ed'
					}
				});
				local.addLayer({
					id: 'cluster-count',
					type: 'symbol',
					source: 'incidents',
					filter: ['has', 'point_count'],
					layout: {
						'text-field': ['to-string', ['get', 'point_count']],
						'text-font': ['Open Sans Semibold'],
						'text-size': 13,
						'text-allow-overlap': true
					},
					paint: {
						'text-color': '#fff7ed'
					}
				});
				addIncidentIcons(local);
				local.addLayer({
					id: 'unclustered',
					type: 'symbol',
					source: 'incidents',
					filter: ['!', ['has', 'point_count']],
					layout: {
						'icon-image': [
							'match',
							['get', 'category'],
							'fire',
							CATEGORY_ICON.fire,
							'looting',
							CATEGORY_ICON.looting,
							'casualty',
							CATEGORY_ICON.casualty,
							'accident',
							CATEGORY_ICON.accident,
							'roadblock',
							CATEGORY_ICON.roadblock,
							'sos',
							CATEGORY_ICON.sos,
							CATEGORY_ICON.other
						],
						'icon-size': ['case', ['==', ['get', 'is_sos'], true], 0.62, 0.5],
						'icon-allow-overlap': true,
						'icon-anchor': 'center'
					}
				});
				local.addSource('draft', {
					type: 'geojson',
					data: { type: 'FeatureCollection', features: [] }
				});
				local.addLayer({
					id: 'draft-pin',
					type: 'circle',
					source: 'draft',
					paint: {
						'circle-radius': 9,
						'circle-color': '#facc15',
						'circle-stroke-width': 3,
						'circle-stroke-color': '#0f172a'
					}
				});
				ready = true;
				if (focusBounds && focusNonce !== seenFocus) {
					seenFocus = focusNonce;
					local.fitBounds(focusBounds, { padding: 56, maxZoom: 14, duration: 0 });
				}
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

			local.on('click', 'zones-fill', (event) => {
				if (interaction.picking || !interaction.showZones || !local) return;
				const feature = event.features?.[0];
				const props = feature?.properties;
				if (!props) return;
				const total = Number(props.total_count ?? 0);
				const critical = Number(props.critical_count ?? 0);
				const categoryRaw = props.top_category == null ? '' : String(props.top_category);
				const category = isCategory(categoryRaw)
					? CATEGORY_LABEL[categoryRaw]
					: total === 0
						? 'None'
						: escapeHtml(categoryRaw || 'Other');
				const bounds = {
					minLng: Number(props.min_lng),
					minLat: Number(props.min_lat),
					maxLng: Number(props.max_lng),
					maxLat: Number(props.max_lat)
				};
				popup?.remove();
				popup = new maplibregl.Popup({ className: 'crisis-popup', maxWidth: '260px' })
					.setLngLat(event.lngLat)
					.setHTML(
						`<p class="text-xs uppercase tracking-wide text-slate-400">${interaction.cellKm} km square</p>
						<p class="mt-1 text-lg font-semibold">${total} events</p>
						<p class="text-sm text-red-300">${critical} critical</p>
						<p class="mt-1 text-sm text-slate-300">Most common: ${category}</p>
						<button type="button" data-drill class="mt-3 w-full rounded-lg bg-red-600 px-3 py-2 text-sm font-semibold text-white">Show exact pins</button>`
					)
					.addTo(local);
				popup.getElement()?.querySelector('[data-drill]')?.addEventListener('click', () => {
					if (Number.isFinite(bounds.minLng)) interaction.onDrillDown(bounds);
					popup?.remove();
				});
			});

			for (const layer of ['clusters', 'cluster-count']) {
				local.on('click', layer, (event) => {
					if (interaction.picking || interaction.showZones) return;
					const clusterId = event.features?.[0]?.properties?.cluster_id;
					const source = local?.getSource('incidents') as GeoJSONSource | undefined;
					if (!local || !source || clusterId === undefined) return;
					void source.getClusterExpansionZoom(Number(clusterId)).then((zoom) => {
						local?.easeTo({ center: event.lngLat, zoom });
					});
				});
			}

			local.on('click', 'unclustered', (event) => {
				if (interaction.picking || interaction.showZones) return;
				const id = event.features?.[0]?.properties?.id;
				if (id) onSelect(String(id));
			});

			local.on('click', (event) => {
				if (!interaction.picking) return;
				interaction.onPick(event.lngLat.lng, event.lngLat.lat);
			});

			for (const layer of ['zones-fill', 'clusters', 'cluster-count', 'unclustered']) {
				local.on('mouseenter', layer, () => {
					local!.getCanvas().style.cursor = 'pointer';
				});
				local.on('mouseleave', layer, () => {
					local!.getCanvas().style.cursor = '';
				});
			}
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
		interaction.picking = picking;
		interaction.onPick = onPick ?? (() => {});
		if (map && ready) map.getCanvas().style.cursor = picking ? 'crosshair' : '';
	});

	$effect(() => {
		const point = draftPin;
		if (!map || !ready) return;
		const source = map.getSource('draft') as GeoJSONSource | undefined;
		source?.setData(
			point
				? {
						type: 'FeatureCollection',
						features: [
							{
								type: 'Feature',
								geometry: { type: 'Point', coordinates: [point.lng, point.lat] },
								properties: {}
							}
						]
					}
				: { type: 'FeatureCollection', features: [] }
		);
	});

	$effect(() => {
		void incidents;
		if (ready) paint();
	});

	$effect(() => {
		const km = cellKm;
		const rows = incidents;
		if (!map || !ready) return;
		const source = map.getSource('zones') as GeoJSONSource | undefined;
		source?.setData(squareGrid(rows, km));
	});

	$effect(() => {
		const zones = showZones;
		interaction.showZones = zones;
		interaction.cellKm = cellKm;
		interaction.onDrillDown = onDrillDown ?? (() => {});
		if (!map || !ready) return;
		const zoneVisibility = zones ? 'visible' : 'none';
		const pinVisibility = zones ? 'none' : 'visible';
		for (const id of ['zones-fill', 'zones-line']) {
			if (map.getLayer(id)) map.setLayoutProperty(id, 'visibility', zoneVisibility);
		}
		for (const id of ['clusters', 'cluster-count', 'unclustered']) {
			if (map.getLayer(id)) map.setLayoutProperty(id, 'visibility', pinVisibility);
		}
		if (!zones) popup?.remove();
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

	$effect(() => {
		if (!map || !ready || !focusBounds || focusNonce === 0 || focusNonce === seenFocus) return;
		seenFocus = focusNonce;
		map.fitBounds(focusBounds, { padding: 56, maxZoom: 14 });
	});
</script>

<div class="absolute inset-0">
	<div class="h-full w-full" bind:this={container}></div>
</div>
