import LightningDatatable from 'lightning/datatable';
import healthCell from './healthCell.html';
import scoreCell from './scoreCell.html';

// lightning-datatable with two custom column types:
// - "health": an SLDS success/warning/error icon instead of the word Green/Yellow/Red. Use it on a
//   column whose value is the raw picklist value.
// - "score": the value after an SLDS score dynamic icon. typeAttributes: option ('positive' or
//   'negative') and label (the icon's alternative text), usually from fieldName.
export default class HealthDatatable extends LightningDatatable {
    static customTypes = {
        health: {
            template: healthCell,
            standardCellLayout: true
        },
        score: {
            template: scoreCell,
            standardCellLayout: true,
            typeAttributes: ['option', 'label']
        }
    };
}
