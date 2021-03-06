#! /usr/bin/env python

import sys
import os
import re
import json
from optparse import OptionParser
import fnmatch

# @param systemCall the command to run
def runCommandLine(systemCall):
	#run the call and return the status
	#print 'Starting %s' % (systemCall)
	status = os.system(systemCall)
	return(status)

# @param sample_dir the dir in which to find the json files used to find the vcf files to pool the variants
def getJsonFiles(json_pattern, sample_dir, key_values=None):
	json_files = [] # list of all of the json files found
	# first, find all of the sample's json files
	if options.debug:
		print "using %s to filter"%key_values
	for root, dirnames, filenames in os.walk(sample_dir):
		#print root, filenames
		for filename in fnmatch.filter(filenames, str(json_pattern)):
			json_file = os.path.join(root, filename)
			if options.debug:
				print "looking at "+json_file
			if key_values:
				for key_value in key_values:
					if options.debug:
						print 'filtering with ', key_value
					key_value = key_value.split(":")
					json_data = json.load(open(json_file))
					if key_value[0] in json_data and json_data[key_value[0]] == key_value[1]:
						if options.debug:
							print "found "+json_file
						json_files.append(json_file)
			else:
				if options.debug:
					print "found "+json_file
				json_files.append(json_file)
	return json_files

# @param json_file the json file to update
# @metrics a list of metrics to update or add to the json file
def update_metrics(json_file, metrics, ex_json):
	# load the given json file
	jsonData = json.load(open(json_file))
	if metrics:
		for metric in metrics:
			print "Adding/updating " + metric + " to the json file %s."%json_file
			# Union the two dictionaries together. If a field is found in both dictionaries, then whatever's in extraJson will overwrite what is in jsonData.
			# Example: dict1 = { "a":1, "b": 2}		dict2 = { "b":3, "c": 4}  dict(dict1.items() + dict2.items()) 	{'a': 1, 'c': 4, 'b': 3}
			try:
				newData = json.loads(metric)
				jsonData = dict(jsonData.items() + newData.items())
			except ValueError:
				print "Unable to load the string %s into JSON"%metric

	elif ex_json:
		exJsonData = json.load(open(ex_json))
		jsonData['analysis']['settings'] = exJsonData['analysis']['settings']
		#jsonData = dict(exJsonData.items() + jsonData.items())

	# dump the json file
	with open(json_file, 'w') as out:
		json.dump(jsonData, out, sort_keys=True, indent = 2)

if __name__ == "__main__":
	# Set up the parser
	parser = OptionParser()

	parser.add_option('-j', '--json', dest='json', help="The name of the .json file to add info to.")
	parser.add_option('-s', '--server', dest='server', help="server where the sample's json file is located")
	parser.add_option('-u', '--user_password', dest='user_password', help="The password to the server")
	parser.add_option('-k', '--json_key_value', dest='json_key_value', action="append", help="Any number of key:value pairs can be used to filter json files found")
	parser.add_option('-m', '--metric', dest='metrics', action="append", help="info to add to a json file. string is loaded into json so must use JSON format. (See push_Data.sh for an example)")
	parser.add_option('-e', '--ex_json', dest='ex_json', help="The json file(s) and the exapmle_json file will be intersected")
	parser.add_option('-a', '--add_run_to_sample', dest='add_run', action="store_true", help="the run's json file has the path to it's sample's json file. It will copy the sample's json file from the other server and add the run to it.")
	parser.add_option('-p', '--push_sample_json', dest='push_sample_json', action="store_true", help="push the sample's json file to the server because it hasn't been copied yet.")
	parser.add_option('-S', '--sample_dirs', dest='sample_dirs', action="append", help="will recursively look in the sample directories specified, find all of the json files matching what is passed in by the --json option and update them")
	parser.add_option('-d', '--debug', dest='debug', action="store_true", help="add more print statements")

	(options, args) = parser.parse_args()

	# check to make sure the inputs are valid
	if not options.json:
		print "--USAGE-ERROR-- --json is required"
		parser.print_help()
		sys.exit(1)
	if not options.sample_dirs and not os.path.isfile(options.json): 
		print "--USAGE-ERROR-- %s not found"%options.json
		parser.print_help()
		sys.exit(1)

	if options.push_sample_json:
		# load the given json file
		jsonData = json.load(open(options.json))
		# get the name of the sample's json file which should be the last item in the list.
		sample_json_name = jsonData["sample_json"].split("/")[-1]
		
		# copy the sample's json file here and check if the copy was successful
		copy_command = "scp Json_Files/%s %s:%s "%(sample_json_name, options.server, jsonData["sample_json"])
		if runCommandLine(copy_command) == 0:
			print "%s file copied successfully"%sample_json_name
		else:
			print "ERROR: Unable to copy the sample's %s json file"%sample_json_name
			sys.exit(1)

	elif options.add_run:
		# load the given json file
		runJsonData = json.load(open(options.json))
		# get the name of the sample's json file which should be the last item in the list.
		sample_json_name = runJsonData["sample_json"].split("/")[-1]

		results_dir =  os.environ['RESULTS_DIR']
		# copy the sample's json file here and check if the copy was successful
		copy_command = "pscp -pw %s %s:%s %s/"%(options.user_password, options.server, runJsonData["sample_json"], results_dir)
		print "	Running pscp -pw xxx %s:%s %s/"%(options.server, runJsonData["sample_json"], results_dir)
		if runCommandLine(copy_command) == 0:
			# load the sample json that we copied to the results dir.
			sample_json_plugin_path = "%s/%s"%(results_dir,sample_json_name)
			sampleJsonData = json.load(open(sample_json_plugin_path))

			# append the current run to this sample's list of runs.
			sampleJsonData['runs'].append(runJsonData['json_file'])
			# make the list of runs into a set and then list again to delete any run duplicates
			sampleJsonData['runs'] = list(set(sampleJsonData['runs']))
			
			# set the status to 'pending' so that the runs will be QCd together.
			sampleJsonData['status'] = 'pending'
			# set the 'sample_status' to 'pushed' so that if the sample has already been merged and there is a new run, then the sample will re-QC and merge everything.
			sampleJsonData['sample_status'] = 'pushed'
			# set the emails
			for email in os.environ['PLUGINCONFIG__EMAIL'].split(','):
				email = email.strip()
				if re.search("@", email) and email not in sampleJsonData['emails']:
					sampleJsonData['emails'].append(email)
			if sampleJsonData['project'] == 'PNET' and 'jkron@childhooddiseases.org' not in sampleJsonData['emails']:
				sampleJsonData['emails'].append('jkron@childhooddiseases.org')
			
			# dump the json file
			with open(sample_json_plugin_path, 'w') as out:
				json.dump(sampleJsonData, out, sort_keys=True, indent = 2)

			# copy the edited sample's json file back to the server
			copy_command = "pscp -pw %s %s %s:%s "%(options.user_password, sample_json_plugin_path, options.server, runJsonData["sample_json"])
			print "	Running pscp -pw xxx %s %s:%s "%(sample_json_plugin_path, options.server, runJsonData["sample_json"])
			if runCommandLine(copy_command)	== 0:
				print "Added a run to %s, and pushed successfully."%sample_json_name
		else:
			print "ERROR: Unable to copy the sample's json file %s!"%runJsonData["sample_json"]
			sys.exit(1)
		

	# if the metrics option is specified, udate the metrics for the json files specified
	elif options.metrics or options.ex_json:
		# if the user specified directories to look in, then find all of the json files in those directories
		if options.sample_dirs:
			for sample_dir in options.sample_dirs:
				# check if there is a key:value to use as a filter
				if options.json_key_value:
					json_files = getJsonFiles(options.json, sample_dir, options.json_key_value)
				else:
					json_files = getJsonFiles(options.json, sample_dir)
				for json_file in json_files:
					update_metrics(json_file, options.metrics, options.ex_json)
		# otherwise just update the single json file
		else:
			update_metrics(options.json, options.metrics, options.ex_json)

