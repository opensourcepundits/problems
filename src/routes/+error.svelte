<script lang="ts">
	import { page } from '$app/state';
</script>

<section class="grid min-h-full place-items-center px-4">
	<div class="max-w-md text-center">
		<p class="text-sm tracking-[0.16em] text-red-300 uppercase">Error {page.status}</p>
		<h1 class="mt-2 text-3xl font-semibold">{page.error?.message || 'Something went wrong.'}</h1>
		<a class="mt-6 inline-block rounded-full bg-white px-4 py-2 text-sm font-medium text-slate-950" href="/">Back to the map</a>
	</div>
</section>
