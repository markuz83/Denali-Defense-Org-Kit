import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { encodeDefaultFieldValues } from 'lightning/pageReferenceUtils';
import { refreshApex } from '@salesforce/apex';
import getData from '@salesforce/apex/AccountCommandCenterController.getData';
import getPickerAccounts from '@salesforce/apex/AccountCommandCenterController.getPickerAccounts';
import { subscribeToDeliveryChanges, touchesAny } from 'c/deliveryLiveUpdates';
import { url, pct, reduceError } from 'c/accountSectionUtils';

const DAY_MS = 24 * 60 * 60 * 1000;
const COMPACT_USD = new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    notation: 'compact',
    maximumFractionDigits: 1
});

// Solid colored circles for the tree grid, which can't use custom cell types (the Service table
// uses c-health-datatable instead). Datatable cells can't take component CSS, so a character is
// the simplest way to get a filled shape there. Screen readers announce "green circle" etc.
const HEALTH_DOT = {
    Green: '\u{1F7E2}',
    Yellow: '\u{1F7E1}',
    Red: '\u{1F534}'
};

// No fixed widths: the tree grid sizes each column to its content (column-widths-mode="auto").
const TREE_COLUMNS = [
    { type: 'url', fieldName: 'url', label: 'Name', typeAttributes: { label: { fieldName: 'name' } } },
    { type: 'text', fieldName: 'kind', label: 'Type' },
    { type: 'text', fieldName: 'status', label: 'Status' },
    {
        type: 'text',
        fieldName: 'health',
        label: 'Health',
        cellAttributes: { alignment: 'center' }
    },
    { type: 'percent', fieldName: 'pct', label: '% Done', typeAttributes: { maximumFractionDigits: 0 } },
    { type: 'date-local', fieldName: 'due', label: 'Due / End' },
    { type: 'date-local', fieldName: 'forecast', label: 'Forecast' },
    { type: 'number', fieldName: 'slip', label: 'Slip (days)', cellAttributes: { class: { fieldName: 'slipClass' } } },
    { type: 'currency', fieldName: 'revenue', label: 'Value', typeAttributes: { maximumFractionDigits: 0 } },
    { type: 'text', fieldName: 'flags', label: 'Flags', wrapText: true }
];

// Rendered by c-health-datatable: "health" draws an SLDS status icon, "score" a met/breached SLA icon.
const SERVICE_COLUMNS = [
    { type: 'url', fieldName: 'url', label: 'Engagement', typeAttributes: { label: { fieldName: 'name' } } },
    { type: 'text', fieldName: 'type', label: 'Type' },
    { type: 'health', fieldName: 'health', label: 'Health', cellAttributes: { alignment: 'center' } },
    { type: 'number', fieldName: 'casesOpen', label: 'Open Cases' },
    {
        type: 'score',
        fieldName: 'slaBreaches',
        label: 'SLA Breaches',
        typeAttributes: { option: { fieldName: 'slaOption' }, label: { fieldName: 'slaLabel' } }
    },
    { type: 'date-local', fieldName: 'nextMilestone', label: 'Next Milestone' }
];

const CASE_COLUMNS = [
    { type: 'url', fieldName: 'url', label: 'Case', initialWidth: 95, typeAttributes: { label: { fieldName: 'number' } } },
    { type: 'text', fieldName: 'subject', label: 'Subject', wrapText: true },
    { type: 'text', fieldName: 'severity', label: 'Severity', cellAttributes: { class: { fieldName: 'severityClass' } } },
    { type: 'text', fieldName: 'status', label: 'Status' },
    { type: 'text', fieldName: 'impact', label: 'Deliverable' }
];

const PERCENT = new Intl.NumberFormat('en-US', { style: 'percent', maximumFractionDigits: 1 });
const money = (v) => COMPACT_USD.format(v || 0);
const healthDot = (h) => HEALTH_DOT[h] || h;

function daysUntil(dateStr) {
    if (!dateStr) return null;
    const [y, m, d] = dateStr.split('-').map(Number);
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    return Math.round((new Date(y, m - 1, d) - today) / DAY_MS);
}

/**
 * One screen for everything happening on an account: KPIs, contracts, the contract ->
 * project -> deliverable tree, a delivery timeline, the risk heat map, and service. Supplier
 * updates, suppliers and the team are separate components (accountSupplierUpdates,
 * accountSuppliers, accountTeam) to place on the page alongside it. On an Account record page it
 * uses the record; on an app page it shows a drop-down of active customers, labelled with their
 * award numbers.
 */
export default class AccountCommandCenter extends NavigationMixin(LightningElement) {
    _recordId;
    accountId;
    data;
    error;
    wiredResult;
    atRiskOnly = false;
    live = false;
    accountOptions;

    treeColumns = TREE_COLUMNS;
    serviceColumns = SERVICE_COLUMNS;
    caseColumns = CASE_COLUMNS;

    // No longer used. Salesforce won't remove a design property while the component is on a page,
    // so it stays as a no-op.
    @api hideSuppliersAndTeam = false;

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

    get isLoading() {
        return !!this.accountId && !this.data && !this.error;
    }

    get hasData() {
        return !!this.data && !!this.data.account;
    }

    get account() {
        return this.data.account;
    }

    get roleBadges() {
        return (this.account.Account_Role__c || '').split(';').filter(Boolean);
    }

    // Space the header card from the account picker above it (app page only).
    get headerCardClass() {
        return this.showPicker ? 'slds-show slds-var-m-top_small' : 'slds-show';
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
        return [this.account.Customer_Tier__c && `${this.account.Customer_Tier__c} tier`, this.account.Account_Status__c, this.account.Owner?.Name && `Owner: ${this.account.Owner.Name}`]
            .filter(Boolean)
            .join(' · ');
    }

    // ---------------------------------------------------------------- KPIs

    get kpis() {
        const k = this.data.kpis;
        return [
            { key: 'acv', label: 'Active Contract Value', value: money(k.activeContractValue), sub: 'Activated contracts' },
            { key: 'backlog', label: 'Backlog', value: money(k.backlog), sub: 'Not yet recognized' },
            { key: 'accepted', label: 'Revenue Accepted', value: money(k.revenueAccepted), sub: 'Milestones accepted' },
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

    // ---------------------------------------------------------------- contracts

    get hasContracts() {
        return this.data.contracts.length > 0;
    }

    // One contract gets the full-width strip layout instead of a lone card in a mostly empty row.
    get contractsClass() {
        return this.data.contracts.length === 1 ? 'contracts contracts_single slds-var-m-top_small' : 'contracts slds-var-m-top_small';
    }

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
            return {
                id: c.Id,
                url: url(c.Id),
                title: c.Award_Number__c || c.ContractNumber,
                subtitle: [c.ContractNumber, c.Contract_Type__c, c.Current_Period__c].filter(Boolean).join(' · '),
                status: c.Status,
                statusClass: c.Status === 'Activated' ? 'slds-theme_success' : '',
                value: money(value),
                recognized: money(recognized),
                fundedOpen: money(fundedOpen),
                unfunded: money(value - recognized - fundedOpen),
                recognizedStyle: `width:${share(recognized)}%`,
                fundedStyle: `width:${share(fundedOpen)}%`,
                hasMargin: c.Original_Margin__c !== null && c.Original_Margin__c !== undefined,
                marginText: `Margin ${PERCENT.format(pct(c.Original_Margin__c) || 0)} at award → ${
                    c.Current_Margin__c === null || c.Current_Margin__c === undefined ? '—' : PERCENT.format(pct(c.Current_Margin__c))} forecast`,
                hasVariance: variance !== null && variance !== undefined,
                varianceText: variance === null || variance === undefined ? '' : ` (${variance >= 0 ? '+' : ''}${Number(variance).toFixed(1)} pts)`,
                varianceClass: variance < 0 ? 'slds-text-color_error' : 'slds-text-color_success',
                optionLabel,
                optionClass,
                programManager: c.Program_Manager__r?.Name
            };
        });
    }

    // ---------------------------------------------------------------- delivery tree

    get treeData() {
        const d = this.data;
        const delByProject = new Map();
        d.deliverables.forEach((del) => {
            if (!delByProject.has(del.Project__c)) delByProject.set(del.Project__c, []);
            delByProject.get(del.Project__c).push(del);
        });

        const deliverableRow = (del) => {
            const flags = [];
            if (del.Is_At_Risk__c) flags.push('At risk');
            if (del.Is_Overdue__c) flags.push('Overdue');
            if (del.Requires_Customer_Action__c) flags.push('Customer action');
            if (del.Acceptance_Status__c && del.Acceptance_Status__c !== 'Not Submitted') flags.push(del.Acceptance_Status__c);
            return {
                id: del.Id,
                url: url(del.Id),
                name: del.Name,
                kind: 'Deliverable',
                status: del.Status__c,
                health: healthDot(del.Health__c),
                pct: pct(del.Percent_Complete__c),
                due: del.Due_Date__c,
                forecast: del.Forecast_Completion_Date__c,
                slip: del.Schedule_Variance_Days__c || null,
                slipClass: del.Schedule_Variance_Days__c > 0 ? 'slds-text-color_error' : '',
                revenue: del.Revenue_Milestone__c,
                flags: flags.join(', '),
                attention: del.Is_At_Risk__c || del.Is_Overdue__c
            };
        };

        const projectRow = (p) => {
            let children = (delByProject.get(p.Id) || []).map(deliverableRow);
            if (this.atRiskOnly) children = children.filter((c) => c.attention);
            const flags = [];
            if (p.Margin_Erosion__c < 0) flags.push(`Margin ${Number(p.Margin_Erosion__c).toFixed(1)} pts`);
            if (p.Project_Manager__r?.Name) flags.push(`PM: ${p.Project_Manager__r.Name}`);
            const row = {
                id: p.Id,
                url: url(p.Id),
                name: p.Name,
                kind: 'Project',
                status: p.Status__c,
                health: healthDot(p.Health__c),
                pct: pct(p.Percent_Complete__c),
                due: p.Target_End_Date__c,
                revenue: p.Revenue_Allocation__c,
                flags: flags.join(', '),
                attention: p.Health__c === 'Red' || children.length > 0
            };
            if (children.length) row._children = children;
            return row;
        };

        const projByContract = new Map();
        d.projects.forEach((p) => {
            if (!projByContract.has(p.Contract__c)) projByContract.set(p.Contract__c, []);
            projByContract.get(p.Contract__c).push(p);
        });

        const rows = [];
        const contractIds = new Set();
        d.contracts.forEach((c) => {
            contractIds.add(c.Id);
            let children = (projByContract.get(c.Id) || []).map(projectRow);
            if (this.atRiskOnly) children = children.filter((p) => p.attention);
            if (this.atRiskOnly && !children.length) return;
            const row = {
                id: c.Id,
                url: url(c.Id),
                name: c.Award_Number__c || c.ContractNumber,
                kind: 'Contract',
                status: c.Status,
                health: healthDot(c.Contract_Health__c),
                due: c.EndDate,
                revenue: c.Contract_Value__c,
                flags: c.Current_Period__c || ''
            };
            if (children.length) row._children = children;
            rows.push(row);
        });
        // Projects whose contract belongs to another account still show, at the top level.
        d.projects
            .filter((p) => !contractIds.has(p.Contract__c))
            .map(projectRow)
            .filter((p) => !this.atRiskOnly || p.attention)
            .forEach((p) => rows.push(p));
        return rows;
    }

    get hasTreeData() {
        return this.treeData.length > 0;
    }

    get expandedRows() {
        const ids = [];
        const walk = (rows) =>
            rows.forEach((r) => {
                if (r._children) {
                    ids.push(r.id);
                    walk(r._children);
                }
            });
        walk(this.treeData);
        return ids;
    }

    get treeEmptyMessage() {
        return this.atRiskOnly ? 'Nothing at risk or overdue.' : 'No contracts or projects on this account yet.';
    }

    handleAtRiskToggle(event) {
        this.atRiskOnly = event.target.checked;
    }

    // ---------------------------------------------------------------- timeline

    get timelineItems() {
        const projectName = new Map(this.data.projects.map((p) => [p.Id, p.Name]));
        return this.data.deliverables
            .filter((del) => del.Status__c !== 'Cancelled')
            .map((del) => ({
                id: del.Id,
                label: del.Name,
                group: projectName.get(del.Project__c) || 'Other',
                start: del.Planned_Start_Date__c,
                end: del.Due_Date__c,
                forecast: del.Forecast_Completion_Date__c,
                health: del.Health__c,
                status: del.Status__c,
                detail: del.Revenue_Milestone__c ? `${money(del.Revenue_Milestone__c)} milestone` : null
            }));
    }

    // ---------------------------------------------------------------- service

    get serviceRows() {
        return this.data.serviceEngagements.map((s) => ({
            id: s.Id,
            url: url(s.Id),
            name: s.Name,
            type: s.Service_Type__c,
            health: s.Health__c,
            casesOpen: s.Cases_Open__c,
            slaBreaches: s.SLA_Breaches__c || 0,
            slaOption: s.SLA_Breaches__c ? 'negative' : 'positive',
            slaLabel: s.SLA_Breaches__c ? 'SLA breached' : 'SLA met',
            nextMilestone: s.Next_Milestone_Date__c
        }));
    }

    get hasService() {
        return this.serviceRows.length > 0;
    }

    get caseRows() {
        return this.data.cases.map((c) => ({
            id: c.Id,
            url: url(c.Id),
            number: c.CaseNumber,
            subject: c.Subject,
            severity: c.Severity__c,
            severityClass: /^Sev [12]/.test(c.Severity__c || '') ? 'slds-text-color_error' : '',
            status: c.IsEscalated ? `${c.Status} (escalated)` : c.Status,
            impact: c.Deliverable__r?.Name
        }));
    }

    get hasCases() {
        return this.caseRows.length > 0;
    }

    // ---------------------------------------------------------------- actions

    handleAccountPicked(event) {
        this.accountId = event.detail.value;
        this.data = undefined;
        this.error = undefined;
    }

    handleRefresh() {
        return refreshApex(this.wiredResult);
    }

    // ---------------------------------------------------------------- live updates (Change Data Capture)

    connectedCallback() {
        this.disconnected = false;
        // The account list is for the app page only; a record page already has its account.
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

    // This account's deliverables or their updates, or anything newly created (it may belong here).
    handleLiveChanges(batch) {
        if (!this.data) return;
        const ids = new Set([...this.data.deliverables.map((d) => d.Id), ...this.data.updatesAwaitingReview.map((u) => u.Id)]);
        const created = batch.some((c) => c.changeType === 'CREATE');
        if (touchesAny(batch, ids) || created) {
            refreshApex(this.wiredResult);
        }
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
