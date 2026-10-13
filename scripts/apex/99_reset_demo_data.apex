// 99_reset_demo_data.apex
// Deletes everything the seed scripts created: anything tied to an Account whose Description
// contains "[demo-seed]" (02, 04, 05, 06, and 09's entitlements), 07's catalog (Product Codes starting "DD-"),
// 09's Knowledge articles (URL names starting "denali-"), and Salesforce's own sample cases ("Sample Case..."),
// which aren't linked to anything in the kit. Metadata is untouched. Deletes run child-first so
// the Restrict lookups (Project -> Contract, Deliverable -> Project, Supplier Assignment
// -> Supplier) never block. Re-run 02 afterwards for a fresh demo.

// Description is a long text area, so SOQL can't filter on it; check the tag in Apex instead.
Set<Id> acctIds = new Set<Id>();
for (Account a : [SELECT Id, Description FROM Account]) {
    if (a.Description != null && a.Description.contains('[demo-seed]')) acctIds.add(a.Id);
}
if (acctIds.isEmpty()) {
    System.debug(LoggingLevel.ERROR, 'No [demo-seed] data found. Nothing to delete.');
} else {
    // Sales Account Plans (06) only exist when the feature is on, so query them dynamically.
    if (Schema.getGlobalDescribe().containsKey('AccountPlan')) {
        // Action plans from 08 target these plans' objectives; remove them (and the tasks they generated)
        // first. Action Plans may not be on, so query them dynamically.
        if (Schema.getGlobalDescribe().containsKey('ActionPlan')) {
            Set<Id> objectiveIds = new Map<Id, SObject>(Database.query(
                'SELECT Id FROM AccountPlanObjective WHERE AccountPlan.AccountId IN :acctIds')).keySet();
            List<SObject> actionPlans = Database.query('SELECT Id FROM ActionPlan WHERE TargetId IN :objectiveIds');
            Set<Id> actionTasks = new Set<Id>();
            for (SObject i : Database.query('SELECT ItemId FROM ActionPlanItem WHERE ActionPlanId IN :actionPlans AND ItemId != null')) {
                actionTasks.add((Id) i.get('ItemId'));
            }
            delete [SELECT Id FROM Task WHERE Id IN :actionTasks];
            delete actionPlans;
        }
        delete Database.query('SELECT Id FROM AccountPlan WHERE AccountId IN :acctIds');   // cascades objectives and measures
    }
    // Activities on these accounts' records (05's history, flow reminders) also go when their
    // record is deleted; deleting the account-level ones first keeps the log counts honest.
    delete [SELECT Id FROM Asset WHERE AccountId IN :acctIds];   // installed base from 07 and the win flow
    delete [SELECT Id FROM Task WHERE AccountId IN :acctIds];
    delete [SELECT Id FROM Event WHERE AccountId IN :acctIds];
    delete [SELECT Id FROM Risk__c WHERE Account__c IN :acctIds OR Project__r.Account__c IN :acctIds];
    delete [SELECT Id FROM Case WHERE AccountId IN :acctIds];
    delete [SELECT Id FROM Service_Engagement__c WHERE Account__c IN :acctIds];   // cascades Engagement Milestones
    // 09's entitlements, once no case or engagement points at them. Entitlement Management may be off.
    if (Schema.getGlobalDescribe().containsKey('Entitlement')) {
        delete Database.query('SELECT Id FROM Entitlement WHERE AccountId IN :acctIds');
    }
    delete [SELECT Id FROM Deliverable__c WHERE Project__r.Account__c IN :acctIds]; // cascades Deliverable Updates
    delete [SELECT Id FROM Project__c WHERE Account__c IN :acctIds];              // cascades Supplier Assignments, Project Resources
    // Activated contracts delete directly once no Project points at them. Setting them back
    // to Draft first fails: the API won't move an Activated contract to another status.
    delete [SELECT Id FROM Contract WHERE AccountId IN :acctIds];
    delete [SELECT Id FROM Opportunity WHERE AccountId IN :acctIds];
    delete [SELECT Id FROM Account WHERE Id IN :acctIds];                         // cascades Contacts

    System.debug(LoggingLevel.ERROR, 'Demo data removed for ' + acctIds.size() + ' accounts.');
}

// Catalog from 07_seed_products.apex (Product Codes starting "DD-"). A standard price book entry
// can't be deleted while a custom price book still has one for the product, so go custom-first.
List<Product2> catalog = [SELECT Id FROM Product2 WHERE ProductCode LIKE 'DD-%'];
if (!catalog.isEmpty()) {
    delete [SELECT Id FROM PricebookEntry WHERE Product2Id IN :catalog AND Pricebook2.IsStandard = false];
    delete [SELECT Id FROM PricebookEntry WHERE Product2Id IN :catalog];
    delete catalog;
    delete [SELECT Id FROM Pricebook2 WHERE Name = 'GSA Schedule' AND IsStandard = false];
    System.debug(LoggingLevel.ERROR, 'Catalog removed: ' + catalog.size() + ' products and the GSA Schedule price book.');
}

// Salesforce's sample cases on its sample accounts (Acme, Global Media). They aren't linked to a
// Service Engagement, Project or Deliverable, so the Case page's Impact Chain has nothing to show.
List<Case> sampleCases = [SELECT Id FROM Case WHERE Subject LIKE 'Sample Case%'];
if (!sampleCases.isEmpty()) {
    delete sampleCases;
    System.debug(LoggingLevel.ERROR, 'Salesforce sample cases removed: ' + sampleCases.size() + '.');
}

// Knowledge articles from 09_seed_service_cloud.apex (URL names starting "denali-"). Published articles
// are archived before they can be deleted. Knowledge may be off.
if (Schema.getGlobalDescribe().containsKey('Knowledge__kav')) {
    Integer removed = 0;
    for (SObject k : Database.query('SELECT KnowledgeArticleId, PublishStatus FROM Knowledge__kav '
            + 'WHERE UrlName LIKE \'denali-%\' AND PublishStatus IN (\'Online\', \'Draft\')')) {
        String articleId = (String) k.get('KnowledgeArticleId');
        if (k.get('PublishStatus') == 'Online') {
            KbManagement.PublishingService.archiveOnlineArticle(articleId, null);
            KbManagement.PublishingService.deleteArchivedArticle(articleId);
        } else {
            KbManagement.PublishingService.deleteDraftArticle(articleId);
        }
        removed++;
    }
    if (removed > 0) System.debug(LoggingLevel.ERROR, 'Knowledge articles removed: ' + removed + '.');
}
