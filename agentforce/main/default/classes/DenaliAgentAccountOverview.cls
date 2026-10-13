/**
 * Agent action: one account's health, from the same data as the Account Command Center.
 */
public with sharing class DenaliAgentAccountOverview {

    public class Request {
        @InvocableVariable(label='Account Name' description='Full or partial account name, such as Northwind' required=true)
        public String accountName;
    }

    public class Result {
        @InvocableVariable(label='Account Overview' description='The account\'s KPIs, at-risk deliverables, open risks, open cases and projects as JSON, or a message asking which account was meant')
        public String result;
    }

    @InvocableMethod(
        label='Denali: Get Account Overview'
        description='Gets one account\'s health: KPIs, at-risk deliverables and the revenue at stake, open risks, open cases and projects. Use for questions about a single named account.'
        category='Denali Assistant')
    public static List<Result> run(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Result r = new Result();
            DenaliAgentSupport.Match m = DenaliAgentSupport.findByName('Account', 'Id, Name', req.accountName, 'account');
            r.result = m.record == null ? m.message : DenaliAgentSupport.toJson(overview(m.record.Id));
            results.add(r);
        }
        return results;
    }

    private static Map<String, Object> overview(Id accountId) {
        AccountCommandCenterController.CommandCenterData d = AccountCommandCenterController.getData(accountId);
        List<Map<String, Object>> atRisk = new List<Map<String, Object>>();
        for (Deliverable__c del : d.deliverables) {
            if (del.Is_At_Risk__c) {
                atRisk.add(new Map<String, Object>{
                    'name' => del.Name, 'project' => projectName(d, del.Project__c), 'status' => del.Status__c,
                    'health' => del.Health__c, 'percentComplete' => del.Percent_Complete__c, 'dueDate' => del.Due_Date__c,
                    'forecastDate' => del.Forecast_Completion_Date__c, 'daysLate' => del.Schedule_Variance_Days__c,
                    'revenueMilestone' => del.Revenue_Milestone__c, 'supplier' => del.Supplier__r?.Name,
                    'url' => DenaliAgentSupport.recordUrl(del.Id)
                });
            }
        }
        List<Map<String, Object>> risks = new List<Map<String, Object>>();
        for (Risk__c rk : d.risks) {
            if (risks.size() == 5) break;
            risks.add(new Map<String, Object>{
                'name' => rk.Name, 'score' => rk.Risk_Score__c, 'severity' => rk.Severity__c, 'status' => rk.Status__c,
                'owner' => rk.Risk_Owner__r?.Name, 'revenueAtRisk' => rk.Revenue_at_Risk__c,
                'url' => DenaliAgentSupport.recordUrl(rk.Id)
            });
        }
        List<Map<String, Object>> cases = new List<Map<String, Object>>();
        for (Case c : d.cases) {
            cases.add(new Map<String, Object>{
                'caseNumber' => c.CaseNumber, 'subject' => c.Subject, 'status' => c.Status, 'severity' => c.Severity__c,
                'escalated' => c.IsEscalated, 'deliverable' => c.Deliverable__r?.Name, 'url' => DenaliAgentSupport.recordUrl(c.Id)
            });
        }
        List<Map<String, Object>> projects = new List<Map<String, Object>>();
        for (Project__c p : d.projects) {
            projects.add(new Map<String, Object>{
                'name' => p.Name, 'status' => p.Status__c, 'health' => p.Health__c, 'percentComplete' => p.Percent_Complete__c,
                'forecastMargin' => p.Forecast_Margin__c, 'marginErosion' => p.Margin_Erosion__c,
                'projectManager' => p.Project_Manager__r?.Name, 'url' => DenaliAgentSupport.recordUrl(p.Id)
            });
        }
        return new Map<String, Object>{
            'account' => new Map<String, Object>{
                'name' => d.account.Name, 'role' => d.account.Account_Role__c, 'tier' => d.account.Customer_Tier__c,
                'customerHealth' => d.account.Customer_Health__c, 'owner' => d.account.Owner?.Name,
                'url' => DenaliAgentSupport.recordUrl(d.account.Id)
            },
            'kpis' => d.kpis,
            'atRiskDeliverables' => atRisk,
            'topOpenRisks' => risks,
            'openCases' => cases,
            'projects' => projects,
            'updatesAwaitingReview' => d.updatesAwaitingReview.size()
        };
    }

    private static String projectName(AccountCommandCenterController.CommandCenterData d, Id projectId) {
        for (Project__c p : d.projects) {
            if (p.Id == projectId) return p.Name;
        }
        return null;
    }
}
