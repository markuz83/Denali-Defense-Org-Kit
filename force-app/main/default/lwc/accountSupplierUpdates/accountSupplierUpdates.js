import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getUpdatesAwaitingReview from '@salesforce/apex/AccountCommandCenterController.getUpdatesAwaitingReview';
import { subscribeToDeliveryChanges, touchesAny } from 'c/deliveryLiveUpdates';
import { url, pct, reduceError } from 'c/accountSectionUtils';

const COLUMNS = [
    { type: 'url', fieldName: 'url', label: 'Update', initialWidth: 110, typeAttributes: { label: { fieldName: 'name' } } },
    { type: 'text', fieldName: 'deliverable', label: 'Deliverable', wrapText: true },
    { type: 'text', fieldName: 'supplier', label: 'Supplier' },
    { type: 'date', fieldName: 'submitted', label: 'Submitted', typeAttributes: { month: 'short', day: 'numeric' } },
    { type: 'text', fieldName: 'reported', label: 'Reported' },
    { type: 'percent', fieldName: 'pct', label: '% Done', typeAttributes: { maximumFractionDigits: 0 } },
    { type: 'text', fieldName: 'review', label: 'Review' }
];

/**
 * Supplier updates on an account's deliverables that are waiting on internal review, for an
 * Account record page. Updates live as updates are submitted or reviewed.
 */
export default class AccountSupplierUpdates extends LightningElement {
    @api recordId;
    columns = COLUMNS;
    rows = [];
    loaded = false;
    error;
    wiredResult;

    @wire(getUpdatesAwaitingReview, { accountId: '$recordId' })
    wired(result) {
        this.wiredResult = result;
        if (result.data) {
            this.rows = result.data.map((u) => ({
                id: u.Id,
                url: url(u.Id),
                name: u.Name,
                deliverable: u.Deliverable__r?.Name,
                supplier: u.Supplier__r?.Name,
                submitted: u.Submitted_Date__c,
                reported: u.Reported_Status__c,
                pct: pct(u.Percent_Complete__c),
                review: u.Internal_Review_Status__c
            }));
            this.error = undefined;
            this.loaded = true;
        } else if (result.error) {
            this.error = reduceError(result.error);
            this.rows = [];
            this.loaded = true;
        }
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get isEmpty() {
        return this.loaded && !this.rows.length;
    }

    connectedCallback() {
        this.disconnected = false;
        subscribeToDeliveryChanges((batch) => this.handleLiveChanges(batch)).then((sub) => {
            if (this.disconnected) {
                sub.unsubscribe();
                return;
            }
            this.liveSubscription = sub;
        });
    }

    disconnectedCallback() {
        this.disconnected = true;
        if (this.liveSubscription) {
            this.liveSubscription.unsubscribe();
            this.liveSubscription = undefined;
        }
    }

    // An update in the list changed (reviewed, say), or a new one was submitted (it may be for this account).
    handleLiveChanges(batch) {
        const ids = new Set(this.rows.map((r) => r.id));
        if (touchesAny(batch, ids) || batch.some((c) => c.changeType === 'CREATE')) {
            refreshApex(this.wiredResult);
        }
    }
}
