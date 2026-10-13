// 05_seed_activity_history.apex
// Adds calls, emails, meetings and open tasks to the demo records, so Activity timelines on
// Accounts, Opportunities, Contacts, Projects and Deliverables tell the same story as the data:
// - Northwind: the Sensor Fusion build stalls on late government-furnished test data, escalates,
//   and a recovery plan review is booked.
// - Federal Logistics Command: Option Year 2 funding is uncertain, and the Denver router outage.
// - Aegis: the Zero Trust pursuit, from industry day to pricing below the margin floor.
// Run after 02 and 04. Re-runnable: it deletes the activities it created (matched by subject on
// the seeded accounts) and adds them again with dates relative to today. 99_reset removes them.
//
// - Activities are owned by the running user, so open tasks show up in their My Tasks.
// - CreatedDate can't be set, so timelines order by the activity date set here, not insert time.

// Description is a long text area, so SOQL can't filter on it; check the tag in Apex instead.
Set<Id> acctIds = new Set<Id>();
Map<String, Id> acct = new Map<String, Id>();
for (Account a : [SELECT Id, Name, Description FROM Account]) {
    if (a.Description != null && a.Description.contains('[demo-seed]')) {
        acctIds.add(a.Id);
        acct.put(a.Name, a.Id);
    }
}
if (acctIds.isEmpty()) {
    Assert.fail('Seeded Accounts not found. Run 02_seed_demo_data.apex first.');
}

Map<String, Id> ids = new Map<String, Id>();
for (Contact c : [SELECT Id, Name FROM Contact WHERE AccountId IN :acctIds]) ids.put(c.Name, c.Id);
for (Opportunity o : [SELECT Id, Name FROM Opportunity WHERE AccountId IN :acctIds]) ids.put(o.Name, o.Id);
for (Project__c p : [SELECT Id, Name FROM Project__c WHERE Account__c IN :acctIds]) ids.put(p.Name, p.Id);
for (Deliverable__c d : [SELECT Id, Name FROM Deliverable__c WHERE Project__r.Account__c IN :acctIds]) ids.put(d.Name, d.Id);
for (String name : acct.keySet()) ids.put(name, acct.get(name));

// Every activity this script creates, keyed by subject so a re-run can find and replace them.
// Columns: kind (Call, Email, Task, Meeting), subject, who (Contact), what (record), days from
// today, open (tasks only: not yet done), notes.
List<List<String>> plan = new List<List<String>>{
    // Northwind Defense Agency: Sensor Fusion slips on government-furnished test data
    new List<String>{ 'Meeting', 'Quarterly program review: Integrated Sensor Modernization', 'Marcus Reyes', 'Northwind Defense Agency', '-35', '',
        'Reviewed delivery against the award. Operator training on track. Raised the risk that government-furnished test data for the Sensor Fusion build may arrive late.' },
    new List<String>{ 'Call', 'Contract mod for additional sensor sites', 'Dana Whitfield', 'NDA - Integrated Sensor Modernization', '-28', '',
        'KO open to a scope mod for two additional sites next fiscal year. Wants a rough order of magnitude by end of quarter.' },
    new List<String>{ 'Email', 'Sensor Fusion Build 2.0: test data dependency', 'Marcus Reyes', 'Sensor Fusion Software Build 2.0', '-16', '',
        'Confirmed the build needs the government-furnished sensor test data set by the end of the month to hold the October 20 acceptance date.' },
    new List<String>{ 'Call', 'Weekly supplier sync: Sensor Fusion integration', 'Luis Ortega', 'Sensor Fusion Software Build 2.0', '-6', '',
        'Ironbridge reports no integration progress this week: still blocked on the test data. Holding at 60% complete.' },
    new List<String>{ 'Call', 'Escalation: government-furnished test data still outstanding', 'Marcus Reyes', 'Sensor Integration - Phase 1', '-3', '',
        'COR acknowledged the delay is on the government side. Agreed to review a recovery schedule; $900K acceptance milestone now at risk.' },
    new List<String>{ 'Task', 'Send Sensor Fusion recovery schedule to the COR', 'Marcus Reyes', 'Sensor Fusion Software Build 2.0', '1', 'open',
        'Show the revised forecast (November 24) and what the government needs to deliver for the build to recover.' },
    new List<String>{ 'Meeting', 'Sensor Fusion recovery plan review', 'Marcus Reyes', 'Sensor Integration - Phase 1', '2', '',
        'Walk the COR through the recovery schedule and agree a new acceptance date.' },
    new List<String>{ 'Task', 'Chase Technical Manual Set draft from the writing team', '', 'Technical Manual Set', '-2', 'open',
        'Draft is overdue; customer review window is shrinking.' },

    // Federal Logistics Command: Option Year 2 and the Denver outage
    new List<String>{ 'Email', 'Option Year 2 funding status', 'Priya Natarajan', 'FLC - Network Ops Option Year 2', '-10', '',
        'Contracting office says Option Year 2 funding depends on the continuing resolution. No commitment yet.' },
    new List<String>{ 'Call', 'Denver depot core router outage: status update', 'Tom Becker', 'Federal Logistics Command', '-2', '',
        'Sev 1 outage at the Denver depot. Replacement hardware shipping overnight; customer wants twice-daily updates until restored.' },
    new List<String>{ 'Task', 'Confirm Option Year 2 funding with the contracting office', 'Priya Natarajan', 'FLC - Network Ops Option Year 2', '-1', 'open',
        'Needed before the option exercise decision meeting.' },
    new List<String>{ 'Meeting', 'Option Year 2 exercise decision', 'Priya Natarajan', 'FLC - Network Ops Option Year 2', '5', '',
        'Customer decides whether to exercise Option Year 2. Bring the funding plan and the outage after-action report.' },

    // Aegis Program Office: the Zero Trust pursuit
    new List<String>{ 'Meeting', 'Zero Trust industry day debrief', 'Helen Cho', 'Aegis Program Office', '-30', '',
        'Aegis plans a production award after the prototype. Vantage Federal is the incumbent and expected to bid aggressively on price.' },
    new List<String>{ 'Call', 'Pricing discussion: Zero Trust Production', 'Helen Cho', 'Aegis - Zero Trust Production (FFP)', '-7', '',
        'Customer signalled a price ceiling. Our current price lands at 9%, below the 12% fixed-price margin floor.' },
    new List<String>{ 'Task', 'Finalize pricing rationale for the Zero Trust FFP bid', 'Helen Cho', 'Aegis - Zero Trust Production (FFP)', '3', 'open',
        'Needed for the Margin Exception approval before the bid goes to a proposal stage.' }
};

Set<String> subjects = new Set<String>();
for (List<String> row : plan) subjects.add(row[1]);
// Match on the related record too: a task on a Deliverable with no Contact has no AccountId.
Set<Id> seeded = new Set<Id>(ids.values());
delete [SELECT Id FROM Task WHERE Subject IN :subjects AND (AccountId IN :acctIds OR WhatId IN :seeded)];
delete [SELECT Id FROM Event WHERE Subject IN :subjects AND (AccountId IN :acctIds OR WhatId IN :seeded)];

Date today = Date.today();
List<Task> tasks = new List<Task>();
List<Event> events = new List<Event>();
List<String> skipped = new List<String>();
for (List<String> row : plan) {
    String kind = row[0], subject = row[1], notes = row[6];
    Id whoId = String.isBlank(row[2]) ? null : ids.get(row[2]);
    Id whatId = ids.get(row[3]);
    if (whatId == null || (String.isNotBlank(row[2]) && whoId == null)) {
        skipped.add(subject);   // e.g. 04 hasn't run, so the Zero Trust FFP deal doesn't exist
        continue;
    }
    Date day = today.addDays(Integer.valueOf(row[4]));
    if (kind == 'Meeting') {
        Datetime starts = Datetime.newInstance(day, Time.newInstance(10, 0, 0, 0));
        events.add(new Event(Subject = subject, WhoId = whoId, WhatId = whatId, StartDateTime = starts,
            EndDateTime = starts.addHours(1), Description = notes, Location = 'Microsoft Teams'));
    } else {
        Boolean open = row[5] == 'open';
        Task t = new Task(Subject = subject, WhoId = whoId, WhatId = whatId, ActivityDate = day,
            Description = notes, TaskSubtype = kind, Status = open ? 'Not Started' : 'Completed',
            Priority = open ? 'High' : 'Normal');
        if (kind == 'Call') {
            t.CallType = 'Outbound';
            t.CallDurationInSeconds = 1200;
        }
        tasks.add(t);
    }
}
insert tasks;
insert events;

System.debug(LoggingLevel.ERROR, 'Activity history: ' + tasks.size() + ' tasks, ' + events.size() + ' events.'
    + (skipped.isEmpty() ? '' : ' Skipped (record not found): ' + String.join(skipped, '; ')));
