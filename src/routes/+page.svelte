<script lang="ts">
	import { browser } from '$app/environment';
	import {
		Check,
		ChevronDown,
		Crosshair,
		Globe,
		Grid3x3,
		MapPin,
		Minus,
		Plus,
		RefreshCw,
		ShieldCheck,
		SquareDashed,
		X
	} from 'lucide-svelte';
	import { onMount } from 'svelte';
	import EmergencySosButton from '$lib/components/EmergencySosButton.svelte';
	import IncidentCard from '$lib/components/IncidentCard.svelte';
	import MapPinView from '$lib/components/MapPinView.svelte';
	import PlaceSearch from '$lib/components/PlaceSearch.svelte';
	import ReportModal from '$lib/components/ReportModal.svelte';
	import AlertTag from '$lib/components/ui/AlertTag.svelte';
	import BrandMark from '$lib/components/ui/BrandMark.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import IconButton from '$lib/components/ui/IconButton.svelte';
	import LiveStatus from '$lib/components/ui/LiveStatus.svelte';
	import Notice from '$lib/components/ui/Notice.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import SettingsPanel from '$lib/components/ui/SettingsPanel.svelte';
	import { CATEGORY_ICON } from '$lib/components/ui/icons';
	import { fetchIncidents, fetchSiteAlert } from '$lib/api';
	import { i18n, LOCALES, clockTime, t, timeAgo } from '$lib/i18n/index.svelte';
	import { createSupabaseBrowserClient, supabaseConfigProblem } from '$lib/supabaseClient';
	import { CATEGORY_META, MAP } from '$lib/tokens';
	import {
		CATEGORIES,
		HOME_VIEWPORT,
		TIME_WINDOWS,
		type Category,
		type Incident,
		type SiteAlert,
		type TileBounds,
		type Viewport
	} from '$lib/types';
	import type { PlaceHit } from '$lib/places';
	import { chrome, mapCommand } from '$lib/ui.svelte';

	let { data } = $props();
	let liveAlert = $state<SiteAlert | null | undefined>(undefined);
	const alert = $derived(liveAlert === undefined ? data.alert : liveAlert);

	let mode = $state<'pins' | 'grid'>('pins');
	let hours = $state(24);
	let categories = $state<Category[]>([]);
	let cellKm = $state(5);
	let viewport = $state<Viewport>({ center: HOME_VIEWPORT.center, zoom: HOME_VIEWPORT.zoom });
	let bounds = $state<TileBounds | null>(null);
	let focusNonce = $state(0);
	let focusBounds = $state<[[number, number], [number, number]] | null>(null);
	let loaded = $state<Incident[]>([]);
	let selectedId = $state<string | null>(null);
	let sheetSnap = $state<'peek' | 'full'>('peek');
	let reportOpen = $state(false);
	let pickingPin = $state(false);
	let draftPin = $state<{ lng: number; lat: number } | null>(null);
	let pinBeforePick: { lng: number; lat: number } | null = null;
	let pickPlaced = $state(false);
	let flyNonce = $state(0);
	let flyTarget = $state<PlaceHit | null>(null);
	let pendingPlace = $state('');
	let placeName = $state('');
	let loading = $state(false);
	let everLoaded = $state(false);
	let error = $state('');
	let offline = $state(false);
	let updatedAt = $state<Date | null>(null);
	let now = $state(Date.now());
	let settingsOpen = $state(false);
	let timeMenuOpen = $state(false);
	let seenCommand = 0;
	const configProblem = supabaseConfigProblem();

	// Categories are filtered on the client so every chip can show its count.
	const incidents = $derived(
		categories.length ? loaded.filter((incident) => categories.includes(incident.category)) : loaded
	);
	const counts = $derived(
		loaded.reduce<Partial<Record<Category, number>>>((acc, incident) => {
			acc[incident.category] = (acc[incident.category] ?? 0) + 1;
			return acc;
		}, {})
	);
	const selected = $derived(loaded.find((incident) => incident.id === selectedId) ?? null);
	const windowLabel = $derived(t(`s${hours}`));
	const statusState = $derived(
		loading ? 'updating' : offline ? 'offline' : error ? 'error' : ('live' as const)
	);
	const updatedLabel = $derived.by(() => {
		void now;
		return updatedAt ? timeAgo(updatedAt.toISOString(), now) : t('just_now');
	});
	const localeShort = $derived(LOCALES.find((locale) => locale.code === i18n.locale)?.short ?? 'EN');
	const showEmpty = $derived(everLoaded && !loading && !error && !offline && incidents.length === 0 && mode === 'pins');
	const showSkeleton = $derived(loading && !everLoaded);

	async function load() {
		const supabase = createSupabaseBrowserClient();
		if (!supabase) {
			error = '';
			loaded = [];
			return;
		}
		loading = true;
		error = '';
		try {
			loaded = await fetchIncidents(supabase, hours, [], mode === 'pins' ? bounds : null);
			offline = false;
			everLoaded = true;
			updatedAt = new Date();
			if (selectedId && !loaded.some((incident) => incident.id === selectedId)) selectedId = null;
		} catch (cause) {
			if (cause instanceof TypeError || !navigator.onLine) offline = true;
			else error = cause instanceof Error ? cause.message : t('load_err_title');
		} finally {
			loading = false;
		}
	}

	function openReport() {
		draftPin = null;
		pickingPin = false;
		pendingPlace = '';
		placeName = '';
		selectedId = null;
		reportOpen = true;
	}

	function select(id: string) {
		selectedId = id;
		sheetSnap = 'peek';
	}

	function drillDown(tile: TileBounds) {
		bounds = tile;
		focusBounds = [
			[tile.minLng, tile.minLat],
			[tile.maxLng, tile.maxLat]
		];
		focusNonce += 1;
		mode = 'pins';
	}

	function clearZone() {
		bounds = null;
		focusBounds = null;
	}

	function onCreated(id: string, lng: number, lat: number) {
		reportOpen = false;
		pickingPin = false;
		draftPin = null;
		mode = 'pins';
		bounds = null;
		focusBounds = null;
		viewport = { center: [lng, lat], zoom: 15 };
		selectedId = id;
		sheetSnap = 'peek';
		void load();
	}

	function startPick() {
		pinBeforePick = draftPin;
		pickPlaced = false;
		pendingPlace = '';
		mode = 'pins';
		pickingPin = true;
	}

	function cancelPick() {
		draftPin = pinBeforePick;
		pendingPlace = '';
		pickingPin = false;
	}

	function confirmPick() {
		if (pendingPlace) placeName = pendingPlace.slice(0, 240);
		pickingPin = false;
	}

	function choosePlace(place: PlaceHit) {
		draftPin = { lng: place.lng, lat: place.lat };
		pickPlaced = true;
		pendingPlace = place.label;
		flyTarget = place;
		flyNonce += 1;
	}

	function toggleCategory(item: Category) {
		categories = categories.includes(item)
			? categories.filter((value) => value !== item)
			: [...categories, item];
	}

	$effect(() => {
		chrome.sheetOpen = !!selected || reportOpen || pickingPin;
	});

	$effect(() => {
		void hours;
		void bounds;
		void mode;
		if (browser) void load();
	});

	$effect(() => {
		if (!browser || mapCommand.nonce === 0 || mapCommand.nonce === seenCommand) return;
		seenCommand = mapCommand.nonce;
		mode = 'pins';
		categories = [];
		bounds = null;
		focusBounds = null;
		viewport = { center: [mapCommand.lng, mapCommand.lat], zoom: 15 };
		selectedId = mapCommand.incidentId;
		sheetSnap = 'peek';
		void load();
	});

	onMount(() => {
		offline = !navigator.onLine;
		const goOnline = () => {
			offline = false;
			void load();
		};
		const goOffline = () => (offline = true);
		window.addEventListener('online', goOnline);
		window.addEventListener('offline', goOffline);
		const tick = setInterval(() => (now = Date.now()), 30000);

		const supabase = createSupabaseBrowserClient();
		const refresh = () => void load();
		const refreshAlert = () => {
			if (!supabase) return;
			void fetchSiteAlert(supabase)
				.then((next) => (liveAlert = next))
				.catch(() => undefined);
		};
		const channel = supabase
			?.channel('crisis-feed')
			.on('postgres_changes', { event: '*', schema: 'public', table: 'incidents' }, refresh)
			.on('postgres_changes', { event: '*', schema: 'public', table: 'incident_comments' }, refresh)
			.on('postgres_changes', { event: '*', schema: 'public', table: 'incident_confirmations' }, refresh)
			.on('postgres_changes', { event: '*', schema: 'public', table: 'site_alerts' }, refreshAlert)
			.subscribe();
		return () => {
			window.removeEventListener('online', goOnline);
			window.removeEventListener('offline', goOffline);
			clearInterval(tick);
			if (supabase && channel) void supabase.removeChannel(channel);
		};
	});
</script>

<svelte:window
	onkeydown={(event) => {
		if (event.key !== 'Escape') return;
		if (settingsOpen || timeMenuOpen) {
			settingsOpen = false;
			timeMenuOpen = false;
		} else if (pickingPin) cancelPick();
		else {
			reportOpen = false;
			selectedId = null;
		}
	}}
/>

{#snippet chips()}
	<div class="chip-rail noscroll flex gap-1.5 overflow-x-auto overscroll-x-contain px-2">
		{#snippet chip(on: boolean, label: string, onclick: () => void, category?: Category)}
			<button type="button" aria-pressed={on} class="flex h-11 shrink-0 items-center py-1" {onclick}>
				<span
					class="inline-flex h-9 items-center gap-1.5 rounded-[10px] border text-label whitespace-nowrap transition-colors {category
						? 'pr-3 pl-2'
						: 'px-3'} {on
						? 'border-accent bg-[var(--accent-tint-strong)] font-bold text-fg'
						: 'border-line-subtle bg-surface-raised font-semibold text-fg-secondary hover:text-fg'}"
				>
					{#if category}
						{@const Glyph = CATEGORY_ICON[category]}
						<span
							class="grid h-[22px] w-[22px] place-items-center rounded-[7px]"
							style="background:{CATEGORY_META[category].color};color:{category === 'sos' ? '#fff' : 'var(--color-cat-glyph)'}"
						>
							<Glyph size={14} strokeWidth={2.5} />
						</span>
					{/if}
					{label}
					{#if category && counts[category]}
						<span class="num text-micro font-semibold text-fg-tertiary">{counts[category]}</span>
					{/if}
				</span>
			</button>
		{/snippet}
		{@render chip(categories.length === 0, t('all'), () => (categories = []))}
		{#each CATEGORIES as item (item)}
			{@render chip(categories.includes(item), t(`cat_${item}`), () => toggleCategory(item), item)}
		{/each}
		<span aria-hidden="true" class="w-0.5 shrink-0"></span>
	</div>
{/snippet}

{#snippet zoneRow()}
	{#if bounds && mode === 'pins'}
		<div class="mx-1.5 mb-1.5 flex h-10 items-center gap-2 rounded-[10px] bg-accent-tint pr-1 pl-3 text-label font-normal text-fg">
			<SquareDashed size={16} class="shrink-0 text-fg-accent" />
			<span class="min-w-0 flex-1 truncate">{t('showing_square', { km: cellKm })}</span>
			<Button variant="ghost" size="sm" icon={X} class="!text-fg-accent" onclick={clearZone}>{t('clear')}</Button>
		</div>
	{/if}
{/snippet}

{#snippet banner()}
	{#if configProblem}
		<Notice tone="warning">{configProblem}</Notice>
	{:else if offline}
		<Notice tone="offline" title={t('offline_title')}>
			{t('offline_body', { t: updatedAt ? clockTime(updatedAt) : '—' })}
			{#snippet action()}
				<Button size="sm" variant="secondary" onclick={() => void load()}>{t('retry')}</Button>
			{/snippet}
		</Notice>
	{:else if error}
		<Notice tone="danger" title={t('load_err_title')}>
			{t('check_conn')}
			{#snippet action()}
				<Button size="sm" variant="secondary" icon={RefreshCw} onclick={() => void load()}>{t('retry')}</Button>
			{/snippet}
		</Notice>
	{/if}
{/snippet}

<div class="absolute inset-x-0 top-0 bottom-0 lg:top-16">
	<MapPinView
		{incidents}
		{viewport}
		{focusNonce}
		{focusBounds}
		{flyNonce}
		{flyTarget}
		picking={pickingPin}
		{draftPin}
		showZones={mode === 'grid'}
		{cellKm}
		theme={chrome.theme}
		dimmed={pickingPin}
		controls={!pickingPin}
		controlsClass="bottom-[calc(128px+env(safe-area-inset-bottom))] lg:bottom-[132px] transition-[right] duration-[280ms] ease-[var(--ease-sheet)] {selected
			? 'lg:right-[432px]'
			: ''}"
		onViewport={(next) => (viewport = next)}
		onSelect={select}
		onDrillDown={drillDown}
		onPick={(lng, lat) => {
			draftPin = { lng, lat };
			pickPlaced = true;
		}}
	/>

	{#if mode === 'grid' && !pickingPin}
		<div
			class="glass absolute bottom-[calc(112px+env(safe-area-inset-bottom))] left-3 z-[15] flex w-fit items-center gap-3 rounded-lg py-1.5 pr-1.5 pl-3 lg:bottom-6"
		>
			<div>
				<p class="mb-1 text-micro font-bold text-fg-secondary">{t('reports_per_square')}</p>
				<div class="flex gap-0.5">
					{#each MAP.heat as [at, color], index (at)}
						<div class="grid justify-items-center gap-0.5">
							<span class="h-2.5 w-7 rounded-[3px]" style="background:{color};box-shadow:inset 0 0 0 1px {MAP.heatLine}"></span>
							<span class="num text-[10px] leading-3 text-fg-tertiary">{index === MAP.heat.length - 1 ? `${at}+` : at}</span>
						</div>
					{/each}
				</div>
			</div>
			<div role="group" aria-label={t('square_size')} class="flex items-center rounded-md border border-line-subtle bg-surface-raised">
				<IconButton icon={Minus} label={t('smaller')} size="sm" disabled={cellKm <= 1} onclick={() => (cellKm = Math.max(1, cellKm - 1))} />
				<span class="num min-w-10 text-center text-label font-bold text-fg">{cellKm} km</span>
				<IconButton icon={Plus} label={t('larger')} size="sm" disabled={cellKm >= 10} onclick={() => (cellKm = Math.min(10, cellKm + 1))} />
			</div>
		</div>
	{/if}

	{#if (showSkeleton || showEmpty) && !pickingPin && !reportOpen && !selected}
		<div
			class="rise absolute inset-x-3 bottom-[calc(120px+env(safe-area-inset-bottom))] z-[15] rounded-lg border border-line-strong bg-surface-sheet p-3.5 shadow-pop lg:right-auto lg:bottom-6 lg:left-1/2 lg:w-[380px] lg:-translate-x-1/2"
		>
			{#if showSkeleton}
				<div class="flex items-center gap-3">
					<span class="shimmer block h-10 w-10 rounded-md bg-surface-raised"></span>
					<div class="grid flex-1 gap-2">
						<span class="shimmer block h-3.5 w-[70%] rounded-sm bg-surface-raised"></span>
						<span class="shimmer block h-3 w-[45%] rounded-sm bg-surface-raised"></span>
					</div>
				</div>
			{:else}
				<div class="flex items-center gap-3">
					<span class="grid h-10 w-10 shrink-0 place-items-center rounded-md bg-surface-raised text-success-400">
						<ShieldCheck size={22} />
					</span>
					<div class="min-w-0 flex-1">
						<p class="font-bold">{t('no_reports_title')}</p>
						<p class="text-label font-normal text-fg-tertiary">{t('no_reports_body')}</p>
					</div>
					{#if hours < 168}
						<Button size="sm" variant="secondary" onclick={() => (hours = 168)}>{t('show_7d')}</Button>
					{/if}
				</div>
			{/if}
		</div>
	{/if}

	<!-- Desktop SOS floats bottom-right and slides left when the incident panel is open. -->
	{#if !pickingPin && !reportOpen}
		<div
			class="absolute bottom-6 z-20 hidden transition-[right] duration-[280ms] ease-[var(--ease-sheet)] lg:block"
			style:right={selected ? '444px' : '24px'}
		>
			<EmergencySosButton />
		</div>
	{/if}
</div>

{#if !pickingPin}
	<!-- Mobile top panel -->
	<div class="absolute inset-x-2 top-[calc(env(safe-area-inset-top)+8px)] z-30 lg:hidden">
	<div class="glass rounded-[18px]">
		<div class="flex h-14 items-center gap-2 pr-1.5 pl-2.5">
			<button
				type="button"
				aria-label={t('settings_aria')}
				aria-haspopup="dialog"
				class="relative -mr-1 -ml-1.5 grid h-11 w-11 shrink-0 place-items-center"
				onclick={() => (settingsOpen = true)}
			>
				<BrandMark size={32} />
				<span
					class="num absolute right-[-2px] bottom-0 h-4 min-w-5 rounded-[5px] bg-[var(--surface-inverse)] px-[3px] text-[9px] leading-4 font-bold text-[var(--text-inverse)] shadow-[0_0_0_2px_var(--surface-sheet)]"
					>{localeShort}</span
				>
			</button>
			<LiveStatus class="flex-1" state={statusState} count={incidents.length} {windowLabel} updated={updatedLabel} />
			<SegmentedControl
				label={t('map_view')}
				iconOnly
				value={mode}
				onchange={(value) => (mode = value)}
				options={[
					{ value: 'pins', label: t('pins'), icon: MapPin },
					{ value: 'grid', label: t('zones'), icon: Grid3x3 }
				]}
			/>
			<div class="relative">
				<Button
					variant="secondary"
					iconRight={ChevronDown}
					class="!gap-1 !pr-2.5 !pl-3"
					onclick={() => (timeMenuOpen = !timeMenuOpen)}
				>
					<span class="num">{windowLabel}</span>
				</Button>
				{#if timeMenuOpen}
					<button type="button" tabindex="-1" aria-label={t('close')} class="fixed inset-0 z-[1] cursor-default" onclick={() => (timeMenuOpen = false)}></button>
					<div role="menu" class="rise absolute top-[50px] right-0 z-[2] w-[236px] rounded-[14px] border border-line-strong bg-surface-sheet p-1 shadow-pop">
						<p class="px-2.5 pt-2 pb-1 text-micro font-bold tracking-caps text-fg-tertiary uppercase">{t('show_reports_from')}</p>
						{#each TIME_WINDOWS as window (window.hours)}
							<button
								type="button"
								role="menuitemradio"
								aria-checked={window.hours === hours}
								class="flex h-11 w-full items-center gap-2.5 rounded-[10px] px-2.5 text-[15px] text-fg {window.hours === hours
									? 'bg-accent-tint'
									: 'hover:bg-surface-raised'}"
								onclick={() => {
									hours = window.hours;
									timeMenuOpen = false;
								}}
							>
								<span class="num w-11 text-left font-bold">{t(`s${window.hours}`)}</span>
								<span class="flex-1 text-left text-fg-secondary">{t(`w${window.hours}`)}</span>
								{#if window.hours === hours}<Check size={18} class="text-fg-accent" />{/if}
							</button>
						{/each}
					</div>
				{/if}
			</div>
		</div>
		<div class="border-t border-line-subtle {bounds && mode === 'pins' ? '' : 'pb-0.5'}">{@render chips()}</div>
		{@render zoneRow()}
		{#if configProblem || offline || error}
			<div class="px-1.5 pb-1.5">{@render banner()}</div>
		{/if}
	</div>
		{#if alert?.active}
			<div class="mt-2 flex justify-end">
				<AlertTag message={alert.message} severity={alert.severity} />
			</div>
		{/if}
	</div>

	<!-- Desktop header -->
	<div class="absolute inset-x-0 top-0 z-30 hidden lg:block">
		<header class="flex h-16 items-center gap-4 border-b border-line-subtle bg-surface-canvas px-4">
			<BrandMark withName />
			<span class="h-7 w-px bg-line-subtle"></span>
			<LiveStatus state={statusState} count={incidents.length} {windowLabel} updated={updatedLabel} />
			<span class="flex-1"></span>
			<SegmentedControl
				label={t('map_view')}
				value={mode}
				onchange={(value) => (mode = value)}
				options={[
					{ value: 'pins', label: t('pins'), icon: MapPin },
					{ value: 'grid', label: t('zones'), icon: Grid3x3 }
				]}
			/>
			<SegmentedControl
				label={t('time_window')}
				value={hours}
				onchange={(value) => (hours = value)}
				options={TIME_WINDOWS.map((window) => ({ value: window.hours as number, label: t(`s${window.hours}`), mono: true }))}
			/>
			<div class="relative">
				<button
					type="button"
					aria-haspopup="dialog"
					aria-expanded={settingsOpen}
					aria-label={t('settings_aria')}
					class="inline-flex h-11 items-center gap-1.5 rounded-md border border-line-strong bg-surface-raised pr-2.5 pl-3 text-label font-bold text-fg hover:bg-surface-raised-hover"
					onclick={() => (settingsOpen = !settingsOpen)}
				>
					<Globe size={18} /><span class="num">{localeShort}</span><ChevronDown size={16} />
				</button>
				{#if settingsOpen && chrome.desktop}
					<button type="button" tabindex="-1" aria-label={t('close')} class="fixed inset-0 z-[1] cursor-default" onclick={() => (settingsOpen = false)}></button>
					<div class="absolute top-[50px] right-0 z-[2]">
						<SettingsPanel layout="desktop" onClose={() => (settingsOpen = false)} />
					</div>
				{/if}
			</div>
			<Button icon={Plus} onclick={openReport}>{t('report_incident')}</Button>
		</header>
		{#if configProblem || offline || error}
			<div class="px-3 pt-2">{@render banner()}</div>
		{/if}
		<div class="flex items-center gap-2 py-2 {alert?.active ? 'pr-4 pl-1' : 'px-1'}">
			<div class="glass min-w-0 overflow-hidden rounded-[14px] px-0.5 {alert?.active ? 'shrink' : 'max-w-[calc(100%-80px)]'}">
				{@render chips()}
			</div>
			{#if alert?.active}
				<AlertTag message={alert.message} severity={alert.severity} class="ml-auto shrink-0" />
			{/if}
		</div>
		{#if bounds && mode === 'pins'}
			<div class="glass ml-3 w-fit rounded-[14px] pt-1.5">{@render zoneRow()}</div>
		{/if}
	</div>
{/if}

{#if settingsOpen && !chrome.desktop}
	<SettingsPanel onClose={() => (settingsOpen = false)} />
{/if}

<!-- Mobile action bar: Report on the left, SOS on the right, in the thumb zone. -->
{#if !pickingPin && !reportOpen && !selected}
	<div
		class="pointer-events-none fixed inset-x-0 bottom-0 z-20 flex items-end gap-3 bg-gradient-to-t from-[var(--action-fade)] to-transparent px-3 pt-7 pb-[calc(12px+env(safe-area-inset-bottom))] lg:hidden"
	>
		<div class="pointer-events-auto min-w-0 flex-1 pb-2.5">
			<Button size="lg" icon={Plus} fullWidth class="shadow-[0_6px_20px_rgba(0,0,0,.4)]" onclick={openReport}>
				<span class="truncate">{t('report_incident')}</span>
			</Button>
		</div>
		<div class="pointer-events-auto shrink-0"><EmergencySosButton /></div>
	</div>
{/if}

{#if pickingPin}
	<div
		class="rise fixed inset-x-2 top-[calc(env(safe-area-inset-top)+8px)] z-40 flex flex-col overflow-hidden rounded-lg border border-line-strong bg-surface-sheet shadow-pop lg:top-[76px] lg:right-auto lg:left-1/2 lg:w-[440px] lg:-translate-x-1/2"
	>
		<PlaceSearch bias={{ lng: viewport.center[0], lat: viewport.center[1] }} onChoose={choosePlace} />
		<div class="flex items-center gap-2.5 py-2 pr-2 pl-3.5">
			<Crosshair size={20} class="shrink-0 text-fg-accent" />
			<div class="min-w-0 flex-1">
				<p class="text-[15px] font-bold">{pickPlaced ? t('pin_placed') : t('pick_title')}</p>
				<p class="text-caption text-fg-tertiary">{pickPlaced ? t('tap_move') : t('pick_sub')}</p>
			</div>
			<Button variant="ghost" onclick={cancelPick}>{t('cancel')}</Button>
		</div>
	</div>
	{#if pickPlaced}
		<div class="rise fixed inset-x-3 bottom-[calc(12px+env(safe-area-inset-bottom))] z-40 flex justify-center lg:bottom-6">
			<Button size="lg" icon={Check} fullWidth class="shadow-pop lg:!w-auto lg:min-w-[320px]" onclick={confirmPick}>{t('use_spot')}</Button>
		</div>
	{/if}
{/if}

{#if reportOpen}
	<ReportModal
		picking={pickingPin}
		lat={draftPin?.lat ?? null}
		lng={draftPin?.lng ?? null}
		{placeName}
		onClose={() => {
			reportOpen = false;
			pickingPin = false;
			draftPin = null;
			placeName = '';
			pendingPlace = '';
		}}
		{onCreated}
		onDropPin={startPick}
		onUseGps={(lat, lng) => {
			draftPin = { lng, lat };
			viewport = { center: [lng, lat], zoom: Math.max(viewport.zoom, 14) };
		}}
	/>
{/if}

{#if selected && !pickingPin && !reportOpen}
	<IncidentCard
		incident={selected}
		bind:snap={sheetSnap}
		onClose={() => (selectedId = null)}
		onChanged={() => void load()}
	/>
{/if}
