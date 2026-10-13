<script lang="ts">
	import { ImagePlus, LocateFixed, X } from 'lucide-svelte';
	import { onDestroy } from 'svelte';
	import { createIncident, currentPosition, uploadEvidence } from '$lib/api';
	import { prepareMedia } from '$lib/media';
	import { createSupabaseBrowserClient } from '$lib/supabaseClient';
	import { CATEGORIES, CATEGORY_LABEL, SEVERITIES, type Category, type Severity } from '$lib/types';
	import { pushToast } from '$lib/ui.svelte';

	let {
		userId,
		onClose,
		onCreated
	}: {
		userId: string;
		onClose: () => void;
		onCreated: (id: string, lng: number, lat: number) => void;
	} = $props();

	let title = $state('');
	let description = $state('');
	let category = $state<Category>('fire');
	let severity = $state<Severity>('medium');
	let addressHint = $state('');
	let lat = $state<number | null>(null);
	let lng = $state<number | null>(null);
	let busy = $state(false);
	let locating = $state(false);
	let previews = $state<{ url: string; file: File; video: boolean }[]>([]);

	const videoWarning = $derived(previews.some((item) => item.video));

	onDestroy(() => {
		for (const preview of previews) URL.revokeObjectURL(preview.url);
	});

	async function useMyLocation() {
		locating = true;
		try {
			const position = await currentPosition();
			lat = position.coords.latitude;
			lng = position.coords.longitude;
		} catch (cause) {
			pushToast(cause instanceof Error ? cause.message : 'Could not read your location.', 'err');
		} finally {
			locating = false;
		}
	}

	async function onFiles(event: Event) {
		const input = event.currentTarget as HTMLInputElement;
		const selected = [...(input.files ?? [])];
		input.value = '';
		for (const file of selected) {
			if (previews.length >= 4) {
				pushToast('You can attach up to 4 files.', 'err');
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
				pushToast(cause instanceof Error ? cause.message : 'Could not prepare that file.', 'err');
			}
		}
		previews = previews;
	}

	function removePreview(index: number) {
		const removed = previews[index];
		if (!removed) return;
		URL.revokeObjectURL(removed.url);
		previews = previews.filter((_, itemIndex) => itemIndex !== index);
	}

	async function submit(event: SubmitEvent) {
		event.preventDefault();
		if (lat === null || lng === null) {
			pushToast('Add your location before submitting.', 'err');
			return;
		}
		const supabase = createSupabaseBrowserClient();
		if (!supabase) {
			pushToast('Supabase is not configured.', 'err');
			return;
		}
		busy = true;
		try {
			const mediaUrls: string[] = [];
			for (const preview of previews) {
				mediaUrls.push(await uploadEvidence(supabase, userId, preview.file));
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
				isSos: false
			});
			pushToast('Report submitted and logged.');
			onCreated(id, lng, lat);
		} catch (cause) {
			pushToast(cause instanceof Error ? cause.message : 'Could not submit the report.', 'err');
		} finally {
			busy = false;
		}
	}
</script>

<div class="fixed inset-0 z-50 flex items-end justify-center bg-slate-950/70 p-0 sm:items-center sm:p-6">
	<form
		class="max-h-[92dvh] w-full max-w-lg overflow-y-auto rounded-t-3xl bg-slate-900 p-5 shadow-2xl sm:rounded-3xl"
		onsubmit={submit}
	>
		<div class="mb-4 flex items-start justify-between gap-3">
			<div>
				<p class="text-xs font-semibold tracking-[0.16em] text-red-300 uppercase">New report</p>
				<h2 class="text-xl font-semibold text-white">What is happening?</h2>
			</div>
			<button type="button" class="rounded-full p-2 text-slate-300 hover:bg-slate-800" onclick={onClose} aria-label="Close">
				<X size={18} />
			</button>
		</div>

		<label class="mb-3 block text-sm text-slate-300">
			Title
			<input
				class="mt-1 w-full rounded-xl border border-slate-700 bg-slate-950 px-3 py-2 text-white outline-none focus:border-red-500"
				bind:value={title}
				required
				maxlength="160"
				placeholder="Fire on the market road"
			/>
		</label>

		<div class="mb-3 grid grid-cols-2 gap-3">
			<label class="text-sm text-slate-300">
				Category
				<select class="mt-1 w-full rounded-xl border border-slate-700 bg-slate-950 px-3 py-2 text-white" bind:value={category}>
					{#each CATEGORIES.filter((item) => item !== 'sos') as item (item)}
						<option value={item}>{CATEGORY_LABEL[item]}</option>
					{/each}
				</select>
			</label>
			<label class="text-sm text-slate-300">
				Severity
				<select class="mt-1 w-full rounded-xl border border-slate-700 bg-slate-950 px-3 py-2 text-white capitalize" bind:value={severity}>
					{#each SEVERITIES as item (item)}
						<option value={item}>{item}</option>
					{/each}
				</select>
			</label>
		</div>

		<label class="mb-3 block text-sm text-slate-300">
			Description
			<textarea
				class="mt-1 min-h-24 w-full rounded-xl border border-slate-700 bg-slate-950 px-3 py-2 text-white outline-none focus:border-red-500"
				bind:value={description}
				maxlength="4000"
				placeholder="What did you see, and is anyone hurt?"
			></textarea>
		</label>

		<label class="mb-3 block text-sm text-slate-300">
			Address hint
			<input
				class="mt-1 w-full rounded-xl border border-slate-700 bg-slate-950 px-3 py-2 text-white outline-none focus:border-red-500"
				bind:value={addressHint}
				maxlength="240"
				placeholder="Near the north gate"
			/>
		</label>

		<div class="mb-3 flex items-center justify-between gap-3 rounded-2xl border border-slate-700 px-3 py-3">
			<p class="text-sm text-slate-300">
				{#if lat !== null && lng !== null}
					{lat.toFixed(5)}, {lng.toFixed(5)}
				{:else}
					Location required
				{/if}
			</p>
			<button
				type="button"
				class="inline-flex items-center gap-1 rounded-full bg-slate-800 px-3 py-2 text-sm text-white"
				onclick={useMyLocation}
				disabled={locating}
			>
				<LocateFixed size={16} />
				{locating ? 'Locating…' : 'Use GPS'}
			</button>
		</div>

		<div class="mb-4">
			<label class="inline-flex cursor-pointer items-center gap-2 rounded-full bg-slate-800 px-3 py-2 text-sm text-white">
				<ImagePlus size={16} />
				Add photo or video
				<input class="sr-only" type="file" accept="image/*,video/mp4,video/webm,video/quicktime" multiple onchange={onFiles} />
			</label>
			<p class="mt-2 text-xs text-slate-400">
				Photos are re-encoded in the browser so EXIF and GPS are removed before upload.
			</p>
			{#if videoWarning}
				<p class="mt-2 text-xs text-amber-300">
					Video files can still contain location metadata. Prefer a photo if you need to hide where it was taken.
				</p>
			{/if}
			{#if previews.length > 0}
				<div class="mt-3 grid grid-cols-4 gap-2">
					{#each previews as preview, index (preview.url)}
						<div class="relative">
							{#if preview.video}
								<!-- svelte-ignore a11y_media_has_caption -->
								<video class="h-16 w-full rounded-lg object-cover" src={preview.url} muted></video>
							{:else}
								<img class="h-16 w-full rounded-lg object-cover" src={preview.url} alt="" />
							{/if}
							<button
								type="button"
								class="absolute top-1 right-1 rounded-full bg-slate-950/80 p-1"
								aria-label="Remove file"
								onclick={() => removePreview(index)}
							>
								<X size={12} />
							</button>
						</div>
					{/each}
				</div>
			{/if}
		</div>

		<button
			class="w-full rounded-2xl bg-red-600 py-3 font-semibold text-white disabled:opacity-60"
			type="submit"
			disabled={busy}
		>
			{busy ? 'Submitting…' : 'Submit report'}
		</button>
	</form>
</div>
