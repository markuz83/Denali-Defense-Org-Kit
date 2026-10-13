// 08_seed_objective_action_plans.apex
// Puts an Action Plan on the account plan objectives from 06, so each objective has the concrete
// steps behind it as tasks with due dates:
// - Recovery Plan: Northwind "Recover Sensor Fusion Build 2.0" and FLC "Restore network reliability".
// - Account Growth: Northwind "Grow task-order revenue on the IDIQ".
// - Option Exercise: FLC "Secure Option Year 2".
// - Capture Plan: Aegis "Win Zero Trust Production" (color-team reviews against Vantage Federal).
// - Margin Exception: Aegis "Price at or above the margin floor".
//
// - Needs Action Plans and Sales Account Plans. Run after 06.
// - Creates and publishes the five Action Plan templates the first time (matched by Unique Name
//   "Denali_…"), and reuses them after that. Published templates can't be edited; to change one,
//   mark its version Obsolete, delete the template, and re-run.
// - Salesforce generates each plan's tasks when the plan is created, owned by the running user and
//   due relative to today.
// - Re-runnable: replaces the action plans (and their tasks) on these objectives. 06 and 99 remove
//   them too; the templates stay.

// Columns: unique name, label, description, then task groups of subject / days after start / priority
List<List<String>> templates = new List<List<String>>{
    new List<String>{ 'Denali_Recovery_Plan', 'Recovery Plan',
        'Get a slipped deliverable or service back on track with the customer.',
        'Confirm the root cause and an owner with the customer', '2', 'High',
        'Agree a recovery schedule with the COR', '5', 'High',
        'Re-baseline the supplier or team plan', '7', 'Normal',
        'Send weekly recovery status to the customer', '14', 'Normal',
        'Confirm recovery and record lessons learned', '30', 'Normal' },
    new List<String>{ 'Denali_Account_Growth', 'Account Growth',
        'Grow an existing customer through task orders and contract modifications.',
        'Hold a quarterly business review with the program office', '14', 'Normal',
        'Map upcoming task orders on the contract vehicle', '21', 'Normal',
        'Send a rough order of magnitude for the scope modification', '30', 'High',
        'Brief the capture team on new requirements', '45', 'Normal' },
    new List<String>{ 'Denali_Option_Exercise', 'Option Exercise',
        'Get a contract option exercised on time.',
        'Confirm option funding with the contracting office', '5', 'High',
        'Send a performance summary to the COR', '10', 'Normal',
        'Confirm option pricing and period of performance', '15', 'Normal',
        'Prepare for the option decision meeting', '20', 'High',
        'Update the contract once the option is exercised', '30', 'Normal' },
    new List<String>{ 'Denali_Capture_Plan', 'Capture Plan',
        'Win a competitive pursuit: competitor review, price-to-win, bid decision and color-team reviews.',
        'Run a black hat review of the incumbent', '7', 'Normal',
        'Complete the price-to-win analysis', '10', 'High',
        'Hold the bid / no-bid review', '14', 'High',
        'Pink team review', '21', 'Normal',
        'Red team review', '30', 'Normal',
        'Gold team review and submit the proposal', '35', 'High' },
    new List<String>{ 'Denali_Margin_Exception', 'Margin Exception',
        'Get pricing below the margin floor approved, or bring it back above the floor.',
        'Regenerate the pricing rationale with Einstein', '1', 'Normal',
        'Submit the opportunity for Pricing Review', '2', 'High',
        'Review the margin shortfall with the approver', '5', 'Normal',
        'Record the decision and update the price', '7', 'Normal' }
};

// Which objective (from 06) gets which template.
Map<String, String> templateFor = new Map<String, String>{
    'Recover Sensor Fusion Build 2.0' => 'Denali_Recovery_Plan',
    'Restore network reliability' => 'Denali_Recovery_Plan',
    'Grow task-order revenue on the IDIQ' => 'Denali_Account_Growth',
    'Secure Option Year 2' => 'Denali_Option_Exercise',
    'Win Zero Trust Production' => 'Denali_Capture_Plan',
    'Price at or above the margin floor' => 'Denali_Margin_Exception'
};

// Description is a long text area, so SOQL can't filter on it; check the tag in Apex instead.
Set<Id> acctIds = new Set<Id>();
for (Account a : [SELECT Id, Description FROM Account]) {
    if (a.Description != null && a.Description.contains('[demo-seed]')) acctIds.add(a.Id);
}
List<AccountPlanObjective> objectives = [SELECT Id, Name FROM AccountPlanObjective
                                         WHERE AccountPlan.AccountId IN :acctIds AND Name IN :templateFor.keySet()];
if (objectives.isEmpty()) {
    Assert.fail('Account plan objectives not found. Run 06_seed_account_plans.apex first.');
}

// ---------------------------------------------------------------- Templates (create once, then reuse)
Map<String, Id> versionFor = new Map<String, Id>();
for (ActionPlanTemplateVersion v : [SELECT Id, ActionPlanTemplate.UniqueName FROM ActionPlanTemplateVersion
                                    WHERE Status = 'Final' AND ActionPlanTemplate.UniqueName LIKE 'Denali_%'
                                    ORDER BY Version]) {
    versionFor.put(v.ActionPlanTemplate.UniqueName, v.Id);   // latest published version wins
}
Integer created = 0;
for (List<String> t : templates) {
    if (versionFor.containsKey(t[0])) continue;
    ActionPlanTemplate template = new ActionPlanTemplate(UniqueName = t[0], Name = t[1], Description = t[2],
        TargetEntityType = 'AccountPlanObjective', ActionPlanType = 'Sales');
    insert template;
    ActionPlanTemplateVersion version = [SELECT Id FROM ActionPlanTemplateVersion WHERE ActionPlanTemplateId = :template.Id LIMIT 1];
    List<ActionPlanTemplateItem> items = new List<ActionPlanTemplateItem>();
    Integer taskCount = (t.size() - 3) / 3;   // subject, days and priority per task, after 3 header columns
    for (Integer n = 0; n < taskCount; n++) {
        items.add(new ActionPlanTemplateItem(ActionPlanTemplateVersionId = version.Id, Name = t[3 + n * 3].left(80),
            UniqueName = t[0] + '_' + (n + 1), ItemEntityType = 'Task', DisplayOrder = n + 1, IsRequired = false));
    }
    insert items;
    List<ActionPlanTemplateItemValue> values = new List<ActionPlanTemplateItemValue>();
    for (Integer n = 0; n < taskCount; n++) {
        Integer i = 3 + n * 3;
        Id itemId = items[n].Id;
        values.add(new ActionPlanTemplateItemValue(ActionPlanTemplateItemId = itemId, Name = 'Subject',
            ItemEntityFieldName = 'Task.Subject', ValueLiteral = t[i]));
        values.add(new ActionPlanTemplateItemValue(ActionPlanTemplateItemId = itemId, Name = 'Due date',
            ItemEntityFieldName = 'Task.ActivityDate', ValueFormula = 'StartDate + ' + t[i + 1]));
        values.add(new ActionPlanTemplateItemValue(ActionPlanTemplateItemId = itemId, Name = 'Priority',
            ItemEntityFieldName = 'Task.Priority', ValueLiteral = t[i + 2]));
    }
    insert values;
    version.Status = 'Final';   // publishes the template
    update version;
    versionFor.put(t[0], version.Id);
    created++;
}

// ---------------------------------------------------------------- Action plans on the objectives
// Replace any earlier plans on these objectives, with the tasks they generated.
List<ActionPlan> old = [SELECT Id FROM ActionPlan WHERE TargetId IN :objectives];
Set<Id> oldTasks = new Set<Id>();
for (ActionPlanItem i : [SELECT ItemId FROM ActionPlanItem WHERE ActionPlanId IN :old AND ItemId != null]) oldTasks.add(i.ItemId);
delete [SELECT Id FROM Task WHERE Id IN :oldTasks];
delete old;

Map<String, String> label = new Map<String, String>();
for (List<String> t : templates) label.put(t[0], t[1]);
List<ActionPlan> plans = new List<ActionPlan>();
for (AccountPlanObjective o : objectives) {
    String template = templateFor.get(o.Name);
    plans.add(new ActionPlan(Name = (label.get(template) + ': ' + o.Name).left(80), TargetId = o.Id,
        ActionPlanTemplateVersionId = versionFor.get(template), ActionPlanType = 'Sales', StartDate = Date.today()));
}
insert plans;

System.debug(LoggingLevel.ERROR, 'Action plans: ' + plans.size() + ' on account plan objectives, '
    + [SELECT COUNT() FROM ActionPlanItem WHERE ActionPlanId IN :plans] + ' tasks. Templates: '
    + created + ' created, ' + (templates.size() - created) + ' reused.');
