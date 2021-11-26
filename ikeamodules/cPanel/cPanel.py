###########
# Ikea
# Generates backups, downloads backups and restores backups from remote servers.
# https://confluence.endurance.com/display/HGS2/Migrations%3A+Ikea 
# Please submit all bug reports at jira.endurance.com
#
# (C) 2011 - HostGator.com, LLC
###########

import urllib2
import ftplib
import json

from base64 import encodestring
from urlparse import urlparse
from operator import itemgetter


class cPanel:
    '''Class which handles functions and methods and holds information for a single cPanel account.'''
    def __init__(self, server, username, password, usessl, ftpcheck, port=2083):
        
        self.server = server
        self.username = username
        self.password = password
        self.ftpcheck = ftpcheck
        self.ftp = False
        self.cpanel = False
        self.backups = []
        self.backupfile = None
        self.dledfile = None
	self.skiphome = False
        
        self.info = {}
        self.info["primarydomain"] = "???"
        self.info["diskusage"] = None
        self.info["disklimit"] = None
        self.info["diskusageperc"] = None
        self.info["diskspaceunits"] = None
        self.info["numaddons"] = None
        self.info["dbs"] = None
        self.info["numemails"] = None
        self.info["numaddons"] = None
        self.info["hostname"] = "???"
	self.info["reseller"] = False
        self.info["movedcpbackup"] = ""
        
        self.info["ssl"] = usessl
        self.info["domains"] = []
        
        self.errors = []
        
        if not usessl:
            self.baseurl = "http://" + server + ":" + str((port-1))
        else:
            self.baseurl = "https://" + server + ":" + str(port)
        
        base64string = encodestring('%s:%s' % (username, password))[:-1]
        self.authheader = "Basic %s" % base64string


    def refreshInfo(self, account=None, cpanel=True, ftp=True):
        self.errors = []
        if account == None:
            account = self.username
        self.ftp = False
        self.cpanel = False
        
        try:
            url = "https://" + self.server + ":2087"
            url += "/json-api/acctcounts?user=%s" % account
            req = urllib2.Request(url)
            req.add_header("Authorization", self.authheader)
            handle = urllib2.urlopen(req)
            data = None
            data = handle.read()

            try:
                dresult = None
                dresult = json.loads(data)
                self.info["reseller"] = True
            except:
                self.info["reseller"] = False
                self.errors.append("WHM: failed to parse reseller account information.")
        except urllib2.URLError, e:
            pass

        # Check cPanel login and get info
        if cpanel:
            try:
                url = self.baseurl
                url += "/json-api/cpanel?user=%s&cpanel_jsonapi_module=StatsBar&cpanel_jsonapi_func=stat" % account
                url += "&display=diskusage|addondomains|sqldatabases|hostname|emailaccounts&cpanel_jsonapi_apiversion=2"
                req = urllib2.Request(url)
                req.add_header("Authorization", self.authheader)
                handle = urllib2.urlopen(req)
                data = None
                data = handle.read()
                
                try:
                    dresult = None
                    dresult = json.loads(data)
                except:
                    self.errors.append("cPanel: failed to fetch account information from server, server returned garbage XML data")
                    dresult = None
                
                if dresult:
                    try:
                        for piece in dresult["cpanelresult"]["data"]:
                            if piece["name"] == "sqldatabases":
                                self.info["dbs"] = piece["_count"]
                            elif piece["name"] == "addondomains":
                                self.info["numaddons"] = piece["_count"]
                            elif piece["name"] == "emailaccounts":
                                self.info["numemails"] = piece["_count"]
                            elif piece["name"] == "diskusage":
                                self.info["diskusage"] = piece["_count"]
                                self.info["disklimit"] = piece["_max"]
                                self.info["diskspaceunits"] = piece["units"]
                                self.info["diskusageperc"] = piece["percent"]
                            elif piece["name"] == "hostname":
                                self.info["hostname"] = piece["value"]
                    except KeyError:
                        pass
                
                url = self.baseurl + "/json-api/cpanel?cpanel_jsonapi_apiversion=2&cpanel_jsonapi_module=DomainLookup&cpanel_jsonapi_func=getmaindomain"
                req = urllib2.Request(url)
                req.add_header("Authorization", self.authheader)
                handle = urllib2.urlopen(req)
                data = None
                data = handle.read()
                
                try:
                    dresult = None
                    dresult = json.loads(data)
                except:
                    self.info["primarydomain"] = "???"
                    self.errors.append("cPanel: failed to check primary domain, server returned garbage JSON data")
                
                if dresult:
                    try:
                        for piece in dresult["cpanelresult"]["data"]:
                            self.info["primarydomain"] = piece["main_domain"]
                            self.info["domains"].append(piece["main_domain"])
                    except KeyError:
                        self.info["primarydomain"] = "???"
                        pass
                
                if self.info["primarydomain"].startswith('Remote execution'):
                    self.info["primarydomain"] = "???"
                
                url = self.baseurl
                url += "/json-api/cpanel?user=%s&cpanel_jsonapi_apiversion=2" % account
                url += "&cpanel_jsonapi_module=AddonDomain&cpanel_jsonapi_func=listaddondomains"
                req = urllib2.Request(url)
                req.add_header("Authorization", self.authheader)
                handle = urllib2.urlopen(req)
                data = None
                data = handle.read()
                
                try:
                    dresult = None
                    dresult = json.loads(data)
                    for piece in dresult["cpanelresult"]["data"]:
                        self.info["domains"].append(piece["domain"])
                except KeyError:
                    pass
                except:
                    self.errors.append("cPanel: failed fetching addon domain information, server returned garbage JSON data")
                    pass
              
                url = self.baseurl
                url += "/json-api/cpanel?user=%s&cpanel_jsonapi_module=Park" % account
                url += "&cpanel_jsonapi_func=listparkeddomains&cpanel_jsonapi_apiversion=2"
                req = urllib2.Request(url)
                req.add_header("Authorization", self.authheader)
                handle = urllib2.urlopen(req)
                data = None
                data = handle.read()
                
                try:
                    dresult = None
                    dresult = json.loads(data)
                    for piece in dresult["cpanelresult"]["data"]:
                        self.info["domains"].append(piece["domain"])
                except KeyError:
                        pass
                except:
                    self.errors.append("cPanel: failed fetching parked domain information, server returned garbage JSON data")
                    pass
                
                
            except urllib2.URLError, e:
                if hasattr(e, 'reason'):
                    self.errors.append("cPanel: " + str(e.reason))
                elif hasattr(e, 'code'):
                    if e.code == 401:
                        self.errors.append("cPanel: Invalid username and/or password")
                    elif e.code == 403:
                        self.errors.append("cPanel: Could not access cPanel due to a '403 Forbidden' error")
                    else:
                        raise
            else:
                self.cpanel = True
        
        if ftp and self.ftpcheck:
            # Check FTP login
            
            try:
                ftp = ftplib.FTP(self.server, self.username, self.password)
                self.ftp = True
            except ftplib.all_errors, e:
                self.errors.append("FTP: " + str(e))
        
        return


    def getBackupList(self, account=None):
        if account == None:
            account = self.username
        
        try:
            backups = []
            data = None
            url = self.baseurl
            url += "/json-api/cpanel?user=%s&cpanel_jsonapi_apiversion=2&cpanel_jsonapi_module=Backups" % account
            url += "&cpanel_jsonapi_func=listfullbackups"
            req = urllib2.Request(url)
            req.add_header("Authorization", self.authheader)
            handle = urllib2.urlopen(req)
            data = handle.read()
        except urllib2.URLError, e:
            if hasattr(e, 'reason'):
                self.errors.append("cPanel: " + str(e.reason))
            elif hasattr(e, 'code'):
                if e.code == 401:
                    self.errors.append("cPanel: Invalid username and/or password")
                elif e.code == 403:
                    self.errors.append("cPanel: Could not access cPanel due to a '403 Forbidden' error")
                else:
                    raise
        else:
            self.cpanel = True
        
        if self.cpanel:
            try:
                result = json.loads(data)
                
                for piece in result["cpanelresult"]["data"]:
                    backups.append({"file": piece["file"], "localtime": piece["localtime"], "status": piece["status"], "time": piece["time"]})
                backups.sort(key=itemgetter("time"), reverse=True)
                self.backups = backups
                return True
            except KeyError:
                return False
        else:
            return False


    def startBackup(self, account=None):
        if account == None:
            account = self.username
        url = self.baseurl
        url += "/json-api/cpanel?user=%s&cpanel_jsonapi_apiversion=1&cpanel_jsonapi_module=Fileman" % account
        url += "&cpanel_jsonapi_func=fullbackup"
        req = urllib2.Request(url)
        req.add_header("Authorization", self.authheader)
        handle = urllib2.urlopen(req)
        data = handle.read()
        data = json.loads(data)
        return data


    def removeFile(self, myfile, account=None):
        if account == None:
            account = self.username
        url = self.baseurl
        url += "/json-api/cpanel?cpanel_jsonapi_user=%s&cpanel_jsonapi_apiversion=2&cpanel_jsonapi_module=Fileman" % account
        url += "&cpanel_jsonapi_func=fileop&op=unlink&sourcefiles=%s&doubledecode=0&metadata=&destfile=" % myfile
        req = urllib2.Request(url)
        req.add_header("Authorization", self.authheader)
        handle = urllib2.urlopen(req)
        data = handle.read()
        data= json.loads(data)
        return data

    def moveFile(self, myfile, myfile2, account=None):
        if account == None:
            account = self.username
        url = self.baseurl
        url += "/json-api/cpanel?cpanel_jsonapi_user=%s&cpanel_jsonapi_apiversion=2&cpanel_jsonapi_module=Fileman" % account
        url += "&cpanel_jsonapi_func=fileop&op=move&sourcefiles=%s" % myfile
        url += "&destfiles=%s" % myfile2
        req = urllib2.Request(url)
        req.add_header("Authorization", self.authheader)
        handle = urllib2.urlopen(req)
        data = handle.read()
        data= json.loads(data)
        return data

