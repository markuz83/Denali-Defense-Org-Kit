/**
 * Backs the My Projects LWC (Denali Delivery home): the current user's active projects with
 * their delivery health, supplier updates waiting on review, deliverables due in the next
 * 30 days, and open risks. Runs in user mode.
 */
public with sharing class MyProjectsController {

    private static final Set<String> DONE_PROJECT = new Set<String>{ 'Complete', 'Cancelled' };
    private static final Set<String> DONE_DELIVERABLE = new Set<String>{ 'Complete', 'Cancelled' };
    private static final Set<String> CLOSED_RISK = new Set<String>{ 'Closed', 'Realized' };
    private static final Set<String> PENDING_REVIEW = new Set<String>{ 'Pending', 'Under Review' };
    @TestVisible private static final Integer DUE_WINDOW_DAYS = 30;

    public class ProjectSummary {
        @AuraEnabled public Project__c project;
        @AuraEnabled public Integer deliverables = 0;
        @AuraEnabled public Integer complete = 0;
        @AuraEnabled public Integer atRisk = 0;
        @AuraEnabled public Integer overdue = 0;
        @AuraEnabled public Integer dueSoon = 0;
        @AuraEnabled public Integer updatesToReview = 0;
        @AuraEnabled public Decimal revenueAtRisk = 0;
    }

    public class MyWork {
        @AuraEnabled public List<ProjectSummary> projects = new List<ProjectSummary>();
        @AuraEnabled public List<Deliverable_Update__c> updatesToReview = new List<Deliverable_Update__c>();
        @AuraEnabled public List<Deliverable__c> dueSoon = new List<Deliverable__c>();
        @AuraEnabled public List<Risk__c> risks = new List<Risk__c>();
    }

    @AuraEnabled(cacheable=true)
    public static MyWork getMyWork() {
        Id me = UserInfo.getUserId();
        MyWork w = new MyWork();
        Map<Id, ProjectSummary> byId = new Map<Id, ProjectSummary>();
        for (Project__c p : [
            SELECT Id, Name, Account__r.Name, Contract__r.Award_Number__c, Status__c, Health__c, Risk_Level__c,
                   Percent_Complete__c, Target_End_Date__c, Forecast_Margin__c, Margin_Erosion__c
            FROM Project__c
            WHERE Project_Manager__c = :me AND Status__c NOT IN :DONE_PROJECT
            WITH USER_MODE
            ORDER BY Target_End_Date__c NULLS LAST
        ]) {
            ProjectSummary s = new ProjectSummary();
            s.project = p;
            byId.put(p.Id, s);
            w.projects.add(s);
        }
        Set<Id> projectIds = byId.keySet();
        Date dueBy = Date.today().addDays(DUE_WINDOW_DAYS);

        for (Deliverable__c d : [
            SELECT Id, Name, Project__c, Project__r.Name, Status__c, Health__c, Due_Date__c, Forecast_Completion_Date__c,
                   Percent_Complete__c, Is_At_Risk__c, Is_Overdue__c, Revenue_Milestone__c, Supplier__r.Name
            FROM Deliverable__c
            WHERE Project__c IN :projectIds
            WITH USER_MODE
            ORDER BY Due_Date__c NULLS LAST
        ]) {
            ProjectSummary s = byId.get(d.Project__c);
            s.deliverables++;
            if (d.Status__c == 'Complete') s.complete++;
            if (d.Is_At_Risk__c) { s.atRisk++; s.revenueAtRisk += d.Revenue_Milestone__c == null ? 0 : d.Revenue_Milestone__c; }
            if (d.Is_Overdue__c) s.overdue++;
            Boolean open = !DONE_DELIVERABLE.contains(d.Status__c);
            if (open && d.Due_Date__c != null && d.Due_Date__c <= dueBy) {
                s.dueSoon++;
                w.dueSoon.add(d);
            }
        }

        w.updatesToReview = [
            SELECT Id, Name, Deliverable__c, Deliverable__r.Name, Deliverable__r.Project__c, Supplier__r.Name,
                   Submitted_Date__c, Reported_Status__c, Percent_Complete__c, Supplier_Health__c, Internal_Review_Status__c,
                   Requires_Customer_Action__c
            FROM Deliverable_Update__c
            WHERE Deliverable__r.Project__c IN :projectIds AND Internal_Review_Status__c IN :PENDING_REVIEW
            WITH USER_MODE
            ORDER BY Submitted_Date__c
        ];
        for (Deliverable_Update__c u : w.updatesToReview) {
            byId.get(u.Deliverable__r.Project__c).updatesToReview++;
        }

        w.risks = [
            SELECT Id, Name, Severity__c, Status__c, Risk_Score__c, Project__r.Name, Deliverable__r.Name, Target_Resolution_Date__c
            FROM Risk__c
            WHERE Status__c NOT IN :CLOSED_RISK AND (Risk_Owner__c = :me OR Project__c IN :projectIds)
            WITH USER_MODE
            ORDER BY Risk_Score__c DESC NULLS LAST
            LIMIT 20
        ];
        return w;
    }
}
