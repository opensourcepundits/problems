<script lang="ts">
	import { onMount } from 'svelte';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import { lanternStyle, type MapTheme } from '$lib/mapStyle';
	import type { Map } from 'maplibre-gl';

	let { lng, lat, theme = 'dark' }: { lng: number; lat: number; theme?: MapTheme } = $props();

	let container = $state<HTMLDivElement | undefined>(undefined);
	let map: Map | undefined;

	onMount(() => {
		const node = container;
		if (!node) return;
		let disposed = false;
		void (async () => {
			const [maplibregl, style] = await Promise.all([
				import('maplibre-gl').then((module) => module.default),
				lanternStyle(document.documentElement.dataset.theme === 'light' ? 'light' : theme)
			]);
			if (disposed) return;
			map = new maplibregl.Map({
				container: node,
				style,
				center: [lng, lat],
				zoom: 15,
				interactive: false,
				attributionControl: false
			});
		})();
		return () => {
			disposed = true;
			map?.remove();
		};
	});

	$effect(() => {
		map?.jumpTo({ center: [lng, lat] });
	});
</script>

<div class="relative h-full w-full bg-map-bg" aria-hidden="true">
	<div class="h-full w-full" bind:this={container}></div>
	<!-- Draft pin: Beacon disc, white ring, white stem, ground shadow. Tip sits on the centre. -->
	<span class="pointer-events-none absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-full">
		<span class="absolute -bottom-[3px] left-1/2 h-1.5 w-4 -translate-x-1/2 rounded-[50%] bg-[rgba(0,0,0,.45)]"></span>
		<span class="relative block h-7 w-7 rounded-full border-[3px] border-white bg-beacon-400 shadow-[0_2px_6px_rgba(0,0,0,.4)]"></span>
		<span class="mx-auto block h-3 w-[3px] bg-white"></span>
	</span>
</div>
