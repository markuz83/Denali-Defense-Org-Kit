import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getMyWork from '@salesforce/apex/MyProjectsController.getMyWork';
import { subscribeToDeliveryChanges } from 'c/deliveryLiveUpdates';

const USD_COMPACT = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', notation: 'compact', maximumFractionDigits: 1 });
const DATE = new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric' });
const DAY_MS = 24 * 60 * 60 * 1000;

function parseDate(value) {
    if (!value) return null;
    const [y, m, d] = String(value).substring(0, 10).split('-').map(Number);
    return new Date(y, m - 1, d);
}

function fmtDate(value) {
    const d = parseDate(value);
    return d ? DATE.format(d) : '';
}

function daysFromToday(value) {
    const d = parseDate(value);
    if (!d) return null;
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    return Math.round((d - today) / DAY_MS);
}

function reduceError(error) {
    if (Array.isArray(error?.body)) return error.body.map((e) => e.message).join(', ');
    return error?.body?.message || error?.message || 'Unknown error';
}

/**
 * Project Manager home: my active projects and their delivery health, supplier updates
 * waiting on my review, what's due in the next 30 days, and my open risks.
 */
export default class MyProjects extends NavigationMixin(LightningElement) {
    work;
    error;
    wiredResult;
    live = false;

    @wire(getMyWork)
    wired(result) {
        this.wiredResult = result;
        if (result.data) {
            this.work = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.error = reduceError(result.error);
        }
    }

    get isLoading() {
        return !this.work && !this.error;
    }

    get hasProjects() {
        return this.work.projects.length > 0;
    }

    get kpis() {
        const w = this.work;
        const atRisk = w.projects.reduce((n, s) => n + s.atRisk, 0);
        const revenue = w.projects.reduce((n, s) => n + (s.revenueAtRisk || 0), 0);
        const overdue = w.projects.reduce((n, s) => n + s.overdue, 0);
        return [
            { key: 'p', label: 'Active projects', value: String(w.projects.length) },
            { key: 'r', label: 'At-risk deliverables', value: String(atRisk), sub: revenue ? `${USD_COMPACT.format(revenue)} at risk` : '', alert: atRisk > 0 },
            { key: 'u', label: 'Updates to review', value: String(w.updatesToReview.length), alert: w.updatesToReview.length > 0 },
            { key: 'd', label: 'Due in 30 days', value: String(w.dueSoon.length), sub: overdue ? `${overdue} overdue` : '', alert: overdue > 0 },
            { key: 'k', label: 'Open risks', value: String(w.risks.length) }
        ].map((k) => ({ ...k, className: k.alert ? 'kpi kpi-alert' : 'kpi' }));
    }

    get projectCards() {
        return this.work.projects.map((s) => {
            const p = s.project;
            const pctDone = p.Percent_Complete__c || 0;
            const chips = [];
            if (s.atRisk) chips.push({ key: 'risk', label: `${s.atRisk} at risk · ${USD_COMPACT.format(s.revenueAtRisk || 0)}`, className: 'chip chip-red' });
            if (s.overdue) chips.push({ key: 'late', label: `${s.overdue} overdue`, className: 'chip chip-red' });
            if (s.updatesToReview) chips.push({ key: 'upd', label: `${s.updatesToReview} update${s.updatesToReview === 1 ? '' : 's'} to review`, className: 'chip chip-orange' });
            if (s.dueSoon) chips.push({ key: 'due', label: `${s.dueSoon} due in 30 days`, className: 'chip' });
            if (p.Margin_Erosion__c < 0) chips.push({ key: 'margin', label: `Margin ${Number(p.Margin_Erosion__c).toFixed(1)} pts vs bid`, className: 'chip chip-orange' });
            return {
                id: p.Id,
                name: p.Name,
                health: p.Health__c,
                meta: [p.Account__r?.Name, p.Contract__r?.Award_Number__c, p.Status__c, p.Target_End_Date__c && `ends ${fmtDate(p.Target_End_Date__c)}`]
                    .filter(Boolean)
                    .join(' · '),
                progressStyle: `width:${Math.min(Math.max(pctDone, 0), 100)}%`,
                progressLabel: `${Math.round(pctDone)}% complete · ${s.complete}/${s.deliverables} deliverables done`,
                chips,
                hasChips: chips.length > 0
            };
        });
    }

    get updateItems() {
        return this.work.updatesToReview.map((u) => ({
            id: u.Id,
            deliverableId: u.Deliverable__c,
            title: u.Deliverable__r?.Name,
            meta: [u.Supplier__r?.Name, u.Submitted_Date__c && `submitted ${DATE.format(new Date(u.Submitted_Date__c))}`,
                u.Reported_Status__c, u.Percent_Complete__c !== null && u.Percent_Complete__c !== undefined && `${Math.round(u.Percent_Complete__c)}%`]
                .filter(Boolean)
                .join(' · '),
            flag: u.Requires_Customer_Action__c ? 'Needs customer action' : u.Supplier_Health__c === 'Red' ? 'Supplier reports Red' : ''
        }));
    }

    get hasUpdates() {
        return this.updateItems.length > 0;
    }

    get dueItems() {
        return this.work.dueSoon.map((d) => {
            const days = daysFromToday(d.Due_Date__c);
            let when = fmtDate(d.Due_Date__c);
            let whenClass = 'when';
            if (days !== null && days < 0) {
                when = `${-days}d overdue`;
                whenClass = 'when when-late';
            } else if (days !== null && days <= 7) {
                when = days === 0 ? 'today' : `in ${days}d`;
                whenClass = 'when when-soon';
            }
            const slip = d.Forecast_Completion_Date__c && d.Due_Date__c && d.Forecast_Completion_Date__c > d.Due_Date__c
                ? `forecast ${fmtDate(d.Forecast_Completion_Date__c)}`
                : '';
            return {
                id: d.Id,
                name: d.Name,
                health: d.Health__c,
                when,
                whenClass,
                meta: [d.Project__r?.Name, d.Status__c, slip, d.Supplier__r?.Name].filter(Boolean).join(' · ')
            };
        });
    }

    get hasDue() {
        return this.dueItems.length > 0;
    }

    get riskItems() {
        return this.work.risks.map((r) => ({
            id: r.Id,
            name: r.Name,
            severity: r.Severity__c || 'Unscored',
            severityClass: r.Severity__c === 'Critical' || r.Severity__c === 'High' ? 'sev sev-high' : 'sev',
            meta: [r.Deliverable__r?.Name || r.Project__r?.Name, r.Status__c, r.Target_Resolution_Date__c && `resolve by ${fmtDate(r.Target_Resolution_Date__c)}`]
                .filter(Boolean)
                .join(' · ')
        }));
    }

    get hasRisks() {
        return this.riskItems.length > 0;
    }

    handleOpen(event) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: event.currentTarget.dataset.id, actionName: 'view' }
        });
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

    // Any deliverable or supplier update change can move these counts; the batch is debounced.
    handleLiveChanges() {
        refreshApex(this.wiredResult);
    }
}
