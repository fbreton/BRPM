require 'yaml'
require 'script_support/bsa_utilities'

bsa_config = YAML.load(SS_integration_details)

BSA_USERNAME = SS_integration_username
BSA_PASSWORD = decrypt_string_with_prefix(SS_integration_password_enc)
BSA_ROLE = bsa_config["role"]
BSA_BASE_URL = SS_integration_dns

def execute(script_params, parent_id, offset, max_records)

  if parent_id.blank?
    # root folder
	data = [{ :title => "MapFromBRPMServers", :key => "MapFromBRPMServers", :isFolder => false }]
    group = BsaUtilities.get_root_group(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, "STATIC_COMPONENT_GROUP")
    data << { :title => group["name"], :key => "#{group["groupId"]}|#{group["objectId"]}|#{group["modelType"]}", :isFolder => true, :hasChild => true, :hideCheckbox => true} if group
    return data
  else
    data = []
    groups = BsaUtilities.get_child_objects_from_parent_group(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, parent_id.split("|")[2], parent_id.split("|")[1], "STATIC_COMPONENT_GROUP")
    if groups
      groups.each do |group|
        data << { :title => group["name"], :key => "#{group["groupId"]}|#{group["objectId"]}|#{group["modelType"]}", :isFolder => true, :hasChild => true, :hideCheckbox => false}
      end
    end
    groups = BsaUtilities.get_child_objects_from_parent_group(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, parent_id.split("|")[2], parent_id.split("|")[1], "SMART_COMPONENT_GROUP")
    if groups
      groups.each do |group|
        data << { :title => group["name"], :key => "#{group["groupId"]}|#{group["objectId"]}|#{group["modelType"]}", :isFolder => true, :hasChild => true, :hideCheckbox => false}
      end
    end
    objects = BsaUtilities.get_child_objects_from_parent_group(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, parent_id.split("|")[2], parent_id.split("|")[1], "COMPONENT")
    if objects
      objects.each do |object|
        data << { :title => object["name"], :key => "#{object["name"]}|#{object["objectId"]}|#{object["dbKey"]}", :isFolder => false }
      end
    end
    return data
  end

end

def import_script_parameters
  { "render_as" => "Tree" }
end