import os
import re
import sys
import threading

from Queue import Queue
from time import sleep
from helpers import bcol, ticker, calcWidth, getCols, checkSummary, openPorts
from subprocess import call

class LoginInfoWorker(threading.Thread):
    def __init__(self, queue):
        threading.Thread.__init__(self)
        self.queue = queue
    
    def run(self):
        while True:
            acct = self.queue.get()
            if acct is None:
                break
            acct.refreshInfo()
            if acct.cpanel:
                print bcol.OKGREEN + acct.username + bcol.ENDC, "checked..",
            else:
                if acct.ftp:
                    print bcol.WARNING + acct.username + bcol.ENDC, "checked..",
                else:
                    print bcol.FAIL + acct.username + bcol.ENDC, "checked..",


def loginInfoChecker(accts, threads, waittime):
    openPorts()
    try:
        t = ticker(bcol.OKBLUE + "[*] " + bcol.ENDC +"Making sure we can access the accounts..")
        t.__enter__()
        queue = Queue()
        for i in range(threads):
            LoginInfoWorker(queue).start()
        for index, acct in enumerate(accts):
            queue.put(acct)
            if (index != len(accts)-1):
                sleep(waittime)
        for i in range(threads):
            queue.put(None) # add end-of-queue markers
        while True:
            if queue.empty():
                print ' done.'
                return
            sleep(1)
    finally:
        t.__exit__()

def is_number(s):
    try:
        float(s)
        return True
    except:
        return False

def preCheck(accts):
    columns = getCols()
    success = False
    count = 1
    print
    print bcol.HEADER + "___Pre-Transfer check".ljust(columns, "_") + bcol.ENDC
    cols = calcWidth(columns, 32, 30, 11, 27)
    print "#  Primary Domain".ljust(cols[0]) + "User / Pass".ljust(cols[1]) + "Adns/DBs/@s".center(cols[2]) + "Disk usage  ".rjust(cols[3])
    aansi = re.compile(r'\x1B\[[^A-Za-z]*[A-Za-z]')
    
    checks = {"toobig": [],
              "nospace": [],
              "noaccess": [],
              "domains": {},
              "users":[]}

    totaldu = 0
    for acct in accts:
        checks["users"].append(acct.username)
        if len(acct.info["domains"]) >= 1:
            checks["domains"][acct.username] = acct.info["domains"]
            
        if not acct.ftp:
            userpass = bcol.WARNING + acct.username + " / " + acct.password + bcol.ENDC
            diskinfo = bcol.WARNING + "??? " + bcol.ENDC
            
        if not acct.cpanel:
            checks["noaccess"].append("U/P: " + bcol.HEADER + acct.username + " / " + acct.password + bcol.ENDC + " Server: " + bcol.WARNING + acct.server + bcol.ENDC)          
            userpass = bcol.FAIL + acct.username + " / " + acct.password + bcol.ENDC
            
        else:
            userpass = bcol.OKGREEN + acct.username + " / " + acct.password + bcol.ENDC
            if not len(acct.errors):
                success = True
            
        domain = bcol.HEADER + acct.info["primarydomain"] + bcol.ENDC
        hostname = bcol.HEADER + acct.info["hostname"] + bcol.ENDC
        
        du = acct.info["diskusage"]
        dl = acct.info["disklimit"]
        dup = acct.info["diskusageperc"]
        duu = acct.info["diskspaceunits"]
        if du and is_number(du): totaldu += float(du)
        numaddons = acct.info["numaddons"]
        dbs = acct.info["dbs"]
        emails = acct.info["numemails"]
        numaddons = acct.info["numaddons"]
        isreseller = acct.info["reseller"]

        if not numaddons: numaddons = "?"
        if not dbs: dbs = "?"
        if not emails: emails = "?"

        if dl == "unlimited": dl = "NA"
        if not du: du = "?"
        if not dl: dl = "?"
        if not dup: dup = "?"
        if not duu: duu = "?"
        diskinfo = bcol.WARNING
        
        if dup and dup != "?":
            if int(dup) > 60:
                diskinfo = bcol.WARNING
            if int(dup) > 75:
                checks["nospace"].append(acct.username)
                diskinfo = bcol.FAIL
            if int(dup) < 60:
                diskinfo = bcol.OKGREEN
        
        try:
            if float(du) > float(3500):
                checks["toobig"].append(acct.username)
                diskinfo = bcol.FAIL
        except ValueError:
            pass
        
        
        diskinfo = diskinfo + du + "/" + dl + " " + duu + " (" + str(dup) + "%) " + bcol.ENDC
        
        if not isreseller:
             c1 = str(count) + ". " + domain + " / " + hostname
        else:
             c1 = str(count) + ". " + bcol.FAIL + "(Reseller) " + bcol.ENDC + domain + " / " + hostname

        a1 = len(c1) - len(aansi.sub('', c1))

        c2 = unicode(userpass, encoding='utf-8')
        a2 = len(c2) - len(aansi.sub('', c2))

        c3 = numaddons + " / " + dbs + " / " + emails
        a3 = len(c3) - len(aansi.sub('', c3))

        c4 = diskinfo
        a4 = len(c4) - len(aansi.sub('', c4))

        print c1.ljust(cols[0] + a1) + c2.ljust(cols[1] + a2) + c3.center(cols[2] + a3) + c4.rjust(cols[3] + a4)

        if len(acct.errors):
            sys.stdout.write(bcol.FAIL)
            for error in acct.errors:
                print "   " + error
            sys.stdout.write(bcol.ENDC)

        count += 1

    c1 = "\nTotal Diskusage:"
    a1 = len(c1) - len(aansi.sub('', c1))

    c2 = "%s%.2f MB%s\n" % (bcol.FAIL, totaldu, bcol.ENDC)
    a2 = len(c2) - len(aansi.sub('', c2))

    print c1.ljust(cols[0] + a1) + "".ljust(cols[1]) + "".center(cols[2]) + c2.rjust(cols[3] + a2)
    checkSummary(checks)
    return success


def listBackups(accts):
    count = 1
    columns = getCols()
    print
    print bcol.HEADER + "___Available backups".ljust(columns, "_") + bcol.ENDC
    cols = calcWidth(columns, 32, 68)
    print "#  Primary Domain".ljust(cols[0]) + "Backups".ljust(cols[1])
    aansi = re.compile(r'\x1B\[[^A-Za-z]*[A-Za-z]')
    
    checks = {"toobig": [],
              "nospace": [],
              "noaccess": [],
              "domains": {},
              "users": []}
    
    for acct in accts:
        checks["users"].append(acct.username)
        if not len(acct.backups) >= 1:
            acct.getBackupList()
        
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
            break
        
        user = bcol.OKGREEN + "(" + acct.username + ")" + bcol.ENDC
        domain = bcol.HEADER + acct.info["primarydomain"] + bcol.ENDC + " " + user
        hostname = bcol.HEADER + acct.info["hostname"] + bcol.ENDC
 
        c1 = str(count) + ". " + domain + " / " + hostname
        a1 = len(c1) - len(aansi.sub('', c1))
        
        if acct.backups:
            if acct.backups[0]["status"] == "complete":
                c2 = bcol.OKGREEN + "complete: "
            elif acct.backups[0]["status"] == "inprogress":
                c2 = bcol.OKBLUE + "in progress: "
            else:
                c2 = bcol.FAIL + "failed: "
            c2 += acct.backups[0]["file"] + bcol.ENDC
            a2 = len(c2) - len(aansi.sub('', c2))
            
            print c1.ljust(cols[0] + a1) + c2.ljust(cols[1] + a2)
            if len(acct.backups) >= 2:
                for backup in acct.backups[1:]:
                    if backup["status"] == "complete":
                        c2 = bcol.OKGREEN + "complete: "
                    elif backup["status"] == "inprogress":
                        c2 = bcol.OKBLUE + "in progress: "
                    else:
                        c2 = bcol.FAIL + "failed: "
                    c2 += backup["file"] + bcol.ENDC
                    a2 = len(c2) - len(aansi.sub('', c2))
                    print ''.ljust(cols[0]) + c2.ljust(cols[1] + a2)
        
        count += 1
        
    checkSummary(checks)
