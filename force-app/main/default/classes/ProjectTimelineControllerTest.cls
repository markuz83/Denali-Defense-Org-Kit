@IsTest
private class ProjectTimelineControllerTest {

    @IsTest
    static void returnsTheProjectsLiveDeliverables() {
        Account a = new Account(Name = 'Timeline Agency', Account_Role__c = 'Customer');
        insert a;
        Contract k = new Contract(AccountId = a.Id, Status = 'Draft', StartDate = Date.today(), ContractTerm = 12);
        insert k;
        Project__c p = new Project__c(Name = 'Timeline Project', Contract__c = k.Id, Status__c = 'In Progress');
        insert p;
        insert new List<Deliverable__c>{
            new Deliverable__c(Name = 'Later', Project__c = p.Id, Status__c = 'In Progress', Due_Date__c = Date.today().addDays(30)),
            new Deliverable__c(Name = 'Sooner', Project__c = p.Id, Status__c = 'Not Started', Due_Date__c = Date.today().addDays(10)),
            new Deliverable__c(Name = 'Dropped', Project__c = p.Id, Status__c = 'Cancelled', Due_Date__c = Date.today().addDays(5))
        };

        Test.startTest();
        List<Deliverable__c> result = ProjectTimelineController.getDeliverables(p.Id);
        Test.stopTest();

        Assert.areEqual(2, result.size(), 'Cancelled deliverables are left off');
        Assert.areEqual('Sooner', result[0].Name, 'Ordered by due date');
    }
}
