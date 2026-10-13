<script lang="ts">
	import { onMount } from 'svelte';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import { addIncidentIcons, CATEGORY_ICON } from '$lib/mapIcons';
	import { osmStyle } from '$lib/mapStyle';
	import type { Incident, Viewport } from '$lib/types';
	import type { FeatureCollection, Point } from 'geojson';
	import type { GeoJSONSource, Map } from 'maplibre-gl';

	let {
		incidents,
		viewport,
		focusNonce = 0,
		focusBounds = null,
		picking = false,
		draftPin = null,
		onViewport,
		onSelect,
		onPick
	}: {
		incidents: Incident[];
		viewport: Viewport;
		focusNonce?: number;
		focusBounds?: [[number, number], [number, number]] | null;
		picking?: boolean;
		draftPin?: { lng: number; lat: number } | null;
		onViewport: (viewport: Viewport) => void;
		onSelect: (id: string) => void;
		onPick?: (lng: number, lat: number) => void;
	} = $props();

	let container = $state<HTMLDivElement | undefined>(undefined);
	let map: Map | undefined;
	let ready = $state(false);
	let applying = false;
	let seenFocus = 0;
	const interaction = {
		picking: false,
		onPick: (_lng: number, _lat: number) => {}
	};

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
					status: incident.status,
					is_sos: incident.is_sos
				}
			}))
		};
	}

	function paint() {
		const source = map?.getSource('incidents') as GeoJSONSource | undefined;
		source?.setData(collection());
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
					},
					paint: {
						'icon-opacity': ['match', ['get', 'status'], 'resolved', 0.45, 1]
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

			local.on('click', 'clusters', (event) => {
				if (interaction.picking) return;
				const clusterId = event.features?.[0]?.properties?.cluster_id;
				const source = local?.getSource('incidents') as GeoJSONSource | undefined;
				if (!local || !source || clusterId === undefined) return;
				void source.getClusterExpansionZoom(Number(clusterId)).then((zoom) => {
					local?.easeTo({ center: event.lngLat, zoom });
				});
			});

			local.on('click', 'unclustered', (event) => {
				if (interaction.picking) return;
				const id = event.features?.[0]?.properties?.id;
				if (id) onSelect(String(id));
			});

			local.on('click', (event) => {
				if (!interaction.picking) return;
				interaction.onPick(event.lngLat.lng, event.lngLat.lat);
			});

			for (const layer of ['clusters', 'unclustered']) {
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
