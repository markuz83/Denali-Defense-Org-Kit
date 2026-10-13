@IsTest
private class AccountPlanMeasureRefreshTest {

    @IsTest
    static void relinksMeasuresForChangedDeals() {
        String openStage = [SELECT ApiName FROM OpportunityStage WHERE IsActive = true AND IsClosed = false ORDER BY SortOrder LIMIT 1].ApiName;
        Account a = new Account(Name = 'Plan Test Agency', Account_Role__c = 'Customer');
        insert a;
        Opportunity linked = new Opportunity(Name = 'Plan Test Deal', AccountId = a.Id, StageName = openStage, CloseDate = Date.today(), Amount = 1000);
        Opportunity other = new Opportunity(Name = 'Unlinked Deal', AccountId = a.Id, StageName = openStage, CloseDate = Date.today(), Amount = 1000);
        insert new List<Opportunity>{ linked, other };
        AccountPlan plan = new AccountPlan(Name = 'Plan Test', AccountId = a.Id);
        insert plan;
        AccountPlanObjective objective = new AccountPlanObjective(Name = 'Grow', AccountPlanId = plan.Id);
        insert objective;
        AccountPlanObjectiveMeasure measure = new AccountPlanObjectiveMeasure(Name = 'Revenue', AccountPlanObjectiveId = objective.Id,
            ValueType = 'Currency', TargetValue = '1000');
        insert measure;
        AccountPlanObjMeasRela link = new AccountPlanObjMeasRela(AccountPlanObjectiveMeasureId = measure.Id, ReferenceRecordId = linked.Id);
        insert link;

        Test.startTest();
        AccountPlanMeasureRefresh.Request r = new AccountPlanMeasureRefresh.Request();
        r.opportunityId = linked.Id;
        AccountPlanMeasureRefresh.refreshFromFlow(new List<AccountPlanMeasureRefresh.Request>{ r });
        Integer none = AccountPlanMeasureRefresh.refresh(new Set<Id>{ other.Id });
        Test.stopTest();

        List<AccountPlanObjMeasRela> after = [SELECT Id, ReferenceRecordId FROM AccountPlanObjMeasRela WHERE AccountPlanObjectiveMeasureId = :measure.Id];
        Assert.areEqual(1, after.size(), 'Still one link');
        Assert.areEqual(linked.Id, after[0].ReferenceRecordId);
        Assert.areNotEqual(link.Id, after[0].Id, 'The link was re-saved, which recalculates the measure');
        Assert.areEqual(0, none, 'Deals without links are left alone');
    }
}
