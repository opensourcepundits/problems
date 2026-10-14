<script lang="ts">
	import { Check, Moon, Phone, Sun, X } from 'lucide-svelte';
	import { LOCALES, i18n, setLocale, t } from '$lib/i18n/index.svelte';
	import { chrome, setTheme, type Theme } from '$lib/ui.svelte';
	import SegmentedControl from './SegmentedControl.svelte';

	let { layout = 'mobile', onClose }: { layout?: 'mobile' | 'desktop'; onClose: () => void } = $props();
</script>

{#snippet body()}
	<div class="flex items-center justify-between {layout === 'mobile' ? 'pt-1 pr-2 pb-2 pl-4' : 'pt-2 pr-2 pb-1 pl-3.5'}">
		<h2 class="{layout === 'mobile' ? 'text-[20px]' : 'text-body'} leading-[26px] font-heavy">{t('language')}</h2>
		{#if layout === 'mobile'}
			<button
				type="button"
				aria-label={t('close')}
				class="grid h-11 w-11 place-items-center rounded-md text-fg-secondary hover:bg-surface-raised"
				onclick={onClose}
			>
				<X size={20} />
			</button>
		{/if}
	</div>
	<div role="radiogroup" aria-label={t('language')} class="flex flex-col gap-0.5 px-1.5">
		{#each LOCALES as locale (locale.code)}
			{@const on = locale.code === i18n.locale}
			<button
				type="button"
				role="radio"
				aria-checked={on}
				lang={locale.code}
				class="flex min-h-[52px] items-center gap-3 rounded-md px-3 py-1.5 text-left text-fg {on
					? 'bg-accent-tint'
					: 'hover:bg-surface-raised'}"
				onclick={() => setLocale(locale.code)}
			>
				<span
					class="num grid h-6 w-8 place-items-center rounded-xs text-[11px] font-bold {on
						? 'bg-accent text-fg-on-accent'
						: 'bg-surface-raised text-fg-secondary'}">{locale.short}</span
				>
				<span class="min-w-0 flex-1">
					<span class="block text-body font-bold leading-[22px]">{locale.name}</span>
					{#if locale.english !== locale.name}
						<span class="block text-caption text-fg-tertiary" lang="en">{locale.english}</span>
					{/if}
				</span>
				{#if on}<Check size={20} class="text-fg-accent" />{/if}
			</button>
		{/each}
	</div>
	<div class="px-3 pt-3.5 pb-1">
		<p class="mx-1 mb-2 text-micro font-bold tracking-caps text-fg-tertiary uppercase">{t('theme')}</p>
		<SegmentedControl
			label={t('theme')}
			fullWidth
			value={chrome.theme}
			onchange={(value: Theme) => setTheme(value)}
			options={[
				{ value: 'dark', label: t('dark'), icon: Moon },
				{ value: 'light', label: t('light'), icon: Sun }
			]}
		/>
	</div>
	<p class="flex gap-2 px-4 pt-3 pb-1 text-caption text-fg-tertiary">
		<Phone size={14} class="mt-0.5 shrink-0" />{t('lang_note')}
	</p>
{/snippet}

{#if layout === 'desktop'}
	<div class="rise w-[300px] rounded-lg border border-line-strong bg-surface-sheet pt-1 pb-2.5 text-fg shadow-pop">
		{@render body()}
	</div>
{:else}
	<button
		type="button"
		tabindex="-1"
		aria-label={t('close')}
		class="fixed inset-0 z-[60] bg-[var(--scrim)]"
		onclick={onClose}
	></button>
	<div
		role="dialog"
		aria-label={t('settings')}
		class="rise fixed inset-x-0 bottom-0 z-[61] rounded-t-xl border-t border-line-strong bg-surface-sheet pt-2.5 pb-[calc(16px+env(safe-area-inset-bottom))] text-fg shadow-sheet"
	>
		<span class="mx-auto mb-1.5 block h-[5px] w-10 rounded-[3px] bg-line-strong"></span>
		{@render body()}
	</div>
{/if}
