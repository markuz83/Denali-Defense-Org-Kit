@IsTest
private class MarginGuardrailControllerTest {

    // Records are created in @TestSetup (outside startTest/stopTest), so the asynchronous
    // Pricing Rationale flow never runs here and no prompt is sent to a model.
    @TestSetup
    static void setup() {
        String openStage = [SELECT ApiName FROM OpportunityStage WHERE IsActive = true AND IsClosed = false ORDER BY SortOrder LIMIT 1].ApiName;
        Account a = new Account(Name = 'Guardrail Agency', Account_Role__c = 'Customer');
        insert a;
        insert new List<Opportunity>{
            new Opportunity(Name = 'Below Floor Deal', AccountId = a.Id, StageName = openStage, CloseDate = Date.today().addMonths(3),
                Amount = 1000000, Contract_Type__c = 'Fixed Price', Acquisition_Type__c = 'Competitive', Estimated_Margin__c = 9),
            new Opportunity(Name = 'Earlier Win', AccountId = a.Id, StageName = 'Closed Won', CloseDate = Date.today().addMonths(-2),
                Amount = 500000, Contract_Type__c = 'Fixed Price', Acquisition_Type__c = 'Competitive', Estimated_Margin__c = 15,
                Create_Contract_on_Win__c = false)
        };
    }

    private static Id dealId() {
        return [SELECT Id FROM Opportunity WHERE Name = 'Below Floor Deal'].Id;
    }

    @IsTest
    static void contextShowsFloorAndComparableWins() {
        Test.startTest();
        MarginGuardrailController.GuardrailContext ctx = MarginGuardrailController.getContext(dealId());
        Test.stopTest();

        Assert.isTrue(ctx.opportunity.Below_Margin_Floor__c, '9% on fixed price is below the 12% floor');
        Assert.areEqual(12, ctx.opportunity.Margin_Floor__c);
        Assert.areEqual(30000, ctx.opportunity.Margin_Shortfall__c, '$1M x 3 points');
        Assert.areEqual(15, ctx.avgWonMarginSameType, 'The earlier competitive win');
        Assert.isTrue(ctx.wonCountSameType >= 1);
        Assert.isFalse(ctx.pendingApproval);
    }

    @IsTest
    static void submitsForApproval() {
        Id oppId = dealId();
        Test.startTest();
        MarginGuardrailController.submitForApproval(oppId, UserInfo.getUserId(), 'Strategic entry.');
        MarginGuardrailController.GuardrailContext ctx = MarginGuardrailController.getContext(oppId);
        Test.stopTest();

        Assert.areEqual('Pending', [SELECT Margin_Approval_Status__c FROM Opportunity WHERE Id = :oppId].Margin_Approval_Status__c);
        Assert.isTrue(ctx.pendingApproval);
        Assert.isNotNull(ctx.pendingApproverName);
    }

    @IsTest
    static void submitRequiresAnApprover() {
        try {
            MarginGuardrailController.submitForApproval(dealId(), null, null);
            Assert.fail('Expected an error without an approver');
        } catch (AuraHandledException e) {
            Assert.isTrue(true);
        }
    }

    @IsTest
    static void regeneratesAndSavesRationale() {
        Id oppId = dealId();
        Test.startTest();
        String text = MarginGuardrailController.regenerateRationale(oppId);
        Test.stopTest();

        Assert.areEqual(MarginGuardrailController.TEST_RATIONALE, text);
        Assert.areEqual(text, [SELECT Pricing_Rationale__c FROM Opportunity WHERE Id = :oppId].Pricing_Rationale__c);
    }
}
