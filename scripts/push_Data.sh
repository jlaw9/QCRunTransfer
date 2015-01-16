#! /bin/bash

#Qsub arguments:

#$ -S /bin/bash
#$ -cwd
#$ -N Push_Data
#$ -o push_results.log
#$ -e push_results.log
#$ -q all.q
#$ -V


#This script is a tool that copies BAM, amplicon.cov.xls and the TSVC_variants.vcf files of a run specified by the user.
# All of the std_out is written to a csv by start_Push.sh. all std_err is written to the screen.

#-----------------------------  FUNCTIONS DEFINED HERE -----------------------------------
#-----------------------------------------------------------------------------------------
function usage {
cat << EOF
USAGE: bash push_Data.sh 
	-h | --help
	-u | --user_server <ionadmin@ip_address>
	-p | --dest_path <path/to/project>	 (Destination folder or path on the other server of the files to push.)
	-i | --run_id <run_id> 			(The run's id. Will be used to find the file)
	-r | --run_json <Json_Files/Run1.json> 			(The run's json file to push)
	-s | --sample_json </projects/Eintsein/E001/E001.json> 			(The sample's json file on the server. if it already exists, a run will be added to it. If not, it will be pushed)
	-P | --proton_name <proton_name> 	(i.e. PLU or MER or NEP or ROT. Will be used to find the location of the bam file and such)
	-bp | --backup_path <backup_path> 	(for pluto: /mnt/Charon/archivedReports 	for mercury: /mnt/Triton/archivedReports)
	-b | --barcode <barcode>		(if this run is barcoded)
	-o | --output_csv <push_results.csv>	(append the results of this samples copy to the file)
	-l | --log_file <push.log>		(Default: push.log) 
EOF
exit 8
}

# creates the output path we are pushing the files to
function create_ssh_Dir {
	ssh ${USER_SERVER} mkdir -p $1 </dev/null
}

#Find the version TS was run to generate the original BAM file.
# $1: The Run_Path/version.txt
function check_TS_Version {
	if [ "`find $1 -maxdepth 0 2>/dev/null`" ]; then
		TS_version=`grep -oE "version.*" $1 -m 1 2>/dev/null | grep -oe "[0-9]\.[0-9]" | perl -ne "chomp and print"`
		if [ "$TS_version" == "" ]; then
			TS_version=`grep -oE "Torrent_Suite=.*" $1 -m 1 2>/dev/null | grep -oe "[0-9]\.[0-9]" | perl -ne "chomp and print"`
		else
			TS_version="not_found"
		fi
	fi
	OUTPUT="${OUTPUT}${TS_version},"	
}
#find the version and parameters TVC was run on the original BAM file.
# $1: The Run_Path/plugin_out/variantCaller_out/drmaa_stdout.txt
function check_TVC_Version {
	if [ "`find $1 -maxdepth 0 2>/dev/null`" ]; then
		TVC_version=`grep -oE "version.*" $1 -m 1 2>/dev/null | \
			grep -oe "[0-9]\.[0-9]" | perl -ne "chomp and print"`
		TVC_parameters=`grep -oiE "results[/_.a-z]+\.json" $1 2>/dev/null | \
			grep -oiE "[_.a-z]+\.json" | perl -ne "chomp and print"`
		OUTPUT="${OUTPUT}${TVC_version}, ${TVC_parameters},"
	#else
#		printf ",,"
	#	printf ""
	fi
}

#Takes as input the relative path/to/file.
#Writes to output the result of finding and pushing the file
function find_and_Push_File {
	# this variable will only be set to True if the file was actually copied.
	COPIED="False"
	if [ "`find $1 -maxdepth 0 2>/dev/null`" ]; then
		FILE_NAME=`find $1 -type f -printf "%f\n"`
		if ssh ${USER_SERVER} stat ${DEST_PATH}/${FILE_NAME} \> /dev/null 2\>\&1; then
			OUTPUT="${OUTPUT}File already copied,"
#			echo "$1 already copied" >> $LOG
		else
			echo "${DEST_PATH}/${FILE_NAME} starting to copy at `date`" >> $LOG
			COUNTER=0
			until [ "$COUNTER" == "10" ]; do
				rsync -avz --progress ${1} ${USER_SERVER}:${DEST_PATH}/${FILE_NAME} > /dev/null 2>&1 </dev/null &
				rsyncPID=$!
				# sleepAndMaybeKill.sh is a bash command that sleeps for the given amount of time, then kills the ProcessID passed to it.
				seconds_to_wait=7200
				bash sleepAndMaybeKill.sh $seconds_to_wait $pushPID >/dev/null 2>&1 &  
				SLEEP_AND_MAYBE_KILL_PID=$!   
				wait $rsyncPID > /dev/null 2>&1
				if [ $? -eq 0 ]; then
					# If push_Data.sh succeeded, then stop the sleep and maybe kill script. 
					kill $SLEEP_AND_MAYBE_KILL_PID >/dev/null 2>&1
					COUNTER=10
					COPIED="True"
					OUTPUT="${OUTPUT}Copied,"
					echo "${DEST_PATH}/${FILE_NAME} copied successfully `date`" >> $LOG
				else
					echo "Connection lost or rsync froze... will retry in 30 seconds." >> $LOG
					let "COUNTER+=1"
					sleep 30
					#printf "ERROR: $1 was not copied,"
				fi
			done
		fi
	else
		echo "--- File not found: $1 ---" >> $LOG 
	#	echo "${DEST_PATH}/${FILE_NAME}" >> files_not_found.txt
		OUTPUT="${OUTPUT}not found," 
	fi
}


# default failenames
LOG="push.log"
OUTPUT_CSV="push_results.csv"

#for arguments
if [ $# -lt 14 ]; then # Technically there should be at least 14 arguments
	usage
	echo "ERROR: Not enough arguments provided"
fi

RUNNING="Starting push with options: "
counter=0
while :
do
	let "counter+=1"
	# If not enough inputs were given for an option, the while loop will just keep going. Stop it and print this error if it loops more than 100 times
	if [ $counter -gt 100 ]; then
		echo "USAGE ERROR: not all required inputs were given for options."
		#echo "$RUNNING"
		exit 8
	fi
	case $1 in
		-h | --help)
			usage
			;;
		-u | --user_server)
			USER_SERVER=$2
			RUNNING="$RUNNING --user_server: $2 "
			shift 2
			;;
		-p | --dest_path)
			DEST_PATH=$2
			RUNNING="$RUNNING --dest_path: $2 "
			shift 2
			;;
		-i | --run_id)
			RUN_ID=$2
			RUNNING="$RUNNING --run_id: $2 "
			shift 2
			;;
		-r | --run_json)
			RUN_JSON=$2
			RUNNING="$RUNNING --run_json: $2 "
			shift 2
			;;
		-s | --sample_json)
			SAMPLE_JSON=$2
			RUNNING="$RUNNING --sample_json: $2 "
			shift 2
			;;
		-P | --proton_name)
			PROTON_NAME=$2
			RUNNING="$RUNNING --proton_name: $2 "
			shift 2
			;;
		-bp | --backup_path)
			BACKUP_PATH=$2
			RUNNING="$RUNNING --backup_path: $2 "
			shift 2
			;;
		-b | --barcode) 
			BARCODE=$2
			RUNNING="$RUNNING --barcode: $2 "
			shift 2
			;;
		-o | --output_csv) 
			OUTPUT_CSV=$2
			RUNNING="$RUNNING --output_csv: $2 "
			shift 2
			;;
		-l | --log_file) 
			LOG=$2
			RUNNING="$RUNNING --log_file: $2 "
			shift 2
			;;
		-*)
			printf >&2 'WARNING: Unknown option (ignored): %s\n' "$1"
			shift
			;;
		*)  # no more options. Stop while loop
			if [ "$1" != "" ]; then
				printf >&2 'WARNING: Unknown argument (ignored): %s\n' "$1"
				shift
			else
				break
			fi
			;;
	esac
done

# the options used
echo "$RUNNING at `date`" >> $LOG

#first, check the connection of the server.
# this check would be too slow.
#ssh -q ${1} exit
#if [ "$?" != "0" ]; then
#	echo "ERROR: Cannot connect to ${USER_SERVER}" 
#	exit 1
#fi

#-----------------------------  BEGIN PUSHING HERE -----------------------------------
#--------------------------------------------------------------------------------------

# The path to push the files to
# Example /rawdata/projects/Einstein/E0001/Run1
#OUT_PATH=${DEST_PATH}/${SAMPLE}/${RUN}
PROJECT_PATH="/results/analysis/output/Home"

#Find the path of the directory that has the specified ROT-ID
# there must be a - before and after the RUN_ID as to ensure the proper run ID is found. 
# For example. With proton MER and Run_ID 21, without the - before and after, it could match MER-210 or MER-218 or MER-213 and so on. With the dash, only MER-21- will be found.
if [ "`find ${PROJECT_PATH}/*${PROTON_NAME}-${RUN_ID}[-_]*/${BARCODE}*rawlib*.bam -type f | grep -v "_tn_" 2>/dev/null`" ]; then
	# head -n 1 shouldn't be necessary, but there are times where there are more than one dir with the same RUN_ID...
	RUN_PATH=`find ${PROJECT_PATH}/*${PROTON_NAME}-${RUN_ID}[-_]* -maxdepth 0 -type d | head -n 1`
#If the directory is not found, check in the backup.
elif [ "`find ${BACKUP_PATH}/*${PROTON_NAME}-${RUN_ID}[-_]*/${BARCODE}*rawlib*.bam -type f 2>/dev/null`" ]; then
	RUN_PATH=`find ${BACKUP_PATH}/*${PROTON_NAME}-${RUN_ID}[-_]* -maxdepth 0 -type d | head -n 1` 
else
	#That rotID was not found, so print error, and quit.
	echo "*${PROTON_NAME}-${RUN_ID}-*/${BARCODE}*rawlib.bam not found in ${PROJECT_PATH} or ${BACKUP_PATH}." >> $LOG
#	echo "${RUN_ID}/${RUN_NUM}_rawlib.bam" >> files_not_found.txt
	echo "*${PROTON_NAME}-${RUN_ID}-*/${BARCODE}*rawlib.bam not found in ${PROJECT_PATH} or ${BACKUP_PATH}." >> $OUTPUT_CSV
	exit 1
fi

#OUTPUT is the variable used to keep track of all of the files copied. Is printed out at the end
OUTPUT="$RUN_PATH,"

# Begin the file transfering!
# Finds the TS and TVC versions that were used to compare for QC later.
check_TS_Version "${RUN_PATH}/version.txt"
check_TVC_Version "${RUN_PATH}/plugin_out/variantCaller_out/drmaa_stdout.txt"
# Create the Sample and run path
create_ssh_Dir "${DEST_PATH}"

# checking to see if a file exists over ssh in python is not easy, so I did it here.
if ! ssh ${USER_SERVER} stat ${SAMPLE_JSON} \> /dev/null 2\>\&1; then
	# push the sample's JSON file. 
	python update_json_tool.py --json "$RUN_JSON" --push_sample_json --server "$USER_SERVER"
fi

#push the BAM file
# if the run is not barcoded, then barcode variable will be empty, so rawlib.bam will be pushed.
find_and_Push_File "${RUN_PATH}/${BARCODE}*rawlib.bam"
if [ "$COPIED" == "True" ]; then
	if [ "$TS_version" == "" ]; then
		TS_version="not_found"
	fi
	python update_json_tool.py --json $RUN_JSON \
		--metric '{"orig_path":"'"$RUN_PATH"'"}' \
		--metric '{"analysis":{"files":["'"$FILE_NAME"'"]}}' \
		--metric '{"ts_version":"'"$TS_version"'"}'
		#--metric '{"torrent_suite_link":"http://'"TS_version"'"}'
	# push the Json File
	find_and_Push_File "${RUN_JSON}"

	# sleep for a random number between 1-20 seconds hopefully so that sample's won't push their json file at the same time.
	sleep $[ ( $RANDOM % 20 )  + 1 ]s
	# if the sample's json file has already been written, add a run to it and recopy it over.
	# the run's json file has the path to it's sample's json file. It will copy the sample's json file from the other server and add the run to it.
	python update_json_tool.py --json "$RUN_JSON" --add_run_to_sample --server "$USER_SERVER"
fi

#push the BAM.bai file
find_and_Push_File "${RUN_PATH}/${BARCODE}*rawlib.bam.bai"
#push the amplicon coverage file

# starting with 4.2 coverage analysis plugin output folder gets a number assigned so taht users can run multiple times without over-writing the previous coverage analysis plugin result 
# example: coverageAnalysis_out.2369
# if there are multiple cov results, hopefully they were run with the same BED file! find will grep the first instance
covPath=`find ${RUN_PATH}/plugin_out/coverageAnalysis_out* -maxdepth 0 2>/dev/null | head -n 1`
find_and_Push_File "${covPath}/*.amplicon.cov.xls"

#push the VCF file
find_and_Push_File "${RUN_PATH}/plugin_out/variantCaller_out/TSVC_variants.vcf"

# push the reportPDF. It is located in the non-archived dir.
if [ "`find ${PROJECT_PATH}/*${PROTON_NAME}-${RUN_ID}[-_]*/report.pdf -type f 2>/dev/null`" ]; then
	pdf=`find ${PROJECT_PATH}/*${PROTON_NAME}-${RUN_ID}[-_]*/report.pdf -type f 2>/dev/null | head -n 1`
	find_and_Push_File "$pdf"
fi

# write the results of copying each file to the output CSV.
echo "$OUTPUT" >> $OUTPUT_CSV

#That should be about it for now.
