import { LightningElement, api, wire } from 'lwc';
import getSuppliers from '@salesforce/apex/AccountCommandCenterController.getSuppliers';
import { url, reduceError } from 'c/accountSectionUtils';

const COLUMNS = [
    { type: 'url', fieldName: 'url', label: 'Supplier', typeAttributes: { label: { fieldName: 'name' } } },
    { type: 'text', fieldName: 'project', label: 'Project', wrapText: true },
    { type: 'text', fieldName: 'role', label: 'Role' },
    { type: 'text', fieldName: 'status', label: 'Status' },
    { type: 'text', fieldName: 'rating', label: 'Rating' },
    { type: 'currency', fieldName: 'value', label: 'Value', typeAttributes: { maximumFractionDigits: 0 } }
];

/**
 * Suppliers assigned to an account's projects, for an Account record page.
 */
export default class AccountSuppliers extends LightningElement {
    @api recordId;
    columns = COLUMNS;
    rows = [];
    loaded = false;
    error;

    @wire(getSuppliers, { accountId: '$recordId' })
    wired(result) {
        if (result.data) {
            this.rows = result.data.map((s) => ({
                id: s.Id,
                url: url(s.Supplier__c),
                name: s.Supplier__r?.Name,
                project: s.Project__r?.Name,
                role: s.Primary_Supplier__c ? `${s.Role__c} (primary)` : s.Role__c,
                status: s.Status__c,
                rating: s.Performance_Rating__c,
                value: s.Contract_Value__c
            }));
            this.error = undefined;
            this.loaded = true;
        } else if (result.error) {
            this.error = reduceError(result.error);
            this.rows = [];
            this.loaded = true;
        }
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get isEmpty() {
        return this.loaded && !this.rows.length;
    }
}
