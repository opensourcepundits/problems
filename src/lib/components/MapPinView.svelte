<script lang="ts">
	import { onMount } from 'svelte';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import { osmStyle } from '$lib/mapStyle';
	import { SEVERITY_COLOR, type Incident, type Viewport } from '$lib/types';
	import type { FeatureCollection, Point } from 'geojson';
	import type { GeoJSONSource, Map } from 'maplibre-gl';

	let {
		incidents,
		viewport,
		focusNonce = 0,
		focusBounds = null,
		onViewport,
		onSelect
	}: {
		incidents: Incident[];
		viewport: Viewport;
		focusNonce?: number;
		focusBounds?: [[number, number], [number, number]] | null;
		onViewport: (viewport: Viewport) => void;
		onSelect: (id: string) => void;
	} = $props();

	let container = $state<HTMLDivElement | undefined>(undefined);
	let map: Map | undefined;
	let ready = $state(false);
	let applying = false;
	let seenFocus = 0;

	function collection(): FeatureCollection<Point> {
		return {
			type: 'FeatureCollection',
			features: incidents.map((incident) => ({
				type: 'Feature',
				geometry: { type: 'Point', coordinates: [incident.lng, incident.lat] },
				properties: {
					id: incident.id,
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
				local.addLayer({
					id: 'unclustered',
					type: 'circle',
					source: 'incidents',
					filter: ['!', ['has', 'point_count']],
					paint: {
						'circle-color': [
							'match',
							['get', 'severity'],
							'critical',
							SEVERITY_COLOR.critical,
							'high',
							SEVERITY_COLOR.high,
							'medium',
							SEVERITY_COLOR.medium,
							'low',
							SEVERITY_COLOR.low,
							'#94a3b8'
						],
						'circle-radius': ['case', ['==', ['get', 'is_sos'], true], 10, 7],
						'circle-stroke-width': ['case', ['==', ['get', 'is_sos'], true], 3, 1.5],
						'circle-stroke-color': '#fff7ed',
						'circle-opacity': ['match', ['get', 'status'], 'resolved', 0.45, 0.95]
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
				const clusterId = event.features?.[0]?.properties?.cluster_id;
				const source = local?.getSource('incidents') as GeoJSONSource | undefined;
				if (!local || !source || clusterId === undefined) return;
				void source.getClusterExpansionZoom(Number(clusterId)).then((zoom) => {
					local?.easeTo({ center: event.lngLat, zoom });
				});
			});

			local.on('click', 'unclustered', (event) => {
				const id = event.features?.[0]?.properties?.id;
				if (id) onSelect(String(id));
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
