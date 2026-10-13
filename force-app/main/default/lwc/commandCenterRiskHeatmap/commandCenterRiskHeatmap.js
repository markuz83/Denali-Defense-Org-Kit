import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

const LIKELIHOOD = ['5 - Near Certainty', '4 - Highly Likely', '3 - Likely', '2 - Low Likelihood', '1 - Not Likely'];
const CONSEQUENCE = ['1 - Minimal', '2 - Minor', '3 - Moderate', '4 - Significant', '5 - Severe'];

function level(value) {
    const n = parseInt(String(value || '').charAt(0), 10);
    return Number.isNaN(n) ? null : n;
}

// Same bands as the Risk Severity formula: 15+ Critical, 10+ High, 5+ Medium, else Low.
function band(score) {
    if (score >= 15) return 'critical';
    if (score >= 10) return 'high';
    if (score >= 5) return 'medium';
    return 'low';
}

/**
 * 5x5 risk heat map (Likelihood down, Consequence across) for a list of Risk__c records.
 * Click a cell to list its risks; risks without both scores are listed as unscored.
 */
export default class CommandCenterRiskHeatmap extends NavigationMixin(LightningElement) {
    @api title = 'Risk Heat Map';
    @api risks = [];
    selectedKey = null;

    get grid() {
        const counts = new Map();
        (this.risks || []).forEach((r) => {
            const l = level(r.Likelihood__c);
            const c = level(r.Consequence__c);
            if (l && c) counts.set(`${l}-${c}`, (counts.get(`${l}-${c}`) || 0) + 1);
        });
        return LIKELIHOOD.map((lLabel) => {
            const l = level(lLabel);
            return {
                key: `row${l}`,
                label: lLabel,
                cells: CONSEQUENCE.map((cLabel) => {
                    const c = level(cLabel);
                    const key = `${l}-${c}`;
                    const count = counts.get(key) || 0;
                    const classes = ['cell', `cell-${band(l * c)}`];
                    if (count) classes.push('cell-filled');
                    if (key === this.selectedKey) classes.push('cell-selected');
                    return {
                        key,
                        count: count || '',
                        className: classes.join(' '),
                        label: `Likelihood ${lLabel}, consequence ${cLabel}: ${count} risk${count === 1 ? '' : 's'}`
                    };
                })
            };
        });
    }

    get consequenceLabels() {
        return CONSEQUENCE.map((c) => ({ key: c, label: c.replace(/^\d - /, ''), level: level(c) }));
    }

    get unscored() {
        return (this.risks || []).filter((r) => !(level(r.Likelihood__c) && level(r.Consequence__c)));
    }

    get hasUnscored() {
        return this.unscored.length > 0;
    }

    get unscoredLabel() {
        const n = this.unscored.length;
        return `${n} unscored risk${n === 1 ? '' : 's'}`;
    }

    get selectedRisks() {
        if (!this.selectedKey) return [];
        const list = this.selectedKey === 'unscored'
            ? this.unscored
            : (this.risks || []).filter((r) => `${level(r.Likelihood__c)}-${level(r.Consequence__c)}` === this.selectedKey);
        return list.map((r) => ({
            id: r.Id,
            name: r.Name,
            meta: [r.Severity__c, r.Status__c, r.Deliverable__r?.Name || r.Project__r?.Name].filter(Boolean).join(' · ')
        }));
    }

    get hasSelection() {
        return this.selectedRisks.length > 0;
    }

    get hasRisks() {
        return (this.risks || []).length > 0;
    }

    handleCellClick(event) {
        const key = event.currentTarget.dataset.key;
        this.selectedKey = this.selectedKey === key ? null : key;
    }

    handleUnscoredClick() {
        this.selectedKey = this.selectedKey === 'unscored' ? null : 'unscored';
    }

    handleRiskClick(event) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: event.currentTarget.dataset.id, actionName: 'view' }
        });
    }
}
