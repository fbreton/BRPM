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
ACTION_ROOT_FOLDER = "/BRPM/Provisioning"

def execute(script_params, parent_id, offset, max_records)

  return [{ :title => "N/A", :key => "", :isFolder => false, :hideCheckbox => true, :unselectable => true }] if script_params["Action"].blank?
  if script_params["Target_Blueprint"].blank?
    blueprint = "Generic"
  elsif script_params["Target_Blueprint"]
	if script_params["Target_Blueprint"] == "rpm{Blueprint}"
		blueprint = script_params["Blueprint"]
		if blueprint.blank?
		    return [{ :title => "No property Blueprint found for RPM component #{script_params["SS_component"]} or empty value", :key => "", :isFolder => false, :hideCheckbox => true, :unselectable => true }]
		else
			bquery = "SELECT * FROM \"SystemObject/Component Template\" WHERE (NAME equals \"#{blueprint}\") AND(DESCRIPTION equals \"Blueprint\")"
			blueprint = BsaUtilities.get_element_systemobject(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, bquery)[0]["name"] rescue nil
			return [{ :title => "Component Template #{blueprint} with description set to Blueprint cannot be found in BSA.", :key => "", :isFolder => false, :hideCheckbox => true, :unselectable => true }] if blueprint.nil?
		end
	else
		blueprint = script_params["Target_Blueprint"]
	end
  else 
    return [{ :title => "A Blueprint needs to be selected", :key => "", :isFolder => false, :hideCheckbox => true, :unselectable => true }]
  end
  session_id = BsaUtilities.bsa_soap_login(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD) 
  result = BsaUtilities.bsa_soap_assume_role(BSA_BASE_URL, BSA_ROLE, session_id) 
  pkgDBKey = script_params["Package"].split('|')[2] unless script_params["Package"].nil?
  pkgDBKey = BsaUtilities.get_package_action_dbkey(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, "#{ACTION_ROOT_FOLDER}/#{blueprint}/#{script_params["Action"]}") unless script_params["Action"].nil?
  packageparams = BsaUtilities.bsa_soap_get_blpackage_property_list(BSA_BASE_URL, session_id, pkgDBKey)
  data = []
  packageparams.each do |elt|
	data << { :title => elt, :key => elt, :isFolder => false, :hideCheckbox => true, :unselectable => true } unless script_params.has_key?(elt)
  end
  return data
end

def import_script_parameters
  { "render_as" => "Tree" }
end