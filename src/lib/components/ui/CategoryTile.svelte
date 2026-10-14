<script lang="ts">
	import { CATEGORY_META } from '$lib/tokens';
	import type { Category } from '$lib/types';
	import { CATEGORY_ICON } from './icons';

	let {
		category,
		size = 36,
		round = false,
		class: extra = ''
	}: { category: Category; size?: number; round?: boolean; class?: string } = $props();

	const sos = $derived(category === 'sos');
	const Glyph = $derived(CATEGORY_ICON[category] ?? CATEGORY_ICON.other);
</script>

<span
	aria-hidden="true"
	class="grid shrink-0 place-items-center {extra}"
	style="width:{size}px;height:{size}px;border-radius:{round || sos ? size / 2 : Math.round(size * 0.29)}px;background:{CATEGORY_META[category]?.color ?? CATEGORY_META.other.color};color:{sos ? '#fff' : 'var(--color-cat-glyph)'}"
>
	<Glyph size={Math.round(size * 0.52)} strokeWidth={2.25} />
</span>
