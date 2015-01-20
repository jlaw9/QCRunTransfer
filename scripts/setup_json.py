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
		self.options = options
		self.ex_json = json.load(open('%s.json'%plugin_settings['sample_name']))
		self.setup_json()

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
	
		sample_json = "%s/%s_%s.json"%(run_path, self.plugin_settings['sample_name'])
	
		# first write the new run's json file
		run_json = self.write_run_json(self.plugin_settings['run_num'], run_name, self.plugin_settings['run_type'], self.plugin_settings['sample_name'], run_path, sample_json)
		# write the sample's json file
		# technically this only needs to be done once for each sample, but we can just make it every run and then only push it once.
		sample_json = self.write_sample_json(self.plugin_settings['sample_name'], sample_json, run_json)


	# @returns the path to the run's json on the server
	def write_run_json(self, runNum, runName, runType, sample, run_path, sample_json):
		json_name = "%s_%s.json"%(sample,runName)
		run_json = "%s/%s"%(run_path,json_name)
		orig_path = self.options.bam.split('/')[:-1]
		bam = self.options.bam.split('/')[-1]
		# get the run_id_num out of the orig_path by parsing the name. Has to account for the two cases where there could either be a '-' or '_' after the runID
		# for example: Auto_user_PLU-2_2 vs Auto_user_PLU-3-Ion
		run_id_num = orig_path.split("Auto_user_")[1].split("-")[1].split("-")[0].split("_")[0]
		proton = orig_path.split("Auto_user_")[1].split("-")[0]
	
		# Write the run's json file which will be used mainly to hold metrics.
		jsonData = {
			"analysis": {
				"files": [bam]
			},
			"json_file": run_json, 
			"json_type": "run",
			"orig_path": orig_path,
			"run_folder": run_path, 
			"run_id": "%s-%s"%(proton, run_id_num),
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
			"ts_version": self.options.ts_version
		}
	
		# make sure hte JsonFiles directory exists
		if not os.path.isdir("Json_Files"):
			os.mkdir("Json_Files")

		# dump the json file
		with open("Json_Files/"+json_name, 'w') as out:
			json.dump(jsonData, out, sort_keys=True, indent = 2)
	
		return run_json


	# @param sample the name of the current sample
	# @param run_path the path of the current run
	def write_sample_json(self, sample, sample_json, run_json):
		sample_path = "%s/%s"%(self.plugin_settings['upload_path'], sample)

		# edit the sample's json file with this sample's info. The other metrics in the sample JSON file should already be set. 
		self.ex_json["json_file"] = "%s/%s.json"%(sample_path, sample) 
		self.ex_json["output_folder"] = "%s/QC"%sample_path 
		# dont set the runs here as things can get overwritten. only set the runs once the bam file has been pushed.
		#self.ex_json["runs"] = [run_json]
		self.ex_json["sample_name"] = sample
		self.ex_json["sample_folder"] = sample_path

		# dump the json file
		with open("Json_Files/%s.json"%sample, 'w') as out:
			json.dump(self.ex_json, out, sort_keys=True, indent = 2)

		# this path will be used to check if the sample's json exists on the server already
		return "%s/%s.json"%(sample_path, sample)


if __name__ == '__main__':

	# set up the option parser
	parser = OptionParser()
	
	# add the options to parse
	parser.add_option('-l', '--local_ip', dest='local_ip', help='Required. the ip address of this machine')
	parser.add_option('-b', '--bam', dest='bam', help='Required. The /path/to/bam file that will be pushed')
	parser.add_option('-t', '--ts_version', dest='ts_version', help='Required. The version of TS used to make the bam file.')
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
	plugin_settings = json.load(open(os.environ['RESULTS_DIR'] + '/startplugin.json'))
	plugin_settings['pluginconfig']['browser_runID'] = plugin_settings['runinfo']['pk']
	plugin_settings = plugin_settings['pluginconfig']
	plugin_settings['plugin_dir'] = os.environ['RESULTS_DIR']

	Setup_Json(plugin_settings, options)

	print "Finished setting up the json files for the run to be pushed"

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
