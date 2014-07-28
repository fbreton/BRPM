require 'yaml'
require 'script_support/bsa_utilities'

bsa_config = YAML.load(SS_integration_details)

BSA_USERNAME = SS_integration_username
BSA_PASSWORD = decrypt_string_with_prefix(SS_integration_password_enc)
BSA_ROLE = bsa_config["role"]
BSA_BASE_URL = SS_integration_dns

def execute(script_params, parent_id, offset, max_records)
  data = []
  if parent_id.blank?
	data = [{ :title => "MapFromBRPMServers", :key => "||servers", :isFolder => false}]
    group = BsaUtilities.get_root_group(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, "STATIC_SERVER_GROUP")
    if group
      data << { :title => group["name"], :key => "|#{group["objectId"]}|#{group["modelType"]}", :isFolder => true, :hasChild => true, :hideCheckbox => true}
    end
  else
    groups = BsaUtilities.get_child_objects_from_parent_group(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, 
                parent_id.split("|")[2], parent_id.split("|")[1], "STATIC_SERVER_GROUP")
    if groups
      groups.each do |group|
        data << { :title => group["name"], :key => "#{parent_id.split("|")[0]}/#{group["name"]}|#{group["objectId"]}|#{group["modelType"]}", :isFolder => true, :hasChild => true, :hideCheckbox => false}
      end
    end
    groups = BsaUtilities.get_child_objects_from_parent_group(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, 
                  parent_id.split("|")[2], parent_id.split("|")[1], "SMART_SERVER_GROUP")
    if groups
      groups.each do |group|
        data << { :title => group["name"], :key => "#{parent_id.split("|")[0]}/#{group["name"]}|#{group["objectId"]}|#{group["modelType"]}", :isFolder => true, :hasChild => true, :hideCheckbox => false}
      end
    end
    objects = BsaUtilities.get_child_objects_from_parent_group(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, 
                  parent_id.split("|")[2], parent_id.split("|")[1], "SERVER")
    if objects
      objects.each do |object|
        data << { :title => object["name"], :key => "#{object["name"]}|#{object["objectId"]}|SERVER|#{object["dbKey"]}", :isFolder => false }
      end
    end
  end
  data
end

def import_script_parameters
  { "render_as" => "Tree" }
end