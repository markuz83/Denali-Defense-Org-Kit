import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { encodeDefaultFieldValues } from 'lightning/pageReferenceUtils';
import { refreshApex } from '@salesforce/apex';
import getData from '@salesforce/apex/AccountCommandCenterController.getData';
import getPickerAccounts from '@salesforce/apex/AccountCommandCenterController.getPickerAccounts';
import { url, pct, reduceError } from 'c/accountSectionUtils';

const DAY_MS = 24 * 60 * 60 * 1000;
const COMPACT_USD = new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    notation: 'compact',
    maximumFractionDigits: 1
});
const PERCENT = new Intl.NumberFormat('en-US', { style: 'percent', maximumFractionDigits: 1 });
const money = (v) => COMPACT_USD.format(v || 0);
const TOP_RISKS = 5;

function daysUntil(dateStr) {
    if (!dateStr) return null;
    const [y, m, d] = dateStr.split('-').map(Number);
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    return Math.round((new Date(y, m - 1, d) - today) / DAY_MS);
}

function dueText(dateStr) {
    const days = daysUntil(dateStr);
    if (days === null) return 'No due date';
    if (days < 0) return `${-days} day${days === -1 ? '' : 's'} late`;
    if (days === 0) return 'Due today';
    return `Due in ${days} day${days === 1 ? '' : 's'}`;
}

/**
 * The Account Command Center for phones (the Denali Portfolio Mobile app). Same data as the
 * desktop accountCommandCenter (getData), laid out as stacked, collapsible sections: KPIs, what
 * needs attention, contracts, projects, top risks, and service. Rows open their records. The
 * desktop's tree grid, timeline and heat map are left out, and there are no live updates (the
 * mobile app has no streaming), so it has a Refresh button instead. On an app page it shows a
 * drop-down of active customers; on an Account record page it uses the record.
 */
export default class AccountCommandCenterMobile extends NavigationMixin(LightningElement) {
    _recordId;
    accountId;
    data;
    error;
    wiredResult;
    accountOptions;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        this.accountId = value;
    }

    @wire(getData, { accountId: '$accountId' })
    wired(result) {
        this.wiredResult = result;
        if (result.data) {
            this.data = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.error = reduceError(result.error);
            this.data = undefined;
        }
    }

    connectedCallback() {
        if (!this._recordId) {
            getPickerAccounts()
                .then((options) => {
                    this.accountOptions = options;
                })
                .catch((e) => {
                    this.accountOptions = [];
                    this.error = reduceError(e);
                });
        }
    }

    // ---------------------------------------------------------------- state

    get showPicker() {
        return !this._recordId;
    }

    get pickerReady() {
        return !!this.accountOptions && this.accountOptions.length > 0;
    }

    get pickerEmpty() {
        return !!this.accountOptions && this.accountOptions.length === 0;
    }

    // A native select has no placeholder, so the first option prompts for a choice.
    get selectOptions() {
        return [{ label: 'Select an account', value: '' }, ...this.accountOptions];
    }

    get selectedValue() {
        return this.accountId || '';
    }

    get isLoading() {
        return !!this.accountId && !this.data && !this.error;
    }

    get hasData() {
        return !!this.data && !!this.data.account;
    }

    get account() {
        return this.data.account;
    }

    get healthBadgeClass() {
        const h = this.account.Customer_Health__c;
        if (h === 'Red') return 'slds-theme_error';
        if (h === 'Yellow') return 'slds-theme_warning';
        if (h === 'Green') return 'slds-theme_success';
        return '';
    }

    get healthLabel() {
        return this.account.Customer_Health__c ? `Health: ${this.account.Customer_Health__c}` : 'Health not set';
    }

    get subtitle() {
        return [this.account.Customer_Tier__c && `${this.account.Customer_Tier__c} tier`, this.account.Owner?.Name && `Owner: ${this.account.Owner.Name}`]
            .filter(Boolean)
            .join(' · ');
    }

    // Open the sections that have something to act on.
    get openSections() {
        const open = ['contracts'];
        if (this.attentionItems.length) open.unshift('attention');
        return open;
    }

    // ---------------------------------------------------------------- KPIs

    get kpis() {
        const k = this.data.kpis;
        return [
            { key: 'acv', label: 'Active Contract Value', value: money(k.activeContractValue), sub: 'Activated contracts' },
            { key: 'backlog', label: 'Backlog', value: money(k.backlog), sub: 'Not yet recognized' },
            {
                key: 'risk',
                label: 'Revenue at Risk',
                value: money(k.revenueAtRisk),
                sub: `${k.atRiskDeliverables} at-risk deliverable${k.atRiskDeliverables === 1 ? '' : 's'}`,
                alert: k.revenueAtRisk > 0
            },
            { key: 'risks', label: 'Open Risks', value: String(k.openRisks), sub: `${k.highRisks} high or critical`, alert: k.highRisks > 0 },
            { key: 'cases', label: 'Open Cases', value: String(k.openCases), sub: `${k.severeCases} Sev 1/2`, alert: k.severeCases > 0 },
            {
                key: 'updates',
                label: 'Updates to Review',
                value: String(k.updatesAwaitingReview),
                sub: `${k.overdueDeliverables} overdue deliverable${k.overdueDeliverables === 1 ? '' : 's'}`,
                alert: k.overdueDeliverables > 0
            }
        ].map((t) => ({ ...t, className: t.alert ? 'kpi kpi-alert' : 'kpi' }));
    }

    // ---------------------------------------------------------------- needs attention

    get attentionItems() {
        const projectName = new Map(this.data.projects.map((p) => [p.Id, p.Name]));
        return this.data.deliverables
            .filter((d) => d.Is_At_Risk__c || d.Is_Overdue__c)
            .map((d) => ({
                id: d.Id,
                url: url(d.Id),
                name: d.Name,
                health: d.Health__c,
                project: projectName.get(d.Project__c),
                status: d.Status__c,
                due: dueText(d.Due_Date__c),
                dueClass: d.Is_Overdue__c ? 'slds-text-color_error' : '',
                revenue: d.Revenue_Milestone__c ? `${money(d.Revenue_Milestone__c)} at stake` : null
            }));
    }

    get hasAttention() {
        return this.attentionItems.length > 0;
    }

    get attentionLabel() {
        return `Needs Attention (${this.attentionItems.length})`;
    }

    // ---------------------------------------------------------------- contracts

    get contractCards() {
        return this.data.contracts.map((c) => {
            const value = c.Contract_Value__c || 0;
            const recognized = Math.min(c.Revenue_Recognized__c || 0, value);
            const fundedOpen = Math.max(Math.min(c.Funded_Value__c || 0, value) - recognized, 0);
            const share = (v) => (value ? Math.round((v / value) * 1000) / 10 : 0);
            const days = c.Status === 'Activated' ? daysUntil(c.Next_Option_Date__c) : null;
            let optionLabel = null;
            let optionClass = '';
            if (days !== null) {
                if (days < 0) {
                    optionLabel = 'Option date passed';
                    optionClass = 'slds-theme_shade';
                } else {
                    optionLabel = `Option decision in ${days} day${days === 1 ? '' : 's'}`;
                    optionClass = days <= 60 ? 'slds-theme_error' : days <= 120 ? 'slds-theme_warning' : 'slds-theme_success';
                }
            }
            const variance = c.Margin_Variance__c;
            const hasMargin = c.Original_Margin__c !== null && c.Original_Margin__c !== undefined;
            return {
                id: c.Id,
                url: url(c.Id),
                title: c.Award_Number__c || c.ContractNumber,
                subtitle: [c.Contract_Type__c, c.Current_Period__c].filter(Boolean).join(' · '),
                status: c.Status,
                statusClass: c.Status === 'Activated' ? 'slds-theme_success' : '',
                value: money(value),
                recognized: money(recognized),
                fundedOpen: money(fundedOpen),
                unfunded: money(value - recognized - fundedOpen),
                recognizedStyle: `width:${share(recognized)}%`,
                fundedStyle: `width:${share(fundedOpen)}%`,
                hasMargin,
                marginText: hasMargin
                    ? `Margin ${PERCENT.format(pct(c.Original_Margin__c) || 0)} at award → ${
                        c.Current_Margin__c === null || c.Current_Margin__c === undefined ? '—' : PERCENT.format(pct(c.Current_Margin__c))} forecast`
                    : '',
                varianceText: variance === null || variance === undefined ? '' : ` (${variance >= 0 ? '+' : ''}${Number(variance).toFixed(1)} pts)`,
                varianceClass: variance < 0 ? 'slds-text-color_error' : 'slds-text-color_success',
                optionLabel,
                optionClass
            };
        });
    }

    get hasContracts() {
        return this.data.contracts.length > 0;
    }

    get contractsLabel() {
        return `Contracts (${this.data.contracts.length})`;
    }

    // ---------------------------------------------------------------- projects

    get projectItems() {
        const atRisk = new Map();
        this.data.deliverables
            .filter((d) => d.Is_At_Risk__c)
            .forEach((d) => atRisk.set(d.Project__c, (atRisk.get(d.Project__c) || 0) + 1));
        return this.data.projects.map((p) => {
            const n = atRisk.get(p.Id) || 0;
            return {
                id: p.Id,
                url: url(p.Id),
                name: p.Name,
                health: p.Health__c,
                detail: [p.Status__c, p.Percent_Complete__c !== null && p.Percent_Complete__c !== undefined ? `${Math.round(p.Percent_Complete__c)}% complete` : null, p.Project_Manager__r?.Name]
                    .filter(Boolean)
                    .join(' · '),
                atRisk: n ? `${n} at-risk deliverable${n === 1 ? '' : 's'}` : null
            };
        });
    }

    get hasProjects() {
        return this.data.projects.length > 0;
    }

    get projectsLabel() {
        return `Projects (${this.data.projects.length})`;
    }

    // ---------------------------------------------------------------- risks

    get riskItems() {
        return this.data.risks.slice(0, TOP_RISKS).map((r) => ({
            id: r.Id,
            url: url(r.Id),
            name: r.Name,
            score: r.Risk_Score__c === null || r.Risk_Score__c === undefined ? '–' : String(r.Risk_Score__c),
            scoreClass: /^(High|Critical)$/.test(r.Severity__c || '') ? 'score score_high' : 'score',
            detail: [r.Severity__c, r.Status__c, r.Risk_Owner__r?.Name].filter(Boolean).join(' · ')
        }));
    }

    get hasRisks() {
        return this.data.risks.length > 0;
    }

    get risksLabel() {
        const n = this.data.risks.length;
        return n > TOP_RISKS ? `Top Risks (${TOP_RISKS} of ${n})` : `Risks (${n})`;
    }

    // ---------------------------------------------------------------- service and cases

    get serviceItems() {
        return this.data.serviceEngagements.map((s) => ({
            id: s.Id,
            url: url(s.Id),
            name: s.Name,
            health: s.Health__c,
            detail: [s.Service_Type__c, `${s.Cases_Open__c || 0} open case${s.Cases_Open__c === 1 ? '' : 's'}`]
                .filter(Boolean)
                .join(' · '),
            slaOption: s.SLA_Breaches__c ? 'negative' : 'positive',
            slaLabel: `${s.SLA_Breaches__c || 0} SLA breach${s.SLA_Breaches__c === 1 ? '' : 'es'}`
        }));
    }

    get caseItems() {
        return this.data.cases.map((c) => ({
            id: c.Id,
            url: url(c.Id),
            name: `${c.CaseNumber} · ${c.Subject}`,
            severity: c.Severity__c,
            severityClass: /^Sev [12]/.test(c.Severity__c || '') ? 'slds-text-color_error' : '',
            detail: [c.IsEscalated ? `${c.Status} (escalated)` : c.Status, c.Deliverable__r?.Name].filter(Boolean).join(' · ')
        }));
    }

    get hasService() {
        return this.data.serviceEngagements.length > 0 || this.data.cases.length > 0;
    }

    get hasEngagements() {
        return this.data.serviceEngagements.length > 0;
    }

    get hasCases() {
        return this.data.cases.length > 0;
    }

    get serviceLabel() {
        return `Service & Cases (${this.data.cases.length} open)`;
    }

    // ---------------------------------------------------------------- actions

    handleAccountPicked(event) {
        this.accountId = event.detail.value || undefined;
        this.data = undefined;
        this.error = undefined;
    }

    handleRefresh() {
        return refreshApex(this.wiredResult);
    }

    // Rows are links (so they read as links), but navigate in-app rather than by URL.
    handleOpen(event) {
        event.preventDefault();
        this.navigateToRecord(event.currentTarget.dataset.id);
    }

    handleOpenAccount() {
        this.navigateToRecord(this.accountId);
    }

    handleNewRisk() {
        this.navigateToNew('Risk__c', { Account__c: this.accountId });
    }

    handleNewCase() {
        this.navigateToNew('Case', { AccountId: this.accountId });
    }

    navigateToRecord(recordId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, actionName: 'view' }
        });
    }

    navigateToNew(objectApiName, defaults) {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName, actionName: 'new' },
            state: { defaultFieldValues: encodeDefaultFieldValues(defaults) }
        });
    }
}
