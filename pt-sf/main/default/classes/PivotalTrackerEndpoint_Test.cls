@isTest
public with sharing class PivotalTrackerEndpoint_Test{
    @isTest
    static void testPivotalTrackerUpdatePayloadCreateProjectAndProjectItems(){

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        PivotalTrackerUpdatePayload pl = new PivotalTrackerUpdatePayload();
        PivotalTrackerUpdatePayload.Primary_resources pr = new PivotalTrackerUpdatePayload.Primary_resources();
        pr.kind = 'test';
        pr.name = 'test project item';
        pr.story_type = 'test story type';
        pr.url = 'https://testurl.com';
        pl.primary_resources = new List<PivotalTrackerUpdatePayload.Primary_resources>{ pr };
        pl.project = new PivotalTrackerUpdatePayload.Project();
        pl.project.id = 111111;
        pl.project.name = 'sfdcboss';
        pl.project.kind = 'project kind';
        pl.kind = 'story_update_activity';
        pl.occurred_at = 1346524199000l;
        req.requestURI = '/services/apexrest/handleInboundPayload/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(pl));

        RestContext.request = req;
        RestContext.response = res;

        Integer countProjects = [SELECT Count()
                                 FROM Project__c];
        system.assertEquals(countProjects, 0);

        Test.startTest();
        PivotalTrackerEndpoint.handleInboundPayload();
        Test.stopTest();

        Project__c[] newProjectCreated = [SELECT Id, Name
                                          FROM Project__c];
        system.assertEquals(newProjectCreated.size(), 1);
        System.assertEquals(newProjectCreated[0].Name, 'sfdcboss');
        System.assertEquals(200, res.statusCode);
    }

    @isTest
    static void testPivotalTrackerUpdatePayloadCreateProjectAndProjectItemsProjectExists(){

        insert new Project__c(Name='sfdcboss', last_Project_update__c = system.now(), Project_Id__c = '111111');
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        PivotalTrackerUpdatePayload pl = new PivotalTrackerUpdatePayload();
        PivotalTrackerUpdatePayload.Primary_resources pr = new PivotalTrackerUpdatePayload.Primary_resources();
        pr.kind = 'test';
        pr.name = 'test project item';
        pr.story_type = 'test story type';
        pr.url = 'https://testurl.com';
        pl.primary_resources = new List<PivotalTrackerUpdatePayload.Primary_resources>{ pr };
        pl.project = new PivotalTrackerUpdatePayload.Project();
        pl.project.id = 111111;
        pl.project.name = 'sfdcboss';
        pl.project.kind = 'project kind';
        pl.kind = 'story_update_activity';
        pl.occurred_at = 1346524199000l;
        req.requestURI = '/services/apexrest/handleInboundPayload/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(pl));

        RestContext.request = req;
        RestContext.response = res;

        Integer countProjects = [SELECT Count()
                                 FROM Project__c];
        system.assertEquals(countProjects, 1);

        Test.startTest();
        PivotalTrackerEndpoint.handleInboundPayload();
        Test.stopTest();

        Project__c[] newProjectCreated = [SELECT Id, Name,Last_Project_Update__c
                                          FROM Project__c];
        system.assertEquals(newProjectCreated.size(), 1);
        System.assertEquals(newProjectCreated[0].Name, 'sfdcboss');
        System.assertNotEquals(newProjectCreated[0].Last_Project_Update__c, null);
        System.assertEquals(200, res.statusCode);
    }

    @isTest
    static void negativeTestParseError(){

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        req.requestURI = '/services/apexrest/handleInboundPayload/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('22394$@@#@$@@1231201-321-303-');

        RestContext.request = req;
        RestContext.response = res;

        Integer countProjects = [SELECT Count()
                                 FROM Project__c];
        system.assertEquals(countProjects, 0);

        Test.startTest();
        PivotalTrackerEndpoint.handleInboundPayload();
        Test.stopTest();

        Project__c[] newProjectCreated = [SELECT Id, Name
                                          FROM Project__c];
        system.assertEquals(newProjectCreated.size(), 0);
        System.assertEquals(400, res.statusCode);
    }

    @isTest
    static void testPivotalTrackerUpdatePayloadCreateProjectAndProjectItemsNegative500(){

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        PivotalTrackerUpdatePayload pl = new PivotalTrackerUpdatePayload();
        PivotalTrackerUpdatePayload.Primary_resources pr = new PivotalTrackerUpdatePayload.Primary_resources();
        pr.kind = 'test';
        pr.name = 'test project item';
        pr.story_type = 'test story type';
        pr.url = 'https://testurl.com';
        pl.primary_resources = new List<PivotalTrackerUpdatePayload.Primary_resources>{ pr };
        pl.project = new PivotalTrackerUpdatePayload.Project();
        pl.project.id = null  ;
        pl.project.name = 'TestException';
        pl.project.kind = 'project kind';
        pl.kind = 'story_update_activity';
        pl.occurred_at = 1346524199000l;
        req.requestURI = '/services/apexrest/handleInboundPayload/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(pl));

        RestContext.request = req;
        RestContext.response = res;

        Integer countProjects = [SELECT Count()
                                 FROM Project__c];
        system.assertEquals(countProjects, 0);

        Test.startTest();
        PivotalTrackerEndpoint.handleInboundPayload();
        Test.stopTest();

        Project__c[] newProjectCreated = [SELECT Id, Name
                                          FROM Project__c];
        system.assertEquals(newProjectCreated.size(), 0);
         System.assertEquals(500, res.statusCode);
    }

    @isTest
    static void testPivotalTrackerUpdatePayloadCreateProjectAndProjectItemsPIExists(){

        insert new Project__c(Name='Existing Project');
        insert new Project_Item__c(pt_id__c='00000',Project__c = [SELECT Id FROM Project__c LIMIT 1].Id);
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        PivotalTrackerUpdatePayload pl = new PivotalTrackerUpdatePayload();
        PivotalTrackerUpdatePayload.Primary_resources pr = new PivotalTrackerUpdatePayload.Primary_resources();
        pr.kind = 'test';
        pr.name = 'test project item';
        pr.story_type = 'test story type';
        pr.id = 00000;
        pr.url = 'https://testurl.com';
        pl.primary_resources = new List<PivotalTrackerUpdatePayload.Primary_resources>{ pr };
        pl.project = new PivotalTrackerUpdatePayload.Project();
        pl.project.id = null  ;
        pl.project.name = 'sfdcboss';
        pl.project.kind = 'project kind';
        pl.kind = 'story_update_activity';
        pl.occurred_at = 1346524199000l;
        req.requestURI = '/services/apexrest/handleInboundPayload/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(pl));

        RestContext.request = req;
        RestContext.response = res;

        Integer countProjects = [SELECT Count()
                                 FROM Project__c];
        system.assertEquals(countProjects, 1);

        Test.startTest();
        PivotalTrackerEndpoint.handleInboundPayload();
        Test.stopTest();

        Project__c[] newProjectCreated = [SELECT Id, Name
                                          FROM Project__c];
         
    }

}