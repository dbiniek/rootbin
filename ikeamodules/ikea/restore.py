import re
import os
import sys
import glob
import time
from subprocess import Popen, PIPE
from socket import gethostname

from helpers import bcol
from helpers import calcWidth
from helpers import getCols
from helpers import domainExists
from helpers import userExists


def restoreStatus(line):
    steps = [("Extracting tarball", "Extracting data from backup.."),  
             ("Extracting Domain", "Extracting domain information from backup.."),
             ("Generating Account", "Generating cPanel account.."),
             ("Restoring MySQL databases", "Restoring MySQL databases.."),
             ("Restoring Mailman lists", "Restoring Mailman lists.."),
             ("Restoring Mailman Archives", "Restoring Mailman archives.."),
             ("Restoring Domains", "Restoring domains.."),
             ("Rebuilding Apache Conf", "Rebuilding Apache configuration file.."),
             ("Restoring Homedir", "Restoring home directory.."),
             ("Restoring Mail files", "Restoring mail files.."),
             ("Restoring Dns Zones", "Restoring DNS zones.."),
             ("Account Restore Complete", "Account restore complete..")]
    for step in steps:
        if not line.lower().find(step[0].lower()) == -1:
            return step[1]
    return False


def preRestoreCheck(acct):
    errors = []
    #globz = "/home/*%s.tar.gz" % acct.username
    #filelist = glob.glob(globz)
    #if len(filelist) > 1:
    #    errors.append("More than one backup file founnd for %s in /home/" % acct.username)
    if not acct.dledfile:
        errors.append("No downloaded backup file found. If you downloaded the file previously, please use /scripts/restorepkg manually.")
 
    for domain in acct.info["domains"]:
        domainowner = None
        domainowner = domainExists(domain)
        if domainowner:
            errors.append("The domain %s already exists on the server and is owned by %s" % (domain, domainowner))
    
    if userExists(acct.username):
        errors.append("The user %s already exists on the server" % acct.username)
    
    return errors

def restoreBackups(accts, backups=[]):
    columns = getCols()
    count = 1
    print
    print bcol.HEADER + "___Restoring backups".ljust(columns, "_") + bcol.ENDC
    cols = calcWidth(columns, 32, 68)
    print "#  Primary Domain".ljust(cols[0]) + "Status".ljust(cols[1])
    aansi = re.compile(r'\x1B\[[^A-Za-z]*[A-Za-z]')
    
    for acct in accts:
        errors = preRestoreCheck(acct)
        
        user = bcol.OKGREEN + "(" + acct.username + ")" + bcol.ENDC
        domain = bcol.HEADER + acct.info["primarydomain"] + bcol.ENDC + " " + user
        
        c1 = str(count) + ". " + domain
        a1 = len(c1) - len(aansi.sub('', c1))
        
        if len(errors) >= 1:
            c2 = bcol.WARNING + "Skipped " + errors[0] + bcol.ENDC
            a2 = len(c2) - len(aansi.sub('', c2))
            print c1.ljust(cols[0] + a1) + c2.ljust(cols[1] + a2)
            continue

#as of cPanel 11.44, restorepgk skips reseller privleges by default        
#        hgservers = ['hostgator.com', 'websitewelcome.com']
#        if gethostname().split('.', 1)[1] in hgservers:
#            cmd = "/scripts/restorepkg --skipres %s" % acct.dledfile
#            c2 = bcol.OKBLUE + "Starting restore process (skipping reseller privileges)" + bcol.ENDC
#            a2 = len(c2) - len(aansi.sub('', c2))
#            print c1.ljust(cols[0] + a1) + c2.ljust(cols[1] + a2)
#            c2 = bcol.OKBLUE + "Running command: " + cmd + bcol.ENDC
#            a2 = len(c2) - len(aansi.sub('', c2))
#            print c1.ljust(cols[0] + a1) + c2.ljust(cols[1] + a2)
#            sys.stdout.flush()
#            time.sleep(3)
#        else:
        cmd = "/scripts/restorepkg %s" % acct.dledfile
        c2 = bcol.OKBLUE + "Starting restore process" + bcol.ENDC
        a2 = len(c2) - len(aansi.sub('', c2))
        print c1.ljust(cols[0] + a1) + c2.ljust(cols[1] + a2)
        c2 = bcol.OKBLUE + "Running command: " + cmd + bcol.ENDC
        a2 = len(c2) - len(aansi.sub('', c2))
        print c1.ljust(cols[0] + a1) + c2.ljust(cols[1] + a2)
        sys.stdout.flush()
        time.sleep(3)

        try:
            p = Popen(cmd.split(),stdout=PIPE, stderr=PIPE)
            log = []
            while True:
                o = p.stdout.readline()
                log.append(o)
                if o == '' and p.poll() != None: break
                st = restoreStatus(o)
                if st:
                    c2 = bcol.OKBLUE + st + bcol.ENDC
                    a2 = len(c2) - len(aansi.sub('', c2))
                print c1.ljust(cols[0] + a1) + c2.ljust(cols[1] + a2) + "\r",
                sys.stdout.flush()
            if userExists(acct.username) and domainExists(acct.info["primarydomain"]):
                c2 = bcol.OKGREEN + "Account restore completed." + bcol.ENDC
                a2 = len(c2) - len(aansi.sub('', c2))
                print c1.ljust(cols[0] + a1) + c2.ljust(cols[1] + a2)
            else:
                file = open(acct.username + ".log", "a")
                file.write(os.linesep.join(log))
                file.close()
                c2 = bcol.FAIL + "Account restore failed, consult %s.log for more information" % (acct.username) + bcol.ENDC
                a2 = len(c2) - len(aansi.sub('', c2))
                print c1.ljust(cols[0] + a1) + c2.ljust(cols[1] + a2)
        except:
            raise
        
        count += 1
