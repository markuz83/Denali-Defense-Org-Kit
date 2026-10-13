@IsTest
private class DeliveryControllersTest {

    @TestSetup
    static void setup() {
        Account a = new Account(Name = 'Delivery Agency', Account_Role__c = 'Customer');
        insert a;
        Contract k = new Contract(AccountId = a.Id, Status = 'Draft', StartDate = Date.today().addMonths(-4), ContractTerm = 24,
            Award_Number__c = 'DLV-001', Contract_Value__c = 3000000);
        insert k;
        Project__c p = new Project__c(Name = 'Delivery Project', Contract__c = k.Id, Status__c = 'In Progress', Health__c = 'Yellow',
            Project_Manager__c = UserInfo.getUserId(), Start_Date__c = Date.today().addMonths(-3),
            Target_End_Date__c = Date.today().addMonths(6), Revenue_Allocation__c = 1000000, Forecast_Cost__c = 900000);
        insert p;
        Deliverable__c blocked = new Deliverable__c(Name = 'Blocked Build', Project__c = p.Id, Status__c = 'Blocked', Health__c = 'Red',
            Blocker_Description__c = 'Waiting on data.', Due_Date__c = Date.today().addDays(10), Percent_Complete__c = 40,
            Revenue_Milestone__c = 250000, Acceptance_Status__c = 'Not Submitted');
        Deliverable__c done = new Deliverable__c(Name = 'Design Doc', Project__c = p.Id, Status__c = 'Complete', Health__c = 'Green',
            Actual_Completion_Date__c = Date.today().addDays(-10), Due_Date__c = Date.today().addDays(-10), Acceptance_Status__c = 'Accepted');
        insert new List<Deliverable__c>{ blocked, done };
        insert new Deliverable_Update__c(Deliverable__c = blocked.Id, Progress_Summary__c = 'Integration resumed.',
            Reported_Status__c = 'In Progress', Percent_Complete__c = 70, Internal_Review_Status__c = 'Pending');
        insert new Risk__c(Name = 'Data late', Deliverable__c = blocked.Id, Risk_Owner__c = UserInfo.getUserId(), Status__c = 'Identified');
        // Case.Deliverable__c has a lookup filter: the deliverable must belong to the case's Project.
        insert new Case(AccountId = a.Id, Subject = 'Build crash', Status = 'New', Severity__c = 'Sev 2 - Major Degradation',
            Project__c = p.Id, Deliverable__c = blocked.Id);
    }

    private static Deliverable_Update__c pendingUpdate() {
        return [SELECT Id, Deliverable__c FROM Deliverable_Update__c WHERE Internal_Review_Status__c = 'Pending' LIMIT 1];
    }

    @IsTest
    static void myWorkSummarizesTheProjectManagersProjects() {
        Test.startTest();
        MyProjectsController.MyWork w = MyProjectsController.getMyWork();
        Test.stopTest();

        Assert.areEqual(1, w.projects.size());
        MyProjectsController.ProjectSummary s = w.projects[0];
        Assert.areEqual(2, s.deliverables);
        Assert.areEqual(1, s.complete);
        Assert.areEqual(1, s.atRisk);
        Assert.areEqual(250000, s.revenueAtRisk);
        Assert.areEqual(1, s.dueSoon, 'The blocked build is due in 10 days; the completed one is excluded');
        Assert.areEqual(1, s.updatesToReview);
        Assert.areEqual(1, w.updatesToReview.size());
        Assert.areEqual(1, w.dueSoon.size());
        Assert.isTrue(w.risks.size() >= 1);
    }

    @IsTest
    static void acceptingAnUpdateAppliesItToTheDeliverable() {
        Deliverable_Update__c u = pendingUpdate();
        Test.startTest();
        SupplierUpdateReviewController.review(u.Id, 'Accepted', null);
        Test.stopTest();

        Assert.areEqual('Accepted', [SELECT Internal_Review_Status__c FROM Deliverable_Update__c WHERE Id = :u.Id].Internal_Review_Status__c);
        Deliverable__c d = [SELECT Status__c, Percent_Complete__c FROM Deliverable__c WHERE Id = :u.Deliverable__c];
        Assert.areEqual('In Progress', d.Status__c, 'Update Review flow applies the reported status');
        Assert.areEqual(70, d.Percent_Complete__c);

        SupplierUpdateReviewController.Review r = SupplierUpdateReviewController.getReview(u.Deliverable__c);
        Assert.areEqual(1, r.updates.size());
        Assert.isNotNull(r.updates[0].Reviewed_By__c, 'Review Stamp flow sets the reviewer');
    }

    @IsTest
    static void bouncingAnUpdateNeedsComments() {
        Deliverable_Update__c u = pendingUpdate();
        try {
            SupplierUpdateReviewController.review(u.Id, 'Needs Clarification', ' ');
            Assert.fail('Expected an error without comments');
        } catch (AuraHandledException e) {
            Assert.isTrue(true);
        }
        Test.startTest();
        SupplierUpdateReviewController.review(u.Id, 'Needs Clarification', 'Which build fixed the crash?');
        Test.stopTest();
        Deliverable_Update__c after = [SELECT Internal_Review_Status__c, Reviewer_Comments__c FROM Deliverable_Update__c WHERE Id = :u.Id];
        Assert.areEqual('Needs Clarification', after.Internal_Review_Status__c);
        Assert.areEqual('Which build fixed the crash?', after.Reviewer_Comments__c);
    }

    @IsTest
    static void unknownDecisionIsRejected() {
        try {
            SupplierUpdateReviewController.review(pendingUpdate().Id, 'Maybe', null);
            Assert.fail('Expected an error');
        } catch (AuraHandledException e) {
            Assert.isTrue(true);
        }
    }

    @IsTest
    static void impactChainFollowsTheCaseUpstream() {
        Id caseId = [SELECT Id FROM Case WHERE Subject = 'Build crash'].Id;
        Test.startTest();
        ImpactChainController.Chain ch = ImpactChainController.getChain(caseId);
        Test.stopTest();

        Assert.areEqual('Blocked Build', ch.deliverable.Name);
        Assert.areEqual('Delivery Project', ch.project.Name);
        Assert.areEqual('DLV-001', ch.contract.Award_Number__c);
        Assert.areEqual(250000, ch.revenueAtStake);
        Assert.isTrue(ch.risks.size() >= 1, 'The manual risk, plus the one Case Create Risk adds for a Sev 2');
    }

    @IsTest
    static void impactChainFollowsAServiceCaseToItsContract() {
        Account a = [SELECT Id FROM Account WHERE Name = 'Delivery Agency'];
        Contract k = [SELECT Id FROM Contract WHERE Award_Number__c = 'DLV-001'];
        Service_Engagement__c se = new Service_Engagement__c(Name = 'Delivery Help Desk', Account__c = a.Id, Contract__c = k.Id,
            Status__c = 'Active');
        insert se;
        insert new Risk__c(Name = 'Recompete pressure', Account__c = a.Id, Contract__c = k.Id, Status__c = 'Identified');
        Case c = new Case(AccountId = a.Id, Subject = 'Help desk outage', Status = 'New', Severity__c = 'Sev 1 - Critical Outage',
            Service_Engagement__c = se.Id);
        insert c;

        Test.startTest();
        ImpactChainController.Chain ch = ImpactChainController.getChain(c.Id);
        Test.stopTest();

        Assert.isNull(ch.deliverable);
        Assert.isNull(ch.project);
        Assert.areEqual('Delivery Help Desk', ch.serviceEngagement.Name);
        Assert.areEqual('DLV-001', ch.contract.Award_Number__c, 'No project, so the contract comes from the Service Engagement');
        Assert.isNull(ch.revenueAtStake);
        // Risk Parents also stamps the contract on the setup's deliverable risks, so look for this one by name.
        Set<String> riskNames = new Set<String>();
        for (Risk__c r : ch.risks) {
            riskNames.add(r.Name);
        }
        Assert.isTrue(riskNames.contains('Recompete pressure'), String.valueOf(riskNames));
    }
}
