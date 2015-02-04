#! /usr/bin/env python

# Goal: setup the sample and run JSON files to be pushed driver.pl
# The output of this script is the /upload/path/to/Run1  or the path to place the run files on the server we're pushing to.

import os
import os.path
import sys
import re
from optparse import OptionParser
import json
import time


# some global variables
PLUTO_BACKUP_PATH="/mnt/Charon/archivedReports"
MERCURY_BACKUP_PATH="/mnt/Triton/archivedReports"
PGM_BACKUP_PATH="/media/Backup_02/archivedReports"

class Setup_Json:
	def __init__(self, plugin_settings, options):
		self.plugin_settings = plugin_settings
	# RESULTS_DIR is the path to the run's plugin dir (i.e. /results/analysis/output/Home/Reanalsys_PNET_BC373_Run4_1342/plugin_out/QCRunTransfer_out.2921)
		self.output_dir = os.environ['TSP_FILEPATH_PLUGIN_DIR']
		self.options = options
		self.ex_json = json.load(open('%s/scripts/%s.json'%(os.environ['PLUGIN_PATH'], plugin_settings['project'])))

	# @param run the line of the CSV 
	def setup_json(self):
		# set the paths and names according to the run_type
		if self.ex_json['sample_type'] == 'tumor_normal':
			if self.plugin_settings['run_type'] == "normal":
				run_path = "%s/%s/Normal/N-%s" %(self.plugin_settings['upload_path'], self.plugin_settings['sample_name'], self.plugin_settings['run_num'])
				run_name = "N-" + self.plugin_settings['run_num']
			elif self.plugin_settings['run_type'] == "tumor":
				run_path = "%s/%s/Tumor/T-%s" %(self.plugin_settings['upload_path'], self.plugin_settings['sample_name'], self.plugin_settings['run_num'])
				run_name = "T-" + self.plugin_settings['run_num']
		else:
			run_path = "%s/%s/Run%s" %(self.plugin_settings['upload_path'], self.plugin_settings['sample_name'], self.plugin_settings['run_num'])
			run_name = "Run" + self.plugin_settings['run_num']
	
		# set the sample_json path
		sample_json = "%s/%s/%s.json"%(self.plugin_settings['upload_path'], self.plugin_settings['sample_name'], self.plugin_settings['sample_name'])
	
		# first write the new run's json file
		run_path, run_json, run_plugin_json_path = self.write_run_json(self.plugin_settings['run_num'], run_name, self.plugin_settings['run_type'], self.plugin_settings['sample_name'], run_path, sample_json)
		# write the sample's json file
		# technically this only needs to be done once for each sample, but we can just make it every run and then only push it once.
		self.write_sample_json(self.plugin_settings['sample_name'], sample_json, run_json)

		return run_path, run_plugin_json_path


	# @returns the path to the run's json on the server
	def write_run_json(self, runNum, runName, runType, sample, run_path, sample_json):
		json_name = "%s_%s.json"%(sample,runName)
		run_json = "%s/%s"%(run_path,json_name)
		orig_path = '/'.join(self.options.bam.split('/')[:-1])
		bam = self.options.bam.split('/')[-1]
		proton = ''
		# get the run_id_num out of the orig_path by parsing the name. Has to account for the two cases where there could either be a '-' or '_' after the runID
		# for example: Auto_user_PLU-2_2 vs Auto_user_PLU-3-Ion
		try:
			# this is the best solution I came up with for this. It's not foolproof... but it should work in most cases.
			run_id_num = orig_path.split("Auto_user_")[1].split("-")[1].split("-")[0].split("_")[0]
			proton = orig_path.split("Auto_user_")[1].split("-")[0]
			run_id = "%s-%s"%(proton, run_id_num)
		except IndexError:
			# use the full path instead
			pass
		#There are runs (such as a reanalysis) which don't have the common 'PLU-231' format (i.e. Reanalysis_PNET_BC373_Run4). 
		# We don't use the runID for anything besides to fill in the QC table. I could just leave the entire name in these cases.
		if len(proton) != 3: 
			run_id = orig_path.split("/")[-1]
			# set the name of the proton as the TSP_PGM_NAME
			proton = os.environ['TSP_PGM_NAME'][0:3].upper()
	
		# Write the run's json file which will be used mainly to hold metrics.
		jsonData = {
			"analysis": {
				"files": [bam]
			},
			"json_file": run_json, 
			"json_type": "run",
			"orig_path": orig_path,
			"run_folder": run_path, 
			"run_id": run_id,
			"run_name": runName, 
			"run_num": runNum, 
			"run_type": runType, 
			"pass_fail_status": "pending", 
			"project": self.ex_json['project'], 
			"proton": proton,
			"sample": sample, 
			"sample_folder": "%s/%s"%(self.plugin_settings['upload_path'], sample),
			"sample_json": sample_json,
			"server_ip": self.options.local_ip,
			"torrent_suite_link": "http://%s/report/%s"%(self.options.local_ip, self.plugin_settings['browser_runID']),
			"orig_filepath_plugin_dir": plugin_settings['tsp_filepath_plugin_dir'],
			"ts_version": self.options.ts_version
		}

		# If this is a barcoded run, save the barcode
		if self.options.barcode:
			jsonData['barcode'] = self.options.barcode
	
		# apparently this script does not have permission to the plugin. Write the JSON files to plugin files of the run.
		## make sure hte JsonFiles directory exists
		#if not os.path.isdir("%s/scripts/Json_Files"%self.output_dir):
		#	os.mkdir("%s/scripts/Json_Files"%self.output_dir)

		run_plugin_json_path = "%s/%s"%(self.output_dir, json_name)
		# dump the json file
		with open(run_plugin_json_path, 'w') as out:
			json.dump(jsonData, out, sort_keys=True, indent = 2)
	
		return run_path, run_json, run_plugin_json_path


	# @param sample the name of the current sample
	# @param run_path the path of the current run
	def write_sample_json(self, sample, sample_json, run_json):
		sample_path = "%s/%s"%(self.plugin_settings['upload_path'], sample)

		# edit the sample's json file with this sample's info. The other metrics in the sample JSON file should already be set. 
		self.ex_json["json_file"] = sample_json 
		self.ex_json["results_qc_json"] = "%s/QC/results_QC.json"%sample_path 
		self.ex_json["qc_folder"] = "%s/QC"%sample_path 
		self.ex_json["output_folder"] = sample_path 
		# set the list of runs to this current run. 
		#If the sample json has already been written, this sample json file will not be used, and the current run will be added to the list of runs in the sample json
		self.ex_json["runs"] = [run_json]
		self.ex_json["sample_name"] = sample
		self.ex_json["sample_folder"] = sample_path
	
		# check if this is an ffpe sample
		if 'ffpe' in self.plugin_settings:
			if 'analysis' not in self.ex_json:
				self.ex_json['analysis'] = {}
			if 'settings' not in self.ex_json['analysis']:
				self.ex_json['analysis']['settings'] = {}
			self.ex_json['analysis']['settings']["ffpe"] = True
	
		# dump the json file
		with open("%s/%s.json"%(self.output_dir, sample), 'w') as out:
			json.dump(self.ex_json, out, sort_keys=True, indent = 2)


if __name__ == '__main__':

	# set up the option parser
	parser = OptionParser()
	
	# add the options to parse
	parser.add_option('-l', '--local_ip', dest='local_ip', help='Required. the ip address of this machine')
	parser.add_option('-b', '--bam', dest='bam', help='Required. The /path/to/bam file that will be pushed')
	parser.add_option('-t', '--ts_version', dest='ts_version', help='Required. The version of TS used to make the bam file.')
	parser.add_option('-B', '--barcode', dest='barcode', help='The name of the barcode (if this is a barcoded run)')
#	parser.add_option('-d', '--destination', dest='destination', help='Required. The destination path where the sample will be copied to.')
#	parser.add_option('-i', '--input', dest='input', help='Required. The input csv file containing the metadata about each sample to be pushed.')
#	parser.add_option('-j', '--ex_json', dest='ex_json', help='Required. The example json file containing the settings necessary for this project. Should be different for every project. For help of how to create the example json file, see the protocls')
#	parser.add_option('-p', '--proton', dest='proton', help='Required. The name of the proton or pgm from which you are pushing the files. Options: "PLU", "MER", "NEP, "ROT"')
#	parser.add_option('-H', '--header', dest='header', action="store_true", help='use this option if the CSV has a header line.')
#	parser.add_option('-o', '--output_csv', dest='output_csv', default='Push_Results.csv', help='The results of copying will be placed in this file. Default: [%default]')
#	parser.add_option('-l', '--log', dest='log', default="Push.log", help='Default: [%default]')
#	parser.add_option('-R', '--run_anyway', dest='run_anyway', help='if the server is not in the list of "accepted servers", push the data anyway')
#	#parser.add_option('-t', '--tumor_normal', dest='tn', action="store_true", help='If the project for which samples are being copied is a Tumor/Normal comparison project, use this option. \
#	#		Otherwise file structure will be treated as a germline only study.')
#
#
	(options, args) = parser.parse_args()

	# options were already set by the plugin. Load the settings
	if 'RESULTS_DIR' not in os.environ:
		print "Error: This script is to be called from driver.pl"
		sys.exit(1)
	plugin_settings = json.load(open(os.environ['TSP_FILEPATH_PLUGIN_DIR'] + '/startplugin.json'))
	plugin_settings['pluginconfig']['browser_runID'] = plugin_settings['runinfo']['pk']
	plugin_settings = plugin_settings['pluginconfig']
	# set this path so that the script can copy back the excel file after it finishes
	plugin_settings['tsp_filepath_plugin_dir'] = os.environ['TSP_FILEPATH_PLUGIN_DIR']

	setup = Setup_Json(plugin_settings, options)
	run_path, run_plugin_json_path = setup.setup_json()
	# only print the run_path and run_json so that driver.pl can use these paths
	print '%s,%s'%(run_path, run_plugin_json_path)
	#print "Finished setting up the json files for the run to be pushed"

#	# options were already set by the plugin. Load the settings
#	plugin_settings = json.load(open(os.environ['RESULTS_DIR'] + '/startplugin.json'))
#    #check to make sure we don't have any errors
#	errors = ""
#	if plugin_settings['pluginconfig']['ip'] == "":
#		errors += "No server name / IP provided\n"
#	
#	if plugin_settings['pluginconfig']['user_name'] == "":
#		errors += "No user name provided\n"
#	
#	if plugin_settings['pluginconfig']['user_password'] == "":
#		errors += "No user password provided\n"
#	
#	if plugin_settings['pluginconfig']['sample'] == "":
#		errors += "No sample provided\n"
#	
#	if plugin_settings['pluginconfig']['run'] == "":
#		errors += "No run provided\n"
#
#	if plugin_settings['pluginconfig']['project'] == "":
#		errors += "No project provided\n"
#	# If the project selected does not have a JSON file, then we can't push the data for it.
#	elif not os.path.isfile("%s.json"%plugin_settings['pluginconfig']['project']):
#		errors += "%s is not a valid project. Has no JSON settings file.\n"%plugin_settings['pluginconfig']['project']
#
#	if errors == "":
#		# Arguments incorrect
#		sys.exit(8)
#	
#	# check to make sure the inputs are valid
#	if not options.input or not options.ex_json or not options.destination or not options.proton:
#		print "USAGE-ERROR!: Options: --input,--example_json, --destination, and --proton are required"
#		parser.print_help()
#		sys.exit(8)
#	if not os.path.isfile(options.input) or not os.path.isfile(options.ex_json):
#		print "USAGE-ERROR!: %s or %s not found"%(options.input, options.ex_json)
#		parser.print_help()
#		sys.exit(4)
#
#	# check if the proton name is valid
#	#valid_protons = ['PLU', 'MER', 'NEP', 'ROT']
#	#if options.proton not in valid_protons:
#	#	print "--USAGE-ERROR-- %s not a valid proton"%options.proton
#	#	parser.print_help()
#	#	sys.exit(1)
#
#	# check if the IP address is valid. More IP addresses can be added overtime
#	# ips: pluto, mercury, triton, triton's external, lam, bonnie's pgm
#	valid_ips = ["ionadmin@192.168.200.42", "ionadmin@192.168.200.41", "ionadmin@192.168.200.131", "ionadmin@12.32.211.40", "ionadmin@192.168.200.214", "ionadmin@130.132.19.237"] 
#	if options.server not in valid_ips and not options.run_anyway:
#		print "--USAGE-ERROR-- %s not a valid server or ipaddress to push to. If it is, sorry for being overly stringent. Use the -R option to run anyway. if the log file shows that nothing is being pushed, check your connection with the server."%options.server
#		parser.print_help()
#		sys.exit(1)
#
#	pusher = Setup_Json(options)
#	with open(options.input, 'r') as input_file:
#		header_line=''	
#		if options.header:
#			header_line = input_file.readline().strip()
#		pusher.find_header_indexes(header_line)
#		# push each run in the file
#		for run in input_file:
#			pusher.push_run(run)
#			# stagger the push submits so they don't overwrite the sample's json file.
#			time.sleep(10)
	
#		# submit the push_Data script to SGE to copy the sample.
#		push_command = "qsub -N Push_%s_%s push_Data.sh "%(run[self.headers['sample']], run_name) + \
#			 "--user_server %s "%self.options.server + \
#			 "--dest_path %s "%run_path + \
#			 "--run_id  %s "%run_id + \
#			 "--run_json  %s "%run_json + \
#			 "--sample_json  %s "%sample_json + \
#			 "--proton_name %s "%proton + \
#			 "--output_csv %s "%self.options.output_csv + \
#			 "--backup_path %s "%self.backup_path 
#		if re.search("Ion", run[self.headers['barcode']]):
#			 push_command += " --barcode %s "%run[self.headers['barcode']]
#		status = self.runCommandLine(push_command)
