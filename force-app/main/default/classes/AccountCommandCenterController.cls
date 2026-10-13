/**
 * Data for the Account Command Center LWC: everything happening on one account (contracts,
 * projects, deliverables, risks, service) in a single call. Supplier updates, suppliers and the
 * team have their own methods for their own components (accountSupplierUpdates, accountSuppliers,
 * accountTeam), which sit alongside the command center on the page.
 *
 * Queries run in user mode, so the viewer's sharing and field-level security apply. KPIs are
 * computed here from live records rather than read from the rollup fields that
 * 03_recalculate_rollups.apex maintains, so they're right even when the rollups are stale.
 * The one exception is backlog, which uses Contract.Total_Backlog__c (a formula over the
 * Revenue Recognized rollup).
 */
public with sharing class AccountCommandCenterController {

    private static final Set<String> CLOSED_RISK = new Set<String>{ 'Closed', 'Realized' };
    private static final Set<String> PENDING_REVIEW = new Set<String>{ 'Pending', 'Under Review' };

    public class Kpis {
        @AuraEnabled public Decimal activeContractValue = 0;
        @AuraEnabled public Decimal backlog = 0;
        @AuraEnabled public Decimal revenueAccepted = 0;
        @AuraEnabled public Decimal revenueAtRisk = 0;
        @AuraEnabled public Integer atRiskDeliverables = 0;
        @AuraEnabled public Integer overdueDeliverables = 0;
        @AuraEnabled public Integer openRisks = 0;
        @AuraEnabled public Integer highRisks = 0;
        @AuraEnabled public Integer openCases = 0;
        @AuraEnabled public Integer severeCases = 0;
        @AuraEnabled public Integer updatesAwaitingReview = 0;
    }

    public class CommandCenterData {
        @AuraEnabled public Account account;
        @AuraEnabled public Kpis kpis = new Kpis();
        @AuraEnabled public List<Contract> contracts;
        @AuraEnabled public List<Project__c> projects;
        @AuraEnabled public List<Deliverable__c> deliverables;
        @AuraEnabled public List<Risk__c> risks;
        @AuraEnabled public List<Case> cases;
        @AuraEnabled public List<Service_Engagement__c> serviceEngagements;
        @AuraEnabled public List<Deliverable_Update__c> updatesAwaitingReview;
    }

    @AuraEnabled(cacheable=true)
    public static CommandCenterData getData(Id accountId) {
        if (accountId == null) {
            return null;
        }
        try {
            return load(accountId);
        } catch (QueryException e) {
            // Most often a field the viewer can't see under user mode.
            throw new AuraHandledException('Unable to load the command center: ' + e.getMessage());
        }
    }

    public class PickerOption {
        @AuraEnabled public String label;
        @AuraEnabled public Id value;
    }

    /**
     * The app page's account list: active customers, each labelled with the award numbers of its
     * activated contracts ("Northwind Defense Agency - NDA-2026-001"). An account with no
     * activated contract shows just its name.
     */
    @AuraEnabled(cacheable=true)
    public static List<PickerOption> getPickerAccounts() {
        try {
            List<PickerOption> options = new List<PickerOption>();
            for (Account a : [
                SELECT Id, Name,
                       (SELECT Award_Number__c FROM Contracts
                        WHERE Status = 'Activated' AND Award_Number__c != null ORDER BY Award_Number__c)
                FROM Account
                WHERE Is_Customer__c = true AND Account_Status__c = 'Active' WITH USER_MODE
                ORDER BY Name LIMIT 500
            ]) {
                List<String> awards = new List<String>();
                for (Contract k : a.Contracts) {
                    awards.add(k.Award_Number__c);
                }
                PickerOption o = new PickerOption();
                o.label = awards.isEmpty() ? a.Name : a.Name + ' - ' + String.join(awards, ', ');
                o.value = a.Id;
                options.add(o);
            }
            return options;
        } catch (QueryException e) {
            throw new AuraHandledException('Unable to load accounts: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Deliverable_Update__c> getUpdatesAwaitingReview(Id accountId) {
        try {
            return accountId == null ? new List<Deliverable_Update__c>() : queryUpdatesAwaitingReview(accountId);
        } catch (QueryException e) {
            throw new AuraHandledException('Unable to load supplier updates: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Supplier_Assignment__c> getSuppliers(Id accountId) {
        if (accountId == null) {
            return new List<Supplier_Assignment__c>();
        }
        try {
            return [
                SELECT Id, Supplier__c, Supplier__r.Name, Project__r.Name, Role__c, Status__c,
                       Performance_Rating__c, Contract_Value__c, Primary_Supplier__c
                FROM Supplier_Assignment__c WHERE Project__r.Account__c = :accountId WITH USER_MODE
                ORDER BY Status__c, Supplier__r.Name
            ];
        } catch (QueryException e) {
            throw new AuraHandledException('Unable to load suppliers: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Project_Resource__c> getTeam(Id accountId) {
        if (accountId == null) {
            return new List<Project_Resource__c>();
        }
        try {
            return [
                SELECT Id, Employee__r.Name, Project__r.Name, Role__c, Allocation__c, Resource_Status__c,
                       Start_Date__c, End_Date__c
                FROM Project_Resource__c
                WHERE Project__r.Account__c = :accountId AND Resource_Status__c != 'Rolled Off' WITH USER_MODE
                ORDER BY Employee__r.Name
            ];
        } catch (QueryException e) {
            throw new AuraHandledException('Unable to load the team: ' + e.getMessage());
        }
    }

    // Shared by getData (the KPI count and live-update matching) and getUpdatesAwaitingReview.
    private static List<Deliverable_Update__c> queryUpdatesAwaitingReview(Id accountId) {
        return [
            SELECT Id, Name, Deliverable__c, Deliverable__r.Name, Supplier__r.Name, Submitted_Date__c,
                   Reported_Status__c, Percent_Complete__c, Supplier_Health__c, Internal_Review_Status__c,
                   Requires_Customer_Action__c
            FROM Deliverable_Update__c
            WHERE Deliverable__r.Project__r.Account__c = :accountId AND Internal_Review_Status__c IN :PENDING_REVIEW
            WITH USER_MODE
            ORDER BY Submitted_Date__c DESC
        ];
    }

    private static CommandCenterData load(Id accountId) {
        CommandCenterData d = new CommandCenterData();
        List<Account> accts = [
            SELECT Id, Name, Account_Role__c, Account_Status__c, Customer_Tier__c, Customer_Health__c,
                   Government_Account__c, Owner.Name
            FROM Account WHERE Id = :accountId WITH USER_MODE
        ];
        if (accts.isEmpty()) {
            return null;
        }
        d.account = accts[0];

        d.contracts = [
            SELECT Id, ContractNumber, Award_Number__c, Status, StartDate, EndDate, Contract_Type__c,
                   Contract_Value__c, Funded_Value__c, Revenue_Recognized__c, Total_Backlog__c, Funded_Backlog__c,
                   Original_Margin__c, Current_Margin__c, Margin_Variance__c, Contract_Health__c,
                   Current_Period__c, Next_Option_Date__c, Program_Manager__r.Name
            FROM Contract WHERE AccountId = :accountId WITH USER_MODE
            ORDER BY Status, StartDate DESC
        ];
        d.projects = [
            SELECT Id, Name, Project_Number__c, Contract__c, Status__c, Health__c, Risk_Level__c,
                   Percent_Complete__c, Start_Date__c, Target_End_Date__c, Project_Manager__r.Name,
                   Budget__c, Forecast_Cost__c, Revenue_Allocation__c, Forecast_Margin__c, Margin_Erosion__c
            FROM Project__c WHERE Account__c = :accountId WITH USER_MODE
            ORDER BY Start_Date__c
        ];
        d.deliverables = [
            SELECT Id, Name, Deliverable_Number__c, Project__c, Deliverable_Type__c, Status__c, Health__c,
                   Priority__c, Percent_Complete__c, Planned_Start_Date__c, Due_Date__c, Forecast_Completion_Date__c,
                   Actual_Completion_Date__c, Schedule_Variance_Days__c, Is_Overdue__c, Is_At_Risk__c,
                   Acceptance_Status__c, Revenue_Milestone__c, Requires_Customer_Action__c, Supplier__r.Name
            FROM Deliverable__c WHERE Project__r.Account__c = :accountId WITH USER_MODE
            ORDER BY Due_Date__c NULLS LAST
        ];
        d.risks = [
            SELECT Id, Name, Risk_Number__c, Risk_Category__c, Likelihood__c, Consequence__c, Risk_Score__c,
                   Severity__c, Status__c, Risk_Owner__r.Name, Project__r.Name, Deliverable__r.Name,
                   Target_Resolution_Date__c, Revenue_at_Risk__c
            FROM Risk__c WHERE Account__c = :accountId AND Status__c NOT IN :CLOSED_RISK WITH USER_MODE
            ORDER BY Risk_Score__c DESC NULLS LAST
        ];
        d.cases = [
            SELECT Id, CaseNumber, Subject, Status, Priority, Severity__c, IsEscalated, CreatedDate,
                   Service_Engagement__r.Name, Deliverable__r.Name
            FROM Case WHERE AccountId = :accountId AND IsClosed = false WITH USER_MODE
            ORDER BY Severity__c NULLS LAST, CreatedDate DESC
        ];
        d.serviceEngagements = [
            SELECT Id, Name, Service_Type__c, Status__c, Health__c, Service_Level__c, Cases_Open__c,
                   SLA_Breaches__c, Next_Milestone_Date__c, Annual_Contract_Value__c, Service_Owner__r.Name
            FROM Service_Engagement__c WHERE Account__c = :accountId WITH USER_MODE
            ORDER BY Status__c, Name
        ];
        d.updatesAwaitingReview = queryUpdatesAwaitingReview(accountId);

        computeKpis(d);
        return d;
    }

    private static void computeKpis(CommandCenterData d) {
        Kpis k = d.kpis;
        for (Contract c : d.contracts) {
            if (c.Status == 'Activated') {
                k.activeContractValue += nz(c.Contract_Value__c);
                k.backlog += nz(c.Total_Backlog__c);
            }
        }
        for (Deliverable__c del : d.deliverables) {
            if (del.Acceptance_Status__c == 'Accepted') k.revenueAccepted += nz(del.Revenue_Milestone__c);
            if (del.Is_At_Risk__c) {
                k.atRiskDeliverables++;
                k.revenueAtRisk += nz(del.Revenue_Milestone__c);
            }
            if (del.Is_Overdue__c) k.overdueDeliverables++;
        }
        k.openRisks = d.risks.size();
        for (Risk__c r : d.risks) {
            if (r.Severity__c == 'High' || r.Severity__c == 'Critical') k.highRisks++;
        }
        k.openCases = d.cases.size();
        for (Case c : d.cases) {
            if (c.Severity__c != null && (c.Severity__c.startsWith('Sev 1') || c.Severity__c.startsWith('Sev 2'))) k.severeCases++;
        }
        k.updatesAwaitingReview = d.updatesAwaitingReview.size();
    }

    private static Decimal nz(Decimal v) {
        return v == null ? 0 : v;
    }
}
