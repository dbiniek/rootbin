###########
# Ikea
# Generates backups, downloads backups and restores backups from remote servers.
# https://confluence.endurance.com/display/HGS2/Migrations%3A+Ikea 
# Please submit all bug reports at jira.endurance.com
#
# (C) 2011 - HostGator.com, LLC
###########

VERSION = (0, 0, 0, 1)
__version__ = ''.join(['-.'[type(x) == int]+str(x) for x in VERSION])[1:]

from cPanel import *
from WHM import *
from helpers import *
