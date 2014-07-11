###
# Hypervisor:
#   name: hypervisor type
#   type: in-list-single
#   list_pairs: 1,Select|2,VMware|7,Solaris|10,XenServer|12,RHEV|14,HyperV
#   position: A1:B1
# Action:
#   name: action
#   type: in-list-single
#   list_pairs: 1,stop|2,start|3,delete
#   position: E1:F1
# VMs:
#   name: VM lisy
#   type: in-external-multi-select
#   external_resource: bsa_list_vm
#   position: A2:F2
###

require 'json'
require 'rest-client'
require 'uri'
require 'savon'
require 'base64'
require 'yaml'
require 'lib/script_support/bsa_utilities'

params["direct_execute"] = true

bsa_config = YAML.load(SS_integration_details)

BSA_USERNAME = SS_integration_username
BSA_PASSWORD = decrypt_string_with_prefix(SS_integration_password_enc)
BSA_ROLE = bsa_config["role"]
BSA_BASE_URL = SS_integration_dns

def get_list_vmid(vmselected,servers)
	listvmid = []
	vmselected.split(",").each do |elt|
		subelt = elt.split("|")
		if subelt[0] == "MapFromBRPMServers"
			vms = servers.split(",").collect { |x| x.strip } rescue []
			vms.each do |vm|
				vmid = BsaUtilities.get_value_from_uri(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE,"#{subelt[1]}#{vm}/AssetAttributeValues/Internal Attribute 1")
				vmid = ["#{subelt[2]} #{vmid}", "#{subelt[1]}#{vm}", vm]
				listvmid << vmid unless listvmid.include?(vmid)
			end
		else
		    vmid = [subelt[2], "#{subelt[1]}#{subelt[0]}", subelt[0]]
			listvmid << vmid unless listvmid.include?(vmid)
		end
	end
	return listvmid
end

session_id = BsaUtilities.bsa_soap_login(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD)
raise "Could not login to BAA Cli Tunnel Service" if session_id.nil?
BsaUtilities.bsa_soap_assume_role(BSA_BASE_URL, BSA_ROLE, session_id)

listvm = get_list_vmid(params["VMs"],params["servers"])

listvm.each do |vmid|
  vmstatus = BsaUtilities.get_value_from_uri(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE,"#{vmid[1]}/AssetAttributeValues/Power Status")
  case params["Action"]
	when "delete"
		BsaUtilities.bsa_soap_execute_cli_command_by_param_list(BSA_BASE_URL, session_id, "Virtualization", "changeVirtualGuestPowerStatus", [vmid[0], "stop"]) if vmstatus == "Started"
		BsaUtilities.bsa_soap_execute_cli_command_by_param_list(BSA_BASE_URL, session_id, "Virtualization", "deleteVirtualGuest", [vmid[0]])
	when "start"
		BsaUtilities.bsa_soap_execute_cli_command_by_param_list(BSA_BASE_URL, session_id, "Virtualization", "changeVirtualGuestPowerStatus", [vmid[0], "start"]) if vmstatus == "Stopped"
	when "stop"
		BsaUtilities.bsa_soap_execute_cli_command_by_param_list(BSA_BASE_URL, session_id, "Virtualization", "changeVirtualGuestPowerStatus", [vmid[0], "stop"]) if vmstatus == "Started"
  end
end


