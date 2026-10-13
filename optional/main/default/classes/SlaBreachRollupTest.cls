@IsTest
private class SlaBreachRollupTest {

    // A test can't make a milestone violate (that takes time passing), so the counting query is
    // exercised against no violations and the write logic is checked with counts handed to apply().

    @TestSetup
    static void setup() {
        insert new List<Service_Engagement__c>{
            new Service_Engagement__c(Name = 'Breached Engagement', SLA_Breaches__c = 0),
            new Service_Engagement__c(Name = 'Stale Engagement', SLA_Breaches__c = 3),
            new Service_Engagement__c(Name = 'Unchanged Engagement', SLA_Breaches__c = 0)
        };
        insert new List<Case>{
            new Case(Subject = 'Breached Case'),
            new Case(Subject = 'Stale Case', SLA_Breached__c = true),
            new Case(Subject = 'Unchanged Case')
        };
    }

    static Case findCase(String subject) {
        return [SELECT Id, SLA_Breached__c FROM Case WHERE Subject = :subject];
    }

    static Service_Engagement__c engagement(String name) {
        return [SELECT Id, SLA_Breaches__c FROM Service_Engagement__c WHERE Name = :name];
    }

    @IsTest
    static void applyWritesOnlyChangedCounts() {
        Id breached = engagement('Breached Engagement').Id;

        Test.startTest();
        List<Service_Engagement__c> changed = SlaBreachRollup.apply(new Map<Id, Integer>{ breached => 2 });
        Test.stopTest();

        Assert.areEqual(2, changed.size(), 'Only the breached and the stale engagement change.');
        Assert.areEqual(2, engagement('Breached Engagement').SLA_Breaches__c);
        Assert.areEqual(0, engagement('Stale Engagement').SLA_Breaches__c, 'No violations left, so the count resets.');
        Assert.areEqual(0, engagement('Unchanged Engagement').SLA_Breaches__c);
    }

    @IsTest
    static void flagCasesWritesOnlyChangedFlags() {
        Id breached = findCase('Breached Case').Id;

        Test.startTest();
        List<Case> changed = SlaBreachRollup.flagCases(new Set<Id>{ breached });
        Test.stopTest();

        Assert.areEqual(2, changed.size(), 'Only the breached and the stale case change.');
        Assert.isTrue(findCase('Breached Case').SLA_Breached__c);
        Assert.isFalse(findCase('Stale Case').SLA_Breached__c, 'No violations left, so the flag clears.');
        Assert.isFalse(findCase('Unchanged Case').SLA_Breached__c);
    }

    @IsTest
    static void scheduledRunResetsStaleCounts() {
        Test.startTest();
        String jobId = System.schedule('SLA Breach Rollup Test', '0 0 * * * ?', new SlaBreachRollup());
        Test.stopTest();

        Assert.isNotNull(jobId);
        Assert.areEqual(0, engagement('Stale Engagement').SLA_Breaches__c, 'No test cases are violated.');
        Assert.isFalse(findCase('Stale Case').SLA_Breached__c, 'No test cases are violated.');
    }
}
