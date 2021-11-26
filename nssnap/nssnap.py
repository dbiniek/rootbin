#!/usr/bin/env python
# nsys.py - New Sys-Snap in Python
#     name is a work in progress, I realize Nvidia has a command called nsys
#         TODO: look for alternative names
# TODO: fix before reboot, adjust formatting, add formatting options for reports, today/yesterday

# config vars
CFG_LOG_DIRECTORY = '/root/SYS-SNAP' # logging folder, also for pid/error logs, no trailing slash
CFG_LOG_RETENTION = 5  # days to save logs for, logs can be big, wise to watch out with this
CFG_SKIP_UNIX_SOCKETS = 1 # do we put unix sockets in the logs, or just tcp/udp

#TODO look into the difference of these:
#original just specified the version as such:
SS_VERSION = '1.0.2'
#vs code suggested a function as such
#def version():
#    SS_VERSION = '1.0.2'
#    return SS_VERSION
#
#SS_VERSION = version()


#imports (https://docs.python.org/3/reference/import.html)

import sys # https://docs.python.org/3/library/sys.html
import time # https://docs.python.org/3/library/time.html
import os # https://docs.python.org/3/library/os.html
import getopt # https://docs.python.org/3/library/getopt.html
##TODO: Look into argparse() https://docs.python.org/3/library/argparse.html#module-argparse
import threading # https://docs.python.org/3/library/threading.html
import subprocess # https://docs.python.org/3/library/subprocess.html
import socket # https://docs.python.org/3/library/socket.html
# The from something import somthing format is calling a class of a module 
from struct import pack # https://docs.python.org/3/library/struct.html
from collections import deque # https://docs.python.org/3/library/collections.html
from datetime import datetime # https://stackoverflow.com/questions/15707532/import-datetime-v-s-from-datetime-import-datetime
import ConfigParser # https://docs.python.org/3/library/configparser.html
import signal # https://docs.python.org/3/library/signal.html
import gzip # https://docs.python.org/3/library/gzip.html

try:
    import MySQLdb as _mysql
except ImportError:
    USE_MYSQLDB = False
else:
    import subprocess # THIS MIGHT GET MOVED TO STANDARD IF SOMETHING ELSE NEEDS, for now just mysql
    USE_MYSQLDB = True

WRITE_PICKLE = True
try:
    import cPickle as _json
    PickleError = _json.PickleError
except ImportError:
    WRITE_PICKLE = False
    PickleError = IOError # I know it's ghetto, but just in case someone tries not using cPickle
    try:
        import cjson as _json
    except ImportError:
        try:
            import ujson as _json
        except ImportError:
            print ("ERROR:  Either the json library (python 2.5+) or cjson/ujson is required.\n Please install ujson via easy_install or pip.\n")
            exit()

# some config stuff that isn't config fileized yet
COMPRESS_STUFF = 0
CFG_LOG_INTERVAL = 60
# maximum amount of logs queued at a given time before the writer starts spitting out errors to prevent memory issues
WRITER_QUEUE_MAX = 30

# import stuff that isn't needed for the daemon but is for other stuff here
if (len(sys.argv) > 1 and sys.argv[1] not in ['--start','--daemon']):
    import glob

# check what control panel in use
# may be able to remove this check, since we don't run plesk
if os.path.exists('/usr/local/cpanel'):
    CONTROL_PANEL = 'cpanel'
elif os.path.exists('/usr/local/psa'):
    CONTROL_PANEL = 'plesk'
else:
    CONTROL_PANEL = None

if os.path.exists('/proc/user_beancounters'):
    CFG_UBC = 1
else:
    CFG_UBC = 0

CFG_MYSQL_MIN_QUERIES = 2 # minimum number of queries to bother logging mysql stuff
CFG_PROC_MIN_LOAD = 0.0 # minimum load to bother recording activity
CFG_PROC_MIN_MEM = 0 # minimum memory usage to log, logging triggered on either this or load
CFG_LOGPICKER_BEHAVIOR = 0 # 0 means pick log closest to date, 1 means pick log closest before date
CFG_EXTENDED_INFO = False # used by some things like ps to show extra data not normally put in the command

CFG_TZ = False # should be left blank, it gets populated as necessary later.

# typography
CLR_BOLD = "\033[1m"
CLR_RSET = "\033[0;0m"
CLR_RSETB = "\033[0;0m" # same as RSET, but RSET gets nuked by nocolor, rsetb doesn't
CLR_LBLUE = "\033[1;34m"
CLR_GREEN = "\033[0;32m"
CLR_RED = "\033[0;31m"
CLR_YELLOW = "\033[1;33m"
# allow NOCOLOR environ var
if os.environ.get('NOCOLOR',False):
    CLR_RED = ""
    CLR_YELLOW = ""
    CLR_BLUE = ""
    CLR_LBLUE = ""
    CLR_GREEN = ""

TCP_STATES = {1: 'ESTABLISHED', 2: 'SYN_SENT', 3: 'SYN_RECV',
                               4: 'FIN_WAIT1', 5: 'FIN_WAIT2', 6: 'TIME_WAIT',
                               7: 'CLOSE', 8: 'CLOSE_WAIT', 9: 'LAST_ACK', 10: 'LISTEN',
                               11: 'CLOSING'}
if not os.environ.get('HOME',False):
    os.environ['HOME'] = '/root' # otherwise it will do dumb things accessing .my.cnf when run as service

