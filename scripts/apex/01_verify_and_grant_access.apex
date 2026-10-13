// 01_verify_and_grant_access.apex
// Confirms every object and field from the metadata deploy exists, then assigns the
// Demo Data Model Access permission set to the running user, and makes a forecast-enabled General
// Manager the forecast manager of that role (for 11's quotas). Safe to re-run.
Map<String, List<String>> expected = new Map<String, List<String>>{
    'Account' => new List<String>{ 'Account_Role__c', 'Is_Customer__c', 'Is_Supplier__c', 'Is_Competitor__c', 'Account_Status__c', 'Customer_Tier__c', 'Customer_Health__c', 'Strategic_Account__c', 'Government_Account__c', 'Total_Contract_Value__c', 'Active_Contract_Value__c', 'Contract_Backlog__c', 'Active_Projects__c', 'At_Risk_Projects__c', 'Open_Deliverables__c', 'At_Risk_Deliverables__c', 'Open_Cases__c', 'Executive_Sponsor__c', 'Deals_Lost_To__c', 'Bookings_Lost_To__c' },
    'Contact' => new List<String>{ 'Contact_Role__c', 'Agency_Office__c', 'Preferred_Contact_Method__c', 'Portal_Access__c', 'Primary_Contact__c', 'Security_Clearance__c' },
    'Opportunity' => new List<String>{ 'Contract_Vehicle__c', 'Program_Type__c', 'Acquisition_Type__c', 'Prime_Subcontract__c', 'Contract_Type__c', 'Expected_Contract_Start__c', 'Expected_Contract_End__c', 'Estimated_Contract_Value__c', 'Incumbent__c', 'Competitive__c', 'Capture_Manager__c', 'Program_Manager__c', 'Customer_Priority__c', 'Estimated_Margin__c', 'Create_Contract_on_Win__c', 'Margin_Floor__c', 'Below_Margin_Floor__c', 'Margin_Approval_Status__c', 'Loss_Reason__c', 'Lost_To__c', 'Margin_Shortfall__c', 'Pricing_Rationale__c' },
    'Contract' => new List<String>{ 'Award_Number__c', 'Contract_Type__c', 'Acquisition_Type__c', 'Contract_Vehicle__c', 'Prime_Subcontract__c', 'Contract_Value__c', 'Funded_Value__c', 'Revenue_Recognized__c', 'Actual_Cost__c', 'Unfunded_Value__c', 'Funded_Backlog__c', 'Total_Backlog__c', 'Percent_Funded__c', 'Original_Margin__c', 'Current_Margin__c', 'Margin_Variance__c', 'Contract_Health__c', 'Contracting_Officer__c', 'COR__c', 'Program_Manager__c', 'Period_of_Performance__c', 'Current_Period__c', 'Next_Option_Date__c', 'Security_Requirement__c', 'Source_Opportunity__c', 'Revenue_Allocation__c', 'Forecast_Cost__c' },
    'Project__c' => new List<String>{ 'Project_Number__c', 'Contract__c', 'Account__c', 'Project_Manager__c', 'Status__c', 'Health__c', 'Start_Date__c', 'Target_End_Date__c', 'Actual_End_Date__c', 'Percent_Complete__c', 'Deliverable_Completion__c', 'Budget__c', 'Actual_Cost__c', 'Forecast_Cost__c', 'Cost_Variance__c', 'Budget_Variance__c', 'Revenue_Allocation__c', 'Revenue_Recognized__c', 'Revenue_at_Risk__c', 'Subcontracted_Value__c', 'Risk_Level__c', 'Open_Risks__c', 'Team_Size__c', 'Description__c', 'Customer_Sponsor__c', 'Internal_Sponsor__c', 'Deliverables__c', 'Deliverables_Complete__c', 'Deliverables_at_Risk__c', 'Bid_Margin__c', 'Forecast_Margin__c', 'Margin_Erosion__c', 'Subcontract_Share__c' },
    'Deliverable__c' => new List<String>{ 'Deliverable_Number__c', 'Project__c', 'Contract__c', 'Account__c', 'Deliverable_Type__c', 'Description__c', 'Status__c', 'Health__c', 'Priority__c', 'Percent_Complete__c', 'Planned_Start_Date__c', 'Due_Date__c', 'Forecast_Completion_Date__c', 'Actual_Completion_Date__c', 'Schedule_Variance_Days__c', 'Is_Overdue__c', 'Acceptance_Status__c', 'Acceptance_Date__c', 'Revenue_Milestone__c', 'Is_At_Risk__c', 'Revenue_at_Risk__c', 'Supplier__c', 'Blocker_Description__c', 'Requires_Customer_Action__c', 'Customer_Action_Description__c', 'Risk_Level__c', 'Risk_Description__c', 'Latest_Update_Date__c' },
    'Deliverable_Update__c' => new List<String>{ 'Deliverable__c', 'Project__c', 'Supplier__c', 'Submitted_By__c', 'Submitted_Date__c', 'Reported_Status__c', 'Percent_Complete__c', 'Forecast_Completion_Date__c', 'Progress_Summary__c', 'Blockers__c', 'Next_Steps__c', 'Requires_Customer_Action__c', 'Customer_Action__c', 'Supplier_Health__c', 'Internal_Review_Status__c', 'Reviewed_By__c', 'Review_Date__c', 'Reviewer_Comments__c' },
    'Supplier_Assignment__c' => new List<String>{ 'Project__c', 'Supplier__c', 'Role__c', 'Primary_Supplier__c', 'Responsibility__c', 'Start_Date__c', 'End_Date__c', 'Status__c', 'Supplier_Manager__c', 'Internal_Owner__c', 'Contract_Value__c', 'Performance_Rating__c', 'Notes__c' },
    'Project_Resource__c' => new List<String>{ 'Project__c', 'Employee__c', 'Role__c', 'Start_Date__c', 'End_Date__c', 'Allocation__c', 'Billable__c', 'Skill__c', 'Resource_Status__c', 'Manager__c', 'Unique_Key__c', 'Notes__c' },
    'Service_Engagement__c' => new List<String>{ 'Service_Number__c', 'Contract__c', 'Account__c', 'Service_Type__c', 'Status__c', 'Health__c', 'Service_Owner__c', 'Start_Date__c', 'End_Date__c', 'Monthly_Contract_Value__c', 'Annual_Contract_Value__c', 'Service_Level__c', 'Cases_Open__c', 'SLA_Breaches__c', 'Next_Milestone_Date__c', 'Customer_Satisfaction__c', 'Description__c', 'Primary_Contact__c' },
    'Engagement_Milestone__c' => new List<String>{ 'Service_Engagement__c', 'Contract__c', 'Account__c', 'Milestone_Type__c', 'Status__c', 'Health__c', 'Milestone_Owner__c', 'Planned_Date__c', 'Due_Date__c', 'Completion_Date__c', 'Slip_Days__c', 'Is_Overdue__c', 'Percent_Complete__c', 'Customer_Acceptance__c', 'Revenue_Impact__c', 'Description__c', 'Notes__c' },
    'Case' => new List<String>{ 'Service_Engagement__c', 'Project__c', 'Deliverable__c', 'Service_Type__c', 'Severity__c', 'Customer_Impact__c', 'Escalation_Reason__c', 'Escalation_Notes__c', 'Root_Cause__c', 'Resolution_Summary__c' },
    'Risk__c' => new List<String>{ 'Risk_Number__c', 'Account__c', 'Contract__c', 'Project__c', 'Deliverable__c', 'Risk_Category__c', 'Likelihood__c', 'Consequence__c', 'Risk_Score__c', 'Severity__c', 'Status__c', 'Risk_Owner__c', 'Identified_Date__c', 'Target_Resolution_Date__c', 'Closed_Date__c', 'Mitigation_Plan__c', 'Contingency_Plan__c', 'Revenue_at_Risk__c', 'Cost_Impact__c', 'Financial_Impact__c' }
};

Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
Integer missing = 0;
Integer checked = 0;
for (String obj : expected.keySet()) {
    Schema.SObjectType t = gd.get(obj.toLowerCase());
    if (t == null) {
        System.debug(LoggingLevel.ERROR, 'MISSING OBJECT: ' + obj);
        missing += expected.get(obj).size();
        continue;
    }
    Map<String, Schema.SObjectField> fm = t.getDescribe().fields.getMap();
    for (String f : expected.get(obj)) {
        checked++;
        if (!fm.containsKey(f.toLowerCase())) {
            System.debug(LoggingLevel.ERROR, 'MISSING FIELD: ' + obj + '.' + f);
            missing++;
        }
    }
}

// Optional pieces (separate deploy)
Boolean entitlementsOn = gd.containsKey('entitlement');
Boolean entitlementField = gd.get('service_engagement__c') != null &&
    gd.get('service_engagement__c').getDescribe().fields.getMap().containsKey('entitlement__c');
Boolean govStages = false;
for (Schema.PicklistEntry e : Opportunity.StageName.getDescribe().getPicklistValues()) {
    if (e.getValue() == 'Capture / Shaping' && e.isActive()) govStages = true;
}

// Grant access to the running user
List<PermissionSet> ps = [SELECT Id FROM PermissionSet WHERE Name = 'Demo_Data_Model_Access' LIMIT 1];
String accessMsg;
if (ps.isEmpty()) {
    accessMsg = 'Permission set Demo_Data_Model_Access NOT FOUND - deploy force-app first.';
} else if ([SELECT COUNT() FROM PermissionSetAssignment WHERE PermissionSetId = :ps[0].Id AND AssigneeId = :UserInfo.getUserId()] > 0) {
    accessMsg = 'Permission set already assigned to you.';
} else {
    insert new PermissionSetAssignment(PermissionSetId = ps[0].Id, AssigneeId = UserInfo.getUserId());
    accessMsg = 'Permission set assigned to you.';
}

// Forecast manager for the General Manager role (Setup -> Forecasts Hierarchy), so the GM's
// forecast and the quotas from 11_seed_forecast_quotas.apex show. Roles are setup records, which
// can't change in the same transaction as 11's quotas, so it happens here.
String forecastMsg = 'Forecast manager: skipped (no General Manager role, or no forecast-enabled user in it).';
List<UserRole> gmRoles = [SELECT Id, ForecastUserId FROM UserRole WHERE DeveloperName = 'General_Manager' LIMIT 1];
List<User> gms = gmRoles.isEmpty() ? new List<User>() : [SELECT Id, Name FROM User WHERE IsActive = true AND ForecastEnabled = true AND UserRoleId = :gmRoles[0].Id ORDER BY CreatedDate LIMIT 1];
if (!gms.isEmpty()) {
    if (gmRoles[0].ForecastUserId == null) {
        gmRoles[0].ForecastUserId = gms[0].Id;
        update gmRoles[0];
        forecastMsg = 'Forecast manager: ' + gms[0].Name + ' set for the General Manager role.';
    } else {
        forecastMsg = 'Forecast manager: already set for the General Manager role.';
    }
}

System.debug(LoggingLevel.ERROR, '===== VERIFY RESULT =====');
System.debug(LoggingLevel.ERROR, 'Fields checked: ' + checked + ' | missing: ' + missing);
System.debug(LoggingLevel.ERROR, 'Entitlement Management enabled: ' + entitlementsOn);
System.debug(LoggingLevel.ERROR, 'Optional Entitlement__c field deployed: ' + entitlementField);
System.debug(LoggingLevel.ERROR, 'Optional government Opportunity stages deployed: ' + govStages);
System.debug(LoggingLevel.ERROR, accessMsg);
System.debug(LoggingLevel.ERROR, forecastMsg);
