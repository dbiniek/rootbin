###########
# Ikea
# Generates backups, downloads backups and restores backups from remote servers.
# https://confluence.endurance.com/display/HGS2/Migrations%3A+Ikea 
# Please submit all bug reports at jira.endurance.com
#
# (C) 2011 - HostGator.com, LLC
###########

import os
import sys
import threading
from os.path import exists
from subprocess import call


class ticker(threading.Thread):
    def __init__(self, msg):
        threading.Thread.__init__(self)
        self.msg = msg
        self.event = threading.Event()

    def __enter__(self):
        self.start()

    # Python 2.5: def __exit__(self, ex_type, ex_value, ex_traceback):
    def __exit__(self):
        self.event.set()
        self.join()

    def run(self):
        sys.stdout.write(self.msg)
        while not self.event.isSet():
            sys.stdout.write(".")
            sys.stdout.flush()
            self.event.wait(1)


class bcol:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    
    def disable(self):
        self.HEADER = ''
        self.OKBLUE = ''
        self.OKGREEN = ''
        self.WARNING = ''
        self.FAIL = ''
        self.ENDC = ''


def parseFile(filename):
    '''Quickly and dirtily 'parse' cPanel login details from a file and return it as a list.
    Each line should contain the following: server hostname/IP, cPanel username, cPanel password
    ie. 127.0.0.1 bob changeme
    '''
    lines = open(filename, "r").readlines()
    list = []
    l = 0
    try:
        for line in lines:
            l = l + 1
            if line[0] != "#":
                info = line.strip().split()
                if len(info) == 0:
                    pass
                elif len(info) < 3:
                    print bcol.WARNING + "[!] " + bcol.ENDC +"Warning, incomplete login details on line " + str(l) + ", \"" + bcol.ENDC + line.strip() + bcol.WARNING + "\", skipping entry" + bcol.ENDC
                else:
                    list.append([info[0], info[1], info[2]])
    except:
        print bcol.FAIL + "[!] " + bcol.ENDC + "Failed to parse cPanel access information from the provided file"
        return False
    return list


def calcWidth(columns, *args):
    perc = columns / 100.0
    cols = []    
    for arg in args:
        cols.append(int(round(perc * arg)))
    total = 0
    for col in cols:
        total += col
    if total > columns:
        cols[1] -= 1
    return cols


def getCols():
    rows, columns = os.popen('stty size', 'r').read().split()
    rows, columns = int(rows), int(columns)
    return columns


def domainExists(domain):
    for line in open("/etc/userdomains", "r"):
        (ldomain, luser) = line.split(":", 1)
        if domain.strip().lower() == ldomain.strip().lower():
            return luser.strip()
    return False

def userExists(user):
    if os.path.isfile("/var/cpanel/users/" + user):
        return True
    return False

def readHash():
    hash = "/root/.accesshash"
    if not exists(hash):
        call(["/usr/local/cpanel/bin/realmkaccesshash"], env={"REMOTE_USER": "root"})
    f = open(hash, "r")
    hash = f.read().replace("\n", "").rstrip()
    auth = "WHM root:" + hash
    return auth

def checkSummary(checks):
    if len(checks["noaccess"]) >= 1:
        print
        print "The login details for the following cPanel accounts appear to be incorrect:"
        for entry in checks["noaccess"]:
            print entry
    
    if len(checks["toobig"]) >= 1:
        print
        print "The following accounts are too big to reliably back up through cPanel:"
        for user in checks["toobig"]:
            print bcol.HEADER + user + bcol.ENDC
        
    if len(checks["nospace"]) >= 1:
        print
        print "The following accounts are at or too close to their disk space quotas:"
        for user in checks["nospace"]:
            print bcol.HEADER + user + bcol.ENDC
        
    if len(checks["domains"]) >= 1:
        collide = False
        try:
            for u, d in checks["domains"].iteritems():
                for line in open("/etc/userdomains", "r"):
                    (ldomain, luser) = line.split(":", 1)
                    ldomain = ldomain.strip().lower()
                    for mdomain in d:
                        if mdomain.strip().lower() == ldomain:
                            if not collide:
                                print
                                print "Domain name collisions! The following domains already exist on the server:"
                                collide = True
                            print bcol.FAIL + ldomain + " (" + u + "), owned by " + luser.strip() + bcol.ENDC
        except IOError:
            print "Skipping domain name collision checking as /etc/userdomains does not exist"
    
    if len(checks["users"]) >= 1:
        ucollide = False
        for user in checks["users"]:
            if exists("/var/cpanel/users/" + user):
                if not ucollide:
                    print
                    print "The following usernames already exists on the server:"
                    ucollide = True
                print bcol.FAIL + user + bcol.ENDC
    
    return

def echo(string, color=None, sl=False):
    return
         
def openPorts():

    if os.geteuid() == 0:
        #2082
        call(['/sbin/iptables','-I','INPUT','-p','tcp','-m','tcp','--dport', '1024:65535','--sport','2082','-j','ACCEPT'])
        call(['/sbin/iptables','-I','OUTPUT','-p','tcp','-m','tcp','--sport', '1024:65535','--dport','2082','-j','ACCEPT'])
        call(['/sbin/iptables','-I','INPUT','-p','udp','-m','udp','--dport', '1024:65535','--sport','2082','-j','ACCEPT'])
        call(['/sbin/iptables','-I','OUTPUT','-p','udp','-m','udp','--sport', '1024:65535','--dport','2082','-j','ACCEPT'])
        #2083
        call(['/sbin/iptables','-I','INPUT','-p','tcp','-m','tcp','--dport', '1024:65535','--sport','2083','-j','ACCEPT']) 
        call(['/sbin/iptables','-I','OUTPUT','-p','tcp','-m','tcp','--sport', '1024:65535','--dport','2083','-j','ACCEPT'])
        call(['/sbin/iptables','-I','INPUT','-p','udp','-m','udp','--dport', '1024:65535','--sport','2083','-j','ACCEPT'])
        call(['/sbin/iptables','-I','OUTPUT','-p','udp','-m','udp','--sport', '1024:65535','--dport','2083','-j','ACCEPT'])
        #2086
        #call(['/sbin/iptables','-I','INPUT','-p','tcp','-m','tcp','--dport', '1024:65535','--sport','2086','-j','ACCEPT']) 
        #call(['/sbin/iptables','-I','OUTPUT','-p','tcp','-m','tcp','--sport', '1024:65535','--dport','2086','-j','ACCEPT'])
        #call(['/sbin/iptables','-I','INPUT','-p','udp','-m','udp','--dport', '1024:65535','--sport','2086','-j','ACCEPT'])
        #call(['/sbin/iptables','-I','OUTPUT','-p','udp','-m','udp','--sport', '1024:65535','--dport','2086','-j','ACCEPT'])
        #2087
        #call(['/sbin/iptables','-I','INPUT','-p','tcp','-m','tcp','--dport', '1024:65535','--sport','2087','-j','ACCEPT']) 
        #call(['/sbin/iptables','-I','OUTPUT','-p','tcp','-m','tcp','--sport', '1024:65535','--dport','2087','-j','ACCEPT'])
        #call(['/sbin/iptables','-I','INPUT','-p','udp','-m','udp','--dport', '1024:65535','--sport','2087','-j','ACCEPT'])
        #call(['/sbin/iptables','-I','OUTPUT','-p','udp','-m','udp','--sport', '1024:65535','--dport','2087','-j','ACCEPT'])
        return
    else:
	print bcol.WARNING + "[!] " + bcol.ENDC + "Not running as root... Unable to open ports on my own :("
        return

def closePorts():

    if os.geteuid() == 0:
        #2082
        call(['/sbin/iptables','-D','INPUT','-p','tcp','-m','tcp','--dport', '1024:65535','--sport','2082','-j','ACCEPT'])
        call(['/sbin/iptables','-D','OUTPUT','-p','tcp','-m','tcp','--sport', '1024:65535','--dport','2082','-j','ACCEPT'])
        call(['/sbin/iptables','-D','INPUT','-p','udp','-m','udp','--dport', '1024:65535','--sport','2082','-j','ACCEPT'])
        call(['/sbin/iptables','-D','OUTPUT','-p','udp','-m','udp','--sport', '1024:65535','--dport','2082','-j','ACCEPT'])
        #2083
        call(['/sbin/iptables','-D','INPUT','-p','tcp','-m','tcp','--dport', '1024:65535','--sport','2083','-j','ACCEPT'])
        call(['/sbin/iptables','-D','OUTPUT','-p','tcp','-m','tcp','--sport', '1024:65535','--dport','2083','-j','ACCEPT'])
        call(['/sbin/iptables','-D','INPUT','-p','udp','-m','udp','--dport', '1024:65535','--sport','2083','-j','ACCEPT'])
        call(['/sbin/iptables','-D','OUTPUT','-p','udp','-m','udp','--sport', '1024:65535','--dport','2083','-j','ACCEPT'])

    return
