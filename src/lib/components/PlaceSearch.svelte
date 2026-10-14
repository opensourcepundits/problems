<script lang="ts">
	import { LoaderCircle, MapPin, Search, X } from 'lucide-svelte';
	import { onMount, untrack } from 'svelte';
	import { i18n, t } from '$lib/i18n/index.svelte';
	import { photonLang, searchPlaces, type PlaceHit } from '$lib/places';

	let {
		bias,
		onChoose
	}: {
		bias: { lng: number; lat: number };
		onChoose: (place: PlaceHit) => void;
	} = $props();

	let query = $state('');
	let places = $state<PlaceHit[]>([]);
	let status = $state<'idle' | 'loading' | 'done' | 'error'>('idle');
	let active = $state(-1);
	let settled = $state('');
	let input = $state<HTMLInputElement | undefined>(undefined);
	let generation = 0;

	onMount(() => {
		if (window.matchMedia('(pointer: fine)').matches) input?.focus();
	});

	const listId = 'place-results';
	const open = $derived(places.length > 0 || status === 'loading' || status === 'error' || (status === 'done' && query.trim().length >= 2));

	$effect(() => {
		const q = query.trim();
		const locale = i18n.locale;
		places = [];
		active = -1;
		if (q.length < 2 || q === settled) {
			status = 'idle';
			return;
		}
		status = 'idle';
		const here = untrack(() => bias);
		const ticket = ++generation;
		const controller = new AbortController();
		const timer = setTimeout(() => {
			if (ticket !== generation) return;
			status = 'loading';
			places = [];
			active = -1;
			void searchPlaces(q, here, photonLang(locale), controller.signal)
				.then((found) => {
					if (ticket !== generation) return;
					places = found;
					active = found.length ? 0 : -1;
					status = 'done';
				})
				.catch((error: unknown) => {
					if (ticket !== generation) return;
					if (error instanceof Error && error.name === 'AbortError') return;
					places = [];
					active = -1;
					status = 'error';
				});
		}, 280);
		return () => {
			generation += 1;
			clearTimeout(timer);
			controller.abort();
		};
	});

	function clear() {
		query = '';
		settled = '';
		places = [];
		active = -1;
		status = 'idle';
		input?.focus();
	}

	function choose(place: PlaceHit) {
		settled = place.name;
		query = place.name;
		places = [];
		active = -1;
		status = 'idle';
		onChoose(place);
		input?.blur();
	}

	function move(delta: number) {
		if (!places.length) return;
		active = (active + delta + places.length) % places.length;
		document.getElementById(`place-opt-${active}`)?.scrollIntoView({ block: 'nearest' });
	}

	function onKeydown(event: KeyboardEvent) {
		if (event.key === 'ArrowDown') {
			event.preventDefault();
			move(1);
		} else if (event.key === 'ArrowUp') {
			event.preventDefault();
			move(-1);
		} else if (event.key === 'Enter') {
			event.preventDefault();
			const place = places[active] ?? places[0];
			if (place) choose(place);
		} else if (event.key === 'Escape' && (query || places.length)) {
			event.stopPropagation();
			clear();
		}
	}
</script>

<div class="border-b border-line-subtle">
	<div class="relative flex items-center focus-within:bg-accent-tint">
		<Search size={18} class="pointer-events-none absolute left-3.5 text-fg-tertiary" />
		<input
			bind:this={input}
			class="h-12 w-full bg-transparent pr-12 pl-10 text-body text-fg outline-none placeholder:text-fg-tertiary"
			type="text"
			role="combobox"
			inputmode="search"
			enterkeyhint="search"
			autocomplete="off"
			autocorrect="off"
			autocapitalize="off"
			spellcheck="false"
			aria-label={t('search_place')}
			aria-autocomplete="list"
			aria-expanded={places.length > 0}
			aria-controls={listId}
			aria-activedescendant={active >= 0 ? `place-opt-${active}` : undefined}
			placeholder={t('search_place_ph')}
			bind:value={query}
			onkeydown={onKeydown}
		/>
		{#if status === 'loading'}
			<LoaderCircle size={18} class="spin absolute right-3.5 text-fg-tertiary" />
		{:else if query}
			<button
				type="button"
				class="absolute right-1 grid h-11 w-11 place-items-center rounded-md text-fg-secondary hover:bg-surface-raised hover:text-fg"
				aria-label={t('clear_search')}
				onclick={clear}
			>
				<X size={18} />
			</button>
		{/if}
	</div>
	{#if open}
		{#if places.length}
			<ul id={listId} role="listbox" class="max-h-[min(15rem,calc(100dvh-280px))] overflow-y-auto overscroll-contain">
				{#each places as place, index (place.id)}
					<li>
						<button
							id="place-opt-{index}"
							type="button"
							role="option"
							aria-selected={index === active}
							class="flex w-full items-start gap-2.5 px-3.5 py-2.5 text-left {index === active
								? 'bg-accent-tint'
								: 'hover:bg-surface-raised'}"
							onmouseenter={() => (active = index)}
							onclick={() => choose(place)}
						>
							<MapPin size={16} class="mt-0.5 shrink-0 text-fg-accent" />
							<span class="min-w-0">
								<span class="block truncate text-body-sm font-bold text-fg">{place.name}</span>
								{#if place.label !== place.name}
									<span class="block truncate text-caption font-normal text-fg-tertiary">{place.label.slice(place.name.length + 2)}</span>
								{/if}
							</span>
						</button>
					</li>
				{/each}
			</ul>
			<p class="px-3.5 py-1.5 text-micro text-fg-tertiary">{t('places_credit')}</p>
		{:else if status === 'loading'}
			<p class="px-3.5 py-2.5 text-caption text-fg-tertiary">{t('searching_places')}</p>
		{:else if status === 'error'}
			<p class="px-3.5 py-2.5 text-caption text-alarm-400">{t('search_failed')}</p>
		{:else}
			<p class="px-3.5 py-2.5 text-caption text-fg-tertiary">{t('no_places')}</p>
		{/if}
	{/if}
</div>
