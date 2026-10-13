/**
 * Agent action: rates every account the user can see as at risk, watch or clear, with reasons.
 *
 * At risk: revenue at risk on an at-risk deliverable, a Critical risk (score 15+), an open Sev 1
 * case, or Red health. Watch: a High risk (score 10-14), an open Sev 2 or escalated case, or
 * Yellow health. Risk Severity is a formula on Risk Score with the same thresholds.
 */
public with sharing class DenaliAgentPortfolioRisk {

    private static final Integer HIGH_RISK_SCORE = 10;
    private static final Integer CRITICAL_RISK_SCORE = 15;
    private static final Set<String> CLOSED_RISK = new Set<String>{ 'Closed', 'Realized' };

    public class Request {
        @InvocableVariable(label='Include Watch' description='Also list accounts on watch, not just those at risk. Defaults to true.')
        public Boolean includeWatch;
    }

    public class Result {
        @InvocableVariable(label='Portfolio Risk' description='Every account rated at risk, watch or clear, with reasons, as JSON')
        public String result;
    }

    public class FlaggedAccount {
        public String status;
        public String name;
        public String customerHealth;
        public String owner;
        public Decimal backlog;
        public Decimal revenueAtRisk = 0;
        public List<String> reasons = new List<String>();
        public Boolean healthRatingOutOfDate;
        public String url;
    }

    @InvocableMethod(
        label='Denali: Get Portfolio Risk'
        description='Checks every account at once and rates each at risk, watch or clear, with the reasons and whether its Customer Health rating looks out of date. Use for any question across accounts, such as which accounts are at risk.'
        category='Denali Assistant')
    public static List<Result> run(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Result r = new Result();
            r.result = DenaliAgentSupport.toJson(assess(req?.includeWatch != false));
            results.add(r);
        }
        return results;
    }

    public static Map<String, Object> assess(Boolean includeWatch) {
        List<Account> accounts = [
            SELECT Id, Name, Customer_Health__c, Owner.Name, Contract_Backlog__c
            FROM Account WITH USER_MODE ORDER BY Name LIMIT 2000
        ];
        Map<Id, List<String>> atRisk = new Map<Id, List<String>>();
        Map<Id, List<String>> watch = new Map<Id, List<String>>();
        Map<Id, Decimal> revenue = new Map<Id, Decimal>();
        for (Account a : accounts) {
            atRisk.put(a.Id, new List<String>());
            watch.put(a.Id, new List<String>());
            revenue.put(a.Id, 0);
        }

        Map<Id, List<String>> deliverableNames = new Map<Id, List<String>>();
        for (Deliverable__c d : [
            SELECT Account__c, Name, Revenue_at_Risk__c FROM Deliverable__c
            WHERE Is_At_Risk__c = true AND Account__c IN :atRisk.keySet() WITH USER_MODE
        ]) {
            revenue.put(d.Account__c, revenue.get(d.Account__c) + (d.Revenue_at_Risk__c == null ? 0 : d.Revenue_at_Risk__c));
            if (!deliverableNames.containsKey(d.Account__c)) deliverableNames.put(d.Account__c, new List<String>());
            deliverableNames.get(d.Account__c).add(d.Name);
        }
        for (Id accountId : deliverableNames.keySet()) {
            atRisk.get(accountId).add('$' + revenue.get(accountId).format() + ' revenue at risk on '
                + String.join(deliverableNames.get(accountId), ', '));
        }

        for (Risk__c rk : [
            SELECT Account__c, Name, Risk_Score__c, Status__c FROM Risk__c
            WHERE Account__c IN :atRisk.keySet() AND Status__c NOT IN :CLOSED_RISK AND Risk_Score__c >= :HIGH_RISK_SCORE
            WITH USER_MODE ORDER BY Risk_Score__c DESC
        ]) {
            Boolean critical = rk.Risk_Score__c >= CRITICAL_RISK_SCORE;
            String reason = (critical ? 'Critical' : 'High') + ' risk \'' + rk.Name + '\' (score '
                + rk.Risk_Score__c.format() + ', ' + rk.Status__c + ')';
            (critical ? atRisk : watch).get(rk.Account__c).add(reason);
        }

        for (Case c : [
            SELECT AccountId, CaseNumber, Subject, Status, Severity__c, IsEscalated FROM Case
            WHERE IsClosed = false AND AccountId IN :atRisk.keySet()
              AND (IsEscalated = true OR Status = 'Escalated' OR Severity__c LIKE 'Sev 1%' OR Severity__c LIKE 'Sev 2%')
            WITH USER_MODE
        ]) {
            String severity = c.Severity__c == null ? 'no severity' : c.Severity__c;
            Boolean escalated = c.IsEscalated || c.Status == 'Escalated';
            String reason = 'Case ' + c.CaseNumber + ' \'' + c.Subject + '\' (' + severity + (escalated ? ', escalated' : '') + ')';
            (severity.startsWith('Sev 1') ? atRisk : watch).get(c.AccountId).add(reason);
        }

        List<FlaggedAccount> flagged = new List<FlaggedAccount>();
        List<String> clear = new List<String>();
        for (Account a : accounts) {
            if (a.Customer_Health__c == 'Red') atRisk.get(a.Id).add('Customer Health is Red');
            if (a.Customer_Health__c == 'Yellow') watch.get(a.Id).add('Customer Health is Yellow');
            if (atRisk.get(a.Id).isEmpty() && watch.get(a.Id).isEmpty()) {
                clear.add(a.Name);
                continue;
            }
            FlaggedAccount f = new FlaggedAccount();
            f.status = atRisk.get(a.Id).isEmpty() ? 'watch' : 'at risk';
            f.name = a.Name;
            f.customerHealth = a.Customer_Health__c;
            f.owner = a.Owner?.Name;
            f.backlog = a.Contract_Backlog__c;
            f.revenueAtRisk = revenue.get(a.Id);
            f.reasons.addAll(atRisk.get(a.Id));
            f.reasons.addAll(watch.get(a.Id));
            String expected = f.status == 'at risk' ? 'Red' : 'Yellow';
            f.healthRatingOutOfDate = a.Customer_Health__c != expected
                && !(f.status == 'watch' && a.Customer_Health__c == 'Red');
            f.url = DenaliAgentSupport.recordUrl(a.Id);
            flagged.add(f);
        }

        // At risk first, then by revenue at risk.
        List<FlaggedAccount> sorted = new List<FlaggedAccount>();
        List<String> statuses = includeWatch ? new List<String>{ 'at risk', 'watch' } : new List<String>{ 'at risk' };
        for (String status : statuses) {
            List<FlaggedAccount> bucket = new List<FlaggedAccount>();
            for (FlaggedAccount f : flagged) {
                if (f.status == status) bucket.add(f);
            }
            while (!bucket.isEmpty()) {
                Integer top = 0;
                for (Integer i = 1; i < bucket.size(); i++) {
                    if (bucket[i].revenueAtRisk > bucket[top].revenueAtRisk) top = i;
                }
                sorted.add(bucket.remove(top));
            }
        }

        return new Map<String, Object>{
            'accountsChecked' => accounts.size(),
            'rules' => 'At risk: revenue at risk on an at-risk deliverable, a Critical risk (score 15+), an open Sev 1 case, or Red health. '
                + 'Watch: a High risk (score 10-14), an open Sev 2 or escalated case, or Yellow health.',
            'flaggedAccounts' => sorted,
            'clearAccounts' => clear
        };
    }
}
