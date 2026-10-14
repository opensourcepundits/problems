<script lang="ts" generics="T extends string | number">
	import type { IconComponent } from './icons';

	type Option = { value: T; label: string; icon?: IconComponent; mono?: boolean };

	let {
		options,
		value,
		onchange,
		label,
		iconOnly = false,
		fullWidth = false,
		size = 'md',
		class: extra = ''
	}: {
		options: Option[];
		value: T;
		onchange: (value: T) => void;
		label: string;
		iconOnly?: boolean;
		fullWidth?: boolean;
		size?: 'sm' | 'md';
		class?: string;
	} = $props();
</script>

<div
	role="group"
	aria-label={label}
	class="{fullWidth ? 'flex' : 'inline-flex'} {size === 'sm' ? 'h-9' : 'h-11'} shrink-0 gap-0.5 rounded-md border border-line-subtle bg-surface-raised p-[3px] {extra}"
>
	{#each options as option (option.value)}
		{@const on = option.value === value}
		<button
			type="button"
			aria-pressed={on}
			aria-label={iconOnly ? option.label : undefined}
			title={iconOnly ? option.label : undefined}
			class="inline-flex items-center justify-center gap-1.5 rounded-[9px] text-label whitespace-nowrap transition-colors {fullWidth ? 'flex-1' : ''} {iconOnly ? (size === 'sm' ? 'min-w-[30px]' : 'min-w-[38px]') : 'px-3'} {on ? 'bg-accent font-bold text-fg-on-accent' : 'font-semibold text-fg-secondary hover:text-fg'}"
			onclick={() => onchange(option.value)}
		>
			{#if option.icon}
				{@const Glyph = option.icon}
				<Glyph size={16} />
			{/if}
			{#if !iconOnly}<span class={option.mono ? 'num' : ''}>{option.label}</span>{/if}
		</button>
	{/each}
</div>
