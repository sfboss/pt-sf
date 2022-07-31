global class PivotalTrackerUpdatePayload {

	public enum kindTypes { pull_request_create_activity, pull_request }

	public class New_values {
		public Long accepted_at;
		public Integer before_id;
		public Integer after_id;
		public String current_state;
		public Long updated_at;
	}

	public class Changes {
		public String story_type;
		public String name;
		public New_values new_values;
		public Original_values original_values;
		public Integer id;
		public String change_type;
		public String kind;
	}

	public class Project {
		public String name;
		public Integer id;
		public String kind;
	}

	public class Primary_resources {
		public String story_type;
		public String name;
		public String url;
		public Integer id;
		public String kind;
	}

	public class Performed_by {
		public String name;
		public String initials;
		public Integer id;
		public String kind;
	}

	public Long occurred_at;
	public String highlight;
	public List<Primary_resources> primary_resources;
	public List<Changes> changes;
	public String message;
	public Integer project_version;
	public Performed_by performed_by;
	public String guid;
	public Project project;
	public String kind;

	public class Original_values {
		public Object accepted_at;
		public Integer before_id;
		public Integer after_id;
		public String current_state;
		public Long updated_at;
	}

	
	public static PivotalTrackerUpdatePayload parse(String json) {
		return (PivotalTrackerUpdatePayload) System.JSON.deserialize(json, PivotalTrackerUpdatePayload.class);
	}
}