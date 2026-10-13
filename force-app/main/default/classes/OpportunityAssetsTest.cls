@IsTest
private class OpportunityAssetsTest {

    static String pv(Schema.SObjectField f, String preferred) {
        for (Schema.PicklistEntry e : f.getDescribe().getPicklistValues()) {
            if (e.isActive() && e.getValue() == preferred) return preferred;
        }
        return null;
    }

    @TestSetup
    static void setup() {
        String openStage = [SELECT ApiName FROM OpportunityStage WHERE IsActive = true AND IsClosed = false ORDER BY SortOrder LIMIT 1].ApiName;
        Account customer = new Account(Name = 'Asset Test Agency', Account_Role__c = 'Customer');
        insert customer;

        Product2 service = new Product2(Name = 'Test Managed Service', ProductCode = 'TEST-MS', IsActive = true, Track_as_Asset__c = true,
            QuantityUnitOfMeasure = pv(Product2.QuantityUnitOfMeasure, 'Year'));
        Product2 labor = new Product2(Name = 'Test Labor', ProductCode = 'TEST-LC', IsActive = true, Track_as_Asset__c = false);
        insert new List<Product2>{ service, labor };
        Id standard = Test.getStandardPricebookId();
        PricebookEntry serviceEntry = new PricebookEntry(Pricebook2Id = standard, Product2Id = service.Id, UnitPrice = 100000, IsActive = true);
        PricebookEntry laborEntry = new PricebookEntry(Pricebook2Id = standard, Product2Id = labor.Id, UnitPrice = 150, IsActive = true);
        insert new List<PricebookEntry>{ serviceEntry, laborEntry };

        // Above the Cost Plus floor, so closing isn't held by the margin gate; no contract on win.
        Opportunity o = new Opportunity(Name = 'Asset Test Deal', AccountId = customer.Id, StageName = openStage,
            CloseDate = Date.today(), Pricebook2Id = standard, Contract_Type__c = 'Cost Plus', Estimated_Margin__c = 10,
            Create_Contract_on_Win__c = false);
        insert o;
        insert new List<OpportunityLineItem>{
            new OpportunityLineItem(OpportunityId = o.Id, PricebookEntryId = serviceEntry.Id, Quantity = 2, UnitPrice = 100000),
            new OpportunityLineItem(OpportunityId = o.Id, PricebookEntryId = laborEntry.Id, Quantity = 400, UnitPrice = 150)
        };
    }

    @IsTest
    static void closingWonCreatesAssetsForTrackedProductsOnly() {
        Opportunity o = [SELECT Id, CloseDate FROM Opportunity WHERE Name = 'Asset Test Deal'];
        Test.startTest();
        update new Opportunity(Id = o.Id, StageName = 'Closed Won');   // the flow calls OpportunityAssets
        Test.stopTest();

        List<Asset> assets = [SELECT Name, Product2.Name, Quantity, Price, PurchaseDate, UsageEndDate, Status, AccountId
                              FROM Asset WHERE Source_Opportunity__c = :o.Id];
        Assert.areEqual(1, assets.size(), 'Only the Track as Asset product becomes an asset');
        Asset a = assets[0];
        Assert.areEqual('Test Managed Service (Asset Test Deal)', a.Name);
        Assert.areEqual(2, a.Quantity);
        Assert.areEqual(100000, a.Price);
        Assert.areEqual(o.CloseDate, a.PurchaseDate);
        Assert.areEqual('Purchased', a.Status);
        if (pv(Product2.QuantityUnitOfMeasure, 'Year') != null) {
            Assert.areEqual(o.CloseDate.addYears(2).addDays(-1), a.UsageEndDate, 'Two years of an annual service');
        }
    }

    @IsTest
    static void rerunningDoesNotDuplicate() {
        Opportunity o = [SELECT Id FROM Opportunity WHERE Name = 'Asset Test Deal'];
        update new Opportunity(Id = o.Id, StageName = 'Closed Won');
        Test.startTest();
        OpportunityAssets.Request r = new OpportunityAssets.Request();
        r.opportunityId = o.Id;
        OpportunityAssets.createFromFlow(new List<OpportunityAssets.Request>{ r });
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM Asset WHERE Source_Opportunity__c = :o.Id]);
    }

    @IsTest
    static void openDealsGetNoAssets() {
        Opportunity o = [SELECT Id FROM Opportunity WHERE Name = 'Asset Test Deal'];
        Test.startTest();
        List<Asset> created = OpportunityAssets.createFor(new Set<Id>{ o.Id });
        Test.stopTest();

        Assert.areEqual(0, created.size());
    }
}
