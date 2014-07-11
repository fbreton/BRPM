require 'script_support/bsa_utilities'
require 'yaml'

bsa_config = YAML.load(SS_integration_details)

BSA_USERNAME = SS_integration_username
BSA_PASSWORD = decrypt_string_with_prefix(SS_integration_password_enc)
BSA_ROLE = bsa_config["role"]
BSA_BASE_URL = SS_integration_dns

def execute(script_params, parent_id, offset, max_records)
  if parent_id.blank?
    # root folder
	data = [{ :title => "/Applications/rpm{application}", :key => "NormalizedPath", :isFolder => false }]
    group = BsaUtilities.get_root_group(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, "DEPOT_GROUP")
    data << { :title => group["name"], :key => "#{group["groupId"]}|#{group["objectId"]}|#{group["modelType"]}", :isFolder => true, :hasChild => true, :hideCheckbox => true} if group
    return data
  else
    groups = BsaUtilities.get_child_objects_from_parent_group(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, "DEPOT_GROUP", parent_id.split("|")[1], "DEPOT_GROUP")
    return [] if groups.nil?
    data = []
    groups.each do |group|
      data << { :title => group["name"], :key => "#{group["groupId"]}|#{group["objectId"]}|#{group["modelType"]}", :isFolder => true, :hasChild => true}
    end
    data
  end
end

def import_script_parameters
  { "render_as" => "Tree" }
end