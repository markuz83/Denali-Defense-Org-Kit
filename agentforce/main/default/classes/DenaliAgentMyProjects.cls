/**
 * Agent action: the current user's active projects and their delivery status, from the same data
 * as the My Projects component on Delivery Home (projects where the user is Project Manager).
 */
public with sharing class DenaliAgentMyProjects {

    public class Request {
        @InvocableVariable(label='Project Name' description='Optional full or partial project name, to show one project only')
        public String projectName;
    }

    public class Result {
        @InvocableVariable(label='My Projects' description='The user\'s active projects with delivery health, deliverables due in 30 days, supplier updates to review and open risks, as JSON')
        public String result;
    }

    @InvocableMethod(
        label='Denali: Get My Projects'
        description='Gets the current user\'s active projects (where they are Project Manager) with delivery health, at-risk and overdue deliverables, deliverables due in the next 30 days, supplier updates waiting on review, and open risks. Use for questions about "my projects" or "my work".'
        category='Denali Assistant')
    public static List<Result> run(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Result r = new Result();
            r.result = DenaliAgentSupport.toJson(myWork(req?.projectName));
            results.add(r);
        }
        return results;
    }

    private static Map<String, Object> myWork(String projectName) {
        String wanted = projectName == null ? '' : projectName.trim().toLowerCase();
        MyProjectsController.MyWork w = MyProjectsController.getMyWork();

        Set<Id> shown = new Set<Id>();
        List<Map<String, Object>> projects = new List<Map<String, Object>>();
        for (MyProjectsController.ProjectSummary s : w.projects) {
            Project__c p = s.project;
            if (String.isNotBlank(wanted) && !p.Name.toLowerCase().contains(wanted)) continue;
            shown.add(p.Id);
            projects.add(new Map<String, Object>{
                'name' => p.Name, 'account' => p.Account__r?.Name, 'status' => p.Status__c, 'health' => p.Health__c,
                'riskLevel' => p.Risk_Level__c, 'percentComplete' => p.Percent_Complete__c, 'targetEndDate' => p.Target_End_Date__c,
                'forecastMargin' => p.Forecast_Margin__c, 'marginErosion' => p.Margin_Erosion__c,
                'deliverables' => s.deliverables, 'complete' => s.complete, 'atRisk' => s.atRisk, 'overdue' => s.overdue,
                'dueIn30Days' => s.dueSoon, 'updatesToReview' => s.updatesToReview, 'revenueAtRisk' => s.revenueAtRisk,
                'url' => DenaliAgentSupport.recordUrl(p.Id)
            });
        }

        List<Map<String, Object>> dueSoon = new List<Map<String, Object>>();
        for (Deliverable__c d : w.dueSoon) {
            if (!shown.contains(d.Project__c)) continue;
            dueSoon.add(new Map<String, Object>{
                'name' => d.Name, 'project' => d.Project__r?.Name, 'status' => d.Status__c, 'health' => d.Health__c,
                'dueDate' => d.Due_Date__c, 'forecastDate' => d.Forecast_Completion_Date__c,
                'percentComplete' => d.Percent_Complete__c, 'atRisk' => d.Is_At_Risk__c, 'overdue' => d.Is_Overdue__c,
                'revenueMilestone' => d.Revenue_Milestone__c, 'supplier' => d.Supplier__r?.Name,
                'url' => DenaliAgentSupport.recordUrl(d.Id)
            });
        }
        List<Map<String, Object>> updates = new List<Map<String, Object>>();
        for (Deliverable_Update__c u : w.updatesToReview) {
            if (!shown.contains(u.Deliverable__r?.Project__c)) continue;
            updates.add(new Map<String, Object>{
                'name' => u.Name, 'deliverable' => u.Deliverable__r?.Name, 'supplier' => u.Supplier__r?.Name,
                'submitted' => u.Submitted_Date__c, 'reportedStatus' => u.Reported_Status__c,
                'percentComplete' => u.Percent_Complete__c, 'supplierHealth' => u.Supplier_Health__c,
                'reviewStatus' => u.Internal_Review_Status__c, 'url' => DenaliAgentSupport.recordUrl(u.Id)
            });
        }
        List<Map<String, Object>> risks = new List<Map<String, Object>>();
        for (Risk__c rk : w.risks) {
            risks.add(new Map<String, Object>{
                'name' => rk.Name, 'severity' => rk.Severity__c, 'score' => rk.Risk_Score__c, 'status' => rk.Status__c,
                'project' => rk.Project__r?.Name, 'deliverable' => rk.Deliverable__r?.Name,
                'targetResolutionDate' => rk.Target_Resolution_Date__c, 'url' => DenaliAgentSupport.recordUrl(rk.Id)
            });
        }

        Map<String, Object> result = new Map<String, Object>{
            'activeProjects' => projects,
            'deliverablesDueIn30Days' => dueSoon,
            'supplierUpdatesToReview' => updates,
            'openRisks' => risks
        };
        if (projects.isEmpty()) {
            result.put('note', String.isBlank(wanted)
                ? 'The user is not Project Manager on any active project.'
                : 'None of the user\'s active projects matches \'' + projectName.trim() + '\'.');
        }
        return result;
    }
}
