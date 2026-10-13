import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getReview from '@salesforce/apex/SupplierUpdateReviewController.getReview';
import review from '@salesforce/apex/SupplierUpdateReviewController.review';
import { subscribeToDeliveryChanges, touchesAny } from 'c/deliveryLiveUpdates';

const DATE = new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric' });
const OPEN = new Set(['Pending', 'Under Review']);
const STATUS_CLASS = {
    Pending: 'status status-pending',
    'Under Review': 'status status-pending',
    Accepted: 'status status-accepted',
    'Needs Clarification': 'status status-bounced',
    Rejected: 'status status-rejected'
};
const HEALTH_CLASS = { Green: 'health health-green', Yellow: 'health health-yellow', Red: 'health health-red' };

// Sparkline geometry (viewBox units).
const SPARK_W = 240;
const SPARK_H = 48;
const SPARK_PAD = 6;

function fmtDate(value) {
    if (!value) return '';
    const s = String(value);
    // Date fields are 'YYYY-MM-DD'; datetimes carry a time part.
    if (s.length === 10) {
        const [y, m, d] = s.split('-').map(Number);
        return DATE.format(new Date(y, m - 1, d));
    }
    return DATE.format(new Date(s));
}

function reduceError(error) {
    if (Array.isArray(error?.body)) return error.body.map((e) => e.message).join(', ');
    return error?.body?.message || error?.message || 'Unknown error';
}

/**
 * Supplier updates on a Deliverable, newest first, with a % complete trend and an inline
 * review decision (Accept / Needs Clarification / Reject). The decision fires the existing
 * flows: the reviewer is stamped, and an accepted update is applied to the Deliverable.
 */
export default class SupplierUpdateReview extends LightningElement {
    @api recordId;
    data;
    error;
    wiredResult;
    comments = {};
    busyId;
    showAll = false;
    live = false;

    @wire(getReview, { deliverableId: '$recordId' })
    wired(result) {
        this.wiredResult = result;
        if (result.data) {
            this.data = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.error = reduceError(result.error);
        }
    }

    get isLoading() {
        return !this.data && !this.error;
    }

    get hasUpdates() {
        return this.data.updates.length > 0;
    }

    get pendingCount() {
        return this.data.updates.filter((u) => OPEN.has(u.Internal_Review_Status__c)).length;
    }

    get title() {
        return this.data && this.pendingCount ? `Supplier Updates (${this.pendingCount} to review)` : 'Supplier Updates';
    }

    get summary() {
        const d = this.data.deliverable;
        return [d.Status__c, d.Percent_Complete__c !== null && d.Percent_Complete__c !== undefined && `${Math.round(d.Percent_Complete__c)}% complete`,
            d.Due_Date__c && `due ${fmtDate(d.Due_Date__c)}`,
            d.Forecast_Completion_Date__c && d.Forecast_Completion_Date__c !== d.Due_Date__c && `forecast ${fmtDate(d.Forecast_Completion_Date__c)}`,
            d.Supplier__r?.Name].filter(Boolean).join(' · ');
    }

    // ---------------------------------------------------------------- trend

    get trend() {
        const points = [...this.data.updates]
            .filter((u) => u.Submitted_Date__c && u.Percent_Complete__c !== null && u.Percent_Complete__c !== undefined)
            .sort((a, b) => new Date(a.Submitted_Date__c) - new Date(b.Submitted_Date__c));
        if (points.length < 2) return null;
        const t0 = new Date(points[0].Submitted_Date__c).getTime();
        const t1 = new Date(points[points.length - 1].Submitted_Date__c).getTime();
        const span = Math.max(t1 - t0, 1);
        const xy = points.map((u) => {
            const x = SPARK_PAD + ((new Date(u.Submitted_Date__c).getTime() - t0) / span) * (SPARK_W - 2 * SPARK_PAD);
            const y = SPARK_H - SPARK_PAD - (Math.min(u.Percent_Complete__c, 100) / 100) * (SPARK_H - 2 * SPARK_PAD);
            return { x, y };
        });
        const last = points[points.length - 1].Percent_Complete__c;
        const first = points[0].Percent_Complete__c;
        const stalled = last <= first;
        return {
            viewBox: `0 0 ${SPARK_W} ${SPARK_H}`,
            points: xy.map((p) => `${p.x.toFixed(1)},${p.y.toFixed(1)}`).join(' '),
            dots: xy.map((p, i) => ({ key: `p${i}`, cx: p.x, cy: p.y })),
            lineClass: stalled ? 'spark-line spark-stalled' : 'spark-line',
            dotClass: stalled ? 'spark-dot spark-stalled' : 'spark-dot',
            label: `${Math.round(first)}% → ${Math.round(last)}% across ${points.length} updates${stalled ? ' (no progress)' : ''}`,
            labelClass: stalled ? 'slds-text-body_small slds-text-color_error' : 'slds-text-body_small slds-text-color_weak'
        };
    }

    // ---------------------------------------------------------------- updates

    get updateCards() {
        const all = this.data.updates.map((u) => {
            const open = OPEN.has(u.Internal_Review_Status__c);
            const reviewed = u.Reviewed_By__r?.Name
                ? `Reviewed by ${u.Reviewed_By__r.Name}${u.Review_Date__c ? ` on ${fmtDate(u.Review_Date__c)}` : ''}`
                : '';
            return {
                id: u.Id,
                name: u.Name,
                submitted: [u.Submitted_Date__c && fmtDate(u.Submitted_Date__c), u.Submitted_By__r?.Name || u.Supplier__r?.Name].filter(Boolean).join(' · '),
                reported: [u.Reported_Status__c, u.Percent_Complete__c !== null && u.Percent_Complete__c !== undefined && `${Math.round(u.Percent_Complete__c)}%`,
                    u.Forecast_Completion_Date__c && `forecast ${fmtDate(u.Forecast_Completion_Date__c)}`].filter(Boolean).join(' · '),
                health: u.Supplier_Health__c,
                healthClass: HEALTH_CLASS[u.Supplier_Health__c] || 'health',
                status: u.Internal_Review_Status__c,
                statusClass: STATUS_CLASS[u.Internal_Review_Status__c] || 'status',
                summary: u.Progress_Summary__c,
                blockers: u.Blockers__c,
                nextSteps: u.Next_Steps__c,
                customerAction: u.Requires_Customer_Action__c ? u.Customer_Action__c || 'Customer action required' : null,
                reviewerComments: u.Reviewer_Comments__c,
                reviewed,
                open,
                cardClass: open ? 'update update-open' : 'update',
                comment: this.comments[u.Id] || '',
                busy: this.busyId === u.Id
            };
        });
        // Always show open ones; closed history collapses to the latest two unless expanded.
        if (this.showAll) return all;
        let closedShown = 0;
        return all.filter((c) => c.open || closedShown++ < 2);
    }

    get hiddenCount() {
        return this.data.updates.length - this.updateCards.length;
    }

    get canShowMore() {
        return !this.showAll && this.hiddenCount > 0;
    }

    get showMoreLabel() {
        return `Show ${this.hiddenCount} older update${this.hiddenCount === 1 ? '' : 's'}`;
    }

    handleShowMore() {
        this.showAll = true;
    }

    handleComment(event) {
        this.comments = { ...this.comments, [event.target.dataset.id]: event.target.value };
    }

    handleAccept(event) {
        this.decide(event.currentTarget.dataset.id, 'Accepted');
    }

    handleClarify(event) {
        this.decide(event.currentTarget.dataset.id, 'Needs Clarification');
    }

    handleReject(event) {
        this.decide(event.currentTarget.dataset.id, 'Rejected');
    }

    async decide(updateId, decision) {
        const comments = (this.comments[updateId] || '').trim();
        if (decision !== 'Accepted' && !comments) {
            this.toast('Add a comment', 'Tell the supplier what needs to change before sending it back.', 'warning');
            return;
        }
        this.busyId = updateId;
        try {
            await review({ updateId, decision, comments: comments || null });
            const messages = {
                Accepted: 'Applied to the deliverable.',
                'Needs Clarification': 'Sent back to the supplier with your comments.',
                Rejected: 'The supplier has been told why.'
            };
            this.toast(`Update ${decision === 'Needs Clarification' ? 'sent back' : decision.toLowerCase()}`, messages[decision], 'success');
            this.comments = { ...this.comments, [updateId]: '' };
            await notifyRecordUpdateAvailable([{ recordId: this.recordId }, { recordId: updateId }]);
            await refreshApex(this.wiredResult);
        } catch (e) {
            this.toast('Could not record the review', reduceError(e), 'error');
        } finally {
            this.busyId = undefined;
        }
    }

    handleRefresh() {
        return refreshApex(this.wiredResult);
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

    // This deliverable, any of its updates, or a new update on it.
    handleLiveChanges(batch) {
        if (!this.data) return;
        const ids = new Set([this.recordId, ...this.data.updates.map((u) => u.Id)]);
        const newUpdate = batch.some((c) => c.entity === 'Deliverable_Update__c' && c.changeType === 'CREATE' && c.payload.Deliverable__c === this.recordId);
        if (touchesAny(batch, ids) || newUpdate) {
            notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            refreshApex(this.wiredResult);
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
