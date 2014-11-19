require 'yaml'
require 'script_support/bsa_utilities'

bsa_config = YAML.load(SS_integration_details)

BSA_USERNAME = SS_integration_username
BSA_PASSWORD = decrypt_string_with_prefix(SS_integration_password_enc)
BSA_ROLE = bsa_config["role"]
BSA_BASE_URL = SS_integration_dns

def execute(script_params, parent_id, offset, max_records)

	data = [{"Select" => 'Generic'},{"Value from component property Blueprint" => "rpm{Blueprint}"}]
	bquery = 'SELECT * FROM "SystemObject/Component Template" WHERE DESCRIPTION equals "Blueprint"'
	BsaUtilities.get_element_systemobject(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE,bquery).each do |elt|
		data << {elt["name"] => elt["name"]}
	end
    return data
end

def import_script_parameters
  { "render_as" => "List" }
end