#! /bin/bash

# Goal: If the job or process ID takes longer than the specified time, kill it.
# $1 is the amount of time to sleep
sleep $1
# $2 is the Process ID to kill
kill $2 >/dev/null 2>&1
