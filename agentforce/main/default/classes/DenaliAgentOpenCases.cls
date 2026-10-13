/**
 * Agent action: open support cases across every account, or for one, most urgent first
 * (severity, then SLA breaches, then the least SLA time left), with what each puts at risk and a
 * summary: counts by severity, SLA breaches, and cases waiting on the customer or a supplier.
 */
public with sharing class DenaliAgentOpenCases {

    private static final Integer MAX_CASES = 25;

    public class Request {
        @InvocableVariable(label='Account Name' description='Optional full or partial account name, to show one account\'s cases only. Leave empty for every account.')
        public String accountName;
    }

    public class Result {
        @InvocableVariable(label='Open Cases' description='Open cases, most urgent first, with a summary, as JSON')
        public String result;
    }

    @InvocableMethod(
        label='Denali: Get Open Cases'
        description='Lists open support cases across every account, or one account, most urgent first: severity, status, SLA breaches and time remaining, and the deliverable revenue each puts at risk, with counts by severity and of cases waiting on the customer or a supplier.'
        category='Denali Assistant')
    public static List<Result> run(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Result r = new Result();
            Id accountId;
            String accountLabel = 'every account';
            if (String.isNotBlank(req.accountName)) {
                DenaliAgentSupport.Match m = DenaliAgentSupport.findByName('Account', 'Id, Name', req.accountName, 'account');
                if (m.record == null) {
                    r.result = m.message;
                    results.add(r);
                    continue;
                }
                accountId = m.record.Id;
                accountLabel = (String) m.record.get('Name');
            }
            r.result = DenaliAgentSupport.toJson(openCases(accountId, accountLabel));
            results.add(r);
        }
        return results;
    }

    private static Map<String, Object> openCases(Id accountId, String accountLabel) {
        String query = 'SELECT Id, CaseNumber, Subject, Status, Priority, Severity__c, IsEscalated, CreatedDate, Account.Name, '
            + 'Service_Engagement__r.Name, Deliverable__r.Name, Deliverable__r.Revenue_Milestone__c, Deliverable__r.Acceptance_Status__c '
            + 'FROM Case WHERE IsClosed = false' + (accountId == null ? '' : ' AND AccountId = :accountId')
            + ' ORDER BY Severity__c NULLS LAST, CreatedDate LIMIT 200';
        List<Case> cases = Database.queryWithBinds(query, new Map<String, Object>{ 'accountId' => accountId }, AccessLevel.USER_MODE);
        Map<Id, Map<String, Object>> sla = DenaliAgentCaseBriefing.slaByCase(new Map<Id, Case>(cases).keySet());

        List<CaseRow> rows = new List<CaseRow>();
        Map<String, Integer> bySeverity = new Map<String, Integer>();
        Integer breached = 0, waitingOnCustomer = 0, waitingOnSupplier = 0, escalated = 0;
        Decimal revenueAtStake = 0;
        for (Case c : cases) {
            String severity = c.Severity__c == null ? 'No severity' : c.Severity__c;
            bySeverity.put(severity, (bySeverity.containsKey(severity) ? bySeverity.get(severity) : 0) + 1);
            Map<String, Object> caseSla = sla.get(c.Id);
            Boolean isBreached = caseSla != null && (Boolean) caseSla.get('breached');
            if (isBreached) breached++;
            if (c.Status == 'Waiting on Customer') waitingOnCustomer++;
            if (c.Status == 'Waiting on Supplier') waitingOnSupplier++;
            if (c.IsEscalated) escalated++;
            Decimal stake = c.Deliverable__r != null && c.Deliverable__r.Acceptance_Status__c != 'Accepted' ? c.Deliverable__r.Revenue_Milestone__c : null;
            if (stake != null) revenueAtStake += stake;
            rows.add(new CaseRow(c, caseSla, isBreached, stake));
        }
        rows.sort();

        List<Map<String, Object>> listed = new List<Map<String, Object>>();
        for (Integer i = 0; i < Math.min(rows.size(), MAX_CASES); i++) {
            listed.add(rows[i].toMap());
        }

        List<Map<String, Object>> engagements = new List<Map<String, Object>>();
        String seQuery = 'SELECT Id, Name, Account__r.Name, Service_Level__c, Health__c, Cases_Open__c, SLA_Breaches__c '
            + 'FROM Service_Engagement__c WHERE (SLA_Breaches__c > 0 OR Cases_Open__c > 0)'
            + (accountId == null ? '' : ' AND Account__c = :accountId') + ' ORDER BY SLA_Breaches__c DESC NULLS LAST LIMIT 10';
        List<Service_Engagement__c> ses = Database.queryWithBinds(seQuery, new Map<String, Object>{ 'accountId' => accountId }, AccessLevel.USER_MODE);
        for (Service_Engagement__c se : ses) {
            engagements.add(new Map<String, Object>{
                'name' => se.Name, 'account' => se.Account__r?.Name, 'serviceLevel' => se.Service_Level__c, 'health' => se.Health__c,
                'openCases' => se.Cases_Open__c, 'slaBreaches' => se.SLA_Breaches__c, 'url' => DenaliAgentSupport.recordUrl(se.Id)
            });
        }

        return new Map<String, Object>{
            'scope' => accountLabel,
            'summary' => new Map<String, Object>{
                'openCases' => cases.size(), 'bySeverity' => bySeverity, 'slaBreached' => breached, 'escalated' => escalated,
                'waitingOnCustomer' => waitingOnCustomer, 'waitingOnSupplier' => waitingOnSupplier,
                'deliverableRevenueAtStake' => revenueAtStake,
                'listed' => listed.size() < cases.size() ? 'The ' + listed.size() + ' most urgent of ' + cases.size() : 'All'
            },
            'cases' => listed,
            'serviceEngagements' => engagements
        };
    }

    /** One case, sortable most urgent first: severity, then breached SLA, then least SLA time left. */
    private class CaseRow implements Comparable {
        Case c;
        Map<String, Object> sla;
        Boolean breached;
        Decimal stake;
        Integer minutesLeft;

        CaseRow(Case c, Map<String, Object> sla, Boolean breached, Decimal stake) {
            this.c = c;
            this.sla = sla;
            this.breached = breached;
            this.stake = stake;
            if (sla != null) {
                for (Object o : (List<Object>) sla.get('milestones')) {
                    Object left = ((Map<String, Object>) o).get('minutesRemaining');
                    if (left != null && (minutesLeft == null || (Integer) left < minutesLeft)) minutesLeft = (Integer) left;
                }
            }
        }

        Integer rank() {
            String s = c.Severity__c == null ? '' : c.Severity__c;
            return s.startsWith('Sev 1') ? 1 : s.startsWith('Sev 2') ? 2 : s.startsWith('Sev 3') ? 3 : s.startsWith('Sev 4') ? 4 : 5;
        }

        public Integer compareTo(Object other) {
            CaseRow o = (CaseRow) other;
            if (rank() != o.rank()) return rank() - o.rank();
            if (breached != o.breached) return breached ? -1 : 1;
            Integer a = minutesLeft == null ? 2147483647 : minutesLeft, b = o.minutesLeft == null ? 2147483647 : o.minutesLeft;
            return a == b ? 0 : (a < b ? -1 : 1);
        }

        Map<String, Object> toMap() {
            return new Map<String, Object>{
                'caseNumber' => c.CaseNumber, 'subject' => c.Subject, 'account' => c.Account?.Name, 'severity' => c.Severity__c,
                'priority' => c.Priority, 'status' => c.Status, 'escalated' => c.IsEscalated,
                'ageDays' => c.CreatedDate.date().daysBetween(Date.today()), 'serviceEngagement' => c.Service_Engagement__r?.Name,
                'deliverable' => c.Deliverable__r?.Name, 'revenueAtStake' => stake, 'slaBreached' => breached,
                'slaMinutesRemaining' => minutesLeft, 'url' => DenaliAgentSupport.recordUrl(c.Id)
            };
        }
    }
}
