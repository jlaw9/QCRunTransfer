#!/usr/bin/expect
# Copyright (C) 2011 Ion Torrent Systems, Inc. All Rights Reserved

set PLUGINCONFIG__USER_NAME [lindex $argv 0]
set PLUGINCONFIG__IP [lindex $argv 1]
set PLUGINCONFIG__PASSWORD [lindex $argv 2]
set PLUGINCONFIG__FILE [lindex $argv 3]

spawn sftp -o batchmode=no -b $PLUGINCONFIG__FILE $PLUGINCONFIG__USER_NAME@$PLUGINCONFIG__IP
expect "*password*" {
    send "${PLUGINCONFIG__PASSWORD}\r"
}

exit