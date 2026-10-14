<script lang="ts">
	import { LocateFixed, Minus, Plus } from 'lucide-svelte';
	import { MapPin as MapPinGlyph } from 'lucide';
	import { onMount } from 'svelte';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import { currentPosition } from '$lib/api';
	import { i18n, t, timeAgo } from '$lib/i18n/index.svelte';
	import { addIncidentIcons, DRAFT_ICON, GLYPH, iconSvg } from '$lib/mapIcons';
	import { LABEL_FONT, lanternStyle, type MapTheme } from '$lib/mapStyle';
	import { squareGrid } from '$lib/squares';
	import { CATEGORY_META, MAP, SEVERITY_META } from '$lib/tokens';
	import { isCategory, isSeverity, type Incident, type TileBounds, type Viewport } from '$lib/types';
	import { chrome, pushToast } from '$lib/ui.svelte';
	import type { Feature, FeatureCollection, Point, Polygon } from 'geojson';
	import type { ExpressionSpecification, GeoJSONSource, Map, Popup } from 'maplibre-gl';

	let {
		incidents,
		viewport,
		focusNonce = 0,
		focusBounds = null,
		flyNonce = 0,
		flyTarget = null,
		picking = false,
		draftPin = null,
		showZones = false,
		cellKm = 5,
		theme = 'dark',
		dimmed = false,
		controls = true,
		controlsClass = 'bottom-[calc(128px+env(safe-area-inset-bottom))] lg:bottom-[132px]',
		onViewport,
		onSelect,
		onPick,
		onDrillDown
	}: {
		incidents: Incident[];
		viewport: Viewport;
		focusNonce?: number;
		focusBounds?: [[number, number], [number, number]] | null;
		flyNonce?: number;
		flyTarget?: {
			lng: number;
			lat: number;
			zoom: number;
			bounds: [[number, number], [number, number]] | null;
		} | null;
		picking?: boolean;
		draftPin?: { lng: number; lat: number } | null;
		showZones?: boolean;
		cellKm?: number;
		theme?: MapTheme;
		dimmed?: boolean;
		controls?: boolean;
		controlsClass?: string;
		onViewport: (viewport: Viewport) => void;
		onSelect: (id: string) => void;
		onPick?: (lng: number, lat: number) => void;
		onDrillDown?: (bounds: TileBounds) => void;
	} = $props();

	let container = $state<HTMLDivElement | undefined>(undefined);
	let map: Map | undefined;
	let ready = $state(false);
	let loadedTheme: MapTheme | null = null;
	let applying = false;
	let seenFocus = 0;
	let seenFly = 0;
	let popup: Popup | undefined;
	let hoverPopup: Popup | undefined;
	let hoverZone: number | null = null;
	let selectedZone: number | null = null;
	let pulseFrame = 0;
	const interaction = {
		picking: false,
		showZones: false,
		cellKm: 5,
		onPick: (_lng: number, _lat: number) => {},
		onDrillDown: (_bounds: TileBounds) => {}
	};

	const EMPTY: FeatureCollection = { type: 'FeatureCollection', features: [] };
	const zoneCount: ExpressionSpecification = ['to-number', ['get', 'total_count']];
	const zoneFill: ExpressionSpecification = [
		'step',
		zoneCount,
		'rgba(0,0,0,0)',
		...MAP.heat.flatMap(([at, color]) => [at, color])
	] as unknown as ExpressionSpecification;
	const severityRing: ExpressionSpecification = [
		'match',
		['get', 'maxSev'],
		4,
		SEVERITY_META.critical.color,
		3,
		SEVERITY_META.high.color,
		2,
		SEVERITY_META.medium.color,
		SEVERITY_META.low.color
	];

	function collection(): FeatureCollection<Point> {
		return {
			type: 'FeatureCollection',
			features: incidents.map((incident) => ({
				type: 'Feature',
				geometry: { type: 'Point', coordinates: [incident.lng, incident.lat] },
				properties: {
					id: incident.id,
					category: incident.is_sos ? 'sos' : incident.category,
					severity: incident.severity,
					sevRank: SEVERITY_META[incident.severity]?.rank ?? 2,
					status: incident.status,
					is_sos: incident.is_sos,
					title: incident.title,
					created_at: incident.created_at
				}
			}))
		};
	}

	function point(lngLat: { lng: number; lat: number } | null): FeatureCollection {
		if (!lngLat) return EMPTY;
		return {
			type: 'FeatureCollection',
			features: [{ type: 'Feature', geometry: { type: 'Point', coordinates: [lngLat.lng, lngLat.lat] }, properties: {} }]
		};
	}

	function outline(bounds: [[number, number], [number, number]] | null): FeatureCollection {
		if (!bounds) return EMPTY;
		const [[w, s], [e, n]] = bounds;
		const ring: Feature<Polygon> = {
			type: 'Feature',
			geometry: { type: 'Polygon', coordinates: [[[w, s], [e, s], [e, n], [w, n], [w, s]]] },
			properties: {}
		};
		return { type: 'FeatureCollection', features: [ring] };
	}

	/** Keeps a fitted area clear of the floating top panel, action bar and map controls. */
	function fitPadding() {
		return chrome.desktop
			? { top: 110, bottom: 40, left: 40, right: 40 }
			: { top: 150, bottom: 150, left: 24, right: 72 };
	}

	function source(id: string) {
		return map?.getSource(id) as GeoJSONSource | undefined;
	}

	function escapeHtml(value: string) {
		return value.replace(/[&<>"']/g, (char) => {
			const named: Record<string, string> = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
			return named[char] ?? char;
		});
	}

	function meterHtml(rank: number, color: string) {
		return `<span aria-hidden="true" style="display:inline-flex;align-items:flex-end;gap:2px;height:12px">${[1, 2, 3, 4]
			.map(
				(step) =>
					`<span style="width:3px;border-radius:1px;height:${Math.round(12 * (0.35 + step * 0.1625))}px;background:${step <= rank ? color : 'var(--border-strong)'}"></span>`
			)
			.join('')}</span>`;
	}

	function categoryTileHtml(category: string, size: number, radius: number) {
		const key = isCategory(category) ? category : 'other';
		const sos = key === 'sos';
		return `<span style="width:${size}px;height:${size}px;border-radius:${sos ? size / 2 : radius}px;background:${CATEGORY_META[key].color};color:${sos ? '#fff' : 'var(--color-cat-glyph)'};display:grid;place-items:center;flex-shrink:0">${iconSvg(GLYPH[key], Math.round(size * 0.58), 2.5)}</span>`;
	}

	function setZoneState(id: number | null, key: 'hover' | 'selected', value: boolean) {
		if (id === null || !map?.getSource('zones')) return;
		map.setFeatureState({ source: 'zones', id }, { [key]: value });
	}

	function syncVisibility() {
		if (!map || !ready) return;
		const zones = showZones ? 'visible' : 'none';
		const pins = showZones ? 'none' : 'visible';
		for (const id of ['zones-fill', 'zones-line', 'zones-hover', 'zones-selected']) {
			if (map.getLayer(id)) map.setLayoutProperty(id, 'visibility', zones);
		}
		for (const id of ['focus-line', 'critical-glow', 'critical-ring', 'sos-pulse-a', 'sos-pulse-b', 'clusters', 'clusters-sos-dot', 'cluster-count', 'unclustered']) {
			if (map.getLayer(id)) map.setLayoutProperty(id, 'visibility', pins);
		}
	}

	/** Adds every Lantern source and layer. Runs on the first load and after each theme swap. */
	function install(local: Map) {
		addIncidentIcons(local);
		local.addSource('zones', { type: 'geojson', data: squareGrid(incidents, cellKm) });
		local.addLayer({ id: 'zones-fill', type: 'fill', source: 'zones', paint: { 'fill-color': zoneFill, 'fill-opacity': 1 } });
		local.addLayer({
			id: 'zones-line',
			type: 'line',
			source: 'zones',
			paint: { 'line-color': ['case', ['>', zoneCount, 0], MAP.heatLine, MAP.heatLineEmpty], 'line-width': 1 }
		});
		local.addLayer({
			id: 'zones-hover',
			type: 'line',
			source: 'zones',
			paint: {
				'line-color': MAP.zoneHover,
				'line-width': 2,
				'line-opacity': ['case', ['boolean', ['feature-state', 'hover'], false], 1, 0]
			}
		});
		local.addLayer({
			id: 'zones-selected',
			type: 'line',
			source: 'zones',
			paint: {
				'line-color': MAP.zoneSelected,
				'line-width': 2,
				'line-opacity': ['case', ['boolean', ['feature-state', 'selected'], false], 1, 0]
			}
		});
		local.addSource('focus', { type: 'geojson', data: outline(focusBounds) });
		local.addLayer({
			id: 'focus-line',
			type: 'line',
			source: 'focus',
			paint: { 'line-color': MAP.zoneSelected, 'line-width': 2, 'line-dasharray': [2, 1.5] }
		});

		local.addSource('incidents', {
			type: 'geojson',
			data: collection(),
			cluster: true,
			clusterRadius: 48,
			clusterMaxZoom: 14,
			clusterProperties: {
				maxSev: ['max', ['get', 'sevRank']],
				sos: ['+', ['case', ['get', 'is_sos'], 1, 0]]
			}
		});
		const loose: ExpressionSpecification = ['!', ['has', 'point_count']];
		const live: ExpressionSpecification = ['match', ['get', 'status'], ['debunked', 'resolved'], false, true];
		local.addLayer({
			id: 'critical-glow',
			type: 'circle',
			source: 'incidents',
			filter: ['all', loose, ['==', ['get', 'severity'], 'critical'], live],
			paint: { 'circle-radius': 28, 'circle-color': MAP.criticalRing, 'circle-opacity': 0.25, 'circle-blur': 0.6 }
		});
		local.addLayer({
			id: 'critical-ring',
			type: 'circle',
			source: 'incidents',
			filter: ['all', loose, ['==', ['get', 'severity'], 'critical'], live],
			paint: {
				'circle-radius': 22,
				'circle-color': 'rgba(0,0,0,0)',
				'circle-stroke-color': MAP.criticalRing,
				'circle-stroke-width': 2
			}
		});
		for (const id of ['sos-pulse-a', 'sos-pulse-b']) {
			local.addLayer({
				id,
				type: 'circle',
				source: 'incidents',
				filter: ['all', loose, ['==', ['get', 'is_sos'], true]],
				paint: {
					'circle-radius': 20,
					'circle-color': 'rgba(0,0,0,0)',
					'circle-stroke-color': MAP.sosHalo,
					'circle-stroke-width': 3,
					'circle-stroke-opacity': 0
				}
			});
		}
		local.addLayer({
			id: 'clusters',
			type: 'circle',
			source: 'incidents',
			filter: ['has', 'point_count'],
			paint: {
				'circle-color': MAP.clusterFill,
				'circle-radius': ['step', ['get', 'point_count'], 19, 10, 23, 50, 28],
				'circle-stroke-width': 3,
				'circle-stroke-color': ['case', ['>', ['get', 'sos'], 0], MAP.sos, severityRing]
			}
		});
		local.addLayer({
			id: 'clusters-sos-dot',
			type: 'circle',
			source: 'incidents',
			filter: ['all', ['has', 'point_count'], ['>', ['get', 'sos'], 0]],
			paint: {
				'circle-radius': 6,
				'circle-color': MAP.sos,
				'circle-stroke-color': MAP.clusterFill,
				'circle-stroke-width': 2,
				'circle-translate': [14, -14]
			}
		});
		local.addLayer({
			id: 'cluster-count',
			type: 'symbol',
			source: 'incidents',
			filter: ['has', 'point_count'],
			layout: {
				'text-field': ['to-string', ['get', 'point_count']],
				'text-font': LABEL_FONT,
				'text-size': 14,
				'text-allow-overlap': true
			},
			paint: { 'text-color': MAP.clusterText }
		});
		local.addLayer({
			id: 'unclustered',
			type: 'symbol',
			source: 'incidents',
			filter: loose,
			layout: {
				'icon-image': ['concat', 'm-', ['get', 'category'], '-', ['get', 'status']],
				'icon-size': [
					'match',
					['get', 'severity'],
					'low',
					SEVERITY_META.low.iconSize,
					'medium',
					SEVERITY_META.medium.iconSize,
					'high',
					SEVERITY_META.high.iconSize,
					'critical',
					SEVERITY_META.critical.iconSize,
					SEVERITY_META.medium.iconSize
				],
				'icon-allow-overlap': true,
				'icon-anchor': 'center',
				'symbol-sort-key': ['get', 'sevRank']
			},
			paint: { 'icon-opacity': ['case', ['==', ['get', 'status'], 'debunked'], 0.45, 1] }
		});
		local.addSource('draft', { type: 'geojson', data: point(draftPin) });
		local.addLayer({
			id: 'draft-pin',
			type: 'symbol',
			source: 'draft',
			layout: { 'icon-image': DRAFT_ICON, 'icon-anchor': 'bottom', 'icon-allow-overlap': true }
		});
		hoverZone = null;
		selectedZone = null;
		ready = true;
		syncVisibility();
	}

	function pulse(local: Map) {
		const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
		if (reduced) return;
		let last = 0;
		const tick = (now: number) => {
			pulseFrame = requestAnimationFrame(tick);
			if (now - last < 33 || !ready || interaction.showZones) return;
			if (!incidents.some((incident) => incident.is_sos)) return;
			last = now;
			for (const [id, offset] of [['sos-pulse-a', 0], ['sos-pulse-b', 800]] as const) {
				if (!local.getLayer(id)) continue;
				const phase = ((now + offset) % 1600) / 1600;
				const eased = 1 - Math.pow(1 - phase, 3);
				local.setPaintProperty(id, 'circle-radius', 18 + eased * 20);
				local.setPaintProperty(id, 'circle-stroke-opacity', 0.55 * (1 - phase));
			}
		};
		pulseFrame = requestAnimationFrame(tick);
	}

	onMount(() => {
		const node = container;
		if (!node) return;
		let disposed = false;
		let local: Map | undefined;

		void (async () => {
			// The pre-paint script in app.html sets data-theme before any component mounts.
			const initialTheme: MapTheme = document.documentElement.dataset.theme === 'light' ? 'light' : 'dark';
			const [maplibregl, style] = await Promise.all([
				import('maplibre-gl').then((module) => module.default),
				lanternStyle(initialTheme)
			]);
			if (disposed) return;
			loadedTheme = initialTheme;
			local = new maplibregl.Map({
				container: node,
				center: viewport.center,
				zoom: viewport.zoom,
				style,
				dragRotate: false,
				pitchWithRotate: false,
				touchPitch: false,
				attributionControl: false
			});
			local.addControl(new maplibregl.AttributionControl({ compact: true }), 'bottom-left');
			// Compact attribution starts expanded; collapse it so it never covers the map chrome.
			local.once('load', () => node.querySelector('.maplibregl-compact-show')?.classList.remove('maplibregl-compact-show'));
			local.touchZoomRotate.disableRotation();
			map = local;
			const observer = new ResizeObserver(() => local?.resize());
			observer.observe(node);
			local.on('remove', () => observer.disconnect());

			local.on('style.load', () => {
				if (!local) return;
				install(local);
				if (focusBounds && focusNonce !== seenFocus) {
					seenFocus = focusNonce;
					local.fitBounds(focusBounds, { padding: fitPadding(), maxZoom: 13, duration: 0 });
				}
			});
			pulse(local);

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
				setZoneState(selectedZone, 'selected', false);
				popup?.remove();
				if (total === 0) return;
				selectedZone = feature.id === undefined ? null : Number(feature.id);
				setZoneState(selectedZone, 'selected', true);
				const critical = Number(props.critical_count ?? 0);
				const top = props.top_category == null ? '' : String(props.top_category);
				const bounds = {
					minLng: Number(props.min_lng),
					minLat: Number(props.min_lat),
					maxLng: Number(props.max_lng),
					maxLat: Number(props.max_lat)
				};
				const mostly = isCategory(top)
					? `<span style="display:flex;align-items:center;gap:8px">${categoryTileHtml(top, 18, 6)}${escapeHtml(t('mostly', { cat: t(`cat_${top}`).toLowerCase() }))}</span>`
					: '';
				const html = `<div style="width:212px">
					<p class="text-micro font-bold uppercase tracking-caps text-fg-tertiary">${escapeHtml(t('km_square', { km: interaction.cellKm }))}</p>
					<p style="margin:6px 0 10px;display:flex;align-items:baseline;gap:6px"><span class="num" style="font-size:28px;line-height:32px;font-weight:700">${total}</span><span class="text-body-sm text-fg-secondary">${escapeHtml(t('reports', { n: total }))}</span></p>
					<div class="text-label text-fg-secondary" style="display:flex;flex-direction:column;gap:6px;margin-bottom:12px;font-weight:400">
						<span style="display:flex;align-items:center;gap:8px"><span style="width:8px;height:8px;border-radius:4px;background:${critical ? 'var(--color-sev-critical)' : 'var(--border-strong)'}"></span><span><span class="num text-fg" style="font-weight:700">${critical}</span> ${escapeHtml(t('crit_word'))}</span></span>
						${mostly}
					</div>
					<button type="button" data-drill class="press inline-flex h-9 w-full items-center justify-center gap-2 rounded-md bg-accent px-3 text-label font-bold text-fg-on-accent hover:bg-accent-hover">${iconSvg(MapPinGlyph, 16)}${escapeHtml(t('show_exact_pins'))}</button>
				</div>`;
				popup = new maplibregl.Popup({ className: 'crisis-popup', maxWidth: '260px', offset: 6 })
					.setLngLat(event.lngLat)
					.setHTML(html)
					.addTo(local);
				popup.on('close', () => {
					setZoneState(selectedZone, 'selected', false);
					selectedZone = null;
				});
				popup.getElement()?.querySelector('[data-drill]')?.addEventListener('click', () => {
					if (Number.isFinite(bounds.minLng)) interaction.onDrillDown(bounds);
					popup?.remove();
				});
			});

			local.on('mousemove', 'zones-fill', (event) => {
				const id = event.features?.[0]?.id;
				const next = id === undefined ? null : Number(id);
				if (next === hoverZone) return;
				setZoneState(hoverZone, 'hover', false);
				hoverZone = next;
				setZoneState(hoverZone, 'hover', true);
			});
			local.on('mouseleave', 'zones-fill', () => {
				setZoneState(hoverZone, 'hover', false);
				hoverZone = null;
			});

			for (const layer of ['clusters', 'cluster-count']) {
				local.on('click', layer, (event) => {
					if (interaction.picking || interaction.showZones) return;
					const clusterId = event.features?.[0]?.properties?.cluster_id;
					const incidentsSource = source('incidents');
					if (!local || !incidentsSource || clusterId === undefined) return;
					void incidentsSource.getClusterExpansionZoom(Number(clusterId)).then((zoom) => {
						local?.easeTo({ center: event.lngLat, zoom: Math.max(zoom, local.getZoom() + 2) });
					});
				});
			}

			local.on('click', 'unclustered', (event) => {
				if (interaction.picking || interaction.showZones) return;
				const id = event.features?.[0]?.properties?.id;
				hoverPopup?.remove();
				if (id) onSelect(String(id));
			});

			const canHover = window.matchMedia('(hover: hover) and (pointer: fine)').matches;
			if (canHover) {
				local.on('mouseenter', 'unclustered', (event) => {
					if (interaction.picking || !local) return;
					const feature = event.features?.[0];
					const props = feature?.properties;
					if (!props || feature.geometry.type !== 'Point') return;
					const severity = isSeverity(String(props.severity)) ? (String(props.severity) as keyof typeof SEVERITY_META) : 'medium';
					const meta = SEVERITY_META[severity];
					const critical = severity === 'critical';
					const html = `<div style="display:flex;gap:10px;width:228px">
						${categoryTileHtml(String(props.category), 32, 10)}
						<div style="min-width:0">
							<p class="text-body-sm font-bold text-fg" style="line-height:20px">${escapeHtml(String(props.title ?? ''))}</p>
							<div class="text-caption text-fg-tertiary" style="margin-top:6px;display:flex;align-items:center;gap:8px;font-weight:400">
								<span class="text-caption font-bold" style="display:inline-flex;align-items:center;gap:6px;height:26px;padding:0 9px 0 8px;border-radius:8px;border:1px solid ${critical ? 'rgba(255,77,77,.45)' : 'var(--border-subtle)'};background:${critical ? 'var(--alarm-tint)' : 'var(--surface-raised)'};color:${critical ? 'var(--color-alarm-400)' : 'var(--text-primary)'}">${meterHtml(meta.rank, `var(--color-sev-${severity})`)}${escapeHtml(t(`sev_${severity}`))}</span>
								${escapeHtml(timeAgo(String(props.created_at)))}
							</div>
						</div>
					</div>`;
					hoverPopup?.remove();
					hoverPopup = new maplibregl.Popup({ className: 'crisis-popup', closeButton: false, closeOnClick: false, offset: 22, maxWidth: '280px' })
						.setLngLat(feature.geometry.coordinates as [number, number])
						.setHTML(html)
						.addTo(local);
				});
				local.on('mouseleave', 'unclustered', () => hoverPopup?.remove());
			}

			local.on('click', (event) => {
				if (!interaction.picking) return;
				interaction.onPick(event.lngLat.lng, event.lngLat.lat);
			});

			for (const layer of ['zones-fill', 'clusters', 'cluster-count', 'unclustered']) {
				local.on('mouseenter', layer, () => {
					if (!interaction.picking) local!.getCanvas().style.cursor = 'pointer';
				});
				local.on('mouseleave', layer, () => {
					local!.getCanvas().style.cursor = interaction.picking ? 'crosshair' : '';
				});
			}
		})();

		return () => {
			disposed = true;
			ready = false;
			cancelAnimationFrame(pulseFrame);
			popup?.remove();
			hoverPopup?.remove();
			local?.remove();
			map = undefined;
		};
	});

	function zoom(delta: number) {
		if (delta > 0) map?.zoomIn();
		else map?.zoomOut();
	}

	async function locate() {
		try {
			const position = await currentPosition();
			map?.flyTo({ center: [position.coords.longitude, position.coords.latitude], zoom: 14 });
		} catch (cause) {
			const code = cause && typeof cause === 'object' && 'code' in cause ? Number(cause.code) : 0;
			pushToast(code === 1 ? t('loc_denied') : code === 3 ? t('loc_timeout') : cause instanceof Error ? cause.message : t('loc_denied'), 'err');
		}
	}

	$effect(() => {
		const next = theme;
		if (!ready || !map || next === loadedTheme) return;
		loadedTheme = next;
		ready = false;
		popup?.remove();
		hoverPopup?.remove();
		void lanternStyle(next).then((style) => map?.setStyle(style, { diff: false }));
	});

	$effect(() => {
		interaction.picking = picking;
		interaction.onPick = onPick ?? (() => {});
		if (ready && map) map.getCanvas().style.cursor = picking ? 'crosshair' : '';
		if (picking) hoverPopup?.remove();
	});

	$effect(() => {
		const pin = draftPin;
		if (!ready) return;
		source('draft')?.setData(point(pin));
	});

	$effect(() => {
		void incidents;
		void i18n.locale;
		if (ready) source('incidents')?.setData(collection());
	});

	$effect(() => {
		const km = cellKm;
		const rows = incidents;
		if (!ready) return;
		source('zones')?.setData(squareGrid(rows, km));
		popup?.remove();
	});

	$effect(() => {
		const bounds = focusBounds;
		if (!ready) return;
		source('focus')?.setData(outline(bounds));
	});

	$effect(() => {
		const zones = showZones;
		interaction.showZones = zones;
		interaction.cellKm = cellKm;
		interaction.onDrillDown = onDrillDown ?? (() => {});
		if (!ready) return;
		syncVisibility();
		if (!zones) popup?.remove();
		else hoverPopup?.remove();
	});

	$effect(() => {
		const next = viewport;
		if (!ready || !map) return;
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
		// Read reactive state before the non-reactive `map` guard so the effect keeps its dependencies.
		const bounds = focusBounds;
		const nonce = focusNonce;
		if (!ready || !map || !bounds || nonce === 0 || nonce === seenFocus) return;
		seenFocus = nonce;
		map.fitBounds(bounds, { padding: fitPadding(), maxZoom: 13 });
	});

	$effect(() => {
		const nonce = flyNonce;
		const target = flyTarget;
		if (!ready || !map || !target || nonce === 0 || nonce === seenFly) return;
		seenFly = nonce;
		const duration = window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 0 : 800;
		// Keep the searched place clear of the search bar and the confirm button.
		const padding = chrome.desktop
			? { top: 180, bottom: 120, left: 48, right: 48 }
			: { top: 220, bottom: 160, left: 28, right: 28 };
		if (target.bounds) map.fitBounds(target.bounds, { padding, maxZoom: target.zoom, duration });
		else map.flyTo({ center: [target.lng, target.lat], zoom: target.zoom, duration });
	});
</script>

<div class="absolute inset-0 bg-map-bg">
	<div
		class="lantern-map h-full w-full transition-[filter] duration-200"
		style:filter={dimmed ? 'saturate(.6) brightness(.7)' : 'none'}
		bind:this={container}
	></div>
	{#if controls}
		<div class="absolute right-3 z-[12] flex flex-col gap-2 {controlsClass}">
			<div class="glass flex flex-col overflow-hidden rounded-md">
				<button type="button" aria-label={t('zoom_in')} title={t('zoom_in')} class="grid h-11 w-11 place-items-center text-fg hover:bg-surface-raised" onclick={() => zoom(1)}>
					<Plus size={20} />
				</button>
				<span class="mx-2 h-px bg-line-subtle"></span>
				<button type="button" aria-label={t('zoom_out')} title={t('zoom_out')} class="grid h-11 w-11 place-items-center text-fg hover:bg-surface-raised" onclick={() => zoom(-1)}>
					<Minus size={20} />
				</button>
			</div>
			<button type="button" aria-label={t('show_my_location')} title={t('show_my_location')} class="glass press grid h-11 w-11 place-items-center rounded-md text-fg" onclick={locate}>
				<LocateFixed size={20} />
			</button>
		</div>
	{/if}
</div>
