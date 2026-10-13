import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

// The SVG is drawn at the container's measured pixel width (viewBox units = pixels), so text
// and bars keep a constant size however wide the window is; wider just means more room.
const DEFAULT_WIDTH = 900;
const MAX_LABEL_WIDTH = 270;
const RIGHT_PAD = 20;
const AXIS_HEIGHT = 28;
const GROUP_HEIGHT = 24;
const ROW_HEIGHT = 24;
const BAR_HEIGHT = 12;
const DAY_MS = 24 * 60 * 60 * 1000;
// Items with no start date (or a start after the end) get a bar this long, ending at the end date.
const DEFAULT_BAR_DAYS = 14;
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
// Health -> CSS class; the colours are SLDS 2 styling hooks in commandCenterTimeline.css.
const HEALTH_CLASS = { Green: 'health-green', Yellow: 'health-yellow', Red: 'health-red' };
const NEUTRAL_CLASS = 'health-none';

function toDate(value) {
    if (!value) return null;
    // Date fields arrive as 'YYYY-MM-DD'; parse as local dates so bars don't shift a day.
    const [y, m, d] = String(value).substring(0, 10).split('-').map(Number);
    return new Date(y, m - 1, d);
}

function truncate(text, max) {
    if (!text) return '';
    return text.length > max ? text.substring(0, max - 1) + '…' : text;
}

/**
 * Gantt-style timeline of dated items, grouped (e.g. deliverables by project).
 * Each item: { id, label, group, start, end, forecast, health, status, detail }.
 * A bar runs from start to end (due date); when forecast is later than end, a dashed red
 * slip line runs to a diamond at the forecast date. Clicking a row opens the record.
 */
export default class CommandCenterTimeline extends NavigationMixin(LightningElement) {
    @api title = 'Timeline';
    @api emptyMessage = 'Nothing with dates to show.';
    _items = [];
    layout = { rows: [], groups: [], ticks: [], height: 0 };
    width = DEFAULT_WIDTH;
    resizeObserver;

    @api
    get items() {
        return this._items;
    }
    set items(value) {
        this._items = value || [];
        this.layout = this.computeLayout(this._items);
    }

    get hasItems() {
        return this.layout.rows.length > 0;
    }

    get viewBox() {
        return `0 0 ${this.width} ${this.layout.height}`;
    }

    get svgHeight() {
        return this.layout.height;
    }

    computeLayout(source) {
        // barStart/barEnd are worked out up front so the date range includes the default bars too;
        // otherwise a bar with no start date can begin left of the chart, over the row labels.
        const items = source
            .map((i) => ({ ...i, s: toDate(i.start), e: toDate(i.end), f: toDate(i.forecast) }))
            .filter((i) => i.e || i.s)
            .map((i) => {
                const barEnd = i.e || i.s;
                const barStart = i.s && i.s <= barEnd ? i.s : new Date(barEnd.getTime() - DEFAULT_BAR_DAYS * DAY_MS);
                return { ...i, barStart, barEnd };
            });
        if (!items.length) return { rows: [], groups: [], ticks: [], height: 0 };

        // Date range covering every bar, forecast and today, padded to whole months.
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const all = [today];
        items.forEach((i) => [i.barStart, i.barEnd, i.f].forEach((d) => d && all.push(d)));
        const min = new Date(Math.min(...all));
        const max = new Date(Math.max(...all));
        const rangeStart = new Date(min.getFullYear(), min.getMonth(), 1);
        const rangeEnd = new Date(max.getFullYear(), max.getMonth() + 1, 1);
        const span = Math.max(rangeEnd - rangeStart, DAY_MS);
        const labelWidth = Math.min(MAX_LABEL_WIDTH, Math.round(this.width * 0.35));
        const chartLeft = labelWidth + 10;
        const chartRight = this.width - RIGHT_PAD;
        const labelChars = Math.max(Math.floor(labelWidth / 7), 12);
        const x = (d) => chartLeft + ((d - rangeStart) / span) * (chartRight - chartLeft);

        // Group rows, keeping the incoming order within each group.
        const groupOrder = [];
        const byGroup = new Map();
        items.forEach((i) => {
            const key = i.group || 'Other';
            if (!byGroup.has(key)) {
                byGroup.set(key, []);
                groupOrder.push(key);
            }
            byGroup.get(key).push(i);
        });

        const rows = [];
        const groups = [];
        let y = AXIS_HEIGHT;
        groupOrder.forEach((key, gi) => {
            groups.push({ key: `g${gi}`, label: truncate(key, 60), y: y + 16, lineY: y + GROUP_HEIGHT - 2 });
            y += GROUP_HEIGHT;
            byGroup.get(key).forEach((i) => {
                const end = i.barEnd;
                const barX = Math.max(x(i.barStart), chartLeft);
                const barW = Math.max(x(end) - barX, 4);
                const healthClass = HEALTH_CLASS[i.health] || NEUTRAL_CLASS;
                const barY = y + (ROW_HEIGHT - BAR_HEIGHT) / 2;
                const slips = i.f && i.f > end;
                const fx = i.f ? x(i.f) : null;
                const cy = y + ROW_HEIGHT / 2;
                rows.push({
                    key: i.id,
                    id: i.id,
                    labelY: y + 16,
                    label: truncate(i.label, labelChars),
                    barX,
                    barY,
                    barW,
                    barClass: `bar ${healthClass}`,
                    hasForecast: !!i.f,
                    slips,
                    slipX1: x(end),
                    slipX2: fx,
                    slipY: cy,
                    diamond: fx === null ? '' : `${fx},${cy - 6} ${fx + 6},${cy} ${fx},${cy + 6} ${fx - 6},${cy}`,
                    diamondClass: `diamond ${slips ? HEALTH_CLASS.Red : healthClass}`,
                    hitY: y,
                    tooltip: [i.label, i.status, i.detail].filter(Boolean).join(' · ')
                });
                y += ROW_HEIGHT;
            });
        });

        // Month ticks (every month, or every third month on long ranges).
        const ticks = [];
        const months = (rangeEnd.getFullYear() - rangeStart.getFullYear()) * 12 + rangeEnd.getMonth() - rangeStart.getMonth();
        const step = months > 18 ? 3 : 1;
        for (let m = 0; m <= months; m += step) {
            const d = new Date(rangeStart.getFullYear(), rangeStart.getMonth() + m, 1);
            ticks.push({
                key: `t${m}`,
                x: x(d),
                labelX: x(d) + 3,
                label: `${MONTHS[d.getMonth()]} ${String(d.getFullYear()).substring(2)}`,
                bottom: y
            });
        }

        return {
            rows,
            groups,
            ticks,
            height: y + 8,
            todayX: x(today),
            todayBottom: y
        };
    }

    get rows() {
        return this.layout.rows;
    }
    get groups() {
        return this.layout.groups;
    }
    get ticks() {
        return this.layout.ticks;
    }
    get todayX() {
        return this.layout.todayX;
    }
    get todayBottom() {
        return this.layout.todayBottom;
    }
    get chartRight() {
        return this.width - RIGHT_PAD;
    }

    renderedCallback() {
        if (this.resizeObserver) return;
        const host = this.template.querySelector('.timeline-host');
        if (!host || typeof ResizeObserver === 'undefined') return;
        this.resizeObserver = new ResizeObserver((entries) => {
            const measured = Math.floor(entries[0].contentRect.width);
            // Ignore tiny changes (scrollbars appearing) to avoid redraw loops.
            if (measured > 0 && Math.abs(measured - this.width) > 2) {
                this.width = measured;
                this.layout = this.computeLayout(this._items);
            }
        });
        this.resizeObserver.observe(host);
    }

    disconnectedCallback() {
        if (this.resizeObserver) {
            this.resizeObserver.disconnect();
            this.resizeObserver = undefined;
        }
    }
    get labelX() {
        return 12;
    }
    get groupLabelX() {
        return 4;
    }

    handleRowClick(event) {
        const recordId = event.currentTarget.dataset.id;
        if (!recordId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, actionName: 'view' }
        });
    }
}
