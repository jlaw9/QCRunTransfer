#! /usr/bin/env python

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

class Push_Data:
	def __init__(self, options):
		self.options = options
		try:
			self.ex_json = json.load(open(options.ex_json))
		except ValueError:
			print "ERROR: %s is not formatted correctly"%self.options.ex_json
			sys.exit(1)
		#self.ex_json = {'sample_type': 'germline'}
		#self.ex_json = {'sample_type': 'tumor_normal', 'project': 'testing'}

		if self.options.proton == "PLU":
			self.backup_path = PLUTO_BACKUP_PATH
			self.ip = "192.168.200.42"
		elif self.options.proton == "MER" or self.options.proton == "NEP":
			self.backup_path = MERCURY_BACKUP_PATH
			self.ip = "192.168.200.41"
		elif self.options.proton == "ROT":
			self.backup_path = PGM_BACKUP_PATH
			self.ip = "130.132.19.237"
	
	# this function is meant to ensure the right columns are used to gather the run metadata when pushing a run.
	# @param header_line the header line of the CSV to push. not yet implemented
	def find_header_indexes(self, header_line):
		if self.ex_json['sample_type'] == 'tumor_normal':
			self.headers = {'sample': 0, 'tumor_normal': 1, 'run_id': 2, 'run_num': 3, 'barcode': 4, 'proton': 5}
		else:
			self.headers = {'sample': 0, 'run_id': 1, 'run_num': 2, 'barcode': 3, 'proton': 4}
		# store the item at self.headers["proton"] as either PLU, NEP, MER, or ROT

	# @param run the line of the CSV 
	def push_run(self, run):
		#print "pushing run: ", run.strip()
		run = run.strip().split(",")
		#print run
		#print self.headers['run_num']
		# first get the proton and run_num
		if len(run[self.headers["run_id"]].split('-')) > 1:
			proton = run[self.headers["run_id"]].split('-')[0]
			run_id = run[self.headers["run_id"]].split('-')[1]
		else:
			proton = run[self.headers["proton"]]
			run_id = run[self.headers["run_id"]]
		run_num = run[self.headers["run_num"]]

		run_path = ''
		if self.ex_json['sample_type'] == 'tumor_normal':
			if run[self.headers['tumor_normal']] == "N":
				run_path = "%s/%s/Normal/N-%s" %(self.options.destination, run[self.headers["sample"]], run_num)
				run_name = "N-" + run_num
				run_type = "normal"
			elif run[self.headers['tumor_normal']] == "T":
				run_path = "%s/%s/Tumor/T-%s" %(self.options.destination, run[self.headers["sample"]], run_num)
				run_name = "T-" + run_num
				run_type = "tumor"
		else:
			run_path = "%s/%s/Run%s"%(self.options.destination, run[self.headers["sample"]], run_num)
			run_name = "Run" + run_num
			run_type = "germline"
		# check if the proton names or pgm names match. They should be None if this is not a proton
		if self.options.proton == proton:
			# first write the new run's json file
			run_json = self.write_run_json(run_num, run_name, run_type, run[self.headers['sample']], run_path)
			# write the sample's json file
			# technically this only needs to be done once, but we can just push it every time.
			sample_json = self.write_sample_json(run[self.headers['sample']], "%s/%s_%s.json"%(run_path, run[self.headers['sample']], run_name))
		
			# submit the push_Data script to SGE to copy the sample.
			push_command = "qsub -N Push_%s_%s push_Data.sh "%(run[self.headers['sample']], run_name) + \
				 "--user_server %s "%self.options.server + \
				 "--dest_path %s "%run_path + \
				 "--run_id  %s "%run_id + \
				 "--run_json  %s "%run_json + \
				 "--sample_json  %s "%sample_json + \
				 "--proton_name %s "%proton + \
				 "--output_csv %s "%self.options.output_csv + \
				 "--backup_path %s "%self.backup_path 
			if re.search("Ion", run[self.headers['barcode']]):
				 push_command += " --barcode %s "%run[self.headers['barcode']]
			status = self.runCommandLine(push_command)

	def write_run_json(self, runNum, runName, runType, sample, run_path):
		json_name = "%s_%s.json"%(sample,runName)
		# Write the run's json file which will be used mainly to hold metrics.
		jsonData = {
			"json_file": "%s/%s"%(run_path,json_name), 
			"json_type": "run",
			"run_folder": run_path, 
			"run_name": runName, 
			"run_num": runNum, 
			"run_type": runType, 
			"pass_fail_status": "pass", 
			"project": self.ex_json['project'], 
			"proton": self.options.proton,
			"sample": sample, 
			"sample_folder": "%s/%s"%(self.options.destination, sample),
			"sample_json": "%s/%s/%s.json"%(self.options.destination, sample, sample),
		}

		# make sure hte JsonFiles directory exists
		if not os.path.isdir("Json_Files"):
			os.mkdir("Json_Files")

		# dump the json file
		with open("Json_Files/"+json_name, 'w') as out:
			json.dump(jsonData, out, sort_keys=True, indent = 2)

		# the path of the run's json file to push
		return "Json_Files/"+json_name


	# @param sample the name of the current sample
	# @param run_path the path of the current run
	def write_sample_json(self, sample, run_json):
		sample_path = "%s/%s"%(self.options.destination, sample)

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

	def runCommandLine(self, systemCall):
		#run the call and return the status
		print 'Starting %s' % (systemCall)
		status = os.system(systemCall)
		return(status)


if __name__ == '__main__':

	# set up the option parser
	parser = OptionParser()
	
	# add the options to parse
	parser.add_option('-s', '--server', dest='server', help='Required. The server to push data to. <ionadmin@ipaddress>')
	parser.add_option('-d', '--destination', dest='destination', help='Required. The destination path where the sample will be copied to.')
	parser.add_option('-i', '--input', dest='input', help='Required. The input csv file containing the metadata about each sample to be pushed.')
	parser.add_option('-j', '--ex_json', dest='ex_json', help='Required. The example json file containing the settings necessary for this project. Should be different for every project. For help of how to create the example json file, see the protocls')
	parser.add_option('-p', '--proton', dest='proton', help='Required. The name of the proton or pgm from which you are pushing the files. Options: "PLU", "MER", "NEP, "ROT"')
	parser.add_option('-H', '--header', dest='header', action="store_true", help='use this option if the CSV has a header line.')
	parser.add_option('-o', '--output_csv', dest='output_csv', default='Push_Results.csv', help='The results of copying will be placed in this file. Default: [%default]')
	parser.add_option('-l', '--log', dest='log', default="Push.log", help='Default: [%default]')
	parser.add_option('-R', '--run_anyway', dest='run_anyway', help='if the server is not in the list of "accepted servers", push the data anyway')
	#parser.add_option('-t', '--tumor_normal', dest='tn', action="store_true", help='If the project for which samples are being copied is a Tumor/Normal comparison project, use this option. \
	#		Otherwise file structure will be treated as a germline only study.')


	(options, args) = parser.parse_args()

	# check to make sure the inputs are valid
	if not options.input or not options.ex_json or not options.destination or not options.proton:
		print "USAGE-ERROR!: Options: --input,--example_json, --destination, and --proton are required"
		parser.print_help()
		sys.exit(8)
	if not os.path.isfile(options.input) or not os.path.isfile(options.ex_json):
		print "USAGE-ERROR!: %s or %s not found"%(options.input, options.ex_json)
		parser.print_help()
		sys.exit(4)

	# check if the proton name is valid
	valid_protons = ['PLU', 'MER', 'NEP', 'ROT']
	if options.proton not in valid_protons:
		print "--USAGE-ERROR-- %s not a valid proton"%options.proton
		parser.print_help()
		sys.exit(1)

	# check if the IP address is valid. More IP addresses can be added overtime
	# ips: pluto, mercury, triton, triton's external, lam, bonnie's pgm
	valid_ips = ["ionadmin@192.168.200.42", "ionadmin@192.168.200.41", "ionadmin@192.168.200.131", "ionadmin@12.32.211.40", "ionadmin@192.168.200.214", "ionadmin@130.132.19.237"] 
	if options.server not in valid_ips and not options.run_anyway:
		print "--USAGE-ERROR-- %s not a valid server or ipaddress to push to. If it is, sorry for being overly stringent. Use the -R option to run anyway. if the log file shows that nothing is being pushed, check your connection with the server."%options.server
		parser.print_help()
		sys.exit(1)

	pusher = Push_Data(options)
	with open(options.input, 'r') as input_file:
		header_line=''	
		if options.header:
			header_line = input_file.readline().strip()
		pusher.find_header_indexes(header_line)
		# push each run in the file
		for run in input_file:
			pusher.push_run(run)
			# stagger the push submits so they don't overwrite the sample's json file.
			time.sleep(10)

	print "Finished submitting runs to be pushed"
