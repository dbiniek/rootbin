###########
# Ikea
# Generates backups, downloads backups and restores backups from remote servers.
# https://confluence.endurance.com/display/HGS2/Migrations%3A+Ikea
# Please submit all bug reports at jira.endurance.com
#
# (C) 2011 - HostGator.com, LLC
###########

VERSION = (2, 0, 0, 0)
__version__ = ''.join(['-.'[type(x) == int]+str(x) for x in VERSION])[1:]


TITLE = "The Incredible Kontent Extraction Automator"
USAGE = """
%prog [options] <file_with_account_list>
%prog [options] <host> <user> <password>
%prog [options]

Reads a white-space separated list of account details ('user password host')
from the provided filename, one account per line or alternatively, for single
accounts takes the arguments 'user password host' directly and verifies the
cPanel access details among other things.

Full documentation: https://confluence.endurance.com/display/HGS/MigrationsTransferIkea

Example of the 'file_with_account_list' file:
    somehost.com bob l4m3passW0RD
    somehost2.net nomnom44 noneshallpass
    
Running the tool:
    %prog -c somehost.com bob l4m3passW0RD
    (runs pre-transfer checks to verify login info and show account stats)
    
    %prog -b list
    (iterates through accounts in the file 'list', verifies information, gets
    account stats and generates backups)
    
    %prog -bd somehost.com bob l4m3passW0RD
    (creates, and downloads backup from source server)
"""

import socket
socket.setdefaulttimeout(45)

from pretransfer import *
from backup import *
from download import *
from restore import *
from posttransfer import *
from helpers import *

import os.path
import re
import readline
from socket import gethostname

from optparse import OptionGroup
from optparse import OptionParser
from urlparse import urlparse

from cPanel import cPanel
from cPanel import WHM


def optionHandler():
    parser = OptionParser(USAGE, version="%prog " + __version__)
    parser.add_option("-c", "--pre-check",
                      action="store_true", dest="precheck", default=False,
                      help="run pre-transfer check for the account(s)")
    parser.add_option("-l", "--list",
                      action="store_true", dest="list", default=False,
                      help="list available cPanel backups for the account(s)")
    parser.add_option("-s", "--skiphome",
                      action="store_true", dest="skiphome", default=False,
                      help="Upload a cpanel-exclude.conf to the account(s)")
    parser.add_option("-b", "--backup",
                      action="store_true", dest="backup", default=False,
                      help="generate cPanel backup(s) for the account(s)")
    parser.add_option("-d", "--download",
                      action="store_true", dest="download", default=False,
                      help="download the most recently generated cPanel backup(s) for the accounts into the current directory")
    parser.add_option("-r", "--restore",
                      action="store_true", dest="restore", default=False,
                      help="restores the downloaded cPanel backup(s)")
    #Disabled. ptcheck is a better metric, and the postchecker doesn't do anything in here. May incorporate ptcheck into this sometime later.
    #parser.add_option("-p", "--post-transfer",
    #                  action="store_true", dest="postcheck", default=False,
    #                  help="run post-transfer check for the account(s)")
    parser.add_option("--cleanup",
                      action="store_true", dest="cleanup", default=False,
                      help="Removes the backup file generated by the script after downloading it")
    
    
    group = OptionGroup(parser, "Additional options")
    group.add_option("-t", "--threads", type="int", metavar="THREADS", dest="threads", default=2,
                      help="sets the number of concurrent threads to use for verifying login details (too many will cause problems, stick with the default) [default: %default]")
    #disabled. just generated the user lists to use the same password.
    #group.add_option("--resellerpass", metavar="PASSWORD", dest="respass",
    #                  help="[NOT YET IMPLEMENTED] use the provided reseller password to accessing the account(s)")
    group.add_option("-w", "--wait", type="int", metavar="WAITTIME", dest="waittime", default=15,
                      help="sets the wait time between each cPanel login attempt that ikea makes. IN SECONDS [default: %default seconds]")
    group.add_option("--no-collision",
                      action="store_true", dest="nocollision", default=False,
                      help="skip checking for domain name collisions")
    group.add_option("--no-ssl",
                      action="store_true", dest="nossl", default=False,
                      help="don't use SSL-secured connections [default: %default]")
    #group.add_option("-v", "--verbose",
    #                  action="store_true", dest="verbose", default=False,
    #                  help="verbose mode, spits out more data while working [default: %default]")
    group.add_option("--check-ftp", "-f", action="store_true", dest="ftpcheck", default=False, help="Enable checking for FTP access. USE ONLY WHEN YOU HAVE DIRECT ACCESS TO THE CPANEL ACCOUNTS [Default: %default]")
    #BIND IP
    group.add_option("--bind-address", "-i", type="string", metavar="BINDIP", dest="bindip", default=None, help="Bind the outgoing calls to the specified IP address. [default: the server's main IP address]")
    parser.add_option_group(group)

    return parser


def getInput():
    user_input = []
    entry = None
    while entry != "done":
        entry = raw_input("> ")
        user_input.append(entry)
    oldhost = None
    user = None
    accts = []
    for line in user_input:
        if line[:31] == "Your Primary Domain With Us: : ":
            break
        if line[:26] == "Old Hosting Account IP: : ":
            print line[26:].split(":")
            print urlparse(line[26:].split(":")[0])
            #oldhost = urlparse(line[26:].split(": : ")[0]
            print oldhost
        elif line[:29] == "The username to that site: : ":
            user = line[29:]
        elif line[:29] == "The password to that site: : ":
            if oldhost and user:
                print bcol.OKGREEN + "[+] " + bcol.ENDC +"Adding", oldhost, user, line[29:]
                accts.append(cPanel(oldhost, user, line[29:]))
                break
        elif line[:15] == "The username to":
            user = line.split(": : ")[1]
        elif line[:15] == "The password to":
            if oldhost and user:
                print bcol.OKGREEN + "[+] " + bcol.ENDC +"Adding", oldhost, user, line.split(": : ")[1]
                accts.append(cPanel(oldhost, user, line.split(": : ")[1]))
                user = None
    return accts


def main():
    print bcol.OKGREEN + "[$] " + bcol.ENDC + TITLE
    parser = optionHandler()
    (options, args) = parser.parse_args()

    if options.bindip:
        true_socket = socket.socket
        def bound_socket(*a, **k): 
            sock = true_socket(*a, **k)
            sock.bind((options.bindip, 0))
            return sock 
        socket.socket = bound_socket
    
    accts = []
    if len(args) == 1:
        if os.path.isfile(args[0]):
            uphlist = parseFile(args[0])
            for line in uphlist:
                accts.append(cPanel(line[0], line[1], line[2], not options.nossl, options.ftpcheck))
        else:
            print bcol.FAIL + "[!] " + bcol.ENDC + "The file '" + args[0] + "' does not exist."
            sys.exit(2)
    elif len(args) == 3:
        accts.append(cPanel(args[0], args[1], args[2], not options.nossl, options.ftpcheck))
    else:
        parser.print_help()
        sys.exit(2)
        print bcol.OKBLUE + "[*] " + bcol.ENDC +"Enter the server IP, account username, account password, separate by spaces on each line."
        print bcol.OKBLUE + "[*] " + bcol.ENDC +"Example:"
        print "\t127.0.0.1 bob p4ssw0rd"
        print bcol.OKBLUE + "[*] " + bcol.ENDC +"Or, alternatively, copy/paste the transfer form from the ticket."
        print bcol.OKBLUE + "[*] " + bcol.ENDC +"Enter 'done' on its own line to proceed:"
        accts = getInput()
        if len(accts) >= 1:
            options.check = True
        else:
            print bcol.WARNING + "[!] " + bcol.ENDC +"No valid accounts data provided, nothing to check. Use --help for more information"
            sys.exit(2)

    #hostname = gethostname().split('.', 1)
    #if hostname[1] == 'hostgator.com' and re.search("gator2\d\d\d$", hostname[0], re.I):
    if not re.search("^/home\d?/", os.getcwd(), re.I):
        print bcol.WARNING + "[!] " + bcol.ENDC + "IKEA must be run in a /home partition!"
        sys.exit(2)
    if (not options.precheck and not options.list and not options.backup and not options.skiphome
        and not options.restore and not options.download): #and not options.postcheck):
        parser.print_help()
        sys.exit(2)
    else:
        loginInfoChecker(accts, options.threads, options.waittime)
    
    if options.precheck:
        success = preCheck(accts)
        if success and not options.backup and not options.download and not options.list:
            print "\n" + bcol.OKBLUE + "[*] " + bcol.ENDC  + "Checks completed. Start backup/download process? Enter the typical backup/download options to processed ('s','b','d','r'). ctrl-c to exit:"
            userinput = raw_input("> ")
            if (len(userinput) > 4):
               print bcol.WARNING + "String length is too large to make any sense. Aborting..." + bcol.ENDC
               sys.exit(2)
            if ("s" in userinput):
                options.skiphome = True
            if ("b" in userinput):
                options.backup = True
            if ("d" in userinput):
                options.download = True
            if ("r" in userinput):
                options.restore = True
        
    if options.list:
        listBackups(accts)
    
    if options.backup:
        createBackups(accts, options.skiphome)
    
    if options.download:
        downloadBackups(accts, options.cleanup, options.skiphome, options.restore)
    
    if options.restore:
        restoreBackups(accts)
    
    #if options.postcheck:
    #    postCheck(accts)
    
    # Read and store some terminal-related values used to calculate the width of the header lines
    #rows, columns = os.popen('stty size', 'r').read().split()
    #rows, columns = int(rows), int(columns)
    closePorts() 
    return
