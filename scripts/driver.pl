#!/usr/lib/perl -w
# copy some BAM files now

use strict;

#grab some key variables
my $PROTOCOL = $ENV{"PLUGINCONFIG__PROTOCOL"} || "FTP";
my $RESULTS_DIR = $ENV{"RUNINFO__REPORT_ROOT_DIR"};
my $RAW_DATA_DIR = $ENV{"RUNINFO__RAW_DATA_DIR"};
my $SERVER_IP = $ENV{"PLUGINCONFIG__IP"};
my $USER_NAME = $ENV{"PLUGINCONFIG__USER_NAME"};
my $USER_PASSWORD = $ENV{"PLUGINCONFIG__USER_PASSWORD"};
my $UPLOAD_DIR = $ENV{"PLUGINCONFIG__UPLOAD_PATH"} . "/" . $ENV{"TSP_ANALYSIS_NAME"} . "/";
my $SAMPLE = $ENV{"PLUGINCONFIG__SAMPLE"};
my $RUN = $ENV{"PLUGINCONFIG__RUN"};
my $PROJECT = $ENV{"PLUGINCONFIG__PROJECT"};
my $OUTPUT_DIR = $ENV{"TSP_FILEPATH_PLUGIN_DIR"};
my $PLUGINNAME = $ENV{"PLUGINNAME"};
my $PRIMARY_BAM = $ENV{"TSP_FILEPATH_BAM"};
my $PLUGIN_PATH = $ENV{"DIRNAME"};
#my $MIN_READS = $ENV{"PLUGINCONFIG__MIN_READS"};

#force scope
{
    #check to make sure we don't have any errors
    my $errors = ();

    if($SERVER_IP eq ""){
	push(@{$errors}, "No server name / IP provided");
    }

    if($USER_NAME eq ""){
	push(@{$errors}, "No user name provided");
    }

    if($USER_PASSWORD eq ""){
	push(@{$errors}, "No user password provided");
    }

    if($SAMPLE eq ""){
	push(@{$errors}, "No sample provided");
    }

    if($RUN eq ""){
	push(@{$errors}, "No run provided");
    }

    #we will store info on the files we are uploading so we can print status updates as needed
    my $files = {};

    #if we have errors let's print the report
    if(defined($errors) && scalar @{$errors} != 0){
	&printReport($errors, $files);
	exit();
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
#		    $files->{$bamFile}->{"status"} = "Pending";
#		    $files->{$bamFile}->{"notes"} = "";
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
#	print "Not a barcoded run, will push up primary BAM only\n";
#	$files->{$PRIMARY_BAM}->{"status"} = "Pending";
#	$files->{$PRIMARY_BAM}->{"notes"} = "";
#    }
#
#    #create the directory where we will stick the data if we are using SSH
#    if($PROTOCOL eq "SSH"){
#	&createUploadDir();
#    }
#
#    #print the report since we are starting the upload process
#    
#    if(scalar keys %{$files} == 0){
#	push(@{$errors}, "No valid BAM files found");
#	&printReport($errors, $files);
#	exit();
#    }
#
#    &printReport($errors, $files);
#
#    #create the report and start uploading
#    foreach my $file (sort {$a cmp $b} keys %{$files}){
#	print "Working on $file\n";
#	$files->{$file}->{"status"} = "Counting Reads";
#	$files->{$file}->{"notes"} = "";
#	&printReport($errors, $files);
#	
#	#check the number of reads - skip for now because it takes a long time
#	my $systemCall = "";
#	#my $systemCall = "samtools view $file | grep -v \"\#\" | wc -l";
#	#my $numReads = `$systemCall`;
#	#chomp($numReads);
#	#print "$numReads reads in $file\n";
#
#	#if($numReads < $MIN_READS){
#	    #print "Skipping because reads less than $MIN_READS\n";
#	    #$files->{$file}->{"status"} = "Skipped";
#	    #$files->{$file}->{"notes"} = "Too few reads ($numReads)";
#	    #&printReport($errors, $files);
#	    #next;
#	#}
#	#else{
#      	    #upload the file	    
#	    #&push($file, $errors, $files, $numReads);
#	    &push($file, $errors, $files);
#	#}
#    }
#
#    #print out final review
#    &printReport($errors, $files);
}

1;

#create the directory to upload
sub createUploadDir{
    #create the directory
    my $systemCall = "sshpass -p $USER_PASSWORD ssh $USER_NAME\@$SERVER_IP \"mkdir -p $UPLOAD_DIR\"";
    system($systemCall);
}

#push a file over
sub push{
    #my ($file, $errors, $files, $numReads) = @_;
    my ($file, $errors, $files) = @_;

    my $size = `ls -lh $file`;
    my @tokens = split(/\s+/, $size);
    $size = $tokens[4];
    chomp($size);

    my $date = `date`;
    chomp($date);
    $files->{$file}->{"status"} = "Uploading";
    #$files->{$file}->{"notes"} = "Started: $date<br>Size: $size Reads: $numReads";
    $files->{$file}->{"notes"} = "Started: $date<br>Size: $size";
    &printReport($errors, $files);

    #see if we should use scp or ftp
    my $systemCall = "pscp -pw $USER_PASSWORD $file $USER_NAME\@$SERVER_IP\:$UPLOAD_DIR/";

    if($PROTOCOL eq "FTP"){
	#write the batch file
	open(OUT, ">$OUTPUT_DIR/sftp.batch") || die "Could not write $OUTPUT_DIR/sftp.batch\n";

	#need to recursively add directories
	my @tokens = split(/\//, $UPLOAD_DIR);
	my $path = "";

	foreach my $token(@tokens){
	    if($token eq ""){
		next;
	    }

	    $path .= "$token/";
	    print OUT "-mkdir $path\n";
	}

	#change directories
	print OUT "cd $UPLOAD_DIR\n";

	#put file
	print OUT "put $file\n";
	close(OUT);

	$systemCall = "expect $PLUGIN_PATH/scripts/ftp_file.sh $USER_NAME $SERVER_IP $USER_PASSWORD $OUTPUT_DIR/sftp.batch";
	print "$systemCall\n";
    }

    #print "$systemCall\n";
    my $pushExitCode = system($systemCall);

    #set the status
    $date = `date`;
    chomp($date);


    #check the status
    if($pushExitCode != 0){
	#push has failed
	    $files->{$file}->{"status"} = "<font color=\"red\">Upload Failed</font>";
	    $files->{$file}->{"notes"} = $files->{$file}->{"notes"}."<br>Finished: $date<br>";
	    push(@{$errors}, "Failed upload on $file");
	    &printReport($errors, $files);
    }
    else{
	#push was good, but now lets check teh get md5 if it was ssh
	if($PROTOCOL eq "SSH"){
	    $files->{$file}->{"status"} = "Checking MD5s";
	    my $md5sum = `md5sum $file`;
	    @tokens = split(/\s+/, $md5sum);
	    $md5sum = $tokens[0];
	    chomp($md5sum);
	
	    @tokens = split(/\//, $file);
	
	    #getremote md5
	    $systemCall = "sshpass -p $USER_PASSWORD ssh $USER_NAME\@$SERVER_IP \"md5sum $UPLOAD_DIR/" . $tokens[scalar @tokens - 1] . "\"";
	    my $remoteMD5sum = `$systemCall`;
	    @tokens = split(/\s+/, $remoteMD5sum);
	    $remoteMD5sum = $tokens[0];
	    chomp($remoteMD5sum);
	    
	    if($md5sum eq $remoteMD5sum){
		$files->{$file}->{"status"} = "Upload Complete";
		$files->{$file}->{"notes"} = $files->{$file}->{"notes"}."<br>Finished: $date<br><font color=\"green\">MD5s Match: $md5sum</font>";
		&printReport($errors, $files);
	    }
	    else{
		$files->{$file}->{"status"} = "MD5 Mismtach";
		$files->{$file}->{"notes"} = $files->{$file}->{"notes"}."<br>Finished: $date<br><font color=\"red\">MD5s Mismatch: $md5sum / $remoteMD5sum</font>";
		push(@{$errors}, "Mistmatch MD5sum on $file");
		&printReport($errors, $files);
	    }
	}
    }
}

#print the report
sub printReport{
    my ($errors, $files) = @_;

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
    print OUT "\t\t\t\t\t\t\t\t\t\t\t<a class=\"accordion-toggle\" data-toggle=\"collapse\" href=\"\#errors\">Summary</a>\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t</div>\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t<div id=\"summary\" class=\"accordion-body collapse in\">\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t<div class=\"accordion-inner\">\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t\t<div id=\"variantSummaryInfoPane\" class=\"row-fluid\">\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t\t\t<div class=\"row-fluid\">\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t\t\t</div>\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t\t<table class=\"table table-condensed\">\n";


    print OUT "\t\t\t\t\t\t\t\t\t\t\t\t\t<tr><th>Variable</th><th>Value</th></tr>\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t\t\t<tr><td>Target Directory</td><td>$UPLOAD_DIR</td></tr>\n";

    #if we are using SSH we can grab extra info
    if($PROTOCOL eq "SSH"){
	#get the target space utilization info
	my $systemCall = "sshpass -p $USER_PASSWORD ssh $USER_NAME\@$SERVER_IP \"df -kh $UPLOAD_DIR\"";
	my $usageOutput = `$systemCall`;
	my @usageTokens = split(/\s+/, $usageOutput);

	print OUT "\t\t\t\t\t\t\t\t\t\t\t\t\t<tr><td>Target Size</td><td>$usageTokens[8]</td></tr>\n";
	print OUT "\t\t\t\t\t\t\t\t\t\t\t\t\t<tr><td>Target Used</td><td>$usageTokens[9]</td></tr>\n";
	print OUT "\t\t\t\t\t\t\t\t\t\t\t\t\t<tr><td>Target Available</td><td>$usageTokens[10]</td></tr>\n";
	print OUT "\t\t\t\t\t\t\t\t\t\t\t\t\t<tr><td>Target % Full</td><td>$usageTokens[11]</td></tr>\n";
    }
    #else we are SFTP
    else{
	
    }

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
    print OUT "\t\t\t\t\t\t\t\t\t\t\t<a class=\"accordion-toggle\" data-toggle=\"collapse\" href=\"\#errors\">Errors</a>\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t</div>\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t<div id=\"errors\" class=\"accordion-body collapse in\">\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t<div class=\"accordion-inner\">\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t\t<div id=\"variantSummaryInfoPane\" class=\"row-fluid\">\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t\t\t<div class=\"row-fluid\">\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t\t\t</div>\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t\t<table class=\"table table-condensed\">\n";

    #error stuff
    if(!defined($errors) || scalar @{$errors} == 0){
	print OUT "\t\t\t\t\t\t\t\t\t\t\t\t\t<tr><th>No Errors</th></tr>\n";	
    }
    else{
	#print error messages
	print OUT "\t\t\t\t\t\t\t\t\t\t\t\t\t<tr><th>Error</th></tr>\n";
	foreach my $error (@{$errors}){
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
    print OUT "\t\t\t\t\t\t\t\t\t\t\t<a class=\"accordion-toggle\" data-toggle=\"collapse\" href=\"\#files\">Files</a>\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t</div>\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t<div id=\"files\" class=\"accordion-body collapse in\">\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t<div class=\"accordion-inner\">\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t\t<div id=\"variantSummaryInfoPane\" class=\"row-fluid\">\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t\t\t<div class=\"row-fluid\">\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t\t\t</div>\n";
    print OUT "\t\t\t\t\t\t\t\t\t\t\t\t<table class=\"table table-condensed\">\n";

    #error stuff
    print OUT "\t\t\t\t\t\t\t\t\t\t\t\t\t<tr><th>File</th><th>Status</th><th>Notes</th></tr>\n";

    foreach my $file (sort {$a cmp $b} keys %{$files}){
	print OUT "\t\t\t\t\t\t\t\t\t\t\t\t\t<tr><td>$file</td><td>", $files->{$file}->{"status"}, "</td><td>", $files->{$file}->{"notes"}, "</td></tr>\n";
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

