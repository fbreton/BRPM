require 'json'
require 'rest-client'
require 'uri'
require 'savon'
require 'base64'

module BsaUtilities
  class << self
  
    def get_type_url(execute_against)
      case execute_against
      when "servers"
        return "/type/PropertySetClasses/SystemObject/Server"
      when "components"
        return "/type/PropertySetClasses/SystemObject/Component"
      when "staticServerGroups", "staticComponentGroups"
        return "/type/PropertySetClasses/SystemObject/Static Group"
      when "smartServerGroups", "smartComponentGroups"
        return "/type/PropertySetClasses/SystemObject/Smart Group"
      end
    end

    def get_execute_against_operation(execute_against)
      case execute_against
      when "servers"
        return "executeAgainstServers"
      when "components"
        return "executeAgainstComponents"
      when "staticServerGroups"
        return "executeAgainstStaticServerGroups"
      when "staticComponentGroups"
        return "executeAgainstStaticComponentGroups"
      when "smartServerGroups"
        return "executeAgainstSmartServerGroups"
      when "smartComponentGroups"
        return "executeAgainstSmartComponentGroups"
      end
    end

    def execute_job_internal(bsa_base_url, bsa_username, bsa_password, bsa_role, job_url, operation, arguments_hash)
      url = "#{bsa_base_url}#{job_url}/Operations/#{operation}"
      url += "?username=#{bsa_username}&password=#{bsa_password}&role=#{bsa_role}"

      response = RestClient.post URI.escape(url), arguments_hash.to_json, :content_type => :json, :accept => :json
      response = JSON.parse(response)
      if response.has_key? "ErrorResponse"
        raise "Error while posting to URL #{url}: #{response["ErrorResponse"]["Error"]}"
      end
 
      query_url = ""
      if response && response["OperationResultResponse"] && 
        response["OperationResultResponse"]["OperationResult"] && response["OperationResultResponse"]["OperationResult"]["value"]
        query_url = response["OperationResultResponse"]["OperationResult"]["value"]

        delay = 0
        begin
          sleep(delay)
          url = "#{bsa_base_url}#{query_url}?username=#{bsa_username}&password=#{bsa_password}&role=#{bsa_role}"
          response = RestClient.get URI.escape(url), :accept => :json
          response = JSON.parse(response)

          if response.has_key? "ErrorResponse"
            raise "Error while querying URL #{url}: #{response["ErrorResponse"]["Error"]}"
          end

          delay = 10
        end while (response.empty? || response["StatusResponse"].empty? || (response["StatusResponse"]["Status"]["status"] == "RUNNING"))

        h = {}
        h["status"] = response["StatusResponse"]["Status"]["status"] 
        h["had_errors"] = response["StatusResponse"]["Status"]["hadErrors"]
        h["had_warnings"] = response["StatusResponse"]["Status"]["hadWarnings"]
        h["is_aborted"] = response["StatusResponse"]["Status"]["isAbort"]
        h["job_run_url"] = response["StatusResponse"]["Status"]["targetURI"]
        return h
      end
      return nil
    end
	
    def execute_job_against_internal(bsa_base_url, bsa_username, bsa_password, bsa_role, job_url, targets, execute_against)
      h = {}
      h["OperationArguments"] = []
      h["OperationArguments"].push({})
      h["OperationArguments"][0]["name"] = execute_against
      h["OperationArguments"][0]["type"] = get_type_url(execute_against)
      h["OperationArguments"][0]["uris"] = []
        
      targets.each do |t|
        h["OperationArguments"][0]["uris"].push(t)
      end

      operation = get_execute_against_operation(execute_against)
      return execute_job_internal(bsa_base_url, bsa_username, bsa_password, bsa_role, job_url, operation, h)
    end
    
    def execute_job_against_servers(bsa_base_url, bsa_username, bsa_password, bsa_role, job_url, targets)
      return execute_job_against_internal(bsa_base_url, bsa_username, bsa_password, bsa_role, job_url, targets, "servers")
    end

    def execute_job_against_static_server_groups(bsa_base_url, bsa_username, bsa_password, bsa_role, job_url, targets)
      return execute_job_against_internal(bsa_base_url, bsa_username, bsa_password, bsa_role, job_url, targets, "staticServerGroups")
    end

    def execute_job_against_smart_server_groups(bsa_base_url, bsa_username, bsa_password, bsa_role, job_url, targets)
      return execute_job_against_internal(bsa_base_url, bsa_username, bsa_password, bsa_role, job_url, targets, "smartServerGroups")
    end

    def execute_job_against_components(bsa_base_url, bsa_username, bsa_password, bsa_role, job_url, targets)
      return execute_job_against_internal(bsa_base_url, bsa_username, bsa_password, bsa_role, job_url, targets, "components")
    end

    def execute_job_against_static_component_groups(bsa_base_url, bsa_username, bsa_password, bsa_role, job_url, targets)
      return execute_job_against_internal(bsa_base_url, bsa_username, bsa_password, bsa_role, job_url, targets, "staticComponentGroups")
    end

    def execute_job_against_smart_component_groups(bsa_base_url, bsa_username, bsa_password, bsa_role, job_url, targets)
      return execute_job_against_internal(bsa_base_url, bsa_username, bsa_password, bsa_role, job_url, targets, "smartComponentGroups")
    end


    def execute_job(bsa_base_url, bsa_username, bsa_password, bsa_role, job_url)
      return execute_job_internal(bsa_base_url, bsa_username, bsa_password, bsa_role, job_url, "execute", {})
    end

    def get_id_from_db_key(db_key)
      last_component = db_key.split(":").last
      if last_component
        return last_component.split("-")[0].to_i
      end
      return nil
    end

    def get_job_run_db_key(bsa_base_url, bsa_username, bsa_password, bsa_role, job_run_url)
      url = "#{bsa_base_url}#{job_run_url}?username=#{bsa_username}&password=#{bsa_password}&role=#{bsa_role}"
      response = RestClient.get URI.escape(url), :accept => :json

      response = JSON.parse(response)
      if response.has_key? "ErrorResponse"
        raise "Error while posting to URL #{url}: #{response["ErrorResponse"]["Error"]}"
      end

      if response["PropertySetInstanceResponse"] && response["PropertySetInstanceResponse"]["PropertySetInstance"]
        return response["PropertySetInstanceResponse"]["PropertySetInstance"]["dbKey"]
      end

      return nil
    end

    def get_job_run_id(bsa_base_url, bsa_username, bsa_password, bsa_role, job_run_url)
      db_key = get_job_run_db_key(bsa_base_url, bsa_username, bsa_password, bsa_role, job_run_url)
      return get_id_from_db_key(db_key) unless db_key.nil?
      return nil
    end

	def get_element_systemobject(bsa_base_url, bsa_username, bsa_password, bsa_role, bquery)
	# Sample of bquery content: SELECT * FROM "SystemObject/Component Template" WHERE DESCRIPTION equals "Blueprint"
	# To know more about querying on condition: https://docs.bmc.com/docs/display/public/bsa85/Querying+on+a+condition
	  url = "#{bsa_base_url}/query?username=#{bsa_username}&password=#{bsa_password}&role=#{bsa_role}"
	  url += "&BQUERY=#{bquery}"
	  response = RestClient.get URI.escape(url), :accept => :json
      response = JSON.parse(response)
	  
      if response.has_key? "ErrorResponse"
        raise "Error while querying URL #{url}: #{response["ErrorResponse"]["Error"]}"
      end
	  
	  if response["PropertySetClassChildrenResponse"] && response["PropertySetClassChildrenResponse"]["PropertySetClassChildren"]
	    if response["PropertySetClassChildrenResponse"]["PropertySetClassChildren"]["PropertySetInstances"]
			unless response["PropertySetClassChildrenResponse"]["PropertySetClassChildren"]["PropertySetInstances"]["Elements"].empty?
				return response["PropertySetClassChildrenResponse"]["PropertySetClassChildren"]["PropertySetInstances"]["Elements"]
			end
		end
		if response["PropertySetClassChildrenResponse"]["PropertySetClassChildren"]["Groups"]
		  unless response["PropertySetClassChildrenResponse"]["PropertySetClassChildren"]["Groups"]["Elements"].empty?
			return response["PropertySetClassChildrenResponse"]["PropertySetClassChildren"]["Groups"]["Elements"]
		  end
		end
		if response["PropertySetClassChildrenResponse"]["PropertySetClassChildren"]["PropertySetClasses"]
		  unless response["PropertySetClassChildrenResponse"]["PropertySetClassChildren"]["PropertySetClasses"]["Elements"].empty?
			return response["PropertySetClassChildrenResponse"]["PropertySetClassChildren"]["PropertySetClasses"]["Elements"]
		  end
		end
      end
      return []
	end
	
    def get_object_property_value(bsa_base_url, bsa_username, bsa_password, bsa_role, object_url, property, bquery = "")
      url = "#{bsa_base_url}#{object_url}/PropertyValues/#{property}/?username=#{bsa_username}&password=#{bsa_password}&role=#{bsa_role}"
      url += bquery
      response = RestClient.get URI.escape(url), :accept => :json
      response = JSON.parse(response)
    
      if response.has_key? "ErrorResponse"
        raise "Error while querying URL #{url}: #{response["ErrorResponse"]["Error"]}"
      end

      if response["PropertyValueChildrenResponse"] && response["PropertyValueChildrenResponse"]["PropertyValueChildren"] &&
        response["PropertyValueChildrenResponse"]["PropertyValueChildren"]["PropertyValueElements"]
        return response["PropertyValueChildrenResponse"]["PropertyValueChildren"]["PropertyValueElements"]["Elements"]
      end
      nil
    end
	
	def get_object_systemproperty_list(bsa_base_url, bsa_username, bsa_password, bsa_role,class_url)
	  url = "#{bsa_base_url}#{class_url}?username=#{bsa_username}&password=#{bsa_password}&role=#{bsa_role}"
	  response = RestClient.get URI.escape(url), :accept => :json
      response = JSON.parse(response)
	  
	  if response.has_key? "ErrorResponse"
        raise "Error while querying URL #{url}: #{response["ErrorResponse"]["Error"]}"
      end
	  if response["PropertySetClassResponse"] && response["PropertySetClassResponse"]["PropertySetClass"] && response["PropertySetClassResponse"]["PropertySetClass"]["Properties"]
	    data = []
		response["PropertySetClassResponse"]["PropertySetClass"]["Properties"]["Elements"].each do |elt|
		  data << elt["name"]
		end
		return data
	  end
	end

	def get_component_custom_property_list(bsa_base_url, bsa_username, bsa_password, bsa_role, component_uri)
	  system_prop_list = get_object_systemproperty_list(bsa_base_url, bsa_username, bsa_password, bsa_role,"/type/PropertySetClasses/SystemObject/Component")
	  url = "#{bsa_base_url}#{component_uri}?username=#{bsa_username}&password=#{bsa_password}&role=#{bsa_role}"
	  response = RestClient.get URI.escape(url), :accept => :json
      response = JSON.parse(response)
    
      if response.has_key? "ErrorResponse"
        raise "Error while querying URL #{url}: #{response["ErrorResponse"]["Error"]}"
      end
	  
	  if response["PropertySetInstanceResponse"] && response["PropertySetInstanceResponse"]["PropertySetInstance"] && response["PropertySetInstanceResponse"]["PropertySetInstance"]["PropertyValues"]
	    data = []
		response["PropertySetInstanceResponse"]["PropertySetInstance"]["PropertyValues"]["Elements"].each do |elt|
		  data << elt["name"] unless system_prop_list.include?(elt["name"])
		end
		return data
	  end
	  nil
	end
	
    def get_job_result_url(bsa_base_url, bsa_username, bsa_password, bsa_role, job_run_url)
      elements = get_object_property_value(bsa_base_url, bsa_username, bsa_password, bsa_role, job_run_url, "JOB_RESULTS*")
      element = elements[0] if elements
      results_psi = element["PropertySetInstance"] if element
      return results_psi["uri"] if results_psi
      nil
    end

    def get_per_target_results_internal(bsa_base_url, bsa_username, bsa_password, bsa_role, job_result_url, property, clazz)
      bquery = "&bquery=select name, had_errors, had_warnings, requires_reboot, exit_code* from \"SystemObject/#{clazz}\""

      h = {}
      elements = get_object_property_value(bsa_base_url, bsa_username, bsa_password, bsa_role, job_result_url, property, bquery)
      if elements
        elements.each do |jrd|
          if jrd["PropertySetInstance"]
            target = jrd["PropertySetInstance"]["name"]
            properties = {}
            if jrd["PropertySetInstance"]["PropertyValues"]
              values = jrd["PropertySetInstance"]["PropertyValues"]["Elements"]
              if values
                values.each do |val|
                  properties[val["name"]] = val["value"]
                end
              end
            end
            h[target] = properties
          end
        end
      end
      return h
    end

    def get_per_target_server_results(bsa_base_url, bsa_username, bsa_password, bsa_role, job_result_url)
      return get_per_target_results_internal(bsa_base_url, bsa_username, bsa_password, bsa_role, job_result_url, "JOB_RESULT_DEVICES*", "Job Result Device")
    end

    def get_per_target_component_results(bsa_base_url, bsa_username, bsa_password, bsa_role, job_result_url)
      return get_per_target_results_internal(bsa_base_url, bsa_username, bsa_password, bsa_role, job_result_url, "JOB_RESULT_COMPONENTS*", "Job Result Component")
    end

    def get_per_target_results(bsa_base_url, bsa_username, bsa_password, bsa_role, job_result_url)
      h = {}
      h["Server"] = get_per_target_server_results(bsa_base_url, bsa_username, bsa_password, bsa_role, job_result_url)
      h["Component"] = get_per_target_component_results(bsa_base_url, bsa_username, bsa_password, bsa_role, job_result_url)
      h
    end

    ###################################################################################
    #
    # Gets a list of components for specified component template
    #
    ###################################################################################
    def get_components_for_component_template(bsa_base_url, bsa_username, bsa_password, bsa_role, component_template_id)
      component_template_url = "/id/#{get_model_type_to_psc_name("TEMPLATE")}/#{component_template_id}"
      return get_object_property_value(bsa_base_url, bsa_username, bsa_password, bsa_role, component_template_url, "COMPONENTS*").collect {|item| item["PropertySetInstance"]}
    end

    def get_model_type_to_psc_name(model_type)
      case model_type
	  when "VIRTUAL_GUEST_PACKAGE"
		return "SystemObject/Depot Object/Virtual Guest Package"
      when "JOB_GROUP"
        return "SystemObject/Static Group/Job Group"
      when "DEPOT_GROUP"
        return "SystemObject/Static Group/Abstract Depot Group/Depot Group"
      when "STATIC_SERVER_GROUP"
        return "SystemObject/Static Group/Static Server Group"
      when "STATIC_COMPONENT_GROUP"
        return "SystemObject/Static Group/Static Component Group"
      when "TEMPLATE_GROUP"
        return "SystemObject/Static Group/Template Group"
      when "SMART_JOB_GROUP", "SMART_SERVER_GROUP", "SMART_DEVICE_GROUP", "SMART_COMPONENT_GROUP", "SMART_DEPOT_GROUP", "SMART_TEMPLATE_GROUP"
        return "SystemObject/Smart Group"
      when "SERVER"
        return "SystemObject/Server"
      when "COMPONENT"
        return "SystemObject/Component"
	  when "ALL_DEPOT_OBJECT"
	    return "SystemObject/Depot Object"
      when "BLPACKAGE"
        return "SystemObject/Depot Object/BLPackage"
      when "NSHSCRIPT"
        return "SystemObject/Depot Object/NSH Script"
      when "AIX_PATCH_INSTALLABLE"
        return "SystemObject/Depot Object/Software/AIX Patch"
      when "AIX_PACKAGE_INSTALLABLE"
        return "SystemObject/Depot Object/Software/AIX Package"
      when "HP_PRODUCT_INSTALLABLE"
        return "SystemObject/Depot Object/Software/HP-UX Product"
      when "HP_BUNDLE_INSTALLABLE"
        return "SystemObject/Depot Object/Software/HP-UX Bundle"
      when "HP_PATCH_INSTALLABLE"
        return "SystemObject/Depot Object/Software/HP-UX Patch"
      when "RPM_INSTALLABLE"
        return "SystemObject/Depot Object/Software/RPM"
      when "SOLARIS_PATCH_INSTALLABLE"
        return "SystemObject/Depot Object/Software/Solaris Patch"
      when "SOLARIS_PACKAGE_INSTALLABLE"
        return "SystemObject/Depot Object/Software/Solaris Package"
      when "HOTFIX_WINDOWS_INSTALLABLE"
        return "SystemObject/Depot Object/Software/Win Depot Software/Hotfix"
      when "SERVICEPACK_WINDOWS_INSTALLABLE"
        return "SystemObject/Depot Object/Software/Win Depot Software/OS Service Pack"
      when "MSI_WINDOWS_INSTALLABLE"
        return "SystemObject/Depot Object/Software/Win Depot Software/MSI Package"
      when "INSTALLSHIELD_WINDOWS_INSTALLABLE"
        return "SystemObject/Depot Object/Software/Win Depot Software/InstallShield Package"
      when "FILE_DEPLOY_JOB"
        return "SystemObject/Job/File Deploy Job"
      when "DEPLOY_JOB"
        return "SystemObject/Job/Deploy Job"
      when "NSH_SCRIPT_JOB"
        return "SystemObject/Job/NSH Script Job"
      when "SNAPSHOT_JOB"
        return "SystemObject/Job/Snapshot Job"
      when "COMPLIANCE_JOB"
        return "SystemObject/Job/Compliance Job"
      when "AUDIT_JOB"
        return "SystemObject/Job/Audit Job"
      when "TEMPLATE"
        return "SystemObject/Component Template"
      end
    end

    def get_model_type_to_model_type_id(model_type)
      case model_type
      when "JOB_GROUP"
        return 5005
      when "SMART_JOB_GROUP"
        return 5006
      when "STATIC_SERVER_GROUP"
        return 5003
      when "SMART_SERVER_GROUP"
        return 5007
      when "DEPOT_GROUP"
        return 5001
      when "SMART_DEPOT_GROUP"
        return 5012
      when "TEMPLATE_GROUP"
        return 5008
      when "SMART_TEMPLATE_GROUP"
        return 5016
      when "STATIC_COMPONENT_GROUP"
        return 5014
      when "SMART_COMPONENT_GROUP"
        return 5015
      end
    end

    def is_a_group(model_type)
      case model_type
      when "JOB_GROUP", "DEPOT_GROUP", "STATIC_COMPONENT_GROUP", "STATIC_SERVER_GROUP", "TEMPLATE_GROUP", "DEVICE_GROUP",
            "SMART_SERVER_GROUP", "SMART_DEVICE_GROUP", "SMART_JOB_GROUP", "SMART_COMPONENT_GROUP", "SMART_DEPOT_GROUP"
        return true
      end
      return false
    end

    
    def get_child_objects_from_parent_group(bsa_base_url, bsa_username, bsa_password, bsa_role, parent_object_type, parent_id, child_object_type)
      url = "#{bsa_base_url}/id/#{get_model_type_to_psc_name(parent_object_type)}/#{parent_id}/"
      url += "?username=#{bsa_username}&password=#{bsa_password}&role=#{bsa_role}"
      url += "&bquery=select name from \"#{get_model_type_to_psc_name(child_object_type)}\""
      response = RestClient.get URI.escape(url), :accept => :json 
      parsed_response = JSON.parse(response)

      if parsed_response.has_key? "ErrorResponse"
        raise "Error while query URL #{url}: #{parsed_response["ErrorResponse"]["Error"]}"
      end
  
      if is_a_group(child_object_type)
        objects = parsed_response["GroupChildrenResponse"]["GroupChildren"]["Groups"]
      else
        objects = parsed_response["GroupChildrenResponse"]["GroupChildren"]["PropertySetInstances"]
      end
      return objects["Elements"] if objects
      nil
    end

	def get_server_details_from_name(bsa_base_url, bsa_username, bsa_password, bsa_role,server)
      url = "#{bsa_base_url}/query"
      url += "?username=#{bsa_username}&password=#{bsa_password}&role=#{bsa_role}"
      url += "&BQUERY=SELECT NAME FROM \"SystemObject/Server\" WHERE NAME equals \"#{server}\""

      response = RestClient.get URI.escape(url), :accept => :json 
      parsed_response = JSON.parse(response)

      if parsed_response.has_key? "ErrorResponse"
        raise "Error: while query URL #{url}: #{parsed_response["ErrorResponse"]["Error"]}"
      end

	  return parsed_response["PropertySetClassChildrenResponse"]["PropertySetClassChildren"]["PropertySetInstances"]["Elements"][0] rescue nil

	end
	
	def get_package_action_dbkey(bsa_base_url, bsa_username, bsa_password, bsa_role,actionpath,osname="")
	  urlos = "#{bsa_base_url}/group/Depot#{actionpath}-#{osname}?username=#{bsa_username}&password=#{bsa_password}&role=#{bsa_role}"
	  urlgen = "#{bsa_base_url}/group/Depot#{actionpath}-Unix?username=#{bsa_username}&password=#{bsa_password}&role=#{bsa_role}"
	  group = File.dirname(actionpath)
	  pkg = File.basename(actionpath)
	  urlno = "#{bsa_base_url}/group/Depot#{group}/?username=#{bsa_username}&password=#{bsa_password}&role=#{bsa_role}"
	  urlno += "&bquery=select name from \"SystemObject/Depot Object\" WHERE name \"starts with\" \"#{pkg}\""
	  response = RestClient.get URI.escape(urlos), :accept => :json 
	  parsed_response = JSON.parse(response)
      dbKey = parsed_response["PropertySetInstanceResponse"]["PropertySetInstance"]["dbKey"] rescue nil
	  if dbKey.nil? && (! osname.empty?) && (osname != "Windows")
	    response = RestClient.get URI.escape(urlgen), :accept => :json 
		parsed_response = JSON.parse(response)
		dbKey = parsed_response["PropertySetInstanceResponse"]["PropertySetInstance"]["dbKey"] rescue nil
		raise "The blpackage #{actionpath} is either not define for #{osname} or for Unix" if dbKey.nil?
	  else 
	    response = RestClient.get URI.escape(urlno), :accept => :json 
        parsed_response = JSON.parse(response)
	    dbKey = parsed_response["GroupChildrenResponse"]["GroupChildren"]["PropertySetInstances"]["Elements"][0]["dbKey"] rescue nil
		raise "The blpackage #{actionpath} do not exist" if dbKey.nil?
	  end
	  return dbKey
	end

	def get_server_list_from_multiselect(bsa_base_url, bsa_username, bsa_password, bsa_role, multiselect, maxserver=nil, list={ "Linux" => [], "Windows" => [], "Solaris" => [], "AIX" => [], "HP-UX" => [] })
	  multiselect.each do |elt|
	    case elt[2]
		  when "STATIC_SERVER_GROUP"
		    url = "#{bsa_base_url}/id/SystemObject/Static Group/Static Server Group/#{elt[1]}/?username=#{bsa_username}&password=#{bsa_password}&role=#{bsa_role}"
		  when "SMART_SERVER_GROUP"
		    url = "#{bsa_base_url}/id/SystemObject/Smart Group/#{elt[1]}/?username=#{bsa_username}&password=#{bsa_password}&role=#{bsa_role}"
		  else
		    url = "#{bsa_base_url}/id/SystemObject/Server/#{elt[1]}/PropertyValues/OS?username=#{bsa_username}&password=#{bsa_password}&role=#{bsa_role}"
		end
		response = RestClient.get URI.escape(url), :accept => :json 
		parsed_response = JSON.parse(response)
		if parsed_response.has_key? "ErrorResponse"
			raise "Error while query URL #{url}: #{parsed_response["ErrorResponse"]["Error"]}"
		end
		groups = parsed_response["GroupChildrenResponse"]["GroupChildren"]["Groups"]["Elements"] rescue nil
		if groups
		  data = []
		  groups.each do |group|
			data << [group["groupId"],group["objectId"],group["modelType"]]
		  end
		  list = get_server_list_from_multiselect(bsa_base_url, bsa_username, bsa_password, bsa_role, data, maxserver, list) unless data.empty?
		end
		servers = parsed_response["GroupChildrenResponse"]["GroupChildren"]["PropertySetInstances"]["Elements"] rescue nil
		if servers
		  data = []
		  servers.each do |object|
		    data << [object["name"],object["objectId"],"SERVER",object["dbKey"]]
		    unless maxserver.nil? 
			  maxserver = maxserver - 1 
		    end
		    list = get_server_list_from_multiselect(bsa_base_url, bsa_username, bsa_password, bsa_role, data, maxserver, list) if ( ! maxserver.nil? ) && ( maxserver <= 0 )
		  end
		  list = get_server_list_from_multiselect(bsa_base_url, bsa_username, bsa_password, bsa_role, data, maxserver, list) unless data.empty?
		end
		osname = parsed_response["PropertyValueResponse"]["PropertyValue"]["value"] rescue nil
		if osname
		  list[osname] << elt[0]
		  list[osname] = list[osname].uniq
		  unless maxserver.nil? 
			maxserver = maxserver - 1 
		  end
		end
	  end
	  return list
	end
	
	def get_component_list_from_multiselect(bsa_base_url, bsa_username, bsa_password, bsa_role, multiselect, template="", maxcomponent=nil)
	  list = []
	  multiselect.each do |elt|
	    case elt[2]
		  when "STATIC_COMPONENT_GROUP"
		    url = "#{bsa_base_url}/id/SystemObject/Static Group/Static Component Group/#{elt[1]}/?username=#{bsa_username}&password=#{bsa_password}&role=#{bsa_role}"
			url += "&bquery=SELECT * FROM \"SystemObject/Component\" WHERE TEMPLATE.NAME equals \"#{template}\"" unless template.empty?
		  when "SMART_COMPONENT_GROUP"
			url = "#{bsa_base_url}/id/SystemObject/Smart Group/#{elt[1]}/?username=#{bsa_username}&password=#{bsa_password}&role=#{bsa_role}"
			url += "&bquery=SELECT * FROM \"SystemObject/Component\" WHERE TEMPLATE.NAME equals \"#{template}\"" unless template.empty?
		  else
			url = "#{bsa_base_url}/query?username=#{bsa_username}&password=#{bsa_password}&role=#{bsa_role}"
			url += "&bquery=SELECT * FROM \"SystemObject/Component\" WHERE (TEMPLATE.NAME equals \"#{template}\") AND (NAME equals \"#{elt[0]}\")"
		end
		if ( elt[2] == "STATIC_COMPONENT_GROUP" ) || ( elt[2] == "SMART_COMPONENT_GROUP" ) || ( ! template.empty? )
			response = RestClient.get URI.escape(url), :accept => :json 
			parsed_response = JSON.parse(response)
			if parsed_response.has_key? "ErrorResponse"
				raise "Error while query URL #{url}: #{parsed_response["ErrorResponse"]["Error"]}"
			end
			groups = parsed_response["GroupChildrenResponse"]["GroupChildren"]["Groups"]["Elements"] rescue nil
			if groups
			  data = []
			  groups.each do |group|
				data << [group["groupId"],group["objectId"],group["modelType"]]
			  end
			  list.concat(get_component_list_from_multiselect(bsa_base_url, bsa_username, bsa_password, bsa_role, data, template)) unless data.empty?
			end
			components = parsed_response["GroupChildrenResponse"]["GroupChildren"]["PropertySetInstances"]["Elements"] rescue nil
			if components
			  components.each do |object|
			    list << [object["name"],object["objectId"],object["dbKey"]]
				unless maxcomponent.nil? 
					maxcomponent = maxcomponent - 1 
				end
				return list if ( ! maxcomponent.nil? ) && ( maxcomponent <= 0 )
			  end
			end
			component = parsed_response["PropertySetClassChildrenResponse"]["PropertySetClassChildren"]["PropertySetInstances"]["Elements"][0] rescue nil
			if component
				list << [component["name"],component["objectId"],component["dbKey"]]
				unless maxcomponent.nil? 
					maxcomponent = maxcomponent - 1 
				end
			end
		else
		  list << elt
		  unless maxcomponent.nil? 
			maxcomponent = maxcomponent - 1 
		  end
		end
		return list if ( ! maxcomponent.nil? ) && ( maxcomponent <= 0 )
	  end
	  return list
	end
	  
    def get_root_group_name(object_type)
      case object_type
      when "JOB_GROUP"
        return "Jobs"
      when "DEPOT_GROUP"
        return "Depot"
      when "STATIC_SERVER_GROUP"
        return "Servers"
      when "STATIC_COMPONENT_GROUP"
        return "Components"
      when "TEMPLATE_GROUP"
        return "Component Templates"
      end
    end

	def get_propertysetinstance_from_group_url(bsa_base_url, bsa_username, bsa_password, bsa_role, group_url)
      url = "#{bsa_base_url}#{group_url}"
      url += "?username=#{bsa_username}&password=#{bsa_password}&role=#{bsa_role}"

      response = RestClient.get URI.escape(url), :accept => :json 
      parsed_response = JSON.parse(response)

      if parsed_response.has_key? "ErrorResponse"
        raise "Error while query URL #{url}: #{parsed_response["ErrorResponse"]["Error"]}"
      end
  
      return parsed_response["GroupResponse"]["Group"] rescue nil
	end
	
	def get_propertysetinstance_from_object_url(bsa_base_url, bsa_username, bsa_password, bsa_role, object_url)
      url = "#{bsa_base_url}#{object_url}"
      url += "?username=#{bsa_username}&password=#{bsa_password}&role=#{bsa_role}"

      response = RestClient.get URI.escape(url), :accept => :json 
      parsed_response = JSON.parse(response)

      if parsed_response.has_key? "ErrorResponse"
        raise "Error while query URL #{url}: #{parsed_response["ErrorResponse"]["Error"]}"
      end
  
      return parsed_response["PropertySetInstanceResponse"]["PropertySetInstance"] rescue nil
	end
	
	def get_job_uri_from_job_qualified_name(bsa_base_url, bsa_username, bsa_password, bsa_role, job)
      url = "#{bsa_base_url}/group/Jobs#{job}"
      url += "?username=#{bsa_username}&password=#{bsa_password}&role=#{bsa_role}"

      response = RestClient.get URI.escape(url), :accept => :json 
      parsed_response = JSON.parse(response)

      if parsed_response.has_key? "ErrorResponse"
        raise "Error while query URL #{url}: #{parsed_response["ErrorResponse"]["Error"]}"
      end
  
      return parsed_response["PropertySetInstanceResponse"]["PropertySetInstance"]["uri"] rescue nil
	end

	def get_job_dbkey_from_job_qualified_name(bsa_base_url, bsa_username, bsa_password, bsa_role, job)
      url = "#{bsa_base_url}/group/Jobs#{job}"
      url += "?username=#{bsa_username}&password=#{bsa_password}&role=#{bsa_role}"

      response = RestClient.get URI.escape(url), :accept => :json 
      parsed_response = JSON.parse(response)

      if parsed_response.has_key? "ErrorResponse"
        raise "Error while query URL #{url}: #{parsed_response["ErrorResponse"]["Error"]}"
      end
  
      return parsed_response["PropertySetInstanceResponse"]["PropertySetInstance"]["dbKey"] rescue nil
	end
	
    def get_root_group(bsa_base_url, bsa_username, bsa_password, bsa_role, object_type, group_path="")
      url = "#{bsa_base_url}/group/#{get_root_group_name(object_type)}#{group_path}"
      url += "?username=#{bsa_username}&password=#{bsa_password}&role=#{bsa_role}"

      response = RestClient.get URI.escape(url), :accept => :json 
      parsed_response = JSON.parse(response)

      if parsed_response.has_key? "ErrorResponse"
        raise "Error while query URL #{url}: #{parsed_response["ErrorResponse"]["Error"]}"
      end
  
      return parsed_response["GroupResponse"]["Group"] rescue nil
    end

    def find_job_from_job_folder(bsa_base_url, bsa_username, bsa_password, bsa_role, job_name, job_model_type, job_group_rest_id)
      url = "#{bsa_base_url}/id/#{get_model_type_to_psc_name(job_model_type)}/#{job_group_rest_id}/"
      url += "?username=#{bsa_username}&password=#{bsa_password}&role=#{bsa_role}"
      url += "&bquery=select name from \"SystemObject/Job\" "
      url += " where name = \"#{job_name}\""

      response = RestClient.get URI.escape(url), :accept => :json 
      parsed_response = JSON.parse(response)

      if parsed_response.has_key? "ErrorResponse"
        raise "Error while query URL #{url}: #{parsed_response["ErrorResponse"]["Error"]}"
      end

      unless parsed_response["GroupChildrenResponse"]["GroupChildren"].has_key? "PropertySetInstances"
        raise "Could not find job #{job_name} inside selected job folder."
      end

      job_obj = parsed_response["GroupChildrenResponse"]["GroupChildren"]["PropertySetInstances"]["Elements"][0] rescue nil
      return job_obj
    end
	
	def get_assets_from_uri(bsa_base_url, bsa_username, bsa_password, bsa_role,uri)
		url = "#{bsa_base_url}#{uri}?username=#{bsa_username}&password=#{bsa_password}&role=#{bsa_role}"
		response = RestClient.get URI.escape(url), :accept => :json 
		parsed_response = JSON.parse(response)
		if parsed_response.has_key? "ErrorResponse"
			raise "Error while query URL #{url}: #{parsed_response["ErrorResponse"]["Error"]}"
		end
		if parsed_response["AssetChildrenResponse"]["AssetChildren"].has_key? "Assets"
			return parsed_response["AssetChildrenResponse"]["AssetChildren"]["Assets"]["Elements"]
		else
			return []
		end
	end
	
	def get_value_from_uri(bsa_base_url, bsa_username, bsa_password, bsa_role,uri)
		url = "#{bsa_base_url}#{uri}?username=#{bsa_username}&password=#{bsa_password}&role=#{bsa_role}"
		response = RestClient.get URI.escape(url), :accept => :json 
		parsed_response = JSON.parse(response)
		if parsed_response.has_key? "ErrorResponse"
			raise "Error while query URL #{url}: #{parsed_response["ErrorResponse"]["Error"]}"
		end
		return parsed_response["AssetAttributeValueResponse"]["AssetAttributeValue"]["value"]
	end
	
	def get_property_value_from_uri(bsa_base_url, bsa_username, bsa_password, bsa_role,uri,propname)
		url = "#{bsa_base_url}#{uri}/?username=#{bsa_username}&password=#{bsa_password}&role=#{bsa_role}"
		response = RestClient.get URI.escape(url), :accept => :json 
		parsed_response = JSON.parse(response)
		if parsed_response.has_key? "ErrorResponse"
			raise "Error while query URL #{url}: #{parsed_response["ErrorResponse"]["Error"]}"
		end
		if parsed_response["PropertySetInstanceChildrenResponse"]["PropertySetInstanceChildren"].has_key? "PropertyValues"
			parsed_response["PropertySetInstanceChildrenResponse"]["PropertySetInstanceChildren"]["PropertyValues"]["Elements"].each do |elt|
				return elt["value"] if elt["name"] == propname
			end
		end
		return []	
	end
	
	def get_template_dbkey_from_name(bsa_base_url, bsa_username, bsa_password, bsa_role,template)
	  url = "#{bsa_base_url}/query"
      url += "?username=#{bsa_username}&password=#{bsa_password}&role=#{bsa_role}"
	  url += "&BQUERY=SELECT NAME FROM \"SystemObject/Component Template\" WHERE NAME equals \"#{template}\""

      response = RestClient.get URI.escape(url), :accept => :json 
      parsed_response = JSON.parse(response)

      if parsed_response.has_key? "ErrorResponse"
        raise "Error: while query URL #{url}: #{parsed_response["ErrorResponse"]["Error"]}"
      end

	  dbkey = parsed_response["PropertySetClassChildrenResponse"]["PropertySetClassChildren"]["PropertySetInstances"]["Elements"][0]["dbKey"] rescue nil
      raise "Error: Could not find sever #{server}." if dbkey.nil?
      
      return dbkey
	end
	
	def get_server_dbkey_from_name(bsa_base_url, bsa_username, bsa_password, bsa_role,server)
      url = "#{bsa_base_url}/query"
      url += "?username=#{bsa_username}&password=#{bsa_password}&role=#{bsa_role}"
      url += "&BQUERY=SELECT NAME FROM \"SystemObject/Server\" WHERE NAME equals \"#{server}\""

      response = RestClient.get URI.escape(url), :accept => :json 
      parsed_response = JSON.parse(response)

      if parsed_response.has_key? "ErrorResponse"
        raise "Error: while query URL #{url}: #{parsed_response["ErrorResponse"]["Error"]}"
      end

	  dbkey = parsed_response["PropertySetClassChildrenResponse"]["PropertySetClassChildren"]["PropertySetInstances"]["Elements"][0]["dbKey"] rescue nil
      raise "Error: Could not find sever #{server}." if dbkey.nil?
      
      return dbkey	
	end
	
	def get_server_uri_from_name(bsa_base_url, bsa_username, bsa_password, bsa_role,server)
      url = "#{bsa_base_url}/query"
      url += "?username=#{bsa_username}&password=#{bsa_password}&role=#{bsa_role}"
      url += "&BQUERY=SELECT NAME FROM \"SystemObject/Server\" WHERE NAME equals \"#{server}\""

      response = RestClient.get URI.escape(url), :accept => :json 
      parsed_response = JSON.parse(response)

      if parsed_response.has_key? "ErrorResponse"
        raise "Error: while query URL #{url}: #{parsed_response["ErrorResponse"]["Error"]}"
      end

	  servuri = parsed_response["PropertySetClassChildrenResponse"]["PropertySetClassChildren"]["PropertySetInstances"]["Elements"][0]["uri"] rescue nil
      raise "Error: Could not find sever #{server}." if servuri.nil?
      
      return servuri	
	end
	
	def list_virtual_mgr(bsa_base_url, bsa_username, bsa_password, bsa_role)
		result = []
		url = "#{bsa_base_url}/type/PropertySetClasses/SystemObject/Virtualization/"
		url += "?username=#{bsa_username}&password=#{bsa_password}&role=#{bsa_role}"
		response = RestClient.get URI.escape(url), :accept => :json 
		parsed_response = JSON.parse(response)["PropertySetClassChildrenResponse"]["PropertySetClassChildren"]["PropertySetInstances"]["Elements"]
		parsed_response.each do |elt|
			servname = elt["name"]
			url = "#{bsa_base_url}#{elt["uri"]}/"
			url += "?username=#{bsa_username}&password=#{bsa_password}&role=#{bsa_role}"
			response = RestClient.get URI.escape(url), :accept => :json 
			response = JSON.parse(response)["PropertySetInstanceChildrenResponse"]["PropertySetInstanceChildren"]["PropertyValues"]["Elements"]
			mgr = ""
			response.each do |serv|
				mgr = serv["value"] if serv["name"] == "VIRTUAL_ENTITY_TYPE"
			end
			uri = get_server_uri_from_name(bsa_base_url, bsa_username, bsa_password, bsa_role, servname)
			dbkey = get_server_dbkey_from_name(bsa_base_url, bsa_username, bsa_password, bsa_role, servname)
			result << {"name" => servname, "id" => get_id_from_db_key(dbkey), "mgr" => mgr, "uri" => uri}
		end
		return result
	end
	
    ########################################################################################
    #                                   SOAP SERVICES                                      #
    ########################################################################################



    def bsa_soap_login(bsa_base_url, bsa_username, bsa_password)
      client = Savon.client("#{bsa_base_url}/services/BSALoginService.wsdl") do |wsdl, http|
         http.auth.ssl.verify_mode = :none 
      end

      response = client.request(:login_using_user_credential) do |soap|
        soap.endpoint = "#{bsa_base_url}/services/LoginService"
        soap.body = {:userName => bsa_username, :password => bsa_password, :authenticationType => "SRP"}
      end

      session_id = response.body[:login_using_user_credential_response][:return_session_id]
    end

    def bsa_soap_assume_role(bsa_base_url, bsa_role, session_id)
      client = Savon.client("#{bsa_base_url}/services/BSAAssumeRoleService.wsdl") do |wsdl, http|
        http.auth.ssl.verify_mode = :none
      end

      client.http.read_timeout = 300

      reponse = client.request(:assume_role) do |soap|
        soap.endpoint = "#{bsa_base_url}/services/AssumeRoleService"
        soap.header = {"ins0:sessionId" => session_id}
        soap.body = { :roleName => bsa_role }
      end
    end

    def bsa_soap_validate_cli_result(result)
      if result && (result.is_a? Hash)
        if result[:success] == false
          raise "Command execution failed: #{result[:error]}, #{result[:comments]}"
        end
        return result
      else
        raise "Command execution did not return a valid response: #{result.inspect}"
      end
      nil
    end

    def bsa_soap_execute_cli_command_using_attachments(bsa_base_url, session_id, namespace, command, args, payload)
      client = Savon.client("#{bsa_base_url}/services/BSACLITunnelService.wsdl") do |wsdl, http|
        http.auth.ssl.verify_mode = :none
      end

      client.http.read_timeout = 300

      response = client.request(:execute_command_using_attachments) do |soap|
        soap.endpoint = "#{bsa_base_url}/services/CLITunnelService"
        soap.header = {"ins1:sessionId" => session_id}
       
        body_details = { :nameSpace => namespace, :commandName => command, :commandArguments => args }
		
		if payload
			payload = Base64.encode64(payload)
			body_details.merge!({:payload => { :argumentNameArray => "fileName", :dataHandlerArray => [payload], :fileNameArray => "sentpayload"}})
		end

        soap.body = body_details
      end

      result = response.body[:execute_command_using_attachments_response][:return]
      return bsa_soap_validate_cli_result(result)
    end

    def bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, namespace, command, args)
      client = Savon.client("#{bsa_base_url}/services/BSACLITunnelService.wsdl") do |wsdl, http|
        http.auth.ssl.verify_mode = :none
      end
      
      client.http.read_timeout = 300

      response = client.request(:execute_command_by_param_list) do |soap|
        soap.endpoint = "#{bsa_base_url}/services/CLITunnelService"
        soap.header = {"ins1:sessionId" => session_id}
        soap.body = { :nameSpace => namespace, :commandName => command, :commandArguments => args }
      end

      result = response.body[:execute_command_by_param_list_response][:return]
      return bsa_soap_validate_cli_result(result)
    end
	
	def bsa_soap_execute_cli_with_no_check(bsa_base_url, session_id, namespace, command, args)
      client = Savon.client("#{bsa_base_url}/services/BSACLITunnelService.wsdl") do |wsdl, http|
        http.auth.ssl.verify_mode = :none
      end
      
      client.http.read_timeout = 300

      response = client.request(:execute_command_by_param_list) do |soap|
        soap.endpoint = "#{bsa_base_url}/services/CLITunnelService"
        soap.header = {"ins1:sessionId" => session_id}
        soap.body = { :nameSpace => namespace, :commandName => command, :commandArguments => args }
      end

      result = response.body[:execute_command_by_param_list_response][:return]
      return result
    end
	
	def bsa_soap_get_uri_from_dbkey(bsa_base_url, session_id, dbkey)
		return bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "GenericObject", "getRESTfulURI", [dbkey])[:return_value]
	end
	
	def bsa_soap_get_blpackage_property_list(bsa_base_url, session_id, dbkey)
		result = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "BlPackage", "listLocalParametersByDBKey", [dbkey])[:return_value]
		return result[1..(result.length-2)].split(", ")
	end
	
	def bsa_soap_get_vgp_by_group_and_name(bsa_base_url, session_id, group, vgpname)
		vgpid = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "Virtualization", "getVirtualGuestPackageIdByGroupAndName", [group,vgpname])[:return_value]
		return bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "Virtualization", "getVirtualGuestPackage", [vgpid])[:return_value]
	end
	
	def bsa_soap_get_uri_from_servername(bsa_base_url, session_id, servername)
		dbkey = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "Server", "getServerDBKeyByName", [servername])[:return_value]
		return bsa_soap_get_uri_from_dbkey(bsa_base_url, session_id, dbkey)
	end
	
	def bsa_soap_execute_job_against(bsa_base_url, bsa_username, bsa_password, bsa_role, session_id, jobkey, targets)
		#first we remove all targets from the job
		jobkey = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "Job", "clearTargetComponentGroups", [jobkey])[:return_value]
		jobkey = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "Job", "clearTargetComponents", [jobkey])[:return_value]
		jobkey = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "Job", "clearTargetGroups", [jobkey])[:return_value]
		jobkey = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "Job", "clearTargetServers", [jobkey])[:return_value]
		# Adding the targets to the job
		targets.each do |t|
			case t.split("|")[0]
			when "SERVER"
				jobkey = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "Job", "addTargetServer", [jobkey,t.split("|")[1]])[:return_value]
			when "COMPONENT"
				jobkey = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "Job", "addTargetComponent", [jobkey,t.split("|")[2]])[:return_value]
			when "STATIC_SERVER_GROUP","SMART_SERVER_GROUP"
				jobkey = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "Job", "addTargetGroup", [jobkey,"#{t.split("|")[1]}"])[:return_value]
			when "STATIC_COMPONENT_GROUP","SMART_COMPONENT_GROUP"
				jobkey = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "Job", "addTargetComponentGroup", [jobkey,"#{t.split("|")[1]}"])[:return_value]
			end
		end
		# Run the job
		job_url = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "GenericObject", "getRESTfulURI", [jobkey])[:return_value]
		execute_job(bsa_base_url, bsa_username, bsa_password, bsa_role, job_url)
	end
	
    def bsa_soap_create_blpackage_deploy_job(bsa_base_url, session_id, job_folder_id, job_name, package_db_key, targets,iSimulateEnabled=true, isStageIndirect=false)
      if targets.nil? || targets.empty?
        raise "Atleast one target needs to be specified while creating a blpackage deploy job"
      end

      result = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "DeployJob", "createDeployJob",
                  [
                    job_name,                       #deployJobName
                    job_folder_id,                  #groupId
                    package_db_key,                 #packageKey
                    1,                              #deployType (0 = BASIC, 1 = ADVANCED)
                    targets.first,                  #serverName
                    iSimulateEnabled,                           #isSimulateEnabled
                    true,                           #isCommitEnabled
                    isStageIndirect,                #isStagedIndirect
                    2,                              #logLevel (0 = ERRORS, 1 = ERRORS_AND_WARNINGS, 2 = ALL_INFO)
                    true,                           #isExecuteByPhase
                    false,                          #isResetOnFailure
                    true,                           #isRollbackAllowed
                    false,                          #isRollbackOnFailure
                    true,                           #isRebootIfRequired
                    true,                           #isCopyLockedFilesAfterReboot
                    true,                           #isStagingAfterSimulate
                    true                            #isCommitAfterStaging
                  ])

      job_db_key = result[:return_value]
       
      targets.each do |t|
        unless (t == targets.first)
          job_db_key = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "DeployJob", "addNamedServerToJobByJobDBKey", [job_db_key, t])[:return_value]
        end
      end
      job_db_key
    end

    def bsa_soap_create_component_based_blpackage_deploy_job(bsa_base_url, session_id, job_folder_id, job_name, package_db_key, targets, isSimulate=true, isStagedIndirect=false)
      if targets.nil? || targets.empty?
        raise "Atleast one component needs to be specified while creating a component based blpackage deploy job"
      end

      result = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "DeployJob", "createComponentBasedDeployJob",
                  [
                    job_name,                       #deployJobName
                    job_folder_id,                  #groupId
                    package_db_key,                 #packageKey
                    1,                              #deployType (0 = BASIC, 1 = ADVANCED)
                    targets.first,                  #componentKey
                    isSimulate,                     #isSimulateEnabled
                    true,                           #isCommitEnabled
                    isStagedIndirect,               #isStagedIndirect
                    2,                              #logLevel (0 = ERRORS, 1 = ERRORS_AND_WARNINGS, 2 = ALL_INFO)
                    true,                           #isExecuteByPhase
                    false,                          #isResetOnFailure
                    true,                           #isRollbackAllowed
                    false,                          #isRollbackOnFailure
                    true,                           #isRebootIfRequired
                    true,                           #isCopyLockedFiles
                    true,                           #isStagingAfterSimulate
                    true,                           #isCommitAfterStaging
                    false,                          #isSingleDeployModeEnabled
                    false,                          #isSUMEnabled
                    0,                              #singleUserMode
                    0,                              #rebootMode
                    false,                          #isMaxWaitTimeEnabled
                    "30",                           #maxWaitTime
                    false,                          #isMaxAgentConnectionTimeEnabled
                    60,                             #maxAgentConnectionTime
                    false,                          #isFollowSymlinks
                    false,                          #useReconfigRebootAtEndOfJob
                    0                               #overrideItemReconfigReboot
                  ])

      job_db_key = result[:return_value]
       
      targets.each do |t|
        unless (t == targets.first)
          job_db_key = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "DeployJob", "addComponentToJobByJobDBKey", [job_db_key, t])[:return_value]
        end
      end
      job_db_key
    end

    def bsa_soap_create_software_deploy_job(bsa_base_url, session_id, job_folder_id, job_name, software_db_key, model_type, targets)
      if targets.nil? || targets.empty?
        raise "Atleast one target needs to be specified while creating a software deploy job"
      end

      result = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "DeployJob", "createSoftwareDeployJob",
                  [
                    job_name,                       #deployJobName
                    job_folder_id,                  #groupId
                    software_db_key,                #objectKey
                    model_type,                     #modelType
                    targets.first,                  #serverName
                    true,                           #isSimulateEnabled
                    true,                           #isCommitEnabled
                    false,                          #isStagedIndirect
                    2,                              #logLevel (0 = ERRORS, 1 = ERRORS_AND_WARNINGS, 2 = ALL_INFO)
                    false,                          #isResetOnFailure
                    true,                           #isRollbackAllowed
                    false,                          #isRollbackOnFailure
                    true,                           #isRebootIfRequired
                    true                            #isCopyLockedFilesAfterReboot
                  ])

      job_db_key = result[:return_value]
       
      targets.each do |t|
        unless (t == targets.first)
          job_db_key = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "DeployJob", "addNamedServerToJobByJobDBKey", [job_db_key, t])[:return_value]
        end
      end

      job_db_key
    end

    def bsa_soap_create_file_deploy_job(bsa_base_url, session_id, job_folder, job_name, source_file_list, destination_dir, targets)
      if targets.nil? || targets.empty?
        raise "Atleast one target needs to be specified while creating a file deploy job"
      end

      source_files_arg = source_file_list.join(",")
      targets_arg = targets.join(",")

      result = bsa_soap_execute_cli_command_using_attachments(bsa_base_url, session_id, "FileDeployJob", "createJobByServers",
                    [
                      job_name,                     #jobName
                      job_folder,                   #jobGroup
                      source_files_arg,             #sourceFiles
                      destination_dir,              #destination
                      false,                        #isPreserveSourceFilePaths
                      0,                            #numTargetsInParallel
                      targets_arg                   #targetServerNames
                    ], nil)

      return result[:return_value]
    end

    def bsa_soap_job_group_to_id(bsa_base_url, session_id, job_folder)
      result = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "JobGroup", "groupNameToId", [job_folder])
      return result[:return_value]
    end

    def bsa_soap_get_group_qualified_path(bsa_base_url, session_id, group_type, group_id)
      result = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "Group", "getAQualifiedGroupName",
                  [
                    get_model_type_to_model_type_id(group_type),    #groupType
                    group_id                                        #groupId
                  ])

      qualified_name = result[:return_value]
    end

    def bsa_soap_get_group_id_for_job(bsa_base_url, session_id, job_key)
      result = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "Job", "getGroupId",
                  [
                    job_key    #jobKey
                  ])

      return result[:return_value]
    end
	
	def bsa_soap_set_properties_for_deployjob(bsa_base_url, session_id, group_id, job_name, prop_name, isAutomapped=true, prop_value=nil)
	  groupName = bsa_soap_get_group_qualified_path(bsa_base_url, session_id, "JOB_GROUP", group_id)
	  if isAutomapped
	    jobDBKey = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id,"DeployJob","setParameterComponentPropertyName",[groupName, job_name, prop_name, false])[:return_value]
	  else
	    jobDBKey = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "DeployJob", "setOverriddenParameterValue", [groupName, job_name, prop_name, prop_value])[:return_value]
	  end
	  return jobDBKey
	end
	
	def bsa_soap_get_package_action_dbkey(bsa_base_url, session_id, genericname, component_dbkey)
	  # genericname is the full qualified name of the package action without OS extension
	  osname = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "Component","getFullyResolvedPropertyValue", [component_dbkey, "TARGET"])[:return_value]
	  servname = osname.sub(/.*\//,'')
	  osname = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "Server","getFullyResolvedPropertyValue", [servname, "OS"])[:return_value]
	  group = File.dirname(genericname)
	  pkg = File.basename(genericname)
	  dbKey = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "BlPackage","getDBKeyByGroupAndName", [group, "#{pkg}-#{osname}"])[:return_value] rescue nil
	  if dbKey.nil?
		dbKey = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "BlPackage","getDBKeyByGroupAndName", [group, "#{pkg}-Unix"])[:return_value] rescue nil
	  end
	  return dbKey
	end
	
	def bsa_soap_check_or_create_group_path(bsa_base_url, session_id,group_path,folder_type)
	  # folder_type can be: "TEMPLATES", "COMPONENTS", "DEPOT", "JOBS", "SERVERS"
	  case folder_type
		when "TEMPLATE"
		  result = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "TemplateGroup","groupNameToId", [group_path])[:return_value] rescue nil
		  if result.nil?
		    parent_path = File.dirname(group_path)
			group = File.basename(group_path)
		    parentid = bsa_soap_check_or_create_group_path(bsa_base_url, session_id,parent_path,folder_type)
			result = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "TemplateGroup","createTemplateGroup", [group,parentid])[:return_value]
		  end
		  return result
		when "COMPONENTS"
		  result = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "ComponentGroup","groupNameToId", [group_path])[:return_value] rescue nil
		  if result.nil?
		    parent_path = File.dirname(group_path)
			group = File.basename(group_path)
		    parentid = bsa_soap_check_or_create_group_path(bsa_base_url, session_id,parent_path,folder_type)
			result = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "StaticComponentGroup","createComponentGroup", [group,parentid])[:return_value]
		  end
		  return result
		when "DEPOT"
		  result = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "DepotGroup","groupNameToId", [group_path])[:return_value] rescue nil
		  if result.nil?
		    parent_path = File.dirname(group_path)
			group = File.basename(group_path)
		    parentid = bsa_soap_check_or_create_group_path(bsa_base_url, session_id,parent_path,folder_type)
			result = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "DepotGroup","createDepotGroup", [group,parentid])[:return_value]
		  end
		  return result
		when "JOBS"
		  result = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "JobGroup","groupNameToId", [group_path])[:return_value] rescue nil
		  if result.nil?
		    parent_path = File.dirname(group_path)
			group = File.basename(group_path)
		    parentid = bsa_soap_check_or_create_group_path(bsa_base_url, session_id, parent_path, folder_type)
			result = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "JobGroup","createJobGroup", [group,parentid])[:return_value]
		  end
		  return result
		when "SERVERS"
		  result = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "ServerGroup","groupNameToId", [group_path])[:return_value] rescue nil
		  if result.nil?
		    parent_path = File.dirname(group_path)
			group = File.basename(group_path)
		    parentid = bsa_soap_check_or_create_group_path(bsa_base_url, session_id,parent_path,folder_type)
			result = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "ServerGroup","createStaticServerGroup", [group,parentid])[:return_value]
		  end
		  return result		
		else 
		  raise "Error: folder type cannot be #{foder_type}"
	  end
	end

    def bsa_soap_export_deploy_job_results(bsa_base_url, session_id, job_folder, job_name, job_run_id)
      result = bsa_soap_execute_cli_command_using_attachments(bsa_base_url, session_id,
                    "Utility", "exportDeployRun", [job_folder, job_name, job_run_id, "/tmp/test.csv"], nil)
      if result && (result.has_key?(:attachment))
        attachment = result[:attachment]
        csv_data = Base64.decode64(attachment)
        return csv_data
      end
      nil
    end

    def bsa_soap_export_snapshot_job_results(bsa_base_url, session_id, job_folder, job_name, job_run_id, targets, export_format = "CSV")
      csv_data = ""
      targets.each do | target |
        result = bsa_soap_execute_cli_command_using_attachments(bsa_base_url, session_id,
                    "Utility", "exportSnapshotRun", [job_folder, job_name, job_run_id, "null", "null",
                        target, "/tmp/test.#{(export_format == "HTML") ? "html" : "csv"}", export_format], nil)
        if result && (result.has_key?(:attachment))
          attachment = result[:attachment]
          csv_data = csv_data + Base64.decode64(attachment) + "\n"
        end
      end
      csv_data
    end

    def bsa_soap_export_nsh_script_job_results(bsa_base_url, session_id, job_run_id)
      result = bsa_soap_execute_cli_command_using_attachments(bsa_base_url, session_id,
                    "Utility", "exportNSHScriptRun", [job_run_id, "/tmp/test.csv"], nil)
      if result && (result.has_key?(:attachment))
        attachment = result[:attachment]
        csv_data = Base64.decode64(attachment)
        return csv_data
      end
      nil
    end    

    def bsa_soap_export_compliance_job_results(bsa_base_url, session_id, job_folder, job_name, job_run_id, export_format = "CSV")
      result = bsa_soap_execute_cli_command_using_attachments(bsa_base_url, session_id,
                    "Utility", "exportComplianceRun", ["null", "null", "null", job_folder, job_name, job_run_id, 
                            "/tmp/test.#{(export_format == "HTML") ? "html" : "csv"}", export_format], nil)
      if result && (result.has_key?(:attachment))
        attachment = result[:attachment]
        csv_data = Base64.decode64(attachment)
        return csv_data
      end
      nil
    end

    def bsa_soap_export_audit_job_results(bsa_base_url, session_id, job_folder, job_name, job_run_id)
      result = bsa_soap_execute_cli_command_using_attachments(bsa_base_url, session_id,
                    "Utility", "simpleExportAuditRun", [job_folder, job_name, job_run_id, "/tmp/test.csv", ""], nil)
      if result && (result.has_key?(:attachment))
        attachment = result[:attachment]
        csv_data = Base64.decode64(attachment)
        return csv_data
      end
      nil
    end

    def bsa_soap_db_key_to_rest_uri(bsa_base_url, session_id, db_key)
      result = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "GenericObject", "getRESTfulURI", [db_key])
      result[:return_value]
    end

    def bsa_soap_map_server_names_to_rest_uri(bsa_base_url, session_id, servers)
      targets = []
      servers.each do |server|
        result = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "Server", "getServerDBKeyByName", [server])
        targets << bsa_soap_db_key_to_rest_uri(bsa_base_url, session_id, result[:return_value])
      end
      targets
    end

    def bsa_create_bl_package_from_component(bsa_base_url, session_id, package_name, depot_group_id, component_key)
      result = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "BlPackage", "createPackageFromComponent",
                  [
                    package_name,       #packageName
                    depot_group_id,     #groupId
                    true,               #bSoftLinked
                    false,              #bCollectFileAcl
                    false,              #bCollectFileAttributes
                    true,               #bCopyFileContents
                    false,              #bCollectRegistryAcl
                    component_key,      #componentKey
                  ])

      bl_package_key = result[:return_value]
    end

    def bsa_set_bl_package_property_value_in_deploy_job(bsa_base_url, session_id, job_group_path, job_name, property, value_as_string)
      result = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "DeployJob", "setOverriddenParameterValue",
                  [
                    job_group_path,     #groupName
                    job_name,           #jobName
                    property,           #parameterName
                    value_as_string     #valueAsString
                  ])

      deploy_job = result[:return_value]
    end
	
	def bsa_set_nsh_script_property_value_in_job(bsa_base_url, session_id, job_group_path, job_name, propindex, value_as_string)
      result = bsa_soap_execute_cli_command_by_param_list(bsa_base_url, session_id, "NSHScriptJob", "addNSHScriptParameterValueByGroupAndName",
                  [
                    job_group_path,     #groupName
                    job_name,           #jobName
                    propindex,           #parameterName
                    value_as_string     #valueAsString
                  ])

      deploy_job = result[:return_value]
    end

  end
end
