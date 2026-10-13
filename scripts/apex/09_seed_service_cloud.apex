// 09_seed_service_cloud.apex
// Puts the demo cases under an SLA and seeds Knowledge, so the Case page's Milestones, path and
// Knowledge components have a story:
// - An entitlement on each demo Service Engagement ("<engagement> SLA", on the Denali Service
//   SLA entitlement process), linked through Service_Engagement__c.Entitlement__c.
// - The open demo cases on that entitlement, with SLA clocks relative to now: the Denver outage
//   (Critical) answered and inside its 24-hour resolution, the Sensor Fusion crash (High) with its
//   4-hour first response breached, the VPN request (Low) answered and waiting on the customer.
// - Four published Knowledge articles that match the demo cases. The closed monitoring case and the
//   VPN request have theirs attached; Denver and Sensor Fusion are left for the demo to attach.
//
// - Needs Entitlement Management, Knowledge (and a Knowledge user running it), and from optional/:
//   the entitlement process, milestone types, Knowledge Details field and Case flows. Run after 02.
// - Re-runnable: replaces its entitlements and articles (articles matched by URL name "denali-").
//   99 removes them too. Run it shortly before the demo, since the SLA clocks start from now.

String pv(Schema.SObjectField f, String preferred, String fallback) {
    for (Schema.PicklistEntry e : f.getDescribe().getPicklistValues()) {
        if (e.isActive() && e.getValue() == preferred) return preferred;
    }
    return fallback;
}

List<SlaProcess> processes = [SELECT Id FROM SlaProcess WHERE Name = 'Denali Service SLA' AND IsActive = true LIMIT 1];
Assert.isFalse(processes.isEmpty(), 'Deploy the Denali Service SLA entitlement process from optional/ first.');
List<Service_Engagement__c> engagements = [
    SELECT Id, Name, Account__c, Start_Date__c, End_Date__c FROM Service_Engagement__c
    WHERE Name IN ('FLC Network Operations Support', 'NDA Sensor Sustainment')
];
Assert.areEqual(2, engagements.size(), 'Run 02_seed_demo_data.apex first.');
Boolean hasEngagementField = Schema.SObjectType.Service_Engagement__c.fields.getMap().containsKey('entitlement__c');
Boolean hasDetailsField = Schema.SObjectType.Knowledge__kav.fields.getMap().containsKey('details__c');

// ---------------------------------------------------------------- Entitlements
Set<Id> engagementIds = new Map<Id, Service_Engagement__c>(engagements).keySet();
Set<Id> accountIds = new Set<Id>();
for (Service_Engagement__c se : engagements) accountIds.add(se.Account__c);

// Re-run: take the engagements, then the cases, off the old entitlements before deleting them.
// Engagements first: Case Entitlement (flow #8) copies the engagement's entitlement onto any case saved.
if (hasEngagementField) {
    for (Service_Engagement__c se : engagements) se.put('Entitlement__c', null);
    update engagements;
}
List<Case> cases = [
    SELECT Id, Subject, IsClosed, Service_Engagement__c FROM Case WHERE Service_Engagement__c IN :engagementIds
];
for (Case c : cases) c.EntitlementId = null;
update cases;
delete [SELECT Id FROM Entitlement WHERE AccountId IN :accountIds AND Name LIKE '% SLA'];

Map<Id, Entitlement> entitlementByEngagement = new Map<Id, Entitlement>();
for (Service_Engagement__c se : engagements) {
    entitlementByEngagement.put(se.Id, new Entitlement(Name = se.Name + ' SLA', AccountId = se.Account__c,
        SlaProcessId = processes[0].Id, StartDate = se.Start_Date__c, EndDate = se.End_Date__c,
        Type = pv(Entitlement.Type, 'Phone Support', null)));
}
insert entitlementByEngagement.values();
if (hasEngagementField) {
    for (Service_Engagement__c se : engagements) se.put('Entitlement__c', entitlementByEngagement.get(se.Id).Id);
    update engagements;
}

// ---------------------------------------------------------------- SLA clocks
// Subject -> Priority (what Case Priority Matrix gives for its Severity x Customer Impact), hours
// since the SLA clock started, and minutes to the first response (null = not answered yet).
Map<String, List<Object>> slaBySubject = new Map<String, List<Object>>{
    'Core router outage at Denver depot' => new List<Object>{ 'Critical', 5, 25 },
    'Fusion build crashes on legacy sensor feed' => new List<Object>{ 'High', 30, null },
    'VPN access for new logistics analysts' => new List<Object>{ 'Low', 26, 180 }
};
// The entitlement process starts from Case.SlaStartDate, so setting it with the entitlement backdates
// the clock; the milestones are created from it.
Datetime now = System.now();
List<Case> slaCases = new List<Case>();
Map<Id, Datetime> startById = new Map<Id, Datetime>();
for (Case c : cases) {
    if (c.IsClosed || !slaBySubject.containsKey(c.Subject)) continue;
    Datetime started = now.addHours(-(Integer) slaBySubject.get(c.Subject)[1]);
    startById.put(c.Id, started);
    slaCases.add(new Case(Id = c.Id, SlaStartDate = started,
        Priority = pv(Case.Priority, (String) slaBySubject.get(c.Subject)[0], 'High'),
        EntitlementId = entitlementByEngagement.get(c.Service_Engagement__c).Id));
}
update slaCases;

List<CaseMilestone> responses = new List<CaseMilestone>();
for (CaseMilestone m : [
    SELECT Id, CaseId, Case.Subject FROM CaseMilestone
    WHERE CaseId IN :startById.keySet() AND MilestoneType.Name = 'First Response' AND IsCompleted = false
]) {
    Object minutes = slaBySubject.get(m.Case.Subject)[2];
    if (minutes != null) {
        m.CompletionDate = startById.get(m.CaseId).addMinutes((Integer) minutes);
        responses.add(m);
    }
}
update responses;

// ---------------------------------------------------------------- Knowledge
// URL name, title, summary, details (HTML), and the case subject to attach it to (null = leave for the demo).
List<List<String>> articles = new List<List<String>>{
    new List<String>{ 'denali-core-router-outage-depot-failover', 'Core router outage at a depot: fail over to the backup path',
        'Restore a depot network after a core router failure by failing over to the LTE backup path while the router is replaced.',
        '<p><b>Symptoms:</b> the depot loses all WAN traffic; the NOC sees the core router unreachable.</p>'
        + '<p><b>Fix:</b> confirm the outage from two monitoring sources, then fail the site over to the LTE backup path '
        + '(runbook NOC-RB-07). Open a hardware RMA with the router vendor and schedule the replacement with the depot lead.</p>'
        + '<p><b>Customer update:</b> within 30 minutes for a Sev 1, then every hour until service is restored.</p>', null },
    new List<String>{ 'denali-fusion-build-legacy-sensor-feed', 'Fusion build crashes on a legacy sensor feed: use the feed adapter',
        'Sensor Fusion builds can crash on legacy sensor feeds that send the older message format. Route them through the feed adapter.',
        '<p><b>Symptoms:</b> the fusion service stops when a legacy sensor connects; logs show a message-format error.</p>'
        + '<p><b>Workaround:</b> route the legacy feed through the format adapter (config key <code>legacyAdapter=true</code>) '
        + 'until the build that parses the older format is accepted.</p>'
        + '<p><b>Next step:</b> link the case to the Sensor Fusion deliverable so delivery sees the impact.</p>', null },
    new List<String>{ 'denali-vpn-onboarding-new-analysts', 'VPN access for new analysts: onboarding checklist',
        'What we need from the customer before new analysts can be given VPN access.',
        '<p><b>We need from the customer:</b> each analyst\'s sponsor approval, completed security training, and a CAC or PIV certificate.</p>'
        + '<p><b>Then:</b> add the analysts to the VPN group and send connection instructions. Set the case to Waiting on Customer '
        + 'while approvals are outstanding: the SLA clock stops.</p>', 'VPN access for new logistics analysts' },
    new List<String>{ 'denali-monitoring-dashboard-stale-data', 'Monitoring dashboard showing stale data: restart the collector',
        'NOC dashboards stop updating when the metrics collector loses its configuration after a change.',
        '<p><b>Symptoms:</b> dashboard panels show the same values for more than 15 minutes.</p>'
        + '<p><b>Fix:</b> restore the collector configuration from the last known good version and restart the collector. '
        + 'Add the change to the configuration baseline so it is not lost again.</p>', 'Monitoring dashboard showing stale data' }
};

// Re-run: remove earlier copies (published ones are archived first).
Set<String> urlNames = new Set<String>();
for (List<String> a : articles) urlNames.add(a[0]);
for (Knowledge__kav old : [SELECT KnowledgeArticleId, PublishStatus FROM Knowledge__kav WHERE UrlName IN :urlNames AND PublishStatus IN ('Online', 'Draft')]) {
    if (old.PublishStatus == 'Online') {
        KbManagement.PublishingService.archiveOnlineArticle(old.KnowledgeArticleId, null);
        KbManagement.PublishingService.deleteArchivedArticle(old.KnowledgeArticleId);
    } else {
        KbManagement.PublishingService.deleteDraftArticle(old.KnowledgeArticleId);
    }
}

List<Knowledge__kav> drafts = new List<Knowledge__kav>();
for (List<String> a : articles) {
    Knowledge__kav k = new Knowledge__kav(UrlName = a[0], Title = a[1], Summary = a[2], Language = 'en_US');
    if (hasDetailsField) k.put('Details__c', a[3]);
    drafts.add(k);
}
insert drafts;

Map<String, Id> caseIdBySubject = new Map<String, Id>();
for (Case c : cases) caseIdBySubject.put(c.Subject, c.Id);
List<CaseArticle> attachments = new List<CaseArticle>();
for (Knowledge__kav k : [SELECT Id, KnowledgeArticleId, UrlName FROM Knowledge__kav WHERE Id IN :drafts]) {
    KbManagement.PublishingService.publishArticle(k.KnowledgeArticleId, true);
    for (List<String> a : articles) {
        if (a[0] == k.UrlName && a[4] != null && caseIdBySubject.containsKey(a[4])) {
            attachments.add(new CaseArticle(CaseId = caseIdBySubject.get(a[4]), KnowledgeArticleId = k.KnowledgeArticleId));
        }
    }
}
insert attachments;


System.debug(LoggingLevel.ERROR, 'Service Cloud seeded: ' + entitlementByEngagement.size() + ' entitlements, '
    + slaCases.size() + ' cases on SLA (' + responses.size() + ' first responses completed), '
    + drafts.size() + ' Knowledge articles published, ' + attachments.size() + ' attached.');
