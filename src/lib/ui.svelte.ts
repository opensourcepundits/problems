export type ToastTone = 'ok' | 'err' | 'sos' | 'info' | 'offline';

export type Toast = {
	id: number;
	message: string;
	tone: ToastTone;
	title?: string;
	action?: { label: string; run: () => void };
};

export const toaster = $state<{ items: Toast[] }>({ items: [] });

let toastSeq = 0;

export function dismissToast(id: number) {
	const index = toaster.items.findIndex((item) => item.id === id);
	if (index >= 0) toaster.items.splice(index, 1);
}

export function pushToast(
	message: string,
	tone: ToastTone = 'ok',
	extra: Pick<Toast, 'title' | 'action'> = {}
) {
	const id = ++toastSeq;
	toaster.items.push({ id, message, tone, ...extra });
	setTimeout(() => dismissToast(id), 4600);
}

export const mapCommand = $state<{
	nonce: number;
	lng: number;
	lat: number;
	incidentId: string | null;
}>({
	nonce: 0,
	lng: 0,
	lat: 0,
	incidentId: null
});

export function flyToIncident(lng: number, lat: number, incidentId: string | null) {
	mapCommand.lng = lng;
	mapCommand.lat = lat;
	mapCommand.incidentId = incidentId;
	mapCommand.nonce += 1;
}

export type Theme = 'dark' | 'light';

/** Shown after an SOS pin is on the map, so the reporter can dial emergency services. */
export const sosCalls = $state({ open: false });

/** Shared chrome state: theme, breakpoint, and whether a sheet covers the action bar. */
export const chrome = $state<{ theme: Theme; desktop: boolean; sheetOpen: boolean }>({
	theme: 'dark',
	desktop: false,
	sheetOpen: false
});

const THEME_KEY = 'cr-theme';

export function initTheme() {
	try {
		chrome.theme = localStorage.getItem(THEME_KEY) === 'light' ? 'light' : 'dark';
	} catch {
		chrome.theme = 'dark';
	}
	applyTheme();
}

export function setTheme(theme: Theme) {
	chrome.theme = theme;
	try {
		localStorage.setItem(THEME_KEY, theme);
	} catch {
		// non-fatal
	}
	applyTheme();
}

function applyTheme() {
	const root = document.documentElement;
	if (chrome.theme === 'light') root.dataset.theme = 'light';
	else delete root.dataset.theme;
	document
		.querySelector('meta[name="theme-color"]:not([media])')
		?.setAttribute('content', chrome.theme === 'light' ? '#f3f5f8' : '#0c1015');
}

/** Tracks the 1024px breakpoint. Returns a cleanup function. */
export function watchBreakpoint() {
	const query = window.matchMedia('(min-width: 1024px)');
	const sync = () => (chrome.desktop = query.matches);
	sync();
	query.addEventListener('change', sync);
	return () => query.removeEventListener('change', sync);
}
