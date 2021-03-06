###
# Hypervisor:
#   name: hypervisor type
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

def execute(script_params, parent_id, offset, max_records)
  virtualmgr = script_params["Hypervisor"]
  data = []
  if parent_id.blank?
    # root folder
	vclist = BsaUtilities.list_virtual_mgr(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE)
	case virtualmgr
		when "VMware"
			vclist.each do |vc|
				data << { :title => vc["name"], :key => "mgr|#{vc["id"]}|#{vc["uri"]}", :isFolder => true, :hasChild => true, :hideCheckbox => true } if vc["mgr"] == "VMware Virtual Center"
			end
	end
  else
	parent = parent_id.split("|")
	case virtualmgr
		when "VMware"
			if parent[0] == "mgr"
				data << { :title => "Clusters", :key => "vmmgr|#{parent[2]}/Assets/BMC_VMware_VirtualInfrastructureManager/Clusters/|#{parent[1]} VMwareCluster", :isFolder => true, :hasChild => true, :hideCheckbox => true }
				data << { :title => "Hosts", :key => "vmmgr|#{parent[2]}/Assets/BMC_VMware_VirtualInfrastructureManager/Hosts/|#{parent[1]} VMwareESXServer", :isFolder => true, :hasChild => true, :hideCheckbox => true }
			end
			if parent[0] == "vmmgr"
				vmmgrlist = BsaUtilities.get_assets_from_uri(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE,parent[1])
				vmmgrlist.each do |vmmgr|
					data << { :title => vmmgr["name"], :key => "hostcl|#{vmmgr["name"]}|#{parent[1]}#{vmmgr["name"]}/|#{parent[2]}", :isFolder => true, :hasChild => true, :hideCheckbox => true }
				end
			end
			if parent[0] == "hostcl"
				assetlist = BsaUtilities.get_assets_from_uri(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, parent[2])
				data << { :title => "MapFromBRPMServers", :key => "MapFromBRPMServers|#{parent[2]}|#{parent[3]}", :isFolder => false}
				unless assetlist.empty?
					assetlist.each do |vm|
						if vm["type"] == "BMC_VMware_VirtualMachine"
							vmid = ""
							vm["AssetAttributeValues"]["Elements"].each do |elt|
								if elt["name"] == "Internal Attribute 1"
									vmid = elt["value"]
								end
							end
							data << { :title => "#{vm["name"]}", :key => "#{vm["name"]}|#{parent[2]}|#{parent[3]} #{vmid}", :isFolder => false}
						end
					end
				end
			end
	end
  end
  return data
end

def import_script_parameters
  { "render_as" => "Tree" }
end