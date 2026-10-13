/**
 * Agent action: a deliverable's status and supplier updates, from the same data as the
 * Supplier Update Review component, plus the % complete trend.
 */
public with sharing class DenaliAgentDeliverableStatus {

    public class Request {
        @InvocableVariable(label='Deliverable Name' description='Full or partial deliverable name, such as Sensor Fusion' required=true)
        public String deliverableName;
    }

    public class Result {
        @InvocableVariable(label='Deliverable Status' description='The deliverable, its supplier updates newest first, and the % complete trend as JSON, or a message asking which deliverable was meant')
        public String result;
    }

    @InvocableMethod(
        label='Denali: Get Deliverable Status'
        description='Gets a deliverable\'s status with its supplier updates, the % complete trend, and whether progress has stalled. Use for questions about a named deliverable.'
        category='Denali Assistant')
    public static List<Result> run(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Result r = new Result();
            DenaliAgentSupport.Match m = DenaliAgentSupport.findByName(
                'Deliverable__c',
                'Id, Name, Project__r.Name, Account__r.Name, Risk_Level__c, Revenue_Milestone__c, Revenue_at_Risk__c, '
                    + 'Schedule_Variance_Days__c, Blocker_Description__c',
                req.deliverableName, 'deliverable');
            r.result = m.record == null ? m.message : DenaliAgentSupport.toJson(status((Deliverable__c) m.record));
            results.add(r);
        }
        return results;
    }

    private static Map<String, Object> status(Deliverable__c found) {
        SupplierUpdateReviewController.Review review = SupplierUpdateReviewController.getReview(found.Id);
        Deliverable__c d = review.deliverable;
        List<Map<String, Object>> updates = new List<Map<String, Object>>();
        List<Decimal> newestFirst = new List<Decimal>();
        for (Deliverable_Update__c u : review.updates) {
            if (updates.size() == 10) break;
            newestFirst.add(u.Percent_Complete__c);
            updates.add(new Map<String, Object>{
                'name' => u.Name, 'submitted' => u.Submitted_Date__c, 'supplier' => u.Supplier__r?.Name,
                'reportedStatus' => u.Reported_Status__c, 'percentComplete' => u.Percent_Complete__c,
                'forecastDate' => u.Forecast_Completion_Date__c, 'supplierHealth' => u.Supplier_Health__c,
                'progressSummary' => u.Progress_Summary__c, 'blockers' => u.Blockers__c,
                'reviewStatus' => u.Internal_Review_Status__c, 'reviewerComments' => u.Reviewer_Comments__c,
                'url' => DenaliAgentSupport.recordUrl(u.Id)
            });
        }
        List<Decimal> trend = new List<Decimal>();   // oldest first
        for (Integer i = newestFirst.size() - 1; i >= 0; i--) {
            trend.add(newestFirst[i]);
        }
        Integer n = trend.size();
        return new Map<String, Object>{
            'deliverable' => new Map<String, Object>{
                'name' => d.Name, 'project' => found.Project__r?.Name, 'account' => found.Account__r?.Name,
                'status' => d.Status__c, 'health' => d.Health__c, 'riskLevel' => found.Risk_Level__c,
                'percentComplete' => d.Percent_Complete__c, 'dueDate' => d.Due_Date__c,
                'forecastDate' => d.Forecast_Completion_Date__c, 'daysLate' => found.Schedule_Variance_Days__c,
                'revenueMilestone' => found.Revenue_Milestone__c, 'revenueAtRisk' => found.Revenue_at_Risk__c,
                'blocker' => found.Blocker_Description__c, 'supplier' => d.Supplier__r?.Name,
                'url' => DenaliAgentSupport.recordUrl(d.Id)
            },
            'percentCompleteTrendOldestFirst' => trend,
            'noProgressSinceLastUpdate' => n >= 2 && trend[n - 1] == trend[n - 2],
            'supplierUpdatesNewestFirst' => updates
        };
    }
}
