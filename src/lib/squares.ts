import type { Incident } from '$lib/types';
import type { FeatureCollection, Polygon } from 'geojson';

/** Main island, padded so the coast sits inside the grid rather than on its edge. */
const ISLAND = {
	minLng: 57.29,
	minLat: -20.55,
	maxLng: 57.83,
	maxLat: -19.94
};

const EARTH = Math.PI * 6378137;

export type SquareFeatureCollection = FeatureCollection<Polygon, {
	total_count: number;
	critical_count: number;
	top_category: string | null;
	min_lng: number;
	min_lat: number;
	max_lng: number;
	max_lat: number;
}>;

function toMercator(lng: number, lat: number): [number, number] {
	const x = (lng * EARTH) / 180;
	const y = Math.log(Math.tan(((90 + lat) * Math.PI) / 360)) * (EARTH / Math.PI);
	return [x, y];
}

function fromMercator(x: number, y: number): [number, number] {
	const lng = (x * 180) / EARTH;
	const lat = (Math.atan(Math.sinh((y * Math.PI) / EARTH)) * 180) / Math.PI;
	return [Number(lng.toFixed(5)), Number(lat.toFixed(5))];
}

export function squareGrid(incidents: Incident[], cellKm: number): SquareFeatureCollection {
	const size = Math.min(10, Math.max(1, Math.round(cellKm))) * 1000;
	const [west, south] = toMercator(ISLAND.minLng, ISLAND.minLat);
	const [east, north] = toMercator(ISLAND.maxLng, ISLAND.maxLat);
	const x0 = Math.floor(west / size) * size;
	const y0 = Math.floor(south / size) * size;
	const cols = Math.max(1, Math.ceil((east - x0) / size));
	const rows = Math.max(1, Math.ceil((north - y0) / size));

	const bins = new Map<string, { total: number; critical: number; categories: Map<string, number> }>();
	for (const incident of incidents) {
		if (incident.status === 'debunked') continue;
		const [x, y] = toMercator(incident.lng, incident.lat);
		const i = Math.floor((x - x0) / size);
		const j = Math.floor((y - y0) / size);
		if (i < 0 || j < 0 || i >= cols || j >= rows) continue;
		const id = `${i}:${j}`;
		let bin = bins.get(id);
		if (!bin) {
			bin = { total: 0, critical: 0, categories: new Map() };
			bins.set(id, bin);
		}
		bin.total += 1;
		if (incident.severity === 'critical') bin.critical += 1;
		bin.categories.set(incident.category, (bin.categories.get(incident.category) ?? 0) + 1);
	}

	const features: SquareFeatureCollection['features'] = [];
	for (let i = 0; i < cols; i++) {
		for (let j = 0; j < rows; j++) {
			const x = x0 + i * size;
			const y = y0 + j * size;
			const sw = fromMercator(x, y);
			const se = fromMercator(x + size, y);
			const ne = fromMercator(x + size, y + size);
			const nw = fromMercator(x, y + size);
			const bin = bins.get(`${i}:${j}`);
			let top: string | null = null;
			let topCount = 0;
			if (bin) {
				for (const [category, count] of bin.categories) {
					if (count > topCount) {
						top = category;
						topCount = count;
					}
				}
			}
			features.push({
				type: 'Feature',
				id: i * rows + j,
				geometry: { type: 'Polygon', coordinates: [[sw, se, ne, nw, sw]] },
				properties: {
					total_count: bin?.total ?? 0,
					critical_count: bin?.critical ?? 0,
					top_category: top,
					min_lng: sw[0],
					min_lat: sw[1],
					max_lng: se[0],
					max_lat: ne[1]
				}
			});
		}
	}

	return { type: 'FeatureCollection', features };
}
