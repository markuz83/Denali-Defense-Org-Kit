/**
 * Backs the Pricing Approvals LWC: Margin Exception approval requests assigned to the current
 * user, with the pricing facts a reviewer needs, and approve/reject. Other approvals waiting on
 * the user (Knowledge articles, say) are left to the standard Items to Approve list.
 */
public with sharing class PricingApprovalsController {

    private static final String MARGIN_EXCEPTION = 'Margin_Exception';

    public class ApprovalItem {
        @AuraEnabled public Id workitemId;
        @AuraEnabled public Id recordId;
        @AuraEnabled public String recordName;
        @AuraEnabled public String objectType;
        @AuraEnabled public String submittedBy;
        @AuraEnabled public Datetime submittedDate;
        @AuraEnabled public Opportunity opportunity;   // set when the record is an Opportunity
    }

    @AuraEnabled(cacheable=true)
    public static List<ApprovalItem> getMyApprovals() {
        List<ProcessInstanceWorkitem> items = [
            SELECT Id, CreatedDate, ProcessInstance.TargetObjectId, ProcessInstance.TargetObject.Name,
                   ProcessInstance.TargetObject.Type, ProcessInstance.SubmittedBy.Name
            FROM ProcessInstanceWorkitem
            WHERE ActorId = :UserInfo.getUserId()
              AND ProcessInstance.ProcessDefinition.DeveloperName = :MARGIN_EXCEPTION
            ORDER BY CreatedDate
        ];
        Set<Id> oppIds = new Set<Id>();
        for (ProcessInstanceWorkitem w : items) {
            if (w.ProcessInstance.TargetObject.Type == 'Opportunity') oppIds.add(w.ProcessInstance.TargetObjectId);
        }
        Map<Id, Opportunity> opps = new Map<Id, Opportunity>([
            SELECT Id, Name, Account.Name, Amount, StageName, CloseDate, Contract_Type__c, Acquisition_Type__c,
                   Estimated_Margin__c, Margin_Floor__c, Margin_Shortfall__c, Estimated_Contract_Value__c,
                   Pricing_Rationale__c, Incumbent__r.Name, Incumbent__r.Deals_Lost_To__c, Incumbent__r.Bookings_Lost_To__c
            FROM Opportunity WHERE Id IN :oppIds WITH USER_MODE
        ]);

        List<ApprovalItem> result = new List<ApprovalItem>();
        for (ProcessInstanceWorkitem w : items) {
            ApprovalItem a = new ApprovalItem();
            a.workitemId = w.Id;
            a.recordId = w.ProcessInstance.TargetObjectId;
            a.recordName = w.ProcessInstance.TargetObject.Name;
            a.objectType = w.ProcessInstance.TargetObject.Type;
            a.submittedBy = w.ProcessInstance.SubmittedBy.Name;
            a.submittedDate = w.CreatedDate;
            a.opportunity = opps.get(a.recordId);
            result.add(a);
        }
        return result;
    }

    /** action is 'Approve' or 'Reject'. */
    @AuraEnabled
    public static void decide(Id workitemId, String action, String comments) {
        if (action != 'Approve' && action != 'Reject') {
            throw new AuraHandledException('Unknown action: ' + action);
        }
        Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
        req.setWorkitemId(workitemId);
        req.setAction(action);
        req.setComments(comments);
        try {
            Approval.ProcessResult result = Approval.process(req);
            if (!result.isSuccess()) {
                throw new AuraHandledException(String.valueOf(result.getErrors()));
            }
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        }
    }
}
