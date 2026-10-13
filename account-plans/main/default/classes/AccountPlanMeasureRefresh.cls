/**
 * Recalculates the Sales Account Plan measures linked to opportunities that changed.
 *
 * Salesforce calculates a measure's Current Value when an opportunity is linked to it, not when the
 * opportunity later changes. So when a linked deal is won, lost or repriced, this re-saves its links
 * (delete and re-insert), which makes Salesforce recalculate. Called by the
 * "Opportunity Refresh Account Plan Measures" flow.
 */
public without sharing class AccountPlanMeasureRefresh {

    public class Request {
        @InvocableVariable(label='Opportunity ID' description='An opportunity whose stage or amount changed' required=true)
        public Id opportunityId;
    }

    @InvocableMethod(
        label='Refresh Account Plan Measures'
        description='Recalculates account plan measures linked to these opportunities.'
        category='Denali')
    public static void refreshFromFlow(List<Request> requests) {
        Set<Id> ids = new Set<Id>();
        for (Request r : requests) ids.add(r.opportunityId);
        refresh(ids);
    }

    public static Integer refresh(Set<Id> opportunityIds) {
        List<AccountPlanObjMeasRela> links = [
            SELECT Id, AccountPlanObjectiveMeasureId, ReferenceRecordId
            FROM AccountPlanObjMeasRela WHERE ReferenceRecordId IN :opportunityIds
        ];
        List<AccountPlanObjMeasRela> again = new List<AccountPlanObjMeasRela>();
        for (AccountPlanObjMeasRela l : links) {
            again.add(new AccountPlanObjMeasRela(AccountPlanObjectiveMeasureId = l.AccountPlanObjectiveMeasureId,
                ReferenceRecordId = l.ReferenceRecordId));
        }
        delete links;
        insert again;
        return again.size();
    }
}
