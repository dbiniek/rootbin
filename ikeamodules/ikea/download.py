###########
# Ikea
# Generates backups, downloads backups and restores backups from remote servers.
# https://confluence.endurance.com/display/HGS2/Migrations%3A+Ikea 
# Please submit all bug reports at jira.endurance.com
#
# (C) 2011 - HostGator.com, LLC
###########

import re
import os

from helpers import bcol
from helpers import calcWidth
from helpers import getCols
from helpers import checkSummary

from urllib2 import Request, urlopen, URLError, HTTPError
from urllib import quote

import shutil
from shutil import move
from time import strftime

def downloadBackups(accts, cleanup=False, skiphome=False, restore=False):
    columns = getCols()
    count = 1
    print
    print bcol.HEADER + "___Downloading backups".ljust(columns, "_") + bcol.ENDC
    cols = calcWidth(columns, 32, 68)
    print "#  Primary Domain".ljust(cols[0]) + "Backup".ljust(cols[1])
    aansi = re.compile(r'\x1B\[[^A-Za-z]*[A-Za-z]')
    
    checks = {"toobig": [],
              "nospace": [],
              "noaccess": [],
              "domains": {},
              "users": []}
    
    backupfiles = []
    for acct in accts:
        checks["users"].append(acct.username)
        if len(acct.info["domains"]) >= 1:
            checks["domains"][acct.username] = acct.info["domains"]
            
        
        if not acct.cpanel:
            checks["noaccess"].append("U/P: " + bcol.HEADER + acct.username + " / " + acct.password + bcol.ENDC + " Server: " + bcol.WARNING + acct.server + bcol.ENDC)
            user = bcol.FAIL + "(" + acct.username + ")" + bcol.ENDC
            domain = bcol.HEADER + acct.info["primarydomain"] + bcol.ENDC + " " + user
            c1 = str(count) + ". " + domain
            a1 = len(c1) - len(aansi.sub('', c1))
            c2 = bcol.FAIL + "Unable to access the cPanel account with the provided details" + bcol.ENDC
            a2 = len(c2) - len(aansi.sub('', c2))
            print c1.ljust(cols[0] + a1) + c2.ljust(cols[1] + a2)
            continue
        
        user = bcol.OKGREEN + "(" + acct.username + ")" + bcol.ENDC
        domain = bcol.HEADER + acct.info["primarydomain"] + bcol.ENDC + " " + user

        if re.search("hostgator.com$", acct.info["hostname"], re.I) or re.search("hostgator.com.tr$", acct.info["hostname"], re.I) or re.search("hostgator.in$", acct.info["hostname"], re.I) or re.search("webhostsunucusu.com$", acct.info["hostname"], re.I) or re.search("websitedns.in$", acct.info["hostname"], re.I):
            c1 = str(count) + ". " + domain
            a1 = len(c1) - len(aansi.sub('', c1))
#           changed to warning per EMC-1949
            c2 = bcol.FAIL + "Hostgator server detected. Are you sure you are using the right tool?" + bcol.ENDC
#            c2 = bcol.FAIL + "Hostgator server detected. Skipping.." + bcol.ENDC
            a2 = len(c2) - len(aansi.sub('', c2))
            print c1.ljust(cols[0] + a1) + c2.ljust(cols[1] + a2)
#            continue
        
        if not len(acct.backups) >= 1:
            acct.getBackupList()
        if len(acct.backups) >= 1:
            local_file = None
            backup = acct.backups[0]["file"]
            c1 = str(count) + ". " + domain
            a1 = len(c1) - len(aansi.sub('', c1))
            c2 = bcol.OKBLUE + backup + bcol.ENDC
            a2 = len(c2) - len(aansi.sub('', c2))
            print c1.ljust(cols[0] + a1) + c2.ljust(cols[1] + a2)
            
            try:
                if os.path.isfile(backup):
                    c2 = bcol.WARNING + "!!! " + backup + " already exists in current directory" + bcol.ENDC
                    a2 = len(c2) - len(aansi.sub('', c2))
                    print c1.ljust(cols[0] + a1) + c2.ljust(cols[1] + a2)
                    newbackup = backup + ".bak" + strftime("%m%d%H%M")
                    move(backup, newbackup)
                    c2 = bcol.OKGREEN + "-> " + backup + " moved to " + newbackup + bcol.ENDC
                    a2 = len(c2) - len(aansi.sub('', c2))
                    print c1.ljust(cols[0] + a1) + c2.ljust(cols[1] + a2)

                if acct.ftp:
                    local_file = downloadFTPfile(backup, acct.username, acct.password, acct.server)
                    acct.backupfile = backup
                else:
                    if acct.info["ssl"]:
                        url = "https://%s:2083/download?file=%s" % (acct.server, backup)
                    else:
                        url = "http://%s:2082/download?file=%s" % (acct.server, backup)

                    c2 = bcol.OKBLUE + backup + " now downloading... " + bcol.ENDC
                    a2 = len(c2) - len(aansi.sub('', c2))
                    print c1.ljust(cols[0] + a1) + c2.ljust(cols[1] + a2)

                    local_file = downloadfile(backup, url, acct.authheader)
                    acct.backupfile = backup
                    c2 = bcol.OKGREEN + "-> " + backup + " downloaded" + bcol.ENDC
                    a2 = len(c2) - len(aansi.sub('', c2))
                    print c1.ljust(cols[0] + a1) + c2.ljust(cols[1] + a2)
                if restore and os.path.isfile(local_file):
                        acct.dledfile = os.path.abspath(local_file)

                if cleanup:
                    acct.removeFile(backup)
                    c2 = bcol.OKBLUE + "-> Cleanup: " + backup + " removed from the source account" + bcol.ENDC
                    a2 = len(c2) - len(aansi.sub('', c2))
                    print c1.ljust(cols[0] + a1) + c2.ljust(cols[1] + a2)
            except:
                raise
    checkSummary(checks)
    
    return backupfiles

def downloadfile(file_name,url, auth=None):

     req = Request(url)
     if auth:
         req.add_header("Authorization", auth)

     # Open the url
     try:
         r = urlopen(req)
         fp = open(file_name, 'wb', 104857600)
         shutil.copyfileobj(r, fp)

     #handle errors
     except HTTPError, e:
         print "HTTP Error:",e.code , url
     except URLError, e:
         print "URL Error:",e.reason , url

     return os.path.abspath(file_name)

def downloadFTPfile(file_name, username, password, server):

     from ftplib import FTP
     ftp = FTP(server)
     ftp.login(username, password)

     fp = open(file_name, 'wb', 104857600)
     ftp.retrbinary("RETR " + file_name, fp.write)
     ftp.close()

     return os.path.abspath(file_name)
