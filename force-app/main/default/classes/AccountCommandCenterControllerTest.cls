@IsTest
private class AccountCommandCenterControllerTest {

    @TestSetup
    static void setup() {
        Account customer = new Account(Name = 'Test Agency', Account_Role__c = 'Customer', Account_Status__c = 'Active');
        Account supplier = new Account(Name = 'Test Supplier', Account_Role__c = 'Supplier', Account_Status__c = 'Active');
        insert new List<Account>{ customer, supplier };

        Contract k = new Contract(AccountId = customer.Id, Status = 'Draft', StartDate = Date.today().addMonths(-3),
            ContractTerm = 24, Award_Number__c = 'TEST-001', Contract_Value__c = 1000000, Funded_Value__c = 400000);
        insert k;
        k.Status = 'Activated';
        update k;

        Project__c p = new Project__c(Name = 'Test Project', Contract__c = k.Id, Status__c = 'In Progress', Health__c = 'Red',
            Start_Date__c = Date.today().addMonths(-3), Target_End_Date__c = Date.today().addMonths(6),
            Budget__c = 500000, Forecast_Cost__c = 550000, Revenue_Allocation__c = 700000);
        insert p;

        Deliverable__c blocked = new Deliverable__c(Name = 'Blocked Build', Project__c = p.Id, Status__c = 'Blocked',
            Health__c = 'Red', Blocker_Description__c = 'Waiting on test data.', Due_Date__c = Date.today().addDays(-5),
            Revenue_Milestone__c = 100000, Acceptance_Status__c = 'Not Submitted');
        Deliverable__c accepted = new Deliverable__c(Name = 'Design Doc', Project__c = p.Id, Status__c = 'Complete',
            Health__c = 'Green', Actual_Completion_Date__c = Date.today().addDays(-30), Due_Date__c = Date.today().addDays(-30),
            Revenue_Milestone__c = 50000, Acceptance_Status__c = 'Accepted');
        insert new List<Deliverable__c>{ blocked, accepted };

        insert new Risk__c(Name = 'Test Risk', Account__c = customer.Id, Likelihood__c = '4 - Highly Likely',
            Consequence__c = '4 - Significant', Status__c = 'Identified', Mitigation_Plan__c = 'Escalate weekly.');
        insert new Case(AccountId = customer.Id, Subject = 'Build crash', Status = 'New',
            Severity__c = 'Sev 2 - Major Degradation', Deliverable__c = blocked.Id, Project__c = p.Id);
        insert new Service_Engagement__c(Name = 'Test Support', Account__c = customer.Id, Contract__c = k.Id, Status__c = 'Active');
        insert new Supplier_Assignment__c(Project__c = p.Id, Supplier__c = supplier.Id, Role__c = 'Subcontractor', Status__c = 'Active');
        insert new Deliverable_Update__c(Deliverable__c = blocked.Id, Progress_Summary__c = 'Still blocked.',
            Reported_Status__c = 'Blocked', Internal_Review_Status__c = 'Pending');
        insert new Project_Resource__c(Project__c = p.Id, Employee__c = UserInfo.getUserId(), Role__c = 'Project Manager',
            Resource_Status__c = 'Active', Allocation__c = 40);
    }

    @IsTest
    static void loadsEverythingForTheAccount() {
        Id accountId = [SELECT Id FROM Account WHERE Name = 'Test Agency'].Id;

        Test.startTest();
        AccountCommandCenterController.CommandCenterData d = AccountCommandCenterController.getData(accountId);
        Test.stopTest();

        Assert.areEqual('Test Agency', d.account.Name);
        Assert.areEqual(1, d.contracts.size());
        Assert.areEqual(1, d.projects.size());
        Assert.areEqual(2, d.deliverables.size());
        Assert.areEqual(1, d.cases.size());
        Assert.areEqual(1, d.serviceEngagements.size());
        Assert.areEqual(1, d.updatesAwaitingReview.size());
        Assert.isTrue(d.risks.size() >= 1, 'Manual risk (plus any the Case Create Risk flow added)');

        Assert.areEqual(1000000, d.kpis.activeContractValue);
        Assert.areEqual(100000, d.kpis.revenueAtRisk, 'Only the blocked deliverable is at risk');
        Assert.areEqual(50000, d.kpis.revenueAccepted);
        Assert.areEqual(1, d.kpis.atRiskDeliverables);
        Assert.areEqual(1, d.kpis.overdueDeliverables);
        Assert.areEqual(1, d.kpis.openCases);
        Assert.areEqual(1, d.kpis.severeCases);
        Assert.areEqual(1, d.kpis.updatesAwaitingReview);
        Assert.isTrue(d.kpis.highRisks >= 1, 'Likelihood 4 x Consequence 4 = 16 is Critical');
    }

    @IsTest
    static void loadsTheSupplierAndTeamSections() {
        Id accountId = [SELECT Id FROM Account WHERE Name = 'Test Agency'].Id;

        Test.startTest();
        List<Deliverable_Update__c> updates = AccountCommandCenterController.getUpdatesAwaitingReview(accountId);
        List<Supplier_Assignment__c> suppliers = AccountCommandCenterController.getSuppliers(accountId);
        List<Project_Resource__c> team = AccountCommandCenterController.getTeam(accountId);
        Test.stopTest();

        Assert.areEqual(1, updates.size());
        Assert.areEqual('Blocked Build', updates[0].Deliverable__r.Name);
        Assert.areEqual(1, suppliers.size());
        Assert.areEqual('Test Supplier', suppliers[0].Supplier__r.Name);
        Assert.areEqual(1, team.size());
        Assert.areEqual('Project Manager', team[0].Role__c);
    }

    @IsTest
    static void listsActiveCustomersWithTheirAwardNumbers() {
        insert new List<Account>{
            new Account(Name = 'New Customer', Account_Role__c = 'Customer', Account_Status__c = 'Active'),
            new Account(Name = 'Prospect Agency', Account_Role__c = 'Customer', Account_Status__c = 'Prospect')
        };

        Test.startTest();
        List<AccountCommandCenterController.PickerOption> options = AccountCommandCenterController.getPickerAccounts();
        Test.stopTest();

        List<String> labels = new List<String>();
        for (AccountCommandCenterController.PickerOption o : options) {
            labels.add(o.label);
        }
        // Active customers only, by name: no supplier, no prospect. No activated contract, no award number.
        Assert.areEqual(new List<String>{ 'New Customer', 'Test Agency - TEST-001' }, labels);
        Assert.areEqual([SELECT Id FROM Account WHERE Name = 'Test Agency'].Id, options[1].value);
    }

    @IsTest
    static void returnsNullWithoutAnAccount() {
        Assert.isNull(AccountCommandCenterController.getData(null));
        Assert.isTrue(AccountCommandCenterController.getUpdatesAwaitingReview(null).isEmpty());
        Assert.isTrue(AccountCommandCenterController.getSuppliers(null).isEmpty());
        Assert.isTrue(AccountCommandCenterController.getTeam(null).isEmpty());
    }
}
