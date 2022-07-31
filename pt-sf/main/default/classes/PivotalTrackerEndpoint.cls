/**
 * @description       : this is a class that will be setup in a Salesforce Experience Site as a public API that can accept data from Pivotal Tracker
 * @author            : sfdc boss
 */
@RestResource(urlMapping = '/handleInboundPayload/*')
/*
 PROPERTIES

 kind
 —  The value of 'kind' will reflect the specific type of activity that an activity resource represents. The value will be a string that ends in '_activity' and which starts with a name based on the change which occurred. This field is read only.
 guid
 —  Project id and version of the activity. This field is read only. This field is always returned.
 project_version
 —  The version of the activity. This field is read only. This field is always returned.
 message
 —  Description of the activity. This field is read only.
 highlight
 —  Boldface portion of the message. This field is read only.
 changes
 —  The set of changes. This field is read only.
 primary_resources
 —  The primary resource(s) affected by this command. This field is read only.
 secondary_resources
 —  The secondary resource(s) affected by this command. This field is read only.
 project_id
 —  id of the project. This field is read only. By default this will be included in responses as a nested structure, using the key project.
 performed_by_id
 —  id of the person who performed this change. This field is read only. By default this will be included in responses as a nested structure, using the key performed_by.
 occurred_at
 —  Time of the activity. This field is read only.
 */
global without sharing class PivotalTrackerEndpoint{
	public static Map<String, String> updateMap = new Map<String, String>(); // a place to store some key/value pairs of updates from the process
	public enum PivotalTracker_kind{ // these are the types of updates that PT could potentially send as detailed in their rest api.  only story_update_activity is in scope for this
		pull_request_create_activity, 
		branch_create_activity, 
		story_create_activity,
		story_update_activity
	}

	/**
	 * handleInboundPayload REST endpoint that will take the pivotal tracker
	 * payload and parse it into Project__c, Project_Items__c, and Tasks
	 * @return   return theJSON inbound from PT
	 */
	@HttpPost
	global static String handleInboundPayload(){
		try{
			PivotalTrackerUpdatePayload pl = parseResponse();
			PivotalTracker_kind pt_update_kind = PivotalTracker_kind.valueOf(pl.kind);

			switch  on pt_update_kind{

				when pull_request_create_activity{
					// handlePullRequestAttached();
				}
				when branch_create_activity{
					// handleBranchAttached();
				}
				when story_create_activity{
					// handleStoryCreated();

				}
				when else{

					Project__c[] projects = handleProjects(pl);
					for (Project__c p : projects){
						String projectId = p.Id;
						handleProjectItems(pl, projectId);
						//handleProjectItemChanges(pl, projectId);
						//createTaskRawDataForProject(pl, projectId);
					}

				}
			}
		} catch (Exception e){
			system.debug('error : ' + e.getMessage() + ' - ' + e.getStackTraceString());
		}

		return 'success';
	}

	/**
	 * @description
	 1. Check if Project Exists -> Upsert Project
	 2. Check if Stories Exist -> Upsert Project Items
	 3. Insert Raw Data in Project Task
	 4. Write changes to Project Items via Tasks
	 5. https://sfdcboss.com/pivotal-tracker-salesforce-data-model
	 @author sfdcboss
	 **/
	public static PivotalTrackerUpdatePayload parseResponse(){
		String json = RestContext.request.requestBody.toString(); /* reach into the requestBody and get the details */
		PivotalTrackerUpdatePayload thePayload = PivotalTrackerUpdatePayload.parse(json) ;
		return thePayload;
	}

	public static Project__c[] handleProjects(PivotalTrackerUpdatePayload pl){

		String thePivotalProject = pl != null && pl.project != null ? String.valueOf(pl.project.id) : null;
		Project__c[] proj = new List<Project__c>();
		if (thePivotalProject == null){
			updateMap.put('handleProjects', 'Project Id in Payload missing, cant continue');
		} else{

			// we have a project Id so we will check for an existing project record. if none exists we will create
			// this handles the use case where no Project has been setup in Salesforce so it creates a Project__c record and we will use the project id in PT as an external ID in salesforce

			Map<String, String> storyIdToSFId = new Map<String, String>();
			String theId = String.valueOf(pl.project.id); // get project_id from the pt payload
			proj = doProjectsExistInSF(new Set<String>{ theId }, DateTime.newInstance(pl.occurred_at)).values(); // check for salesforce sobject for project__c , if not create it, return map

		}
		updateMap.put('handleProjects', 'Synced Project Records, Ids: ' + proj);
		return proj;
	}

	public static void handleProjectItems(PivotalTrackerUpdatePayload pl, String projectId){
		Project_Item__c[] projectItemsToInsert = createProjectItems(projectId, pl);
		updateMap.put('handleProjectItems', 'Synced Project Items Records, Ids: ' + projectItemsToInsert);
	}

	public static Project_Item__c[] createProjectItems(String projectId, PivotalTrackerUpdatePayload pl){
		String theId = String.valueOf(pl.project.id);

		Project_Item__c[] projectItems = new List<Project_Item__c>(); /* used to insert Project Items */
		Map<String, String> storyIdToSFId = getStoryIdByProjectItemId(pl);

		for (PivotalTrackerUpdatePayload.Primary_resources pr : pl.primary_resources){
			String theStoryId = pr.id != null ? String.valueOf(pr.id) : '';
			projectItems.add(new Project_Item__c(Data__c = String.valueOf(pl), Project__c = projectId, pt_id__c = theStoryId, pt_url__c = pr.url != null ? String.valueOf(pr.url) : '', pt_story_type__c = pr.story_type != null ? String.valueOf(pr.story_type) : '', pt_kind__c = pr.kind != null ? String.valueOf(pr.kind) : '', pt_name__c = pr.name != null ? String.valueOf(pr.name) : '', Id = storyIdToSFId.containsKey(theStoryId) ? theStoryId : null));

		}
		
		upsert projectItems;

		return projectItems;
	}

	public static Map<String, Project__c> doProjectsExistInSF(Set<String> pivotalTrackerProjectIds, DateTime timestamp){
		Map<String, Project__c> proj = new Map<String, Project__c>([SELECT Id,Project_Id__c,Last_Project_Update__c
		                                                    FROM Project__c
		                                                    WHERE Project_Id__c IN:pivotalTrackerProjectIds]);
		Map<String, Project__c> projUpsert = new Map<String, Project__c>();
		for (String s : pivotalTrackerProjectIds){
			Boolean keepSearching = true;
			for (Project__c p : proj.values()){
				if (keepSearching == true){
					if (p.Project_Id__c == s){
						//found project
						keepSearching = false;
					} else{
						//no project
						keepSearching = true;
					}
					p.Last_Project_Update__c = timestamp;

				}
			}
			if (keepSearching == true){
				projUpsert.put(s, new Project__c(Last_Project_Update__c = timestamp, Project_ID__c = s));
			}

		}
		if (projUpsert.size() > 0)
			upsert projUpsert.values()Project_Id__c;
		for (Project__c p : projUpsert.values())
			proj.put(p.Id, p);
		return proj;
	}

	public static Map<String, String> getStoryIdByProjectItemId(PivotalTrackerUpdatePayload pl){
		Map<String, String> storyIdToSFId = new Map<String, String>();

		String[] storyIds = getStoryIdsInPayload(pl);
		Map<Id, Project_Item__c> pitems = new Map<Id, Project_Item__c>([SELECT Id, pt_id__c
		                                                                FROM Project_Item__c
		                                                                WHERE pt_id__c IN:storyIds]);

		for (Project_Item__c pi : pitems.values()){
			storyIdToSFId.put(pi.pt_id__c, pi.Id);
		}
		return storyIdToSFId;
	}

	public static List<String> getStoryIdsInPayload(PivotalTrackerUpdatePayload pl){
		Project_Item__c[] projectItems = new List<Project_Item__c>();

		// we know Pivotal Tracker will send data over as "primary resource, so we are grabbing that
		String[] storyIds = new List<String>();
		for (PivotalTrackerUpdatePayload.Primary_resources pr : pl.primary_resources){
			storyIds.add(String.valueOf(pr.id));
		}
		return storyIds;
	}

	/*
	 public static void handleStoryCreated(){
	 String method = 'GET';
	 String pivotalTrackerProjectId = '2501714';
	 String[] pivotalTrackerStoryId = getStoryIdsInPayload(pl);
	 PivotalTrackerService.PivotalTrackerStory story = PivotalTrackerService.PT_EndPoint_Story(
	 method,
	 pivotalTrackerProjectId,
	 PivotalTrackerStoryId[0],
	 new List<String>{ pivotalTrackerProjectId, pivotalTrackerStoryId[0] }
	 );
	 system.debug(story);
	 String theDescription = story.description;
	 system.debug('the story description from the project record ::: ' + story);
	 PivotalTrackerService.PivotalTrackerStory storyupdate = new PivotalTrackerService.PivotalTrackerStory();
	 storyupdate=story;
	 String theStoryTemplate = [SELECT Story_Template__c FROM Project__c WHERE Name = 'Test Project' LIMIT 1].Story_Template__c;
	 if (theStoryTemplate.contains('zzdescriptionzz')) theStoryTemplate = theStoryTemplate.replaceAll('zzdescriptionzz', theDescription);
	 system.debug(theStoryTemplate);
	 storyupdate.description = theStoryTemplate;
	 storyupdate.project_id = null;
	 PivotalTrackerService.PivotalTrackerStory[] storyupdated = PivotalTrackerService.PT_EndPoint_Stories(
	 'PUT',
	 pivotalTrackerProjectId,
	 PivotalTrackerStoryId[0],
	 new List<PivotalTrackerService.PivotalTrackerStory>{storyupdate}
	 );
	 }
	 public static List<String> getPrimaryResourceValues() {
	 Project_Item__c[] projectItems = new List<Project_Item__c>();
	 String[] primaryResources = new List<String>();
	 for (PivotalTrackerUpdatePayload.Primary_resources pr : pl.primary_resources) {
	 primaryResources.add(String.valueOf(pr.id));
	 }
	 return primaryResources;
	 }





	 public static void getExistingDataForStory(){

	 }

	 public static void setTemplateStoryNew(){

	 }

	 public static void handleBranchAttached() {
	 /* this should take the PR data coming in from the endpoint update and write it to a Deployment Item record

	 // external ids
	 // Deployment - Build_Source_Branch__c
	 // Deployment Items - Git_Branch__c
	 // Project Item - theStory ()
	 // Sandbox Name is the branch

	 PivotalTrackerUpdatePayload thePL = pl;
	 Map<String, String> branchToProjectItem = new Map<String, String>();
	 String theBranch = '';
	 String theSlackMessage = '<b>Pivotal Tracker Integration Activity</b>';
	 if (thePL.kind == 'branch_create_activity') {
	 system.debug('inside PR activity');
	 String theMessage = thePL.message;
	 String thePRName = theMessage.substringAfter('created branch: ');
	 String theorganization = thePRName.substringBefore('/');
	 String theRepo = theMessage.substringAfterLast('/').substringAfterLast(' ');
	 theBranch = thePRName.substringAfterLast(' ').replaceAll('"', '');
	 theSlackMessage = theSlackMessage + '<ul><li>Branch *'+theBranch+'* added in Pivotal Tracker.</li>';
	 system.debug('inside PR activity theMessage :: ' + theMessage);
	 system.debug('inside PR activity thePRName :: ' + thePRName);
	 system.debug('inside PR activity theorganization :: ' + theorganization);
	 system.debug('inside PR activity theRepo :: ' + theRepo);
	 system.debug('inside PR activity theBranch :: ' + theBranch);

	 PivotalTrackerUpdatePayload.Primary_resources[] thePrimaryResources = thePL.primary_resources;
	 Integer theStory = 0;
	 Project_Item__c[] pItems;
	 // create a sandbox!
	 Project_Item__c[] theP;
	 Boolean needsUpdate = false;
	 String theProjectId = '';
	 if (thePrimaryResources.size() > 0) {
	 theStory = thePrimaryResources[0].id;
	 pItems = [
	 SELECT Id, Name, Git_Branch__c, Git_Pull_Request__c, Git_PR_Full_Name__c, Project__c, Deployment_Item__c,Deployment_Item__r.Name
	 FROM Project_Item__c
	 WHERE pt_Id__c = :theStory
	 ];
	 if (pItems.size() > 0) {
	 // this means that we did find stories via Project Item c by PT id
	 for (Project_Item__c pItem : pItems) {
	 branchToProjectItem.put(theBranch, pItem.Id);
	 pItem.Git_Branch__c = theBranch;
	 needsUpdate = true;
	 }
	 }

	 if (needsUpdate)
	 update pItems;
	 }

	 Deployment__c[] deployments = [
	 SELECT Id,Name
	 FROM Deployment__c
	 WHERE Build_Source_Branch__c = :theBranch
	 ORDER BY CreatedDate DESC
	 LIMIT 1
	 ];
	 Boolean needsChanged = false;

	 Deployment_Items__c[] deploymentItems = new List<Deployment_Items__c>();

	 Boolean createdNotUpdated = false;

	 if (deployments.size() == 0) {
	 deployments.add(new Deployment__c(Build_Source_Branch__c=theBranch));
	 insert deployments;
	 theSlackMessage = theSlackMessage + '<li>Created Deployment record for *'+theBranch+'*.</li>';

	 } else {
	 theSlackMessage += '<li>Deployment record *' + deployments[0].Name + '* exists for *'+theBranch+'* and will be used.</li>';

	 }

	 if (deployments.size() > 0) {
	 for (Deployment__c deployment : deployments) {
	 deployment.Project_Item__c = branchToProjectItem.get(theBranch);

	 deploymentItems.add(
	 new Deployment_Items__c(
	 Git_Branch__c = theBranch,
	 Deployment__c = deployment.Id,
	 Project_Item__c = branchToProjectItem.get(theBranch)
	 )
	 );
	 needsChanged = true;
	 }
	 }

	 Map<String,String> branchToDepId = new Map<String,String>();
	 if (needsChanged)
	 upsert deployments;
	 if (deploymentItems.size() > 0) {
	 insert deploymentItems;


	 for (Deployment_Items__c di : [
	 SELECT Id,Name, Project_Item__c,Project_Item__r.Name,Git_Branch__c
	 FROM Deployment_Items__c
	 ORDER BY CreatedDate DESC LIMIT 1]) branchToDepId.put(di.Git_Branch__c, di.Id);

	 String theDeploymentItemName = '';
	 String theDeploymentItemId = '';
	 String theProjectItemName = '';
	 String theProjectItemId = '';
	 pItems = [
	 SELECT Id, Name, Git_Branch__c, Git_Pull_Request__c, Git_PR_Full_Name__c, Project__c, Deployment_Item__c,Deployment_Item__r.Name
	 FROM Project_Item__c
	 WHERE pt_Id__c = :theStory];
	 for (Project_Item__c pi : pItems) {
	 pi.Deployment_Item__c = branchToDepId.get(pi.Git_Branch__c) == null ? '' : branchToDepId.get(pi.Git_Branch__c);
	 theDeploymentItemId = pi.Deployment_Item__c;
	 theDeploymentItemName = pi.Deployment_Item__r.Name;
	 theProjectItemName = pi.Name;
	 theProjectItemId = pi.Id;
	 }
	 update pItems;
	 theSlackMessage = theSlackMessage +  '<li>Deployment Item '+(needsChanged==true?'created':'found')+' and linked to Project Item: *'+theProjectItemName+ '* --  Branch: *' + theBranch+'*.</li></ul>';


	 }

	 //system.debug (pi);

	 BT_Utils.postToSlack(theSlackMessage);
	 }
	 //handleSandboxCreation(theBranch);
	 //insertOrgRecord();

	 }
	 @future(callout=true)
	 public static void handleSandboxCreation(String branch){
	 // check for existing sandbox:
	 Boolean sandboxExists = SandboxUtils.doesSandboxExist(branch);
	 String theIdSandbox = '';

	 if (!sandboxExists){
	 SandboxUtils.createSandbox(branch,'');
	 BT_Utils.postToSlack('<b>Deployment Activity</b><ul><li>Sandbox has been created for *'+branch+'*.</li></ul>');
	 } else {
	 // do something
	 BT_Utils.postToSlack('<b>Deployment Activity</b><ul><li>Sandbox creation skipped for *'+branch+'*.  Already exists.</li></ul>');

	 }
	 }

	 @future
	 public static void insertOrgRecord(){

	 }


	 public static void handlePullRequestAttached() {
	 /* this should take the PR data coming in from the endpoint update and write it to a Deployment Item record *

	 PivotalTrackerUpdatePayload thePL = pl;
	 if (thePL.kind == 'pull_request_create_activity') {
	 system.debug('inside PR activity');
	 String theMessage = thePL.message;
	 String thePRName = theMessage.substringAfter('added pull request: ');
	 String theorganization = thePRName.substringBefore('/');
	 String theRepo = theMessage.substringAfterLast('/').substringBefore(' PR ');
	 String thePRNumber = thePRName.substringAfterLast(' PR ').replaceAll('"', '');
	 system.debug('inside PR activity theMessage :: ' + theMessage);
	 system.debug('inside PR activity thePRName :: ' + thePRName);
	 system.debug('inside PR activity theorganization :: ' + theorganization);
	 system.debug('inside PR activity theRepo :: ' + theRepo);
	 system.debug('inside PR activity thePRNumber :: ' + thePRNumber);

	 PivotalTrackerUpdatePayload.Primary_resources[] thePrimaryResources = thePL.primary_resources;
	 Integer theStory = 0;
	 Project_Item__c[] theP;
	 Boolean needsUpdate = false;

	 if (thePrimaryResources.size() > 0) {
	 theStory = thePrimaryResources[0].id;
	 Project_Item__c[] pItems = [
	 SELECT Id, Name, Git_Branch__c, Git_Pull_Request__c, Git_PR_Full_Name__c
	 FROM Project_Item__c
	 WHERE pt_Id__c = :theStory
	 ];
	 if (pItems.size() > 0) {
	 // this means that we did find stories via Project Item c by PT id
	 for (Project_Item__c pItem : pItems) {
	 pItem.Git_Branch__c = thePRName;
	 pItem.Git_Pull_Request__c = thePRNumber;
	 pItem.Git_PR_Full_Name__c = thePRName;
	 needsUpdate = true;
	 }
	 }

	 if (needsUpdate)
	 update pItems;
	 }
	 }
	 }


	 public static Project_Item__c[] deDupeProjectItems(Project_Item__c[] projectItems) {
	 Map<Id, Project_Item__c> projectItemsMap = new Map<Id, Project_Item__c>();
	 Project_Item__c[] projectItemsDedupe = new List<Project_Item__c>();

	 for (Project_Item__c pi : projectItems) {
	 if (pi.Id != null) {
	 projectItemsMap.put(pi.Id, pi);
	 } else {
	 projectItemsDedupe.add(pi);
	 }
	 }
	 projectItemsDedupe.addAll(projectItemsMap.values());
	 return projectItemsDedupe;
	 }

	 public static void handleProjectItemChanges() {
	 /* now we have our project + project items, lets log the specific changes to tasks
	 Task[] theTasks = createChangesForProjectItemTasks(pl);
	 insert theTasks;
	 }

	 public static List<String> getStoryIdsInPayload(PivotalTrackerUpdatePayload pl) {
	 Project_Item__c[] projectItems = new List<Project_Item__c>();

	 // we know Pivotal Tracker will send data over as "primary resource, so we are grabbing that
	 String[] storyIds = new List<String>();
	 for (PivotalTrackerUpdatePayload.Primary_resources pr : pl.primary_resources) {
	 storyIds.add(String.valueOf(pr.id));
	 }
	 return storyIds;
	 }

	 public static Map<String, String> getStoryIdByProjectItemId(PivotalTrackerUpdatePayload pl) {
	 Map<String, String> storyIdToSFId = new Map<String, String>();

	 String[] storyIds = getStoryIdsInPayload(pl);
	 Map<Id, Project_Item__c> pitems = new Map<Id, Project_Item__c>(
	 [SELECT Id, Story_Id__c FROM Project_Item__c WHERE Story_Id__c IN :storyIds]
	 );

	 for (Project_Item__c pi : pitems.values()) {
	 storyIdToSFId.put(pi.Story_Id__c, pi.Id);
	 }
	 return storyIdToSFId;
	 }



	 public static Project__c createProjectRecord(
	 String projectName,
	 String jsonData,
	 String projectId
	 ) {
	 Project__c project = new Project__c(
	 Name = projectName,
	 JSON__c = jsonData,
	 Project_Id__c = projectId
	 );
	 return project;
	 }



	 public static Task[] createTaskRawDataForProject(PivotalTrackerUpdatePayload pl, String projectId) {
	 Task[] insertTasks = new List<Task>();
	 Task theRawData = new Task(
	 Subject = 'Raw Data Inbound - ' + pl.message + ' - ' + system.today().format(),
	 WhatId = projectId,
	 Description = pl.toString(),
	 Status = 'Completed',
	 OwnerId = userInfo.getUserId()
	 );
	 insertTasks.add(theRawData);
	 system.debug('projectId :: ' + projectId);
	 return insertTasks;
	 }

	 public static Task[] createChangesForProjectItemTasks(PivotalTrackerUpdatePayload pl) {
	 Task[] insertTasks = new List<Task>(); /* used to insert multi change payloads on a Project Item
	 Map<String, String> theIds = getStoryIdByProjectItemId(pl);
	 PivotalTrackerUpdatePayload.Changes[] changes = pl.changes;
	 Map<String, String> theNewValuesCurrentState = new Map<String, String>();
	 String projectId = '';
	 projectId = String.valueOf(pl.project.id);
	 for (PivotalTrackerUpdatePayload.Changes change : changes) {
	 PivotalTrackerUpdatePayload.New_values newVals;
	 PivotalTrackerUpdatePayload.Original_values originalVals;
	 newVals = change.new_values;
	 originalVals = change.original_values;

	 Task theTask = new Task(
	 New_Values_Accepted_At__c = newvals == null
	 ? ''
	 : String.valueOf(newVals.accepted_at),
	 New_Values_After_Id__c = newvals == null ? '' : String.valueOf(newVals.after_id),
	 New_Values_Before_Id__c = newvals == null ? '' : String.valueOf(newVals.before_id),
	 New_Values_Current_State__c = newvals == null
	 ? ''
	 : String.valueOf(newVals.current_state),
	 New_Values_Updated_At__c = newvals == null ? '' : String.valueOf(newVals.updated_at),
	 Original_Values_Updated_At__c = originalVals == null
	 ? ''
	 : String.valueOf(originalVals.updated_at),
	 Original_Values_Accepted_At__c = originalVals == null
	 ? ''
	 : String.valueOf(originalVals.accepted_at),
	 Original_Values_After_Id__c = originalVals == null
	 ? ''
	 : String.valueOf(originalVals.after_id),
	 Original_Values_Before_Id__c = originalVals == null
	 ? ''
	 : String.valueOf(originalVals.before_id),
	 Original_Values_Current_State__c = originalVals == null
	 ? ''
	 : String.valueOf(originalVals.current_state),
	 Subject = change.name + ' - ' + change.change_type,
	 WhatId = theIds.get(String.valueOf(change.id)),
	 Description = change.name + change.story_type + change.new_values + change.original_values,
	 //Name = change.name,
	 Story_Type__c = change.story_type,
	 New_Values__c = change.new_values != null ? change.new_values.toString() : '',
	 Old_Values__c = change.original_values != null ? change.original_values.toString() : '',
	 Change_Id__c = String.valueOf(change.id),
	 Change_Type__c = change.change_type,
	 Change_Kind__c = change.kind,
	 Status = 'Completed'
	 );

	 insertTasks.add(theTask);
	 }
	 for (Task t : insertTasks) {
	 if (t.Change_Id__c != null && t.New_Values_Current_State__c != null) {
	 theNewValuesCurrentState.put(t.Change_Id__c, t.New_Values_Current_State__c);
	 }
	 }
	 Project_Item__c[] theItems = new List<Project_Item__c>();
	 String projectItemId='';
	 if (theNewValuesCurrentState.size() > 0) {
	 for (String s : theNewValuesCurrentState.keySet()) {
	 Project_Item__c projectItem = new Project_Item__c(
	 Project__c = [SELECT Id FROM Project__c WHERE Project_Id__c = :projectId]?.Id,
	 pt_Id__c = Decimal.valueOf(s),
	 Story_Status__c = theNewValuesCurrentState.get(s)
	 );
	 String theState = theNewValuesCurrentState.get(s);
	 Deployment_Items__c depItem;
	 switch on theState {
	 when 'accepted' {
	 //projectItem.. = now();
	 depItem = new Deployment_Items__c(
	 Deployment__c = getDeploymentRecord()

	 );
	 insert depItem;
	 //depItem.Deployment__c = getDeploymentRecord();
	 projectItem.Accepted_Timestamp__c = System.Now();
	 }
	 when 'planned' {
	 projectItem.Planned_Timestamp__c = System.Now();
	 }
	 when 'started' {
	 projectItem.Started_Timestamp__c = System.Now();
	 }
	 when 'unstarted' {
	 projectItem.Unstarted_Timestamp__c = System.Now();
	 }
	 when 'finished' {
	 projectItem.Finished_Timestamp__c = System.Now();
	 }
	 when 'delivered' {
	 projectItem.Planned_Timestamp__c = System.Now();
	 }
	 // TODO: Add to project trigger
	 }
	 projectItem.Deployment_Item__c = depItem.Id;
	 theItems.add(projectItem);
	 }
	 }
	 if (theItems.size() > 0)
	 upsert theItems pt_Id__c;
	 return insertTasks;
	 }

	 public static string getDeploymentRecord(){
	 // this should find a Deployment with a label of 'Accepted' for the Deployment Category
	 List<Deployment__c> theExisting = [SELECT Id FROM Deployment__c WHERE Status__c != 'Deployed' AND Deployment_Category__c='Accepted'];//new List<Deployment__c>();

	 String theDeploymentId = '';
	 if(theExisting.size() == 0){
	 Deployment__c theDeployment = new Deployment__c(
	 Deployment_Category__c = 'Accepted',
	 Status__c = 'New'
	 );
	 insert theDeployment;
	 theDeploymentId = theDeployment.Id;
	 } else {
	 theDeploymentId = theExisting[0].Id;
	 }
	 return theDeploymentId;
	 }
	 */
}