@IsTest
private class PortfolioControllersTest {

    // Records are created in @TestSetup (outside startTest/stopTest), so asynchronous flow
    // paths (e.g. the Pricing Rationale prompt) never run here.
    @TestSetup
    static void setup() {
        String openStage = [SELECT ApiName FROM OpportunityStage WHERE IsActive = true AND IsClosed = false ORDER BY SortOrder LIMIT 1].ApiName;
        Account customer = new Account(Name = 'Portfolio Agency', Account_Role__c = 'Customer');
        Account rival = new Account(Name = 'Rival Federal', Account_Role__c = 'Competitor');
        insert new List<Account>{ customer, rival };

        insert new List<Opportunity>{
            new Opportunity(Name = 'Open Below Floor', AccountId = customer.Id, StageName = openStage, CloseDate = Date.today().addMonths(3),
                Amount = 1000000, Contract_Type__c = 'Fixed Price', Acquisition_Type__c = 'Competitive', Estimated_Margin__c = 9,
                Incumbent__c = rival.Id),
            new Opportunity(Name = 'Won Against Rival', AccountId = customer.Id, StageName = 'Closed Won', CloseDate = Date.today().addMonths(-2),
                Amount = 500000, Contract_Type__c = 'Fixed Price', Acquisition_Type__c = 'Competitive', Estimated_Margin__c = 12,
                Incumbent__c = rival.Id, Create_Contract_on_Win__c = false),
            new Opportunity(Name = 'Lost To Rival', AccountId = customer.Id, StageName = 'Closed Lost', CloseDate = Date.today().addMonths(-1),
                Amount = 800000, Contract_Type__c = 'Fixed Price', Acquisition_Type__c = 'Competitive', Estimated_Margin__c = 17,
                Incumbent__c = rival.Id, Lost_To__c = rival.Id, Loss_Reason__c = 'Price', Create_Contract_on_Win__c = false)
        };

        Contract k = new Contract(AccountId = customer.Id, Status = 'Draft', StartDate = Date.today().addMonths(-6), ContractTerm = 24,
            Award_Number__c = 'PORT-001', Contract_Value__c = 2000000, Funded_Value__c = 800000, Original_Margin__c = 18);
        insert k;
        Project__c p = new Project__c(Name = 'Portfolio Project', Contract__c = k.Id, Status__c = 'In Progress', Health__c = 'Yellow',
            Start_Date__c = Date.today().addMonths(-5), Revenue_Allocation__c = 1000000, Forecast_Cost__c = 850000);
        insert p;
        insert new List<Deliverable__c>{
            new Deliverable__c(Name = 'Blocked Item', Project__c = p.Id, Status__c = 'Blocked', Health__c = 'Red',
                Blocker_Description__c = 'Waiting.', Due_Date__c = Date.today().addDays(-3), Revenue_Milestone__c = 200000),
            new Deliverable__c(Name = 'Done Item', Project__c = p.Id, Status__c = 'Complete', Health__c = 'Green',
                Actual_Completion_Date__c = Date.today().addDays(-20), Due_Date__c = Date.today().addDays(-20),
                Acceptance_Status__c = 'Accepted', Revenue_Milestone__c = 100000)
        };
        insert new Risk__c(Name = 'Contract Risk', Contract__c = k.Id, Likelihood__c = '4 - Highly Likely',
            Consequence__c = '4 - Significant', Status__c = 'Identified', Mitigation_Plan__c = 'Weekly review.');
    }

    @IsTest
    static void pricingApprovalsListsAndDecides() {
        Id oppId = [SELECT Id FROM Opportunity WHERE Name = 'Open Below Floor'].Id;
        Test.startTest();
        MarginGuardrailController.submitForApproval(oppId, UserInfo.getUserId(), 'Must win.');
        List<PricingApprovalsController.ApprovalItem> items = PricingApprovalsController.getMyApprovals();
        Assert.areEqual(1, items.size());
        Assert.areEqual(oppId, items[0].recordId);
        Assert.areEqual(9, items[0].opportunity.Estimated_Margin__c);
        PricingApprovalsController.decide(items[0].workitemId, 'Approve', 'Strategic.');
        Test.stopTest();

        Assert.areEqual('Approved', [SELECT Margin_Approval_Status__c FROM Opportunity WHERE Id = :oppId].Margin_Approval_Status__c);
        Assert.areEqual(0, PricingApprovalsController.getMyApprovals().size());
    }

    @IsTest
    static void pricingApprovalsRejectsUnknownAction() {
        try {
            PricingApprovalsController.decide(null, 'Delegate', null);
            Assert.fail('Expected an error');
        } catch (AuraHandledException e) {
            Assert.isTrue(true);
        }
    }

    @IsTest
    static void competitorIntelFromOpportunityAndAccount() {
        Id oppId = [SELECT Id FROM Opportunity WHERE Name = 'Open Below Floor'].Id;
        Id rivalId = [SELECT Id FROM Account WHERE Name = 'Rival Federal'].Id;
        Test.startTest();
        CompetitorIntelController.Intel fromOpp = CompetitorIntelController.getIntel(oppId);
        CompetitorIntelController.Intel fromAccount = CompetitorIntelController.getIntel(rivalId);
        Test.stopTest();

        Assert.areEqual('Rival Federal', fromOpp.competitorName);
        Assert.areEqual(1, fromOpp.wins);
        Assert.areEqual(1, fromOpp.losses);
        Assert.areEqual(800000, fromOpp.bookingsLost);
        Assert.areEqual(12, fromOpp.avgMarginWon);
        Assert.areEqual(17, fromOpp.avgMarginLost);
        Assert.areEqual(1, fromOpp.openDeals);
        Assert.areEqual('Price', fromOpp.lossReasons[0].reason);
        Assert.areEqual(fromOpp.losses, fromAccount.losses);
        Assert.areEqual(9, fromOpp.pursuitMargin, 'The open opportunity\'s own margin');
        Assert.areEqual(12, fromOpp.pursuitFloor, 'Fixed Price floor');
        Assert.isNull(fromAccount.pursuitMargin, 'No pursuit on a competitor\'s account page');
        Assert.isNull(CompetitorIntelController.getIntel([SELECT Id FROM Account WHERE Name = 'Portfolio Agency'].Id),
            'A customer account is not profiled');
    }

    @IsTest
    static void contractHealthRollsUpUnderneath() {
        Id contractId = [SELECT Id FROM Contract WHERE Award_Number__c = 'PORT-001'].Id;
        Test.startTest();
        ContractHealthController.Health h = ContractHealthController.getHealth(contractId);
        Test.stopTest();

        Assert.areEqual(1, h.projects.size());
        Assert.areEqual(2, h.deliverables);
        Assert.areEqual(1, h.deliverablesComplete);
        Assert.areEqual(1, h.deliverablesAtRisk);
        Assert.areEqual(1, h.deliverablesOverdue);
        Assert.areEqual(200000, h.revenueAtRisk);
        Assert.areEqual(200000, h.revenueAwaitingAcceptance);
        Assert.areEqual(1, h.openRisks);
        Assert.areEqual(1, h.highRisks);
    }
}
