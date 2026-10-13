// 04_seed_revenue_history.apex
// Adds the deals behind the Revenue Health and Margin & Competition dashboards:
// - Three quarters of bookings against the $5.5M quarterly target, so fiscal-year reporting has a
//   trend: $6.1M won (111%) three quarters ago (with 02's $4.2M Northwind award, which closes eight
//   months before the seed), $4.6M (84%) two quarters ago, and $3.7M (67%) last quarter. Losses to the incumbent competitor (Vantage Federal) grow each quarter ($0.8M, $2.4M,
//   $3.3M), each with a Loss Reason. Wins against Vantage are priced lower than the losses, which
//   Competitor Intel reads (13.5% against 18%). One No Bid stays out
//   of win rates.
// - One open fixed-price deal priced at 9%, below its 12% Margin Floor, to demo the Margin
//   Exception approval (move it to a proposal stage and the validation rule stops it).
// Run after 02_seed_demo_data.apex. Re-runnable: deals are matched by name and updated, so
// re-running also brings earlier runs up to date. 99_reset removes them with the rest of the seed.
//
// - Kept out of 02 because anonymous Apex is capped at 32,000 characters.
// - Close dates are relative to today (fiscal year starts in January).
// - The won deals are task orders and mods under existing vehicles, so no new Contracts.
// - When optional/'s sales processes are deployed, it also gives every demo deal its record type:
//   Contract Growth for task orders, mods and option exercises, New Pursuit for everything else.

String pv(Schema.SObjectField f, String preferred, String fallback) {
    for (Schema.PicklistEntry e : f.getDescribe().getPicklistValues()) {
        if (e.isActive() && e.getValue() == preferred) return preferred;
    }
    return fallback;
}

// Description is a long text area, so SOQL can't filter on it; check the tag in Apex instead.
Map<String, Id> acct = new Map<String, Id>();
for (Account a : [SELECT Id, Name, Description FROM Account
                  WHERE Name IN ('Northwind Defense Agency', 'Federal Logistics Command', 'Aegis Program Office', 'Vantage Federal')]) {
    if (a.Description != null && a.Description.contains('[demo-seed]')) acct.put(a.Name, a.Id);
}
if (acct.size() < 4) {
    Assert.fail('Seeded Accounts not found. Run 02_seed_demo_data.apex first.');
}

Id army = acct.get('Northwind Defense Agency'), logistics = acct.get('Federal Logistics Command');
Id aegis = acct.get('Aegis Program Office'), vantage = acct.get('Vantage Federal');
Id me = UserInfo.getUserId();
Date today = Date.today();
Date lastQStart = Date.newInstance(today.year(), ((today.month() - 1) / 3) * 3 + 1, 1).addMonths(-3);
Date q1Start = lastQStart.addMonths(-6), q2Start = lastQStart.addMonths(-3);   // three and two quarters ago
String won = 'Closed Won', lost = 'Closed Lost';
String noBid = pv(Opportunity.StageName, 'No Bid', lost);
String stageCapture = pv(Opportunity.StageName, 'Capture / Shaping', 'Qualification');
String tTaskOrder = pv(Opportunity.Type, 'Task Order', 'Existing Customer - Upgrade');
String tMod = pv(Opportunity.Type, 'Contract Modification', 'Existing Customer - Upgrade');
String tNew = pv(Opportunity.Type, 'New Business', 'New Customer');

List<Opportunity> opps = new List<Opportunity>{
    new Opportunity(Name = 'NDA - Sensor Sustainment Task Order 3', AccountId = army, StageName = won,
        CloseDate = lastQStart.addDays(20), Amount = 1600000, Estimated_Contract_Value__c = 1600000, Type = tTaskOrder,
        Contract_Vehicle__c = 'IDIQ', Acquisition_Type__c = 'Sole Source', Prime_Subcontract__c = 'Prime',
        Contract_Type__c = 'Fixed Price', Program_Manager__c = me, Estimated_Margin__c = 16, Create_Contract_on_Win__c = false),
    new Opportunity(Name = 'FLC - Surge Network Support Mod', AccountId = logistics, StageName = won,
        CloseDate = lastQStart.addDays(45), Amount = 900000, Estimated_Contract_Value__c = 900000, Type = tMod,
        Contract_Vehicle__c = 'GSA Schedule', Acquisition_Type__c = 'Sole Source', Prime_Subcontract__c = 'Prime',
        Contract_Type__c = 'Time & Materials', Program_Manager__c = me, Estimated_Margin__c = 19, Create_Contract_on_Win__c = false),
    new Opportunity(Name = 'NDA - Operator Training Task Order', AccountId = army, StageName = won,
        CloseDate = lastQStart.addDays(75), Amount = 1200000, Estimated_Contract_Value__c = 1200000, Type = tTaskOrder,
        Contract_Vehicle__c = 'IDIQ', Acquisition_Type__c = 'Competitive', Prime_Subcontract__c = 'Prime',
        Contract_Type__c = 'Fixed Price', Incumbent__c = vantage, Program_Manager__c = me,
        Estimated_Margin__c = 12, Create_Contract_on_Win__c = false),
    new Opportunity(Name = 'Aegis - Cyber Range Pilot', AccountId = aegis, StageName = lost,
        CloseDate = lastQStart.addDays(38), Amount = 2200000, Estimated_Contract_Value__c = 2200000, Type = tNew,
        Contract_Vehicle__c = 'Direct Contract', Acquisition_Type__c = 'Competitive', Prime_Subcontract__c = 'Prime',
        Contract_Type__c = 'Fixed Price', Incumbent__c = vantage, Capture_Manager__c = me,
        Estimated_Margin__c = 17, Create_Contract_on_Win__c = false, Loss_Reason__c = 'Price', Lost_To__c = vantage),
    new Opportunity(Name = 'FLC - Depot Automation Study', AccountId = logistics, StageName = lost,
        CloseDate = lastQStart.addDays(66), Amount = 1100000, Estimated_Contract_Value__c = 1100000, Type = tNew,
        Contract_Vehicle__c = 'GSA Schedule', Acquisition_Type__c = 'Competitive', Prime_Subcontract__c = 'Prime',
        Contract_Type__c = 'Time & Materials', Incumbent__c = vantage, Capture_Manager__c = me,
        Estimated_Margin__c = 20, Create_Contract_on_Win__c = false, Loss_Reason__c = 'Incumbent Advantage', Lost_To__c = vantage),
    // Three quarters ago: with 02's $4.2M Northwind award, $6.1M won; a loss on price to Vantage; a No Bid
    new Opportunity(Name = 'NDA - Cyber Assessment Task Order', AccountId = army, StageName = won,
        CloseDate = q1Start.addDays(70), Amount = 1900000, Estimated_Contract_Value__c = 1900000, Type = tTaskOrder,
        Contract_Vehicle__c = 'IDIQ', Acquisition_Type__c = 'Competitive', Prime_Subcontract__c = 'Prime',
        Contract_Type__c = 'Fixed Price', Incumbent__c = vantage, Program_Manager__c = me,
        Estimated_Margin__c = 13, Create_Contract_on_Win__c = false),
    new Opportunity(Name = 'Aegis - Cloud Migration Assessment', AccountId = aegis, StageName = lost,
        CloseDate = q1Start.addDays(55), Amount = 800000, Estimated_Contract_Value__c = 800000, Type = tNew,
        Contract_Vehicle__c = 'Direct Contract', Acquisition_Type__c = 'Competitive', Prime_Subcontract__c = 'Prime',
        Contract_Type__c = 'Fixed Price', Incumbent__c = vantage, Capture_Manager__c = me,
        Estimated_Margin__c = 18, Create_Contract_on_Win__c = false, Loss_Reason__c = 'Price', Lost_To__c = vantage),
    new Opportunity(Name = 'FLC - Fleet Telematics Pilot', AccountId = logistics, StageName = noBid,
        CloseDate = q1Start.addDays(30), Amount = 600000, Estimated_Contract_Value__c = 600000, Type = tNew,
        Contract_Vehicle__c = 'GSA Schedule', Acquisition_Type__c = 'Competitive', Prime_Subcontract__c = 'Prime',
        Contract_Type__c = 'Time & Materials', Capture_Manager__c = me, Estimated_Margin__c = 20,
        Create_Contract_on_Win__c = false, Loss_Reason__c = 'No Bid'),
    // Two quarters ago: $4.6M won (one below the floor, approved), two losses to Vantage
    new Opportunity(Name = 'NDA - Sensor Sustainment Task Order 2', AccountId = army, StageName = won,
        CloseDate = q2Start.addDays(20), Amount = 1700000, Estimated_Contract_Value__c = 1700000, Type = tTaskOrder,
        Contract_Vehicle__c = 'IDIQ', Acquisition_Type__c = 'Sole Source', Prime_Subcontract__c = 'Prime',
        Contract_Type__c = 'Fixed Price', Program_Manager__c = me, Estimated_Margin__c = 15, Create_Contract_on_Win__c = false),
    new Opportunity(Name = 'FLC - Field Engineering Surge Mod', AccountId = logistics, StageName = won,
        CloseDate = q2Start.addDays(50), Amount = 1300000, Estimated_Contract_Value__c = 1300000, Type = tMod,
        Contract_Vehicle__c = 'GSA Schedule', Acquisition_Type__c = 'Sole Source', Prime_Subcontract__c = 'Prime',
        Contract_Type__c = 'Time & Materials', Program_Manager__c = me, Estimated_Margin__c = 18, Create_Contract_on_Win__c = false),
    new Opportunity(Name = 'NDA - Logistics Analytics Task Order', AccountId = army, StageName = won,
        CloseDate = q2Start.addDays(80), Amount = 1600000, Estimated_Contract_Value__c = 1600000, Type = tTaskOrder,
        Contract_Vehicle__c = 'IDIQ', Acquisition_Type__c = 'Competitive', Prime_Subcontract__c = 'Prime',
        Contract_Type__c = 'Fixed Price', Incumbent__c = vantage, Program_Manager__c = me,
        Estimated_Margin__c = 11, Margin_Approval_Status__c = 'Approved', Create_Contract_on_Win__c = false),
    new Opportunity(Name = 'Aegis - Identity Modernization', AccountId = aegis, StageName = lost,
        CloseDate = q2Start.addDays(35), Amount = 1500000, Estimated_Contract_Value__c = 1500000, Type = tNew,
        Contract_Vehicle__c = 'Direct Contract', Acquisition_Type__c = 'Competitive', Prime_Subcontract__c = 'Prime',
        Contract_Type__c = 'Fixed Price', Incumbent__c = vantage, Capture_Manager__c = me,
        Estimated_Margin__c = 16, Create_Contract_on_Win__c = false, Loss_Reason__c = 'Price', Lost_To__c = vantage),
    new Opportunity(Name = 'FLC - Warehouse RFID Pilot', AccountId = logistics, StageName = lost,
        CloseDate = q2Start.addDays(65), Amount = 900000, Estimated_Contract_Value__c = 900000, Type = tNew,
        Contract_Vehicle__c = 'GSA Schedule', Acquisition_Type__c = 'Competitive', Prime_Subcontract__c = 'Prime',
        Contract_Type__c = 'Time & Materials', Incumbent__c = vantage, Capture_Manager__c = me,
        Estimated_Margin__c = 19, Create_Contract_on_Win__c = false, Loss_Reason__c = 'Technical', Lost_To__c = vantage),
    // Live demo deal: 9% on fixed price is below the 12% floor
    new Opportunity(Name = 'Aegis - Zero Trust Production (FFP)', AccountId = aegis, StageName = stageCapture,
        CloseDate = today.addMonths(4), Amount = 2400000, Estimated_Contract_Value__c = 7200000, Type = tNew,
        Contract_Vehicle__c = 'Direct Contract', Acquisition_Type__c = 'Competitive', Prime_Subcontract__c = 'Prime',
        Contract_Type__c = 'Fixed Price', Program_Type__c = 'Production', Incumbent__c = vantage,
        Capture_Manager__c = me, Program_Manager__c = me, Customer_Priority__c = 'Critical', Estimated_Margin__c = 9)
};

// Match existing deals by name so a re-run updates them instead of duplicating.
Map<String, Id> existing = new Map<String, Id>();
Set<String> names = new Set<String>();
for (Opportunity o : opps) names.add(o.Name);
for (Opportunity o : [SELECT Id, Name FROM Opportunity WHERE Name IN :names AND AccountId IN :acct.values()]) {
    existing.put(o.Name, o.Id);
}
for (Opportunity o : opps) o.Id = existing.get(o.Name);
upsert opps;

// Record types (optional/): each drives its own sales process and path.
Map<String, Id> rt = new Map<String, Id>();
for (RecordType r : [SELECT Id, DeveloperName FROM RecordType WHERE SobjectType = 'Opportunity' AND IsActive = true
                     AND DeveloperName IN ('New_Pursuit', 'Contract_Growth')]) {
    rt.put(r.DeveloperName, r.Id);
}
List<Opportunity> retyped = new List<Opportunity>();
if (rt.size() == 2) {
    Set<String> growth = new Set<String>{ 'Task Order', 'Option Exercise', 'Contract Modification' };
    for (Opportunity o : [SELECT Id, Type, RecordTypeId FROM Opportunity WHERE AccountId IN :acct.values()]) {
        Id wanted = rt.get(growth.contains(o.Type) ? 'Contract_Growth' : 'New_Pursuit');
        if (o.RecordTypeId != wanted) retyped.add(new Opportunity(Id = o.Id, RecordTypeId = wanted));
    }
    update retyped;
}

System.debug(LoggingLevel.ERROR, 'Revenue history: ' + (opps.size() - existing.size()) + ' added, ' + existing.size()
    + ' updated (quarters from ' + q1Start.format() + '; last quarter starts ' + lastQStart.format() + '). '
    + (rt.size() == 2 ? retyped.size() + ' deals given a record type.' : 'No sales process record types deployed.'));
