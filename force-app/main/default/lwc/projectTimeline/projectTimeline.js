import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getDeliverables from '@salesforce/apex/ProjectTimelineController.getDeliverables';
import { subscribeToDeliveryChanges, touchesAny } from 'c/deliveryLiveUpdates';

const USD_COMPACT = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', notation: 'compact', maximumFractionDigits: 1 });

/**
 * Project record page wrapper for the Command Center timeline: loads the project's
 * deliverables and draws them (bars to due date, slips to forecast, today line).
 */
export default class ProjectTimeline extends LightningElement {
    @api recordId;
    items = [];
    error;
    wiredResult;
    live = false;

    @wire(getDeliverables, { projectId: '$recordId' })
    wired(result) {
        this.wiredResult = result;
        const { data, error } = result;
        if (data) {
            this.error = undefined;
            this.items = data.map((d) => ({
                id: d.Id,
                label: d.Name,
                // One group: the page is already about this project. Supplier-owned work is labelled.
                group: 'Deliverables',
                start: d.Planned_Start_Date__c,
                end: d.Due_Date__c,
                forecast: d.Forecast_Completion_Date__c,
                health: d.Health__c,
                status: d.Status__c,
                detail: [d.Revenue_Milestone__c && `${USD_COMPACT.format(d.Revenue_Milestone__c)} milestone`,
                    d.Supplier__r?.Name && `Supplier: ${d.Supplier__r.Name}`, d.Is_At_Risk__c && 'At risk'].filter(Boolean).join(' · ')
            }));
        } else if (error) {
            this.error = error.body?.message || error.message;
        }
    }

    // ---------------------------------------------------------------- live updates (Change Data Capture)

    connectedCallback() {
        this.disconnected = false;
        subscribeToDeliveryChanges((batch) => this.handleLiveChanges(batch)).then((sub) => {
            if (this.disconnected) {
                sub.unsubscribe();
                return;
            }
            this.liveSubscription = sub;
            this.live = sub.live;
        });
    }

    disconnectedCallback() {
        this.disconnected = true;
        if (this.liveSubscription) {
            this.liveSubscription.unsubscribe();
            this.liveSubscription = undefined;
        }
    }

    // This project's deliverables, or a deliverable newly added to it.
    handleLiveChanges(batch) {
        const ids = new Set(this.items.map((i) => i.id));
        const added = batch.some((c) => c.entity === 'Deliverable__c' && c.changeType === 'CREATE' && c.payload.Project__c === this.recordId);
        if (touchesAny(batch, ids) || added) {
            refreshApex(this.wiredResult);
        }
    }
}
