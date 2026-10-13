/**
 * Declarative Lookup Rollup Summaries (dlrs) child trigger for Contract: hands every change to DLRS so the
 * Realtime rollups in customMetadata/dlrs__LookupRollupSummary2.* stay current. Same body DLRS generates.
 **/
trigger dlrs_ContractTrigger on Contract
    (before delete, before insert, before update, after delete, after insert, after undelete, after update)
{
    dlrs.RollupService.triggerHandler(Contract.SObjectType);
}
