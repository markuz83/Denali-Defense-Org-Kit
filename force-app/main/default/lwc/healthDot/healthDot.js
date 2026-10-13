import { LightningElement, api } from 'lwc';

// SLDS utility icons with the semantic feedback colours: the shape carries the meaning too, so
// health doesn't rely on colour alone.
const ICONS = {
    Green: { name: 'utility:success', variant: 'success' },
    Yellow: { name: 'utility:warning', variant: 'warning' },
    Red: { name: 'utility:error', variant: 'error' }
};

// An icon for a Green/Yellow/Red health value. A blank value keeps the icon's space so rows
// stay aligned; any other value shows as plain text.
export default class HealthDot extends LightningElement {
    @api value;
    @api size = 'x-small';

    get icon() {
        return ICONS[this.value];
    }

    get isBlank() {
        return this.value === null || this.value === undefined || this.value === '';
    }

    get label() {
        return `Health: ${this.value}`;
    }
}
