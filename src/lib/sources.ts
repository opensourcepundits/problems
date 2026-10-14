// Source links: where a report was seen (a Facebook post such as Mopays.com, a reel, a news article).
// Mirrors public.is_allowed_source_url in supabase/source_links.sql; keep both lists in sync.

const HOSTS: Record<string, string> = {
	'facebook.com': 'Facebook',
	'fb.watch': 'Facebook',
	'fb.com': 'Facebook',
	'instagram.com': 'Instagram',
	'youtube.com': 'YouTube',
	'youtu.be': 'YouTube',
	'tiktok.com': 'TikTok',
	'x.com': 'X',
	'twitter.com': 'X',
	'mopays.com': 'Mopays.com',
	'defimedia.info': 'Defi Media',
	'lexpress.mu': "l'express",
	'lemauricien.com': 'Le Mauricien',
	'topnews.mu': 'Top News',
	'ionnews.mu': 'ION News',
	'inside.news': 'Inside News',
	'zinfos974.com': 'Zinfos974'
};

/** Facebook path segments that are not page names. */
const FACEBOOK_RESERVED = new Set(['watch', 'reel', 'share', 'story.php', 'permalink.php', 'photo', 'photo.php', 'video.php', 'groups', 'events', 'plugins']);

/** Well-known Mauritian pages, shown with their proper names. */
const FACEBOOK_PAGES: Record<string, string> = {
	mopays: 'Mopays.com',
	defimedia: 'Defi Media',
	lexpress: "l'express",
	topnewsmu: 'Top News',
	ionnewsmu: 'ION News'
};

export type SourceInfo = {
	url: string;
	/** Platform or publisher, e.g. "Facebook" or "Defi Media". */
	site: string;
	/** Who posted it when we can tell, e.g. "Mopays.com". */
	publisher: string | null;
	/** Short, readable form of the link for display. */
	display: string;
	kind: 'video' | 'post' | 'article';
	/** Facebook video plugin URL, loaded only when the viewer taps Play. */
	embed: string | null;
};

function matchHost(hostname: string): string | null {
	const host = hostname.toLowerCase().replace(/^www\.|^m\.|^web\.|^mbasic\./, '');
	for (const allowed of Object.keys(HOSTS)) {
		if (host === allowed || host.endsWith(`.${allowed}`)) return allowed;
	}
	return null;
}

/** Parses a pasted link. Returns null if it is not an allowed https source. */
export function parseSource(raw: string | null | undefined): SourceInfo | null {
	const text = (raw ?? '').trim();
	if (!text || text.length > 500 || /\s/.test(text)) return null;
	let url: URL;
	try {
		url = new URL(text);
	} catch {
		return null;
	}
	if (url.protocol !== 'https:') return null;
	const host = matchHost(url.hostname);
	if (!host) return null;

	const site = HOSTS[host];
	const segments = url.pathname.split('/').filter(Boolean);
	const facebook = site === 'Facebook';
	const video =
		facebook
			? host === 'fb.watch' || /\/(videos|reel|reels|watch)\b/.test(url.pathname) || url.searchParams.has('v')
			: /youtube|youtu\.be|tiktok/.test(host) || /\/(reel|reels)\//.test(url.pathname);

	let publisher: string | null = null;
	if (facebook && segments[0] && !FACEBOOK_RESERVED.has(segments[0].toLowerCase())) {
		publisher = FACEBOOK_PAGES[segments[0].toLowerCase()] ?? segments[0];
	} else if (!facebook && !['Instagram', 'YouTube', 'TikTok', 'X'].includes(site)) {
		publisher = site;
	}

	const path = segments.slice(0, 2).join('/');
	const display = `${host}${path ? `/${path}` : ''}${segments.length > 2 ? '/…' : ''}`;

	return {
		url: url.toString(),
		site,
		publisher,
		display,
		kind: video ? 'video' : facebook || site === 'Instagram' || site === 'X' ? 'post' : 'article',
		embed:
			facebook && video
				? `https://www.facebook.com/plugins/video.php?href=${encodeURIComponent(url.toString())}&show_text=false&width=500`
				: null
	};
}
