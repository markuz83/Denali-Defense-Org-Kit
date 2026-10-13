// 02_seed_demo_data.apex
// Seeds a connected demo story: 3 customers, 2 suppliers, 1 competitor, opportunities,
// awarded contracts, projects, deliverables, supplier updates, services, cases, and risks.
//
// - Every seeded Account is tagged "[demo-seed]" in Description so 99_reset can remove it all.
// - The flows aren't part of the metadata deploy, so this script fills the fields they would
//   (Account__c/Contract__c inheritance, stamps, etc.) itself.
// - Picklist values fall back to Salesforce defaults when the optional standard value sets
//   (government stages, case statuses, etc.) haven't been deployed.
// - Run 03_recalculate_rollups.apex afterwards to fill the rollup numbers.

// Returns `preferred` if it's an active value of the picklist, otherwise `fallback`.
String pv(Schema.SObjectField f, String preferred, String fallback) {
    for (Schema.PicklistEntry e : f.getDescribe().getPicklistValues()) {
        if (e.isActive() && e.getValue() == preferred) return preferred;
    }
    return fallback;
}

// Description is a long text area, so SOQL can't filter on it; check the tag in Apex instead.
for (Account a : [SELECT Description FROM Account]) {
    if (a.Description != null && a.Description.contains('[demo-seed]')) {
        Assert.fail('Demo data already exists. Run 99_reset_demo_data.apex first.');
    }
}

String TAG = ' [demo-seed]';
Date today = Date.today();
Id me = UserInfo.getUserId();

// ---------------------------------------------------------------- Accounts
Account army = new Account(Name = 'Northwind Defense Agency', Account_Role__c = 'Customer',
    Account_Status__c = 'Active', Customer_Tier__c = 'Strategic', Customer_Health__c = 'Yellow',
    Government_Account__c = true, Industry = pv(Account.Industry, 'Defense', 'Government'),
    BillingCity = 'Huntsville', Description = 'Fictional DoD program office.' + TAG);
Account logistics = new Account(Name = 'Federal Logistics Command', Account_Role__c = 'Customer',
    Account_Status__c = 'Active', Customer_Tier__c = 'Key', Customer_Health__c = 'Green',
    Government_Account__c = true, Industry = pv(Account.Industry, 'Federal Civilian', 'Government'),
    BillingCity = 'Arlington', Description = 'Fictional civilian agency.' + TAG);
Account aegis = new Account(Name = 'Aegis Program Office', Account_Role__c = 'Customer',
    Account_Status__c = 'Prospect', Customer_Tier__c = 'Standard',
    Government_Account__c = true, Industry = pv(Account.Industry, 'Intelligence Community', 'Government'),
    BillingCity = 'Chantilly', Description = 'Fictional prospect agency.' + TAG);
Account ironbridge = new Account(Name = 'Ironbridge Systems', Account_Role__c = 'Supplier;Partner',
    Account_Status__c = 'Active', Industry = pv(Account.Industry, 'Technology', 'Technology'),
    BillingCity = 'Tampa', Description = 'Fictional software subcontractor.' + TAG);
Account halcyon = new Account(Name = 'Halcyon Engineering', Account_Role__c = 'Supplier',
    Account_Status__c = 'Active', Industry = pv(Account.Industry, 'Manufacturing', 'Manufacturing'),
    BillingCity = 'Melbourne', Description = 'Fictional hardware supplier.' + TAG);
Account vantage = new Account(Name = 'Vantage Federal', Account_Role__c = 'Competitor',
    Account_Status__c = 'Active', Industry = pv(Account.Industry, 'Technology', 'Technology'),
    Description = 'Fictional competitor / incumbent.' + TAG);
insert new List<Account>{ army, logistics, aegis, ironbridge, halcyon, vantage };

// ---------------------------------------------------------------- Contacts
Contact ko = new Contact(FirstName = 'Dana', LastName = 'Whitfield', AccountId = army.Id,
    Title = 'Contracting Officer', Contact_Role__c = 'Contracting Officer', Agency_Office__c = 'NDA Contracting Directorate',
    Email = 'dana.whitfield@example.com', Preferred_Contact_Method__c = 'Email', Security_Clearance__c = 'Secret');
Contact cor = new Contact(FirstName = 'Marcus', LastName = 'Reyes', AccountId = army.Id,
    Title = 'Program Manager', Contact_Role__c = 'Program Manager;Contracting Officer\'s Representative',
    Agency_Office__c = 'PEO Integrated Systems', Email = 'marcus.reyes@example.com', Primary_Contact__c = true,
    Security_Clearance__c = 'Top Secret');
Contact logKo = new Contact(FirstName = 'Priya', LastName = 'Natarajan', AccountId = logistics.Id,
    Title = 'Contracting Officer', Contact_Role__c = 'Contracting Officer', Agency_Office__c = 'FLC Acquisition',
    Email = 'priya.natarajan@example.com', Primary_Contact__c = true);
Contact logTech = new Contact(FirstName = 'Tom', LastName = 'Becker', AccountId = logistics.Id,
    Title = 'IT Operations Lead', Contact_Role__c = 'Technical;Support', Email = 'tom.becker@example.com',
    Preferred_Contact_Method__c = 'Portal');
Contact aegisExec = new Contact(FirstName = 'Helen', LastName = 'Cho', AccountId = aegis.Id,
    Title = 'Deputy Director', Contact_Role__c = 'Executive', Email = 'helen.cho@example.com', Primary_Contact__c = true);
Contact ibPm = new Contact(FirstName = 'Luis', LastName = 'Ortega', AccountId = ironbridge.Id,
    Title = 'Delivery Manager', Contact_Role__c = 'Supplier Manager', Email = 'luis.ortega@example.com',
    Portal_Access__c = true, Preferred_Contact_Method__c = 'Portal', Primary_Contact__c = true);
Contact hcPm = new Contact(FirstName = 'Grace', LastName = 'Holloway', AccountId = halcyon.Id,
    Title = 'Program Lead', Contact_Role__c = 'Supplier Manager', Email = 'grace.holloway@example.com',
    Portal_Access__c = true, Preferred_Contact_Method__c = 'Portal', Primary_Contact__c = true);
insert new List<Contact>{ ko, cor, logKo, logTech, aegisExec, ibPm, hcPm };

// ---------------------------------------------------------------- Opportunities
String won = 'Closed Won';
String stageProposal = pv(Opportunity.StageName, 'Proposal Submitted', 'Proposal/Price Quote');
String stageCapture = pv(Opportunity.StageName, 'Capture / Shaping', 'Qualification');

Opportunity oppArmy = new Opportunity(Name = 'NDA - Integrated Sensor Modernization', AccountId = army.Id,
    StageName = won, CloseDate = today.addMonths(-8), Amount = 4200000, Estimated_Contract_Value__c = 12600000,
    Type = pv(Opportunity.Type, 'New Business', 'New Customer'), LeadSource = pv(Opportunity.LeadSource, 'SAM.gov', null),
    Contract_Vehicle__c = 'IDIQ', Acquisition_Type__c = 'Competitive', Prime_Subcontract__c = 'Prime',
    Contract_Type__c = 'Fixed Price', Program_Type__c = 'Production', Incumbent__c = vantage.Id,
    Expected_Contract_Start__c = today.addMonths(-7), Expected_Contract_End__c = today.addMonths(29),
    Capture_Manager__c = me, Program_Manager__c = me, Customer_Priority__c = 'High', Estimated_Margin__c = 18);
Opportunity oppLog = new Opportunity(Name = 'FLC - Managed Network Operations', AccountId = logistics.Id,
    StageName = won, CloseDate = today.addMonths(-14), Amount = 1800000, Estimated_Contract_Value__c = 5400000,
    Type = pv(Opportunity.Type, 'Recompete', 'Existing Customer - Replacement'),
    Contract_Vehicle__c = 'GSA Schedule', Acquisition_Type__c = 'Follow-On', Prime_Subcontract__c = 'Prime',
    Contract_Type__c = 'Time & Materials', Program_Type__c = 'Sustainment',
    Expected_Contract_Start__c = today.addMonths(-13), Expected_Contract_End__c = today.addMonths(23),
    Capture_Manager__c = me, Program_Manager__c = me, Customer_Priority__c = 'Medium', Estimated_Margin__c = 22);
Opportunity oppLogOpt = new Opportunity(Name = 'FLC - Network Ops Option Year 2', AccountId = logistics.Id,
    StageName = stageProposal, CloseDate = today.addMonths(2).addDays(-14), Amount = 1850000, Estimated_Contract_Value__c = 1850000,   // before FLC-2025-014's option date
    Type = pv(Opportunity.Type, 'Option Exercise', 'Existing Customer - Upgrade'),
    Contract_Vehicle__c = 'GSA Schedule', Acquisition_Type__c = 'Sole Source', Prime_Subcontract__c = 'Prime',
    Contract_Type__c = 'Time & Materials', Program_Manager__c = me, Customer_Priority__c = 'High', Estimated_Margin__c = 21);
Opportunity oppAegis = new Opportunity(Name = 'Aegis - Zero Trust Prototype (OTA)', AccountId = aegis.Id,
    StageName = stageCapture, CloseDate = today.addMonths(6), Amount = 950000, Estimated_Contract_Value__c = 3100000,
    Type = pv(Opportunity.Type, 'New Business', 'New Customer'), LeadSource = pv(Opportunity.LeadSource, 'Industry Day', null),
    Contract_Vehicle__c = 'Direct Contract', Acquisition_Type__c = 'OTA', Prime_Subcontract__c = 'Prime',
    Contract_Type__c = 'Cost Plus', Program_Type__c = 'Prototype', Incumbent__c = vantage.Id,
    Capture_Manager__c = me, Customer_Priority__c = 'Critical', Estimated_Margin__c = 15);
insert new List<Opportunity>{ oppArmy, oppLog, oppLogOpt, oppAegis };

// ---------------------------------------------------------------- Contracts (what Flow #1 would create)
Contract kArmy = new Contract(AccountId = army.Id, Status = 'Draft', StartDate = today.addMonths(-7), ContractTerm = 36,
    Award_Number__c = 'NDA-2026-001', Contract_Type__c = 'Fixed Price', Acquisition_Type__c = 'Competitive',
    Contract_Vehicle__c = 'IDIQ', Prime_Subcontract__c = 'Prime', Contract_Value__c = 12600000, Funded_Value__c = 5200000,
    Original_Margin__c = 18, Contract_Health__c = 'Yellow', Contracting_Officer__c = ko.Id, COR__c = cor.Id,
    Program_Manager__c = me, Current_Period__c = 'Base', Next_Option_Date__c = today.addMonths(5),
    Security_Requirement__c = 'CUI', Source_Opportunity__c = oppArmy.Id, Description = 'Sensor modernization production award.');
Contract kLog = new Contract(AccountId = logistics.Id, Status = 'Draft', StartDate = today.addMonths(-13), ContractTerm = 36,
    Award_Number__c = 'FLC-2025-014', Contract_Type__c = 'Time & Materials', Acquisition_Type__c = 'Follow-On',
    Contract_Vehicle__c = 'GSA Schedule', Prime_Subcontract__c = 'Prime', Contract_Value__c = 5400000, Funded_Value__c = 3600000,
    Original_Margin__c = 22, Contract_Health__c = 'Green', Contracting_Officer__c = logKo.Id,
    Program_Manager__c = me, Current_Period__c = 'Option Year 1', Next_Option_Date__c = today.addMonths(2),
    Security_Requirement__c = 'None', Source_Opportunity__c = oppLog.Id, Description = 'Managed network operations recompete.');
insert new List<Contract>{ kArmy, kLog };
kArmy.Status = 'Activated';
kLog.Status = 'Activated';
update new List<Contract>{ kArmy, kLog };
// Option Year 2 is a renewal of the FLC contract; linking it stops the Renewal Opp flow (#13) creating a duplicate.
update new Opportunity(Id = oppLogOpt.Id, ContractId = kLog.Id);

// ---------------------------------------------------------------- Projects
Project__c pSensor = new Project__c(Name = 'Sensor Integration - Phase 1', Contract__c = kArmy.Id, Account__c = army.Id,
    Project_Manager__c = me, Internal_Sponsor__c = me, Customer_Sponsor__c = cor.Id, Status__c = 'In Progress',
    Health__c = 'Yellow', Risk_Level__c = 'High', Start_Date__c = today.addMonths(-6), Target_End_Date__c = today.addMonths(6),
    Percent_Complete__c = 55, Budget__c = 2400000, Actual_Cost__c = 1450000, Forecast_Cost__c = 2620000,
    Revenue_Allocation__c = 3100000, Description__c = 'Integrate next-gen sensors into existing ground stations.');
Project__c pTraining = new Project__c(Name = 'Operator Training & Documentation', Contract__c = kArmy.Id, Account__c = army.Id,
    Project_Manager__c = me, Customer_Sponsor__c = cor.Id, Status__c = 'In Progress', Health__c = 'Green',
    Risk_Level__c = 'Low', Start_Date__c = today.addMonths(-3), Target_End_Date__c = today.addMonths(4),
    Percent_Complete__c = 40, Budget__c = 600000, Actual_Cost__c = 210000, Forecast_Cost__c = 580000,
    Revenue_Allocation__c = 820000);
Project__c pNoc = new Project__c(Name = 'NOC Tooling Refresh', Contract__c = kLog.Id, Account__c = logistics.Id,
    Project_Manager__c = me, Customer_Sponsor__c = logTech.Id, Status__c = 'Complete', Health__c = 'Green',
    Risk_Level__c = 'Low', Start_Date__c = today.addMonths(-12), Target_End_Date__c = today.addMonths(-4),
    Actual_End_Date__c = today.addMonths(-4), Percent_Complete__c = 100, Budget__c = 450000, Actual_Cost__c = 430000,
    Forecast_Cost__c = 430000, Revenue_Allocation__c = 540000);
insert new List<Project__c>{ pSensor, pTraining, pNoc };

// ---------------------------------------------------------------- Deliverables (Flow #3 inheritance done here)
List<Deliverable__c> dels = new List<Deliverable__c>{
    new Deliverable__c(Name = 'CDRL A001 - System Design Document', Project__c = pSensor.Id, Contract__c = kArmy.Id,
        Account__c = army.Id, Deliverable_Type__c = 'Documentation', Status__c = 'Complete', Health__c = 'Green',
        Priority__c = 'High', Percent_Complete__c = 100, Due_Date__c = today.addMonths(-4),
        Forecast_Completion_Date__c = today.addMonths(-4), Actual_Completion_Date__c = today.addMonths(-4).addDays(-3),
        Acceptance_Status__c = 'Accepted', Acceptance_Date__c = today.addMonths(-4).addDays(5),
        Revenue_Milestone__c = 450000, Supplier__c = ironbridge.Id, Risk_Level__c = 'Low'),
    new Deliverable__c(Name = 'Sensor Fusion Software Build 2.0', Project__c = pSensor.Id, Contract__c = kArmy.Id,
        Account__c = army.Id, Deliverable_Type__c = 'Software', Status__c = 'Blocked', Health__c = 'Red',
        Priority__c = 'Critical', Percent_Complete__c = 60, Due_Date__c = today.addDays(20),
        Forecast_Completion_Date__c = today.addDays(55), Acceptance_Status__c = 'Not Submitted',
        Revenue_Milestone__c = 900000, Supplier__c = ironbridge.Id, Risk_Level__c = 'Critical',
        Blocker_Description__c = 'Waiting on government-furnished test data set.',
        Requires_Customer_Action__c = true, Customer_Action_Description__c = 'Provide GFI test data package (CDRL A004).',
        Risk_Description__c = 'Build slip threatens the Phase 1 acceptance milestone.'),
    new Deliverable__c(Name = 'Ground Station Hardware Kit (x12)', Project__c = pSensor.Id, Contract__c = kArmy.Id,
        Account__c = army.Id, Deliverable_Type__c = 'Hardware', Status__c = 'In Progress', Health__c = 'Yellow',
        Priority__c = 'High', Percent_Complete__c = 45, Due_Date__c = today.addMonths(2),
        Forecast_Completion_Date__c = today.addMonths(2).addDays(10), Acceptance_Status__c = 'Not Submitted',
        Revenue_Milestone__c = 1200000, Supplier__c = halcyon.Id, Risk_Level__c = 'Medium'),
    new Deliverable__c(Name = 'Integration Test Report', Project__c = pSensor.Id, Contract__c = kArmy.Id,
        Account__c = army.Id, Deliverable_Type__c = 'Testing', Status__c = 'Not Started', Health__c = 'Green',
        Priority__c = 'Medium', Percent_Complete__c = 0, Due_Date__c = today.addMonths(5),
        Forecast_Completion_Date__c = today.addMonths(5), Acceptance_Status__c = 'Not Submitted',
        Revenue_Milestone__c = 300000, Risk_Level__c = 'Low'),
    new Deliverable__c(Name = 'Operator Training Curriculum', Project__c = pTraining.Id, Contract__c = kArmy.Id,
        Account__c = army.Id, Deliverable_Type__c = 'Training', Status__c = 'Submitted', Health__c = 'Green',
        Priority__c = 'Medium', Percent_Complete__c = 90, Due_Date__c = today.addDays(10),
        Forecast_Completion_Date__c = today.addDays(7), Acceptance_Status__c = 'Pending Review',
        Revenue_Milestone__c = 250000, Risk_Level__c = 'Low'),
    new Deliverable__c(Name = 'Technical Manual Set', Project__c = pTraining.Id, Contract__c = kArmy.Id,
        Account__c = army.Id, Deliverable_Type__c = 'Documentation', Status__c = 'In Progress', Health__c = 'Yellow',
        Priority__c = 'Medium', Percent_Complete__c = 35, Due_Date__c = today.addDays(-5),
        Forecast_Completion_Date__c = today.addDays(25), Acceptance_Status__c = 'Not Submitted',
        Revenue_Milestone__c = 180000, Supplier__c = ironbridge.Id, Risk_Level__c = 'Medium'),
    new Deliverable__c(Name = 'Monitoring Platform Cutover', Project__c = pNoc.Id, Contract__c = kLog.Id,
        Account__c = logistics.Id, Deliverable_Type__c = 'Integration', Status__c = 'Complete', Health__c = 'Green',
        Priority__c = 'High', Percent_Complete__c = 100, Due_Date__c = today.addMonths(-5),
        Forecast_Completion_Date__c = today.addMonths(-5), Actual_Completion_Date__c = today.addMonths(-5),
        Acceptance_Status__c = 'Accepted', Acceptance_Date__c = today.addMonths(-5).addDays(7),
        Revenue_Milestone__c = 540000, Supplier__c = halcyon.Id, Risk_Level__c = 'Low')
};
insert dels;
Deliverable__c dDesign = dels[0], dSoftware = dels[1], dHardware = dels[2], dManual = dels[5];

// ---------------------------------------------------------------- Deliverable Updates (supplier submissions)
insert new List<Deliverable_Update__c>{
    new Deliverable_Update__c(Deliverable__c = dSoftware.Id, Project__c = pSensor.Id, Supplier__c = ironbridge.Id,
        Submitted_By__c = ibPm.Id, Submitted_Date__c = System.now().addDays(-14), Reported_Status__c = 'In Progress',
        Percent_Complete__c = 60, Forecast_Completion_Date__c = today.addDays(30), Supplier_Health__c = 'Yellow',
        Progress_Summary__c = 'Core fusion algorithms complete; UI integration underway.',
        Next_Steps__c = 'Begin system integration once GFI test data arrives.',
        Internal_Review_Status__c = 'Accepted', Reviewed_By__c = me, Review_Date__c = today.addDays(-12)),
    new Deliverable_Update__c(Deliverable__c = dSoftware.Id, Project__c = pSensor.Id, Supplier__c = ironbridge.Id,
        Submitted_By__c = ibPm.Id, Submitted_Date__c = System.now().addDays(-2), Reported_Status__c = 'Blocked',
        Percent_Complete__c = 60, Forecast_Completion_Date__c = today.addDays(55), Supplier_Health__c = 'Red',
        Progress_Summary__c = 'No progress on integration this week.',
        Blockers__c = 'Government-furnished test data still not received.',
        Requires_Customer_Action__c = true, Customer_Action__c = 'Deliver GFI test data package.',
        Internal_Review_Status__c = 'Pending'),
    new Deliverable_Update__c(Deliverable__c = dHardware.Id, Project__c = pSensor.Id, Supplier__c = halcyon.Id,
        Submitted_By__c = hcPm.Id, Submitted_Date__c = System.now().addDays(-3), Reported_Status__c = 'In Progress',
        Percent_Complete__c = 45, Forecast_Completion_Date__c = today.addMonths(2).addDays(10), Supplier_Health__c = 'Yellow',
        Progress_Summary__c = '5 of 12 kits assembled; connector lead times slipping.',
        Internal_Review_Status__c = 'Needs Clarification', Reviewed_By__c = me, Review_Date__c = today.addDays(-1),
        Reviewer_Comments__c = 'Please confirm whether the connector delay affects the kit ship date.'),
    new Deliverable_Update__c(Deliverable__c = dManual.Id, Project__c = pTraining.Id, Supplier__c = ironbridge.Id,
        Submitted_By__c = ibPm.Id, Submitted_Date__c = System.now().addDays(-1), Reported_Status__c = 'In Progress',
        Percent_Complete__c = 35, Forecast_Completion_Date__c = today.addDays(25), Supplier_Health__c = 'Yellow',
        Progress_Summary__c = 'Volumes 1-2 drafted; volume 3 waiting on final hardware photos.',
        Internal_Review_Status__c = 'Pending')
};

// ---------------------------------------------------------------- Supplier Assignments & Project Resources
insert new List<Supplier_Assignment__c>{
    new Supplier_Assignment__c(Project__c = pSensor.Id, Supplier__c = ironbridge.Id, Role__c = 'Subcontractor',
        Primary_Supplier__c = true, Status__c = 'Active', Start_Date__c = today.addMonths(-6), End_Date__c = today.addMonths(6),
        Supplier_Manager__c = ibPm.Id, Internal_Owner__c = me, Contract_Value__c = 780000,
        Performance_Rating__c = 'Satisfactory', Responsibility__c = 'Sensor fusion software and design documentation.'),
    new Supplier_Assignment__c(Project__c = pSensor.Id, Supplier__c = halcyon.Id, Role__c = 'Hardware Supplier',
        Status__c = 'Active', Start_Date__c = today.addMonths(-5), End_Date__c = today.addMonths(4),
        Supplier_Manager__c = hcPm.Id, Internal_Owner__c = me, Contract_Value__c = 640000,
        Performance_Rating__c = 'Very Good', Responsibility__c = 'Ground station hardware kits.'),
    new Supplier_Assignment__c(Project__c = pTraining.Id, Supplier__c = ironbridge.Id, Role__c = 'Professional Services',
        Status__c = 'Active', Start_Date__c = today.addMonths(-3), End_Date__c = today.addMonths(4),
        Supplier_Manager__c = ibPm.Id, Internal_Owner__c = me, Contract_Value__c = 150000,
        Responsibility__c = 'Technical manual authoring.'),
    new Supplier_Assignment__c(Project__c = pNoc.Id, Supplier__c = halcyon.Id, Role__c = 'Engineering Partner',
        Status__c = 'Completed', Start_Date__c = today.addMonths(-12), End_Date__c = today.addMonths(-4),
        Supplier_Manager__c = hcPm.Id, Internal_Owner__c = me, Contract_Value__c = 120000,
        Performance_Rating__c = 'Exceptional')
};
List<Project_Resource__c> res = new List<Project_Resource__c>();
for (Project__c p : new List<Project__c>{ pSensor, pTraining, pNoc }) {
    Boolean done = p.Status__c == 'Complete';
    res.add(new Project_Resource__c(Project__c = p.Id, Employee__c = me, Role__c = 'Project Manager',
        Start_Date__c = p.Start_Date__c, End_Date__c = p.Target_End_Date__c, Allocation__c = done ? 0 : 40,
        Billable__c = true, Skill__c = 'Program management', Resource_Status__c = done ? 'Rolled Off' : 'Active',
        Unique_Key__c = String.valueOf(p.Id) + String.valueOf(me)));
}
insert res;

// ---------------------------------------------------------------- Service Engagements & Milestones
Service_Engagement__c seNoc = new Service_Engagement__c(Name = 'FLC Network Operations Support', Contract__c = kLog.Id,
    Account__c = logistics.Id, Service_Type__c = 'Managed Services', Status__c = 'Active', Health__c = 'Green',
    Service_Owner__c = me, Start_Date__c = today.addMonths(-13), End_Date__c = today.addMonths(23),
    Monthly_Contract_Value__c = 150000, Service_Level__c = 'Gold', Customer_Satisfaction__c = 4.4,
    Primary_Contact__c = logTech.Id, Description__c = '24x7 NOC monitoring and incident response.');
Service_Engagement__c seSustain = new Service_Engagement__c(Name = 'NDA Sensor Sustainment', Contract__c = kArmy.Id,
    Account__c = army.Id, Service_Type__c = 'Sustainment', Status__c = 'Active', Health__c = 'Yellow',
    Service_Owner__c = me, Start_Date__c = today.addMonths(-2), End_Date__c = today.addMonths(29),
    Monthly_Contract_Value__c = 60000, Service_Level__c = 'Platinum', Customer_Satisfaction__c = 3.8,
    Primary_Contact__c = cor.Id);
insert new List<Service_Engagement__c>{ seNoc, seSustain };

insert new List<Engagement_Milestone__c>{
    new Engagement_Milestone__c(Name = 'Q3 Service Review', Service_Engagement__c = seNoc.Id, Contract__c = kLog.Id,
        Account__c = logistics.Id, Milestone_Type__c = 'Monthly Review', Status__c = 'Complete', Health__c = 'Green',
        Milestone_Owner__c = me, Planned_Date__c = today.addDays(-20), Due_Date__c = today.addDays(-20),
        Completion_Date__c = today.addDays(-20), Percent_Complete__c = 100, Customer_Acceptance__c = 'Accepted'),
    new Engagement_Milestone__c(Name = 'Annual SLA Review', Service_Engagement__c = seNoc.Id, Contract__c = kLog.Id,
        Account__c = logistics.Id, Milestone_Type__c = 'SLA Review', Status__c = 'Scheduled', Health__c = 'Green',
        Milestone_Owner__c = me, Planned_Date__c = today.addDays(30), Due_Date__c = today.addDays(30)),
    new Engagement_Milestone__c(Name = 'Option Year 2 Renewal Decision', Service_Engagement__c = seNoc.Id,
        Contract__c = kLog.Id, Account__c = logistics.Id, Milestone_Type__c = 'Renewal', Status__c = 'In Progress',
        Health__c = 'Yellow', Milestone_Owner__c = me, Planned_Date__c = today.addDays(45), Due_Date__c = today.addDays(60),
        Percent_Complete__c = 30, Revenue_Impact__c = 1850000),
    new Engagement_Milestone__c(Name = 'Sustainment Readiness Assessment', Service_Engagement__c = seSustain.Id,
        Contract__c = kArmy.Id, Account__c = army.Id, Milestone_Type__c = 'Readiness Assessment', Status__c = 'In Progress',
        Health__c = 'Yellow', Milestone_Owner__c = me, Planned_Date__c = today.addDays(-10), Due_Date__c = today.addDays(-3),
        Percent_Complete__c = 70)
};

// ---------------------------------------------------------------- Cases
String sNew = pv(Case.Status, 'New', 'New');
String sWorking = pv(Case.Status, 'Working', 'Working');
String sWaitCust = pv(Case.Status, 'Waiting on Customer', sWorking);
String sClosed = 'Closed';
String tIncident = pv(Case.Type, 'Incident', 'Other');
String tRequest = pv(Case.Type, 'Service Request', 'Other');
String pCritical = pv(Case.Priority, 'Critical', 'High');
String oPortal = pv(Case.Origin, 'Portal', 'Web');

insert new List<Case>{
    new Case(Subject = 'Core router outage at Denver depot', AccountId = logistics.Id, ContactId = logTech.Id,
        Service_Engagement__c = seNoc.Id, Status = sWorking, Priority = pCritical, Origin = pv(Case.Origin, 'Phone', 'Phone'),
        Type = tIncident, Reason = pv(Case.Reason, 'Outage', null), Severity__c = 'Sev 1 - Critical Outage',
        Customer_Impact__c = 'Site / Program', IsEscalated = true, Escalation_Reason__c = 'SLA Risk',
        Escalation_Notes__c = 'Depot shipping halted; customer PM requested hourly updates.',
        Description = 'All traffic down at the Denver depot since 06:10 local.'),
    new Case(Subject = 'VPN access for new logistics analysts', AccountId = logistics.Id, ContactId = logTech.Id,
        Service_Engagement__c = seNoc.Id, Status = sWaitCust, Priority = 'Low', Origin = oPortal,
        Type = tRequest, Reason = pv(Case.Reason, 'Access Request', null), Severity__c = 'Sev 4 - Informational / Request',
        Customer_Impact__c = 'Multiple Users'),
    new Case(Subject = 'Monitoring dashboard showing stale data', AccountId = logistics.Id, ContactId = logTech.Id,
        Service_Engagement__c = seNoc.Id, Status = sClosed, Priority = 'Medium', Origin = oPortal,
        Type = tIncident, Reason = pv(Case.Reason, 'Degraded Performance', null), Severity__c = 'Sev 3 - Minor Issue',
        Customer_Impact__c = 'Multiple Users', Root_Cause__c = 'Configuration',
        Resolution_Summary__c = 'Collector polling interval reset after the platform patch; restored defaults.'),
    new Case(Subject = 'Fusion build crashes on legacy sensor feed', AccountId = army.Id, ContactId = cor.Id,
        Service_Engagement__c = seSustain.Id, Project__c = pSensor.Id, Deliverable__c = dSoftware.Id,
        Status = sNew, Priority = 'High', Origin = pv(Case.Origin, 'Email', 'Email'), Type = tIncident,
        Reason = pv(Case.Reason, 'Degraded Performance', null), Severity__c = 'Sev 2 - Major Degradation',
        Customer_Impact__c = 'Site / Program',
        Description = 'Build 1.9 crashes when ingesting the legacy radar feed during field testing.')
};

// ---------------------------------------------------------------- Risks (Flow #10 / #11 results)
insert new List<Risk__c>{
    new Risk__c(Name = 'GFI test data late', Account__c = army.Id, Contract__c = kArmy.Id, Project__c = pSensor.Id,
        Deliverable__c = dSoftware.Id, Risk_Category__c = 'Customer', Likelihood__c = '5 - Near Certainty',
        Consequence__c = '4 - Significant', Status__c = 'Mitigating', Risk_Owner__c = me,
        Identified_Date__c = today.addDays(-21), Target_Resolution_Date__c = today.addDays(14),
        Mitigation_Plan__c = 'Weekly escalation with the COR; build synthetic test harness in parallel.',
        Revenue_at_Risk__c = 900000, Cost_Impact__c = 85000),
    new Risk__c(Name = 'Connector supply chain delay', Account__c = army.Id, Contract__c = kArmy.Id, Project__c = pSensor.Id,
        Deliverable__c = dHardware.Id, Risk_Category__c = 'Supplier', Likelihood__c = '3 - Likely',
        Consequence__c = '3 - Moderate', Status__c = 'Monitoring', Risk_Owner__c = me,
        Identified_Date__c = today.addDays(-10), Target_Resolution_Date__c = today.addDays(30),
        Contingency_Plan__c = 'Qualify alternate connector vendor.', Cost_Impact__c = 40000),
    new Risk__c(Name = 'Key engineer attrition', Account__c = army.Id, Contract__c = kArmy.Id, Project__c = pTraining.Id,
        Risk_Category__c = 'Staffing', Likelihood__c = '2 - Low Likelihood', Consequence__c = '3 - Moderate',
        Status__c = 'Identified', Risk_Owner__c = me),
    new Risk__c(Name = 'Option Year 2 funding uncertainty', Account__c = logistics.Id, Contract__c = kLog.Id,
        Risk_Category__c = 'Cost', Likelihood__c = '3 - Likely', Consequence__c = '5 - Severe', Status__c = 'Analyzing',
        Risk_Owner__c = me, Mitigation_Plan__c = 'Brief CO on continuity of operations; prepare bridge options.',
        Revenue_at_Risk__c = 1850000)
};

System.debug(LoggingLevel.ERROR, 'Demo data seeded. Next: run 03_recalculate_rollups.apex.');
