#! /usr/bin/env python

import json 
import os
import sys

print 'starting'

print os.environ['RESULTS_DIR']
test_json = json.load(open(os.environ['RESULTS_DIR'] + '/startplugin.json'))
print 'ip: ', test_json['pluginconfig']['ip']

print 'done'
