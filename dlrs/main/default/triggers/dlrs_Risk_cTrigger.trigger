/**
 * Declarative Lookup Rollup Summaries (dlrs) child trigger for Risk__c: hands every change to DLRS so the
 * Realtime rollups in customMetadata/dlrs__LookupRollupSummary2.* stay current. Same body DLRS generates.
 **/
trigger dlrs_Risk_cTrigger on Risk__c
    (before delete, before insert, before update, after delete, after insert, after undelete, after update)
{
    dlrs.RollupService.triggerHandler(Risk__c.SObjectType);
}
