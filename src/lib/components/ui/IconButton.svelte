<script lang="ts">
	import type { IconComponent } from './icons';

	let {
		icon,
		label,
		variant = 'ghost',
		size = 'md',
		pressed,
		disabled = false,
		class: extra = '',
		onclick
	}: {
		icon: IconComponent;
		label: string;
		variant?: 'ghost' | 'raised' | 'overlay' | 'primary' | 'media';
		size?: 'sm' | 'md' | 'lg';
		pressed?: boolean;
		disabled?: boolean;
		class?: string;
		onclick?: (event: MouseEvent) => void;
	} = $props();

	const sizes = { sm: 'h-9 w-9', md: 'h-11 w-11', lg: 'h-13 w-13' };
	const looks = {
		ghost: 'bg-transparent text-fg-secondary border-transparent hover:bg-surface-raised',
		raised: 'bg-surface-raised text-fg border-line-subtle hover:bg-surface-raised-hover',
		overlay: 'glass text-fg',
		primary: 'bg-accent text-fg-on-accent border-transparent hover:bg-accent-hover',
		media: 'bg-[rgba(7,9,12,.66)] text-white border-[rgba(255,255,255,.12)]'
	};
	const on = 'bg-[var(--accent-tint-strong)] text-fg-accent border-accent';
	const Glyph = $derived(icon);
</script>

<button
	type="button"
	aria-label={label}
	title={label}
	aria-pressed={pressed}
	{disabled}
	class="press grid shrink-0 place-items-center rounded-md border p-0 disabled:cursor-default disabled:opacity-45 {sizes[size]} {pressed ? on : looks[variant]} {extra}"
	{onclick}
>
	<Glyph size={size === 'sm' ? 18 : 20} />
</button>
