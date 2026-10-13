/**
 * Backs the Impact Chain LWC on the Case page: what a service issue touches upstream —
 * the Deliverable, its Project and Contract, the revenue milestone at stake, and the open
 * risks already logged against them (Case Create Risk, flow #10, adds one for Sev 1/2).
 * A support case with no Deliverable or Project (on a managed service, say) follows its
 * Service Engagement to the Contract instead, and shows the contract's open risks.
 */
public with sharing class ImpactChainController {

    private static final Set<String> CLOSED_RISK = new Set<String>{ 'Closed', 'Realized' };
    private static final Integer MAX_RISKS = 5;

    public class Chain {
        @AuraEnabled public Case caseRecord;
        @AuraEnabled public Deliverable__c deliverable;
        @AuraEnabled public Project__c project;
        @AuraEnabled public Contract contract;
        @AuraEnabled public Service_Engagement__c serviceEngagement;
        @AuraEnabled public List<Risk__c> risks = new List<Risk__c>();
        @AuraEnabled public Decimal revenueAtStake;
    }

    @AuraEnabled(cacheable=true)
    public static Chain getChain(Id caseId) {
        List<Case> cs = [
            SELECT Id, CaseNumber, Subject, Status, Priority, Severity__c, Customer_Impact__c, IsEscalated,
                   Account.Name, Deliverable__c, Project__c, Service_Engagement__c
            FROM Case WHERE Id = :caseId WITH USER_MODE
        ];
        if (cs.isEmpty()) {
            return null;
        }
        Chain ch = new Chain();
        ch.caseRecord = cs[0];

        if (ch.caseRecord.Deliverable__c != null) {
            ch.deliverable = [
                SELECT Id, Name, Status__c, Health__c, Due_Date__c, Forecast_Completion_Date__c, Schedule_Variance_Days__c,
                       Percent_Complete__c, Is_At_Risk__c, Acceptance_Status__c, Revenue_Milestone__c, Project__c, Supplier__r.Name
                FROM Deliverable__c WHERE Id = :ch.caseRecord.Deliverable__c WITH USER_MODE
            ];
        }
        Id projectId = ch.deliverable != null ? ch.deliverable.Project__c : ch.caseRecord.Project__c;
        if (projectId != null) {
            ch.project = [
                SELECT Id, Name, Status__c, Health__c, Percent_Complete__c, Project_Manager__r.Name,
                       Forecast_Margin__c, Margin_Erosion__c, Contract__c
                FROM Project__c WHERE Id = :projectId WITH USER_MODE
            ];
            ch.contract = contract(ch.project.Contract__c);
        }
        if (ch.caseRecord.Service_Engagement__c != null) {
            ch.serviceEngagement = [
                SELECT Id, Name, Service_Type__c, Health__c, Service_Level__c, SLA_Breaches__c, Annual_Contract_Value__c,
                       Contract__c
                FROM Service_Engagement__c WHERE Id = :ch.caseRecord.Service_Engagement__c WITH USER_MODE
            ];
            if (ch.contract == null && ch.serviceEngagement.Contract__c != null) {
                ch.contract = contract(ch.serviceEngagement.Contract__c);
            }
        }

        if (ch.deliverable != null || projectId != null) {
            Id deliverableId = ch.deliverable?.Id;
            ch.risks = [
                SELECT Id, Name, Severity__c, Status__c, Risk_Category__c, Deliverable__r.Name, CreatedDate
                FROM Risk__c
                WHERE Status__c NOT IN :CLOSED_RISK
                  AND (Deliverable__c = :deliverableId OR (Project__c = :projectId AND Deliverable__c = null))
                WITH USER_MODE
                ORDER BY Risk_Score__c DESC NULLS LAST, CreatedDate DESC
                LIMIT :MAX_RISKS
            ];
        } else if (ch.contract != null) {
            ch.risks = [
                SELECT Id, Name, Severity__c, Status__c, Risk_Category__c, Deliverable__r.Name, CreatedDate
                FROM Risk__c
                WHERE Status__c NOT IN :CLOSED_RISK AND Contract__c = :ch.contract.Id
                WITH USER_MODE
                ORDER BY Risk_Score__c DESC NULLS LAST, CreatedDate DESC
                LIMIT :MAX_RISKS
            ];
        }
        if (ch.deliverable != null && ch.deliverable.Acceptance_Status__c != 'Accepted') {
            ch.revenueAtStake = ch.deliverable.Revenue_Milestone__c;
        }
        return ch;
    }

    private static Contract contract(Id contractId) {
        List<Contract> found = [
            SELECT Id, ContractNumber, Award_Number__c, Status, Contract_Value__c, Total_Backlog__c,
                   Next_Option_Date__c, Contract_Health__c
            FROM Contract WHERE Id = :contractId WITH USER_MODE
        ];
        return found.isEmpty() ? null : found[0];
    }
}
