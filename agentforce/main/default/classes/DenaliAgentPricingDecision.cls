/**
 * Agent action: approves or rejects a Margin Exception request waiting on the current user,
 * the same way the Pricing Approvals component does.
 */
public with sharing class DenaliAgentPricingDecision {

    public class Request {
        @InvocableVariable(label='Opportunity Name' description='Full or partial name of the opportunity whose pricing approval to decide' required=true)
        public String opportunityName;
        @InvocableVariable(label='Decision' description='Approve or Reject' required=true)
        public String decision;
        @InvocableVariable(label='Comments' description='The approver\'s comments, recorded in Approval History')
        public String comments;
    }

    public class Result {
        @InvocableVariable(label='Outcome' description='What happened, including the opportunity\'s new Margin Approval Status')
        public String result;
    }

    @InvocableMethod(
        label='Denali: Decide Pricing Approval'
        description='Approves or rejects a Margin Exception request that is waiting on the current user. Only use after the user has clearly said which deal and whether to approve or reject.'
        category='Denali Assistant')
    public static List<Result> run(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Result r = new Result();
            r.result = decide(req);
            results.add(r);
        }
        return results;
    }

    private static String decide(Request req) {
        String decision = req.decision == null ? '' : req.decision.trim().capitalize();
        if (decision != 'Approve' && decision != 'Reject') {
            return 'The decision must be Approve or Reject, not \'' + req.decision + '\'.';
        }
        String wanted = req.opportunityName == null ? '' : req.opportunityName.trim().toLowerCase();
        List<PricingApprovalsController.ApprovalItem> exact = new List<PricingApprovalsController.ApprovalItem>();
        List<PricingApprovalsController.ApprovalItem> partial = new List<PricingApprovalsController.ApprovalItem>();
        for (PricingApprovalsController.ApprovalItem item : PricingApprovalsController.getMyApprovals()) {
            String name = item.recordName == null ? '' : item.recordName.toLowerCase();
            if (name == wanted) exact.add(item);
            else if (String.isNotBlank(wanted) && name.contains(wanted)) partial.add(item);
        }
        List<PricingApprovalsController.ApprovalItem> matches = exact.isEmpty() ? partial : exact;
        if (matches.isEmpty()) {
            return 'No pricing approval waiting on you matches \'' + req.opportunityName + '\'.';
        }
        if (matches.size() > 1) {
            List<String> names = new List<String>();
            for (PricingApprovalsController.ApprovalItem item : matches) names.add(item.recordName);
            return 'Several approvals waiting on you match: ' + String.join(names, ', ') + '. Ask which one they mean.';
        }

        PricingApprovalsController.ApprovalItem item = matches[0];
        try {
            PricingApprovalsController.decide(item.workitemId, decision, req.comments);
        } catch (AuraHandledException e) {
            return 'Salesforce didn\'t accept the decision: ' + e.getMessage();
        }
        String status = [SELECT Margin_Approval_Status__c FROM Opportunity WHERE Id = :item.recordId WITH USER_MODE].Margin_Approval_Status__c;
        return (decision == 'Approve' ? 'Approved' : 'Rejected') + ' pricing for ' + item.recordName
            + '. Margin Approval Status is now ' + status + '. ' + DenaliAgentSupport.recordUrl(item.recordId);
    }
}
