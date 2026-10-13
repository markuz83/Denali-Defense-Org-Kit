import { LightningElement, api, wire } from 'lwc';
import getTeam from '@salesforce/apex/AccountCommandCenterController.getTeam';
import { pct, reduceError } from 'c/accountSectionUtils';

const COLUMNS = [
    { type: 'text', fieldName: 'employee', label: 'Employee' },
    { type: 'text', fieldName: 'project', label: 'Project', wrapText: true },
    { type: 'text', fieldName: 'role', label: 'Role' },
    { type: 'percent', fieldName: 'allocation', label: 'Allocation', typeAttributes: { maximumFractionDigits: 0 } },
    { type: 'text', fieldName: 'status', label: 'Status' }
];

/**
 * Who's working on an account's projects (everyone not rolled off), for an Account record page.
 */
export default class AccountTeam extends LightningElement {
    @api recordId;
    columns = COLUMNS;
    rows = [];
    loaded = false;
    error;

    @wire(getTeam, { accountId: '$recordId' })
    wired(result) {
        if (result.data) {
            this.rows = result.data.map((t) => ({
                id: t.Id,
                employee: t.Employee__r?.Name,
                project: t.Project__r?.Name,
                role: t.Role__c,
                allocation: pct(t.Allocation__c),
                status: t.Resource_Status__c
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
