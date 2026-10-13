export type Toast = {
	id: number;
	message: string;
	tone: 'ok' | 'err';
};

export const toaster = $state<{ items: Toast[] }>({ items: [] });

let toastSeq = 0;

export function pushToast(message: string, tone: Toast['tone'] = 'ok') {
	const id = ++toastSeq;
	toaster.items.push({ id, message, tone });
	setTimeout(() => {
		const index = toaster.items.findIndex((item) => item.id === id);
		if (index >= 0) toaster.items.splice(index, 1);
	}, 4600);
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
