###
# Target_Environment:
#   name: Target Environment
#   position: D1:F1
#   type: in-external-single-select
#   external_resource: bsa_getenvironment
#   required: yes
# Target_Blueprint:
#   name: Target Blueprint
#   position: A1:C1
#   type: in-external-single-select
#   external_resource: bsa_targetblueprint
#   required: yes
# Action:
#   name: Action
#   position: A2:C2
#   type: in-external-single-select
#   external_resource: bsa_getaction
#   required: yes
# Required_parameters:
#  name: Required parameter
#  position: D2:F2
#  type: in-external-single-select
#  external_resource: bsa_requiredpackageproperties
# Action_Parameters:
#   name: Action Parameters
#   position: A3:F3
# Job_Folder:
#   name: Deploy Job Folder
#   position: A4:F4
#   type: in-external-multi-select
#   external_resource: bsa_deployjob_folders
#   required: yes
# Deploy_Options:
#   name: Deploy Options
#   position: A5:F5
#   type: in-external-multi-select
#   external_resource: bsa_deployphases
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
ACTION_ROOT_FOLDER = "/BRPM/Actions"

# Initialize variable
message = "" #message to display at the end of execution

# Connect to BSA
session_id = BsaUtilities.bsa_soap_login(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD)
raise "Could not login to BSA Cli Tunnel Service" if session_id.nil?
BsaUtilities.bsa_soap_assume_role(BSA_BASE_URL, BSA_ROLE, session_id)

###########################################
# Check pre requisites
###########################################

# Check if needed if normalized folder path exists and create them if needed
if params["Job_Folder"] == "NormalizedPath"
  jobGroup = BsaUtilities.bsa_soap_check_or_create_group_path(BSA_BASE_URL, session_id, DEFAULT_JOB_FOLDER, "JOBS")
else
  jobGroup = params["Job_Folder"].split('|')[0]
end

# Get environment 
if params["Target_Environment"] == "rpm{SS_environment}"
  bquery = "SELECT * FROM \"SystemObject/Static Group/Static Component Group\" WHERE (NAME equals \"#{params["SS_environment"]}\") AND (DESCRIPTION equals \"Environment\")"
  result = BsaUtilities.get_element_systemobject(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, bquery)[0] rescue nil
  if result.nil?
    bquery = "SELECT * FROM \"SystemObject/Static Group/Smart Component Group\" WHERE (NAME equals \"#{params["SS_environment"]}\") AND (DESCRIPTION equals \"Environment\")"
    result = BsaUtilities.get_element_systemobject(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, bquery)[0] rescue nil
  end
  raise "Component group #{params["SS_environment"]} with description set to Environment cannot be found in BSA." if result.nil?
  envSelected = [[result["groupId"], result["objectId"], result["modelType"]]]
else
  envSelected = [params["Target_Environment"].split('|')]
end 

# Get Blueprint
if params["Target_Blueprint"] == "rpm{Blueprint}"
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

# get target list from env regarding blueprint
targetlist = BsaUtilities.get_component_list_from_multiselect(BSA_BASE_URL,BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, envSelected, blueprint)
if targetlist.empty?
  envname = BsaUtilities.get_propertysetinstance_from_group_url(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, "/id/SystemObject/Smart Group/#{envSelected[0][1]}")["name"] rescue nil
  envname = BsaUtilities.get_propertysetinstance_from_group_url(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, "/id/SystemObject/Static Group/Static Component Group/#{envSelected[0][1]}")["name"] if envname.nil?
  message += "No target found of type #{blueprint} in environment #{envname}\n"
  message += "Nothing to deploy..."
else
  # Create deploy jobs and run them
  targetlist.each do |target|
	session_id = BsaUtilities.bsa_soap_login(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD)
	raise "Could not login to BSA Cli Tunnel Service" if session_id.nil?
	BsaUtilities.bsa_soap_assume_role(BSA_BASE_URL, BSA_ROLE, session_id)
    # Get package dbkey
	pkgDBKey = BsaUtilities.bsa_soap_get_package_action_dbkey(BSA_BASE_URL, session_id, "#{ACTION_ROOT_FOLDER}/#{blueprint}/#{params["Action"]}", target[2])
	# create job
    jobName = "#{params["SS_application"]}-#{target[0]}-#{params["Action"]}-#{CURRENT_DATE}"
	jobDBKey = BsaUtilities.bsa_soap_create_component_based_blpackage_deploy_job(BSA_BASE_URL, session_id, jobGroup, jobName, pkgDBKey, [target[2]], jobOpts["simulate"], jobOpts["stagedindirect"]) rescue nil
	raise "Cannot create deploy job #{jobName}" if jobDBKey.nil?
	message += "--- Deploy job created: #{jobName} ---\n"
  
	# Set properties for package deploy
	componentparams = BsaUtilities.get_component_custom_property_list(BSA_BASE_URL,BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, "/id/SystemObject/Component/#{targetlist[0][1]}")
	packageparams = BsaUtilities.bsa_soap_get_blpackage_property_list(BSA_BASE_URL, session_id, pkgDBKey)
	packageparams.each do |elt|
		if componentparams.include?(elt)
			result = BsaUtilities.bsa_soap_set_properties_for_deployjob(BSA_BASE_URL, session_id, jobGroup, jobName, elt)
			message += "\tAutomap property #{elt}\n"
		end
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
		execution_status = "WITH_ERRORS"
		raise "\nJob, #{jobName} Execution failed:\n   Please check job logs for errors\n"
	end

	message += "--- Job #{jobName} executed #{execution_status} ---\n\n"
  end
end

puts(message)


