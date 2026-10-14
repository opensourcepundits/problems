import { LOCALES, MESSAGES, type Locale, type MessageKey } from './messages';

export { LOCALES, type Locale };

const STORAGE_KEY = 'cr-locale';

/** A few strings the handoff table does not cover. Kreol and Italian are drafts like the rest. */
const EXTRA: Record<Locale, Record<string, string>> = {
	en: {
		need_source: 'source link',
		source_label: 'Source link',
		source_ph: 'Paste a Facebook post or news link',
		source_hint: 'Where you saw it, e.g. a Mopays.com video. It stays on the original site.',
		source_invalid: 'Use a full https:// link from Facebook, Instagram, YouTube, TikTok, X or a Mauritian news site.',
		source_title: 'Original source',
		source_video: 'Video on {site}',
		source_post: 'Post on {site}',
		source_article: 'Article on {site}',
		open_on: 'Open on {site}',
		play_here: 'Play here',
		embed_note: 'Playing loads the video from Facebook.',
		via: 'via {site}',
		remove_link: 'Remove link',
		rate_limited_report: 'You have sent several reports in a short time. Try again in {min} min.',
		rate_limited_sos: 'SOS limit reached on this device. Call 999 now. You can send again in {min} min.',
		max_files: 'You can attach up to 4 files.',
		loc_timeout: 'Location request timed out. Try again with a clear sky view.',
		not_configured: 'The live map is not connected yet.',
		comment_failed: 'Could not post the update.',
		vote_failed: 'Could not save your vote.'
	},
	fr: {
		need_source: 'lien source',
		source_label: 'Lien source',
		source_ph: 'Collez un lien Facebook ou d’article',
		source_hint: 'Où vous l’avez vu, par ex. une vidéo de Mopays.com. Elle reste sur le site d’origine.',
		source_invalid: 'Utilisez un lien https:// complet de Facebook, Instagram, YouTube, TikTok, X ou d’un site d’info mauricien.',
		source_title: 'Source d’origine',
		source_video: 'Vidéo sur {site}',
		source_post: 'Publication sur {site}',
		source_article: 'Article sur {site}',
		open_on: 'Ouvrir sur {site}',
		play_here: 'Lire ici',
		embed_note: 'La lecture charge la vidéo depuis Facebook.',
		via: 'via {site}',
		remove_link: 'Retirer le lien',
		rate_limited_report: 'Vous avez envoyé plusieurs signalements en peu de temps. Réessayez dans {min} min.',
		rate_limited_sos: 'Limite de SOS atteinte sur cet appareil. Appelez le 999 maintenant. Nouvel envoi possible dans {min} min.',
		max_files: 'Vous pouvez joindre 4 fichiers au maximum.',
		loc_timeout: 'La localisation a expiré. Réessayez à découvert.',
		not_configured: 'La carte en direct n’est pas encore connectée.',
		comment_failed: 'Impossible de publier la mise à jour.',
		vote_failed: 'Impossible d’enregistrer votre vote.'
	},
	mfe: {
		need_source: 'lien sours',
		source_label: 'Lien sours',
		source_ph: 'Koll enn lien Facebook ouswa enn lartik',
		source_hint: 'Kot ou finn trouv li, par egzanp enn video Mopays.com. Li res lor sit orizinal.',
		source_invalid: 'Servi enn lien https:// komplet Facebook, Instagram, YouTube, TikTok, X ouswa enn sit nouvel morisien.',
		source_title: 'Sours orizinal',
		source_video: 'Video lor {site}',
		source_post: 'Post lor {site}',
		source_article: 'Lartik lor {site}',
		open_on: 'Ouver lor {site}',
		play_here: 'Zwe isi',
		embed_note: 'Kan ou zwe li, video-la sarz depi Facebook.',
		via: 'via {site}',
		remove_link: 'Tir lien-la',
		rate_limited_report: 'Ou finn avoy plizir rapor dan enn ti letan. Re-esey dan {min} min.',
		rate_limited_sos: 'Limit SOS finn ateint lor sa aparey-la. Apel 999 aster. Ou kapav avoy ankor dan {min} min.',
		max_files: 'Ou kapav met ziska 4 fisie.',
		loc_timeout: 'Lokalizasion pa finn marse. Re-esey dan enn plas ouver.',
		not_configured: 'Lakart an direk pa ankor konekte.',
		comment_failed: 'Pa finn kapav pibliye nouvel la.',
		vote_failed: 'Pa finn kapav anrezistre ou vot.'
	},
	de: {
		need_source: 'Quellenlink',
		source_label: 'Quellenlink',
		source_ph: 'Facebook-Beitrag oder Nachrichtenlink einfügen',
		source_hint: 'Wo Sie es gesehen haben, z. B. ein Mopays.com-Video. Es bleibt auf der Originalseite.',
		source_invalid: 'Verwenden Sie einen vollständigen https://-Link von Facebook, Instagram, YouTube, TikTok, X oder einer mauritischen Nachrichtenseite.',
		source_title: 'Originalquelle',
		source_video: 'Video auf {site}',
		source_post: 'Beitrag auf {site}',
		source_article: 'Artikel auf {site}',
		open_on: 'Auf {site} öffnen',
		play_here: 'Hier abspielen',
		embed_note: 'Beim Abspielen wird das Video von Facebook geladen.',
		via: 'über {site}',
		remove_link: 'Link entfernen',
		rate_limited_report: 'Sie haben in kurzer Zeit mehrere Meldungen gesendet. Versuchen Sie es in {min} Min. erneut.',
		rate_limited_sos: 'SOS-Limit auf diesem Gerät erreicht. Rufen Sie jetzt 999 an. Erneut senden in {min} Min. möglich.',
		max_files: 'Sie können bis zu 4 Dateien anhängen.',
		loc_timeout: 'Standortabfrage abgelaufen. Versuchen Sie es im Freien erneut.',
		not_configured: 'Die Live-Karte ist noch nicht verbunden.',
		comment_failed: 'Update konnte nicht gesendet werden.',
		vote_failed: 'Ihre Stimme konnte nicht gespeichert werden.'
	},
	it: {
		need_source: 'link alla fonte',
		source_label: 'Link alla fonte',
		source_ph: 'Incolla un post Facebook o un link di notizie',
		source_hint: 'Dove l’hai visto, ad es. un video di Mopays.com. Resta sul sito originale.',
		source_invalid: 'Usa un link https:// completo da Facebook, Instagram, YouTube, TikTok, X o un sito di notizie mauriziano.',
		source_title: 'Fonte originale',
		source_video: 'Video su {site}',
		source_post: 'Post su {site}',
		source_article: 'Articolo su {site}',
		open_on: 'Apri su {site}',
		play_here: 'Riproduci qui',
		embed_note: 'La riproduzione carica il video da Facebook.',
		via: 'via {site}',
		remove_link: 'Rimuovi link',
		rate_limited_report: 'Hai inviato diverse segnalazioni in poco tempo. Riprova tra {min} min.',
		rate_limited_sos: 'Limite SOS raggiunto su questo dispositivo. Chiama subito il 999. Potrai inviare di nuovo tra {min} min.',
		max_files: 'Puoi allegare fino a 4 file.',
		loc_timeout: 'Posizione non trovata in tempo. Riprova all’aperto.',
		not_configured: 'La mappa in diretta non è ancora collegata.',
		comment_failed: 'Impossibile pubblicare l’aggiornamento.',
		vote_failed: 'Impossibile salvare il tuo voto.'
	}
};

export type Key = MessageKey | keyof (typeof EXTRA)['en'];

function isLocale(value: string | null | undefined): value is Locale {
	return !!value && value in MESSAGES;
}

function detect(): Locale {
	try {
		const saved = localStorage.getItem(STORAGE_KEY);
		if (isLocale(saved)) return saved;
	} catch {
		// storage blocked; fall through to the browser languages
	}
	for (const lang of navigator.languages ?? [navigator.language]) {
		const tag = String(lang).toLowerCase();
		if (tag.startsWith('mfe') || tag.startsWith('cpf')) return 'mfe';
		const primary = tag.split('-')[0];
		if (isLocale(primary)) return primary;
	}
	return 'en';
}

export const i18n = $state<{ locale: Locale }>({ locale: 'en' });

/** Call once on the client (layout onMount). */
export function initLocale() {
	i18n.locale = detect();
	document.documentElement.lang = i18n.locale;
}

export function setLocale(locale: Locale) {
	i18n.locale = locale;
	document.documentElement.lang = locale;
	try {
		localStorage.setItem(STORAGE_KEY, locale);
	} catch {
		// non-fatal
	}
}

function lookup(locale: Locale, key: string): string | undefined {
	return MESSAGES[locale][key] ?? EXTRA[locale][key];
}

/** Translate with `{var}` interpolation and `.one`/`.other` plurals keyed on `n`. Falls back to English. */
export function t(key: Key | (string & {}), vars?: Record<string, string | number>): string {
	const locale = i18n.locale;
	let k: string = key;
	if (vars?.n != null && (lookup(locale, `${key}.one`) ?? lookup('en', `${key}.one`))) {
		k = `${key}.${Number(vars.n) === 1 ? 'one' : 'other'}`;
	}
	let text = lookup(locale, k) ?? lookup('en', k) ?? key;
	if (vars) for (const [name, value] of Object.entries(vars)) text = text.split(`{${name}}`).join(String(value));
	return text;
}

/** "12 min ago" style label. Kreol is not in CLDR, so it keeps the handoff's ago_* strings. */
export function timeAgo(iso: string, now = Date.now()): string {
	const minutes = (now - new Date(iso).getTime()) / 60000;
	if (minutes < 1) return t('just_now');
	if (i18n.locale === 'mfe') {
		if (minutes < 60) return t('ago_min', { n: Math.round(minutes) });
		const hours = minutes / 60;
		if (hours < 24) return t('ago_h', { n: Math.round(hours) });
		const days = Math.round(hours / 24);
		return days === 1 ? t('yesterday') : t('ago_d', { n: days });
	}
	const format = new Intl.RelativeTimeFormat(i18n.locale, { numeric: 'auto', style: 'long' });
	if (minutes < 60) return format.format(-Math.round(minutes), 'minute');
	const hours = minutes / 60;
	if (hours < 24) return format.format(-Math.round(hours), 'hour');
	return format.format(-Math.round(hours / 24), 'day');
}

export function absoluteTime(iso: string): string {
	return new Intl.DateTimeFormat(i18n.locale === 'mfe' ? 'fr-MU' : i18n.locale, {
		dateStyle: 'medium',
		timeStyle: 'short'
	}).format(new Date(iso));
}

export function clockTime(date: Date): string {
	return new Intl.DateTimeFormat(i18n.locale === 'mfe' ? 'fr-MU' : i18n.locale, { timeStyle: 'short' }).format(date);
}

/** Decimal comma for fr/de. */
export function formatNumber(value: number, digits: number): string {
	return new Intl.NumberFormat(i18n.locale === 'mfe' ? 'en' : i18n.locale, {
		minimumFractionDigits: digits,
		maximumFractionDigits: digits,
		useGrouping: false
	}).format(value);
}
