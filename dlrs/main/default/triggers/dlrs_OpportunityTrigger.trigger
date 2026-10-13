/**
 * Declarative Lookup Rollup Summaries (dlrs) child trigger for Opportunity: hands every change to DLRS so the
 * Realtime rollups in customMetadata/dlrs__LookupRollupSummary2.* stay current. Same body DLRS generates.
 **/
trigger dlrs_OpportunityTrigger on Opportunity
    (before delete, before insert, before update, after delete, after insert, after undelete, after update)
{
    dlrs.RollupService.triggerHandler(Opportunity.SObjectType);
}
