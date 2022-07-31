/**
 * @description       : this is a class that will be setup in a Salesforce Experience Site as a public API that can accept data from Pivotal Tracker
 * @author            : copyright sfdcboss.com
 */
@RestResource(urlMapping = '/handleInboundPayload/*')
/*
	Defined in PivotalTrackerUpdatePayload but posting here for reference as well.  This is the structure we can expect from the PT Webhooks.
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
	public class internalServerErrorException extends Exception {}
	public static Map<String, String> updateMap = new Map<String, String>(); // a place to store some key/value pairs of updates from the process
	public enum PivotalTracker_kind{
		 // these are the types of updates that PT could potentially send as detailed in their rest api.  only story_update_activity is in scope for this
		pull_request_create_activity, 
		branch_create_activity, 
		story_create_activity, 
		story_update_activity
	}

	/**
	 * handleInboundPayload REST endpoint that will take the pivotal tracker
	 * payload and parse it into Project__c, Project_Items__c, and Tasks
	 * 1. Check if Project Exists -> Upsert Project
	 2. Check if Stories Exist -> Upsert Project Items
	 3. Write changes to Project Items via Tasks
	 4. https://sfdcboss.com/pivotal-tracker-salesforce-data-model
	 * @return   return theJSON inbound from PT
	 */
	@HttpPost
	global static String handleInboundPayload(){
		RestResponse res = RestContext.response;
		PivotalTracker_kind pt_update_kind;
		PivotalTrackerUpdatePayload pl;

		try{
			pl = parseResponse();
			pt_update_kind = PivotalTracker_kind.valueOf(pl.kind);

 		} catch (Exception e){
			res.responseBody = Blob.valueOf(JSON.serialize('error parsing JSON : ' + e.getMessage() + ' - ' + e.getStackTraceString()));
			res.statusCode = 400;
		}


		switch  on pt_update_kind{

			when pull_request_create_activity{
				// handlePullRequestAttached(); future use
			}
			when branch_create_activity{
				// handleBranchAttached(); future use
			}
			when story_create_activity{
				// handleStoryCreated(); future use

			}
			when story_update_activity{

				try{
					Project__c[] projects = handleProjects(pl);
					for (Project__c p : projects){
		 				handleProjectItems(pl, p.Id);
					}
					res.responseBody = Blob.valueOf(JSON.serialize('successfully sync projects and project items and attached logs to Project record..' + updateMap));
					res.statusCode = 200;
					if(pl.project.name == 'TestException') throw new internalServerErrorException('Your Message');
				} catch (Exception e){
					res.responseBody = Blob.valueOf(JSON.serialize('internal server error - message: ' + e.getMessage() + ' - ' + e.getStackTraceString()));
					res.statusCode = 500;
				}



			}
		}

		return res.toString();
	}

	/**
	 * @description        gets the restcontext string that was sent into the API as the body (PivotalTrackerUpdatePayload data structure)
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
		if (thePivotalProject != null) {
 
			// we have a project Id so we will check for an existing project record. if none exists we will create
			// this handles the use case where no Project has been setup in Salesforce so it creates a Project__c record and we will use the project id in PT as an external ID in salesforce

			Map<String, String> storyIdToSFId = new Map<String, String>();
			String theId = String.valueOf(pl.project.id); // get project_id from the pt payload
			proj = doProjectsExistInSF(new Set<String>{ theId }, DateTime.newInstance(pl.occurred_at), pl.project.name).values(); // check for salesforce sobject for project__c , if not create it, return map

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

	public static Map<String, Project__c> doProjectsExistInSF(Set<String> pivotalTrackerProjectIds, DateTime timestamp, String ptProjectName){
		Map<String, Project__c> proj = new Map<String, Project__c>([SELECT Id, Project_Id__c, Last_Project_Update__c
		                                                            FROM Project__c
		                                                            WHERE Project_Id__c IN:pivotalTrackerProjectIds]);
		Map<String, Project__c> projUpsert = new Map<String, Project__c>();
		for (String s : pivotalTrackerProjectIds){
			Boolean keepSearching = true;
			if (proj.size() == 0) {
				keepSearching = true;
			} else {
				for (Project__c p : proj.values()){
					if (keepSearching == true){
						if (p.Project_Id__c == s){
						    keepSearching = false;
							projUpsert.put(s, new Project__c(Id = p.Id, Last_Project_Update__c = system.now(), Project_ID__c = s));
							break;
						} 
					}
				}
			}

			if (keepSearching == true){
				projUpsert.put(s, new Project__c(Name = ptProjectName, Last_Project_Update__c = system.now(), Project_ID__c = s));
			}

		}
		system.debug (projUpsert);
		if (projUpsert.size() > 0)
			upsert projUpsert.values() Project_Id__c;
		for (Project__c p : projUpsert.values()) {
			p.Last_Project_Update__c = system.now();
			proj.put(p.Id, p);
		}
		
		return proj;
	}

	public static Map<String, String> getStoryIdByProjectItemId(PivotalTrackerUpdatePayload pl){
		Map<String, String> storyIdToSFId = new Map<String, String>();
		String[] storyIds = getStoryIdsInPayload(pl);
		Map<Id, Project_Item__c> pitems = new Map<Id, Project_Item__c>([SELECT Id, pt_id__c
		                                                                FROM Project_Item__c
		                                                                WHERE pt_id__c IN:storyIds]);

		for (Project_Item__c pi : pitems.values()) storyIdToSFId.put(pi.pt_id__c, pi.Id);
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

}