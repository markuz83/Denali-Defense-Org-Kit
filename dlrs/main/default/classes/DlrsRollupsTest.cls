/**
 * Exercises the DLRS child triggers with real records and checks the Realtime rollups they
 * drive (customMetadata/dlrs__LookupRollupSummary2.*), end to end: Deliverable and Risk ->
 * Project -> Contract -> Account, Case -> Account and Service Engagement, and Opportunity ->
 * competitor Account.
 */
@IsTest
private class DlrsRollupsTest {

    @IsTest
    static void rollupsFlowUpTheHierarchy() {
        Account customer = new Account(Name = 'Rollup Agency', Account_Role__c = 'Customer');
        Account rival = new Account(Name = 'Rollup Rival', Account_Role__c = 'Competitor');
        insert new List<Account>{ customer, rival };

        Contract k = new Contract(AccountId = customer.Id, Status = 'Draft', StartDate = Date.today(), ContractTerm = 12,
            Award_Number__c = 'ROLL-001', Contract_Value__c = 1000000);
        insert k;
        k.Status = 'Activated';
        update k;

        Project__c p = new Project__c(Name = 'Rollup Project', Contract__c = k.Id, Status__c = 'In Progress', Health__c = 'Red',
            Actual_Cost__c = 100000, Revenue_Allocation__c = 600000, Forecast_Cost__c = 500000);
        insert p;

        Test.startTest();
        insert new List<Deliverable__c>{
            new Deliverable__c(Name = 'Accepted', Project__c = p.Id, Status__c = 'Complete', Health__c = 'Green',
                Actual_Completion_Date__c = Date.today(), Acceptance_Status__c = 'Accepted', Revenue_Milestone__c = 200000),
            new Deliverable__c(Name = 'Blocked', Project__c = p.Id, Status__c = 'Blocked', Health__c = 'Red',
                Blocker_Description__c = 'Waiting.', Revenue_Milestone__c = 300000)
        };
        insert new Risk__c(Name = 'Open risk', Project__c = p.Id, Status__c = 'Identified');
        insert new Risk__c(Name = 'Closed risk', Project__c = p.Id, Status__c = 'Closed');
        Service_Engagement__c se = new Service_Engagement__c(Name = 'Rollup Support', Account__c = customer.Id, Contract__c = k.Id, Status__c = 'Active');
        insert se;
        insert new Case(AccountId = customer.Id, Service_Engagement__c = se.Id, Subject = 'Open issue', Status = 'New');
        insert new Opportunity(Name = 'Lost deal', AccountId = customer.Id, StageName = 'Closed Lost', CloseDate = Date.today(),
            Amount = 750000, Lost_To__c = rival.Id, Loss_Reason__c = 'Price', Create_Contract_on_Win__c = false);
        Test.stopTest();

        Project__c proj = [SELECT Deliverables__c, Deliverables_Complete__c, Deliverables_at_Risk__c, Revenue_Recognized__c,
                                  Revenue_at_Risk__c, Open_Risks__c FROM Project__c WHERE Id = :p.Id];
        Assert.areEqual(2, proj.Deliverables__c);
        Assert.areEqual(1, proj.Deliverables_Complete__c);
        Assert.areEqual(1, proj.Deliverables_at_Risk__c);
        Assert.areEqual(200000, proj.Revenue_Recognized__c);
        Assert.areEqual(300000, proj.Revenue_at_Risk__c);
        Assert.areEqual(1, proj.Open_Risks__c, 'The closed risk is excluded');

        Contract con = [SELECT Revenue_Recognized__c, Actual_Cost__c, Revenue_Allocation__c, Forecast_Cost__c, Total_Backlog__c
                        FROM Contract WHERE Id = :k.Id];
        Assert.areEqual(200000, con.Revenue_Recognized__c, 'Chains through the Project rollup');
        Assert.areEqual(100000, con.Actual_Cost__c);
        Assert.areEqual(600000, con.Revenue_Allocation__c);
        Assert.areEqual(500000, con.Forecast_Cost__c);

        Account acct = [SELECT Total_Contract_Value__c, Active_Contract_Value__c, Contract_Backlog__c, Active_Projects__c,
                               At_Risk_Projects__c, Open_Deliverables__c, At_Risk_Deliverables__c, Open_Cases__c
                        FROM Account WHERE Id = :customer.Id];
        Assert.areEqual(1000000, acct.Total_Contract_Value__c);
        Assert.areEqual(1000000, acct.Active_Contract_Value__c);
        Assert.areEqual(800000, acct.Contract_Backlog__c, '1,000,000 value - 200,000 recognized');
        Assert.areEqual(1, acct.Active_Projects__c);
        Assert.areEqual(1, acct.At_Risk_Projects__c);
        Assert.areEqual(1, acct.Open_Deliverables__c);
        Assert.areEqual(1, acct.At_Risk_Deliverables__c);
        Assert.areEqual(1, acct.Open_Cases__c);

        Assert.areEqual(1, [SELECT Cases_Open__c FROM Service_Engagement__c WHERE Id = :se.Id].Cases_Open__c);

        Account r = [SELECT Deals_Lost_To__c, Bookings_Lost_To__c FROM Account WHERE Id = :rival.Id];
        Assert.areEqual(1, r.Deals_Lost_To__c);
        Assert.areEqual(750000, r.Bookings_Lost_To__c);
    }

    @IsTest
    static void deletingAChildRecalculates() {
        Account customer = new Account(Name = 'Delete Agency', Account_Role__c = 'Customer');
        insert customer;
        Contract k = new Contract(AccountId = customer.Id, Status = 'Draft', StartDate = Date.today(), ContractTerm = 12);
        insert k;
        Project__c p = new Project__c(Name = 'Delete Project', Contract__c = k.Id, Status__c = 'In Progress');
        insert p;
        Deliverable__c d = new Deliverable__c(Name = 'Temp', Project__c = p.Id, Status__c = 'Not Started');
        insert d;

        Test.startTest();
        delete d;
        Test.stopTest();

        Assert.areEqual(0, [SELECT Deliverables__c FROM Project__c WHERE Id = :p.Id].Deliverables__c);
    }
}
