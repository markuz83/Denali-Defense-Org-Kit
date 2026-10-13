// 03_recalculate_rollups.apex
// Recalculates every lookup-based rollup in the data model (the ones DLRS or Flow would
// maintain) across ALL records in the org. Safe to re-run any time, e.g. before a demo.
// Native roll-up summaries (Subcontracted Value, Team Size, Next Milestone Date) maintain
// themselves and aren't touched. Sized for demo data (well under 50,000 rows per object).

Set<String> closedDel = new Set<String>{ 'Complete', 'Cancelled' };
Set<String> closedRisk = new Set<String>{ 'Closed', 'Realized' };

Decimal nz(Decimal d) { return d == null ? 0 : d; }
void addTo(Map<Id, Decimal> m, Id key, Decimal v) {
    if (key == null) return;
    m.put(key, nz(m.get(key)) + nz(v));
}
Decimal valOf(Map<Id, Decimal> m, Id key) { return nz(m.get(key)); }
Integer failures(List<Database.SaveResult> results, String label) {
    Integer n = 0;
    for (Database.SaveResult r : results) {
        if (!r.isSuccess()) {
            n++;
            System.debug(LoggingLevel.ERROR, label + ' ' + r.getId() + ': ' + r.getErrors()[0].getMessage());
        }
    }
    return n;
}

// ---------------------------------------------------------------- Project <- Deliverables, Risks
Map<Id, Decimal> dCount = new Map<Id, Decimal>(), dDone = new Map<Id, Decimal>(), dRisk = new Map<Id, Decimal>();
Map<Id, Decimal> revRec = new Map<Id, Decimal>(), revRisk = new Map<Id, Decimal>(), openRisks = new Map<Id, Decimal>();
Map<Id, Decimal> acctOpenDel = new Map<Id, Decimal>(), acctRiskDel = new Map<Id, Decimal>();

for (Deliverable__c d : [SELECT Project__c, Account__c, Status__c, Is_At_Risk__c, Acceptance_Status__c,
                                Revenue_Milestone__c FROM Deliverable__c]) {
    addTo(dCount, d.Project__c, 1);
    if (d.Status__c == 'Complete') addTo(dDone, d.Project__c, 1);
    if (d.Is_At_Risk__c) { addTo(dRisk, d.Project__c, 1); addTo(revRisk, d.Project__c, d.Revenue_Milestone__c); addTo(acctRiskDel, d.Account__c, 1); }
    if (d.Acceptance_Status__c == 'Accepted') addTo(revRec, d.Project__c, d.Revenue_Milestone__c);
    if (!closedDel.contains(d.Status__c)) addTo(acctOpenDel, d.Account__c, 1);
}
for (Risk__c r : [SELECT Project__c, Status__c FROM Risk__c WHERE Project__c != null]) {
    if (!closedRisk.contains(r.Status__c)) addTo(openRisks, r.Project__c, 1);
}

List<Project__c> projects = [SELECT Id, Account__c, Contract__c, Status__c, Health__c, Actual_Cost__c,
                                     Revenue_Allocation__c, Forecast_Cost__c FROM Project__c];
Map<Id, Decimal> kRev = new Map<Id, Decimal>(), kCost = new Map<Id, Decimal>();
Map<Id, Decimal> kAlloc = new Map<Id, Decimal>(), kForecast = new Map<Id, Decimal>();
Map<Id, Decimal> acctActiveProj = new Map<Id, Decimal>(), acctRiskProj = new Map<Id, Decimal>();
for (Project__c p : projects) {
    p.Deliverables__c = valOf(dCount, p.Id);
    p.Deliverables_Complete__c = valOf(dDone, p.Id);
    p.Deliverables_at_Risk__c = valOf(dRisk, p.Id);
    p.Revenue_Recognized__c = valOf(revRec, p.Id);
    p.Revenue_at_Risk__c = valOf(revRisk, p.Id);
    p.Open_Risks__c = valOf(openRisks, p.Id);
    addTo(kRev, p.Contract__c, p.Revenue_Recognized__c);
    addTo(kCost, p.Contract__c, p.Actual_Cost__c);
    addTo(kAlloc, p.Contract__c, p.Revenue_Allocation__c);
    addTo(kForecast, p.Contract__c, p.Forecast_Cost__c);
    if (p.Status__c == 'In Progress') addTo(acctActiveProj, p.Account__c, 1);
    if (p.Health__c == 'Red' && p.Status__c != 'Complete' && p.Status__c != 'Cancelled') addTo(acctRiskProj, p.Account__c, 1);
}
Integer errs = failures(Database.update(projects, false), 'Project');

// ---------------------------------------------------------------- Contract <- Projects
List<Contract> contracts = [SELECT Id, AccountId, Status, Contract_Value__c FROM Contract];
for (Contract k : contracts) {
    k.Revenue_Recognized__c = valOf(kRev, k.Id);
    k.Actual_Cost__c = valOf(kCost, k.Id);
    k.Revenue_Allocation__c = valOf(kAlloc, k.Id);    // with Forecast Cost, drives Current Margin %
    k.Forecast_Cost__c = valOf(kForecast, k.Id);
}
errs += failures(Database.update(contracts, false), 'Contract');

// ---------------------------------------------------------------- Account <- Contracts, Cases
Map<Id, Decimal> tcv = new Map<Id, Decimal>(), acv = new Map<Id, Decimal>(), backlog = new Map<Id, Decimal>();
for (Contract k : [SELECT AccountId, Status, Contract_Value__c, Total_Backlog__c FROM Contract]) {
    addTo(tcv, k.AccountId, k.Contract_Value__c);
    if (k.Status == 'Activated') { addTo(acv, k.AccountId, k.Contract_Value__c); addTo(backlog, k.AccountId, k.Total_Backlog__c); }
}
Map<Id, Decimal> acctCases = new Map<Id, Decimal>(), seCases = new Map<Id, Decimal>();
for (Case c : [SELECT AccountId, Service_Engagement__c FROM Case WHERE IsClosed = false]) {
    addTo(acctCases, c.AccountId, 1);
    addTo(seCases, c.Service_Engagement__c, 1);
}
// Competitors: deals and bookings lost to them (grounds the Pricing Rationale prompt)
Map<Id, Decimal> lostDeals = new Map<Id, Decimal>(), lostBookings = new Map<Id, Decimal>();
for (Opportunity o : [SELECT Lost_To__c, Amount FROM Opportunity WHERE Lost_To__c != null AND IsClosed = true AND IsWon = false]) {
    addTo(lostDeals, o.Lost_To__c, 1);
    addTo(lostBookings, o.Lost_To__c, o.Amount);
}

Set<Id> acctIds = new Set<Id>();
for (Map<Id, Decimal> m : new List<Map<Id, Decimal>>{ tcv, acctCases, acctOpenDel, acctRiskDel, acctActiveProj, acctRiskProj, lostDeals }) acctIds.addAll(m.keySet());
// also zero out accounts that previously had values but no longer do
for (Account a : [SELECT Id FROM Account WHERE Total_Contract_Value__c > 0 OR Open_Cases__c > 0 OR Open_Deliverables__c > 0
                  OR Active_Projects__c > 0 OR At_Risk_Projects__c > 0 OR At_Risk_Deliverables__c > 0 OR Deals_Lost_To__c > 0]) acctIds.add(a.Id);

List<Account> accts = new List<Account>();
for (Id aid : acctIds) {
    accts.add(new Account(Id = aid,
        Total_Contract_Value__c = valOf(tcv, aid), Active_Contract_Value__c = valOf(acv, aid),
        Contract_Backlog__c = valOf(backlog, aid), Active_Projects__c = valOf(acctActiveProj, aid),
        At_Risk_Projects__c = valOf(acctRiskProj, aid), Open_Deliverables__c = valOf(acctOpenDel, aid),
        At_Risk_Deliverables__c = valOf(acctRiskDel, aid), Open_Cases__c = valOf(acctCases, aid),
        Deals_Lost_To__c = valOf(lostDeals, aid), Bookings_Lost_To__c = valOf(lostBookings, aid)));
}
errs += failures(Database.update(accts, false), 'Account');

// ---------------------------------------------------------------- Service Engagement <- Cases
List<Service_Engagement__c> ses = [SELECT Id FROM Service_Engagement__c];
for (Service_Engagement__c se : ses) se.Cases_Open__c = valOf(seCases, se.Id);
errs += failures(Database.update(ses, false), 'Service Engagement');

// SLA Breaches comes from SlaBreachRollup (optional/, needs Entitlement Management), the same
// class the hourly schedule runs. Looked up by name so this script still runs without it.
Type slaRollup = Type.forName('SlaBreachRollup');
if (slaRollup != null) ((Schedulable) slaRollup.newInstance()).execute(null);

System.debug(LoggingLevel.ERROR, '===== ROLLUPS RECALCULATED =====');
System.debug(LoggingLevel.ERROR, 'Projects: ' + projects.size() + ' | Contracts: ' + contracts.size() +
    ' | Accounts: ' + accts.size() + ' | Service Engagements: ' + ses.size() + ' | Failed updates: ' + errs);
if (slaRollup == null) System.debug(LoggingLevel.ERROR, 'SLA Breaches skipped: deploy optional/ (SlaBreachRollup) first.');
