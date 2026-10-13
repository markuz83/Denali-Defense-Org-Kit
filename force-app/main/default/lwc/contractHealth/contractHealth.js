import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getHealth from '@salesforce/apex/ContractHealthController.getHealth';

const DAY_MS = 24 * 60 * 60 * 1000;
const USD_COMPACT = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', notation: 'compact', maximumFractionDigits: 1 });
const money = (v) => USD_COMPACT.format(v || 0);
const pctLabel = (v) => (v === null || v === undefined ? '—' : `${Number(v).toFixed(1)}%`);

function daysUntil(dateStr) {
    if (!dateStr) return null;
    const [y, m, d] = dateStr.split('-').map(Number);
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    return Math.round((new Date(y, m - 1, d) - today) / DAY_MS);
}

function reduceError(error) {
    if (Array.isArray(error?.body)) return error.body.map((e) => e.message).join(', ');
    return error?.body?.message || error?.message || 'Unknown error';
}

/**
 * Contract Health for the Contract record page: funding and recognition, margin at award vs
 * forecast, the next option decision, and what's at risk in the projects underneath.
 */
export default class ContractHealth extends NavigationMixin(LightningElement) {
    @api recordId;
    h;
    error;

    @wire(getHealth, { contractId: '$recordId' })
    wired({ data, error }) {
        if (data) {
            this.h = data;
            this.error = undefined;
        } else if (error) {
            this.error = reduceError(error);
        }
    }

    get isLoading() {
        return !this.h && !this.error;
    }

    get k() {
        return this.h.contract;
    }

    // ---------------------------------------------------------------- funding

    get value() {
        return this.k.Contract_Value__c || 0;
    }

    get parts() {
        const value = this.value;
        const recognized = Math.min(this.k.Revenue_Recognized__c || 0, value);
        const fundedOpen = Math.max(Math.min(this.k.Funded_Value__c || 0, value) - recognized, 0);
        return { recognized, fundedOpen, unfunded: Math.max(value - recognized - fundedOpen, 0) };
    }

    share(v) {
        return this.value ? Math.round((v / this.value) * 1000) / 10 : 0;
    }

    get valueLabel() {
        return money(this.value);
    }

    get recognizedStyle() {
        return `width:${this.share(this.parts.recognized)}%`;
    }

    get fundedStyle() {
        return `width:${this.share(this.parts.fundedOpen)}%`;
    }

    get recognizedLabel() {
        return money(this.parts.recognized);
    }

    get fundedLabel() {
        return money(this.parts.fundedOpen);
    }

    get unfundedLabel() {
        return money(this.parts.unfunded);
    }

    // ---------------------------------------------------------------- margin

    get hasMargin() {
        return this.k.Original_Margin__c !== null && this.k.Original_Margin__c !== undefined;
    }

    get originalMargin() {
        return pctLabel(this.k.Original_Margin__c);
    }

    get currentMargin() {
        return pctLabel(this.k.Current_Margin__c);
    }

    get varianceLabel() {
        const v = this.k.Margin_Variance__c;
        return v === null || v === undefined ? '' : `${v >= 0 ? '+' : ''}${Number(v).toFixed(1)} pts`;
    }

    get varianceClass() {
        return this.k.Margin_Variance__c < 0 ? 'variance slds-text-color_error' : 'variance slds-text-color_success';
    }

    // ---------------------------------------------------------------- option

    get option() {
        const days = this.k.Status === 'Activated' ? daysUntil(this.k.Next_Option_Date__c) : null;
        if (days === null) return null;
        if (days < 0) return { label: 'Option date passed', className: 'option option-past', sub: this.k.Current_Period__c };
        return {
            label: `${days} day${days === 1 ? '' : 's'} to option decision`,
            className: days <= 60 ? 'option option-urgent' : days <= 120 ? 'option option-soon' : 'option option-ok',
            sub: [this.k.Current_Period__c && `Now in ${this.k.Current_Period__c}`, this.k.Program_Manager__r?.Name && `PM ${this.k.Program_Manager__r.Name}`]
                .filter(Boolean)
                .join(' · ')
        };
    }

    // ---------------------------------------------------------------- underneath

    get tiles() {
        const h = this.h;
        return [
            { key: 'del', label: 'Deliverables done', value: `${h.deliverablesComplete} / ${h.deliverables}` },
            { key: 'risk', label: 'Revenue at risk', value: money(h.revenueAtRisk), alert: h.revenueAtRisk > 0 },
            { key: 'await', label: 'Awaiting acceptance', value: money(h.revenueAwaitingAcceptance) },
            { key: 'late', label: 'Overdue', value: String(h.deliverablesOverdue), alert: h.deliverablesOverdue > 0 },
            { key: 'risks', label: 'Open risks', value: `${h.openRisks} (${h.highRisks} high)`, alert: h.highRisks > 0 },
            { key: 'cases', label: 'Open cases', value: String(h.openCases) }
        ].map((t) => ({ ...t, className: t.alert ? 'tile tile-alert' : 'tile' }));
    }

    get hasProjects() {
        return this.h.projects.length > 0;
    }

    get projects() {
        return this.h.projects.map((p) => ({
            id: p.Id,
            name: p.Name,
            health: p.Health__c,
            meta: [p.Status__c, p.Percent_Complete__c !== null && p.Percent_Complete__c !== undefined && `${Math.round(p.Percent_Complete__c)}% done`,
                p.Project_Manager__r?.Name].filter(Boolean).join(' · '),
            margin: p.Forecast_Margin__c !== null && p.Forecast_Margin__c !== undefined ? `${pctLabel(p.Forecast_Margin__c)} forecast` : '',
            erosion: p.Margin_Erosion__c < 0 ? `${Number(p.Margin_Erosion__c).toFixed(1)} pts` : '',
            erosionClass: 'slds-text-color_error'
        }));
    }

    handleOpen(event) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: event.currentTarget.dataset.id, actionName: 'view' }
        });
    }
}
