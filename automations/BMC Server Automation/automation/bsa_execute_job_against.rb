###
#
# job_type:
#   name: Job Type
#   type: in-list-single
#   list_pairs: 0,Select|1,FileDeploy|2,PackageDeploy|3,NSHScriptJob|4,SnapshotJob|5,ComplianceJob|6,AuditJob
#   position: A1:B1
#   required: yes
# job:
#   name: Job
#   type: in-external-single-select
#   external_resource: bsa_jobs
#   position: A2:F2
# target_mode:
#   name: Target Mode
#   type: in-list-single
#   list_pairs: 0,Select|1,JobDefaultTargets|2,AlternateBAAComponents|3,MappedBAAComponents|4,AlternateBAAServers|5,MapFromBRPMServers
#   position: A3:B3
# targets:
#   name: Targets
#   type: in-external-multi-select
#   external_resource: bsa_job_targets
#   position: A4:F4
# job_status:
#   name: Job Status
#   type: out-text
#   position: A1:C1
# target_status:
#   name: Target Status
#   type: out-table
#   position: A2:F2
# job_log:
#   name: Job Log
#   type: out-file
#   position: A3:F3
# job_log_html:
#   name: Job Log HTML
#   type: out-url
#   position: A4:F4
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

def get_target_url_prefix(target_mode)
  case target_mode
  when "4", "AlternateBAAServers"
    return "/id/SystemObject/Server/"
  when "2", "AlternateBAAComponents", "3", "MappedBAAComponents"
    return "/id/SystemObject/Component/"
  end
end

def export_job_results(session_id, job_folder, job_name, job_run_id, job_type, target_names)
  case job_type
  when "2", "PackageDeploy"
    return BsaUtilities.bsa_soap_export_deploy_job_results(BSA_BASE_URL, session_id, job_folder, job_name, job_run_id)
  when "3", "NSHScriptJob"
    return BsaUtilities.bsa_soap_export_nsh_script_job_results(BSA_BASE_URL, session_id, job_run_id)
  when "4", "SnapshotJob"
    return BsaUtilities.bsa_soap_export_snapshot_job_results(BSA_BASE_URL, session_id, job_folder, job_name, job_run_id, target_names, "CSV")
  when "5", "ComplianceJob"
    return BsaUtilities.bsa_soap_export_compliance_job_results(BSA_BASE_URL, session_id, job_folder, job_name, job_run_id, "CSV")
  when "6", "AuditJob"
    return BsaUtilities.bsa_soap_export_audit_job_results(BSA_BASE_URL, session_id, job_folder, job_name, job_run_id)
  end
  return nil
end

def export_html_job_results(session_id, job_folder, job_name, job_run_id, job_type, target_names)
  case job_type
  when "4", "SnapshotJob"
    return BsaUtilities.bsa_soap_export_snapshot_job_results(BSA_BASE_URL, session_id, job_folder, job_name, job_run_id, target_names, "HTML")
  when "5", "ComplianceJob"
    return BsaUtilities.bsa_soap_export_compliance_job_results(BSA_BASE_URL, session_id, job_folder, job_name, job_run_id, "HTML")
  end
  return nil
end

def get_mapped_model_type(job_type)
  case job_type
  when "1", "FileDeploy"
    return "FILE_DEPLOY_JOB"
  when "2", "PackageDeploy"
    return "DEPLOY_JOB"
  when "3", "NSHScriptJob"
    return "NSH_SCRIPT_JOB"
  when "4", "SnapshotJob"
    return "SNAPSHOT_JOB"
  when "5", "ComplianceJob"
    return "COMPLIANCE_JOB"
  when "6", "AuditJob"
    return "AUDIT_JOB"
  end
end

  begin
    job_params = params["job"].split("|")
    job_name = job_params[0]
    job_rest_id = job_params[1]
    job_db_key = job_params[2]

    job_url = "/id/#{BsaUtilities.get_model_type_to_psc_name(get_mapped_model_type(params["job_type"]))}/#{job_rest_id}"

    if (params["job_type"] == "1") || (params["job_type"] == "FileDeploy") ||
     (params["job_type"] == "3") || (params["job_type"] == "NSHScriptJob") ||
     (params["job_type"] == "4") || (params["job_type"] == "SnapshotJob")

      if (params["target_mode"] == "2") || (params["target_mode"] == "AlternateBAAComponents") ||
        (params["target_mode"] == "3") || (params["target_mode"] == "MappedBAAComponents")
        raise "File deploy job cannot be run against components. It can run only against servers"
      end

    end

    session_id = BsaUtilities.bsa_soap_login(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD)
    raise "Could not login to BAA Cli Tunnel Service" if session_id.nil?

    BsaUtilities.bsa_soap_assume_role(BSA_BASE_URL, BSA_ROLE, session_id)

    targets = []
    target_names = []

    if (params["target_mode"] == "5") || (params["target_mode"] == "MapFromBRPMServers")
      targets = params["servers"].split(",").collect{|s| "SERVER|" + s.strip} if params["servers"]
      raise "No BRPM servers found to map to BAA servers" if (targets.nil? || targets.empty?)
      target_names = params["servers"].split(",").collect{|s| s.strip}
    elsif params["targets"]
      targets = params["targets"].split(",")
	  targets.each do |x|
		target_names << x.split("|")[0] if (x.split("|")[2] == "SERVER")
	  end
      targets = targets.collect{ |t| "#{t.split("|")[2]}|#{t.split("|")[0]}|#{t.split("|")[3]}" }
    end

    if (params["target_mode"] == "4") || (params["target_mode"] == "AlternateBAAServers") ||
      (params["target_mode"] == "5") || (params["target_mode"] == "MapFromBRPMServers") ||
	  (params["target_mode"] == "2") || (params["target_mode"] == "AlternateBAAComponents") ||
      (params["target_mode"] == "3") || (params["target_mode"] == "MappedBAAComponents")
      h = BsaUtilities.bsa_soap_execute_job_against(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, session_id, job_db_key, targets)
    elsif (params["target_mode"] == "1") || (params["target_mode"] == "JobDefaultTargets")
      h = BsaUtilities.execute_job(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, job_url)
    end

    raise "Could run specified job, did not get a valid response from server" if h.nil?

    execution_status = "_SUCCESSFULLY"
    execution_status = "_WITH_WARNINGS" if (h["had_warnings"] == "true")
    if (h["had_errors"] == "true")
      execution_status = "_WITH_ERRORS"
      write_to("Job Execution failed: Please check job logs for errors")
    end

    pack_response "job_status", h["status"] + execution_status

    job_run_url = h["job_run_url"]
    write_to("Job Run URL: #{job_run_url}")

    job_run_id = BsaUtilities.get_job_run_id(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, job_run_url)
    raise "Could not fetch job_run_id" if job_run_id.nil?

    job_result_url = BsaUtilities.get_job_result_url(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, job_run_url)
    
    if job_result_url
      h = BsaUtilities.get_per_target_results(BSA_BASE_URL, BSA_USERNAME, BSA_PASSWORD, BSA_ROLE, job_result_url)
      if h
        table_data = [['', 'Target Type', 'Name', 'Had Errors?', 'Had Warnings?', 'Need Reboot?', 'Exit Code']]
        target_count = 0
        h.each_pair do |k3, v3|
          v3.each_pair do |k1, v1|
            table_data << ['', k3, k1, v1['HAD_ERRORS'], v1['HAD_WARNINGS'], v1['REQUIRES_REBOOT'], v1['EXIT_CODE*']]
            target_count = target_count + 1
          end
        end
        pack_response "target_status", {:totalItems => target_count, :perPage => '10', :data => table_data }
      end
    else
      write_to("Could not fetch job_result_url, target based status not available")
    end

    job_folder_id = BsaUtilities.bsa_soap_get_group_id_for_job(BSA_BASE_URL, session_id, job_db_key)
    job_folder_path = BsaUtilities.bsa_soap_get_group_qualified_path(BSA_BASE_URL, session_id, "JOB_GROUP", job_folder_id)

    results_csv = export_job_results(session_id, job_folder_path, job_name, job_run_id, params["job_type"], target_names)
    if results_csv
      bsa_job_logs = File.join(params["SS_automation_results_dir"], "bsa_job_logs")
      unless File.directory?(bsa_job_logs)
        Dir.mkdir(bsa_job_logs, 0700)
      end

      log_file_path = File.join(bsa_job_logs, "#{job_run_id}.log")
      fh = File.new(log_file_path, "w")
      fh.write(results_csv)
      fh.close

      pack_response "job_log", log_file_path
    else
      write_to("Could not fetch job results...")
    end

    results_html = export_html_job_results(session_id, job_folder_path, job_name, job_run_id, params["job_type"], target_names)
    if results_html
      bsa_job_logs = File.join(params["SS_automation_results_dir"], "bsa_job_logs")
      unless File.directory?(bsa_job_logs)
        Dir.mkdir(bsa_job_logs, 0700)
      end
      resultarray = results_html.split("\n")
      index = 0
      compok = "false"
      while (index < resultarray.length) do
        if resultarray[index].include?('<tr><td><b>Failed Checks:</b></td>')
          if resultarray[index+1].include?('<td>0</td></tr>')
            compok = "true"
          else
            results_html = results_html + '<HTML><BODY><p><p><p align="center"><a href="waitrun.jsp"><img src="rem_button.jpg" align="middle"></p></BODY></HTML>'
          end
          index = resultarray.length
        end
        index = index+1
      end
      log_file_path = params["SS_automation_results_dir"]
	  log_file_path["automation_results"] = "server/webapps/ROOT/automation/#{job_run_id}.html"
      fh = File.new(log_file_path, "w")
      fh.write(results_html)
      if (params["job_type"] == "ComplianceJob")
        towrite = "#{job_db_key}\n#{job_run_id}"
        fp = File.new("/opt/bmc/BRLM/server/webapps/ROOT/automation/param.txt","w")
        fp.write(towrite)
        fp.close		
      end
      fh.close
      result_url = params["SS_base_url"]
      result_url["/brpm"] = "/automation/#{job_run_id}.html"
      pack_response "job_log_html", result_url
      raise "ERROR: Compliance drifts" if (compok == "false")
    end

  rescue Exception => e
    write_to("Operation failed: #{e.message}, Backtrace:\n#{e.backtrace.inspect}")
  end