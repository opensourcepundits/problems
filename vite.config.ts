import { readFileSync } from 'node:fs';
import JavaScriptObfuscator from 'javascript-obfuscator';
import { sveltekit } from '@sveltejs/kit/vite';
import tailwindcss from '@tailwindcss/vite';
import { SvelteKitPWA } from '@vite-pwa/sveltekit';
import vitePluginBundleObfuscator from 'vite-plugin-bundle-obfuscator';
import { defineConfig, type OutputChunk, type Plugin } from 'vite';

const manifest = JSON.parse(
	readFileSync(new URL('./static/manifest.webmanifest', import.meta.url), 'utf8')
);

const obfuscatorOptions = {
	compact: true,
	controlFlowFlattening: false,
	identifierNamesGenerator: 'hexadecimal',
	renameGlobals: false,
	selfDefending: false,
	ignoreImports: true,
	stringArray: true,
	stringArrayCallsTransform: true,
	stringArrayEncoding: ['base64'],
	stringArrayThreshold: 0.75
} as const;

function isVendorChunk(fileName: string, chunk: OutputChunk) {
	if (chunk.name?.startsWith('vendor')) return true;
	if (/sw\.js$|workbox-/.test(fileName)) return true;
	const ids = chunk.moduleIds ?? [];
	return ids.length > 0 && ids.every((id) => id.includes('node_modules'));
}

// The plugin splits vendor code out of the client build, but SvelteKit does not
// emit the index.html hook it uses to obfuscate. Run the same options on the client chunks.
function clientObfuscator(): Plugin {
	const plugin = vitePluginBundleObfuscator({
		apply: (_config, env) => env.command === 'build' && !env.isSsrBuild,
		autoExcludeNodeModules: true,
		excludes: [/sw\.js$/, /workbox-.*\.js$/],
		options: obfuscatorOptions
	}) as Plugin;
	const original = plugin.generateBundle;
	plugin.generateBundle = async function (outputOptions, bundle, isWrite) {
		if (typeof original === 'function') await original.call(this, outputOptions, bundle, isWrite);
		if (this.environment?.name === 'ssr') return;
		for (const [fileName, file] of Object.entries(bundle)) {
			if (file.type !== 'chunk' || !fileName.includes('_app/immutable/') || isVendorChunk(fileName, file)) continue;
			file.code = JavaScriptObfuscator.obfuscate(file.code, obfuscatorOptions).getObfuscatedCode();
			file.map = null;
		}
	};
	return plugin;
}

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
		}),
		clientObfuscator()
	]
});
