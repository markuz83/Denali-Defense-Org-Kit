/**
 * Agent action: a briefing on one support case - severity and status, what it puts at risk
 * (the same chain as the Case page's Impact Chain: deliverable, project, contract, the revenue
 * milestone at stake, open risks), its SLA milestones, and any attached Knowledge articles.
 *
 * SLA milestones need Entitlement Management and articles need Knowledge, so both are queried
 * dynamically: without them the briefing simply leaves those parts out.
 */
public with sharing class DenaliAgentCaseBriefing {

    public class Request {
        @InvocableVariable(label='Case' description='Case number (such as 00001078 or 1078) or words from the case subject' required=true)
        public String caseName;
    }

    public class Result {
        @InvocableVariable(label='Case Briefing' description='The case briefing as JSON, or a message asking which case was meant')
        public String result;
    }

    @InvocableMethod(
        label='Denali: Get Case Briefing'
        description='Briefs on one support case: severity, status and age, the deliverable, project and contract it puts at risk with the revenue at stake, its SLA milestones (breached or time remaining), linked risks and attached Knowledge articles. Finds the case by number or subject.'
        category='Denali Assistant')
    public static List<Result> run(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Result r = new Result();
            Object found = findCase(req.caseName);
            r.result = found instanceof Id ? DenaliAgentSupport.toJson(briefing((Id) found)) : (String) found;
            results.add(r);
        }
        return results;
    }

    /** Returns the matching case's Id, or a message when there is no single match. */
    private static Object findCase(String name) {
        String trimmed = name == null ? '' : name.trim().removeStartIgnoreCase('case').trim();
        if (String.isBlank(trimmed)) {
            return 'No case given. Ask for the case number or what the case is about.';
        }
        List<Case> matches;
        if (trimmed.isNumeric()) {
            // Case numbers are zero-padded (00001078); "1078" should still find it.
            String tail = '%' + trimmed.replaceFirst('^0+', '');
            matches = [SELECT Id, CaseNumber, Subject, Status FROM Case WHERE CaseNumber LIKE :tail WITH USER_MODE ORDER BY CaseNumber DESC LIMIT 6];
        } else {
            String pattern = '%' + trimmed.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_') + '%';
            matches = [SELECT Id, CaseNumber, Subject, Status FROM Case WHERE Subject LIKE :pattern WITH USER_MODE ORDER BY IsClosed, CreatedDate DESC LIMIT 6];
        }
        if (matches.size() == 1) return matches[0].Id;
        if (matches.isEmpty()) return 'No case matches \'' + trimmed + '\'.';
        List<String> labels = new List<String>();
        for (Integer i = 0; i < Math.min(matches.size(), DenaliAgentSupport.MATCH_LIMIT); i++) {
            labels.add(matches[i].CaseNumber + ' \'' + matches[i].Subject + '\' (' + matches[i].Status + ')');
        }
        return '\'' + trimmed + '\' matches several cases: ' + String.join(labels, '; ')
            + (matches.size() > DenaliAgentSupport.MATCH_LIMIT ? ' and more' : '') + '. Ask which one they mean.';
    }

    private static Map<String, Object> briefing(Id caseId) {
        Case c = [
            SELECT Id, CaseNumber, Subject, Status, Priority, Severity__c, Customer_Impact__c, IsEscalated, Origin, Type,
                   CreatedDate, Owner.Name, Account.Name, Contact.Name, Escalation_Reason__c
            FROM Case WHERE Id = :caseId WITH USER_MODE
        ];
        ImpactChainController.Chain ch = ImpactChainController.getChain(caseId);

        Map<String, Object> impact = new Map<String, Object>{ 'revenueAtStake' => ch.revenueAtStake };
        if (ch.deliverable != null) {
            impact.put('deliverable', new Map<String, Object>{
                'name' => ch.deliverable.Name, 'status' => ch.deliverable.Status__c, 'health' => ch.deliverable.Health__c,
                'dueDate' => ch.deliverable.Due_Date__c, 'daysLate' => ch.deliverable.Schedule_Variance_Days__c,
                'revenueMilestone' => ch.deliverable.Revenue_Milestone__c, 'acceptance' => ch.deliverable.Acceptance_Status__c,
                'supplier' => ch.deliverable.Supplier__r?.Name, 'url' => DenaliAgentSupport.recordUrl(ch.deliverable.Id)
            });
        }
        if (ch.project != null) {
            impact.put('project', new Map<String, Object>{
                'name' => ch.project.Name, 'health' => ch.project.Health__c, 'projectManager' => ch.project.Project_Manager__r?.Name,
                'url' => DenaliAgentSupport.recordUrl(ch.project.Id)
            });
        }
        if (ch.serviceEngagement != null) {
            impact.put('serviceEngagement', new Map<String, Object>{
                'name' => ch.serviceEngagement.Name, 'serviceType' => ch.serviceEngagement.Service_Type__c,
                'serviceLevel' => ch.serviceEngagement.Service_Level__c, 'health' => ch.serviceEngagement.Health__c,
                'slaBreaches' => ch.serviceEngagement.SLA_Breaches__c, 'annualValue' => ch.serviceEngagement.Annual_Contract_Value__c,
                'url' => DenaliAgentSupport.recordUrl(ch.serviceEngagement.Id)
            });
        }
        if (ch.contract != null) {
            impact.put('contract', new Map<String, Object>{
                'awardNumber' => ch.contract.Award_Number__c, 'contractNumber' => ch.contract.ContractNumber,
                'health' => ch.contract.Contract_Health__c, 'nextOptionDate' => ch.contract.Next_Option_Date__c,
                'daysUntilOption' => ch.contract.Next_Option_Date__c == null ? null : Date.today().daysBetween(ch.contract.Next_Option_Date__c),
                'url' => DenaliAgentSupport.recordUrl(ch.contract.Id)
            });
        }
        List<Map<String, Object>> risks = new List<Map<String, Object>>();
        for (Risk__c rk : ch.risks) {
            risks.add(new Map<String, Object>{
                'name' => rk.Name, 'severity' => rk.Severity__c, 'status' => rk.Status__c, 'category' => rk.Risk_Category__c,
                'url' => DenaliAgentSupport.recordUrl(rk.Id)
            });
        }

        return new Map<String, Object>{
            'case' => new Map<String, Object>{
                'caseNumber' => c.CaseNumber, 'subject' => c.Subject, 'status' => c.Status, 'priority' => c.Priority,
                'severity' => c.Severity__c, 'customerImpact' => c.Customer_Impact__c, 'escalated' => c.IsEscalated,
                'escalationReason' => c.Escalation_Reason__c, 'type' => c.Type, 'origin' => c.Origin,
                'ageDays' => c.CreatedDate.date().daysBetween(Date.today()), 'owner' => c.Owner?.Name,
                'account' => c.Account?.Name, 'contact' => c.Contact?.Name, 'url' => DenaliAgentSupport.recordUrl(c.Id)
            },
            'impact' => impact,
            'openRisks' => risks,
            'sla' => slaByCase(new Set<Id>{ caseId }).get(caseId),
            'articles' => articles(caseId)
        };
    }

    /**
     * Each case's SLA milestones: name, target, whether it's breached or done, and minutes left
     * (from the target time; negative once overdue).
     * Empty when Entitlement Management is off. Shared with the Open Cases action.
     */
    public static Map<Id, Map<String, Object>> slaByCase(Set<Id> caseIds) {
        Map<Id, Map<String, Object>> sla = new Map<Id, Map<String, Object>>();
        if (caseIds.isEmpty() || !Schema.getGlobalDescribe().containsKey('CaseMilestone')) return sla;
        Map<Id, Boolean> stopped = new Map<Id, Boolean>();
        for (SObject c : Database.queryWithBinds('SELECT Id, IsStopped FROM Case WHERE Id IN :ids',
                new Map<String, Object>{ 'ids' => caseIds }, AccessLevel.USER_MODE)) {
            stopped.put(c.Id, (Boolean) c.get('IsStopped'));
        }
        for (SObject m : Database.queryWithBinds(
                'SELECT CaseId, MilestoneType.Name, TargetDate, CompletionDate, IsCompleted, IsViolated '
                + 'FROM CaseMilestone WHERE CaseId IN :ids ORDER BY TargetDate',
                new Map<String, Object>{ 'ids' => caseIds }, AccessLevel.USER_MODE)) {
            Id caseId = (Id) m.get('CaseId');
            if (!sla.containsKey(caseId)) {
                sla.put(caseId, new Map<String, Object>{
                    'breached' => false, 'clockStopped' => stopped.get(caseId), 'milestones' => new List<Object>()
                });
            }
            Map<String, Object> entry = sla.get(caseId);
            Boolean violated = (Boolean) m.get('IsViolated'), completed = (Boolean) m.get('IsCompleted');
            Datetime target = (Datetime) m.get('TargetDate');
            if (violated) entry.put('breached', true);
            ((List<Object>) entry.get('milestones')).add(new Map<String, Object>{
                'milestone' => (String) m.getSObject('MilestoneType')?.get('Name'), 'target' => m.get('TargetDate'),
                'completed' => completed, 'completedAt' => m.get('CompletionDate'), 'breached' => violated,
                'minutesRemaining' => completed || target == null ? null : (Integer) ((target.getTime() - Datetime.now().getTime()) / 60000)
            });
        }
        return sla;
    }

    /** Titles of the Knowledge articles attached to the case. Empty when Knowledge is off. */
    private static List<String> articles(Id caseId) {
        List<String> titles = new List<String>();
        // KnowledgeArticleVersion isn't in the global describe, so check for CaseArticle and guard the rest.
        if (!Schema.getGlobalDescribe().containsKey('CaseArticle')) return titles;
        try {
            Set<Id> versionIds = new Set<Id>();
            for (SObject ca : Database.queryWithBinds('SELECT KnowledgeArticleVersionId FROM CaseArticle WHERE CaseId = :caseId',
                    new Map<String, Object>{ 'caseId' => caseId }, AccessLevel.USER_MODE)) {
                if (ca.get('KnowledgeArticleVersionId') != null) versionIds.add((Id) ca.get('KnowledgeArticleVersionId'));
            }
            if (versionIds.isEmpty()) return titles;
            for (SObject v : Database.queryWithBinds('SELECT Title FROM KnowledgeArticleVersion WHERE Id IN :ids',
                    new Map<String, Object>{ 'ids' => versionIds }, AccessLevel.USER_MODE)) {
                titles.add((String) v.get('Title'));
            }
        } catch (QueryException e) {
            // Knowledge is off or not visible to this user: leave the articles out.
        }
        return titles;
    }
}
