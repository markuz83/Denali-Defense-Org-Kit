/**
 * Turns a won Opportunity's assetizable product lines into Assets: the customer's installed base.
 * Called by the "Opportunity Create Assets on Win" flow, and by 07_seed_products.apex for demo
 * deals that were won before they had product lines.
 *
 * - One asset per product on the deal, on the deal's account, linked back with Source Opportunity.
 *   Only products with Track as Asset ticked count (labor, implementations and training don't).
 *   It's a kit field rather than the standard Is Assetizable, which needs extra licensing.
 * - Annual services (unit of measure "Year") run from the close date for the line's number of
 *   years, so renewals and option decisions show as the asset's Usage End Date.
 * - Skips products that already have an asset from the same deal, so re-running is safe.
 *
 * Without sharing: it's automation acting for whoever closed the deal, who may not own the account.
 */
public without sharing class OpportunityAssets {

    public class Request {
        @InvocableVariable(label='Opportunity ID' description='A won opportunity' required=true)
        public Id opportunityId;
    }

    @InvocableMethod(
        label='Create Assets from Won Opportunity'
        description='Creates an asset for each Track as Asset product line on a won opportunity, skipping products that already have one.'
        category='Denali')
    public static void createFromFlow(List<Request> requests) {
        Set<Id> ids = new Set<Id>();
        for (Request r : requests) ids.add(r.opportunityId);
        createFor(ids);
    }

    public static List<Asset> createFor(Set<Id> opportunityIds) {
        Set<String> existing = new Set<String>();
        for (Asset a : [SELECT Source_Opportunity__c, Product2Id FROM Asset WHERE Source_Opportunity__c IN :opportunityIds]) {
            existing.add(a.Source_Opportunity__c + ':' + a.Product2Id);
        }

        List<Asset> assets = new List<Asset>();
        for (OpportunityLineItem li : [
            SELECT OpportunityId, Opportunity.AccountId, Opportunity.Name, Opportunity.CloseDate,
                   Product2Id, Product2.Name, Product2.QuantityUnitOfMeasure, Quantity, UnitPrice
            FROM OpportunityLineItem
            WHERE OpportunityId IN :opportunityIds AND Opportunity.IsWon = true
              AND Opportunity.AccountId != null AND Product2.Track_as_Asset__c = true
            ORDER BY Opportunity.Name, SortOrder
        ]) {
            String key = li.OpportunityId + ':' + li.Product2Id;
            if (existing.contains(key)) continue;
            existing.add(key);

            Date starts = li.Opportunity.CloseDate;
            Boolean annual = li.Product2.QuantityUnitOfMeasure == 'Year';
            assets.add(new Asset(
                Name = li.Product2.Name + ' (' + li.Opportunity.Name + ')',
                AccountId = li.Opportunity.AccountId,
                Product2Id = li.Product2Id,
                Source_Opportunity__c = li.OpportunityId,
                Quantity = li.Quantity,
                Price = li.UnitPrice,
                PurchaseDate = starts,
                UsageEndDate = annual ? starts.addYears(li.Quantity.intValue()).addDays(-1) : null,
                Status = 'Purchased'
            ));
        }
        insert assets;
        return assets;
    }
}
