<script lang="ts">
	import { Camera, Check, Link, LoaderCircle, LocateFixed, MapPin, MapPinOff, RotateCcw, Send, X } from 'lucide-svelte';
	import { onDestroy, type Snippet } from 'svelte';
	import { createIncident, currentPosition, RateLimitError, uploadEvidence } from '$lib/api';
	import { t } from '$lib/i18n/index.svelte';
	import { prepareMedia } from '$lib/media';
	import { createSupabaseBrowserClient } from '$lib/supabaseClient';
	import { CATEGORY_META } from '$lib/tokens';
	import { CATEGORIES, SEVERITIES, type Category, type Severity } from '$lib/types';
	import { chrome, pushToast } from '$lib/ui.svelte';
	import BottomSheet from './ui/BottomSheet.svelte';
	import Button from './ui/Button.svelte';
	import IconButton from './ui/IconButton.svelte';
	import MiniMap from './ui/MiniMap.svelte';
	import Notice from './ui/Notice.svelte';
	import SeverityMeter from './ui/SeverityMeter.svelte';
	import SourceCard from './ui/SourceCard.svelte';
	import { parseSource } from '$lib/sources';
	import { CATEGORY_ICON } from './ui/icons';

	let {
		picking,
		lat,
		lng,
		placeName = '',
		onClose,
		onCreated,
		onDropPin,
		onUseGps
	}: {
		picking: boolean;
		lat: number | null;
		lng: number | null;
		placeName?: string;
		onClose: () => void;
		onCreated: (id: string, lng: number, lat: number) => void;
		onDropPin: () => void;
		onUseGps: (lat: number, lng: number) => void;
	} = $props();

	let title = $state('');
	let description = $state('');
	let category = $state<Category | null>(null);
	let severity = $state<Severity>('medium');
	let addressHint = $state('');
	let addressTouched = $state(false);
	let sourceText = $state('');
	let sourceTouched = $state(false);
	let phase = $state<'editing' | 'submitting' | 'success' | 'error'>('editing');
	let errorMessage = $state('');
	let tried = $state(false);
	let locating = $state(false);
	let locationError = $state('');
	let gps = $state<{ lat: number; lng: number; accuracy: number } | null>(null);
	let created = $state<{ id: string; lng: number; lat: number } | null>(null);
	let previews = $state<{ url: string; file: File; video: boolean }[]>([]);
	let fileInput = $state<HTMLInputElement | undefined>(undefined);

	const MAX_MEDIA = 4;
	const hasLocation = $derived(lat !== null && lng !== null);
	const source = $derived(parseSource(sourceText));
	const sourceInvalid = $derived(!!sourceText.trim() && !source);
	const videoWarning = $derived(previews.some((item) => item.video));
	const missing = $derived(
		[!category && 'category', !hasLocation && 'location', !title.trim() && 'title', sourceInvalid && 'source'].filter(
			(item): item is string => !!item
		)
	);
	// Accuracy only applies while the pin is still the GPS fix; a dropped pin has none.
	const accuracy = $derived(gps && gps.lat === lat && gps.lng === lng ? gps.accuracy : null);
	const pickable = CATEGORIES.filter((item) => item !== 'sos');

	// A searched place fills the landmark until the person types their own.
	$effect(() => {
		const next = placeName.trim();
		if (!addressTouched && next) addressHint = next.slice(0, 240);
	});

	onDestroy(() => {
		for (const preview of previews) URL.revokeObjectURL(preview.url);
	});

	async function useMyLocation() {
		locating = true;
		locationError = '';
		try {
			const position = await currentPosition();
			gps = {
				lat: position.coords.latitude,
				lng: position.coords.longitude,
				accuracy: Math.round(position.coords.accuracy)
			};
			onUseGps(position.coords.latitude, position.coords.longitude);
		} catch (cause) {
			const code = cause && typeof cause === 'object' && 'code' in cause ? Number(cause.code) : 0;
			locationError = code === 3 ? t('loc_timeout') : t('loc_denied');
		} finally {
			locating = false;
		}
	}

	async function onFiles(event: Event) {
		const input = event.currentTarget as HTMLInputElement;
		const selected = [...(input.files ?? [])];
		input.value = '';
		for (const file of selected) {
			if (previews.length >= MAX_MEDIA) {
				pushToast(t('max_files'), 'err');
				break;
			}
			try {
				const prepared = await prepareMedia(file);
				previews.push({
					url: URL.createObjectURL(prepared.file),
					file: prepared.file,
					video: prepared.videoMayContainLocation
				});
			} catch (cause) {
				pushToast(cause instanceof Error ? cause.message : t('could_not_update'), 'err');
			}
		}
	}

	function removePreview(index: number) {
		const removed = previews[index];
		if (!removed) return;
		URL.revokeObjectURL(removed.url);
		previews = previews.filter((_, itemIndex) => itemIndex !== index);
	}

	async function submit(event?: SubmitEvent) {
		event?.preventDefault();
		tried = true;
		if (missing.length || lat === null || lng === null || !category) return;
		const supabase = createSupabaseBrowserClient();
		if (!supabase) {
			errorMessage = t('not_configured');
			phase = 'error';
			return;
		}
		phase = 'submitting';
		try {
			const mediaUrls: string[] = [];
			for (const preview of previews) {
				mediaUrls.push(await uploadEvidence(supabase, preview.file));
			}
			const id = await createIncident(supabase, {
				title: title.trim(),
				description: description.trim(),
				category,
				severity,
				lng,
				lat,
				addressHint: addressHint.trim(),
				mediaUrls,
				isSos: false,
				sourceUrl: source?.url ?? null
			});
			created = { id, lng, lat };
			phase = 'success';
		} catch (cause) {
			errorMessage =
				cause instanceof RateLimitError
					? t('rate_limited_report', { min: Math.ceil(cause.retryAfterSeconds / 60) })
					: cause instanceof Error && cause.message.includes('source_url_not_allowed')
						? t('source_invalid')
					: cause instanceof TypeError
						? t('not_sent_body')
						: cause instanceof Error
							? cause.message
							: t('not_sent_body');
			phase = 'error';
		}
	}

	function viewOnMap() {
		if (created) onCreated(created.id, created.lng, created.lat);
		else onClose();
	}
</script>

{#snippet header()}
	<div class="flex items-center gap-3 border-b border-line-subtle pt-0 pr-3 pb-3 pl-4 lg:px-5 lg:pt-[18px] lg:pb-3.5">
		<div class="flex-1">
			<h2 class="text-title-lg font-heavy text-fg">{phase === 'success' ? t('report_sent') : t('report_title')}</h2>
			{#if phase !== 'success'}
				<p class="mt-0.5 text-label font-normal text-fg-tertiary">{t('report_sub')}</p>
			{/if}
		</div>
		<IconButton icon={X} label={t('close')} onclick={onClose} />
	</div>
{/snippet}

{#snippet group(step: string, heading: string, aside: string, tone: 'muted' | 'alarm', content: Snippet)}
	<section class="flex flex-col gap-2.5">
		<header class="flex items-baseline justify-between gap-3">
			<h3 class="flex items-baseline gap-2 text-body font-bold text-fg">
				<span class="num text-micro font-bold text-fg-tertiary">{step}</span>{heading}
			</h3>
			{#if aside}
				<span class="text-caption {tone === 'alarm' ? 'text-alarm-400' : 'num text-fg-tertiary'}">{aside}</span>
			{/if}
		</header>
		{@render content()}
	</section>
{/snippet}

{#snippet field(label: string, optional: boolean, count: string, error: string, input: Snippet)}
	<label class="flex min-w-0 flex-col gap-1.5">
		<span class="flex justify-between text-label font-bold text-fg-secondary">
			<span>{label}{#if optional}<span class="font-medium text-fg-tertiary">&nbsp;· {t('optional')}</span>{/if}</span>
			{#if count}<span class="num text-micro font-medium text-fg-tertiary">{count}</span>{/if}
		</span>
		{@render input()}
		{#if error}<span class="text-caption text-alarm-400">{error}</span>{/if}
	</label>
{/snippet}

{#snippet success()}
	<div class="flex flex-col items-center gap-3 px-5 py-8 text-center">
		<span class="grid h-16 w-16 place-items-center rounded-full bg-[rgba(62,207,142,.16)] text-success-400">
			<Check size={32} strokeWidth={3} />
		</span>
		<p class="text-title font-bold">{t('on_map_now')}</p>
		<p class="max-w-[300px] text-body-sm text-fg-secondary">{t('success_body')}</p>
		<div class="mt-2 flex gap-2">
			<Button variant="secondary" onclick={onClose}>{t('done')}</Button>
			<Button icon={MapPin} onclick={viewOnMap}>{t('view_on_map')}</Button>
		</div>
	</div>
{/snippet}

{#snippet categoryPicker()}
	<div role="radiogroup" aria-label={t('q1')} class="grid grid-cols-3 gap-2">
		{#each pickable as item (item)}
			{@const on = item === category}
			{@const Glyph = CATEGORY_ICON[item]}
			<button
				type="button"
				role="radio"
				aria-checked={on}
				class="press relative flex min-h-20 flex-col items-center justify-center gap-1.5 rounded-[14px] px-1.5 py-2.5 text-label leading-[18px] font-bold {on
					? 'border-2 border-accent bg-accent-tint text-fg'
					: 'border border-line-subtle bg-surface-raised text-fg-secondary hover:bg-surface-raised-hover'}"
				onclick={() => (category = item)}
			>
				<span class="grid h-9 w-9 place-items-center rounded-full text-[var(--color-cat-glyph)]" style="background:{CATEGORY_META[item].color}">
					<Glyph size={20} strokeWidth={2.25} />
				</span>
				{t(`cat_${item}`)}
				{#if on}
					<span class="absolute top-1.5 right-1.5 grid h-[18px] w-[18px] place-items-center rounded-full bg-accent text-fg-on-accent">
						<Check size={12} strokeWidth={3} />
					</span>
				{/if}
			</button>
		{/each}
	</div>
{/snippet}

{#snippet severityPicker()}
	<div>
		<div role="radiogroup" aria-label={t('q2')} class="grid grid-cols-4 gap-1 rounded-[14px] border border-line-subtle bg-surface-raised p-[3px]">
			{#each SEVERITIES as item (item)}
				{@const on = item === severity}
				<button
					type="button"
					role="radio"
					aria-checked={on}
					class="flex h-[58px] min-w-0 flex-col items-center justify-center gap-[5px] rounded-[11px] text-label leading-[18px] font-bold {on
						? 'text-fg'
						: 'text-fg-secondary hover:text-fg'}"
					style={on
						? `background:color-mix(in oklab, var(--color-sev-${item}) 18%, transparent);box-shadow:inset 0 0 0 2px var(--color-sev-${item})`
						: ''}
					onclick={() => (severity = item)}
				>
					<SeverityMeter severity={item} size={14} />
					<span class="max-w-full truncate px-1">{t(`sev_${item}`)}</span>
				</button>
			{/each}
		</div>
		<p class="mx-0.5 mt-2 text-caption text-fg-tertiary">{t(`sev_${severity}`)}: {t(`help_${severity}`)}</p>
	</div>
{/snippet}

{#snippet locationCard()}
	<div class="overflow-hidden rounded-lg border bg-surface-raised {locationError ? 'border-[rgba(255,107,107,.5)]' : 'border-line-subtle'}">
		<div class="relative {hasLocation ? 'h-[132px]' : 'h-[88px]'}">
			{#if hasLocation && lat !== null && lng !== null}
				<MiniMap {lng} {lat} theme={chrome.theme} />
			{:else}
				<div class="absolute inset-0 grid place-items-center bg-map-bg text-fg-tertiary">
					<div class="flex items-center gap-2 text-label font-normal">
						{#if locating}
							<LoaderCircle size={18} class="spin text-accent" />{t('finding_location')}
						{:else}
							<MapPinOff size={18} />{t('no_location')}
						{/if}
					</div>
				</div>
			{/if}
		</div>
		<div class="flex flex-col gap-2.5 p-3">
			{#if hasLocation && lat !== null && lng !== null}
				<div>
					<p class="text-body leading-[22px] font-bold text-fg">{t('dropped_pin')}</p>
					<p class="mt-0.5 text-caption text-fg-tertiary">
						<span class="num">{lat.toFixed(5)}, {lng.toFixed(5)}</span>{#if accuracy}
							· ±<span class="num">{accuracy}</span> m{/if}
					</p>
				</div>
			{:else if locationError}
				<p class="text-label font-normal text-alarm-400">{locationError}</p>
			{:else}
				<p class="text-label font-normal text-fg-secondary">{t('add_where')}</p>
			{/if}
			<div class="grid grid-cols-2 gap-2 max-[399px]:grid-cols-1">
				<Button variant={hasLocation ? 'secondary' : 'primary'} icon={LocateFixed} loading={locating} class="!px-2" onclick={useMyLocation}>
					<span class="truncate">{locating ? t('locating') : t('use_my_location')}</span>
				</Button>
				<Button variant="secondary" icon={MapPin} class="!px-2" onclick={onDropPin}>
					<span class="truncate">{hasLocation ? t('move_pin') : t('pick_on_map')}</span>
				</Button>
			</div>
		</div>
	</div>
{/snippet}

{#snippet mediaStrip()}
	<div class="noscroll flex gap-2 overflow-x-auto">
		{#each previews as preview, index (preview.url)}
			<div class="relative h-[72px] w-[72px] shrink-0 overflow-hidden rounded-md border border-line-subtle bg-ink-250">
				{#if preview.video}
					<!-- svelte-ignore a11y_media_has_caption -->
					<video class="h-full w-full object-cover" src={preview.url} muted playsinline></video>
				{:else}
					<img class="h-full w-full object-cover" src={preview.url} alt="" />
				{/if}
				<button
					type="button"
					aria-label={t('remove')}
					title={t('remove')}
					class="absolute top-0.5 right-0.5 grid h-7 w-7 place-items-center rounded-sm border border-[rgba(255,255,255,.12)] bg-[rgba(7,9,12,.66)] text-white"
					onclick={() => removePreview(index)}
				>
					<X size={16} />
				</button>
			</div>
		{/each}
		{#if previews.length < MAX_MEDIA}
			<button
				type="button"
				class="flex h-[72px] w-[72px] shrink-0 flex-col items-center justify-center gap-1 rounded-md border-[1.5px] border-dashed border-line-strong text-micro font-bold text-fg-secondary hover:bg-surface-raised"
				onclick={() => fileInput?.click()}
			>
				<Camera size={20} />{t('add')}
				<span class="num -mt-1 font-medium text-fg-tertiary">{previews.length}/{MAX_MEDIA}</span>
			</button>
		{/if}
		<input
			bind:this={fileInput}
			class="sr-only"
			type="file"
			accept="image/*,video/mp4,video/webm,video/quicktime"
			multiple
			tabindex="-1"
			onchange={onFiles}
		/>
	</div>
{/snippet}

{#snippet form()}
	<div class="flex flex-col gap-[22px] px-4 pt-4 pb-6 lg:px-5 lg:pt-[18px]">
		{#if phase === 'error'}
			<Notice tone="danger" title={t('not_sent_title')}>{errorMessage || t('not_sent_body')}</Notice>
		{/if}
		{@render group('1', t('q1'), tried && !category ? t('choose_one') : '', 'alarm', categoryPicker)}
		{@render group('2', t('q2'), '', 'muted', severityPicker)}
		{#snippet where()}
			{@render locationCard()}
			{#snippet landmark()}
				<input
					class="h-12 w-full rounded-md border border-line-input bg-surface-input px-3.5 text-body text-fg outline-none placeholder:text-fg-tertiary focus:border-[var(--border-focus)] focus:shadow-[0_0_0_3px_var(--accent-tint-strong)]"
					bind:value={addressHint}
					maxlength="240"
					placeholder={t('landmark_ph')}
					oninput={() => (addressTouched = true)}
				/>
			{/snippet}
			{@render field(t('landmark'), true, '', '', landmark)}
		{/snippet}
		{@render group('3', t('q3'), tried && !hasLocation ? t('required') : '', 'alarm', where)}
		{#snippet details()}
			{#snippet titleInput()}
				<input
					class="h-12 w-full rounded-md border bg-surface-input px-3.5 text-body text-fg outline-none placeholder:text-fg-tertiary focus:shadow-[0_0_0_3px_var(--accent-tint-strong)] {tried && !title.trim()
						? 'border-alarm-400'
						: 'border-line-input focus:border-[var(--border-focus)]'}"
					bind:value={title}
					maxlength="160"
					aria-invalid={tried && !title.trim() ? true : undefined}
					placeholder={t('title_ph')}
				/>
			{/snippet}
			{@render field(t('short_title'), false, `${title.length}/160`, tried && !title.trim() ? t('title_err') : '', titleInput)}
			{#snippet descriptionInput()}
				<textarea
					class="min-h-24 w-full resize-y rounded-md border border-line-input bg-surface-input px-3.5 py-3 text-body text-fg outline-none placeholder:text-fg-tertiary focus:border-[var(--border-focus)] focus:shadow-[0_0_0_3px_var(--accent-tint-strong)]"
					bind:value={description}
					maxlength="4000"
					placeholder={t('what_saw_ph')}
				></textarea>
			{/snippet}
			{@render field(t('what_saw'), true, '', '', descriptionInput)}
		{/snippet}
		{@render group('4', t('q4'), '', 'muted', details)}
		{#snippet media()}
			{@render mediaStrip()}
			<Notice tone="privacy">{t('privacy')}</Notice>
			{#if videoWarning}<Notice tone="warning">{t('video_warn')}</Notice>{/if}
			{#if source}
				<div class="flex flex-col gap-1.5">
					<span class="text-label font-bold text-fg-secondary">{t('source_label')}</span>
					<SourceCard {source} onRemove={() => (sourceText = '')} />
				</div>
			{:else}
				{#snippet sourceInput()}
					<span class="relative block">
						<Link size={18} class="pointer-events-none absolute top-1/2 left-3.5 -translate-y-1/2 text-fg-tertiary" />
						<input
							class="h-12 w-full rounded-md border bg-surface-input pr-3.5 pl-10 text-body text-fg outline-none placeholder:text-fg-tertiary focus:shadow-[0_0_0_3px_var(--accent-tint-strong)] {sourceInvalid && (sourceTouched || tried)
								? 'border-alarm-400'
								: 'border-line-input focus:border-[var(--border-focus)]'}"
							type="url"
							inputmode="url"
							autocomplete="off"
							autocapitalize="off"
							spellcheck="false"
							maxlength="500"
							placeholder={t('source_ph')}
							aria-invalid={sourceInvalid && (sourceTouched || tried) ? true : undefined}
							bind:value={sourceText}
							onblur={() => (sourceTouched = true)}
						/>
					</span>
					{#if !(sourceInvalid && (sourceTouched || tried))}
						<span class="text-caption font-normal text-fg-tertiary">{t('source_hint')}</span>
					{/if}
				{/snippet}
				{@render field(t('source_label'), true, '', sourceInvalid && (sourceTouched || tried) ? t('source_invalid') : '', sourceInput)}
			{/if}
		{/snippet}
		{@render group('5', t('q5'), `${previews.length}/${MAX_MEDIA}`, 'muted', media)}
	</div>
{/snippet}

{#snippet footer()}
	{#if phase !== 'success'}
		<div class="flex flex-col gap-1.5 border-t border-line-subtle px-4 py-3">
			<Button
				size="lg"
				fullWidth
				icon={phase === 'error' ? RotateCcw : Send}
				loading={phase === 'submitting'}
				onclick={() => void submit()}
			>
				{phase === 'submitting' ? t('sending_report') : phase === 'error' ? t('try_again') : t('send_report')}
			</Button>
			{#if tried && missing.length}
				<p role="alert" class="text-center text-caption text-alarm-400">
					{t('still_needed', { list: missing.map((key) => t(`need_${key}`)).join(', ') })}
				</p>
			{:else}
				<p class="text-center text-caption text-fg-tertiary">{t('public_logged')}</p>
			{/if}
		</div>
	{/if}
{/snippet}

{#if !picking}
	{#if chrome.desktop}
		<div class="fixed inset-0 z-50 grid place-items-center bg-[var(--scrim)] p-6">
			<button type="button" tabindex="-1" aria-label={t('close')} class="absolute inset-0 cursor-default" onclick={onClose}></button>
			<div
				role="dialog"
				aria-label={t('report_title')}
				class="rise relative flex max-h-full w-[560px] max-w-full flex-col overflow-hidden rounded-xl border border-line-strong bg-surface-sheet shadow-pop"
			>
				{@render header()}
				<div class="min-h-0 flex-1 overflow-y-auto overscroll-contain">
					{#if phase === 'success'}{@render success()}{:else}{@render form()}{/if}
				</div>
				{@render footer()}
			</div>
		</div>
	{:else}
		<BottomSheet snap="full" lockFull {onClose} label={t('report_title')} {header} {footer}>
			{#if phase === 'success'}{@render success()}{:else}{@render form()}{/if}
		</BottomSheet>
	{/if}
{/if}
