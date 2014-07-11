###
# Builder:
#   name: Builder
#   position: A1:F1
#   type: in-external-single-select
#   external_resource: bsa_componentbuilders
#   required: yes
# Archive_Name:
#   name: Archive Name
#   position: A2:F2
#   required: yes
# Package_Folder:
#   name: Package folder
#   position: A3:F3
#   type: in-external-single-select
#   external_resource: bsa_app_package_folders
#   required: yes
# Package_Name:
#   name: Package Name
#   position: A4:F4
#   required: yes
# Target_Environment:
#   name: Target Environment
#   position: A5:B5
#   type: in-external-single-select
#   external_resource: bsa_getenvironment
#   required: yes
# Target_Blueprint:
#   name: Target Blueprint
#   position: E5:F5
#   type: in-external-single-select
#   external_resource: bsa_targetblueprint
#   required: yes
# Deploy_Options:
#   name: Deploy Options
#   position: A6:F6
#   type: in-external-multi-select
#   external_resource: bsa_deployphases
# Job_Folder:
#   name: Deploy Job Folder
#   position: A7:F7
#   type: in-external-single-select
#   external_resource: bsa_deployjob_folders
#   required: yes
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
DEFAULT_PKG_FORLDER = "/Applications/#{params["SS_application"]}"
DEFAULT_JOB_FOLDER = "/BRPM/Deploy"
DEFAULT_COMPONENT_BUILDER = "#{params["SS_application"]}-#{params["SS_component"]}-build"
ARCHIVE_FILE_NAME_PROPERTY = "FILE_NAME"

# Initialize variable
message = "" #message to display at the end of execution
jobName = "#{params["SS_application"]}-#{params["SS_component"]}-#{CURRENT_DATE}"

# Connect to BSA
session_id = BsaUtilities.bsa_soap_login(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD)
raise "Could not login to BSA Cli Tunnel Service" if session_id.nil?
BsaUtilities.bsa_soap_assume_role(BSA_BASE_URL, BSA_ROLE, session_id)

###########################################
# Check pre requisites
###########################################

# Check if needed if normalized folder path exists and create them if needed
if params["Package_Folder"] == "NormalizedPath"
  pkgGroup = BsaUtilities.bsa_soap_check_or_create_group_path(BSA_BASE_URL, session_id, DEFAULT_PKG_FORLDER, "DEPOT")
else
  pkgGroup = params["Package_Folder"].split('|')[0]
end

if params["Job_Folder"] == "NormalizedPath"
  jobGroup = BsaUtilities.bsa_soap_check_or_create_group_path(BSA_BASE_URL, session_id, DEFAULT_JOB_FOLDER, "JOBS")
else
  jobGroup = params["Job_Folder"].split('|')[0]
end

if params["Builder"]  == "NormalizedName"
  bquery = "SELECT * FROM \"SystemObject/Component\" WHERE NAME equals \"#{DEFAULT_COMPONENT_BUILDER}\""
  result = BsaUtilities.get_element_systemobject(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE,bquery)
  raise "BSA component #{DEFAULT_COMPONENT_BUILDER} not found" if result.empty?
  compDBKey = result[0]["dbKey"]
else
  compDBKey = params["Builder"].split('|')[2]
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

# setup the archive file property value of component builder
compDBKey = BsaUtilities.bsa_soap_execute_cli_command_by_param_list(BSA_BASE_URL, session_id, "Component", "setPropertyValue", [compDBKey, ARCHIVE_FILE_NAME_PROPERTY, sub_tokens(params, params["Archive_Name"])])[:return_value]

# Create package if it doesn't already exist
pkgName = sub_tokens(params,params["Package_Name"])
if params["Package_Folder"] == "NormalizedPath"
  object_url = "/group/Depot#{DEFAULT_PKG_FORLDER}/#{pkgName}"
else
  object_url = "#{params["Package_Folder"].split('|')[1]}/#{pkgName}"
end
pkgDBKey = BsaUtilities.get_propertysetinstance_from_object_url(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, object_url)["dbKey"] rescue nil
if pkgDBKey.nil?
  pkgDBKey =  BsaUtilities.bsa_create_bl_package_from_component(BSA_BASE_URL, session_id, pkgName, pkgGroup, compDBKey) rescue nil
  raise "Could not create blpackage #{pkgName}" if pkgDBKey.nil?
  message += "BlPackage #{pkgName} created.\n"
else
    message += "BlPackage #{pkgName} already exist, no need to create it\n"
end

# get target list from env regarding blueprint
targetlist = BsaUtilities.get_component_list_from_multiselect(BSA_BASE_URL,BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, envSelected, blueprint)
if targetlist.empty?
  envname = BsaUtilities.get_propertysetinstance_from_group_url(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, "/id/SystemObject/Smart Group/#{envSelected[0][1]}")["name"] rescue nil
  envname = BsaUtilities.get_propertysetinstance_from_group_url(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, "/id/SystemObject/Static Group/Static Component Group/#{envSelected[0][1]}")["name"] if envname.nil?
  message += "No target found of type #{blueprint} in environment #{envname}\n"
  message += "Nothing to deploy..."
else
  # Create deploy job
  targetsDBKeyList = targetlist.collect { |t| t[2] } 
  jobDBKey = BsaUtilities.bsa_soap_create_component_based_blpackage_deploy_job(BSA_BASE_URL, session_id, jobGroup, jobName, pkgDBKey, targetsDBKeyList, jobOpts["simulate"], jobOpts["stagedindirect"]) rescue nil
  raise "Cannot create deploy job #{jobName}" if jobDBKey.nil?
  message += "Deploy job created: #{jobName}\n"
  
  # Set properties for package deploy
  componentparams = BsaUtilities.get_component_custom_property_list(BSA_BASE_URL,BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, "/id/SystemObject/Component/#{targetlist[0][1]}")
  packageparams = BsaUtilities.bsa_soap_get_blpackage_property_list(BSA_BASE_URL, session_id, pkgDBKey)
  packageparams.each do |elt|
    if componentparams.include?(elt)
		result = BsaUtilities.bsa_soap_set_properties_for_deployjob(BSA_BASE_URL, session_id, jobGroup, jobName, elt)
		message += "Automap property #{elt}\n"
	end
    if params.has_key?(elt)	
		result = BsaUtilities.bsa_soap_set_properties_for_deployjob(BSA_BASE_URL, session_id, jobGroup, jobName, elt, isAutomapped=false, prop_value=params[elt]) 
		message += "Property #{elt} set to value #{params[elt]}\n"
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

  message += "Job #{jobName} executed #{execution_status} "
end

puts(message)


