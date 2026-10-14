import {
	Ban,
	BadgeCheck,
	CarFront,
	CircleCheck,
	CircleDashed,
	CircleDot,
	Construction,
	Flame,
	HeartPulse,
	Siren,
	Store
} from 'lucide-svelte';
import type { Category, Status } from '$lib/types';

export type IconComponent = typeof Flame;

export const CATEGORY_ICON: Record<Category, IconComponent> = {
	fire: Flame,
	looting: Store,
	casualty: HeartPulse,
	accident: CarFront,
	roadblock: Construction,
	sos: Siren,
	other: CircleDot
};

export const STATUS_ICON: Record<Status, IconComponent> = {
	unverified: CircleDashed,
	verified: BadgeCheck,
	resolved: CircleCheck,
	debunked: Ban
};
