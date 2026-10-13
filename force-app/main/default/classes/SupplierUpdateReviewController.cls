/**
 * Backs the Supplier Update Review LWC on the Deliverable page: the deliverable's supplier
 * updates (newest first) and an inline review decision. Setting Internal Review Status fires
 * the existing automation: Review Stamp (#7) stamps the reviewer, and Update Review (#6)
 * applies an Accepted update to the Deliverable or emails the submitter on a bounce.
 */
public with sharing class SupplierUpdateReviewController {

    private static final Set<String> DECISIONS = new Set<String>{ 'Under Review', 'Accepted', 'Needs Clarification', 'Rejected' };
    private static final Set<String> NEEDS_COMMENTS = new Set<String>{ 'Needs Clarification', 'Rejected' };

    public class Review {
        @AuraEnabled public Deliverable__c deliverable;
        @AuraEnabled public List<Deliverable_Update__c> updates;
    }

    @AuraEnabled(cacheable=true)
    public static Review getReview(Id deliverableId) {
        List<Deliverable__c> ds = [
            SELECT Id, Name, Status__c, Health__c, Percent_Complete__c, Due_Date__c, Forecast_Completion_Date__c,
                   Latest_Update_Date__c, Supplier__r.Name
            FROM Deliverable__c WHERE Id = :deliverableId WITH USER_MODE
        ];
        if (ds.isEmpty()) {
            return null;
        }
        Review r = new Review();
        r.deliverable = ds[0];
        r.updates = [
            SELECT Id, Name, Submitted_Date__c, Submitted_By__r.Name, Supplier__r.Name, Reported_Status__c,
                   Percent_Complete__c, Forecast_Completion_Date__c, Supplier_Health__c, Progress_Summary__c,
                   Blockers__c, Next_Steps__c, Requires_Customer_Action__c, Customer_Action__c,
                   Internal_Review_Status__c, Reviewer_Comments__c, Reviewed_By__r.Name, Review_Date__c
            FROM Deliverable_Update__c
            WHERE Deliverable__c = :deliverableId
            WITH USER_MODE
            ORDER BY Submitted_Date__c DESC NULLS LAST, CreatedDate DESC
        ];
        return r;
    }

    @AuraEnabled
    public static void review(Id updateId, String decision, String comments) {
        if (!DECISIONS.contains(decision)) {
            throw new AuraHandledException('Unknown review decision: ' + decision);
        }
        if (NEEDS_COMMENTS.contains(decision) && String.isBlank(comments)) {
            throw new AuraHandledException('Tell the supplier what needs to change.');
        }
        Deliverable_Update__c u = new Deliverable_Update__c(Id = updateId, Internal_Review_Status__c = decision);
        if (String.isNotBlank(comments)) {
            u.Reviewer_Comments__c = comments;
        }
        try {
            update as user u;
        } catch (DmlException e) {
            // e.g. an already-accepted update is locked, or a Deliverable validation rule blocks applying it.
            throw new AuraHandledException(e.getDmlMessage(0));
        }
    }
}
