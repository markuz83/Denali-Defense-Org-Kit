/**
 * Backs the Margin Guardrail LWC on the Opportunity record page: where the deal's margin sits
 * against its floor and against recent wins, the Margin Exception approval state, and the
 * Einstein-drafted Pricing Rationale.
 */
public with sharing class MarginGuardrailController {

    @TestVisible private static final String PROMPT_TEMPLATE = 'Pricing_Rationale';
    @TestVisible private static final String TEST_RATIONALE = 'Summary: test rationale.';

    public class GuardrailContext {
        @AuraEnabled public Opportunity opportunity;
        @AuraEnabled public Decimal avgWonMarginSameType;      // percent units, e.g. 15.5
        @AuraEnabled public Integer wonCountSameType = 0;
        @AuraEnabled public Decimal avgWonMarginAll;
        @AuraEnabled public Integer wonCountAll = 0;
        @AuraEnabled public Boolean pendingApproval = false;
        @AuraEnabled public String pendingApproverName;
        @AuraEnabled public Datetime submittedDate;
    }

    @AuraEnabled(cacheable=true)
    public static GuardrailContext getContext(Id opportunityId) {
        List<Opportunity> opps = [
            SELECT Id, Name, Amount, StageName, IsClosed, Contract_Type__c, Acquisition_Type__c,
                   Estimated_Margin__c, Margin_Floor__c, Below_Margin_Floor__c, Margin_Shortfall__c,
                   Margin_Approval_Status__c, Pricing_Rationale__c,
                   Incumbent__c, Incumbent__r.Name, Incumbent__r.Deals_Lost_To__c, Incumbent__r.Bookings_Lost_To__c
            FROM Opportunity WHERE Id = :opportunityId WITH USER_MODE
        ];
        if (opps.isEmpty()) {
            return null;
        }
        GuardrailContext ctx = new GuardrailContext();
        ctx.opportunity = opps[0];

        // Won deals over roughly the last two years: same acquisition type, and all types.
        Date since = Date.today().addYears(-2);
        if (ctx.opportunity.Acquisition_Type__c != null) {
            AggregateResult same = [
                SELECT AVG(Estimated_Margin__c) avgMargin, COUNT(Id) n FROM Opportunity
                WHERE IsWon = true AND CloseDate >= :since AND Estimated_Margin__c != null
                  AND Acquisition_Type__c = :ctx.opportunity.Acquisition_Type__c AND Id != :opportunityId
                WITH USER_MODE
            ];
            ctx.avgWonMarginSameType = (Decimal) same.get('avgMargin');
            ctx.wonCountSameType = (Integer) same.get('n');
        }
        AggregateResult all = [
            SELECT AVG(Estimated_Margin__c) avgMargin, COUNT(Id) n FROM Opportunity
            WHERE IsWon = true AND CloseDate >= :since AND Estimated_Margin__c != null AND Id != :opportunityId
            WITH USER_MODE
        ];
        ctx.avgWonMarginAll = (Decimal) all.get('avgMargin');
        ctx.wonCountAll = (Integer) all.get('n');

        List<ProcessInstanceWorkitem> pending = [
            SELECT ActorId, ProcessInstance.CreatedDate
            FROM ProcessInstanceWorkitem
            WHERE ProcessInstance.TargetObjectId = :opportunityId AND ProcessInstance.Status = 'Pending'
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        if (!pending.isEmpty()) {
            ctx.pendingApproval = true;
            ctx.submittedDate = pending[0].ProcessInstance.CreatedDate;
            ctx.pendingApproverName = actorName(pending[0].ActorId);
        }
        return ctx;
    }

    // The approver's name, looked up by Id: the polymorphic Actor.Name relationship comes back
    // empty through a Workitems subquery, and in test context even when queried directly.
    private static String actorName(Id actorId) {
        if (actorId == null) return null;
        if (actorId.getSObjectType() == User.SObjectType) {
            List<User> u = [SELECT Name FROM User WHERE Id = :actorId];
            return u.isEmpty() ? null : u[0].Name;
        }
        List<Group> g = [SELECT Name FROM Group WHERE Id = :actorId];
        return g.isEmpty() ? null : g[0].Name;
    }

    /**
     * Submits the opportunity to the Margin Exception approval process. The process asks the
     * submitter to choose the approver, so the LWC passes one.
     */
    @AuraEnabled
    public static void submitForApproval(Id opportunityId, Id approverId, String comments) {
        if (approverId == null) {
            throw new AuraHandledException('Choose who should review the pricing.');
        }
        Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
        req.setObjectId(opportunityId);
        req.setNextApproverIds(new List<Id>{ approverId });
        req.setComments(comments);
        req.setSubmitterId(UserInfo.getUserId());
        try {
            Approval.ProcessResult result = Approval.process(req);
            if (!result.isSuccess()) {
                throw new AuraHandledException(String.valueOf(result.getErrors()));
            }
        } catch (DmlException e) {
            // e.g. "No applicable approval process was found" when the deal isn't below its floor.
            throw new AuraHandledException(e.getDmlMessage(0));
        }
    }

    /**
     * Has Einstein redraft the Pricing Rationale from the current record and saves it.
     * Returns the new text.
     */
    @AuraEnabled
    public static String regenerateRationale(Id opportunityId) {
        String text;
        try {
            text = Test.isRunningTest() ? TEST_RATIONALE : generate(opportunityId);
        } catch (Exception e) {
            throw new AuraHandledException('Einstein couldn\'t draft the rationale: ' + e.getMessage());
        }
        if (String.isBlank(text)) {
            throw new AuraHandledException('Einstein returned an empty rationale. Try again.');
        }
        Opportunity opp = new Opportunity(Id = opportunityId, Pricing_Rationale__c = text.trim().left(5000));
        try {
            update as user opp;
        } catch (DmlException e) {
            // e.g. the record is locked while the approval is pending.
            throw new AuraHandledException(e.getDmlMessage(0));
        }
        return opp.Pricing_Rationale__c;
    }

    private static String generate(Id opportunityId) {
        ConnectApi.WrappedValue oppInput = new ConnectApi.WrappedValue();
        oppInput.value = new Map<String, String>{ 'id' => opportunityId };

        ConnectApi.EinsteinPromptTemplateGenerationsInput input = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        input.inputParams = new Map<String, ConnectApi.WrappedValue>{ 'Input:Opportunity' => oppInput };
        input.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
        input.additionalConfig.applicationName = 'PromptTemplateGenerationsInvocable';
        input.isPreview = false;

        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation output =
            ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(PROMPT_TEMPLATE, input);
        if (output.generations == null || output.generations.isEmpty()) {
            return null;
        }
        return output.generations[0].text;
    }
}
