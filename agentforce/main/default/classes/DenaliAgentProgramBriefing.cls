/**
 * Agent action: a briefing on one program (a Contract) - funding and backlog, margin variance,
 * at-risk deliverables, open risks, open support cases and the next option date.
 */
public with sharing class DenaliAgentProgramBriefing {

    private static final Set<String> CLOSED_RISK = new Set<String>{ 'Closed', 'Realized' };
    private static final Integer TOP_RISKS = 5;

    public class Request {
        @InvocableVariable(label='Program Name' description='Award number (such as NDA-2026-001), contract number, project name or account name' required=true)
        public String programName;
    }

    public class Result {
        @InvocableVariable(label='Program Briefing' description='The program briefing as JSON, or a message asking which program was meant')
        public String result;
    }

    @InvocableMethod(
        label='Denali: Get Program Briefing'
        description='Briefs on one program (contract): funded backlog, margin variance, at-risk deliverables, open risks, open support cases and the next option date. Finds the program by award number, contract number, project name or account name.'
        category='Denali Assistant')
    public static List<Result> run(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Result r = new Result();
            Object found = findProgram(req.programName);
            r.result = found instanceof Id ? DenaliAgentSupport.toJson(briefing((Id) found)) : (String) found;
            results.add(r);
        }
        return results;
    }

    /**
     * Returns the matching contract's Id, or a message when there is no single match. Contract has
     * no Name, so users name a program by its award or contract number, one of its projects, or its account.
     */
    private static Object findProgram(String name) {
        String trimmed = name == null ? '' : name.trim();
        if (String.isBlank(trimmed)) {
            return 'No program name given. Ask for the award number, project or account.';
        }
        String pattern = '%' + trimmed.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_') + '%';

        List<Contract> exact = [
            SELECT Id FROM Contract WHERE Award_Number__c = :trimmed OR ContractNumber = :trimmed
            WITH USER_MODE LIMIT 2
        ];
        if (exact.size() == 1) return exact[0].Id;

        Set<Id> ids = new Set<Id>();
        for (Contract c : [
            SELECT Id FROM Contract WHERE Award_Number__c LIKE :pattern OR Account.Name LIKE :pattern
            WITH USER_MODE LIMIT 20
        ]) {
            ids.add(c.Id);
        }
        for (Project__c p : [
            SELECT Contract__c FROM Project__c WHERE Name LIKE :pattern AND Contract__c != null
            WITH USER_MODE LIMIT 20
        ]) {
            ids.add(p.Contract__c);
        }
        if (ids.size() == 1) return new List<Id>(ids)[0];
        if (ids.isEmpty()) return 'No program matches \'' + trimmed + '\'.';

        List<String> labels = new List<String>();
        for (Contract c : [
            SELECT Award_Number__c, ContractNumber, Account.Name, Status FROM Contract WHERE Id IN :ids
            WITH USER_MODE ORDER BY Award_Number__c NULLS LAST LIMIT :DenaliAgentSupport.MATCH_LIMIT
        ]) {
            labels.add(programLabel(c) + ' (' + c.Account.Name + ', ' + c.Status + ')');
        }
        return '\'' + trimmed + '\' matches several programs: ' + String.join(labels, '; ')
            + (ids.size() > DenaliAgentSupport.MATCH_LIMIT ? ' and more' : '') + '. Ask which one they mean.';
    }

    private static Map<String, Object> briefing(Id contractId) {
        Contract c = [
            SELECT Id, Award_Number__c, ContractNumber, Account.Name, Status, Contract_Health__c, Contract_Type__c,
                   Current_Period__c, StartDate, EndDate, Next_Option_Date__c, Program_Manager__r.Name,
                   Contract_Value__c, Funded_Value__c, Unfunded_Value__c, Percent_Funded__c, Revenue_Recognized__c,
                   Funded_Backlog__c, Total_Backlog__c, Original_Margin__c, Current_Margin__c, Margin_Variance__c
            FROM Contract WHERE Id = :contractId WITH USER_MODE
        ];

        List<Map<String, Object>> projects = new List<Map<String, Object>>();
        for (Project__c p : [
            SELECT Id, Name, Status__c, Health__c, Percent_Complete__c, Forecast_Margin__c, Bid_Margin__c,
                   Margin_Erosion__c, Project_Manager__r.Name
            FROM Project__c WHERE Contract__c = :contractId WITH USER_MODE ORDER BY Name
        ]) {
            projects.add(new Map<String, Object>{
                'name' => p.Name, 'status' => p.Status__c, 'health' => p.Health__c, 'percentComplete' => p.Percent_Complete__c,
                'forecastMargin' => p.Forecast_Margin__c, 'bidMargin' => p.Bid_Margin__c, 'marginErosionPts' => p.Margin_Erosion__c,
                'projectManager' => p.Project_Manager__r?.Name, 'url' => DenaliAgentSupport.recordUrl(p.Id)
            });
        }

        // Deliverables link to the contract directly or through their project.
        List<Map<String, Object>> atRisk = new List<Map<String, Object>>();
        Decimal revenueAtRisk = 0;
        for (Deliverable__c d : [
            SELECT Id, Name, Project__r.Name, Status__c, Health__c, Percent_Complete__c, Due_Date__c,
                   Forecast_Completion_Date__c, Schedule_Variance_Days__c, Is_Overdue__c, Revenue_Milestone__c,
                   Blocker_Description__c, Supplier__r.Name
            FROM Deliverable__c
            WHERE (Contract__c = :contractId OR Project__r.Contract__c = :contractId)
              AND (Is_At_Risk__c = true OR Is_Overdue__c = true)
            WITH USER_MODE ORDER BY Due_Date__c NULLS LAST
        ]) {
            revenueAtRisk += d.Revenue_Milestone__c == null ? 0 : d.Revenue_Milestone__c;
            atRisk.add(new Map<String, Object>{
                'name' => d.Name, 'project' => d.Project__r?.Name, 'status' => d.Status__c, 'health' => d.Health__c,
                'percentComplete' => d.Percent_Complete__c, 'dueDate' => d.Due_Date__c,
                'forecastDate' => d.Forecast_Completion_Date__c, 'daysLate' => d.Schedule_Variance_Days__c,
                'overdue' => d.Is_Overdue__c, 'revenueMilestone' => d.Revenue_Milestone__c,
                'blocker' => d.Blocker_Description__c, 'supplier' => d.Supplier__r?.Name,
                'url' => DenaliAgentSupport.recordUrl(d.Id)
            });
        }

        // Risks link to the contract directly, through a project, or through a deliverable's project.
        List<Map<String, Object>> topRisks = new List<Map<String, Object>>();
        Integer openRisks = 0;
        Decimal riskExposure = 0;
        for (Risk__c rk : [
            SELECT Id, Name, Risk_Score__c, Severity__c, Status__c, Risk_Category__c, Risk_Owner__r.Name,
                   Financial_Impact__c, Target_Resolution_Date__c, Mitigation_Plan__c
            FROM Risk__c
            WHERE (Contract__c = :contractId OR Project__r.Contract__c = :contractId
                   OR Deliverable__r.Project__r.Contract__c = :contractId)
              AND Status__c NOT IN :CLOSED_RISK
            WITH USER_MODE ORDER BY Risk_Score__c DESC NULLS LAST
        ]) {
            openRisks++;
            riskExposure += rk.Financial_Impact__c == null ? 0 : rk.Financial_Impact__c;
            if (topRisks.size() < TOP_RISKS) {
                topRisks.add(new Map<String, Object>{
                    'name' => rk.Name, 'score' => rk.Risk_Score__c, 'severity' => rk.Severity__c, 'status' => rk.Status__c,
                    'category' => rk.Risk_Category__c, 'owner' => rk.Risk_Owner__r?.Name,
                    'financialImpact' => rk.Financial_Impact__c, 'targetResolution' => rk.Target_Resolution_Date__c,
                    'mitigation' => rk.Mitigation_Plan__c, 'url' => DenaliAgentSupport.recordUrl(rk.Id)
                });
            }
        }

        // Open cases link to the contract through their deliverable, project or service engagement.
        List<Case> cases = [
            SELECT Id, CaseNumber, Subject, Status, Severity__c, IsEscalated, Deliverable__r.Name
            FROM Case
            WHERE IsClosed = false
              AND (Deliverable__r.Project__r.Contract__c = :contractId OR Project__r.Contract__c = :contractId
                   OR Service_Engagement__r.Contract__c = :contractId)
            WITH USER_MODE ORDER BY Severity__c NULLS LAST, CreatedDate
        ];
        Map<Id, Map<String, Object>> sla = DenaliAgentCaseBriefing.slaByCase(new Map<Id, Case>(cases).keySet());
        List<Map<String, Object>> openCases = new List<Map<String, Object>>();
        Integer severeCases = 0, slaBreached = 0;
        for (Case cs : cases) {
            Boolean breached = sla.containsKey(cs.Id) && (Boolean) sla.get(cs.Id).get('breached');
            if (breached) slaBreached++;
            if (cs.Severity__c != null && (cs.Severity__c.startsWith('Sev 1') || cs.Severity__c.startsWith('Sev 2'))) severeCases++;
            openCases.add(new Map<String, Object>{
                'caseNumber' => cs.CaseNumber, 'subject' => cs.Subject, 'status' => cs.Status, 'severity' => cs.Severity__c,
                'escalated' => cs.IsEscalated, 'deliverable' => cs.Deliverable__r?.Name, 'slaBreached' => breached,
                'url' => DenaliAgentSupport.recordUrl(cs.Id)
            });
        }

        return new Map<String, Object>{
            'program' => new Map<String, Object>{
                'awardNumber' => c.Award_Number__c, 'contractNumber' => c.ContractNumber, 'account' => c.Account.Name,
                'status' => c.Status, 'health' => c.Contract_Health__c, 'contractType' => c.Contract_Type__c,
                'programManager' => c.Program_Manager__r?.Name, 'startDate' => c.StartDate, 'endDate' => c.EndDate,
                'url' => DenaliAgentSupport.recordUrl(c.Id)
            },
            'funding' => new Map<String, Object>{
                'contractValue' => c.Contract_Value__c, 'fundedValue' => c.Funded_Value__c, 'unfundedValue' => c.Unfunded_Value__c,
                'percentFunded' => c.Percent_Funded__c, 'revenueRecognized' => c.Revenue_Recognized__c,
                'fundedBacklog' => c.Funded_Backlog__c, 'totalBacklog' => c.Total_Backlog__c
            },
            'margin' => new Map<String, Object>{
                'originalMargin' => c.Original_Margin__c, 'currentMargin' => c.Current_Margin__c,
                'marginVariancePts' => c.Margin_Variance__c
            },
            'nextOption' => new Map<String, Object>{
                'currentPeriod' => c.Current_Period__c, 'nextOptionDate' => c.Next_Option_Date__c,
                'daysUntilOption' => c.Next_Option_Date__c == null ? null : Date.today().daysBetween(c.Next_Option_Date__c)
            },
            'atRiskDeliverables' => atRisk,
            'revenueAtRisk' => revenueAtRisk,
            'openRiskCount' => openRisks,
            'openRiskExposure' => riskExposure,
            'topOpenRisks' => topRisks,
            'openCaseCount' => cases.size(),
            'severeCaseCount' => severeCases,
            'slaBreachedCaseCount' => slaBreached,
            'openCases' => openCases,
            'projects' => projects
        };
    }

    private static String programLabel(Contract c) {
        return String.isNotBlank(c.Award_Number__c) ? c.Award_Number__c : 'Contract ' + c.ContractNumber;
    }
}
