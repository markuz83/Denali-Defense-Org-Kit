/**
 * Agent action: the Margin Exception requests waiting on the current user, from the same data
 * as the Pricing Approvals component. The agent runs as the user, so "mine" needs no lookup.
 */
public with sharing class DenaliAgentPricingApprovals {

    public class Request {
        @InvocableVariable(label='Opportunity Name' description='Optional full or partial opportunity name, to show one request only')
        public String opportunityName;
    }

    public class Result {
        @InvocableVariable(label='Pricing Approvals' description='Pricing approval requests waiting on the user, with margin, floor, shortfall, incumbent and rationale, as JSON')
        public String result;
    }

    @InvocableMethod(
        label='Denali: Get My Pricing Approvals'
        description='Lists the Margin Exception approval requests waiting on the current user: opportunities priced below their margin floor, with margin, floor, shortfall, incumbent and pricing rationale.'
        category='Denali Assistant')
    public static List<Result> run(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Result r = new Result();
            r.result = DenaliAgentSupport.toJson(new Map<String, Object>{ 'pendingRequests' => pending(req?.opportunityName) });
            results.add(r);
        }
        return results;
    }

    private static List<Map<String, Object>> pending(String opportunityName) {
        String wanted = opportunityName == null ? '' : opportunityName.trim().toLowerCase();
        List<Map<String, Object>> requests = new List<Map<String, Object>>();
        for (PricingApprovalsController.ApprovalItem item : PricingApprovalsController.getMyApprovals()) {
            if (String.isNotBlank(wanted) && (item.recordName == null || !item.recordName.toLowerCase().contains(wanted))) {
                continue;
            }
            Opportunity o = item.opportunity;
            Map<String, Object> request = new Map<String, Object>{
                'opportunity' => item.recordName, 'submittedBy' => item.submittedBy, 'submitted' => item.submittedDate,
                'url' => DenaliAgentSupport.recordUrl(item.recordId)
            };
            if (o != null) {
                request.putAll(new Map<String, Object>{
                    'account' => o.Account?.Name, 'amount' => o.Amount, 'stage' => o.StageName, 'contractType' => o.Contract_Type__c,
                    'estimatedMargin' => o.Estimated_Margin__c, 'marginFloor' => o.Margin_Floor__c,
                    'marginShortfall' => o.Margin_Shortfall__c, 'pricingRationale' => o.Pricing_Rationale__c,
                    'incumbent' => o.Incumbent__r?.Name, 'dealsLostToIncumbent' => o.Incumbent__r?.Deals_Lost_To__c,
                    'bookingsLostToIncumbent' => o.Incumbent__r?.Bookings_Lost_To__c
                });
            }
            requests.add(request);
        }
        return requests;
    }
}
