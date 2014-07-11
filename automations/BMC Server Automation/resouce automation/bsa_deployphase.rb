def execute(script_params, parent_id, offset, max_records)
  return [
			{ :title => "Simulate before deploy", :key => "simulate", :isFolder => false },
			{ :title => "Stage indirect (using repeaters)", :key => "stage", :isFolder => false }
		]
end

def import_script_parameters
  { "render_as" => "Tree" }
end