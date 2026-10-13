import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getIntel from '@salesforce/apex/CompetitorIntelController.getIntel';

const USD_COMPACT = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', notation: 'compact', maximumFractionDigits: 1 });
const DATE = new Intl.DateTimeFormat('en-US', { month: 'short', year: 'numeric' });
const pctLabel = (v) => (v === null || v === undefined ? '—' : `${Number(v).toFixed(1)}%`);
// For sentences: one decimal place, without a trailing ".0" (13.5%, 18%).
const marginLabel = (v) => `${Number(Number(v).toFixed(1))}%`;

function reduceError(error) {
    if (Array.isArray(error?.body)) return error.body.map((e) => e.message).join(', ');
    return error?.body?.message || error?.message || 'Unknown error';
}

/**
 * Our record against one competitor (the Opportunity's incumbent, or the competitor Account
 * itself): win rate, bookings won and lost, margin on wins vs losses, why we lose, and the
 * most recent head-to-head deals.
 */
export default class CompetitorIntel extends NavigationMixin(LightningElement) {
    @api recordId;
    intel;
    error;
    loaded = false;

    @wire(getIntel, { recordId: '$recordId' })
    wired({ data, error }) {
        if (data !== undefined) {
            this.intel = data;
            this.error = undefined;
            this.loaded = true;
        } else if (error) {
            this.error = reduceError(error);
            this.loaded = true;
        }
    }

    get isLoading() {
        return !this.loaded;
    }

    get noCompetitor() {
        return this.loaded && !this.error && !this.intel;
    }

    get title() {
        return this.intel ? `Competitor Intel: ${this.intel.competitorName}` : 'Competitor Intel';
    }

    get decided() {
        return this.intel.wins + this.intel.losses;
    }

    get hasHistory() {
        return this.decided > 0;
    }

    get winRate() {
        return this.decided ? Math.round((this.intel.wins / this.decided) * 100) : 0;
    }

    get winRateLabel() {
        return `${this.winRate}%`;
    }

    get recordLine() {
        return `${this.intel.wins} won · ${this.intel.losses} lost (3 yrs)`;
    }

    get winBarStyle() {
        return `width:${this.winRate}%`;
    }

    get stats() {
        const i = this.intel;
        return [
            { key: 'won', label: 'Bookings won', value: USD_COMPACT.format(i.bookingsWon || 0) },
            { key: 'lost', label: 'Bookings lost to them', value: USD_COMPACT.format(i.bookingsLost || 0), alert: i.bookingsLost > 0 },
            { key: 'mwon', label: 'Avg margin on wins', value: pctLabel(i.avgMarginWon) },
            { key: 'mlost', label: 'Avg margin on losses', value: pctLabel(i.avgMarginLost) },
            { key: 'open', label: 'Open deals vs them', value: `${i.openDeals} · ${USD_COMPACT.format(i.openPipeline || 0)}` }
        ].map((s) => ({ ...s, className: s.alert ? 'stat-value slds-text-color_error' : 'stat-value' }));
    }

    // History first (average margin on wins against losses), what it suggests, then how this
    // pursuit compares with its margin floor when the component is on an open opportunity.
    get marginInsight() {
        const { avgMarginWon, avgMarginLost, pursuitMargin, pursuitFloor, competitorName } = this.intel;
        if (avgMarginWon === null || avgMarginWon === undefined || avgMarginLost === null || avgMarginLost === undefined) return null;
        const diff = avgMarginLost - avgMarginWon;
        const pressure = diff >= 0.5;
        const sentences = [`Historical wins against ${competitorName} average ${marginLabel(avgMarginWon)} margin, versus ${marginLabel(avgMarginLost)} on losses.`];
        if (pressure) {
            sentences.push('That suggests margin pressure worth investigating.');
        } else if (diff <= -0.5) {
            sentences.push('Our wins carry more margin than our losses, so price doesn\'t seem to decide these deals.');
        } else {
            sentences.push('Margin hasn\'t separated our wins from our losses.');
        }
        if (pursuitMargin !== null && pursuitMargin !== undefined) {
            let pursuit = `This pursuit is at ${marginLabel(pursuitMargin)}`;
            if (pursuitFloor !== null && pursuitFloor !== undefined) {
                pursuit += pursuitMargin < pursuitFloor
                    ? `, which ${pressure ? 'also ' : ''}falls below our ${marginLabel(pursuitFloor)} floor`
                    : `, at or above our ${marginLabel(pursuitFloor)} floor`;
            }
            sentences.push(`${pursuit}.`);
        }
        return sentences.join(' ');
    }

    get hasReasons() {
        return this.intel.lossReasons && this.intel.lossReasons.length > 0;
    }

    get reasons() {
        const max = Math.max(...this.intel.lossReasons.map((r) => r.amount || 0), 1);
        return [...this.intel.lossReasons]
            .sort((a, b) => (b.amount || 0) - (a.amount || 0))
            .map((r) => ({
                key: r.reason,
                label: r.reason,
                detail: `${r.count} · ${USD_COMPACT.format(r.amount || 0)}`,
                style: `width:${Math.max(((r.amount || 0) / max) * 100, 4)}%`
            }));
    }

    get recent() {
        return this.intel.recent.map((h) => ({
            id: h.id,
            name: h.name,
            outcome: h.won ? 'Won' : 'Lost',
            outcomeClass: h.won ? 'outcome outcome-won' : 'outcome outcome-lost',
            meta: [h.closeDate && DATE.format(new Date(h.closeDate)), h.amount && USD_COMPACT.format(h.amount),
                h.margin !== null && h.margin !== undefined && `${Number(h.margin).toFixed(0)}% margin`, h.lossReason]
                .filter(Boolean)
                .join(' · ')
        }));
    }

    handleOpen(event) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: event.currentTarget.dataset.id, actionName: 'view' }
        });
    }
}
