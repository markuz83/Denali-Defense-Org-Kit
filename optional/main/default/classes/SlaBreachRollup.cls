/**
 * Keeps the SLA breach fields current:
 * - Case.SLA_Breached__c: checked when the case has at least one violated SLA milestone (open or
 *   completed late), so list views and reports can filter on breached cases.
 * - Service_Engagement__c.SLA_Breaches__c: the number of the engagement's breached cases.
 *
 * - Scheduled, because milestones are violated as time passes, not when a record is saved, so a
 *   realtime rollup would never fire. 10_schedule_sla_breach_rollup.apex runs it hourly, and
 *   03_recalculate_rollups.apex calls it too, so the two never disagree.
 * - Counts CaseMilestone.IsViolated rather than Case.MilestoneStatus, which SOQL can't filter on.
 * - Only writes records whose value changed.
 *
 * Without sharing: it's a rollup, so it has to see every case whoever scheduled it.
 */
public without sharing class SlaBreachRollup implements Schedulable {

    public void execute(SchedulableContext context) {
        flagCases(breachedCaseIds());
        apply(countBreaches());
    }

    public static Map<Id, Integer> countBreaches() {
        Map<Id, Integer> breaches = new Map<Id, Integer>();
        for (AggregateResult r : [
            SELECT Case.Service_Engagement__c engagement, COUNT_DISTINCT(CaseId) cases
            FROM CaseMilestone
            WHERE IsViolated = true AND Case.Service_Engagement__c != null
            GROUP BY Case.Service_Engagement__c
        ]) {
            breaches.put((Id) r.get('engagement'), (Integer) r.get('cases'));
        }
        return breaches;
    }

    /** Ids of every case with at least one violated milestone. */
    public static Set<Id> breachedCaseIds() {
        Set<Id> caseIds = new Set<Id>();
        for (AggregateResult r : [SELECT CaseId FROM CaseMilestone WHERE IsViolated = true GROUP BY CaseId]) {
            caseIds.add((Id) r.get('CaseId'));
        }
        return caseIds;
    }

    /** Checks SLA Breached on the given cases and clears it on any other case that has it. */
    @TestVisible
    static List<Case> flagCases(Set<Id> breached) {
        List<Case> changed = new List<Case>();
        for (Case c : [SELECT Id, SLA_Breached__c FROM Case WHERE Id IN :breached OR SLA_Breached__c = true]) {
            Boolean isBreached = breached.contains(c.Id);
            if (c.SLA_Breached__c != isBreached) {
                c.SLA_Breached__c = isBreached;
                changed.add(c);
            }
        }
        update changed;
        return changed;
    }

    @TestVisible
    static List<Service_Engagement__c> apply(Map<Id, Integer> breaches) {
        List<Service_Engagement__c> changed = new List<Service_Engagement__c>();
        for (Service_Engagement__c se : [SELECT Id, SLA_Breaches__c FROM Service_Engagement__c]) {
            Integer count = breaches.containsKey(se.Id) ? breaches.get(se.Id) : 0;
            if (se.SLA_Breaches__c != count) {
                se.SLA_Breaches__c = count;
                changed.add(se);
            }
        }
        update changed;
        return changed;
    }
}
