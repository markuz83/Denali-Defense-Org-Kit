/**
 * Backs the Project Timeline LWC: a project's deliverables with the dates, health, and
 * revenue the timeline draws. Runs in user mode, so sharing and field-level security apply.
 */
public with sharing class ProjectTimelineController {

    @AuraEnabled(cacheable=true)
    public static List<Deliverable__c> getDeliverables(Id projectId) {
        return [
            SELECT Id, Name, Status__c, Health__c, Planned_Start_Date__c, Due_Date__c, Forecast_Completion_Date__c,
                   Revenue_Milestone__c, Is_At_Risk__c, Supplier__r.Name
            FROM Deliverable__c
            WHERE Project__c = :projectId AND Status__c != 'Cancelled'
            WITH USER_MODE
            ORDER BY Due_Date__c NULLS LAST
        ];
    }
}
