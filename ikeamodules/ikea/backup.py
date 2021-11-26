###########
# Ikea
# Generates backups, downloads backups and restores backups from remote servers.
# https://confluence.endurance.com/display/HGS2/Migrations%3A+Ikea 
# Please submit all bug reports at jira.endurance.com
#
# (C) 2011 - HostGator.com, LLC
###########

import re
import sys
import time
import random
from helpers import bcol
from helpers import calcWidth
from helpers import getCols
from time import strftime
from urllib2 import Request, urlopen, URLError, HTTPError
from urllib import quote

def createBackups(accts, shome=False):
    """Loop through accounts and generate backups"""
    columns = getCols()
    count = 1
    print
    print bcol.HEADER + "___Backup creation".ljust(columns, "_") + bcol.ENDC
    cols = calcWidth(columns, 32, 60, 8)
    print "#  Primary Domain (username)".ljust(cols[0]) + "Status".ljust(cols[1]) + "Time ".rjust(cols[2])
    aansi = re.compile(r'\x1B\[[^A-Za-z]*[A-Za-z]')
    wgets = []
    
    for acct in accts:
        try:
            if acct.backups[0]['file']:
                mostrecentoldbackup = acct.backups[0]['file']
        except IndexError:
            mostrecentoldbackup = None
            pass
        else:
            mostrecentoldbackup = None
        
        checkagain = []
        
        if not acct.cpanel:
            c1 = str(count) + ". " + bcol.HEADER + acct.info["primarydomain"] + bcol.ENDC + bcol.FAIL + " (" + acct.username + ")" + bcol.ENDC
            a1 = len(c1) - len(aansi.sub('', c1))
            c2 = bcol.FAIL + "Bad cPanel login details, skipping.." + bcol.ENDC
            a2 = len(c2) - len(aansi.sub('', c2))
            print c1.ljust(cols[0] + a1) + c2.ljust(cols[1] + a2)
            continue

        c1 = str(count) + ". " + bcol.HEADER + acct.info["primarydomain"] + bcol.ENDC + bcol.OKGREEN + " (" + acct.username + ")" + bcol.ENDC
        a1 = len(c1) - len(aansi.sub('', c1))

        if re.search("hostgator.com$", acct.info["hostname"], re.I) or re.search("hostgator.com.tr$", acct.info["hostname"], re.I) or re.search("hostgator.in$", acct.info["hostname"], re.I) or re.search("webhostsunucusu.com$", acct.info["hostname"], re.I) or re.search("websitedns.in$", acct.info["hostname"], re.I):
#	    changed to warning per EMC-1949
	    c2 = bcol.WARNING + "Hostgator server detected. Are you sure you are using the right tool?" + bcol.ENDC
#	    c2 = bcol.FAIL + "Hostgator server detected. Skipping.." + bcol.ENDC
            a2 = len(c2) - len(aansi.sub('', c2))
            print c1.ljust(cols[0] + a1) + c2.ljust(cols[1] + a2)
#            continue

        if shome:
            test = skiphome(acct, count)
            if not test:
                c2 = bcol.WARNING + "Failed to create cpbackup-exclude.conf. Skipping..." + bcol.ENDC
                a2 = len(c2) - len(aansi.sub('', c2))
                print c1.ljust(cols[0] + a1) + c2.ljust(cols[1] + a2)
                continue

        if acct.startBackup():
            
            c2 = bcol.WARNING + "Request sent, waiting for it to take.." + bcol.ENDC
            
            starttime = time.time()
            failcount = 0
            done = False
            ttc = starttime + 5
            
            while not done:
                
                curtime = time.time()
                tdiff = curtime - starttime
                
                if curtime >= ttc:
                    ttc = curtime + random.randint(10, 25)
                    if acct.getBackupList():
                        if len(acct.backups) >= 1:
                            if acct.backups[0]['status'] == "complete":
                                if not acct.backups[0]['file'] == mostrecentoldbackup:
                                    c2 = bcol.OKGREEN + "Complete: " + acct.backups[0]['file'] + bcol.ENDC
                                    done = True
                            elif acct.backups[0]['status'] == "inprogress":
                                started = True
                                c2 = bcol.OKBLUE + "Process started and verified.. (" + acct.backups[0]['file'] + ")" + bcol.ENDC
                            elif acct.backups[0]['status'] == "timeout":
                                failcount += 1
                                c2 = bcol.WARNING + "Backup timed out server-side, will check again.. (" + str(failcount) + ")"+ bcol.ENDC
                    else:
                        if failcount >= 10:
                            c2 = bcol.FAIL + "Failed getting list of backups from the server, backup may still have been started." + bcol.ENDC
                            done = True
                        else:
                            failcount += 1
                            c2 = bcol.WARNING + "Unable to get list of backups, will check again.. (retry " + str(failcount) + ")"+ bcol.ENDC
                            
                a2 = len(c2) - len(aansi.sub('', c2))
                
                if tdiff >= 60:
                    c3 = "%02dm %02ds " % (divmod(tdiff, 60))
                else:
                    c3 = "%02ds " % (tdiff)
                a3 = len(c3) - len(aansi.sub('', c3))
                
                print c1.ljust(cols[0] + a1) + c2.ljust(cols[1] + a2) + c3.rjust(cols[2] + a3) + "\r",
                sys.stdout.flush()
                time.sleep(1)
            print

        if shome or acct.info["movedcpbackup"]:
            undoshome(acct, count)

        count += 1

def skiphome(acct, count):

    columns = getCols()
    cols = calcWidth(columns, 32, 68)
    aansi = re.compile(r'\x1B\[[^A-Za-z]*[A-Za-z]')
    checks = {"toobig": [],
              "nospace": [],
              "noaccess": [],
              "domains": {},
              "users": []}

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
        return 0

    user = bcol.OKGREEN + "(" + acct.username + ")" + bcol.ENDC
    domain = bcol.HEADER + acct.info["primarydomain"] + bcol.ENDC + " " + user

    if re.search("hostgator.com$", acct.info["hostname"], re.I) or re.search("hostgator.com.tr$", acct.info["hostname"], re.I) or re.search("hostgator.in$", acct.info["hostname"], re.I) or re.search("webhostsunucusu.com$", acct.info["hostname"], re.I) or re.search("websitedns.in$", acct.info["hostname"], re.I):
        c1 = str(count) + ". " + domain
        a1 = len(c1) - len(aansi.sub('', c1))
#        c2 = bcol.FAIL + "Hostgator server detected. Skipping.." + bcol.ENDC
#	changing to warning per EMC-1949
	c2 = bcol.WARNING + "Hostgator server detected. Are you sure you are using the right tool?" + bcol.ENDC
        a2 = len(c2) - len(aansi.sub('', c2))
        print c1.ljust(cols[0] + a1) + c2.ljust(cols[1] + a2)
#        return 0

    if skipcheck(acct):
        c1 = str(count) + ". " + domain
        a1 = len(c1) - len(aansi.sub('', c1))
        c2 = bcol.OKBLUE + '-> Uploaded cpbackup-exclude.conf' + bcol.ENDC
        a2 = len(c2) - len(aansi.sub('', c2))
        print c1.ljust(cols[0] + a1) + c2.ljust(cols[1] + a2)

        if acct.info["ssl"]:
            url = "https://%s:2083/" % acct.server
        else:
            url = "https://%s:2082/" % acct.server

        url += "json-api/cpanel?cpanel_jsonapi_user=%s&cpanel_jsonapi_apiversion=2&cpanel_jsonapi_module=Fileman" % acct.username
        url += "&cpanel_jsonapi_func=savefile&dir=&filename=cpbackup-exclude.conf&content=%s" % '*'
        req = Request(url)
        req.add_header("Authorization", acct.authheader)
        urlopen(req)
        acct.skiphome = True
        return 1
    else:
        c1 = str(count) + ". " + domain
        a1 = len(c1) - len(aansi.sub('', c1))
        c2 = bcol.OKBLUE + 'It appears that placing a cpbackup-exclude.conf failed' + bcol.ENDC
        a2 = len(c2) - len(aansi.sub('', c2))
        print c1.ljust(cols[0] + a1) + c2.ljust(cols[1] + a2)
        return 0
    
def skipcheck (acct):
    #just attempt to the download the file and parse it. cPanel's viewfile is cumbersome and unneeded.
    try:
        if acct.info["ssl"]:
            baseurl = "https://%s:2083" % (acct.server)
        else:
            baseurl = "https://%s:2082" % (acct.server)

        url = baseurl + "/download?file=%s" % ("cpbackup-exclude.conf")
        req = Request(url)
        req.add_header("Authorization", acct.authheader)

        f = urlopen(req)
        for line in f:
            if not line.strip():
                continue
            elif line.strip() != "*":
                acct.info["movedcpbackup"] = "cpbackup-exclude.conf.bak" + strftime("%m%d%H%M")
                try:
                    data = acct.moveFile("cpbackup-exclude.conf", acct.info["movedcpbackup"])
                    dresult = data["cpanelresult"]["data"]
                    for piece in dresult:
                        success = piece["result"][0]
                except:
                    return 0

                if success:
                    return 1
                else:
                    return 0

    except HTTPError, e:
    #if http error occurs, ie, file not found, etc, just overwrite it
        return 1

    return 1

def undoshome (acct, count):

    columns = getCols()
    cols = calcWidth(columns, 32, 68)
    aansi = re.compile(r'\x1B\[[^A-Za-z]*[A-Za-z]')
    checks = {"toobig": [],
              "nospace": [],
              "noaccess": [],
              "domains": {},
              "users": []}

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
        return

    user = bcol.OKGREEN + "(" + acct.username + ")" + bcol.ENDC
    domain = bcol.HEADER + acct.info["primarydomain"] + bcol.ENDC + " " + user

    if re.search("hostgator.com$", acct.info["hostname"], re.I) or re.search("hostgator.com.tr$", acct.info["hostname"], re.I) or re.search("hostgator.in$", acct.info["hostname"], re.I) or re.search("webhostsunucusu.com$", acct.info["hostname"], re.I) or re.search("websitedns.in$", acct.info["hostname"], re.I):
        c1 = str(count) + ". " + domain
        a1 = len(c1) - len(aansi.sub('', c1))
#       changed to warning per EMC-1949
        c2 = bcol.WARNING + "Hostgator server detected. Are you sure you are using the right tool?" + bcol.ENDC
#        c2 = bcol.FAIL + "Hostgator server detected. Skipping.." + bcol.ENDC
        a2 = len(c2) - len(aansi.sub('', c2))
        print c1.ljust(cols[0] + a1) + c2.ljust(cols[1] + a2)
#        return

    if acct.skiphome:
       acct.removeFile("cpbackup-exclude.conf")
       c1 = str(count) + ". " + domain
       a1 = len(c1) - len(aansi.sub('', c1))
       c2 = bcol.OKBLUE + "-> Removed the cpbackup-exclude.conf" + bcol.ENDC
       a2 = len(c2) - len(aansi.sub('', c2))
       print c1.ljust(cols[0] + a1) + c2.ljust(cols[1] + a2)
       if acct.info["movedcpbackup"]:
            acct.moveFile(acct.info["movedcpbackup"], "cpbackup-exclude.conf")
            c2 = bcol.OKBLUE + "-> Restored original cpbackup-exclude.conf" + bcol.ENDC
            a2 = len(c2) - len(aansi.sub('', c2))
            print c1.ljust(cols[0] + a1) + c2.ljust(cols[1] + a2)
            return
