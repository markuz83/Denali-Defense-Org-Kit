import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getMyApprovals from '@salesforce/apex/PricingApprovalsController.getMyApprovals';
import decide from '@salesforce/apex/PricingApprovalsController.decide';

const USD = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 });
const USD_COMPACT = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', notation: 'compact', maximumFractionDigits: 1 });
const DATE = new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric' });

function reduceError(error) {
    if (Array.isArray(error?.body)) return error.body.map((e) => e.message).join(', ');
    return error?.body?.message || error?.message || 'Unknown error';
}

/**
 * Approval requests waiting on the current user. Opportunity margin exceptions show the
 * pricing facts and the Einstein rationale so the reviewer can decide in place.
 */
export default class PricingApprovals extends NavigationMixin(LightningElement) {
    items;
    error;
    wiredResult;
    comments = {};
    expanded = {};
    busyId;

    @wire(getMyApprovals)
    wired(result) {
        this.wiredResult = result;
        if (result.data) {
            this.items = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.error = reduceError(result.error);
        }
    }

    get isLoading() {
        return !this.items && !this.error;
    }

    get hasItems() {
        return this.items && this.items.length > 0;
    }

    get isEmpty() {
        return this.items && this.items.length === 0;
    }

    get title() {
        const n = this.items ? this.items.length : 0;
        return n ? `Pricing Approvals (${n})` : 'Pricing Approvals';
    }

    get cards() {
        return (this.items || []).map((a) => {
            const o = a.opportunity;
            const gap = o && o.Estimated_Margin__c !== null && o.Estimated_Margin__c !== undefined && o.Margin_Floor__c
                ? o.Estimated_Margin__c - o.Margin_Floor__c
                : null;
            const inc = o?.Incumbent__r;
            const expanded = !!this.expanded[a.workitemId];
            return {
                key: a.workitemId,
                workitemId: a.workitemId,
                recordId: a.recordId,
                name: a.recordName,
                isOpportunity: !!o,
                meta: [a.objectType, a.submittedBy && `from ${a.submittedBy}`, a.submittedDate && DATE.format(new Date(a.submittedDate))]
                    .filter(Boolean)
                    .join(' · '),
                account: o?.Account?.Name,
                amount: o?.Amount ? USD_COMPACT.format(o.Amount) : null,
                contractType: o?.Contract_Type__c,
                marginLine: gap === null ? null : `${Number(o.Estimated_Margin__c).toFixed(1)}% vs ${Number(o.Margin_Floor__c).toFixed(0)}% floor`,
                gapLabel: gap === null ? null : `${gap.toFixed(1)} pts`,
                shortfall: o?.Margin_Shortfall__c ? USD.format(o.Margin_Shortfall__c) : null,
                totalValue: o?.Estimated_Contract_Value__c && o.Estimated_Contract_Value__c > (o.Amount || 0)
                    ? USD_COMPACT.format(o.Estimated_Contract_Value__c)
                    : null,
                incumbent: inc
                    ? `${inc.Name}${inc.Deals_Lost_To__c ? ` · beat us ${inc.Deals_Lost_To__c}× (${USD_COMPACT.format(inc.Bookings_Lost_To__c || 0)})` : ''}`
                    : null,
                rationale: o?.Pricing_Rationale__c,
                expanded,
                toggleLabel: expanded ? 'Hide rationale' : 'Show rationale',
                rationaleClass: expanded ? 'rationale' : 'rationale rationale-collapsed',
                comment: this.comments[a.workitemId] || '',
                busy: this.busyId === a.workitemId
            };
        });
    }

    handleOpen(event) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: event.currentTarget.dataset.id, actionName: 'view' }
        });
    }

    handleToggle(event) {
        const id = event.currentTarget.dataset.id;
        this.expanded = { ...this.expanded, [id]: !this.expanded[id] };
    }

    handleComment(event) {
        this.comments = { ...this.comments, [event.target.dataset.id]: event.target.value };
    }

    handleApprove(event) {
        this.decide(event.currentTarget.dataset.id, event.currentTarget.dataset.record, 'Approve');
    }

    handleReject(event) {
        this.decide(event.currentTarget.dataset.id, event.currentTarget.dataset.record, 'Reject');
    }

    async decide(workitemId, recordId, action) {
        this.busyId = workitemId;
        try {
            await decide({ workitemId, action, comments: this.comments[workitemId] || null });
            this.dispatchEvent(new ShowToastEvent({
                title: action === 'Approve' ? 'Approved' : 'Rejected',
                message: 'The submitter has been notified.',
                variant: 'success'
            }));
            await notifyRecordUpdateAvailable([{ recordId }]);
            await refreshApex(this.wiredResult);
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Could not record the decision', message: reduceError(e), variant: 'error' }));
        } finally {
            this.busyId = undefined;
        }
    }

    handleRefresh() {
        return refreshApex(this.wiredResult);
    }
}
