@IsTest
private class DenaliAgentActionsTest {

    // Records are created in @TestSetup (outside startTest/stopTest), so asynchronous flow
    // paths (e.g. the Pricing Rationale prompt) never run here.
    @TestSetup
    static void setup() {
        String openStage = [SELECT ApiName FROM OpportunityStage WHERE IsActive = true AND IsClosed = false ORDER BY SortOrder LIMIT 1].ApiName;
        Account customer = new Account(Name = 'Agent Test Agency', Account_Role__c = 'Customer', Customer_Health__c = 'Green');
        Account quiet = new Account(Name = 'Agent Quiet Agency', Account_Role__c = 'Customer');
        Account rival = new Account(Name = 'Agent Rival Federal', Account_Role__c = 'Competitor');
        insert new List<Account>{ customer, quiet, rival };

        insert new Opportunity(Name = 'Agent Open Below Floor', AccountId = customer.Id, StageName = openStage,
            CloseDate = Date.today().addMonths(3), Amount = 1000000, Contract_Type__c = 'Fixed Price',
            Acquisition_Type__c = 'Competitive', Estimated_Margin__c = 9, Incumbent__c = rival.Id);

        Contract k = new Contract(AccountId = customer.Id, Status = 'Draft', StartDate = Date.today().addMonths(-6), ContractTerm = 24,
            Award_Number__c = 'AGENT-001', Contract_Value__c = 2000000, Funded_Value__c = 800000, Original_Margin__c = 18,
            Next_Option_Date__c = Date.today().addDays(90), Current_Period__c = 'Base');
        insert k;
        Project__c p = new Project__c(Name = 'Agent Project', Contract__c = k.Id, Account__c = customer.Id, Status__c = 'In Progress',
            Health__c = 'Yellow', Start_Date__c = Date.today().addMonths(-5), Revenue_Allocation__c = 1000000, Forecast_Cost__c = 850000);
        insert p;
        Deliverable__c blocked = new Deliverable__c(Name = 'Agent Blocked Build', Project__c = p.Id, Account__c = customer.Id,
            Status__c = 'Blocked', Health__c = 'Red', Blocker_Description__c = 'Waiting on test data.',
            Due_Date__c = Date.today().addDays(10), Revenue_Milestone__c = 200000);
        insert blocked;
        insert new List<Deliverable_Update__c>{
            new Deliverable_Update__c(Deliverable__c = blocked.Id, Progress_Summary__c = 'Integration started.',
                Reported_Status__c = 'In Progress', Percent_Complete__c = 60, Internal_Review_Status__c = 'Pending',
                Submitted_Date__c = Datetime.now().addDays(-14)),
            new Deliverable_Update__c(Deliverable__c = blocked.Id, Progress_Summary__c = 'No progress.',
                Reported_Status__c = 'Blocked', Percent_Complete__c = 60, Internal_Review_Status__c = 'Pending',
                Submitted_Date__c = Datetime.now().addDays(-1))
        };
        // Likelihood 4 x Consequence 4 scores 16: Critical.
        insert new Risk__c(Name = 'Agent Funding Risk', Account__c = customer.Id, Project__c = p.Id, Likelihood__c = '4 - Highly Likely',
            Consequence__c = '4 - Significant', Status__c = 'Analyzing', Mitigation_Plan__c = 'Weekly review.');
        insert new Case(AccountId = customer.Id, Subject = 'Agent build crash', Status = 'New',
            Severity__c = 'Sev 2 - Major Degradation', Project__c = p.Id, Deliverable__c = blocked.Id);
    }

    @IsTest
    static void portfolioRiskRatesAccountsAndFlagsStaleHealth() {
        Test.startTest();
        Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(DenaliAgentPortfolioRisk.run(
            new List<DenaliAgentPortfolioRisk.Request>{ new DenaliAgentPortfolioRisk.Request() })[0].result);
        Test.stopTest();

        Map<String, Object> flagged;
        for (Object o : (List<Object>) data.get('flaggedAccounts')) {
            Map<String, Object> f = (Map<String, Object>) o;
            if (f.get('name') == 'Agent Test Agency') flagged = f;
        }
        Assert.isNotNull(flagged, 'The customer with a blocked deliverable is flagged');
        Assert.areEqual('at risk', flagged.get('status'));
        Assert.areEqual(200000, (Decimal) flagged.get('revenueAtRisk'));
        Assert.areEqual(true, flagged.get('healthRatingOutOfDate'), 'Green health on an at-risk account is out of date');
        Assert.isTrue(((List<Object>) data.get('clearAccounts')).contains('Agent Quiet Agency'));
    }

    @IsTest
    static void portfolioRiskCanSkipWatchAccounts() {
        Account a = [SELECT Id FROM Account WHERE Name = 'Agent Quiet Agency'];
        a.Customer_Health__c = 'Yellow';
        update a;
        DenaliAgentPortfolioRisk.Request req = new DenaliAgentPortfolioRisk.Request();
        req.includeWatch = false;
        Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(
            DenaliAgentPortfolioRisk.run(new List<DenaliAgentPortfolioRisk.Request>{ req })[0].result);

        for (Object o : (List<Object>) data.get('flaggedAccounts')) {
            Assert.areEqual('at risk', ((Map<String, Object>) o).get('status'));
        }
    }

    @IsTest
    static void accountOverviewFindsByPartialName() {
        DenaliAgentAccountOverview.Request req = new DenaliAgentAccountOverview.Request();
        req.accountName = 'Test Agency';
        Test.startTest();
        Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(
            DenaliAgentAccountOverview.run(new List<DenaliAgentAccountOverview.Request>{ req })[0].result);
        Test.stopTest();

        Assert.areEqual('Agent Test Agency', ((Map<String, Object>) data.get('account')).get('name'));
        Assert.areEqual(1, ((List<Object>) data.get('atRiskDeliverables')).size());
        Assert.areEqual(1, ((List<Object>) data.get('openCases')).size());
    }

    @IsTest
    static void accountOverviewAsksWhenAmbiguousOrBlank() {
        DenaliAgentAccountOverview.Request ambiguous = new DenaliAgentAccountOverview.Request();
        ambiguous.accountName = 'Agent';
        DenaliAgentAccountOverview.Request blank = new DenaliAgentAccountOverview.Request();
        blank.accountName = ' ';
        List<DenaliAgentAccountOverview.Result> results = DenaliAgentAccountOverview.run(
            new List<DenaliAgentAccountOverview.Request>{ ambiguous, blank });

        Assert.isTrue(results[0].result.contains('matches several records'));
        Assert.isTrue(results[1].result.contains('Portfolio Risk'));
    }

    @IsTest
    static void deliverableStatusFlagsStalledProgress() {
        DenaliAgentDeliverableStatus.Request req = new DenaliAgentDeliverableStatus.Request();
        req.deliverableName = 'Blocked Build';
        Test.startTest();
        Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(
            DenaliAgentDeliverableStatus.run(new List<DenaliAgentDeliverableStatus.Request>{ req })[0].result);
        Test.stopTest();

        Assert.areEqual(true, data.get('noProgressSinceLastUpdate'));
        Assert.areEqual(2, ((List<Object>) data.get('supplierUpdatesNewestFirst')).size());
        Assert.areEqual(200000, (Decimal) ((Map<String, Object>) data.get('deliverable')).get('revenueAtRisk'));
    }

    @IsTest
    static void myProjectsListsTheUsersActiveWork() {
        Project__c p = [SELECT Id FROM Project__c WHERE Name = 'Agent Project'];
        p.Project_Manager__c = UserInfo.getUserId();
        update p;
        DenaliAgentMyProjects.Request all = new DenaliAgentMyProjects.Request();
        DenaliAgentMyProjects.Request other = new DenaliAgentMyProjects.Request();
        other.projectName = 'Some Other Project';
        Test.startTest();
        List<DenaliAgentMyProjects.Result> results = DenaliAgentMyProjects.run(
            new List<DenaliAgentMyProjects.Request>{ all, other });
        Test.stopTest();

        Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(results[0].result);
        List<Object> projects = (List<Object>) data.get('activeProjects');
        Assert.areEqual(1, projects.size());
        Map<String, Object> project = (Map<String, Object>) projects[0];
        Assert.areEqual('Agent Project', project.get('name'));
        Assert.areEqual(1, project.get('atRisk'));
        Assert.areEqual(2, ((List<Object>) data.get('supplierUpdatesToReview')).size());
        Assert.areEqual(1, ((List<Object>) data.get('deliverablesDueIn30Days')).size());

        Map<String, Object> filtered = (Map<String, Object>) JSON.deserializeUntyped(results[1].result);
        Assert.areEqual(0, ((List<Object>) filtered.get('activeProjects')).size());
        Assert.isTrue(((String) filtered.get('note')).contains('Some Other Project'));
    }

    @IsTest
    static void deliverableStatusReportsNoMatch() {
        DenaliAgentDeliverableStatus.Request req = new DenaliAgentDeliverableStatus.Request();
        req.deliverableName = 'Nothing Like This';
        Assert.areEqual('No deliverable matches \'Nothing Like This\'.',
            DenaliAgentDeliverableStatus.run(new List<DenaliAgentDeliverableStatus.Request>{ req })[0].result);
    }

    @IsTest
    static void pricingApprovalsListAndApprove() {
        Id oppId = [SELECT Id FROM Opportunity WHERE Name = 'Agent Open Below Floor'].Id;
        Test.startTest();
        MarginGuardrailController.submitForApproval(oppId, UserInfo.getUserId(), 'Must win.');
        DenaliAgentPricingApprovals.Request all = new DenaliAgentPricingApprovals.Request();
        DenaliAgentPricingApprovals.Request other = new DenaliAgentPricingApprovals.Request();
        other.opportunityName = 'Some Other Deal';
        List<DenaliAgentPricingApprovals.Result> lists = DenaliAgentPricingApprovals.run(
            new List<DenaliAgentPricingApprovals.Request>{ all, other });
        Map<String, Object> listed = (Map<String, Object>) JSON.deserializeUntyped(lists[0].result);
        Map<String, Object> filtered = (Map<String, Object>) JSON.deserializeUntyped(lists[1].result);

        DenaliAgentPricingDecision.Request req = new DenaliAgentPricingDecision.Request();
        req.opportunityName = 'open below floor';
        req.decision = 'approve';
        req.comments = 'Strategic.';
        String outcome = DenaliAgentPricingDecision.run(new List<DenaliAgentPricingDecision.Request>{ req })[0].result;
        Test.stopTest();

        List<Object> pending = (List<Object>) listed.get('pendingRequests');
        Assert.areEqual(1, pending.size());
        Assert.areEqual(0, ((List<Object>) filtered.get('pendingRequests')).size());
        Assert.areEqual(9, (Decimal) ((Map<String, Object>) pending[0]).get('estimatedMargin'));
        Assert.isTrue(outcome.startsWith('Approved pricing for Agent Open Below Floor'), outcome);
        Assert.areEqual('Approved', [SELECT Margin_Approval_Status__c FROM Opportunity WHERE Id = :oppId].Margin_Approval_Status__c);
    }

    @IsTest
    static void pricingDecisionRejectsBadInput() {
        DenaliAgentPricingDecision.Request badDecision = new DenaliAgentPricingDecision.Request();
        badDecision.opportunityName = 'Agent Open Below Floor';
        badDecision.decision = 'Delegate';
        DenaliAgentPricingDecision.Request notPending = new DenaliAgentPricingDecision.Request();
        notPending.opportunityName = 'Agent Open Below Floor';
        notPending.decision = 'Reject';
        List<DenaliAgentPricingDecision.Result> results = DenaliAgentPricingDecision.run(
            new List<DenaliAgentPricingDecision.Request>{ badDecision, notPending });

        Assert.isTrue(results[0].result.startsWith('The decision must be Approve or Reject'));
        Assert.isTrue(results[1].result.startsWith('No pricing approval waiting on you'));
    }

    @IsTest
    static void programBriefingFindsByAwardNumberOrProject() {
        DenaliAgentProgramBriefing.Request byAward = new DenaliAgentProgramBriefing.Request();
        byAward.programName = 'AGENT-001';
        DenaliAgentProgramBriefing.Request byProject = new DenaliAgentProgramBriefing.Request();
        byProject.programName = 'agent project';
        Test.startTest();
        List<DenaliAgentProgramBriefing.Result> results = DenaliAgentProgramBriefing.run(
            new List<DenaliAgentProgramBriefing.Request>{ byAward, byProject });
        Test.stopTest();

        Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(results[0].result);
        Assert.areEqual('AGENT-001', ((Map<String, Object>) data.get('program')).get('awardNumber'));
        // DLRS rolls Revenue Recognized up from projects, and nothing is recognized yet, so the whole funded value is backlog.
        Assert.areEqual(800000, (Decimal) ((Map<String, Object>) data.get('funding')).get('fundedBacklog'));
        Assert.areEqual(90, (Integer) ((Map<String, Object>) data.get('nextOption')).get('daysUntilOption'));
        Assert.areEqual(1, ((List<Object>) data.get('atRiskDeliverables')).size(), 'The blocked deliverable links through its project');
        Assert.areEqual(200000, (Decimal) data.get('revenueAtRisk'));
        // The setup risk links through its project; Case_Create_Risk adds a second one from the Sev 2 case.
        Assert.areEqual(2, (Integer) data.get('openRiskCount'));
        Set<String> riskNames = new Set<String>();
        for (Object o : (List<Object>) data.get('topOpenRisks')) {
            riskNames.add((String) ((Map<String, Object>) o).get('name'));
        }
        Assert.isTrue(riskNames.contains('Agent Funding Risk'), String.valueOf(riskNames));
        Assert.isNotNull(((Map<String, Object>) data.get('margin')).get('marginVariancePts'));
        Assert.areEqual(1, (Integer) data.get('openCaseCount'), 'The Sev 2 case links through its deliverable');
        Assert.areEqual(1, (Integer) data.get('severeCaseCount'));
        Assert.areEqual(results[0].result, results[1].result, 'A project name finds its contract');
    }

    @IsTest
    static void programBriefingAsksWhenAmbiguousOrMissing() {
        Account customer = [SELECT Id FROM Account WHERE Name = 'Agent Test Agency'];
        insert new Contract(AccountId = customer.Id, Status = 'Draft', StartDate = Date.today(), ContractTerm = 12,
            Award_Number__c = 'AGENT-002');
        DenaliAgentProgramBriefing.Request ambiguous = new DenaliAgentProgramBriefing.Request();
        ambiguous.programName = 'Agent Test Agency';
        DenaliAgentProgramBriefing.Request missing = new DenaliAgentProgramBriefing.Request();
        missing.programName = 'Nothing Like This';
        DenaliAgentProgramBriefing.Request blank = new DenaliAgentProgramBriefing.Request();
        List<DenaliAgentProgramBriefing.Result> results = DenaliAgentProgramBriefing.run(
            new List<DenaliAgentProgramBriefing.Request>{ ambiguous, missing, blank });

        Assert.isTrue(results[0].result.contains('matches several programs'), results[0].result);
        Assert.isTrue(results[0].result.contains('AGENT-002'), results[0].result);
        Assert.areEqual('No program matches \'Nothing Like This\'.', results[1].result);
        Assert.isTrue(results[2].result.startsWith('No program name given'));
    }

    @IsTest
    static void caseBriefingFindsByNumberOrSubject() {
        String caseNumber = [SELECT CaseNumber FROM Case WHERE Subject = 'Agent build crash'].CaseNumber;
        DenaliAgentCaseBriefing.Request byNumber = new DenaliAgentCaseBriefing.Request();
        byNumber.caseName = 'case ' + caseNumber.replaceFirst('^0+', '');
        DenaliAgentCaseBriefing.Request bySubject = new DenaliAgentCaseBriefing.Request();
        bySubject.caseName = 'build crash';
        Test.startTest();
        List<DenaliAgentCaseBriefing.Result> results = DenaliAgentCaseBriefing.run(
            new List<DenaliAgentCaseBriefing.Request>{ byNumber, bySubject });
        Test.stopTest();

        Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(results[0].result);
        Map<String, Object> c = (Map<String, Object>) data.get('case');
        Assert.areEqual(caseNumber, c.get('caseNumber'));
        Assert.areEqual('Sev 2 - Major Degradation', c.get('severity'));
        Map<String, Object> impact = (Map<String, Object>) data.get('impact');
        Assert.areEqual(200000, (Decimal) impact.get('revenueAtStake'), 'The blocked deliverable\'s milestone is at stake');
        Assert.areEqual('AGENT-001', ((Map<String, Object>) impact.get('contract')).get('awardNumber'));
        Assert.isFalse(((List<Object>) data.get('openRisks')).isEmpty());
        Assert.areEqual(results[0].result, results[1].result, 'The subject finds the same case');
    }

    @IsTest
    static void caseBriefingAsksWhenAmbiguousOrMissing() {
        Account customer = [SELECT Id FROM Account WHERE Name = 'Agent Test Agency'];
        insert new Case(AccountId = customer.Id, Subject = 'Agent build slow', Status = 'New', Severity__c = 'Sev 3 - Minor Issue');
        DenaliAgentCaseBriefing.Request ambiguous = new DenaliAgentCaseBriefing.Request();
        ambiguous.caseName = 'Agent build';
        DenaliAgentCaseBriefing.Request missing = new DenaliAgentCaseBriefing.Request();
        missing.caseName = 'Nothing Like This';
        DenaliAgentCaseBriefing.Request blank = new DenaliAgentCaseBriefing.Request();
        List<DenaliAgentCaseBriefing.Result> results = DenaliAgentCaseBriefing.run(
            new List<DenaliAgentCaseBriefing.Request>{ ambiguous, missing, blank });

        Assert.isTrue(results[0].result.contains('matches several cases'), results[0].result);
        Assert.areEqual('No case matches \'Nothing Like This\'.', results[1].result);
        Assert.isTrue(results[2].result.startsWith('No case given'));
    }

    @IsTest
    static void openCasesListsMostUrgentFirst() {
        Account quiet = [SELECT Id FROM Account WHERE Name = 'Agent Quiet Agency'];
        insert new List<Case>{
            new Case(AccountId = quiet.Id, Subject = 'Agent network outage', Status = 'New', Severity__c = 'Sev 1 - Critical Outage'),
            new Case(AccountId = quiet.Id, Subject = 'Agent access request', Status = 'Waiting on Customer',
                Severity__c = 'Sev 4 - Informational / Request')
        };
        DenaliAgentOpenCases.Request everyone = new DenaliAgentOpenCases.Request();
        DenaliAgentOpenCases.Request oneAccount = new DenaliAgentOpenCases.Request();
        oneAccount.accountName = 'Agent Test Agency';
        DenaliAgentOpenCases.Request noAccount = new DenaliAgentOpenCases.Request();
        noAccount.accountName = 'Nothing Like This';
        Test.startTest();
        List<DenaliAgentOpenCases.Result> results = DenaliAgentOpenCases.run(
            new List<DenaliAgentOpenCases.Request>{ everyone, oneAccount, noAccount });
        Test.stopTest();

        Map<String, Object> all = (Map<String, Object>) JSON.deserializeUntyped(results[0].result);
        List<Object> cases = (List<Object>) all.get('cases');
        Assert.areEqual(3, cases.size());
        Assert.areEqual('Agent network outage', ((Map<String, Object>) cases[0]).get('subject'), 'Sev 1 first');
        Assert.areEqual('Agent access request', ((Map<String, Object>) cases[2]).get('subject'), 'Sev 4 last');
        Map<String, Object> summary = (Map<String, Object>) all.get('summary');
        Assert.areEqual(1, (Integer) summary.get('waitingOnCustomer'));
        Assert.areEqual(200000, (Decimal) summary.get('deliverableRevenueAtStake'));

        Map<String, Object> mine = (Map<String, Object>) JSON.deserializeUntyped(results[1].result);
        Assert.areEqual('Agent Test Agency', mine.get('scope'));
        Assert.areEqual(1, ((List<Object>) mine.get('cases')).size());
        Assert.areEqual('No account matches \'Nothing Like This\'.', results[2].result);
    }
}
