/**
 * Backs the Contract Health LWC: funding and recognition, margin at award vs forecast, the
 * next option decision, and what's at risk underneath (projects, deliverables, risks, cases).
 * Deliverable and risk figures are computed live; Revenue Recognized, Revenue Allocation and
 * Forecast Cost on the Contract are rollups (03_recalculate_rollups.apex).
 */
public with sharing class ContractHealthController {

    private static final Set<String> CLOSED_RISK = new Set<String>{ 'Closed', 'Realized' };

    public class Health {
        @AuraEnabled public Contract contract;
        @AuraEnabled public List<Project__c> projects;
        @AuraEnabled public Integer deliverables = 0;
        @AuraEnabled public Integer deliverablesComplete = 0;
        @AuraEnabled public Integer deliverablesAtRisk = 0;
        @AuraEnabled public Integer deliverablesOverdue = 0;
        @AuraEnabled public Decimal revenueAtRisk = 0;
        @AuraEnabled public Decimal revenueAwaitingAcceptance = 0;
        @AuraEnabled public Integer openRisks = 0;
        @AuraEnabled public Integer highRisks = 0;
        @AuraEnabled public Integer openCases = 0;
    }

    @AuraEnabled(cacheable=true)
    public static Health getHealth(Id contractId) {
        List<Contract> ks = [
            SELECT Id, ContractNumber, Award_Number__c, Status, StartDate, EndDate, Contract_Type__c,
                   Contract_Value__c, Funded_Value__c, Revenue_Recognized__c, Total_Backlog__c, Funded_Backlog__c,
                   Percent_Funded__c, Original_Margin__c, Current_Margin__c, Margin_Variance__c,
                   Revenue_Allocation__c, Forecast_Cost__c, Actual_Cost__c, Contract_Health__c,
                   Current_Period__c, Next_Option_Date__c, Program_Manager__r.Name
            FROM Contract WHERE Id = :contractId WITH USER_MODE
        ];
        if (ks.isEmpty()) {
            return null;
        }
        Health h = new Health();
        h.contract = ks[0];
        h.projects = [
            SELECT Id, Name, Status__c, Health__c, Percent_Complete__c, Forecast_Margin__c, Margin_Erosion__c,
                   Project_Manager__r.Name
            FROM Project__c WHERE Contract__c = :contractId WITH USER_MODE ORDER BY Start_Date__c
        ];
        for (Deliverable__c d : [
            SELECT Status__c, Is_At_Risk__c, Is_Overdue__c, Acceptance_Status__c, Revenue_Milestone__c
            FROM Deliverable__c WHERE Project__r.Contract__c = :contractId WITH USER_MODE
        ]) {
            h.deliverables++;
            if (d.Status__c == 'Complete') h.deliverablesComplete++;
            if (d.Is_At_Risk__c) { h.deliverablesAtRisk++; h.revenueAtRisk += nz(d.Revenue_Milestone__c); }
            if (d.Is_Overdue__c) h.deliverablesOverdue++;
            if (d.Acceptance_Status__c != 'Accepted' && d.Status__c != 'Cancelled') h.revenueAwaitingAcceptance += nz(d.Revenue_Milestone__c);
        }
        for (Risk__c r : [
            SELECT Severity__c FROM Risk__c WHERE Contract__c = :contractId AND Status__c NOT IN :CLOSED_RISK WITH USER_MODE
        ]) {
            h.openRisks++;
            if (r.Severity__c == 'High' || r.Severity__c == 'Critical') h.highRisks++;
        }
        h.openCases = [
            SELECT COUNT() FROM Case
            WHERE IsClosed = false AND (Project__r.Contract__c = :contractId OR Service_Engagement__r.Contract__c = :contractId)
            WITH USER_MODE
        ];
        return h;
    }

    private static Decimal nz(Decimal v) {
        return v == null ? 0 : v;
    }
}
