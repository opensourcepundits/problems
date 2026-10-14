// Quiet, keyless vector basemap. Dark: OpenFreeMap "dark" (a Dark Matter fork). Light: OpenFreeMap "positron".
// Both are free, need no key, and ship their own glyphs and OSM/OpenMapTiles attribution.
import type { StyleSpecification } from 'maplibre-gl';

export type MapTheme = 'dark' | 'light';

export const STYLE_URL = {
	dark: 'https://tiles.openfreemap.org/styles/dark',
	light: 'https://tiles.openfreemap.org/styles/positron'
} as const;

/** Font stack served by the OpenFreeMap glyph endpoint, used for cluster counts. */
export const LABEL_FONT = ['Noto Sans Bold'];

type Loose = Record<string, unknown>;

/** Fetch the style and push it further into the background so markers and zones own the colour. */
export async function lanternStyle(theme: MapTheme = 'dark'): Promise<StyleSpecification> {
	let style: StyleSpecification;
	try {
		const response = await fetch(STYLE_URL[theme]);
		if (!response.ok) throw new Error(`Style request failed: ${response.status}`);
		style = await response.json();
	} catch {
		return rasterFallback(theme);
	}
	const dark = theme === 'dark';
	for (const layer of style.layers) {
		const id = layer.id;
		const paint = ((layer as Loose).paint ??= {}) as Loose;
		const layout = ((layer as Loose).layout ??= {}) as Loose;
		if (layer.type === 'background') paint['background-color'] = dark ? '#0e1116' : '#e9edf1';
		if (/water/.test(id) && layer.type === 'fill') paint['fill-color'] = dark ? '#0a1420' : '#d5e1ec';
		if (/landuse|landcover|park/.test(id) && layer.type === 'fill') paint['fill-opacity'] = 0.35;
		// Buildings are noise at island zooms, and POIs compete with incident markers.
		if (/building/.test(id)) layout.visibility = 'none';
		if (/poi|housenumber/.test(id)) layout.visibility = 'none';
		if (layer.type === 'line' && /road|highway|street|path/.test(id)) {
			const major = /motorway|trunk|primary/.test(id);
			paint['line-color'] = dark ? (major ? '#2b3440' : '#1d242d') : major ? '#ffffff' : '#f7f8fa';
		}
		if (layer.type === 'symbol' && layout['text-field']) {
			paint['text-color'] = dark ? '#8c96a5' : '#5f6a7a';
			paint['text-halo-color'] = dark ? '#0e1116' : '#e9edf1';
			paint['text-halo-width'] = 1.2;
		}
	}
	return style;
}

/** Used when the vector style cannot be fetched (offline with an empty cache). */
function rasterFallback(theme: MapTheme): StyleSpecification {
	const flavour = theme === 'dark' ? 'World_Dark_Gray_Base' : 'World_Light_Gray_Base';
	return {
		version: 8,
		glyphs: 'https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf',
		sources: {
			base: {
				type: 'raster',
				tiles: [
					`https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/${flavour}/MapServer/tile/{z}/{y}/{x}`
				],
				tileSize: 256,
				attribution: 'Esri, HERE, Garmin, &copy; OpenStreetMap contributors'
			}
		},
		layers: [
			{ id: 'background', type: 'background', paint: { 'background-color': theme === 'dark' ? '#0e1116' : '#e9edf1' } },
			{ id: 'base', type: 'raster', source: 'base' }
		]
	};
}
