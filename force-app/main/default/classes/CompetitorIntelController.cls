/**
 * Backs the Competitor Intel LWC. On an Opportunity it profiles the Incumbent; on an Account
 * it profiles that account as a competitor. "Head to head" means closed deals where the
 * competitor was the incumbent or the one we lost to, over the last three years. On an open
 * Opportunity it also returns that pursuit's margin and floor, so the component can compare them.
 */
public with sharing class CompetitorIntelController {

    public class HeadToHead {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String accountName;
        @AuraEnabled public Date closeDate;
        @AuraEnabled public Boolean won;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Decimal margin;
        @AuraEnabled public String lossReason;
    }

    public class ReasonCount {
        @AuraEnabled public String reason;
        @AuraEnabled public Integer count;
        @AuraEnabled public Decimal amount;
    }

    public class Intel {
        @AuraEnabled public Id competitorId;
        @AuraEnabled public String competitorName;
        @AuraEnabled public Integer wins = 0;
        @AuraEnabled public Integer losses = 0;
        @AuraEnabled public Decimal bookingsWon = 0;
        @AuraEnabled public Decimal bookingsLost = 0;
        @AuraEnabled public Decimal avgMarginWon;
        @AuraEnabled public Decimal avgMarginLost;
        @AuraEnabled public Integer openDeals = 0;
        @AuraEnabled public Decimal openPipeline = 0;
        @AuraEnabled public List<ReasonCount> lossReasons = new List<ReasonCount>();
        @AuraEnabled public List<HeadToHead> recent = new List<HeadToHead>();
        // The open Opportunity the component sits on (null on an Account page or a closed deal).
        @AuraEnabled public Decimal pursuitMargin;
        @AuraEnabled public Decimal pursuitFloor;
    }

    @AuraEnabled(cacheable=true)
    public static Intel getIntel(Id recordId) {
        Id competitorId = resolveCompetitor(recordId);
        if (competitorId == null) {
            return null;
        }
        Intel intel = new Intel();
        intel.competitorId = competitorId;
        intel.competitorName = [SELECT Name FROM Account WHERE Id = :competitorId WITH USER_MODE].Name;

        Date since = Date.today().addYears(-3);
        Decimal marginWonSum = 0, marginLostSum = 0;
        Integer marginWonN = 0, marginLostN = 0;
        Map<String, ReasonCount> reasons = new Map<String, ReasonCount>();
        for (Opportunity o : [
            SELECT Id, Name, Account.Name, CloseDate, IsWon, IsClosed, Amount, Estimated_Margin__c, Loss_Reason__c, Lost_To__c
            FROM Opportunity
            WHERE (Incumbent__c = :competitorId OR Lost_To__c = :competitorId) AND CloseDate >= :since
            WITH USER_MODE
            ORDER BY CloseDate DESC
        ]) {
            if (!o.IsClosed) {
                intel.openDeals++;
                intel.openPipeline += nz(o.Amount);
                continue;
            }
            // A loss counts against this competitor only if we lost to them (or didn't record who won).
            Boolean lostToThem = !o.IsWon && (o.Lost_To__c == competitorId || o.Lost_To__c == null);
            if (!o.IsWon && !lostToThem) continue;

            if (o.IsWon) {
                intel.wins++;
                intel.bookingsWon += nz(o.Amount);
                if (o.Estimated_Margin__c != null) { marginWonSum += o.Estimated_Margin__c; marginWonN++; }
            } else {
                intel.losses++;
                intel.bookingsLost += nz(o.Amount);
                if (o.Estimated_Margin__c != null) { marginLostSum += o.Estimated_Margin__c; marginLostN++; }
                String reason = String.isBlank(o.Loss_Reason__c) ? 'Not recorded' : o.Loss_Reason__c;
                if (!reasons.containsKey(reason)) {
                    ReasonCount rc = new ReasonCount();
                    rc.reason = reason;
                    rc.count = 0;
                    rc.amount = 0;
                    reasons.put(reason, rc);
                }
                reasons.get(reason).count++;
                reasons.get(reason).amount += nz(o.Amount);
            }
            if (intel.recent.size() < 6) {
                HeadToHead h = new HeadToHead();
                h.id = o.Id;
                h.name = o.Name;
                h.accountName = o.Account.Name;
                h.closeDate = o.CloseDate;
                h.won = o.IsWon;
                h.amount = o.Amount;
                h.margin = o.Estimated_Margin__c;
                h.lossReason = o.Loss_Reason__c;
                intel.recent.add(h);
            }
        }
        intel.avgMarginWon = marginWonN > 0 ? marginWonSum / marginWonN : null;
        intel.avgMarginLost = marginLostN > 0 ? marginLostSum / marginLostN : null;
        intel.lossReasons = reasons.values();

        if (recordId.getSObjectType() == Opportunity.SObjectType) {
            for (Opportunity o : [SELECT Estimated_Margin__c, Margin_Floor__c, IsClosed FROM Opportunity WHERE Id = :recordId WITH USER_MODE]) {
                if (!o.IsClosed) {
                    intel.pursuitMargin = o.Estimated_Margin__c;
                    intel.pursuitFloor = o.Margin_Floor__c;
                }
            }
        }
        return intel;
    }

    private static Id resolveCompetitor(Id recordId) {
        if (recordId == null) return null;
        String type = recordId.getSObjectType().getDescribe().getName();
        if (type == 'Opportunity') {
            List<Opportunity> o = [SELECT Incumbent__c FROM Opportunity WHERE Id = :recordId WITH USER_MODE];
            return o.isEmpty() ? null : o[0].Incumbent__c;
        }
        if (type == 'Account') {
            List<Account> a = [SELECT Id, Is_Competitor__c FROM Account WHERE Id = :recordId WITH USER_MODE];
            return (a.isEmpty() || !a[0].Is_Competitor__c) ? null : a[0].Id;
        }
        return null;
    }

    private static Decimal nz(Decimal v) {
        return v == null ? 0 : v;
    }
}
