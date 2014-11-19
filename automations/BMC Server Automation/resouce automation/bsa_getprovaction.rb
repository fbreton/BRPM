###
# Target_Blueprint:
#   name: Target Blueprint
###

require 'yaml'
require 'script_support/bsa_utilities'

bsa_config = YAML.load(SS_integration_details)

BSA_USERNAME = SS_integration_username
BSA_PASSWORD = decrypt_string_with_prefix(SS_integration_password_enc)
BSA_ROLE = bsa_config["role"]
BSA_BASE_URL = SS_integration_dns

ROOT_FOLDER = "/BRPM/Provisioning"

def execute(script_params, parent_id, offset, max_records)
	blueprint = script_params["Target_Blueprint"]
	if blueprint == "rpm{Blueprint}"
	  actionfolder = BsaUtilities.get_root_group(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, "DEPOT_GROUP","#{ROOT_FOLDER}/#{script_params["Blueprint"]}")
	else
	  actionfolder = BsaUtilities.get_root_group(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, "DEPOT_GROUP","#{ROOT_FOLDER}/#{blueprint}")
	end
	data = []
	actions = BsaUtilities.get_child_objects_from_parent_group(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, actionfolder["modelType"], actionfolder["objectId"], "BLPACKAGE") 
	actions.each do |elt|
	    actionname = elt["name"].sub(/-[^-]*$/,'')
		data << {actionname => actionname} unless data.include?({actionname => actionname})
	end
    return data.sort_by { |k| k.keys[0]}
end

def import_script_parameters
  { "render_as" => "List" }
end