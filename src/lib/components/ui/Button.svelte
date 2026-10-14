<script lang="ts">
	import { LoaderCircle } from 'lucide-svelte';
	import type { Snippet } from 'svelte';
	import type { IconComponent } from './icons';

	let {
		variant = 'primary',
		size = 'md',
		icon,
		iconRight,
		loading = false,
		fullWidth = false,
		disabled = false,
		type = 'button',
		pressed,
		class: extra = '',
		onclick,
		children
	}: {
		variant?: 'primary' | 'secondary' | 'ghost' | 'alarm' | 'inverse';
		size?: 'sm' | 'md' | 'lg';
		icon?: IconComponent;
		iconRight?: IconComponent;
		loading?: boolean;
		fullWidth?: boolean;
		disabled?: boolean;
		type?: 'button' | 'submit';
		pressed?: boolean;
		class?: string;
		onclick?: (event: MouseEvent) => void;
		children?: Snippet;
	} = $props();

	const sizes = {
		sm: 'h-9 min-w-9 px-3 text-label rounded-md',
		md: 'h-11 min-w-11 px-4 text-body rounded-md',
		lg: 'h-13 min-w-13 px-5 text-body rounded-[14px]'
	};
	const looks = {
		primary: 'bg-accent text-fg-on-accent border-transparent hover:bg-accent-hover active:bg-[var(--accent-pressed)]',
		secondary: 'bg-surface-raised text-fg border-line-strong hover:bg-surface-raised-hover',
		ghost: 'bg-transparent text-fg-secondary border-transparent hover:bg-surface-raised',
		alarm: 'bg-alarm text-white border-transparent active:bg-alarm-700',
		inverse: 'bg-[var(--surface-inverse)] text-[var(--text-inverse)] border-transparent hover:opacity-90'
	};
	const glyph = $derived(size === 'sm' ? 16 : 20);
</script>

<button
	{type}
	disabled={disabled || loading}
	aria-pressed={pressed}
	aria-busy={loading || undefined}
	class="press inline-flex items-center justify-center gap-2 border font-bold leading-5 whitespace-nowrap disabled:cursor-default {sizes[size]} {looks[variant]} {fullWidth ? 'w-full' : ''} {disabled ? 'opacity-45' : ''} {extra}"
	{onclick}
>
	{#if loading}
		<LoaderCircle size={glyph} class="spin shrink-0" />
	{:else if icon}
		{@const Glyph = icon}
		<Glyph size={glyph} class="shrink-0" />
	{/if}
	{@render children?.()}
	{#if iconRight && !loading}
		{@const Glyph = iconRight}
		<Glyph size={glyph} class="shrink-0" />
	{/if}
</button>
