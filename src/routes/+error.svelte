<script lang="ts">
	import { page } from '$app/state';
	import { ArrowLeft, MapPinOff } from 'lucide-svelte';
	import AppHeader from '$lib/components/ui/AppHeader.svelte';
	import { t } from '$lib/i18n/index.svelte';

	const message = $derived(page.status === 404 ? t('err_title') : page.error?.message || t('err_title'));
</script>

<div class="flex h-full flex-col">
	<AppHeader />
	<section class="grid flex-1 place-items-center p-6">
		<div class="flex max-w-[400px] flex-col items-center gap-3 text-center">
			<span class="grid h-14 w-14 place-items-center rounded-lg bg-surface-raised text-fg-tertiary">
				<MapPinOff size={28} />
			</span>
			<p class="num text-caption font-bold tracking-caps text-fg-tertiary">{t('error_n', { n: page.status })}</p>
			<h1 class="text-display font-heavy text-balance">{message}</h1>
			<p class="text-body text-fg-secondary">{t('err_body')}</p>
			<a
				href="/"
				class="press mt-2 inline-flex h-13 items-center gap-2 rounded-[14px] bg-accent px-5 font-bold text-fg-on-accent hover:bg-accent-hover"
			>
				<ArrowLeft size={20} />{t('back_to_map')}
			</a>
		</div>
	</section>
</div>
