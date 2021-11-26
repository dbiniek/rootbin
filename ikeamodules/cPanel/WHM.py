###########
# Ikea
# Generates backups, downloads backups and restores backups from remote servers.
# https://confluence.endurance.com/display/HGS2/Migrations%3A+Ikea 
# Please submit all bug reports at jira.endurance.com
#
# (C) 2011 - HostGator.com, LLC
###########

from cPanel import cPanel
from base64 import encodestring
import urllib2
from helpers import xmlToDict
import xml.parsers.expat

class WHM(cPanel):
    '''
    Class object for a WHM account, root or reseller.
    '''
    def __init__(self, server, username, password='', hash=None, ssl=True, port=2086):
        cPanel.__init__(self, server, username, password, ssl=ssl, port=port)
        self.whm = False

        if hash:
            self.authheader = "WHM " + username + ":" + hash
        else:
            base64string = encodestring('%s:%s' % (username, password))[:-1]
            self.authheader = "Basic %s" % base64string
    
    
    def checkInfo(self):
        self.whm = False
        try:
            url = self.baseurl
            url += "/xml-api/myprivs"
            req = urllib2.Request(url)
            req.add_header("Authorization", self.authheader)
            handle = urllib2.urlopen(req)
            data = None
            data = handle.read()
        except urllib2.URLError, e:
            if hasattr(e, 'reason'):
                self.errors.append("WHM: " + str(e.reason))
            elif hasattr(e, 'code'):
                if e.code == 401:
                    self.errors.append("WHM: Invalid username and/or password")
                elif e.code == 403:
                    self.errors.append("WHM: Could not access WHM due to a '403 Forbidden' error")
                else:
                    raise
        else:
            self.whm = True
        
        return self.whm
    
    def getSummary(self, account):
        '''
        Returns a tuple of the XML representation of the accountsummary data for
        the requested account and any errors encountered.
        '''
        errors = []
        try:
            url = self.baseurl
            url += "/xml-api/accountsummary?user=%s" % account
            req = urllib2.Request(url)
            req.add_header("Authorization", self.authheader)
            handle = urllib2.urlopen(req)
            data = handle.read()
        except urllib2.URLError, e:
            if hasattr(e, 'reason'):
                errors.append("WHM: " + str(e.reason))
            elif hasattr(e, 'code'):
                if e.code == 401:
                    errors.append("WHM: Invalid access details")
                elif e.code == 403:
                    errors.append("WHM: Could not access WHM due to a '403 Forbidden' error")
                else:
                    raise
        try:
            data = xmlToDict(data)
        except:
            errors.append("WHM: failed to fetch account information from server, server returned garbage XML data")
        return data["acct"][0], errors
    
    
#    def getInfo(self, account):
#        errors = []
#        info = {}
#        try:
#            url = self.baseurl
#            url += "/xml-api/cpanel?user=%s&cpanel_xmlapi_module=StatsBar&cpanel_xmlapi_func=stat" % self.username
#            url += "&display=diskusage|addondomains|sqldatabases||emailaccounts|theme&cpanel_xmlapi_apiversion=2"
#            req = urllib2.Request(url)
#            req.add_header("Authorization", self.authheader)
#            handle = urllib2.urlopen(req)
#            data = None
#            data = handle.read()
#            
#            try:
#                dresult = None
#                dresult = xmlToDict(data)["data"]
#            except:
#                errors.append("cPanel: failed to fetch account information from server, server returned garbage XML data")
#                dresult = None
#            
#            if dresult:
#                try:
#                    for piece in dresult:
#                        if piece["name"][0] == "sqldatabases":
#                            info["dbs"] = piece["_count"][0]
#                        elif piece["name"][0] == "addondomains":
#                            info["numaddons"] = piece["_count"][0]
#                        elif piece["name"][0] == "emailaccounts":
#                            info["numemails"] = piece["_count"][0]
#                        elif piece["name"][0] == "diskusage":
#                            info["diskusage"] = piece["_count"][0]
#                            info["disklimit"] = piece["_max"][0]
#                            info["diskspaceunits"] = piece["units"][0]
#                            info["diskusageperc"] = piece["percent"][0]
#                except KeyError:
#                    pass
#            
#            url = self.baseurl + "/xml-api/cpanel?cpanel_xmlapi_apiversion=1&cpanel_xmlapi_module=print&arg-0=DOMAIN"
#            req = urllib2.Request(url)
#            req.add_header("Authorization", self.authheader)
#            handle = urllib2.urlopen(req)
#            data = None
#            data = handle.read()
#            
#            try:
#                dresult = None
#                dresult = xmlToDict(data)["data"]
#            except:
#                errors.append("cPanel: failed to check primary domain, server returned garbage XML data")
#            
#            if dresult:
#                try:
#                    for piece in dresult:
#                        info["primarydomain"] = piece["result"][0]
#                        info["domains"].append(piece["result"][0])
#                except KeyError:
#                    pass
#            
#            
#            url = self.baseurl
#            url += "/xml-api/cpanel?user=%s&cpanel_xmlapi_apiversion=2" % self.username
#            url += "&cpanel_xmlapi_module=AddonDomain&cpanel_xmlapi_func=listaddondomains"
#            req = urllib2.Request(url)
#            req.add_header("Authorization", self.authheader)
#            handle = urllib2.urlopen(req)
#            data = None
#            data = handle.read()
#            
#            try:
#                dresult = None
#                dresult = xmlToDict(data)["data"]
#                for piece in dresult:
#                    info["domains"].append(piece["domain"][0])
#            except KeyError:
#                pass
#            except xml.parsers.expat.ExpatError:
#                errors.append("cPanel: failed fetching addon domain information, server returned garbage XML data")
#                pass
#            
#            url = self.baseurl
#            url += "/xml-api/cpanel?user=%s&cpanel_xmlapi_module=Park" % self.username
#            url += "&cpanel_xmlapi_func=listparkeddomains&cpanel_xmlapi_apiversion=2"
#            req = urllib2.Request(url)
#            req.add_header("Authorization", self.authheader)
#            handle = urllib2.urlopen(req)
#            data = None
#            data = handle.read()
#            
#            try:
#                dresult = None
#                dresult = xmlToDict(data)["data"]
#                for piece in dresult:
#                    info["domains"].append(piece["domain"][0])
#            except KeyError:
#                    pass
#            except xml.parsers.expat.ExpatError:
#                errors.append("cPanel: failed fetching parked domain information, server returned garbage XML data")
#                pass
#        except urllib2.URLError, e:
#            if hasattr(e, 'reason'):
#                errors.append("cPanel: " + str(e.reason))
#            elif hasattr(e, 'code'):
#                if e.code == 401:
#                    errors.append("cPanel: Invalid username and/or password")
#                elif e.code == 403:
#                    errors.append("cPanel: Could not access cPanel due to a '403 Forbidden' error")
#                else:
#                    raise
#        return info, errors
    
    def test(self, account):
        url = self.baseurl
        url += "/xml-api/cpanel?user=%s&cpanel_xmlapi_apiversion=2&cpanel_xmlapi_module=Backups" % account
        url += "&cpanel_xmlapi_func=listfullbackups"
        print url
        req = urllib2.Request(url)
        req.add_header("Authorization", self.authheader)
        handle = urllib2.urlopen(req)
        data = handle.read()
        data = xmlToDict(data)
        return data
    
    
    def addPackage(self, name, quota=150, bwlimit=1500, featurelist="default", ip=0, cgi=1, frontpage=0,
                   cpmod="x3", language="English", maxftp="unlimited", maxsql="unlimited", maxpop="unlimited",
                   maxlst="unlimited", maxsub="unlimited", maxpark="unlimited", maxaddon="unlimited", hasshell=0):
        url = self.baseurl
        url += "/xml-api/addpkg?name=%s&featurelist=%s&quota=%d&ip=%d&cgi=%d" % (name, featurelist, quota, ip, cgi)
        url += "&frontpage=%d&cpmod=%s&maxftp=%s&maxsql=%s&maxpop=%s" % (frontpage, cpmod, maxftp, maxsql, maxpop)
        url += "&maxlst=%s&maxsub=%s&maxpark=%s&maxaddon=%s" % (maxlst, maxsub, maxpark, maxaddon)
        url += "&hasshell=%d&bwlimit=%s" % (hasshell, bwlimit)
        print url
        req = urllib2.Request(url)
        req.add_header("Authorization", self.authheader)
        handle = urllib2.urlopen(req)
        data = handle.read()
        data = xmlToDict(data)
        return data
    
    
    def setPackage(self, account, package):
        url = self.baseurl
        url += "/xml-api/changepackage?user=%s&pkg=%s" % (account, package)
        print url
        req = urllib2.Request(url)
        req.add_header("Authorization", self.authheader)
        handle = urllib2.urlopen(req)
        data = handle.read()
        data = xmlToDict(data)
        return data
        
        
