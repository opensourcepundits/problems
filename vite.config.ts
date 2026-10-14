import { readFileSync } from 'node:fs';
import { sveltekit } from '@sveltejs/kit/vite';
import tailwindcss from '@tailwindcss/vite';
import { SvelteKitPWA } from '@vite-pwa/sveltekit';
import { defineConfig } from 'vite';

const manifest = JSON.parse(
	readFileSync(new URL('./static/manifest.webmanifest', import.meta.url), 'utf8')
);

export default defineConfig({
	server: {
		host: '127.0.0.1',
		port: 5173
	},
	plugins: [
		tailwindcss(),
		sveltekit(),
		SvelteKitPWA({
			registerType: 'autoUpdate',
			manifest,
			includeAssets: ['favicon.svg', 'pwa-192.png', 'pwa-512.png', 'pwa-maskable-512.png', 'fonts/*.woff2'],
			workbox: {
				runtimeCaching: [
					{
						urlPattern: ({ request }) => request.mode === 'navigate',
						handler: 'NetworkFirst',
						options: {
							cacheName: 'pages',
							networkTimeoutSeconds: 4,
							expiration: { maxEntries: 16, maxAgeSeconds: 60 * 60 * 24 }
						}
					},
					{
						urlPattern: /^https:\/\/tiles\.openfreemap\.org\/styles\/.*/i,
						handler: 'StaleWhileRevalidate',
						options: {
							cacheName: 'map-styles',
							expiration: { maxEntries: 8, maxAgeSeconds: 60 * 60 * 24 * 14 },
							cacheableResponse: { statuses: [0, 200] }
						}
					},
					{
						urlPattern: /^https:\/\/(tiles\.openfreemap\.org|server\.arcgisonline\.com)\/.*/i,
						handler: 'CacheFirst',
						options: {
							cacheName: 'map-tiles',
							expiration: { maxEntries: 1200, maxAgeSeconds: 60 * 60 * 24 * 14 },
							cacheableResponse: { statuses: [0, 200] }
						}
					},
					{
						urlPattern: /^https:\/\/.*\.supabase\.co\/storage\/v1\/object\/public\/incident-media\/.*/i,
						handler: 'StaleWhileRevalidate',
						options: {
							cacheName: 'incident-media',
							expiration: { maxEntries: 200, maxAgeSeconds: 60 * 60 * 24 * 7 },
							cacheableResponse: { statuses: [0, 200] }
						}
					}
				]
			},
			devOptions: {
				enabled: false
			}
		})
	]
});
