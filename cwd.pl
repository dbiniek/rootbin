#!/usr/bin/perl
use strict;

###########
#
# SCRIPT NAME: cwd (Change Working Directory / Change to Web DocumentRoot / Cobras Work Diligently)
#
# DESCRIPTION:
#	On cPanel servers, cwd will change the console's working directory into the
#	DocumentRoot of the domain specified. The script is able to do this due to
#	a few layers of abstraction:
#		- alias cwd = '/root/bin/cwd'
#		- /root/bin/cwd contains: `/root/bin/cwd.pl $1 $2`
#		- When the alias 'cwd' is executed, it sources the output of
#		  the perl script (which may output "cd /home/user/public_html")
#
#	This combination of scripts allows the current working directory to be
#	changed -- otherwise, a new bash process would be launched and it's
#	directory would be changed, which wouldn't make this a very useful script.
#
# USAGE:
#	[root@gator1337 ~]# cwd gator.com
#	[root@gator1337 /home/gator/public_html/]# 
#
# URL TO WIKI: https://confluence.endurance.com/display/HGS/CWD 
#
# URL TO GIT: https://stash.endurance.com/projects/HGADMIN/repos/cwd/browse 
#
# MAINTAINER: Robert West
#
# Please submit all bug reports at jira.endurance.com 
# (C) 2012 - HostGator.com, LLC
#
#
# ChangeLog:
#
# 2013-02-12 :: 0.3.4 :: Added check and generation of .accesshash (bug #13464)
#
# 2012-09-26 :: 0.3.3 :: If IP address is provided (e.g. 's 1.2.3.4' which calls cwd automatically), do nothing.
# 2012-09-06 :: 0.3.2 :: I had enabled warnings, which just caused more headaches. Added logic
#                        to check if $xml->{data} is defined prior to trying to use it, disabled warnings.
# 2012-09-05 :: 0.3.1 :: Imported "XMLin" subroutine, cleaned up a couple undefined value warnings.
# 2012-09-04 :: 0.3.0 :: Reorganized main code, made a couple things into 
#                        subroutines, better error checking.
# 2012-01-06 :: 0.2.5 :: Rewrote subdir handler, added header info
# 2011-12-13 :: 0.2.4 :: Added more verbose error messages
# 2011-11-22 :: 0.2.3 :: Added -q flag for suppressing error messages.
#                        Updated cwd shell script to pass $1 and $2.
# 2011-09-30 :: 0.2.2 :: fixed duplicate use of $request variable for clarity
# 2011-09-30 :: 0.2.1 :: cleaned up formatting, minor logic improvement
# 0.2 added lc($domain) so people can be lazier
#
##########

# We can't really check if quiet mode is on until Getopt is loaded
use Getopt::Long;

my $quietmode = 0;
my $verbose = 0;

GetOptions(
	"q" => \$quietmode,
	"v" => \$verbose,
);

eval {
#	require LWP::UserAgent;
#	require MIME::Base64;
#	require XML::Simple;
#	require HTTP::Request;
	require URI;
	1;
} || error("Error loading required modules" . ($verbose ? ": $@" : "."), 1);

#XML::Simple->import('XMLin');

my $url = $ARGV[0] || usage();

if ($url =~ m/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/)
{
	if ($quietmode)
	{
		print "echo -n\n";
	} else {
		print "echo Cannot look up document root by IP -- must provide domain name or URL.\n";
	}
	exit;
}

my $dir = getPathFromURL($url) || error("Could not find document root for URL provided.", 1);

print "cd $dir\n";

exit;

############################################################
### Show usage and exit.
### If quiet mode is on, just exit without printing.
############################################################
sub usage
{
	if (! $quietmode)
	{
		print "echo; \n"
		    . "echo \"USAGE: /root/bin/cwd [-q] example.com/subdir -- can include http:// also. \"; \n"
		    . "echo \"       If subdir doesn't exist, chdirs into first directory that does exist.\"; \n"
		    . "echo; \n"
		    . "echo \"FLAGS: -q (optional) -- suppress error messages.\"; \n"
		    . "echo \"       -v (optional) -- show additional details in error messages.\"; \n"
		    . "echo; \n";
	}
	exit;
}

############################################################
### Error message
### Paramter 1 = "Error Message Text"
### Paramter 2 = Error Type (1=error, 0=warning)
### Echos error message, suppressed if quiet mode is on.
### Exits if message is error, otherwise just echos message
############################################################
sub error
{
	my $message = $_[0];
	my $type = $_[1];

	if (! $quietmode)
	{
		$message =~ s/"/\\"/g;
		print "echo \"$message\" \n";
	}

	if ($type == 1)
	{
		exit;
	}

}

############################################################
### Main Loop
###
### EXPECTS:
###     "http://blahblah.com/"
### RETURNS:
###     "/home/user/public_html/blahblah.com"
############################################################
sub getPathFromURL
{
	my $url = shift;

	# fill data for domain and URI
	my ($domain, $uri) = splitUrl($url);

	## print documentroot
	my $docRoot = getDocRoot(lc($domain)) || error("Could not determine document root.", 1);

	if (! -d $docRoot)
	{
		error("Cannot change directory: $docRoot does not exist", 1);
	}
	
	elsif (-d $docRoot && $uri && -d $docRoot . $uri)
	{
		return $docRoot . $uri;
	}

	elsif (! $uri)
	{
		return $docRoot;
	}

	else
	{
		return getClosestDirectory($docRoot, $uri);
	}
}


############################################################
### Get closest directory that actually exists.
### In the example below, if the "subdomain" dir doesn't exist,
### it will return "path/to/" or whatever the closest match is.
###
### EXPECTS:
###     ("/home/user/public_html/", "path/to/subdomain")
### RETURNS:
###     "/home/user/public_html/path/to"
############################################################
sub getClosestDirectory
{
	my ($docRoot, $uri) = @_;

	# Only loop 10x, after that give up and just use docroot
	my $sdcount = 0;
	while (! -d $docRoot . $uri && $sdcount < 10)
	{
		$uri =~ s/\/$//;
		$uri =~ s/[^\/]*$//;
		$sdcount++;
	}

	if (-d $docRoot . $uri)
	{
		return $docRoot . $uri;
	} else {
		return $docRoot;
	}
}


############################################################
### Split URL 
###
### EXPECTS:
###	http://url.com/subdir
###	https://url.com/subdir
###	ftp://url.com/subdir
### RETURNS: ("url.com", "/subdir")
############################################################

sub splitUrl
{
	my $domain;
	my $uri;
	my $url = $_[0];
	if ($url =~ "/")
	{
		if ($url !~ m/^(ftp|https?):/)
		{
			if ($url =~ m/:\/\//)
			{
				error("Malformed URL. If using a URL, only ftp, http, and https protocols are accepted", 1);
			}
			$url =~ s/^/http:\/\//;
		}
		my $u = URI->new("$url", "http");
		$domain = $u->host;
		$uri = $u->path;
	}
	else
	{
		$domain = $url;
	}

	return ($domain, $uri);

}


################################################################################
### Get DocumentRoot
###
### EXPECTS: domain.com ($domName)
### RETURNS: /doc/root/ or 0
### REQUIRES: HTTP::Request, LWP::UserAgent
################################################################################

sub getDocRoot 
{
	my $domName = $_[0];
	my $docRoot;
	my $accesshash;

	# Delete ^www.
	$domName =~ s/^www\.//;

	#Open and read from /etc/userdatadomains
	my $userdata = '/etc/userdatadomains';
	my @fields;
	open(data, $userdata) or die "Could not read from $userdata";
	while(<data>){
		chomp;
		@fields = split(m/[(:|==)]/, $_);
		if( $fields[0] eq $domName ){
			close data;
			return $fields[9];
		}
	}
	close data;
	error("cPanel cannot determine DocumentRoot for '$domName'", 1);

	# Read access hash
#	system("/usr/local/cpanel/whostmgr/bin/whostmgr ./setrhash > /dev/null") unless (-e "/root/.accesshash");
#	open HASH, "/root/.accesshash" or error('Error reading access hash' . ($verbose ? ": $!" : "."), 1);
#	while (<HASH>)
#	{
#		$accesshash .= $_;
#		chomp $accesshash;
#	}

#	my $request_uri = "/xml-api/domainuserdata?domain=" . $domName;
#	my $auth = "WHM root:" . $accesshash;
#	my $rurl = "http://127.0.0.1:2086";

#	my $ua = LWP::UserAgent->new;
#	$ua->timeout(4);

#	my $request = HTTP::Request->new( GET => $rurl . $request_uri);
#	$request->header( Authorization => $auth );
#	my $response = $ua->request($request);
#	exit if $response->content !~ /^</;

#	my $xml = XMLin($response->content);
#
#	if (defined($xml->{data}) && $xml->{data}->{reason} eq "Access denied")
#	{
#		error("Unable to authenticate using cPanel API: Access denied", 1);
#	}
#	else
#	{
#		if ($xml->{userdata}->{documentroot})
#		{
#			return $xml->{userdata}->{documentroot};
#		}
#		else
#		{
#			error("cPanel cannot determine DocumentRoot for '$domName'", 1);
#		}
#	}

	return 0;
}
