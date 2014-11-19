###
# Target_Environment:
#   name: Environment
#   position: D1:F1
#   type: in-external-single-select
#   external_resource: bsa_getenvironment
# Target_Blueprint:
#   name: Blueprint
#   position: A1:C1
#   type: in-external-single-select
#   external_resource: bsa_targetblueprint
# Action:
#   name: Action
#   position: A2:C2
#   type: in-external-single-select
#   external_resource: bsa_getprovaction
#   required: yes
# Service_Name:
#   name: Service Name
#   position: D2:F2
# Job_Folder:
#   name: Deploy Job Folder
#   position: A3:F3
#   type: in-external-multi-select
#   external_resource: bsa_deployjob_folders
#   required: yes
# Deploy_Options:
#   name: Deploy Options
#   position: A4:F4
#   type: in-external-multi-select
#   external_resource: bsa_deployphases
# Targets:
#   name: Targets
#   position: A5:F5
#   type: in-external-multi-select
#   external_resource: bsa_getservers
#   required: yes
# Required_parameters:
#   name: Required parameter
#   position: A6:F6
#   type: in-external-single-select
#   external_resource: bsa_requiredpackageproperties_servers
# Action_Parameters:
#   name: Action Parameters
#   position: A7:F7
###

require 'json'
require 'rest-client'
require 'uri'
require 'yaml'
require 'lib/script_support/bsa_utilities'

params["direct_execute"] = true

bsa_config = YAML.load(SS_integration_details)

BSA_USERNAME = SS_integration_username
BSA_PASSWORD = decrypt_string_with_prefix(SS_integration_password_enc)
BSA_ROLE = bsa_config["role"]
BSA_BASE_URL = SS_integration_dns
CURRENT_DATE = Time.new.strftime("%Y-%m-%d_%H-%M-%S")

# Constant setup to fix values that are just arbitrary choice
DEFAULT_JOB_FOLDER = "/BRPM/Deploy"
ACTION_ROOT_FOLDER = "/BRPM/Provisioning"

# Initialize variable
message = "" #message to display at the end of execution

# Connect to BSA
session_id = BsaUtilities.bsa_soap_login(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD)
raise "Could not login to BSA Cli Tunnel Service" if session_id.nil?
BsaUtilities.bsa_soap_assume_role(BSA_BASE_URL, BSA_ROLE, session_id)

###########################################
# Check pre requisites
###########################################

# Check if environment and blueprint setup if service name is provided
raise "When you request to create a service, the name has to be provided" if  (! params["Service_Name"].blank?) && params["Target_Blueprint"].blank?
# Check if needed if normalized folder path exists and create them if needed
if params["Job_Folder"] == "NormalizedPath"
  jobGroup = BsaUtilities.bsa_soap_check_or_create_group_path(BSA_BASE_URL, session_id, DEFAULT_JOB_FOLDER, "JOBS")
else
  jobGroup = params["Job_Folder"].split('|')[0]
end

# Get environment 
if not params["Service_Name"].blank?
  if params["Target_Environment"] == "rpm{SS_environment}"
    bquery = "SELECT * FROM \"SystemObject/Static Group/Static Component Group\" WHERE (NAME equals \"#{params["SS_environment"]}\") AND (DESCRIPTION equals \"Environment\")"
    result = BsaUtilities.get_element_systemobject(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, bquery)[0] rescue nil
    if result.nil?
      bquery = "SELECT * FROM \"SystemObject/Static Group/Smart Component Group\" WHERE (NAME equals \"#{params["SS_environment"]}\") AND (DESCRIPTION equals \"Environment\")"
      result = BsaUtilities.get_element_systemobject(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, bquery)[0] rescue nil
    end
	if result.nil?
	  gpcpId = BsaUtilities.bsa_soap_execute_cli_command_by_param_list(BSA_BASE_URL,session_id,"Group","createGroupPath",[5014,"/#{params["SS_environment"]}"])[:return_value].split(';')[0].split('=')[1].strip rescue nil
	  raise "Can not create component group #{params["SS_environment"]}." if gpcpId.nil?
	  bquery = "SELECT * FROM \"SystemObject/Static Group/Static Component Group\" WHERE NAME equals \"#{params["SS_environment"]}\""
	  result = BsaUtilities.get_element_systemobject(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, bquery)[0]
	  aux = BsaUtilities.bsa_soap_execute_cli_command_by_param_list(BSA_BASE_URL,session_id,"Group","setDescription",[result["groupId"],"Environment"])
	end
    envSelected = [[result["groupId"], result["objectId"], result["modelType"]]]
  else
    envSelected = [params["Target_Environment"].split('|')]
  end
end

#Get servers list
servSelected = []
params["Targets"].split(',').each do |elt|
  aux = elt.split('|')
  if aux[2] == "servers"
    params["servers"].split(',').each do |serv|
	  servdetails = BsaUtilities.get_server_details_from_name(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE,serv)
	  raise "Server #{serv} is not registered in BSA" if servdetails.nil?
	  servSelected << [serv,servdetails["objectId"],"SERVER",servdetails["dbKey"]]
	end
  else
    servSelected << aux
  end
end
servSelected = BsaUtilities.get_server_list_from_multiselect(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD,BSA_ROLE, servSelected)
raise "The server group you selected do not contain any servers" if servSelected["Linux"].empty? && servSelected["Windows"].empty? && servSelected["Solaris"].empty? && servSelected["AIX"].empty? && servSelected["HP-UX"].empty?

# Get Blueprint
if params["Target_Blueprint"].blank?
  blueprint = "Generic"
elsif params["Target_Blueprint"] == "rpm{Blueprint}"
  blueprint = params["Blueprint"]
  if blueprint.blank?
    raise "No property Blueprint found for RPM component #{params["SS_component"]} or empty value"
  else
    bquery = "SELECT * FROM \"SystemObject/Component Template\" WHERE (NAME equals \"#{blueprint}\") AND (DESCRIPTION equals \"Blueprint\")"
    blueprint = BsaUtilities.get_element_systemobject(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, bquery)[0]["name"] rescue nil
	raise "Component Template #{blueprint} with description set to Blueprint cannot be found in BSA." if blueprint.nil?
  end
else
  blueprint = params["Target_Blueprint"]
end

# Get Job options
jobOpts = params["Deploy_Options"].split(',')
jobOpts = { "simulate" => jobOpts.include?("simulate"), "stagedindirect" => jobOpts.include?("stage")}

# Get Action_Parameters
actionparams = {}
unless params["Action_Parameters"].empty?
	params["Action_Parameters"].split('|').each do |elt|
		actionparams.merge!({ elt.split('=')[0] => sub_tokens(params,elt.split('=')[1]) })
	end
end

# Create deploy jobs and run them
servSelected.each do |osname,targets|
  unless targets.empty?
    # Get package dbkey
	pkgDBKey = BsaUtilities.get_package_action_dbkey(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD,BSA_ROLE,"#{ACTION_ROOT_FOLDER}/#{blueprint}/#{params["Action"]}",osname)
	raise "No pkg for #{osname} in #{ACTION_ROOT_FOLDER}/#{blueprint}/" if pkgDBKey.nil?
	
	# soap connection
	session_id = BsaUtilities.bsa_soap_login(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD)
	raise "Could not login to BSA Cli Tunnel Service" if session_id.nil?
	BsaUtilities.bsa_soap_assume_role(BSA_BASE_URL, BSA_ROLE, session_id)	
	
	# create job
    jobName = "#{params["SS_application"]}-#{osname}-#{params["Action"]}-#{CURRENT_DATE}"
	jobDBKey = BsaUtilities.bsa_soap_create_blpackage_deploy_job(BSA_BASE_URL, session_id, jobGroup, jobName, pkgDBKey, targets, jobOpts["simulate"], jobOpts["stagedindirect"]) rescue nil
	raise "Cannot create deploy job #{jobName}" if jobDBKey.nil?
	message += "--- Deploy job created: #{jobName} ---\n"
	
	# Set properties for package deploy
	packageparams = BsaUtilities.bsa_soap_get_blpackage_property_list(BSA_BASE_URL, session_id, pkgDBKey)
	packageparams.each do |elt|
		if params.has_key?(elt)	
			result = BsaUtilities.bsa_soap_set_properties_for_deployjob(BSA_BASE_URL, session_id, jobGroup, jobName, elt, isAutomapped=false, prop_value=params[elt]) 
			message += "\tProperty #{elt} set to value #{params[elt]}\n"
		end
		if actionparams.has_key?(elt)
			result = BsaUtilities.bsa_soap_set_properties_for_deployjob(BSA_BASE_URL, session_id, jobGroup, jobName, elt, isAutomapped=false, prop_value=actionparams[elt]) 
			message += "\tProperty #{elt} set to value #{actionparams[elt]}\n"
		end
	end
	
	# Excecute deployjob
	job_url = BsaUtilities.bsa_soap_db_key_to_rest_uri(BSA_BASE_URL, session_id, jobDBKey)
	raise "Could not fetch REST URI for job: #{jobName}" if job_url.nil?
      
	h = BsaUtilities.execute_job(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, job_url)
	raise "Could run specified job, did not get a valid response from server" if h.nil?

	execution_status = "SUCCESSFULLY"
	execution_status = "WITH_WARNINGS" if (h["had_warnings"] == "true")
	if (h["had_errors"] == "true")
		raise "\nJob, #{jobName} Execution failed:\n   Please check job logs for errors\n"
	end
	message += "--- Job #{jobName} executed #{execution_status} ---\n\n"
	
	# Create components and add them to env if needed
	unless params["Service_Name"].blank?
	  targets.each do |server|
		compname = "#{sub_tokens(params,params["Service_Name"])}-#{server}"
		templateDBKey = BsaUtilities.get_template_dbkey_from_name(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, blueprint)
		servid = BsaUtilities.get_id_from_db_key(BsaUtilities.get_server_dbkey_from_name(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, server))
		compDBKey = BsaUtilities.bsa_soap_execute_cli_command_by_param_list(BSA_BASE_URL,session_id,"Component","createComponent",[compname,templateDBKey,servid])[:return_value]
		raise "Can not create component #{compname}" if compDBKey.nil?
		message += "--- Component #{compname} created ---/n"
		# component created, now we need to set properties
		compUri = BsaUtilities.bsa_soap_get_uri_from_dbkey(BSA_BASE_URL,session_id,compDBKey)
		compProps = BsaUtilities.get_component_custom_property_list(BSA_BASE_URL,BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, compUri)
		compProps.each do |property|
		  propvalue = nil
		  propvalue = params[property] if params.has_key?(property)
		  propvalue = actionparams[property] if actionparams.has_key?(property) 
		  unless propvalue.nil?
		    compDBKey = BsaUtilities.bsa_soap_execute_cli_command_by_param_list(BSA_BASE_URL,session_id,"Component","setPropertyValue",[compDBKey,property,propvalue])[:return_value] 
			message += "Set property #{property} to #{propvalue}/n"
		  end
		end
		# add component to env if needed
		unless params["Service_Name"].blank?
		  envPath = BsaUtilities.bsa_soap_execute_cli_command_by_param_list(BSA_BASE_URL,session_id,"Group","getAQualifiedGroupName",[5014,envSelected[0][0]])[:return_value]
		  groupDBKey = BsaUtilities.bsa_soap_execute_cli_command_by_param_list(BSA_BASE_URL,session_id,"StaticComponentGroup","addComponentToComponentGroupByGroupAndDBKey",[envPath,compDBKey])[:return_value]
		  message += "Added to env #{envPath}/n"
		end
		message += "-----------/n/n"
	  end
	end
  end
end

puts(message)
