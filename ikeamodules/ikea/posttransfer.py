from os.path import exists
from subprocess import Popen

import os
import re
import sys

from helpers import bcol
from helpers import calcWidth
from helpers import getCols


def compare(source, dest):
    diff = False
    for k, v in source.items():
        v2 = dest.get(k, 0)
        if v != v2 :
            if not diff:
                diff = {}
            diff[k] = v, v2
    return diff


def postCheck(accts):
    columns = getCols()
    count = 1
    print
    print bcol.HEADER + "___Post-Transfer check".ljust(columns, "_") + bcol.ENDC
    cols = calcWidth(columns, 29, 18, 12, 12, 12, 17)
    print "#  Primary Domain".ljust(cols[0]) + "User".ljust(cols[1]) + "Domains".center(cols[2]) + "Databases".center(cols[3]) + "Email Accts".center(cols[4]) + "Disk Usage  ".rjust(cols[5])
    aansi = re.compile(r'\x1B\[[^A-Za-z]*[A-Za-z]')
    
    
    
    for acct in accts:
        if not acct.cpanel:
            domain = bcol.HEADER + acct.info["primarydomain"] + bcol.ENDC + " "
            c1 = str(count) + ". " + domain
            a1 = len(c1) - len(aansi.sub('', c1))
            c2 = bcol.FAIL + acct.username + bcol.ENDC
            a2 = len(c2) - len(aansi.sub('', c2))
            c3 = bcol.FAIL + "Unable to access the source account with the provided details" + bcol.ENDC
            a3 = len(c3) - len(aansi.sub('', c3))
            print c1.ljust(cols[0] + a1) + c2.ljust(cols[1] + a2) + c3.ljust(cols[1] + a3)
            break
        
        
        
        count += 1
    
    