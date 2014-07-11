###
#
# target_mode:
#   name: Target Mode
#   type: in-list-single
#   list_pairs: 0,Select|1,JobDefaultTargets|2,AlternateBAAComponents|3,MappedBAAComponents|4,AlternateBAAServers|5,MapFromBRPMServers
###

require 'yaml'
require 'script_support/bsa_utilities'

bsa_config = YAML.load(SS_integration_details)

BSA_USERNAME = SS_integration_username
BSA_PASSWORD = decrypt_string_with_prefix(SS_integration_password_enc)
BSA_ROLE = bsa_config["role"]
BSA_BASE_URL = SS_integration_dns

def get_static_group_model_type(target_mode)
  case target_mode
  when "4", "AlternateBAAServers"
    return "STATIC_SERVER_GROUP"
  when "2", "AlternateBAAComponents"
    return "STATIC_COMPONENT_GROUP"
  end
end

def get_smart_group_model_type(target_mode)
  case target_mode
  when "4", "AlternateBAAServers"
    return "SMART_SERVER_GROUP"
  when "2", "AlternateBAAComponents"
    return "SMART_COMPONENT_GROUP"
  end
end

def get_leaf_object_model_type(target_mode)
  case target_mode
  when "4", "AlternateBAAServers"
    return "SERVER"
  when "2", "AlternateBAAComponents"
    return "COMPONENT"
  end
end

def execute(script_params, parent_id, offset, max_records)

  if (script_params["target_mode"] == "1") || (script_params["target_mode"] == "JobDefaultTargets") || 
        (script_params["target_mode"] == "5") || (script_params["target_mode"] == "MapFromBRPMServers")
    return []
  end

  project_server_id = script_params["SS_project_server_id"]
  if project_server_id.blank?
    raise "Project Server needs to be set for this automation to work"
  end

  mapping = script_params["SS_component_mapping_#{project_server_id}"]
  component_template_id = nil
  if mapping && (mapping.is_a? Hash)
    component_template_id = mapping["component_template"]
  end

  data = []
  if parent_id.blank?
    write_to("target mode: #{script_params["target_mode"]}")
    case script_params["target_mode"]
    when "4", "AlternateBAAServers"
      group = BsaUtilities.get_root_group(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, "STATIC_SERVER_GROUP")
      if group
        data << { :title => group["name"], :key => "|#{group["objectId"]}|#{group["modelType"]}", :isFolder => true, :hasChild => true, :hideCheckbox => true}
      end
    when "2", "AlternateBAAComponents"
      group = BsaUtilities.get_root_group(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, "STATIC_COMPONENT_GROUP")
      if group
        data << { :title => group["name"], :key => "|#{group["objectId"]}|#{group["modelType"]}", :isFolder => true, :hasChild => true, :hideCheckbox => true}
      end
    when "3", "MappedBAAComponents"
      unless component_template_id.blank?
        data << { :title => script_params["SS_component"], :key => component_template_id, :isFolder => true, :hasChild => true, :hideCheckbox => true}
      end
    end
  else
    case script_params["target_mode"]
    when "4", "AlternateBAAServers", "2", "AlternateBAAComponents"
      groups = BsaUtilities.get_child_objects_from_parent_group(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, 
                    parent_id.split("|")[2], parent_id.split("|")[1], get_static_group_model_type(script_params["target_mode"]))
      if groups
        groups.each do |group|
          data << { :title => group["name"], :key => "#{parent_id.split("|")[0]}/#{group["name"]}|#{group["objectId"]}|#{group["modelType"]}", :isFolder => true, :hasChild => true, :hideCheckbox => false}
        end
      end
      groups = BsaUtilities.get_child_objects_from_parent_group(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, 
                    parent_id.split("|")[2], parent_id.split("|")[1], get_smart_group_model_type(script_params["target_mode"]))
      if groups
        groups.each do |group|
          data << { :title => group["name"], :key => "#{parent_id.split("|")[0]}/#{group["name"]}|#{group["objectId"]}|#{group["modelType"]}", :isFolder => true, :hasChild => true, :hideCheckbox => false}
        end
      end
      objects = BsaUtilities.get_child_objects_from_parent_group(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, 
                    parent_id.split("|")[2], parent_id.split("|")[1], get_leaf_object_model_type(script_params["target_mode"]))
      if objects
		object_type = get_leaf_object_model_type(script_params["target_mode"])
        objects.each do |object|
          data << { :title => object["name"], :key => "#{object["name"]}|#{object["objectId"]}|#{object_type}|#{object["dbKey"]}", :isFolder => false }
        end
      end
    when "3", "MappedBAAComponents"
      unless component_template_id.blank?
        objects = BsaUtilities.get_components_for_component_template(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, component_template_id.split('|')[1])
        if objects
          objects.each do |object|
            data << { :title => object["name"], :key => "#{object["name"]}|#{object["objectId"]}|COMPONENT|#{object["dbKey"]}", :isFolder => false }
          end
        end
      end
    end
  end
  data
end

def import_script_parameters
  { "render_as" => "Tree" }
end