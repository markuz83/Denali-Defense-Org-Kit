import { LightningElement, api, wire } from 'lwc';
import { getRecord, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getContext from '@salesforce/apex/MarginGuardrailController.getContext';
import submitForApproval from '@salesforce/apex/MarginGuardrailController.submitForApproval';
import regenerateRationale from '@salesforce/apex/MarginGuardrailController.regenerateRationale';

import ESTIMATED_MARGIN from '@salesforce/schema/Opportunity.Estimated_Margin__c';
import CONTRACT_TYPE from '@salesforce/schema/Opportunity.Contract_Type__c';
import AMOUNT from '@salesforce/schema/Opportunity.Amount';
import APPROVAL_STATUS from '@salesforce/schema/Opportunity.Margin_Approval_Status__c';
import LAST_MODIFIED from '@salesforce/schema/Opportunity.LastModifiedDate';

// Fields whose changes should refresh the card (edits made elsewhere on the page).
const WATCHED_FIELDS = [ESTIMATED_MARGIN, CONTRACT_TYPE, AMOUNT, APPROVAL_STATUS, LAST_MODIFIED];
const USD = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 });
const USD_COMPACT = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', notation: 'compact', maximumFractionDigits: 1 });

function fmtPct(v) {
    return v === null || v === undefined ? '—' : `${Number(v).toFixed(1)}%`;
}

function reduceError(error) {
    if (!error) return 'Unknown error';
    if (Array.isArray(error.body)) return error.body.map((e) => e.message).join(', ');
    return error.body?.message || error.message || 'Unknown error';
}

/**
 * Margin Guardrail for the Opportunity record page: estimated margin against the floor for the
 * contract type and against recent wins, the profit given up, the Margin Exception approval
 * (with inline submit), and the Einstein-drafted Pricing Rationale (with regenerate).
 */
export default class MarginGuardrail extends LightningElement {
    @api recordId;
    ctx;
    error;
    contextResult;
    lastModified;

    approverId;
    comments = '';
    submitting = false;
    regenerating = false;

    approverFilter = { criteria: [{ fieldPath: 'IsActive', operator: 'eq', value: true }] };

    @wire(getRecord, { recordId: '$recordId', fields: WATCHED_FIELDS })
    watchRecord({ data }) {
        const stamp = data?.fields?.LastModifiedDate?.value;
        if (stamp && this.lastModified && stamp !== this.lastModified && this.contextResult) {
            refreshApex(this.contextResult);
        }
        if (stamp) this.lastModified = stamp;
    }

    @wire(getContext, { opportunityId: '$recordId' })
    wiredContext(result) {
        this.contextResult = result;
        if (result.data) {
            this.ctx = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.error = reduceError(result.error);
            this.ctx = undefined;
        }
    }

    // ---------------------------------------------------------------- state

    get opp() {
        return this.ctx?.opportunity;
    }

    get isLoading() {
        return !this.ctx && !this.error;
    }

    get hasMargin() {
        return this.opp && this.opp.Estimated_Margin__c !== null && this.opp.Estimated_Margin__c !== undefined;
    }

    get margin() {
        return this.opp.Estimated_Margin__c;
    }

    get floor() {
        return this.opp.Margin_Floor__c;
    }

    get below() {
        return !!this.opp.Below_Margin_Floor__c;
    }

    get marginLabel() {
        return fmtPct(this.margin);
    }

    get floorLabel() {
        return `${fmtPct(this.floor)} floor for ${this.opp.Contract_Type__c || 'an unset contract type (fixed price assumed)'}`;
    }

    get gapLabel() {
        const gap = this.margin - this.floor;
        return `${gap >= 0 ? '+' : ''}${gap.toFixed(1)} pts vs floor`;
    }

    // SLDS score dynamic icon: a filled circle at or above the floor, a hollow one below it.
    get scoreOption() {
        return this.below ? 'negative' : 'positive';
    }

    get scoreLabel() {
        return this.below ? 'Below the margin floor' : 'At or above the margin floor';
    }

    get gapClass() {
        return this.below ? 'gap slds-text-color_error' : 'gap slds-text-color_success';
    }

    // ---------------------------------------------------------------- bar

    get scaleMax() {
        const values = [this.margin, this.floor, this.ctx.avgWonMarginSameType, this.ctx.avgWonMarginAll]
            .filter((v) => v !== null && v !== undefined);
        return Math.max(25, Math.ceil((Math.max(...values) + 3) / 5) * 5);
    }

    position(v) {
        return Math.min(Math.max((v / this.scaleMax) * 100, 0), 100);
    }

    get marginBarStyle() {
        return `width:${this.position(this.margin)}%`;
    }

    get marginBarClass() {
        return this.below ? 'bar-fill bar-below' : 'bar-fill bar-ok';
    }

    get floorMarkerStyle() {
        return `left:${this.position(this.floor)}%`;
    }

    get hasWonReference() {
        return this.ctx.avgWonMarginSameType !== null && this.ctx.avgWonMarginSameType !== undefined;
    }

    get wonMarkerStyle() {
        return `left:${this.position(this.ctx.avgWonMarginSameType)}%`;
    }

    get wonLabel() {
        const n = this.ctx.wonCountSameType;
        return `${fmtPct(this.ctx.avgWonMarginSameType)} avg on ${n} ${this.opp.Acquisition_Type__c || ''} win${n === 1 ? '' : 's'}`.replace('  ', ' ');
    }

    get allWonLabel() {
        if (this.ctx.avgWonMarginAll === null || this.ctx.avgWonMarginAll === undefined) return null;
        return `${fmtPct(this.ctx.avgWonMarginAll)} across all ${this.ctx.wonCountAll} wins (2 yrs)`;
    }

    get scaleTicks() {
        const ticks = [];
        for (let v = 0; v <= this.scaleMax; v += 5) {
            ticks.push({ key: `t${v}`, label: `${v}%`, style: `left:${this.position(v)}%` });
        }
        return ticks;
    }

    // ---------------------------------------------------------------- facts

    get shortfallLabel() {
        return this.opp.Margin_Shortfall__c ? USD.format(this.opp.Margin_Shortfall__c) : null;
    }

    get amountLabel() {
        return this.opp.Amount ? USD_COMPACT.format(this.opp.Amount) : '—';
    }

    get incumbentLine() {
        const inc = this.opp.Incumbent__r;
        if (!inc) return null;
        const deals = inc.Deals_Lost_To__c || 0;
        if (!deals) return `Incumbent ${inc.Name}: no recorded losses to them.`;
        return `Incumbent ${inc.Name} has beaten us on ${deals} deal${deals === 1 ? '' : 's'} (${USD_COMPACT.format(inc.Bookings_Lost_To__c || 0)}).`;
    }

    // ---------------------------------------------------------------- approval

    get status() {
        if (this.ctx.pendingApproval) return 'pending';
        if (!this.below) return 'within';
        if (this.opp.Margin_Approval_Status__c === 'Approved') return 'approved';
        if (this.opp.Margin_Approval_Status__c === 'Rejected') return 'rejected';
        return 'needs';
    }

    get statusBadge() {
        if (!this.opp) return null;
        return {
            within: { label: 'Within guardrail', className: 'slds-theme_success' },
            needs: { label: 'Needs pricing review', className: 'slds-theme_warning' },
            pending: { label: 'Pricing review pending', className: 'slds-theme_info' },
            approved: { label: 'Exception approved', className: 'slds-theme_success' },
            rejected: { label: 'Exception rejected', className: 'slds-theme_error' }
        }[this.status];
    }

    get canSubmit() {
        return (this.status === 'needs' || this.status === 'rejected') && !this.opp.IsClosed;
    }

    get pendingLine() {
        const who = this.ctx.pendingApproverName ? ` with ${this.ctx.pendingApproverName}` : '';
        return `Submitted for pricing review${who}. The deal can't move to proposal or Closed Won until it's approved.`;
    }

    get rejectedLine() {
        return 'Pricing Review rejected this price. Re-price at or above the floor, or strengthen the rationale and resubmit.';
    }

    get isRejected() {
        return this.status === 'rejected';
    }

    get isPending() {
        return this.status === 'pending';
    }

    get isApproved() {
        return this.status === 'approved';
    }

    get submitDisabled() {
        return this.submitting || !this.approverId;
    }

    handleApproverChange(event) {
        this.approverId = event.detail.recordId;
    }

    handleCommentsChange(event) {
        this.comments = event.target.value;
    }

    async handleSubmit() {
        this.submitting = true;
        try {
            await submitForApproval({ opportunityId: this.recordId, approverId: this.approverId, comments: this.comments });
            this.toast('Submitted for pricing review', 'The approver has been notified.', 'success');
            this.comments = '';
            await this.refreshAll();
        } catch (e) {
            this.toast('Could not submit', reduceError(e), 'error');
        } finally {
            this.submitting = false;
        }
    }

    // ---------------------------------------------------------------- rationale

    get rationale() {
        return this.opp.Pricing_Rationale__c;
    }

    get showRationale() {
        return this.below || !!this.rationale;
    }

    get canRegenerate() {
        return this.below && !this.opp.IsClosed && !this.ctx.pendingApproval;
    }

    get regenerateLabel() {
        return this.rationale ? 'Regenerate with Einstein' : 'Draft with Einstein';
    }

    async handleRegenerate() {
        this.regenerating = true;
        try {
            await regenerateRationale({ opportunityId: this.recordId });
            this.toast('Pricing rationale drafted', 'Review and edit it before submitting.', 'success');
            await this.refreshAll();
        } catch (e) {
            this.toast('Could not draft the rationale', reduceError(e), 'error');
        } finally {
            this.regenerating = false;
        }
    }

    // ---------------------------------------------------------------- helpers

    async refreshAll() {
        await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        await refreshApex(this.contextResult);
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
