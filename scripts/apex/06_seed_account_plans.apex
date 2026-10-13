// 06_seed_account_plans.apex
// Adds a Sales Account Plan to each demo customer, so management can show how they strategize on
// existing customers and prospects:
// - Northwind Defense Agency: growth plan (recover Sensor Fusion, grow task orders on the IDIQ).
// - Federal Logistics Command: retention plan (secure Option Year 2, restore reliability).
// - Aegis Program Office: capture plan for a prospect (win Zero Trust Production above the floor).
// Each plan has the account strategy and SWOT filled in, objectives, and measures. Measures that
// track deals are linked to the demo opportunities and calculated by Salesforce, so closing a
// deal in the demo moves its plan's numbers:
// "Opportunity Revenue Targets" (won Amount, created when Account Plans is enabled) and
// "Open Pipeline" (open Amount, deployed from account-plans/).
//
// Needs Sales Account Plans enabled and account-plans/ deployed. Run after 02 and 04.
// Re-runnable: it deletes the seeded accounts' plans and creates them again. 99_reset removes them.
// The Open Pipeline definition deploys as Draft (conditions can only be added in Draft), and Apex
// can't update it, so activate it once after deploying:
//   sf data update record --sobject AccountPlanObjMeasCalcDef --where "DeveloperName=Denali_Open_Pipeline" --values "Status=Active"


// Description is a long text area, so SOQL can't filter on it; check the tag in Apex instead.
Map<String, Id> acct = new Map<String, Id>();
for (Account a : [SELECT Id, Name, Description FROM Account
                  WHERE Name IN ('Northwind Defense Agency', 'Federal Logistics Command', 'Aegis Program Office')]) {
    if (a.Description != null && a.Description.contains('[demo-seed]')) acct.put(a.Name, a.Id);
}
if (acct.size() < 3) {
    Assert.fail('Seeded Accounts not found. Run 02_seed_demo_data.apex first.');
}

Map<String, Id> calc = new Map<String, Id>();
for (AccountPlanObjMeasCalcDef d : [SELECT Id, DeveloperName FROM AccountPlanObjMeasCalcDef WHERE Status = 'Active'
                                    AND DeveloperName IN ('Opportunity_Revenue_Targets', 'Denali_Open_Pipeline')]) {
    calc.put(d.DeveloperName, d.Id);
}
if (calc.size() < 2) {
    Assert.fail('Active calculation definitions not found. Enable Sales Account Plans, deploy account-plans/, '
        + 'and activate Denali_Open_Pipeline (see the header).');
}

Map<String, Id> opp = new Map<String, Id>();
for (Opportunity o : [SELECT Id, Name FROM Opportunity WHERE AccountId IN :acct.values()]) opp.put(o.Name, o.Id);

Set<Id> seededAccounts = new Set<Id>(acct.values());
// Action plans from 08 target these plans' objectives; remove them (and the tasks they generated)
// first. Action Plans may not be on, so query them dynamically.
if (Schema.getGlobalDescribe().containsKey('ActionPlan')) {
    Set<Id> objectiveIds = new Map<Id, SObject>(Database.query(
        'SELECT Id FROM AccountPlanObjective WHERE AccountPlan.AccountId IN :seededAccounts')).keySet();
    List<SObject> actionPlans = Database.query('SELECT Id FROM ActionPlan WHERE TargetId IN :objectiveIds');
    Set<Id> actionTasks = new Set<Id>();
    for (SObject i : Database.query('SELECT ItemId FROM ActionPlanItem WHERE ActionPlanId IN :actionPlans AND ItemId != null')) {
        actionTasks.add((Id) i.get('ItemId'));
    }
    delete [SELECT Id FROM Task WHERE Id IN :actionTasks];
    delete actionPlans;
}
delete [SELECT Id FROM AccountPlan WHERE AccountId IN :acct.values()];   // objectives and measures go with them

Date today = Date.today();
Id me = UserInfo.getUserId();

// ---------------------------------------------------------------- Plans
AccountPlan nda = new AccountPlan(Name = 'Northwind Defense Agency: Growth Plan', AccountId = acct.get('Northwind Defense Agency'),
    Status = 'Active', StartDate = today.addMonths(-1), EndDate = today.addMonths(11),
    AccountVision = 'Be the Agency\'s trusted integrator for sensor modernization, from build through sustainment.',
    AccountStrategicPriorities = 'Field the integrated sensor capability on schedule; consolidate sustainment under one contract; prepare for the next-generation sensor program.',
    AccountPrfmIndicators = 'Revenue milestones accepted on time; task-order revenue on the IDIQ; Customer Health back to Green.',
    AccountChallenges = 'Government-furnished test data arrives late; continuing resolution limits new starts; the program office is short-staffed.',
    AccountIndustryTrends = 'Shift to open sensor architectures (modular open systems approach); more work routed through IDIQ task orders.',
    AccountCompetitors = 'Vantage Federal (incumbent on adjacent sensor work).',
    AccountCompetitiveStrengths = 'Integration track record on Phase 1; cleared team on site; strong supplier in Ironbridge Systems.',
    AccountCmptvWeaknesses = 'Sensor Fusion Build 2.0 is 35 days late; a single software supplier for the fusion build.',
    RelationshipStrengths = 'Close working relationship with the COR (Marcus Reyes) and contracting officer (Dana Whitfield).',
    RelationshipWeaknesses = 'Little contact above the program office.',
    RelationshipOpportunities = 'Contract mod for two additional sensor sites; operator training follow-on.',
    RelationshipThreats = 'A missed acceptance date on Sensor Fusion could push the Agency toward Vantage Federal.');
AccountPlan flc = new AccountPlan(Name = 'Federal Logistics Command: Retention Plan', AccountId = acct.get('Federal Logistics Command'),
    Status = 'Active', StartDate = today.addMonths(-2), EndDate = today.addMonths(10),
    AccountVision = 'Keep Managed Network Operations through every option year and grow into depot modernization.',
    AccountStrategicPriorities = 'Get Option Year 2 exercised; restore confidence after the Denver depot outage; re-open depot automation.',
    AccountPrfmIndicators = 'Option Year 2 exercised on time; zero Sev 1 outages per quarter; depot automation pipeline.',
    AccountChallenges = 'Option Year 2 funding depends on the continuing resolution; the Denver router outage hurt confidence.',
    AccountIndustryTrends = 'Network modernization budgets moving to zero-trust upgrades.',
    AccountCompetitors = 'Vantage Federal won the depot automation study.',
    AccountCompetitiveStrengths = 'Incumbent on network operations, with 18 months of performance history.',
    AccountCmptvWeaknesses = 'Lost depot automation to the incumbent on Incumbent Advantage.',
    RelationshipStrengths = 'Contracting office (Priya Natarajan) is responsive; the technical lead (Tom Becker) values twice-daily updates.',
    RelationshipWeaknesses = 'Customer Health shows Green, but a critical funding risk is open.',
    RelationshipOpportunities = 'Zero-trust network upgrade as a contract modification.',
    RelationshipThreats = 'Option Year 2 not exercised if funding slips past the decision date.');
AccountPlan aegis = new AccountPlan(Name = 'Aegis Program Office: Zero Trust Capture Plan', AccountId = acct.get('Aegis Program Office'),
    Status = 'Active', StartDate = today.addMonths(-1), EndDate = today.addMonths(8),
    AccountVision = 'Win the Zero Trust production award and become the Office\'s zero-trust partner.',
    AccountStrategicPriorities = 'Deliver the prototype (OTA) well; win the production award at or above the margin floor.',
    AccountPrfmIndicators = 'Zero Trust Production won; production margin at or above the 12% fixed-price floor.',
    AccountChallenges = 'Customer price ceiling puts our price at 9%, below the floor; first award with this office.',
    AccountIndustryTrends = 'Zero-trust mandates across the intelligence community; prototypes moving to production under OTA follow-ons.',
    AccountCompetitors = 'Vantage Federal: incumbent, expected to bid aggressively on price.',
    AccountCompetitiveStrengths = 'Zero-trust architecture team; prototype performance.',
    AccountCmptvWeaknesses = 'No past performance with this office; we win against Vantage Federal only when we price 3.5 points lower.',
    RelationshipStrengths = 'Executive sponsor engaged (Helen Cho) since industry day.',
    RelationshipWeaknesses = 'No relationship with the contracting office yet.',
    RelationshipOpportunities = 'Production award leads to sustainment and enterprise roll-out.',
    RelationshipThreats = 'Lost the Cyber Range Pilot to Vantage Federal on price.');
insert new List<AccountPlan>{ nda, flc, aegis };

// ---------------------------------------------------------------- Objectives
// Columns: plan, objective, description, months to target
List<AccountPlan> plans = new List<AccountPlan>{ nda, flc, aegis };
List<List<String>> objectiveRows = new List<List<String>>{
    new List<String>{ '0', 'Recover Sensor Fusion Build 2.0', 'Get the government-furnished test data, agree a recovery schedule with the COR, and protect the $900K acceptance milestone.', '2' },
    new List<String>{ '0', 'Grow task-order revenue on the IDIQ', 'Win sustainment and training task orders, and the scope mod for two additional sensor sites.', '11' },
    new List<String>{ '0', 'Return Customer Health to Green', 'Deliver on time and close the open risks on Sensor Integration Phase 1.', '6' },
    new List<String>{ '1', 'Secure Option Year 2', 'Confirm funding with the contracting office and get Option Year 2 exercised before the decision date.', '3' },
    new List<String>{ '1', 'Restore network reliability', 'No Sev 1 outages after the Denver depot incident; share the after-action report.', '6' },
    new List<String>{ '2', 'Win Zero Trust Production', 'Turn prototype performance into the production award.', '4' },
    new List<String>{ '2', 'Price at or above the margin floor', 'Close the gap between the customer price ceiling and the 12% fixed-price floor, or get the Margin Exception approved.', '2' }
};
List<AccountPlanObjective> objectives = new List<AccountPlanObjective>();
for (List<String> row : objectiveRows) {
    objectives.add(new AccountPlanObjective(AccountPlanId = plans[Integer.valueOf(row[0])].Id, Name = row[1],
        Description = row[2], ObjectiveOwnerId = me, StartDate = today.addMonths(-1),
        EndDate = today.addMonths(Integer.valueOf(row[3]))));
}
insert objectives;

// ---------------------------------------------------------------- Measures
// Columns: objective index, measure, value type, target, current (blank when calculated),
// calculation (blank for manual), linked opportunities (comma-separated)
List<List<String>> measureRows = new List<List<String>>{
    new List<String>{ '0', 'Revenue milestone accepted', 'Currency', '900000', '0', '', '' },
    new List<String>{ '1', 'Task-order revenue won', 'Currency', '5000000', '', 'Opportunity_Revenue_Targets',
        'NDA - Sensor Sustainment Task Order 3,NDA - Operator Training Task Order' },
    new List<String>{ '2', 'Deliverables on time', 'Percent', '90', '60', '', '' },
    new List<String>{ '3', 'Option Year 2 exercised', 'Currency', '1850000', '', 'Opportunity_Revenue_Targets', 'FLC - Network Ops Option Year 2' },
    new List<String>{ '4', 'Sev 1 outages this quarter', 'Number', '0', '1', '', '' },
    new List<String>{ '5', 'Zero Trust pipeline', 'Currency', '3350000', '', 'Denali_Open_Pipeline',
        'Aegis - Zero Trust Production (FFP),Aegis - Zero Trust Prototype (OTA)' },
    new List<String>{ '5', 'Zero Trust Production won', 'Currency', '2400000', '', 'Opportunity_Revenue_Targets', 'Aegis - Zero Trust Production (FFP)' },
    new List<String>{ '6', 'Production margin', 'Percent', '12', '9', '', '' }
};
List<AccountPlanObjectiveMeasure> measures = new List<AccountPlanObjectiveMeasure>();
for (List<String> row : measureRows) {
    measures.add(new AccountPlanObjectiveMeasure(AccountPlanObjectiveId = objectives[Integer.valueOf(row[0])].Id,
        Name = row[1], ValueType = row[2], TargetValue = row[3],
        CurrentValue = String.isBlank(row[4]) ? null : row[4],
        AccountPlanObjMeasCalcDefId = String.isBlank(row[5]) ? null : calc.get(row[5])));
}
insert measures;

List<AccountPlanObjMeasRela> links = new List<AccountPlanObjMeasRela>();
List<String> missing = new List<String>();
for (Integer i = 0; i < measureRows.size(); i++) {
    if (String.isBlank(measureRows[i][6])) continue;
    for (String name : measureRows[i][6].split(',')) {
        if (opp.containsKey(name)) {
            links.add(new AccountPlanObjMeasRela(AccountPlanObjectiveMeasureId = measures[i].Id, ReferenceRecordId = opp.get(name)));
        } else {
            missing.add(name);   // e.g. 04 hasn't run
        }
    }
}
insert links;

System.debug(LoggingLevel.ERROR, 'Account plans: ' + plans.size() + ' plans, ' + objectives.size() + ' objectives, '
    + measures.size() + ' measures, ' + links.size() + ' linked deals.'
    + (missing.isEmpty() ? '' : ' Deals not found: ' + String.join(missing, '; ')));
