#!/usr/lib/perl -w
# copy some BAM FILES now

use strict;

#grab some key variables
my $PROTOCOL = $ENV{"PLUGINCONFIG__PROTOCOL"} || "FTP";
my $RESULTS_DIR = $ENV{"RUNINFO__REPORT_ROOT_DIR"};
my $RAW_DATA_DIR = $ENV{"RUNINFO__RAW_DATA_DIR"};
my $OUTPUT_DIR = $ENV{"TSP_FILEPATH_PLUGIN_DIR"};
my $PLUGINNAME = $ENV{"PLUGINNAME"};
my $PRIMARY_BAM = $ENV{"TSP_FILEPATH_BAM"};
my $PLUGIN_PATH = $ENV{"DIRNAME"};
my $SERVER_IP = $ENV{"PLUGINCONFIG__IP"};
my $USER_NAME = $ENV{"PLUGINCONFIG__USER_NAME"};
my $USER_PASSWORD = $ENV{"PLUGINCONFIG__USER_PASSWORD"};
my $UPLOAD_DIR = $ENV{"PLUGINCONFIG__UPLOAD_PATH"};
my $SAMPLE_NAME = $ENV{"PLUGINCONFIG__SAMPLE_NAME"};
my $RUN_NUM = $ENV{"PLUGINCONFIG__RUN_NUM"};
my $RUN_TYPE = $ENV{"PLUGINCONFIG__RUN_TYPE"};
my $PROJECT = $ENV{"PLUGINCONFIG__PROJECT"};
my $BARCODE = $ENV{"PLUGINCONFIG__BARCODE"};
my $FFPE = $ENV{"PLUGINCONFIG__FFPE"};
my $SAMPLE_DIR = $UPLOAD_DIR . "/" . $SAMPLE_NAME;
#my $RUN_DIR = $SAMPLE_NAME_DIR . "/" . $RUN

# make these global as they will be used throughout the entire script
my $ERRORS = ();
# we will store info on the FILES we are uploading so we can print status updates as needed
my $FILES = {};

#force scope
{
	# small test
	print "FFPE: $FFPE\n";
    #check to make sure we don't have any ERRORS

    if($SERVER_IP eq ""){
		push(@{$ERRORS}, "No server name / IP provided");
    }

    if($USER_NAME eq ""){
		push(@{$ERRORS}, "No user name provided");
    }

    if($USER_PASSWORD eq ""){
		push(@{$ERRORS}, "No user password provided");
    }

    if($SAMPLE_NAME eq ""){
		push(@{$ERRORS}, "No sample name provided");
    }

    if($RUN_NUM eq ""){
		push(@{$ERRORS}, "No run number provided");
    }

    #if we have ERRORS let's print the report
    if(defined($ERRORS) && scalar @{$ERRORS} != 0){
		&printReport($ERRORS, $FILES);
		exit(1);
    }

	# get the path and name to the bam file we will push. If it's not found, script will exit
	my ($bamFile, $bamFileName) = &getBam();

	# get the upload path of the run_dir on the server and create the sample and run JSON FILES.
	my ($run_dir, $run_json) = &createJsonFiles($bamFile, $bamFileName);

    #create the directory where we will stick the data
    my $returnStatus = &createUploadDir($run_dir);

	# set the path the bam file will be uploaded to on the server we're pushing to
	my $upload_bam_path = "$run_dir/$bamFileName";
	# add the bam file to the list of bams to push
	$FILES = &addFile($bamFile, $upload_bam_path, $FILES);

	# if the bam file pushes successfully, then we know we should push the rest
	my $pushExitCode = &push($bamFile, $ERRORS, $FILES);
	if($pushExitCode != 0){
		# if the bam file didn't push, then don't push any of the other FILES. The report was already printed
		exit(1);
	}

	# check to see if the sample JSON needs to be pushed or add this run to the sample JSON file.
	&pushSampleJson($FILES, $run_json);

    #print the report since we are starting the upload process
    &printReport($ERRORS, $FILES);

	# add the bam index file to the list of bams to push
	$FILES = &addFile($bamFile.".bai", $upload_bam_path.".bai", $FILES);
	# starting with 4.2 coverage analysis plugin output folder gets a number assigned so taht users can run multiple times without over-writing the previous coverage analysis plugin result 
	# example: coverageAnalysis_out.2369. if there are multiple cov results, hopefully they were run with the same BED file! find will get the first instance
	$FILES = &find_and_add_file("$RESULTS_DIR/plugin_out/coverageAnalysis_out*/*.amplicon.cov.xls", $run_dir, $FILES);
	# check to see if there is a vcf file to push as well. If not, cov or TVC will be run on the analysis server.
	$FILES = &find_and_add_file("$RESULTS_DIR/plugin_out/variantCaller_out*/TSVC_variants.vcf", $run_dir, $FILES);
	# push the report.pdf as well
	$FILES = &find_and_add_file("$RESULTS_DIR/report.pdf", $run_dir, $FILES);

    #create the report and start uploading
    foreach my $file (sort {$a cmp $b} keys %{$FILES}){
		print "Working on $file\n";
	    &push($file, $ERRORS, $FILES);
    }

    #print out final review
    &printReport($ERRORS, $FILES);
}

#    #see if this is a barcoded run or not
#    if( -e $ENV{"TSP_FILEPATH_BARCODE_TXT"}){
#	print "This is a barcoded run\n";
#
#	#grab the primary mapped BAM file root name
#	my @tokens = split(/\//, $PRIMARY_BAM);
#	my $bamFile = $tokens[scalar @tokens - 1];
#
#	#parse the barcode file
#	open(IN, $ENV{"TSP_FILEPATH_BARCODE_TXT"}) || die "Could not open ", $ENV{"TSP_FILEPATH_BARCODE_TXT"}, "\n"; 
#
#	while(my $line = <IN>){
#	    chomp($line);
#	    my @tokens = split(/\,/, $line);
#	    
#	    #skip if not more than one token since not likely a barcode entry
#	    if(scalar @tokens > 1){
#		my $barcodeName = $tokens[1];
#		my $bamFile = $RESULTS_DIR . "/" . $barcodeName . "_" . $bamFile;
#
#		#see if the file exists since barcode file shows all barcodes in the set whether used or not
#		if( -e $bamFile){
#		    print "BAM found for barcode $barcodeName - adding to list\n";
#		    $FILES->{$bamFile}->{"status"} = "Pending";
#		    $FILES->{$bamFile}->{"notes"} = "";
#		}
#		else{
#		    print "No BAM file for barcode $barcodeName at $bamFile - skipping\n";
#		}
#	    }
#	}
#
#	close(IN);
#    }
#    else{
#    }

1;

# gets the proper bam file and path
sub getBam{
	#grab the primary mapped BAM file root name
	my $bamFile = $PRIMARY_BAM;
	my @tokens = split(/\//, $PRIMARY_BAM);
	my $bamFileName = $tokens[scalar @tokens - 1];
	if($BARCODE ne ""){

		# now add the barcode
		$bamFile = $RESULTS_DIR . "/" . $BARCODE . "_" . $bamFileName;

		#see if the file exists since barcode file shows all barcodes in the set whether used or not
		if( -e $bamFile){
			print "Will push the bam file of barcde: " . $BARCODE . "\n";
		}
		else{
			# there is an error, print the report and exit
			push(@{$ERRORS}, "No BAM file for barcode $BARCODE at $bamFile - quitting");
			&printReport($ERRORS, $FILES);
			exit(1);
		}
	}
	else{
		print "Will push up primary BAM\n";
	}
	return ($bamFile, $bamFileName);
}

# add a file to the $FILES dictionary
sub addFile{
	my ($file, $upload_path, $FILES) = @_;
	$FILES->{$file}->{"upload_path"} = $upload_path;
	$FILES->{$file}->{"status"} = "Pending";
	$FILES->{$file}->{"notes"} = "";
	return $FILES;
}

# if a file exists, add it to the list of FILES to push
sub find_and_add_file{
	my ($file, $run_dir, $FILES) = @_;

	# if the file is found, then add it to the list of FILES to push.
	my $systemCall="find $file -maxdepth 0 2>/dev/null | head -n 1";
	my $filePath = `$systemCall`;
	chomp($filePath);
	if(length($filePath) != 0){
		my @tokens = split(/\//, $filePath);
		my $fileName = $tokens[scalar @tokens - 1];
		# add the amplicon.cov.xls file to the list of FILES to be pushed.
		$FILES = &addFile($filePath, "$run_dir/$fileName", $FILES);
	}
	return $FILES;
}

# create the Sample and Run JSON FILES to be pushed
sub createJsonFiles{
	my ($bamFile, $bamFileName) = @_;

	# get the ip address of the current server.
	my $systemCall = q(/sbin/ifconfig | grep 'inet addr:' | grep -v "127.0.0.1" | cut -d: -f2 | head -n 1 | awk '{print $1}');
	my $local_ip = `bash -c \"$systemCall\"`;
	chomp($local_ip);
	my $TS_version = "not_found";
#	# TODO get the ts_version of this bam file
#    if( -e $ENV{"TSP_FILEPATH_BARCODE_TXT"}){
#		my $TS_version=`grep -oE \"version.*\" $1 -m 1 2>/dev/null | grep -oe "[0-9]\.[0-9]" | perl -ne "chomp and print"`
#		if [ "$TS_version" == "" ]; then
#			TS_version=`grep -oE "Torrent_Suite=.*" $1 -m 1 2>/dev/null | grep -oe "[0-9]\.[0-9]" | perl -ne "chomp and print"`
#		else
#			TS_version="not_found"
#
    $systemCall = "python $PLUGIN_PATH/scripts/setup_json.py --local_ip $local_ip --bam $bamFile --ts_version $TS_version";
	print "running setup_json.py: $systemCall\n";
    my $results = `$systemCall`;
    my @tokens = split(/\,/, $results);
    my $run_dir = $tokens[0];
    my $run_json = $tokens[1];
	chomp($run_dir);
    chomp($run_json);
	return ($run_dir, $run_json);
}

#create the directory to upload
sub createUploadDir{
	my ($upload_dir) = @_;
    #create the directory
    my $systemCall = "sshpass -p $USER_PASSWORD ssh $USER_NAME\@$SERVER_IP \"mkdir -p $upload_dir\"";
	print "Running: $systemCall\n";
    my $returnStatus = system($systemCall);
	if($returnStatus ne 0){
		push(@{$ERRORS}, "Unable to create the run_dir on the server over SSH. Check the username, password, and ip. Quitting.");
		&printReport($ERRORS, $FILES);
		exit(1);
    }
}

# check to push the sampleJSON
sub pushSampleJson{
    my ($FILES, $run_json) = @_;
	# Check to see if this sample's JSON file already exists
	# Check this first to avoid conflict with other runs of this sample that are also being pushed.
    my $systemCall = "sshpass -p $USER_PASSWORD ssh $USER_NAME\@$SERVER_IP \"stat $SAMPLE_DIR/$SAMPLE_NAME.json 2>/dev/null\"";
	my $result = `$systemCall`;
	if(length($result) == 0){
		# doesn't exist, so push the sample's JSON file. 
		# the sample JSON file already has the current run in this sample's list of runs.
		my $sample_json = "$RESULTS_DIR/$SAMPLE_NAME.json";
		$FILES = &addFile($sample_json, "$SAMPLE_DIR/$SAMPLE_NAME.json", $FILES);
	    my $pushExitStatus = &push($sample_json, $ERRORS, $FILES);
		if($pushExitStatus ne 0){
			# The sample json is needed in order to run any analysis so if pushing the sample json fails, quit.
			exit(1);
		}
	}
	else{
		# copy the sample_json file from the other server, add this run to it and recopy it back over.
		$systemCall = "python $PLUGIN_PATH/scripts/update_json_tool.py --user_password $USER_PASSWORD --json $run_json --add_run_to_sample --server $USER_NAME\@$SERVER_IP";
		my $returnStatus = system($systemCall);
		if($returnStatus ne 0){
			push(@{$ERRORS}, "Unable to add the run to the sample's JSON file located on the analysis server.");
			&printReport($ERRORS, $FILES);
			# if this run is not added to the list of runs, then it will not be considered in the analysis.
			exit(1);
		}
	}
}


#push a file over
sub push{
    my ($file, $ERRORS, $FILES) = @_;

	# upload path:
	my $upload_path = $FILES->{$file}->{"upload_path"};

	# set the pushExitCode to 0 for if the file has already been uploaded
	my $pushExitCode = 0;
	my $date = `date`;
	chomp($date);

	# if this file has already been pushed, then don't do anything
	if($FILES->{$file}->{"status"} eq "Pending"){
		# check the md5sum before copying to see if the file has already been copyied before. Bam file takes about 1min 30sec
		my ($md5sum, $remoteMD5sum) = &check_md5sum($file, $upload_path);
		if($md5sum eq $remoteMD5sum){
			$FILES->{$file}->{"status"} = "Already Uploaded";
			$FILES->{$file}->{"notes"} = $FILES->{$file}->{"notes"}."<br>Finished: $date<br><font color=\"green\">MD5s Match: $md5sum</font>";
			&printReport($ERRORS, $FILES);
		}
		else{
			my $size = `ls -lh $file`;
			my @tokens = split(/\s+/, $size);
			$size = $tokens[4];
			chomp($size);

			$FILES->{$file}->{"status"} = "Uploading";
			#$FILES->{$file}->{"notes"} = "Started: $date<br>Size: $size Reads: $numReads";
			$FILES->{$file}->{"notes"} = "Started: $date<br>Size: $size";
			&printReport($ERRORS, $FILES);

			# push the file
			my $systemCall = "pscp -pw $USER_PASSWORD $file $USER_NAME\@$SERVER_IP\:$upload_path";
			#print "$systemCall\n";
			$pushExitCode = system($systemCall);

			#set the status
			$date = `date`;
			chomp($date);
		
			#check the status
			if($pushExitCode != 0){
				#push has failed
				$FILES->{$file}->{"status"} = "<font color=\"red\">Upload Failed</font>";
				$FILES->{$file}->{"notes"} = $FILES->{$file}->{"notes"}."<br>Finished: $date<br>";
				push(@{$ERRORS}, "Failed upload on $file");
				&printReport($ERRORS, $FILES);
			}
			else{
				# check the md5sum to see if the FILES match completely
				my ($md5sum, $remoteMD5sum) = &check_md5sum($file, $upload_path);
				if($md5sum eq $remoteMD5sum){
					$FILES->{$file}->{"status"} = "Upload Complete";
					$FILES->{$file}->{"notes"} = $FILES->{$file}->{"notes"}."<br>Finished: $date<br><font color=\"green\">MD5s Match: $md5sum</font>";
					&printReport($ERRORS, $FILES);
				}
				else{
					# something went wrong with the push!
					$pushExitCode = 1;
					$FILES->{$file}->{"status"} = "MD5 Mismtach";
					$FILES->{$file}->{"notes"} = $FILES->{$file}->{"notes"}."<br>Finished: $date<br><font color=\"red\">MD5s Mismatch: $md5sum / $remoteMD5sum</font>";
					push(@{$ERRORS}, "Mistmatch MD5sum on $file");
					&printReport($ERRORS, $FILES);
				}
			}
		}
	}
	return $pushExitCode;
}

sub check_md5sum{
	my ($file, $upload_path) = @_;
	#push was good, but now lets check teh get md5 if it was ssh
	$FILES->{$file}->{"status"} = "Checking MD5s";
	my $md5sum = `md5sum $file`;
	my @tokens = split(/\s+/, $md5sum);
	$md5sum = $tokens[0];
	chomp($md5sum);

	@tokens = split(/\//, $file);

	#getremote md5
	my $systemCall = "sshpass -p $USER_PASSWORD ssh $USER_NAME\@$SERVER_IP \"md5sum $upload_path \"";
	my $remoteMD5sum = `$systemCall`;
	@tokens = split(/\s+/, $remoteMD5sum);
	$remoteMD5sum = $tokens[0];
	chomp($remoteMD5sum);

	return ($md5sum, $remoteMD5sum);
}

#print the report
sub printReport{
    my ($ERRORS, $FILES) = @_;

    open(OUT, ">$OUTPUT_DIR/status_block.html") || die "Could not write status report\n";

    print OUT "<!DOCTYPE html>\n";
    print OUT "\t<html>\n";
    print OUT "\t\t<head>\n";
    print OUT "\t\t\t<title>QCRunTransfer</title>\n";
    print OUT "\t\t\t<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n";
    print OUT "\t\t\t<link href=\"/pluginMedia/QCRunTransfer/css/kendo.common.min.css\" rel=\"stylesheet\" />\n";
    print OUT "\t\t\t<link href=\"/pluginMedia/QCRunTransfer/css/kendo.default.min.css\" rel=\"stylesheet\" />\n";
    print OUT "\t\t\t<link href=\"/pluginMedia/QCRunTransfer/css/kendo.ir.css\" rel=\"stylesheet\" />\n";
    print OUT "\t\t\t<link href=\"/pluginMedia/QCRunTransfer/css/ir.css\" rel=\"stylesheet\">\n";
    print OUT "\t\t\t<link href=\"/pluginMedia/QCRunTransfer/css/app.css\" rel=\"stylesheet\">\n";
    print OUT "\t\t\t<link href=\"/pluginMedia/QCRunTransfer/css/bootstrap.css\" rel=\"stylesheet\">\n";
    print OUT "\t\t\t<link href=\"/pluginMedia/QCRunTransfer/css/app.less\" rel=\"stylesheet/less\">\n";
    print OUT "\t\t\t<link href=\"/pluginMedia/QCRunTransfer/css/bootstrap-custom.css\" rel=\"stylesheet\">\n";
    print OUT "\t\t\t<link href=\"/pluginMedia/QCRunTransfer/css/bootstrap-select.min.css\" rel=\"stylesheet\">\n";
    print OUT "\t\t\t<script src=\"/pluginMedia/QCRunTransfer/js/less-1.4.1.min.js\"></script>\n";
    print OUT "\t\t\t<script src=\"/pluginMedia/QCRunTransfer/js/jquery-1.8.2.min.js\"></script>\n";
    print OUT "\t\t\t<script src=\"/pluginMedia/QCRunTransfer/js/bootstrap-select.min.js\"></script>\n";
    print OUT "\t\t\t<script src=\"/pluginMedia/QCRunTransfer/js/bootstrap.min.js\"></script>\n";
    print OUT "\t\t</head>\n";

    print OUT "\t\t<div class=\"main\">\n";
    print OUT "\t\t\t<div class=\"main-content clearfix\">\n";
    print OUT "\t\t\t\t<div class=\"container-fluid\">\n";
    print OUT "\t\t\t\t\t<div class=\"row-fluid sample\">\n";
    print OUT "\t\t\t\t\t\t<div class=\"span12\">\n";
    print OUT "\t\t\t\t\t\t\t<div style=\"padding:0 5px\">\n";

    #summary
    print OUT "\t\t\t\t\t\t\t\t<div style=\"padding-top:5px\">\n";
    print OUT "\t\t\t\t\t\t\t\t\t<div class=\"accordion-group\">\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t<div class=\"accordion-heading\">\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t<a class=\"accordion-toggle\" data-toggle=\"collapse\" href=\"\#ERRORS\">Summary</a>\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t</div>\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t<div id=\"summary\" class=\"accordion-body collapse in\">\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t<div class=\"accordion-inner\">\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t\t<div id=\"variantSummaryInfoPane\" class=\"row-fluid\">\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t\t\t<div class=\"row-fluid\">\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t\t\t</div>\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t\t<table class=\"table table-condensed\">\n";


    print OUT "\t\t\t\t\t\t\t\t\t\t\t\t\t<tr><th>Variable</th><th>Value</th></tr>\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t\t\t<tr><td>Target Directory</td><td>$UPLOAD_DIR</td></tr>\n";

	#get the target space utilization info
	my $systemCall = "sshpass -p $USER_PASSWORD ssh $USER_NAME\@$SERVER_IP \"df -kh $UPLOAD_DIR\"";
	my $usageOutput = `$systemCall`;
	my @usageTokens = split(/\s+/, $usageOutput);

	print OUT "\t\t\t\t\t\t\t\t\t\t\t\t\t<tr><td>Target Size</td><td>$usageTokens[8]</td></tr>\n";
	print OUT "\t\t\t\t\t\t\t\t\t\t\t\t\t<tr><td>Target Used</td><td>$usageTokens[9]</td></tr>\n";
	print OUT "\t\t\t\t\t\t\t\t\t\t\t\t\t<tr><td>Target Available</td><td>$usageTokens[10]</td></tr>\n";
	print OUT "\t\t\t\t\t\t\t\t\t\t\t\t\t<tr><td>Target % Full</td><td>$usageTokens[11]</td></tr>\n";

    print OUT "\t\t\t\t\t\t\t\t\t\t\t\t</table>\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t\t</div>\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t</div>\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t</div>\n";
    print OUT "\t\t\t\t\t\t\t\t\t</div>\n";
    print OUT "\t\t\t\t\t\t\t\t</div>\n";

    #error section
    print OUT "\t\t\t\t\t\t\t\t<div style=\"padding-top:5px\">\n";
    print OUT "\t\t\t\t\t\t\t\t\t<div class=\"accordion-group\">\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t<div class=\"accordion-heading\">\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t<a class=\"accordion-toggle\" data-toggle=\"collapse\" href=\"\#ERRORS\">Errors</a>\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t</div>\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t<div id=\"ERRORS\" class=\"accordion-body collapse in\">\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t<div class=\"accordion-inner\">\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t\t<div id=\"variantSummaryInfoPane\" class=\"row-fluid\">\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t\t\t<div class=\"row-fluid\">\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t\t\t</div>\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t\t<table class=\"table table-condensed\">\n";

    #error stuff
    if(!defined($ERRORS) || scalar @{$ERRORS} == 0){
		print OUT "\t\t\t\t\t\t\t\t\t\t\t\t\t<tr><th>No Errors</th></tr>\n";	
    }
    else{
		#print error messages
		print OUT "\t\t\t\t\t\t\t\t\t\t\t\t\t<tr><th>Error</th></tr>\n";
		foreach my $error (@{$ERRORS}){
			print OUT "\t\t\t\t\t\t\t\t\t\t\t\t\t<tr><td>$error</td></tr>\n";
		}
    }

    print OUT "\t\t\t\t\t\t\t\t\t\t\t\t</table>\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t\t</div>\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t</div>\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t</div>\n";
    print OUT "\t\t\t\t\t\t\t\t\t</div>\n";
    print OUT "\t\t\t\t\t\t\t\t</div>\n";

    #file section
    print OUT "\t\t\t\t\t\t\t\t<div style=\"padding-top:5px\">\n";
    print OUT "\t\t\t\t\t\t\t\t\t<div class=\"accordion-group\">\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t<div class=\"accordion-heading\">\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t<a class=\"accordion-toggle\" data-toggle=\"collapse\" href=\"\#FILES\">Files</a>\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t</div>\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t<div id=\"FILES\" class=\"accordion-body collapse in\">\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t<div class=\"accordion-inner\">\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t\t<div id=\"variantSummaryInfoPane\" class=\"row-fluid\">\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t\t\t<div class=\"row-fluid\">\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t\t\t</div>\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t\t<table class=\"table table-condensed\">\n";

    #error stuff
    print OUT "\t\t\t\t\t\t\t\t\t\t\t\t\t<tr><th>File</th><th>Status</th><th>Notes</th></tr>\n";

    foreach my $file (sort {$a cmp $b} keys %{$FILES}){
		print OUT "\t\t\t\t\t\t\t\t\t\t\t\t\t<tr><td>$file</td><td>", $FILES->{$file}->{"status"}, "</td><td>", $FILES->{$file}->{"notes"}, "</td></tr>\n";
    }

    print OUT "\t\t\t\t\t\t\t\t\t\t\t\t</table>\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t\t</div>\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t</div>\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t</div>\n";
    print OUT "\t\t\t\t\t\t\t\t\t</div>\n";
    print OUT "\t\t\t\t\t\t\t\t</div>\n";

    #close it out
    print OUT "\t\t\t\t\t\t\t</div>\n";
    print OUT "\t\t\t\t\t\t</div>\n";
    print OUT "\t\t\t\t\t</div>\n";
    print OUT "\t\t\t\t</div>\n";
    print OUT "\t\t\t</div>\n";
    print OUT "\t\t</body>\n";
    print OUT "\t</html>\n";

    close(OUT);
}


