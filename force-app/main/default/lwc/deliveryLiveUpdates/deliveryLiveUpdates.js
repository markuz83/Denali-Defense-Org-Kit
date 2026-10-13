import { subscribe, unsubscribe, onError, isEmpEnabled } from 'lightning/empApi';

// Change Data Capture channels for the objects whose changes the Denali components show.
// Enabled by platformEventChannelMembers/ChangeEvents_*_ChangeEvent.
const CHANNELS = ['/data/Deliverable__ChangeEvent', '/data/Deliverable_Update__ChangeEvent'];
const DEFAULT_DEBOUNCE_MS = 800;

let errorHandlerRegistered = false;

/**
 * Subscribes to Deliverable and Deliverable Update changes made by anyone (users, flows,
 * integrations) and calls onChanges with a debounced batch of
 * { entity, changeType, recordIds, payload }. Resolves to an unsubscribe function.
 *
 * Streaming (lightning/empApi) isn't available in the Salesforce mobile app; there this
 * resolves to a no-op and the component simply doesn't update live.
 */
export async function subscribeToDeliveryChanges(onChanges, debounceMs = DEFAULT_DEBOUNCE_MS) {
    let enabled = false;
    try {
        enabled = await isEmpEnabled();
    } catch (e) {
        enabled = false;
    }
    if (!enabled) {
        return { live: false, unsubscribe: () => {} };
    }
    if (!errorHandlerRegistered) {
        onError((error) => {
            // eslint-disable-next-line no-console
            console.warn('Denali live updates: streaming error', JSON.stringify(error));
        });
        errorHandlerRegistered = true;
    }

    let timer;
    let pending = [];
    const handler = (message) => {
        const payload = message?.data?.payload || {};
        const header = payload.ChangeEventHeader || {};
        pending.push({
            entity: header.entityName,
            changeType: header.changeType,
            recordIds: header.recordIds || [],
            payload
        });
        clearTimeout(timer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        timer = setTimeout(() => {
            const batch = pending;
            pending = [];
            onChanges(batch);
        }, debounceMs);
    };

    const subscriptions = await Promise.all(CHANNELS.map((channel) => subscribe(channel, -1, handler).catch(() => null)));
    const active = subscriptions.filter(Boolean);
    return {
        live: active.length > 0,
        unsubscribe: () => {
            clearTimeout(timer);
            active.forEach((s) => unsubscribe(s, () => {}));
        }
    };
}

/** True when a change touches any of the given record Ids. */
export function touchesAny(batch, ids) {
    return batch.some((c) => c.recordIds.some((id) => ids.has(id)));
}
