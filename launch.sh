#!/bin/bash
#Copyright (C) 2015  Jeff Law
 
#This program is free software; you can redistribute it and/or
#modify it under the terms of the GNU General Public License
#as published by the Free Software Foundation; either version 2
#of the License, or (at your option) any later version.
 
#This program is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
 
#You should have received a copy of the GNU General Public License
#along with this program; if not, write to the Free Software
#Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

VERSION="1.0.1.0" # major.minor.bug

# ===================================================
# Plugin functions
# ===================================================

#*! @function
#  @param  $*  the command to be executed
run ()
{
	echo "running: $*";
	eval $*;
	EXIT_CODE="$?";
}

# ===================================================
# Plugin initialization
# ===================================================

# use git pull here to ensure that we are using the most up-to-date version of the scripts
run "git --git-dir=/results/plugins/QCRunTransfer/.git pull";

# remove some files if they are there
run "rm -rf ${TSP_FILEPATH_PLUGIN_DIR}/*.html";

# if the known_hosts file is deleted, then sshpass won't work!
#clean up old keys just in case user has brought down the vm and then spun it up again and want to avoid ssh warning
#if [ -e ~/.ssh/known_hosts ]; then
#    rm ~/.ssh/known_hosts
#fi

#if [ -e ~/.putty/sshhostkeys ]; then
#    rm ~/.putty/sshhostkeys
#fi

#create connection to generated ssh entry
expect $DIRNAME/scripts/ssh_connection.sh $PLUGINCONFIG__USER_NAME $PLUGINCONFIG__IP
expect $DIRNAME/scripts/pscp_connection.sh $PLUGINCONFIG__USER_PASSWORD $PLUGINCONFIG__USER_NAME $PLUGINCONFIG__IP > $TSP_FILEPATH_PLUGIN_DIR/temp.txt
rm $TSP_FILEPATH_PLUGIN_DIR/temp.txt

#build call to the driver.pl script which will take care of the rest
run "perl ${DIRNAME}/scripts/driver.pl";


