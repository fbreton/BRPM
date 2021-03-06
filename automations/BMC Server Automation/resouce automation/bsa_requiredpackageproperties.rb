###
# Action:
#  name: Action
###

require 'json'
require 'rest-client'
require 'uri'
require 'yaml'
require 'script_support/bsa_utilities'

bsa_config = YAML.load(SS_integration_details)

BSA_USERNAME = SS_integration_username
BSA_PASSWORD = decrypt_string_with_prefix(SS_integration_password_enc)
BSA_ROLE = bsa_config["role"]
BSA_BASE_URL = SS_integration_dns
ACTION_ROOT_FOLDER = "/BRPM/Actions"

def execute(script_params, parent_id, offset, max_records)

  return [{ :title => "N.A", :key => "1", :isFolder => false, :hideCheckbox => true, :unselectable => true }] if script_params["Package"].blank? && script_params["Action"].blank?
  if script_params["Targets"]
    targets = script_params["Targets"].split(',').collect{ |t| t.split('|')} 
  elsif script_params["Target_Environment"]
    if script_params["Target_Environment"] == "rpm{SS_environment}"
		bquery = "SELECT * FROM \"SystemObject/Static Group/Static Component Group\" WHERE (NAME equals \"#{script_params["SS_environment"]}\") AND (DESCRIPTION equals \"Environment\")"
		result = BsaUtilities.get_element_systemobject(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, bquery)[0] rescue nil
		if result.nil?
			bquery = "SELECT * FROM \"SystemObject/Static Group/Smart Component Group\" WHERE (NAME equals \"#{script_params["SS_environment"]}\") AND (DESCRIPTION equals \"Environment\")"
			result = BsaUtilities.get_element_systemobject(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, bquery)[0] rescue nil
		end
		return [{ :title => "Component group #{script_params["SS_environment"]} with description set to Environment cannot be found in BSA.", :key => "1", :isFolder => false, :hideCheckbox => true, :unselectable => true }] if result.nil?
		targets = [[result["groupId"], result["objectId"], result["modelType"]]]
	else
		targets = [script_params["Target_Environment"].split('|')]
	end 
	if script_params["Target_Blueprint"]
		if script_params["Target_Blueprint"] == "rpm{Blueprint}"
			blueprint = script_params["Blueprint"]
			if blueprint.blank?
				return [{ :title => "No property Blueprint found for RPM component #{script_params["SS_component"]} or empty value", :key => "1", :isFolder => false, :hideCheckbox => true, :unselectable => true }]
			else
				bquery = "SELECT * FROM \"SystemObject/Component Template\" WHERE (NAME equals \"#{blueprint}\")AND(DESCRIPTION equals \"Blueprint\")"
				blueprint = BsaUtilities.get_element_systemobject(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, bquery)[0]["name"] rescue nil
				return [{ :title => "No property Blueprint found for RPM component #{script_params["SS_component"]} or empty value", :key => "1", :isFolder => false, :hideCheckbox => true, :unselectable => true }] if blueprint.nil?
			end
		else
			blueprint = script_params["Target_Blueprint"]
		end
	else
	  blueprint = ""
	end
  else 
    return [{ :title => "N.A", :key => "1", :isFolder => false, :hideCheckbox => true, :unselectable => true }]
  end
  
  session_id = BsaUtilities.bsa_soap_login(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD) 
  result = BsaUtilities.bsa_soap_assume_role(BSA_BASE_URL, BSA_ROLE, session_id) 
  target = BsaUtilities.get_component_list_from_multiselect(BSA_BASE_URL,BSA_USERNAME, BSA_PASSWORD, BSA_ROLE,targets,blueprint,1)[0]
  mappedparams = BsaUtilities.get_component_custom_property_list(BSA_BASE_URL,BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, "/id/SystemObject/Component/#{target[1]}") rescue []
  pkgDBKey = script_params["Package"].split('|')[2] unless script_params["Package"].nil?
  pkgDBKey = BsaUtilities.bsa_soap_get_package_action_dbkey(BSA_BASE_URL, session_id, "#{ACTION_ROOT_FOLDER}/#{blueprint}/#{script_params["Action"]}", target[2]) unless script_params["Action"].nil?
  packageparams = BsaUtilities.bsa_soap_get_blpackage_property_list(BSA_BASE_URL, session_id, pkgDBKey)
  data = []
  packageparams.each do |elt|
	data << { :title => elt, :key => elt, :isFolder => false, :hideCheckbox => true, :unselectable => true } unless mappedparams.include?(elt) || script_params.has_key?(elt)
  end
  return data
end

def import_script_parameters
  { "render_as" => "Tree" }
end
