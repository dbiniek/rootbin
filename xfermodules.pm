###########
# Perl modules used by the Migrations department
# 
# Not created yet
# Please submit all bug reports at jira.endurance.com
#
# (C) 2011 - HostGator.com, LLC
###########
#==============================================================================

=pod

=head1 Example of how to include the modules:

 if (!-e "/root/bin/xfermodules.pm") {
     print "The transfers modules do not appear to be on the server.\n";
     exit 1;
 }else {
     require "/root/bin/xfermodules.pm";
 }

=cut

package xfermodules;
$VERSION = "1.25";

1;

###########"
# Userdata Perl module
# A module that gathers information about a cPanel account with some functions to copy data out of the account.
# Please submit all bug reports at jira.endurance.com"
# Example script that uses this module: finishedxfer
# Git URL for this module: NA yet.
# (C) 2011 - HostGator.com, LLC"
###########"

#-----------------------------------------------------------------------------------------------------------

#Todo: Update lookup_docroot and lookup_subdomain_docroot to use the hashes rather than looping through the arrays.

=pod

=head1 Example usage for Userdata.pm:

 my $ud = Userdata->new("localhost", "myuser");
 $ud->dump();  #Shows some info. from the myuser account


=head2 Example of copying a document root to a new directory:

 $ud->copy_document_root("mydomain1.com", "/home/newuser/public_html");

=cut

package Userdata;
use Term::ANSIColor qw(:constants);
use File::Find ();
use Tie::File;
use LWP::UserAgent;
use strict;
use Data::Dumper;
use File::Copy;
use JSON;
if (eval {require JSON;}) {# JSON module will only be on cPanel servers.
     require JSON;         # If we're on Plesk, it won't load, but we won't use it.
}

sub new {                          #Constructor
     my $class = shift;
     my $self  = {};
     $self->{class}           = $class;
     $self->{server}          = $_[0];
     $self->{username}        = $_[1];    #Account Username
     $self->{loggobj}         = $_[2];
     $self->{token}           = $_[3];
     $self->{ip}              = undef;    #Account IP address
     $self->{dedicatedip}     = 0;        #Flag indicating whether or not an IP is dedicated (1=Yes, 0=No)
     $self->{primarydomain}   = undef;
     $self->{partition}       = undef;    #i.e. home or home2.  Only used by cPanel.
     $self->{owner}           = undef;
     $self->{plan}            = undef;
     $self->{addons}          = [];       #Array that holds the addon domains. (actually addon:subdomain)
     $self->{addonsubdomains} = [];       #Array that holds subdomains associated with the addon domains.
     $self->{addondirs}       = [];       #Array that holds addon domain directories. (currently only populated by cPanel servers)
     $self->{maxaddons}       = 0;        #Maximum number of addons this account is configured to allow.
     $self->{domainkeys}      = [];       #Array that holds the domain keys for the addon domains.
     $self->{subdomains}      = [];       #Array that holds the subdomains not already associated with addon domains.
     $self->{subdomaindirs}   = [];       #Array that holds subdomain directories.    (currently only populated by cPanel servers)
     $self->{subdomain_subdomaindir} = {};#Hash with subdomain as the key and subdomaindir as the value
     $self->{subdomaindir_subdomain} = {};#Hash with subdomaindir as the key and subdomain as the value
     $self->{addon_addondir}  = {};#Hash with addon as the key and addondir as the value. i.e. {mssdomain10.com} = /home/mss001/public_html/mssdomain10.com
     $self->{addon_addonsubdomain} = {};#Hash with addon as the key and associated subdomain as the value.  i.e. {mssdomain10.com} = mssdomain10.primary.com 
     $self->{addondir_addon}  = {};#Hash with addondir as the key and addon as the value. i.e. {/home/mss001/public_html/mssdomain10.com} = mssdomain10.com
     $self->{parked_parkeddir}= {};#Hash with parked domain as the key and its dir as the value. i.e. {mydomain.com} = /home/mss001/public_html
     $self->{parkeddir_parked}= {};#Hash with parked domain dir as the key and the domain as the value. i.e. {/home/mss001/public_html} = mydomain.com
     $self->{ns1}             = undef;
     $self->{ns2}             = undef;
     $self->{ns1ip}           = undef;
     $self->{ns2ip}           = undef;
     $self->{ownerns1}        = undef;
     $self->{ownerns2}        = undef;
     $self->{ownerns1ip}      = undef;
     $self->{ownerns2ip}      = undef;
     $self->{mysqlpass}       = undef;
     $self->{resellerquota}          = undef;  # Total quota for the reseller plan.
     $self->{resellerbandwidth}      = undef;  # Total reseller bandwidth.
     $self->{totaldiskalloc}         = undef;  # Total disk space allocated to a reseller.
     $self->{totalbwalloc}           = undef;  # Total bandwidth allocated to a reseller.
     $self->{clients}                = [];     # Client account usernames (Pertinent if $self->{username} is a reseller).
     $self->{clients_diskusage}      = {};     # Disk usage for a reseller client.
     $self->{clients_diskquota}      = {};     # Disk usage limit with $self->{clients} as the key.
     $self->{clients_bandwidthusage} = {};     # Bandwidth usage with $self->{clients} as the key.
     $self->{clients_bandwidthlimit} = {};     # Bandwidth limit with $self->{clients} as the key.
     $self->{diskusage}       = undef;
     $self->{diskunits}       = undef;
     $self->{disklimit}       = undef;
     $self->{diskpercent}     = undef;
     $self->{bandwidthusage}  = undef;    # Bandwidth usage   for this account.
     $self->{bandwidthunits}  = undef;    # Bandwidth units   for this account.
     $self->{bandwidthlimit}  = undef;    # Bandwidth limit   for this account.
     $self->{bandwidthpercent}= undef;    # Bandwidth percent for this account.
     $self->{mysqldiskusage}  = undef;
     $self->{mysqlunits}      = undef;
     $self->{totaldiskusage}  = undef;    #Sum of {diskusage} and {mysqldiskusage}.
     $self->{totalunits}      = undef;    #Units for {totaldiskusage}.
     $self->{databases}       = 0;        #A count of the databases.
     $self->{inodes}          = 0;        #Inodes in this account.
     $self->{dblist_name}     = [];       #An array of databases.
     $self->{dblist_size}     = {};       #A hash array of database sizes where an element of dblist_name is the key.
     $self->{dblist_tables}   = {};       #A hash array showing the number of tables in each database where an element of dblist_name is the key.
     $self->{userlist_dbs}    = {};       #A hash array with database users as the key and the number of databases the user is assigned to as the value.
     $self->{ftpuser}         = undef;    #FTP user (Used by the Plesk ui script)
     $self->{ftppass}         = undef;    #FTP password (Used by the Plesk ui script)
     $self->{pleskpass}       = undef;    #Plesk admin password
     $self->{sslcerts}        = [];       #Array of strings showing SSL info.  Each element represents 1 cert, and shows the valid domains.
     $self->{sslcertsfile}    = [];       #Array with the ssl certs file from /var/cpanel/userdata/username. (not the actual cert)
     $self->{sslstart}        = [];       #Array of strings showing starting date/time that the same element in sslcerts is valid.
     $self->{sslend}          = [];       #Array of strings showing ending date/time that the same element in sslcerts is valid.
     $self->{sslstatus}       = [];       #
     $self->{email_path}      = {};       #A hash array with email addresses as the key and the maildir file path as the value.
     $self->{email_pass}      = {};       #A hash array with email addresses as the key and the email password as the value.
     $self->{error}           = 0;        #Error indicator.  This will be set to 1 if there was any problem gathering the data.
     $self->{error_msg}       = undef;    #Used by copy_awstats and possibly other methods to elaborate when there are problems.
     $self->{branding}        = undef;    #Branding this account is set to (i.e. "HG" for HostGator shared accounts)
     bless($self, $class);
     if (-e "/etc/psa/.psa.shadow") {
          $self->{mysqlpass} = `cat /etc/psa/.psa.shadow`; #Grab MySQL password.
          chomp($self->{mysqlpass});
          if (plesk_setprimaryinfo($self)  != 0) {$self->{error} = 10; return $self;}
          if (plesk_setparkeddomains($self)!= 0) {$self->{error} = 8; return $self;}
          if (plesk_setaddons($self)       != 0) {$self->{error} = 6; return $self;}
          if (plesk_setsubdomains($self)   != 0) {$self->{error} = 4; return $self;}
          if (setnameservers($self)        != 0) {$self->{error} = 2; return $self;}
     }else { #If the password file doesn't exist, this must be a cPanel server.  Run the cPanel methods.
          if (cpanel_setprimaryinfo($self) != 0) {$self->{error} = 10; return $self;}
          if (cpanel_lookup_branding($self)!= 0) {$self->{error} = 11; return $self;}
          if (cpanel_setparkeddomains($self) != 0) {$self->{error} = 8; return $self;}
          if (lookup_ssl_info($self)       != 0) {$self->{error} = 7; return $self;}
          if (cpanel_setaddons($self)      != 0) {$self->{error} = 6; return $self;}
          if (cpanel_setsubdomains($self)  != 0) {$self->{error} = 4; return $self;}
          if (setnameservers($self)        != 0) {$self->{error} = 2; return $self;}
     }
     $self->set_inodes();
     return $self;
}

# Determine whether we are on Plesk or cPanel, then call the appropriate email subroutine.
sub lookup_email_info {
     my $self = shift;
     if (-e "/etc/psa/.psa.shadow") {
          return plesk_lookup_email_info($self);
     }else {
          return cpanel_lookup_email_info($self);
     }
}

# Look up all of the email addresses for this user.
# Input:  Nothing
# Output: $self->{email_path} will be populated with all if this account's email addresses.
sub plesk_lookup_email_info {
     my $self = shift;
     $self->plesk_lookup_email_bydomain($self->{primarydomain});
     foreach my $addon (@{ $self->{addons} }) {
          $self->plesk_lookup_email_bydomain($addon);
     }
}

# Look up all of the email addresses in a given domain on Plesk.
# Input:  Domain name
# Output: $self->{email_path} will have all of the given domain's email addresses added to it.
sub plesk_lookup_email_bydomain {
     my $self         = shift;
     my $email_domain = $_[0]; #Email domain.
     my $mysqlpass    = $self->{mysqlpass};
     my @email_list = `mysql -ss -u'admin' -p'$mysqlpass' -e"select mail_name,name,password from mail left join domains on mail.dom_id = domains.id inner join accounts on mail.account_id = accounts.id where name = '$email_domain';" psa`;
                      # Example result from the above query
                      # test2   mailmove.org    $1$0yvPKpWx$P3d9vUpH0nvI7Y4hUTE0R/
                      # test3   mailmove.org    $1$erzBVjot$ZETzuttTGuU5ZlhkzWkKJ1
     if (($? >> 8) > 0) {   #Houston, we have a problem.. Print the output from the mysql command.
          foreach my $db (@email_list) {
               print $db;
          }
          return;
     }
     foreach my $rec (@email_list) {
          chomp($rec);
          if ($rec =~ /\s$/) {
               print RED . "****** Warning ****** " . RESET . "Email address skipped in domain $email_domain.  It appears to have a blank password.\n";
               print "This line should now *email domain password* but it shows this:\n";
               print "*$rec*\n\n";
               next;
          }
          $rec =~ m/(\S+)\s+\S+\s+(\S+)/;
          my $email_user   = $1; #Current email user without "@domain.com" (first  capture group from the above regex)
          my $email_pass   = $2; #Current email password                   (second capture group from the above regex)
          my $email_addr =  $email_user . "\@" . $email_domain;
          my $email_path = "/var/qmail/mailnames/" . $email_domain . "/" . $email_user . "/Maildir";
          $self->{email_path}{$email_addr} = $email_path;
          $self->{email_pass}{$email_addr} = $email_pass;
     }
     return;
}




# Look up all of the email addresses for this user.
# Input:  Nothing
# Output: $self->{email_path} will be populated with all if this account's email addresses.
sub cpanel_lookup_email_info {
     my $self = shift;
     $self->cpanel_lookup_email_bydomain($self->{primarydomain});
     foreach my $addon (keys %{ $self->{addon_addondir} }) {
          $self->cpanel_lookup_email_bydomain($addon);
     }
     foreach my $parked (keys %{$self->{parked_parkeddir}}) {   #todo: test
          $self->cpanel_lookup_email_bydomain($parked);
     }
}

#List the email accounts for a domain of a cPanel account.
# Input:  domain name
# Output: $self->{email_path} hash array will be populated.
#           i.e. $self->{info@mydomain.com} = "/home/user/mail/mydomain.com/info";
#         Return value: 0 = OK and populated
#                       1 = No email accounts listed
#                       2 = Error
sub cpanel_lookup_email_bydomain {
     my $self       = shift;
     my $domain     = $_[0];                #Domain name to list the email accounts for.
     my $homedir    = "/" . $self->{partition} . "/" . $self->{username};
     unless (-s "$homedir/etc/$domain/shadow") {  #Check to see if a shadow file is there for this domain's email accounts.
          #$self->logg("No email shadow file found for $domain email accounts.  Skipping email for $domain.\n",1);
          return 1;                                                # It isn't, so let's return without extracting anything.
     }
     eval {
          open (INFILE, "$homedir/etc/$domain/shadow");
          while (my $line = <INFILE>) {
               chomp($line);
               if ($line =~ /^.*:/) {
                    $line          =~ /(.*?):(.*?):.*/;  # Capture the username and password into $1 and $2. from a line like "user:$1$OgEc4rUM$y6KYO0HDq9AXFdt6i9gTq0:15513::::::"
                    my $email_user =  $1;
                    my $email      =  $email_user . "\@" . $domain;
                    my $pass       =  $2;
                    my $email_path = "/" . $self->{partition} . "/" . $self->{username} . "/mail/" . $domain . "/" . $email_user;
                    $self->{email_path}{$email} = $email_path;
                    $self->{email_pass}{$email} = $pass;
               }
          }
          close INFILE;
     } or do {
          $self->logg("Error reading $homedir/etc/$domain/shadow",1);
          return 2;
     };
     return 0;
}


# Determine whether we are on Plesk or cPanel, then call the appropriate diskusage subroutine.
sub lookup_db_info {
     my $self = shift;
     if (-e "/etc/psa/.psa.shadow") {
          return plesk_lookup_db_info($self);
     }else {
          return cpanel_lookup_db_info($self);
     }
}


sub plesk_lookup_db_info {
     my $self = shift;
     my $mysqlpass = $self->{mysqlpass};
     my $database;
     my $dbsize;
     my $dbtables;
     my @dblist = `mysql -ss -u'admin' -p'$mysqlpass' -e"select data_bases.name from data_bases inner join hosting on data_bases.dom_id = hosting.dom_id inner join sys_users on sys_users.id = hosting.sys_user_id where sys_users.login = '$self->{username}';" psa`;
     if (($? >> 8) > 0) {
          foreach my $db (@dblist) {
               print $db;
          }
          return 1;
     }
     foreach $database (@dblist) {
          chomp ($database);
          push (@{$self->{dblist_name}}, $database);          #Store the data.
          #look up the database size.
          $dbsize = `mysql -ss -u'admin' -p'$mysqlpass' -e "select sum(DATA_LENGTH + INDEX_LENGTH) from tables where TABLE_SCHEMA = '$database';" information_schema`;
          chomp($dbsize);
          if (($? >> 8) > 0) {
               $self->logg("Error looking up database table count.  Looked up value is: " . $dbsize, 0);
               next;
          }
          $self->{dblist_size}{$database}   = $dbsize;
          #look up the number of tables.
          $dbtables = `mysql -ss -u'admin' -p'$mysqlpass' -e "select count(*) from TABLES where TABLE_SCHEMA = '$database';" information_schema`;
          chomp($dbtables);
          if (($? >> 8) > 0) {
               $self->logg("Error looking up database table count.  Looked up value is: " . $dbtables, 0);
               next;
          }
          $self->{dblist_tables}{$database} = $dbtables;
     }
     return 0;
}

# Look up database info.
#
# Input:  $self->{username}
#         $self->{server}
# Output: The following members are populated:
#         $self->{dblist_name}
#         $self->{dblist_size}
#         $self->{dblist_tables}
#         $self->{userlist_dbs}
sub cpanel_lookup_db_info {
     my $self = shift;
     my $dbtables;
     my $url = "json-api/cpanel?user=" . $self->{username} . "&cpanel_jsonapi_module=MysqlFE&cpanel_jsonapi_func=listdbs";
     my $jsondata = $self->cpanel_jsonapi($url);
     if (! $jsondata) {
         $self->logg( RED . "Error looking up database info.\n" . RESET, 1);
         return 1; #Error
     }
     foreach my $db (@{$jsondata->{cpanelresult}->{data}}) {
          push (@{$self->{dblist_name}}, $db->{"db"}); #Push the database name onto our own array of database names.
          $self->{dblist_size}{$db->{"db"}} = $db->{"size"};

          if (length($db->{"db"}) > 0 && $db->{"size"} > 0) {
               #look up the number of tables.
               $dbtables = `mysql -ss -e "select count(*) from TABLES where TABLE_SCHEMA = '$db->{db}';" information_schema`;
               chomp($dbtables);
               if (($? >> 8) > 0) {
                    $self->logg("Error looking up database table count.  Looked up value is: " . $dbtables, 0);
                    next;
               }
          }
          $self->{dblist_tables}{$db->{"db"}} = $dbtables;
          #Here is where we count the databases assigned to each user in order to detect the issue of one database user
          # being assigned to more than one database in cPanel --> Plesk transfers.
          foreach my $dbuser (@{$db->{userlist}}) {
               $self->{userlist_dbs}{$dbuser->{user}} = $self->{userlist_dbs}{$dbuser->{user}} + 1;
          }
     }
     return 0;
}

# Look up the SSL cert(s) for this account and populate the SSL related member arrays.
# One account should only have one certificate, so there is no need for the SSL members to be arrays.
# However, updating the members to scalars would require updating all dependent scripts.  So they remain
# arrays for this reason and because the arrays work fine other than being more complex than needed.
# Input:  Username from member.
#         The files in /var/cpanel/userdata/$user
# Output: Member arrays are populated with the SSL info.
sub lookup_ssl_info {
     my $self = shift;
     my $user = $self->{username};
     my @cpanel_userdata_files = `ls -1 /var/cpanel/userdata/$user`;
     if (($? >> 8) > 0) {
          foreach my $line (@cpanel_userdata_files) { #Something went wrong.  Print the output and exit.
               $self->logg(RED . $line . RESET, 1);
          }
          return 1;
     }
     foreach my $file (@cpanel_userdata_files) {      #Find the _SSL files in /var/cpanel/userdata/$user dir.
          chomp ($file);
          if ($file =~ /_SSL$/) {
               my $cert = $self->lookup_ssl_cert($file);
               $self->set_cert_info($cert, $file);    #Add this cert info to the member arrays.
          }
     }
     return 0;
}

# Input: full path filename to the certificate file.
# Output: SSL info is pushed onto the following arrays:
#         $self->{sslstart}
#         $self->{sslend}
#         $self->{sslcerts}
#         $self->{sslstatus}
#         Return: 0=OK, 1=Error
sub set_cert_info {
     my $self            = shift;
     my $certfile        = shift;
     my $cpanel_ssl_file = shift;
     my @sslmembers;
     my $status;
     if (lookup_cert_info($self, $certfile, \@sslmembers) > 0) {
          return 1;
     }
     push (@{ $self->{sslcertsfile} }, $cpanel_ssl_file);
     push (@{ $self->{sslcerts}     }, @sslmembers[0]);
     push (@{ $self->{sslstart}     }, @sslmembers[1]);
     push (@{ $self->{sslend}       }, @sslmembers[2]);
     $status = check_cert($self, $certfile);         #Check and record the status of the certificate.
     if ($status == 0) {
          push(@{ $self->{sslstatus} }, "OK");
     }elsif ($status == 1) {
          push(@{ $self->{sslstatus} }, "Not valid yet");
     }elsif ($status == 2) {
          push(@{ $self->{sslstatus} }, "Expired");
     }else {
          push(@{ $self->{sslstatus} }, "Error");
     }
     return 0;
}

#Check to see if a certificate is valid.
# Input: User object
#        Certificate file including full path.
#Output: 0 = OK - Appears to be valid.
#        1 = Not valid yet (i.e. today is before the start date)
#        2 = Expired       (i.e. today is after the end data)
#        3 = Error
sub check_cert {
     my $self  = shift;
     my $certfile = $_[0];
     my @sslmembers;
     my $start_date;
     my $start_year;
     my $start_month;
     my $start_day;
     my $end_date;
     my $end_year;
     my $end_month;
     my $end_day;
     my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
     my $now = sprintf("%04d%02d%02d", $year+1900, $mon+1, $mday);
     my %months = ("Jan", 1, "Feb", 2, "Mar", 3, "Apr", 4, "May", 5, "Jun", 6, "Jul", 7, "Aug", 8, "Sep", 9, "Oct", 10, "Nov", 11, "Dec", 12);
     if (lookup_cert_info($self, $certfile, \@sslmembers) > 0) {
          $self->logg(RED . "Error looking up certificate info.\n" . RESET, 1);
          return 3;
     }
     #**test** $sslmembers[0] = "Self signed: C=US, ST=TX, L=Houston, O=HG, OU=TR, CN=mssdomain1.com/emailAddress=mstreeter\@hostgator.com";
     #**test** $sslmembers[1] = "Not Before: Sep  2 15:49:30 2011 GMT";
     #**test** $sslmembers[2] = "Not After : Sep  4 15:49:30 2011 GMT";

     #At this point, the array is populated with something like this:
     # $sslmembers[0] = Self signed: C=US, ST=TX, L=Houston, O=HG, OU=TR, CN=mssdomain1.com/emailAddress=mstreeter@hostgator.com
     # $sslmembers[1] = Not Before: Sep  2 15:49:30 2011 GMT
     # $sslmembers[2] = Not After : Sep  1 15:49:30 2012 GMT
     if ($sslmembers[0] =~ /Self signed/) {   #If it's self signed, then return a 1.
          return 1;
     }
     $start_year = $sslmembers[1];
     $start_year =~ s/ [A-Z][A-Z][A-Z]$//;
     $start_year =~ s/.* //;
     $start_month = $sslmembers[1];
     $start_month =~ s/Not Before: //;
     $start_month =~ s/ .*//;
     $start_day = $sslmembers[1];
     $start_day =~ s/Not Before: [A-Za-z][A-Za-z][A-Za-z] *//;
     $start_day =~ s/ .*//;
     $start_date = sprintf("%04d%02d%02d", $start_year, $months{$start_month}, $start_day);
     $end_year = $sslmembers[2];
     $end_year =~ s/ [A-Z][A-Z][A-Z]$//;
     $end_year =~ s/.* //;
     $end_month = $sslmembers[2];
     $end_month =~ s/Not After : //;
     $end_month =~ s/ .*//;
     $end_day = $sslmembers[2];
     $end_day =~ s/Not After : [A-Za-z][A-Za-z][A-Za-z] *//;
     $end_day =~ s/ .*//;
     $end_date = sprintf("%04d%02d%02d", $end_year, $months{$end_month}, $end_day);
     #After all of this parsing, we have 3 variables: $now, $start_date, and $end_date in yyyymmdd form that can be compared to check the date validity.
     if ($now < $start_date) {
          return 1;             #Certificate is not valid yet. Return a 1.
     }
     if ($now > $end_date) {
          return 2;
     }
     return 0;
}


# Input: full path filename to the certificate file.
#        Reference to an $array that can be populated.
# Output: SSL info is pushed onto the following arrays:
#         $array[0] = sslcerts
#         $array[1] = sslstart
#         $array[2] = sslend
#         Return: 0=OK, 1=Error
sub lookup_cert_info {
     my $self       = shift;
     my $certfile   = $_[0];
     my $sslmembers = $_[1];
     my $flag       = 0;
     my $sslissuer;
     my $sslsubject;
     my $selfsigned;      #Contains "" or "Self signed: " to indicate a self-signed certificate.
     my $sslstart;
     my $sslend;
     my $sslaltname;
     $certfile = "'" . $certfile . "'"; # Quote it for bash in case theres a *.
     my @certinfo = `openssl x509 -in $certfile -text`;
     if (($? >> 8) > 0) {
          foreach my $line (@certinfo) {
               $self->logg( RED . $line . RESET, 1);
          }
          return 1;
     }
     foreach my $line (@certinfo) {
          chomp ($line);

          if ($line =~ /Issuer: /) {       #Look for and set the Issuer line (we compare later to the Subject to see if it's self-signed).
               $sslissuer = $line;
               $sslissuer =~ s/Issuer: //;
               $sslissuer =~ s/ *//;
          }
          if ($line =~ /Subject: /) {      #Look for and set the Subject line.
               $sslsubject = $line;
               $sslsubject =~ s/Subject: //;
               $sslsubject =~ s/ *//;
          }

          if ($line =~ /Not Before: /) {   #Look for and set the starting date.
               $sslstart = $line;
               $sslstart =~ s/ *//;
          }
          if ($line =~ /Not After : /) {   #Look for and set the ending date.
               $sslend = $line;
               $sslend =~ s/ *//;
          }
          if ($line =~ /Subject Alternative Name:/) { #Look for the "Subject Alternative Name:" line.  The line following it contains valid domain names.
               $flag = 1;
               next;
          }
          if ($flag == 1) {
               $sslaltname = $line;
               $sslaltname =~ s/ *//;
               $flag = 0;
          }
     }
     if (length($sslsubject)==0 || length($sslstart)==0 || length($sslend)==0) {
          return 1; #If the 4 varialbes aren't set, then something went wrong.
     }
     if ($sslissuer eq $sslsubject) {
          $selfsigned = "Self signed: ";
     }
     if (length($sslaltname) > 0) {
          $sslsubject = $sslaltname;
     }
     push (@{ $sslmembers }, $selfsigned . $sslsubject);
     push (@{ $sslmembers }, $sslstart);
     push (@{ $sslmembers }, $sslend);
     return 0;
}


# Input: _SSL filename in /var/cpanel/userdata/user
# Output: filename of the SSL certificate.
sub lookup_ssl_cert {
     my $self    = shift;
     my $sslfile = $_[0];
     my $user    = $self->{username};
     my $crtfile;
     my $currversion = +(split /\./,`cat /usr/local/cpanel/version`)[1];
     my @file;
     eval {
          open (my $INFILE, "/var/cpanel/userdata/$user/$sslfile");
          @file = <$INFILE>;
          close $INFILE;
     } or do {
          $self->logg( RED . "Error opening /var/cpanel/userdata/$user/$sslfile\n" . RESET, 1);
          return 1;
     };
     if ($currversion >= 68){
          $sslfile =~ s/_SSL//;
          return "/var/cpanel/ssl/apache_tls/$sslfile/certificates";
     }
     else{
          foreach my $line (@file) {
               chomp($line);
               if ($line =~ /^sslcertificatefile: /) {
                   $crtfile = $line;
                   $crtfile =~ s/^sslcertificatefile: //;
                   return $crtfile;
               }
          }
     }
     return "";
}

# Determine whether we are on Plesk or cPanel, then call the appropriate diskusage subroutine.
sub lookup_diskusage {
     my $self = shift;
     if (-e "/etc/psa/.psa.shadow") {
          plesk_lookup_diskusage($self);
     }else {
          cpanel_lookup_diskusage($self);
     }
}

#Populate the following fields: $self->{diskusage}
#                               $self->{diskunits}
#                               $self->{mysqldiskusage} - Not looked up.  Populated with "NA"
#                               $self->{mysqlunits}     - Not looked up.  Populated with "NA"
#                               $self->{totaldiskusage} - Populated directly from $self->{diskusage}
#                               $self->{totalunits}     - Populated directly from $self->{diskunits}
#                               $self->{databases}
sub plesk_lookup_diskusage {
     my $self = shift;
     my $diskusage;
     my $diskunits;
     my $databases;
     $self->{mysqldiskusage} = "NA";
     $self->{mysqlunits}     = "NA";
     #/usr/local/psa/bin/client -i renew |egrep '(Disk usage:|MySQL databases:)'
     my $cmdline = "/usr/local/psa/bin/client -i " . $self->{username} . " |egrep '(Disk usage:|MySQL databases:)'";
     my @output = `$cmdline`;
     if (($? >> 8) > 0) {     #Check the return code, and exit if the external call failed.
          return ($? >> 8);
     }
     foreach my $line (@output) { #Put the addon domains that are in @addons into the object's addon array.
          chomp ($line);
          if ($line =~ /Disk usage:/) {
               $diskusage = $line;
               $diskusage =~ s/.*: *//;
               $diskusage =~ s/ .*//;
               $self->{'diskusage'} = $diskusage;
               $diskunits = $line;
               $diskunits =~ s/.* //;
               $self->{'diskunits'} = $diskunits;
          }
          if ($line =~ /MySQL databases:/) {
               $databases = $line;
               $databases =~ s/.* //;
               $self->{'databases'} = $databases;
          }
     }
     $self->{totaldiskusage} = $self->to_bytes($diskusage, $diskunits);
     $self->{totalunits} = "Bytes";

}

#Populate disk usage and other info. pulled from StatsBar.
sub cpanel_lookup_diskusage {
     my $self = shift;
     my $url = "json-api/cpanel".
               "?user=" . $self->{username}.
               "&cpanel_jsonapi_apiversion=2".
               "&cpanel_jsonapi_module=StatsBar".
               "&cpanel_jsonapi_func=stat".
               "&display=diskusage|mysqldiskusage|sqldatabases|addondomains|bandwidthusage";
     my $jsondata = $self->cpanel_jsonapi($url);
     if (! $jsondata) {
         $self->logg( RED . "Error looking up disk usage info.\n" . RESET, 1);
         return 1; #Error
     }
     if ($self->cpanel_lookup_statsbar($jsondata, "diskusage")) { #If the "diskusage" section of the StatsBar data exists,
          $self->{diskusage}        = $self->cpanel_lookup_statsbar($jsondata, "diskusage")->{_count}; # then set the values.
          $self->{diskunits}        = $self->cpanel_lookup_statsbar($jsondata, "diskusage")->{units};
          $self->{disklimit}        = $self->cpanel_lookup_statsbar($jsondata, "diskusage")->{max};
          $self->{disklimit}        =~ s/[^a-zA-Z0-9,.]/ /;
          $self->{diskpercent}      = $self->cpanel_lookup_statsbar($jsondata, "diskusage")->{percent};
     }
     if ($self->cpanel_lookup_statsbar($jsondata, "mysqldiskusage")) {
          $self->{mysqldiskusage}   = $self->cpanel_lookup_statsbar($jsondata, "mysqldiskusage")->{_count};
          $self->{mysqldiskusage}   = $self->to_units($self->{mysqldiskusage});
          $self->{mysqlunits}       = $self->{mysqldiskusage};
          #Both $self->{mysqldiskusage} and $self->{mysqlunits} have the same thing now (i.e. 20.27 MB)
          $self->{mysqldiskusage}   =~ s/ .*//; # Now let's get rid of the " MB" in $self->{mysqldiskusage}
          $self->{mysqlunits}       =~ s/.* //; # and get rid of the "20.27 " in $self->{mysqlunits}.
     }
     if ($self->cpanel_lookup_statsbar($jsondata, "sqldatabases")) {
          $self->{databases}        = $self->cpanel_lookup_statsbar($jsondata, "sqldatabases")->{count};
     }
     if ($self->cpanel_lookup_statsbar($jsondata, "addondomains")) {
          $self->{maxaddons}        = $self->cpanel_lookup_statsbar($jsondata, "addondomains")->{max};
          $self->{maxaddons}        =~ s/ //g; #Remove any spaces.
     }
     if ($self->cpanel_lookup_statsbar($jsondata, "bandwidthusage")) {
          $self->{bandwidthusage}   = $self->cpanel_lookup_statsbar($jsondata, "bandwidthusage")->{_count};
          $self->{bandwidthunits}   = $self->cpanel_lookup_statsbar($jsondata, "bandwidthusage")->{units};
          $self->{bandwidthlimit}   = $self->cpanel_lookup_statsbar($jsondata, "bandwidthusage")->{max};
          $self->{bandwidthlimit}   =~ s/[^a-zA-Z0-9,.]/ /;
          $self->{bandwidthlimit}   =~ s/\.//; #Get rid of decimals because 1000 MB shows up as 1.000 MB.
          $self->{bandwidthpercent} = $self->cpanel_lookup_statsbar($jsondata, "bandwidthusage")->{percent};
     }
     my $byte_diskusage      = $self->to_bytes($self->{diskusage},      $self->{diskunits});
     my $byte_mysqlusage     = $self->to_bytes($self->{mysqldiskusage}, $self->{mysqlunits});
     $self->{totaldiskusage} = $byte_diskusage; #->{totaldiskusage} is same as ->{diskusage} except that it's bytes.
                                                # cPanel, by default, includes MySQL in with the disk usage.
     $self->{totalunits} = "Bytes";
     return 0;
}

# Look up a section of data in StatsBar output.
# Input:  Reference to the decoded StatsBar json data.
#         Name of the requested section (i.e. "diskusage", "mysqldiskusage", etc.
# Output: Reference to the requested section of data.
#         undef if the section is not found.
sub cpanel_lookup_statsbar {
     my $self               = shift;
     my $jsondata           = shift;
     my $requested_section  = shift;
     foreach my $section (@{$jsondata->{cpanelresult}->{data}}) {
          if ($section->{name} eq $requested_section) {
               return $section;
          }
     }
     return undef;
}

# Convert a number from gigabytes, megabytes or kilobytes into bytes.
# Input:  Number to covert
#         Units that number is currently represented in.
# Output: Number of bytes.
#         undef if either input is undefined.
sub to_bytes {
     my $self  = shift;
     my $value = shift;
     my $units = shift;
     if (!$value || !$units) {
          return undef;
     }
     $value =~ s/,//g; # Remove any commas so the calculations work.
     if ($units eq "GB") {
          $value = $value * 1073741824;
     }elsif ($units eq "MB") {
          $value = $value * 1048576;
     }elsif ($units eq "KB") {
          $value = $value * 1024;
     }
     return $value;
}

# Convert a number from bytes into a more readable format with units.
# Input:  bytes
# Output example: "23.45 MB"
sub to_units {
     my $self  = shift;
     my $value = shift;
     if ($value > 1073741824) {
          $value = sprintf("%.2f", $value / 1073741824);
          $value = $value . " GB";
     }elsif ($value > 1048576){
          $value = sprintf("%.2f", $value / 1048576);
          $value = $value . " MB";
     }elsif ($value > 1024) {
          $value = sprintf("%.2f", $value / 1024);
          $value = $value . " KB";
     }else {
          $value = $value . " Bytes";
     }
     return $value;
}

# This cPanel account may also be a reseller.  Look up the list of usernames owned by this reseller.
# Input: $self
# Output: Return value 0 = OK, 1 = Error.
#         $self->{clients}
#         $self->{clients_diskusage}
#         $self->{clients_diskquota}
#         $self->{clients_bandwidthusage}
#         $self->{clients_bandwidthlimit}
sub cpanel_lookup_clients {
     my $self = shift;
     my $url = "json-api/resellerstats?reseller=" . $self->{username};
     my $jsondata = $self->cpanel_jsonapi($url);
     if (! $jsondata) {
         $self->logg( RED . "Error looking up reseller stats.\n" . RESET, 1);
         return 1; #Error
     }
     if ($jsondata->{result}->{status} ne "1") {
         $self->logg( RED . "cPanel API error looking up reseller stats.\n" . RESET, 1);
         return 1; #Error
     }
     $self->{resellerbandwidth} = $jsondata->{result}->{bandwidthlimit};
     $self->{resellerquota}     = $jsondata->{result}->{diskquota};
     $self->{totaldiskalloc}    = $jsondata->{result}->{totaldiskalloc};
     $self->{totalbwalloc}      = $jsondata->{result}->{totalbwalloc};
     foreach my $acct (@{$jsondata->{result}->{accts}}) {
          if ($acct->{deleted} eq "0") {
               push (@{ $self->{clients} }, $acct->{user});
               $self->{clients_diskusage}{$acct->{user}}      = $acct->{diskused};
               $self->{clients_diskquota}{$acct->{user}}      = $acct->{diskquota};
               $self->{clients_bandwidthusage}{$acct->{user}} = $acct->{bandwidthused};
               $self->{clients_bandwidthlimit}{$acct->{user}} = $acct->{bandwidthlimit};
          }
     }
     return 0;
}

sub dump {
     my $self = shift;
     $self->logg("User:        " . $self->{username} . "\n", 1);
     $self->logg("Primary Dom: " . $self->{primarydomain} . "\n", 1);
     $self->logg("Partition:   " . $self->{partition} . "\n", 1);
     $self->logg("IP:          " . $self->{ip} . "\n", 1);
     $self->logg("Owner:       " . $self->{owner} . "\n", 1);
     $self->logg("Plan:        " . $self->{plan} . "\n", 1);
     $self->logg("NS1:         " . $self->{ns1} . "\n", 1);
     $self->logg("NS2:         " . $self->{ns2} . "\n", 1);
     $self->logg("NS1IP:       " . $self->{ns1ip} . "\n", 1);
     $self->logg("NS2IP:       " . $self->{ns2ip} . "\n", 1);
     $self->logg("Databases:   " . $self->{databases} . "\n", 1);
     $self->logg("Disk usage:  " . $self->{diskusage} . " " . $self->{diskunits} . "\n", 1);
     $self->logg("MySQL usage: " . $self->{mysqldiskusage} . " " .  $self->{mysqlunits} . "\n", 1);
     my $totaldiskusage = $self->to_units($self->{totaldiskusage});
     $self->logg("Total usage: $totaldiskusage\n", 1);
     $self->logg("Addons:\n", 1);
     my $index = 0;
     foreach my $addon (@{ $self->{addons} }) {
          $addon =~ s/:.*//;
          $self->logg($addon . " - " . @{ $self->{addondirs}}[$index] . "\n", 1);
          $index = $index + 1;
     }
     $self->logg("Subdomains:\n", 1);
     my $index = 0;
     foreach my $subdomain (@{ $self->{subdomains} }) {
          $self->logg($subdomain . " - " . @{ $self->{subdomaindirs}}[$index] . "\n", 1);
          $index = $index + 1;
     }
}

# Populate $self->{ns1}, $self->{ns2}, $self->{ns1ip}, $self->{ns2ip}
# Input:  $self
# Output: 0=OK, 1=Error.
sub setnameservers {
     my $self = shift;
     my $primarydomain = $self->{primarydomain};
     my $ip            = $self->{ip};
     my $nscount       = 0;
     my @hostoutput = `host -t ns $primarydomain $ip`; #Look up the NS records.
     my @nameservers;
     if (($? >> 8) > 0) {     #Check the return code, and exit if the external call failed.
          $self->logg(RED . "The nameservers for $primarydomain are not configured correctly.  " . RESET . "There should normally be two NS records in the zone file for $primarydomain.  The result of the following command triggered this error: \"host -t ns $primarydomain $ip\".  Note that if $primarydomain is not the domain name you are working with, please note that it may be the primary domain of another account such as a reseller client.\n", 1);
          foreach my $line (@hostoutput) { #Show the output from the failed command.
               $self->logg(RED . $line . RESET, 1);
          }
          return 1;
     }
     foreach my $line (@hostoutput) {
          if ($line =~ /name server/) {
               chomp($line);
               $line =~ s/.*name server //;
               $line =~ s/\.$//;
               if ($nscount == 0) {
                    push (@nameservers, $line);
                    $nscount = $nscount + 1;
               }elsif ($nscount == 1) {
                    push (@nameservers, $line);
                    $nscount = $nscount + 1;
               }else {
                    $self->logg( RED . "There are more than two nameservers for this $primarydomain.  This could indicate a problem.  I'll show the first two.\n" . RESET, 1);
                    last;
               }
          }
     }
     if ($nscount < 2) {
          $self->logg(RED . "DNS is not configured correctly for $primarydomain.  " . RESET . "There should be at least two nameservers for $primarydomain.  Please check the zone file for $primarydomain.  Sometimes this error can be caused by the cPanel account having an ip address that isn't on the server.  Make sure that ifconfig lists $ip as one of the ip addresses.\n", 1);
          return 1;
     }
     @nameservers = sort @nameservers; #Nameservers are shown in round robin order, so we sort before setting the member variables.
     $self->{ns1} = $nameservers[0];
     $self->{ns2} = $nameservers[1];
     if ($self->{ns1} eq "ns1.com" || $self->{ns1} eq "ns2.com" || $self->{ns2} eq "ns1.com" || $self->{ns2} eq "ns2.com") {
          $self->logg(RED . "The nameservers for this server are showing as " . $self->{ns1} . " and " . $self->{ns2} . ".  This indicates that the nameservers are not configured correctly.\n" . RESET, 1);
          return 1;
     }
     my $ns1 = $self->{ns1};
     my @hostoutput = `host -t a $ns1 $ip`; #Look up the A record for NS1
     if (($? >> 8) > 0) {     #Check the return code, and exit if the external call failed.
          $self->logg(RED . "The nameservers for $primarydomain are not configured correctly.  " . RESET . "According to the DNS service on this server, there is no IP address for $ns1.  The DNS service on this server needs to have an A record for $ns1 because $ns1 is listed as a nameserver for $primarydomain.  The result of the following command triggered this error: \"host -t a $ns1 $ip\"\n", 1);
          foreach my $line (@hostoutput) { #Show the output from the failed command.
               $self->logg($line, 1);
          }
          if ($ns1 =~ /\.(hostgator\.(com(\.(tr|br))?|in)|(websitewelcome|webhostsunucusu|ehost(s)?|ideahost|hostclear)\.com|websitedns\.in|prodns\.com\.br)$/) {
               $self->logg("Even though a problem was found, since this appears to be a shared server, and this type of issue typically does not cause problems for customers, I am continuing.\n", 1);
          }else {
               return 1;
          }
     }
     my $count = 0;
     foreach my $line (@hostoutput) {
          if ($line =~ /has address/) {
               chomp($line);
               $line =~ s/.*has address //;
               if ($count == 0) {
                    $self->{ns1ip} = $line;
                    $nscount = $count + 1;
               }else {
                    $self->logg("There is more than 1 A record for this nameserver: $ns1.  This could indicate a problem.  I'll use the first one.\n", 1);
                    last;
               }
          }
     }
     my $ns2 = $self->{ns2};
     my @hostoutput = `host -t a $ns2 $ip`; #Look up the A record for NS2
     if (($? >> 8) > 0) {     #Check the return code, and exit if the external call failed.
          $self->logg(RED . "The nameservers for $primarydomain are not configured correctly.  " . RESET . "According to the DNS service on this server, there is no IP address for $ns2.  The DNS service on this server needs to have an A record for $ns2 because $ns2 is listed as a nameserver for $primarydomain.  The result of the following command triggered this error: \"host -t a $ns2 $ip\"\n", 1);
          foreach my $line (@hostoutput) { #Show the output from the failed command.
               $self->logg($line, 1);
          }
          if ($ns2 =~ /\.(hostgator\.(com(\.(tr|br))?|in)|(websitewelcome|webhostsunucusu|ehost(s)?|ideahost|hostclear)\.com|websitedns\.in|prodns\.com\.br)$/) {
               $self->logg("Even though a problem was found, since this appears to be a shared server, and this type of issue typically does not cause problems for customers, I am continuing.\n", 1);
          }else {
               return 1;
          }
     }
     my $count = 0;
     foreach my $line (@hostoutput) {
          if ($line =~ /has address/) {
               chomp($line);
               $line =~ s/.*has address //;
               if ($count == 0) {
                    $self->{ns2ip} = $line;
                    $nscount = $count + 1;
               }else {
                    $self->logg("There is more than 1 A record for this nameserver: $ns2.  This could indicate a problem.  I'll use the first one.\n", 1);
                    last;
               }
          }
     }
     if ($self->{ns1ip} eq $self->{ns2ip}) {
          $self->logg(RED . "The nameservers for $primarydomain are not configured correctly.  " . RESET . "Both nameservers (" . $self->{ns1} . " and " . $self->{ns2} . ") have the same IP address (" . $self->{ns1ip} . ").  Please set them to different IP addresses.\n", 1);
          if ($ns1 =~ /\.(hostgator\.(com(\.(tr|br))?|in)|(websitewelcome|webhostsunucusu|ehost(s)?|ideahost|hostclear)\.com|websitedns\.in|prodns\.com\.br)$/) {
               $self->logg("Even though a problem was found, since this appears to be a shared server, and this type of issue typically does not cause problems for customers, I am continuing.\n", 1);
          }else {
               return 1;
          }
     }

     if ($self->{owner} eq $self->{username} or $self->{owner} eq "root") {
     	  $self->{ownerns1} = $self->{ns1};
     	  $self->{ownerns2} = $self->{ns2};
     	  $self->{ownerns1ip} = $self->{ns1ip};
     	  $self->{ownerns2ip} = $self->{ns2ip};
     } elsif ($self->{owner} ne "" ) {
     	  my $owner = Userdata->new("localhost", $self->{owner}, $self->{loggobj}, $self->{token});
          $self->{ownerns1} = $owner->{ns1};
          $self->{ownerns2} = $owner->{ns2};
          $self->{ownerns1ip} = $owner->{ns1ip};
          $self->{ownerns2ip} = $owner->{ns2ip};
     }
     return 0;
}

sub plesk_setsubdomains {
     my $self = shift;
     my $username = $self->{username};
     my $mysqlpass = $self->{mysqlpass};
     my @subdomains;
     my $subdomain;
     # Look up the subdomains and put them into @subdomains array.
     @subdomains = `mysql -ss -u'admin' -p'$mysqlpass' -e"select subdomains.name, domains.name, subdomains.www_root from subdomains inner join sys_users on sys_users.id=subdomains.sys_user_id inner join domains on domains.id=subdomains.dom_id where sys_users.login = '$username';" psa`;
     if (($? >> 8) > 0) {     #Check the return code, and exit if the external call failed.
          return ($? >> 8);
     }
     foreach my $line (@subdomains) { #Put the addon domains that are in @addons into the object's addon array.
          chomp ($line);
          my $sub = $line;
          $sub =~ s/\t.*//;
          $sub =~ s/ .*//;
          my $domain = $line;
          $domain =~ s/.*?\t//;
          $domain =~ s/.*? //;
          $domain =~ s/\t.*//;
          $domain =~ s/ .*//;
          $subdomain = "$sub.$domain";
          my $dir = $line;
          $dir =~ s/.*\t//;
          $dir =~ s/.* //;
          push (@{ $self->{subdomains} }, "$subdomain"); #add the subdomain to the subdomain array.
          push (@{ $self->{subdomaindirs} }, "$dir");    #add the subdomain directory to the subdomain directory array.
          $self->{subdomain_subdomaindir}{$subdomain} = $dir;
          $self->{subdomaindir_subdomain}{$dir} = $subdomain;
     }
     return 0;
}

# Populate subdomain members from a cPanel API call.
# Input: $self
# Output: $self->{subdomains}
#         $self->{subdomaindirs}
#         $self->{subdomain_subdomaindir}
#         $self->{subdomaindir_subdomain}
#         Returns 0 if ok, 1 if error.
sub cpanel_setsubdomains {
     my $self = shift;
     my $url = "json-api/cpanel?user=" . $self->{username} . "&cpanel_jsonapi_module=SubDomain&cpanel_jsonapi_func=cplistsubdomains&cpanel_jsonapi_apiversion=1";
     my $jsondata = $self->cpanel_jsonapi($url);
     if (! $jsondata) {
         $self->logg( RED . "Error looking up reseller subdomains.\n" . RESET, 1);
         return 1; #Error
     }
     my $all_subdomains_str = $jsondata->{data}->{result}; # This a a multi-line string that has all of the subdomain info on separate lines.
     my @all_subdomains = split("\n", $all_subdomains_str);
     foreach my $subdomain_line (@all_subdomains) {
          $subdomain_line =~ m/([^\s]+) \(([^\s]+)\).*/;
          my $subdomain = $1;
          my $dir       = $2;
          $dir = "/" . $self->{partition} . "/" . $self->{username} . "/" . $dir;
          if (havesubdomain($self, $subdomain) == 0) {        #If we don't already have this subdomain listed, then
               push (@{ $self->{subdomains} }, "$subdomain"); #add the subdomain to the subdomain array.
               push (@{ $self->{subdomaindirs} }, "$dir");    #add the subdomain directory to the subdomain directory array.
               $self->{subdomain_subdomaindir}{$subdomain} = $dir;
               $self->{subdomaindir_subdomain}{$dir} = $subdomain;
          }
     }
     return 0;
}

# Find out if a subdomain is already listed as the sub of an addon domain.
# Input:  $self
#         Subdomain
# Output: 0 = no
#         1 = yes
sub havesubdomain {
     my $self      = shift;
     my $subdomain = $_[0];
     my $ret       = 0;
     foreach my $line (@{ $self->{addonsubdomains} }) {
          if ($line eq $subdomain) {
               $ret = 1;
               last;
          }
     }
     return $ret;
}

sub plesk_setaddons {
     my $self = shift;
     my $username = $self->{username};
     my $mysqlpass = $self->{mysqlpass};
     my @addons;
     my $domainid;
     my $addondir;
     # Look up the domain ID of the primary domain.
     $domainid = `mysql -ss -u'admin' -p'$mysqlpass' -e"select hosting.dom_id from hosting inner join sys_users on hosting.sys_user_id=sys_users.id inner join domains on domains.id=hosting.dom_id where sys_users.login = '$username' and domains.webspace_id=0 limit 1;" psa`;
     if (($? >> 8) > 0) {     #Check the return code, and exit if the external call failed.
          return ($? >> 8);
     }
     chomp($domainid);
     if (length($domainid) == 0) {
          $self->logg("Domain ID of $username not found.  It could be that this is the username for an addon domain?\n", 1);
          return 1;
     }
     # Look up the addon domains and put them into @addons array.
     @addons = `mysql -ss -u'admin' -p'$mysqlpass' -e "select name from domains where webspace_id=$domainid;" psa`;
     if (($? >> 8) > 0) {         #Check the return code, and exit if the external call failed.
          return ($? >> 8);
     }
     foreach my $addon (@addons) { #Put the addon domains that are in @addons into the object's addon array.
          chomp ($addon);
          push (@{ $self->{addons} }, "$addon");
          $addondir = ""; #Make sure the addondir var has nothing left over since we are using it repeatedly.
          $addondir = `mysql -ss -u'admin' -p'$mysqlpass' -e "select hosting.www_root as 'Document Root' from domains inner join hosting on domains.id=hosting.dom_id where domains.name='$addon' limit 1;" psa`; #Look up the directory of the addon domain.
          chomp($addondir);
          push (@{ $self->{addondirs} }, "$addondir");
          $self->{addon_addondir}{$addon} = $addondir;
          $self->{addondir_addon}{$addondir} = $addon;
     }
     return 0;
}

sub plesk_setparkeddomains {
     my $self = shift;
     my $username = $self->{username};
     my $mysqlpass = $self->{mysqlpass};
     my $domainid;
     # Look up the domain ID of the primary domain.
     $domainid = `mysql -ss -u'admin' -p'$mysqlpass' -e"select hosting.dom_id from hosting inner join sys_users on hosting.sys_user_id=sys_users.id inner join domains on domains.id=hosting.dom_id where sys_users.login = '$username' and domains.webspace_id=0 limit 1;" psa`;
     if (($? >> 8) > 0) {     #Check the return code, and exit if the external call failed.
          return ($? >> 8);
     }
     chomp($domainid);
     if (length($domainid) == 0) {
          $self->logg("Domain ID of $username not found.  It could be that this is the username for an addon domain?\n", 1);
          return 1;
     }
     # Look up the domain aliases and their associated directories.
     my @parkeddomains = `mysql -ss -u'admin' -p'$mysqlpass' -e"select domainaliases.name, hosting.www_root from domainaliases left join hosting on domainaliases.dom_id = hosting.dom_id where domainaliases.dom_id = '$domainid';" psa`;
     if (($? >> 8) > 0) {
          # If this failed, it could be Plesk 11 which changed a table name.
          @parkeddomains = `mysql -ss -u'admin' -p'$mysqlpass' -e"select domain_aliases.name, hosting.www_root from domain_aliases left join hosting on domain_aliases.dom_id = hosting.dom_id where domain_aliases.dom_id = '$domainid';" psa`;
          if (($? >> 8) > 0) {
               return ($? >> 8);
          }
     }
     foreach my $line (@parkeddomains) {
          my $parked =  $line;
          $parked =~ s/^ *//;
          $parked =~ s/ .*//;
          $parked =~ s/\t.*//;
          chomp ($parked);
          my $parkeddir    = $line;
          $parkeddir       =~ s/.* //;
          $parkeddir       =~ s/.*\t//;
          chomp ($parkeddir);
          if (length($parked) > 0 && length($parkeddir) > 0) { 
               $self->{parked_parkeddir}{$parked}  = $parkeddir;
               $self->{parkeddir_parked}{$parkeddir} = $parked;
          }
     }
}

# Look up parked domains
# Input:  $self
# Output: Hash arrays $self->{parked_parkeddir}
#                     $self->{parkeddir_parked}
#         Return value 0=OK, 1=Error.
sub cpanel_setparkeddomains {
     my $self = shift;
     my $url = "json-api/cpanel?user=" . $self->{username} . "&cpanel_jsonapi_module=Park&cpanel_jsonapi_func=listparkeddomains&cpanel_jsonapi_apiversion=2";
     my $jsondata = $self->cpanel_jsonapi($url);
     if (! $jsondata) {
         $self->logg( RED . "Error looking up parked domains.\n" . RESET, 1);
         return 1; #Error
     }
     foreach my $parked (@{$jsondata->{cpanelresult}->{data}}) {
          $self->{parked_parkeddir}{$parked->{domain}} = $parked->{dir};
          $self->{parkeddir_parked}{$parked->{dir}}    = $parked->{domain};
     }
     return 0;
}

# Call the cPanel API to list the addon domains, then add them to our addon list.
# Input:  $self
# Output: $self->{addons}
#         $self->{addondirs}
#         $self->{addonsubdomains}
#         $self->{addon_addondir}
#         $self->{addondir_addon}
#         $self->{domainkeys} }
#         Returns 0 if ok, 1 if error.
sub cpanel_setaddons {
     my $self = shift;
     my $url = "json-api/cpanel?user=" . $self->{username} . "&cpanel_jsonapi_module=AddonDomain&cpanel_jsonapi_func=listaddondomains&cpanel_jsonapi_apiversion=2";
     my $jsondata = $self->cpanel_jsonapi($url);
     if (! $jsondata) {
          $self->logg( RED . "Error looking up addon domains.\n" . RESET, 1);
          return 1; #Error
     }
     foreach my $addon (@{$jsondata->{cpanelresult}->{data}}) { #Loop through the addons from the JSON data and set the memeber variables.
          push (@{ $self->{addons} },                      "$addon->{domain}:$addon->{fullsubdomain}");
          push (@{ $self->{addondirs} },                    $addon->{dir});
          push (@{ $self->{addonsubdomains} },              $addon->{fullsubdomain});
          push (@{ $self->{domainkeys} },                   $addon->{domainkey});
          $self->{addon_addondir}{$addon->{domain}}       = $addon->{dir};
          $self->{addon_addonsubdomain}{$addon->{domain}} = $addon->{fullsubdomain};
          $self->{addondir_addon}{$addon->{dir}}          = $addon->{domain};
     }
     return 0;
}

sub plesk_setprimaryinfo {
     my $self = shift;
     my $username = $self->{username};
     my $ip;
     my $iptype;
     my $primarydomain;
     my $mysqlpass = $self->{mysqlpass};
     # Look up the primary domain name.
     $primarydomain = `mysql -ss -u'admin' -p'$mysqlpass' -e"select domains.name from hosting inner join sys_users on hosting.sys_user_id=sys_users.id inner join domains on domains.id=hosting.dom_id where sys_users.login = '$username' and domains.webspace_id=0 limit 1;" psa`;
     if (($? >> 8) > 0) {     #Check the return code, and exit if the external call failed.
          return ($? >> 8);
     }
     chomp($primarydomain);
     $self->{primarydomain} = $primarydomain;
     # Look up the IP address from the primary domain.
     $ip = `mysql -ss -u'admin' -p'$mysqlpass' -e "SELECT IP_Addresses.ip_address FROM IP_Addresses INNER JOIN domains ON domains.name = '$primarydomain' INNER JOIN clients ON clients.id=domains.cl_id INNER JOIN ip_pool ON ip_pool.id=clients.pool_id WHERE IP_Addresses.id = ip_pool.ip_address_id limit 1;" psa`;
     if (($? >> 8) > 0) {     #Check the return code, and exit if the external call failed.
          return ($? >> 8);
     }
     chomp($ip);
     $self->{ip} = $ip;
     # Look up the IP address type (shared or exclusive).
     $iptype = `mysql -ss -u'admin' -p'$mysqlpass' -e "select ip_pool.type from IP_Addresses inner join ip_pool on IP_Addresses.id=ip_pool.ip_address_id where IP_Addresses.ip_address = '$ip' limit 1;" psa`;
     if (($? >> 8) > 0) {     #Check the return code, and exit if the external call failed.
          return ($? >> 8);
     }
     chomp($iptype);
     if ($iptype =~ /exclusive/) { #The above query will return "shared" or "exclusive".  Set $self->{dedicatedip} according to this result.
          $self->{dedicatedip} = 1;
     }elsif($iptype =~ /shared/) {
          $self->{dedicatedip} = 0;
     }else{
          return 1; #If the $iptype isn't "shared" or "exclusive", then return a failure.
     }
     #Look up the FTP user
     my $cmdline = "mysql -ss -u'admin' -p`cat /etc/psa/.psa.shadow` -e\"select login from sys_users inner join hosting on sys_users.id=hosting.sys_user_id inner join domains on domains.id=hosting.dom_id where domains.name = '" . $self->{primarydomain} . "' limit 1;\" psa";
     my $output = `$cmdline`;
     if (($? >> 8) > 0) {     #Check the return code, and exit if the external call failed.
          return ($? >> 8);
     }
     chomp $output;
     $self->{'ftpuser'} = $output;
     #Look up the FTP password
     my $cmdline = "mysql -ss -u'admin' -p`cat /etc/psa/.psa.shadow` -e\"select password from accounts where id=(select account_id from sys_users inner join hosting on sys_users.id=hosting.sys_user_id inner join domains on domains.id=hosting.dom_id where domains.name = '" . $self->{primarydomain} . "' limit 1);\" psa";
     my $output = `$cmdline`;
     if (($? >> 8) > 0) {     #Check the return code, and exit if the external call failed.
          return ($? >> 8);
     }
     chomp $output;
     $self->{'ftppass'} = $output;
     #Look up the Plesk admin password
     my $cmdline = "mysql -ss -u'admin' -p`cat /etc/psa/.psa.shadow` -e\"select accounts.password from accounts inner join clients on clients.account_id=accounts.id where clients.id = (select domains.cl_id from domains where domains.name = '" . $self->{primarydomain} . "' limit 1);\" psa";
     my $output = `$cmdline`;
     if (($? >> 8) > 0) {     #Check the return code, and exit if the external call failed.
          return ($? >> 8);
     }
     chomp $output;
     $self->{'pleskpass'} = $output;
     return 0;
}

# Set the primary info. for a cPanel account.
# Input:  $self
# Output: $self->{ip}
#         $self->{dedicatedip}
#         $self->{primarydomain}
#         $self->{owner}
#         $self->{plan}
#         $self->{partition}
sub cpanel_setprimaryinfo {
     my $self = shift;
     my $url = "json-api/accountsummary?user=" . $self->{username};
     my $jsondata = $self->cpanel_jsonapi($url);
     if (! $jsondata) {
          $self->logg( RED . "Error looking up cPanel account info.\n" . RESET, 1);
          return 1; #Error
     }
     if (! $jsondata->{acct}) {
          return 1; #JSON data returned, but no account info.  Can be caused by empty username.
     }
     if ($self->{username} ne $jsondata->{acct}[0]->{user}) {
          return 1; # We just lookup up $self->{username} and it doesn't match.  Something's wrong.
     }
     $self->{ip}            = $jsondata->{acct}[0]->{ip};
     $self->{dedicatedip}   = $self->cpanel_isdedicatedip($self->{ip});
     $self->{primarydomain} = $jsondata->{acct}[0]->{domain};
     $self->{owner}         = $jsondata->{acct}[0]->{owner};
     $self->{plan}          = $jsondata->{acct}[0]->{plan};
     $self->{partition}     = $jsondata->{acct}[0]->{partition};
     return 0;
}

sub cpanel_lookup_branding {
     my $self = shift;
     
     my $url = "json-api/cpanel".
               "?user=" . $self->{username}.
               "&cpanel_jsonapi_apiversion=2".
               "&cpanel_jsonapi_module=Branding".
               "&cpanel_jsonapi_func=getbrandingpkg";
     my $jsondata = $self->cpanel_jsonapi($url);
     if (! $jsondata) {
         $self->logg( RED . "Error looking up disk usage info.\n" . RESET, 1);
         return 1; #Error
     }
     $self->{branding} = $jsondata->{cpanelresult}->{data}[0]->{brandingpkgname};
     return 0;
}

sub cpanel_isdedicatedip {
        my $self = shift;
        my $ip   = shift;
        unshift @INC, '/usr/local/cpanel';
        require Cpanel::DIp;
        my $ipdata = Cpanel::DIp::get_ip_info();
        if ($ipdata->{$ip}->{'dedicated'}) {
                return 1;
        }
        return 0;
}

# Retrieve a perl hash from the cPanel JSON API.
# Input:  $self
#         $url
# Output: Data hash with the retrieved info.
#         or undef if there was a problem.
sub cpanel_jsonapi {
     my $self = shift;
     my $url  = shift;
     my @strarray = $self->gocpanel($self->{server}, $url);  #@strarray now has the output from the cPanel API call.
     my $strdata  = join("\n", @strarray);
     my $jsondata;
     eval {$jsondata = JSON::decode_json($strdata); };  #Parse the JSON from the cPanel call.
     if (! $jsondata) {
          $self->logg( RED . "Error looking up addon domains.\n" . RESET, 1);
          return undef; #Error
     }
     return $jsondata;
} 

sub gocpanel {
        my $self   = shift;
        my $server = shift;
        my $url    = shift;
        my $localserver = `hostname`;
        if ($server eq $localserver || $server eq "localhost") {
             my @result = $self->local_gocpanel($server, $url);
             return @result;
        }else {
             my @result = $self->remote_gocpanel($server, $url);
             return @result;
        }    
}

#------------------------------------------------------------------
# Make a cPanel API call locally.
# Input: cpanel API request (i.e. "accountsummary?user=$cpuser")
# Output: Array showing the XML output of the API call.
sub local_gocpanel {
     my $self           = shift;
     my ($server, $url) = @_;
     my $apistring      = $_[0];
     my @result;
     my $tokensupport;
     my $token_name;
     my $token = $self->{token};
     my $json;
     my $currversion = +(split /\./,`cat /usr/local/cpanel/version`)[1];
     my $auth;
     my $command;
     my $hash;
     my $ua;
     my $response;
     if ( $currversion >= 64 ){
             $auth = "whm root:". $token;
     } else {
                if ( ! -s '/root/.accesshash' ) {
                        system('export REMOTE_USER="root"; /usr/local/cpanel/bin/realmkaccesshash');
                }
                local( $/ ) ;
                open( my $fh, "/root/.accesshash" ) or die "Failed to open /root/.accesshash\n";
                $hash = <$fh>;
                $hash =~ s/\n//g;
                $auth = "WHM root:" . $hash;
     }
     my $browser = LWP::UserAgent->new;
     if ($LWP::VERSION >= 6) {
          $browser->ssl_opts( 'verify_hostname' => 0);
     }
     $browser->ssl_opts('SSL_verify_mode' => '0');
     my $request = HTTP::Request->new( GET => "https://127.0.0.1:2087/$url" );
     $request->header( Authorization => $auth );
     my $response = $browser->request( $request );
     #$self->logg($response->content . "\n", 1);
     if ($response->is_error()) {
          $self->logg(RED . "Error: " . $response->status_line() . RESET . "\n", 1);
          if ($response->status_line() =~ /403 Forbidden/) {
               $self->logg("This error is often caused by the WHM cPHulk Brute Force Protection.  Try logging into WHM to confirm this.\nIf the WHM error confirms this, find out your external IP address from a site such as whatsmyip.org, then whitelist it on the server with this script:\n/scripts/cphulkdwhitelist <IP Address>\nThen log into WHM to flush the cPHulk database or to temporarily disable cPHulk Brute Force Protection.\n", 1);
          }
          if ($response->status_line() =~ /500/) {
               $self->logg("This error is often caused by an improperly licensed cPanel installation.  Please try logging into WHM to confirm this.\n", 1);
          }
         push (@result, "Error");
         return @result;
     }
     @result = split(/\n/, $response->content);
     return @result;
}

# Version of gcpanel that is executed from wizard.
sub remote_gocpanel {
        my $self   = shift;
        my $server = shift;
        my $url    = shift;
        my @result;
        my $command = "cat /root/.accesshash";
        my $hash = $self->get_accesshash($server, $command);
        if (!$hash) { die "[!] Access hash not found \n"; }
        my $auth = "WHM root:" . $hash;
        my $ua = LWP::UserAgent->new;
        my $request =  HTTP::Request->new( GET =>"http://$server:2086/$url");
        $request->header( Authorization =>  $auth );
        my $response = $ua->request($request);
        if ($response->is_error()) {
        $self->logg(RED . "Error: " . $response->status_line() . RESET . "\n", 1);
              if ($response->status_line() =~ /403 Forbidden/) {
                   $self->logg("This error is often caused by the WHM cPHulk Brute Force Protection.  Try logging into WHM to confirm this.\nIf the WHM error confirms this, find out your external IP address from a site such as whatsmyip.org, then whitelist it on the server with this script:\n/scripts/cphulkdwhitelist <IP Address>\nThen log into WHM to flush the cPHulk database or to temporarily disable cPHulk Brute Force Protection.\n", 1);
              }
              if ($response->status_line() =~ /500/) {
                   $self->logg("This error is often caused by an improperly licensed cPanel installation.  Please try logging into WHM to confirm this.\n", 1);
              }
              push (@result, "Error");
              return @result;
        }
        @result = split(/\n/, $response->content);
        return @result;
}

sub get_accesshash {
        my $self = shift;
        my ($target,$command) = @_;
        my $SSH_KEY="/home/hgchats/.ssh/hostgator.chats";
        # some checks, if this is null we got real issues.
        if (($command eq "")||($command =~ /^$/)||($command =~ /^\s+$/)) {
                $self->logg("[!] Our command was null! Aborting!\n", 1);
                return;
        }
#        system("sudo","-u","hgchats","/usr/bin/chatconnect",$target,$command);

        my $cmd = "sudo -u hgchats /usr/bin/chatconnect $target \"$command\"";
        #$self->logg($cmd, 1);
        my $interim = `$cmd`;
        #my $out = `$cmd`;
        my @out = split(/\r|\n/,$interim);
        my $out = join('',@out);
        return $out;
}

# Rename AWStats .txt files.  Used by mvdomain during a domain swap.
sub swap_awstats {
     my $self           = shift;
     my $preaddon       = shift;
     my $preaddonsub    = shift;
     my $postaddonsub   = shift;
     my $preprimary     = $self->{primarydomain};
     my $postprimary    = $preaddon;
     my $postaddon      = $preprimary;
     my $awstatsdir     = "/$self->{partition}/$self->{username}/tmp/awstats";
     my $dh;
     $self->{error_msg} = "";

     # Rename the files associated with the old primary domain.
     if (!opendir ($dh, $awstatsdir)) {
          $self->{error_msg} = "Failed to open directory $awstatsdir  $!";
          return 0;
     }
     my @src_files = grep { /awstats[0-9]{6}\.$preprimary\.txt/ && -f "$awstatsdir/$_" } readdir($dh);
     closedir $dh;
     foreach my $src_file (@src_files) { #Move the files
          my $dst_file =  $src_file;
          $dst_file =~ s/$preprimary/$postaddonsub/;
          if (!rename ("$awstatsdir/$src_file", "$awstatsdir/$dst_file")) {
               $self->{error_msg} = "File copy of $awstatsdir/$src_file to $awstatsdir/$dst_file failed: $!";
               return 0;
          }
     }

     # Rename the files associated with the old addon domain.
     if (!opendir ($dh, $awstatsdir)) {
          $self->{error_msg} = "Failed to open directory $awstatsdir  $!";
          return 0;
     }
     my @src_files = grep { /awstats[0-9]{6}\.$preaddonsub\.txt/ && -f "$awstatsdir/$_" } readdir($dh);
     closedir $dh;
     foreach my $src_file (@src_files) { #Move the files
          my $dst_file =  $src_file;
          $dst_file =~ s/$preaddonsub/$postprimary/;
          if (!rename ("$awstatsdir/$src_file", "$awstatsdir/$dst_file")) {
               $self->{error_msg} = "File copy of $awstatsdir/$src_file to $awstatsdir/$dst_file failed: $!";
               return 0;
          }
     }

     # Rename all of the remaining .txt files with the new primary domain name.
     if (!opendir ($dh, $awstatsdir)) {
          $self->{error_msg} = "Failed to open directory $awstatsdir  $!";
          return 0;
     }
     my @src_files = grep { /awstats[0-9]{6}\..*$preprimary\.txt/ && -f "$awstatsdir/$_" } readdir($dh);
     closedir $dh;
     foreach my $src_file (@src_files) { #Move the files
          my $dst_file =  $src_file;
          $dst_file =~ s/$preprimary/$postprimary/;
          if (!rename ("$awstatsdir/$src_file", "$awstatsdir/$dst_file")) {
               $self->{error_msg} = "File copy of $awstatsdir/$src_file to $awstatsdir/$dst_file failed: $!";
               return 0;
          }
     }

     # Remove all of the .conf files because they are all invalid and need to be regernated at the next runweblogs.
     if (!opendir ($dh, $awstatsdir)) {
          $self->{error_msg} = "Failed to open directory $awstatsdir  $!";
          return 0;
     }
     my @src_files = grep { /.*\.conf/ && -f "$awstatsdir/$_" } readdir($dh);
     closedir $dh;
     foreach my $src_file (@src_files) { #Move the files
          if (!unlink "$awstatsdir/$src_file") {
               $self->{error_msg} = "Could not delete $awstatsdir/$src_file $!";
               return 0;
          }
     }
}


# Input:  Domain
#         Dest Userdata object. 
# Output: 1=OK, 0=Fail
sub copy_awstats {
     my $self        = shift;
     my $domain      = shift;
     my $ud_user     = shift;
     my $src_domaintype;
     my $dst_domaintype;

     if ($self->{primarydomain} eq $domain) {
          $src_domaintype = "primary";
     }else{
          $src_domaintype = "addon";
     }
     if ($ud_user->{primarydomain} eq $domain) {
          $dst_domaintype = "primary";
     }else{
          $dst_domaintype = "addon";
     }
     
     if ($src_domaintype eq "primary" && $dst_domaintype eq "primary") {
          $self->{error_msg} = "Critical error in copy_awstats.  Primary to primary is unsupported.";
          return 0;
     }elsif ($src_domaintype eq "primary" && $dst_domaintype eq "addon") {
          $self->{error_msg} = "Critical error in copy_awstats.  A primary to addon AWStats migration should not be done with copy_awstats.";
          return 0;
     }elsif ($src_domaintype eq "addon" && $dst_domaintype eq "primary") {
          return $self->copy_awstats_addon_primary($domain, $ud_user);
     }elsif ($src_domaintype eq "addon" && $dst_domaintype eq "addon") {
          return $self->copy_awstats_addon_addon($domain, $ud_user);
     }
}



# Planning to make copy_awstats_primary_primary and copy_awstats_primary_addon or similar subs be the separate steps
# for a primary --> addon merge.  The problem is that the source account is removed before the destination addon is
# created.  Before the addon is created, the exact subdomain associated with the addon is not known.  After the addon
# is created, the source files no longer exist.  So we have to do this in 2 steps:
# 1) Copy the AWStats .txt files over before the source account is deleted.
# 2) rename the AWStats .txt files after the addon is created on the destination.

# Copy the AWStats files as they are for a primary --> Addon migration.
# This is called before the source cPanel is deleted.  Copied files will be renamed later by copy_awstats_post_primary_addon
sub copy_awstats_pre_primary_addon {
     my $self        = shift;
     my $domain      = shift;
     my $ud_user     = shift;
     return $self->_copy_awstats($domain, $domain, $ud_user);
}

# Rename the AWStats files that were recently copied to $ud_user from a primary domain format to
# an addon domain format.
sub copy_awstats_post_primary_addon {
     my $self         = shift;
     my $domain       = shift;
     my $ud_user      = shift;
     my $postaddonsub = $ud_user->{addon_addonsubdomain}{$domain};
     my $awstatsdir   = "/$ud_user->{partition}/$ud_user->{username}/tmp/awstats";
     my $dh;

     # Rename the files associated with the old primary domain.
     if (!opendir ($dh, $awstatsdir)) {
          $self->{error_msg} = "Failed to open directory $awstatsdir  $!";
          return 0;
     }
     my @src_files = grep { /awstats[0-9]{6}\.$domain\.txt/ && -f "$awstatsdir/$_" } readdir($dh);
     closedir $dh;
     foreach my $src_file (@src_files) { #Move the files
          my $dst_file =  $src_file;
          $dst_file =~ s/$domain/$postaddonsub/;
          if (!rename ("$awstatsdir/$src_file", "$awstatsdir/$dst_file")) {
               $self->{error_msg} = "File copy of $awstatsdir/$src_file to $awstatsdir/$dst_file failed: $!";
               return 0;
          }
     }
     return 1;
}


sub copy_awstats_addon_primary {
     my $self        = shift;
     my $domain      = shift;
     my $ud_user     = shift;
     my $src_domain  = $self->{addon_addonsubdomain}{$domain};
     return $self->_copy_awstats($src_domain, $domain, $ud_user);
}

sub copy_awstats_addon_addon {
     my $self        = shift;
     my $domain      = shift;
     my $ud_user     = shift;
     my $src_domain  = $self->{addon_addonsubdomain}{$domain};
     my $dst_domain  = $ud_user->{addon_addonsubdomain}{$domain};
     #$src_domain and $dst_domain will both be the subdomain since this is addon to addon (i.e. mydom.primary.com)
     return $self->_copy_awstats($src_domain, $dst_domain, $ud_user);
}

sub _copy_awstats {
     my $self        = shift;
     my $src_domain  = shift; # Will be either domain.tld or domain.primary.tld.
     my $dst_domain  = shift; # Will be either domain.tld or domain.primary.tld.
     my $ud_user     = shift;
     my $src_homedir = "/$self->{partition}/$self->{username}";
     my $dst_homedir = "/$ud_user->{partition}/$ud_user->{username}";  #i.e. /home/myuser      
     my $dh;
     # List the files to copy
     if (!opendir ($dh, "$src_homedir/tmp/awstats")) {
          $self->{error_msg} = "Failed to open directory $src_homedir/tmp/awstats.  $!";
          return 0;
     }
     my @src_files = grep { /awstats[0-9]{6}.$src_domain.txt/ && -f "$src_homedir/tmp/awstats/$_" } readdir($dh);
     closedir $dh;
     if (scalar(@src_files) == 0) {
          $self->{error_msg} = "No Awstats found for $src_domain";
          return 0;
     }
     my %files; #Make hash array of source -> destination filenames. (i.e. where the source filename is the key.)
     foreach my $src_file (@src_files) { #Rename the destination files.
          my $dst_file      =  $src_file;
          $dst_file         =~ s/$src_domain/$dst_domain/;
          $files{$src_file} =  $dst_file;
     }
     # Create the awstats directory if needed.
     if (not -d "$dst_homedir/tmp/awstats") {
          if (!$self->mkdir("$dst_homedir/tmp/awstats")) {
               $self->{error_msg} = "Failed to create $dst_homedir/tmp/awstats to copy Awstats data.";
               return 0;
          }
     }
     # Copy the files
     foreach my $file (keys %files) {
          if (!copy ("$src_homedir/tmp/awstats/$file", "$dst_homedir/tmp/awstats/$files{$file}")) {
               $self->{error_msg} = "File copy of $src_homedir/tmp/awstats/$file to $dst_homedir/tmp/awstats/$files{$file} failed: $!";
               return 0;
          }
     }
     return 1;
}


# Rsync the email from this user to the home directory of another user.
# Input: Domain of the email addresses                       i.e. mydomain.com
#        User object of the destination user.
# Output: 0=OK
sub copy_mail {
     my $self             = shift;
     my $domain           = $_[0];
     my $ud_user          = $_[1];
     my $user_homedir     = "/" . $ud_user->{partition} . "/" . $ud_user->{username};  #i.e. /home/myuser
     my $from_mailaccts   = "/" . $self->{partition}    . "/" . $self->{username} . "/etc/"  . $domain;
     my $from_mailcontent = "/" . $self->{partition}    . "/" . $self->{username} . "/mail/" . $domain;
     my $to_mailaccts     = $user_homedir . "/etc/";
     my $to_mailcontent   = $user_homedir . "/mail/";
     my $to_passwd        = $to_mailaccts . $domain . "/passwd";
     $self->rsync_files($from_mailaccts, $to_mailaccts, "");
     $self->rsync_files($from_mailcontent, $to_mailcontent, "");
     if (-e $to_passwd) {
          $self->replace_text("\/" . $self->{username} . "\/", "\/" . $ud_user->{username} . "\/", $to_passwd); # Update the username within the passwd file.
     }else {
          return 1; #The passwd file isn't there, so don't try to update it.
     }
     return 0;
}

# Clone email.  This is like copy_mail except that the mail is being copied to a new domain.
# Input: Domain of the email addresses                       i.e. mydomain.com
#        User object of the destination user.
# Output: 0=OK
sub clone_mail {
     my $self             = shift;
     my $domain           = shift;
     my $clone_domain     = shift;
     my $ud_user          = shift;
     my $user_homedir     = "/" . $ud_user->{partition} . "/" . $ud_user->{username};  #i.e. /home/myuser
     my $from_mailaccts   = "/" . $self->{partition}    . "/" . $self->{username} . "/etc/"  . $domain . "/";
     my $from_mailcontent = "/" . $self->{partition}    . "/" . $self->{username} . "/mail/" . $domain . "/";
     my $to_mailaccts     = $user_homedir . "/etc/" . $clone_domain . "/";
     my $to_mailcontent   = $user_homedir . "/mail/" . $clone_domain . "/";
     my $to_passwd        = $to_mailaccts . $clone_domain . "/passwd";
     #Make sure the destination directories exist.
     if (!-d $to_mailaccts) {
          if (!$self->mkdir($to_mailaccts)) {
               return 1;
          }
     }
     if (!-d $to_mailcontent) {
          if (!$self->mkdir($to_mailcontent)) {
                return 1;
          }
     }
     $self->rsync_files($from_mailaccts, $to_mailaccts, "");
     $self->rsync_files($from_mailcontent, $to_mailcontent, "");
     if (-e $to_passwd) {
          $self->replace_text("\/" . $self->{username} . "\/", "\/" . $ud_user->{username} . "\/", $to_passwd); # Update the username within the passwd file.
     }else {
          return 1; #The passwd file isn't there, so don't try to update it.
     }
     return 0;
}

# Appears to be not in use but commenting just in case.
sub move_mail {
     my $self             = shift;
     my $domain           = $_[0];
     my $ud_user          = $_[1];

     print "*********** ***********\n"; #print *** to help me know if this is still used.  Otherwise I can delete later.

     my $user_homedir     = "/$ud_user->{partition}/$ud_user->{username}";  #i.e. /home/myuser
     my $from_mailaccts   = "/" . $self->{partition} . "/" . $self->{username} . "/etc/"  . $domain;
     my $from_mailcontent = "/" . $self->{partition} . "/" . $self->{username} . "/mail/" . $domain;
     my $to_mailaccts     = $user_homedir . "/etc/";
     my $to_mailcontent   = $user_homedir . "/mail/";
     my $to_passwd        = $to_mailaccts . $domain . "/passwd";
     if (-e $from_mailaccts) {
          move_file ($self, $from_mailaccts, $to_mailaccts);
          move_file ($self, $from_mailcontent, $to_mailcontent);
     }
     if (-e $to_passwd) {
          $self->replace_text("\/" . $self->{username} . "\/", "\/" . $ud_user->{username} . "\/", $to_passwd); # Update the username within the passwd file.
     }else {
          return 1; #The passwd file isn't there, so don't try to update it.
     }
     return 0;
}

#Input: Domain or subdomain
#       Destination directory
sub copy_document_root {
     my $self         = shift;
     my $domain       = $_[0];
     my $dest_docroot = $_[1];
     my $src_docroot  = lookup_docroot($self, $domain);
     if (length($src_docroot) == 0) { #if the docroot couldn't be looked up, something went wrong.
          return;                    #Since we don't return a value, return without doing anything.
     }
     if ($src_docroot !~ /\/$/) {             #If src directory doesn't end with a "/", then add one so rsync will copy the contents of the directory.
          $src_docroot = $src_docroot . "/";
     }
     my $excludes = find_excludes($self, $domain);
     if ($dest_docroot =~ $src_docroot) { #If destination docroot is within the source docroot,
          my $relative_dest_docroot = $dest_docroot;
          $relative_dest_docroot =~ s/.*\///;
          $excludes = $excludes . "--exclude='$relative_dest_docroot'";
     }
     $self->rsync_files($src_docroot, $dest_docroot, $excludes);    #rsync the document root.
}


#Input: Domain or subdomain
#       Destination directory
sub move_document_root {
     my $self                = shift;
     my $domain              = $_[0];
     my $dest_docroot        = $_[1];
     my $additional_excludes = $_[2];       #Reference to an array with additional excludes.
     my @excludes;
     my $src_docroot  = lookup_docroot($self, $domain);
     make_exclude_list($self, \@excludes, $domain);
     foreach my $exc (@{$additional_excludes}) {  #Allow for excludes in addition to the addons and subdomains added by make_exclude_list.
          push (@excludes, $exc);
     }
     #http://stackoverflow.com/questions/5502218/how-do-i-insert-new-fields-into-self-in-perl-from-a-filefind-callback
     # This find call is pivotal.  As the "first argument" we are passing it a closure {} of options.  wanted and no_chdir.
     # "wanted" is also a closure referencing the address of the wanted sub because this is the only way you can pass additional
     # arguments to the wanted sub.  Since the wanted sub is in an object, we have to pass the object hash.  We also need 3 other args.
     File::Find::find({wanted => sub {$self->movefile($src_docroot, $dest_docroot, \@excludes)}, no_chdir => 1, bydepth => 1}, $src_docroot);
     #$self->logg("*************** Cleaning up empty directories **********************\n", 1);
     #File::Find::find({wanted => sub {$self->cleanupdir($src_docroot,              \@excludes)}, no_chdir => 1}, $src_docroot);
}

#This is a callback method referenced by File::Find::find in the move_document_root method.
#It is called for every file in a directory tree.  Each time it is called, it decides whether or not
# to copy the file and copies it to $dest_docroot if necessary.
#Input:  $File::Find::name (Full path to a file)
#        $src_docroot  - The source directory to move from.
#        $dest_docroot - The directory to move to.
#        $excludes     - Reference to an array of directories to exclude from the move.
#        
sub movefile {
    my $self         = shift;
    my $src_docroot  = $_[0];
    my $dest_docroot = $_[1];
    my $excludes     = $_[2];
    my $dest;
    if (valid_to_copy($File::Find::name, $src_docroot, $excludes)) {
         #$self->logg(GREEN . $File::Find::name . RESET . "\n", 1);               #This file will be moved.
         if (-e $File::Find::name) {
              $dest = $File::Find::name;  #Calculate the destination dir.
              $dest =~ s/$src_docroot//;
              $dest = $dest_docroot . $dest;
              if (! -e $dest) {
                   $dest = chopbottomdir($dest);
                   #$self->logg(GREEN . "mv $File::Find::name $dest" . RESET . "\n", 1);
                   move_file ($self, $File::Find::name, $dest);
              }else {
                   rmdir $File::Find::name;
              }
         }else {
              #$self->logg("$File::Find::name does not exist.\n", 1);
         }
    }else {
         #$self->logg(RED . "$File::Find::name" . RESET . "\n", 1);               #This file will not be moved.
         rmdir $File::Find::name;				       #If it's an empty directory, remove it.
    }
}

#Check to see if a file is valid to copy.
#Input:  file       (i.e. mydir/file1 or /home/user/mydir/file1)
#        Source document root
#        Dest   document root
#Output: 1=copy
#        0=Don't copy.
sub valid_to_copy {
     my $testfile    = $_[0];
     my $src_docroot = $_[1];
     my $excludes    = $_[2];
     my $flag        = 1;
     $testfile    =~ s/\ /\\\ /g; #Escape characters in a filename that will cause problems.
     $testfile    =~ s/;/\\;/g;
     $testfile    =~ s/\(/\\\(/g;
     $testfile    =~ s/\)/\\\)/g;
     $testfile    =~ s/\+/\\\+/g;
     $testfile    =~ s/\&/\\\&/g;
     $testfile    =~ s/\'/\\\'/g;
     $testfile    =~ s/\[/\\\[/g;
     $testfile    =~ s/\]/\\\]/g;
     $testfile    =~ s/\</\\\</g;
     $testfile    =~ s/\>/\\\>/g;
     if ($testfile eq $src_docroot) {
          return 0;
     }
     foreach my $exclude (@{$excludes}) {
          if ($testfile =~ /^$exclude\// || $exclude =~ /$testfile/) {
               $flag = 0;
          }
     }
     return $flag;
}


#Move a file or directory from one location to the other, creating parent directories as needed.
#Input: File to move, including path.
#       Destination directory.
sub move_file {
     my $self    = shift;
     my $srcfile = $_[0];
     my $dest    = $_[1];
     my $ret;
     $srcfile =~ s/\ /\\\ /g; #Escape characters in a filename that will cause problems.
     $dest    =~ s/\ /\\\ /g;
     $srcfile =~ s/;/\\;/g;
     $dest    =~ s/;/\\;/g;
     $srcfile =~ s/\(/\\\(/g;
     $dest    =~ s/\(/\\\(/g;
     $srcfile =~ s/\)/\\\)/g;
     $dest    =~ s/\)/\\\)/g;
     $srcfile =~ s/\+/\\\+/g;
     $dest    =~ s/\+/\\\+/g;
     $srcfile =~ s/\&/\\\&/g;
     $dest    =~ s/\&/\\\&/g;
     $srcfile =~ s/\'/\\\'/g;
     $dest    =~ s/\'/\\\'/g;
     $srcfile =~ s/\[/\\\[/g;
     $dest    =~ s/\[/\\\[/g;
     $srcfile =~ s/\]/\\\]/g;
     $dest    =~ s/\]/\\\]/g;
     $srcfile =~ s/\</\\\</g;
     $dest    =~ s/\</\\\</g;
     $srcfile =~ s/\>/\\\>/g;
     $dest    =~ s/\>/\\\>/g;
     if (! -e $dest) {   # If the destination dir doesn't exist.  Make it.
          if (!$self->mkdir($dest)) {
               $self->logg("Could not make the directory $dest\n", 1);
               return 1;
          }
     }
     #$self->logg("mv $srcfile $dest\n", 1);
     my @output = `mv $srcfile $dest 2>&1`;
     foreach my $out (@output) { #Print the output from the external call.
          $self->logg($out, 1);
     }
     if (($? >> 8) > 0) {        #Check the return code, and exit if the external call failed.
          $ret = ($? >> 8);
          $self->logg("Could not mv $srcfile $dest\n", 1);
          return $ret;
     }
     return 0;
}

# Chop off the bottom part of a path.  (i.e. chop of the file or directory to the right of the last "/".
# Input: Full directory path (i.e. /var/www/vhosts/mydomain.tld/httpdocs)
# Output: Rightmost directory chopped (i.e. /var/www/vhosts/mydomain.tld)
sub chopbottomdir {
     my $fullpath = $_[0];
     #Find last "/" in the fullpath and put its index into $lastloc.
     my $loc = 0;
     my $lastloc = 0; #Init the variable.
     while ($loc >= 0) {
          $lastloc = $loc;
          $loc = index($fullpath, "/", $loc+1);
     }
     my $dirpath = substr $fullpath,0,$lastloc;
     return $dirpath;
}

#Input: Source directory
#       Dest   directory
#       Excludes (i.e. --exclude='mydir1' --exclude='mydir2')
sub rsync_files {
     my $self     = shift;
     my $src      = $_[0];
     my $dest     = $_[1];
     my $excludes = $_[2];
     my $cmdline = "rsync -av --progress $excludes $src $dest 2>&1";
     $self->logg($cmdline . "\n", 1);
     my @output = `$cmdline`;
     if (($? >> 8) > 0) {     #Check the return code, and exit if the external call failed.
          return ($? >> 8);
     }
     foreach my $line (@output) { #Put the addon domains that are in @addons into the object's addon array.
          chomp ($line);
          $self->logg($line . "\n", 1);
     }
}

#Input: domain
#       Userdata (or cpbdata) object.
#Output: All of the --exclude options to be used with rsync that exclude addon document roots within the passed domains's document root.
sub find_excludes {
     my $self   = shift;
     my $domain = $_[0];
     my @dirs;
     make_exclude_list($self, \@dirs, $domain);
     my $domaindir = lookup_docroot($self, $domain) . "/";
     my $rsync = "";
     foreach my $line (@dirs) {
          $line =~ s/$domaindir//;
          $rsync = $rsync . "--exclude='" . $line . "' ";
     }
     return $rsync;
}

# Make a list of directories to exclude from an rsync.
#Input:  Userdata object
#        Reference to an array to populate with the output list.
#        Domain to transfer, excluding all other domains.
sub make_exclude_list {
     my $self    = shift;
     my $dirlist = $_[0];  #Final array of directories that we return.
     my $domain  = $_[1];
     my @dirs;             #Working array of directories.
     my $dir = lookup_docroot($self, $domain);
     lookup_docrootlist($self, \@dirs, $domain);
     lookup_subdomain_docrootlist($self, \@dirs, $domain);
     foreach my $line (@dirs) {
          if (($line =~ $dir || $dir =~ $line) && length($line) >= length($dir)) {
               push(@{$dirlist}, $line);
          }
     }
}

# Look up the document root of a domain or subdomain.
# Input: A domain name or subdomain name.
# Output: The document root in a string.
#         or "" if not found.
sub lookup_docroot {
     my $self   = shift; #UserData object
     my $domain = $_[0];
     my $docroot;
     $docroot = lookup_domain_docroot($self, $domain);
     if ($docroot eq "") {
          $docroot = lookup_subdomain_docroot($self, $domain);
     }
     return $docroot;
}

#Input:  UserData object.
#        Domain whose directory we are searching for.
#Output: Document root for that domain.
sub lookup_domain_docroot {
     my $self        = shift; #UserData object
     my $domain    = $_[0]; #Domain whose directory we are searching.
     my $domaindir = "";
     my $counter   = 0;
     if ($domain eq $self->{primarydomain}) {
          $domaindir = "/" . $self->{partition} . "/" . $self->{username} . "/public_html";
     }else {
          #Search for our domain in the addon domains.
          foreach my $line (@{$self->{addons}}) { #Search through the addon domains.
               $line =~ s/:.*//;
               if ($line eq $domain) {           #Is this the addon we're looking for?
                    $domaindir = @{$self->{addondirs}}[$counter];
                    last;
               }
               $counter++;
          }
     }
     return $domaindir;
}

# Make a list of addon domain directories for a cPanel account, excluding the domain we pass.
# Input:  cPanel Userdata object
#         Reference to an array (i.e. \@myarray)
#         Domain to exclude.
# Output: The array in the second argument is populated with the document roots of all domains in the account except the domain passed in the 3rd argument.
#         i.e. /home/user/public_html/addon1dir
#              /home/user/public_html/addon2dir
#              etc...  
sub lookup_docrootlist {
     my $self            = shift;
     my $dirlist       = $_[0];
     my $domain        = $_[1];
     my $primarydocroot = "/" . $self->{partition} . "/" . $self->{username} . "/public_html";
     my $docroot        = lookup_docroot($self, $domain);
     if ($primarydocroot ne $docroot) { #If the primary domain isn't the excluded domain, then add it to the list.
          push(@{$dirlist}, $primarydocroot);
     }
     my $index = 0;
     foreach my $addon (@{$self->{addons}}) {
          chomp ($addon);
          $addon =~ s/:.*//;
          my $addondocroot = lookup_docroot($self, $addon);
          if ($addondocroot ne $docroot) {
               my $addondir = @{$self->{addondirs}}[$index];
               push(@{$dirlist}, $addondir);
          }
          $index++;
     }
}

#Find the document roots for all subdomains in an account except for that of the domain we're transferring.
#Input:  Userdata object
#        Reference to an array to populate with the output list.
#        Domain to exclude from the list.
#Oupput: The array in the second argument is populated with the document roots of all domains in the account except the domain passed in the 3rd argument.
sub lookup_subdomain_docrootlist {
     my $self          = shift;  
     my $dirlist       = $_[0];
     my $domain        = $_[1];
     my $docroot       = lookup_docroot($self, $domain);
     my $index = 0;
     foreach my $subdomain (@{$self->{subdomains}}) { #Loop through the subdomains.
          chomp ($subdomain);
          my $subdomaindocroot = lookup_docroot($self, $subdomain);
          if ($subdomaindocroot ne $docroot) {
               my $subdomaindir = @{$self->{subdomaindirs}}[$index];
               push(@{$dirlist}, $subdomaindir);
          }
          $index++;
      }
}


#-------------------------------not done
#Input:  UserData object.
#        Domain whose directory we are searching for. (i.e. sub1.mydomain.com)
#Output: Document root for that domain.
sub lookup_subdomain_docroot {
     my $self         = shift; #UserData object passed by reference.
     my $subdomain    = $_[0]; #Domain whose directory we are searching.
     my $subdomaindir = "";
     my $index        = 0;
     $subdomain =~ s/\*/\\\*/;
     foreach my $sub (@{$self->{subdomains}}) { #Search through the addon domains.
          chomp ($sub); 
          $sub =~ s/\*/\\\*/;
          if ($sub =~ $subdomain) {           #Is this the addon we're looking for?
               $subdomaindir = @{$self->{subdomaindirs}}[$index];
               last;
          }
          $index++;
     }
     return $subdomaindir;
}

# Find inode usage for a user.
# Input:  $self->{username}
# Output: $self->{inodes} will be set to the number of inodes.
#         If inodes on the server are off, $self->{inodes} will be set to 0.
sub set_inodes {
     my $self         = shift;
     my $idx          = 0;
     my $start_idx    = 0;
     my $end_idx      = 0;
     my $inodes;
     $self->{inodes}  = 0;
     my $total_inodes = 0;
     my @qinfo = `quota -sv $self->{username}`;
     if (($? >> 8) > 0) {
          return; #Error - quota command might not be installed.
     }
     #We are parsing multiple lines in which right-justified number line up under the word "files".
     #     ... files ...
     #          1111
     #Once we find the index of the s in "files", we can start there on the next line and read backwards
     # to find the number we want.
     foreach my $line (@qinfo) {
          chomp ($line); 
          if ($idx <= 0) {
               $idx = index($line, "files");
          }else {
               $end_idx   = $idx + 4; #Set the ending index to the same position the "s" was on in the previous line.
               $start_idx = $end_idx;
               while ($start_idx > 0   # We havent run out of characters to look at
                        && (           # and the following is true:
                              (substr($line, $start_idx, 1) ge "0" && substr($line, $start_idx, 1) le "9") #It's a number
                              || substr($line, $start_idx, 1) eq "k" # or it's a "k" for kilobytes
                           )
                     ) {
                    $start_idx--;
               }
               $inodes = substr($line, $start_idx+1, $end_idx-$start_idx);
               if (length($inodes)>0) { # If we have an inode value
                    if ($inodes =~ /k/) { # If it contains a "k"
                         $inodes =~ s/k//;# Remove the k and
                         $inodes = $inodes * 1024; # multiply by 1000.
                    }
                    $self->{inodes} = $self->{inodes} + $inodes;
               }
          }
     }
}

#Replace text in a file
#Input:  Text pattern to search for
#        Text pattern to replace the first pattern with.
#        Filename to update
#Output: Updates the file.  If there's a serious error: crash and burn!
sub replace_text {
     my $self = shift;  
     my $search_pattern  = $_[0];
     my $replace_pattern = $_[1];
     my $filenam         = $_[2];

     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam or die "Error updating file $filenam\n";

     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line =~ /$search_pattern/) {
              $line =~ s/$search_pattern/$replace_pattern/g;
         }
     }
     untie @lines;
}

# Make a directory including its path as needed.
# Input:  Directory to make
# Output: 1=OK, 0=Error
sub mkdir {
     my $self = shift;
     my $dir  = shift;
     my @output = `mkdir -p $dir 2>&1`;
     if (($? >> 8) > 0) {        #Check the return code, and exit if the external call failed.
          foreach my $out (@output) {
               $self->logg ($out,1);
          }
          return 0;
     }
     return 1;
}

#Print or log the passed argument.
# Input:  A text string
# Output: If $self->{loggobj} is defined then log to the logg object.  Otherwise, print the info.
sub logg {
     my $self = shift;
     my $info_to_log = $_[0];
     my $loglevel    = $_[1];
     if ($self->{loggobj}) {
          $self->{loggobj}->logg($info_to_log, $loglevel);
     }else {
          print $info_to_log;
     }
     return 0;
}

1;
###########"
# cpbdata Perl module
# A module that gathers information from a cPanel backup file with some functions to copy data out of the backup.
# Please submit all bug reports at jira.endurance.com"
#
# (C) 2011 - HostGator.com, LLC"
###########"

=pod

=head1 Example usage for cpbdata.pm with logging:

 my $log = logg->new();
 my $ud = cpbdata->new("cpmove-myuser.tar.gz", 1, $log);
 print $ud->{primarydomain};

=head2 Example of copying a document root to a new directory:

$ud->copy_document_root("testdom2.com", "/home/newuser/public_html");

=cut

package cpbdata;
use Term::ANSIColor qw(:constants);
use Tie::File;
use File::Copy;
use strict;

sub new {                          #Constructor
     my $class = shift;
     my $self  = {};
     $self->{class}         = $class;
     $self->{archivefile}   = $_[0];
     $self->{full}          = $_[1];      #0=Only extract the files that have the info. to summarize the account.  1=Full extraction. 
     $self->{loggobj}       = $_[2];
     $self->{archivedir}    = undef;
     $self->{username}      = undef;
     $self->{primarydomain} = undef;
     $self->{ip}            = undef;
     $self->{owner}         = undef;
     $self->{partition}     = undef;
     $self->{plan}          = undef;
     $self->{contact_email} = undef;
     $self->{addons}          = [];       #Array that holds the addon domains.
     $self->{addonsubdomains} = [];       #Array that holds subdomains associated with the addon domains. i.e. mssdomain004a.info:mssdomain004a.mssdomain1.com
     $self->{addondirs}       = [];       #Array that holds addon domain directories.                     i.e. /home/mss001/public_html/mssdomain004a.info
     $self->{domainkeys}      = [];       #Array that holds the domain keys for the addon domains.        i.e. mssdomain004a_mssdomain1.com
     $self->{subdomains}      = [];       #Array that holds the subdomains not already associated with addon domains.
     $self->{subdomaindirs}   = [];       #Array that holds subdomain directories.    (currently only populated by cPanel servers)
     $self->{subdomain_subdomaindir} = {};#Hash with subdomain as the key and subdomaindir as the value
     $self->{subdomaindir_subdomain} = {};#Hash with subdomaindir as the key and subdomain as the value
     $self->{parked_parkeddir}= {};#Hash with parked domain as the key and its dir as the value. i.e. {mydomain.com} = /home/mss001/public_html
     $self->{parkeddir_parked}= {};#Hash with parked domain dir as the key and the domain as the value. i.e. {/home/mss001/public_html} = mydomain.com
     $self->{addon_addonsubdomain} = {};#Hash with addon as the key and associated subdomain as the value.  i.e. {mssdomain10.com} = mssdomain10.primary.com
     $self->{ns1}             = undef;
     $self->{ns2}             = undef;
     $self->{ns1ip}           = undef;
     $self->{ns2ip}           = undef;
     $self->{diskusage}       = undef;
     $self->{diskunits}       = undef;
     $self->{mysqldiskusage}  = undef;
     $self->{mysqlunits}      = undef;
     $self->{totaldiskusage}  = undef;
     $self->{totalunits}      = undef;
     $self->{databases}       = undef;
     $self->{inodes}          = 0;
     $self->{dblist_name}     = [];       #An array of databases.
     $self->{dblist_size}     = {};       #A hash array of database sizes where an element of dblist_name is the key.
     $self->{dblist_tables}   = {};       #A hash array showing the number of tables in each database where an element of dblist_name is the key.
     $self->{sslcerts}        = [];       #Array of strings showing SSL info.  Each element represents 1 cert, and shows the valid domains.
     $self->{sslstart}        = [];       #Array of strings showing starting date/time that the same element in sslcerts is valid.
     $self->{sslend}          = [];       #Array of strings showing ending date/time that the same element in sslcerts is valid.
     $self->{sslstatus}       = [];       #
     $self->{email_path}      = {};       #A hash array with email addresses as the key and the maildir file path as the value.
     $self->{email_pass}      = {};       #A hash array with email addresses as the key and the email password as the value.
     $self->{error}           = 0;        #Error indicator.  This will be set to 1 if there was any problem gathering the data.
     $self->{error_msg}       = undef;    #Used by copy_awstats and possibly other methods to elaborate when there are problems.
     $self->{extractedbak}    = 0;        #0=We did not extract the backup dir (so don't delete it). 1=We extracted the backup, so ok to delete it.
     bless($self, $class);
     if (-d $self->{archivefile}) {       #If the archive filename we were given is a directory, then skip the extraction.
          $self->logg("$self->{archivefile} appears to be a directory.  Skipping extraction.\n", 1);
          $self->{archivedir} = $self->{archivefile};
     }else {                              #Otherwise, extract the archive.
          if (extractbackup($self, $self->{full}) > 0) {
               $self->{error} = 1;
               return $self;
          }
     }
     if (setprimaryinfo($self)   != 0) {$self->{error} = 1; return $self;}
     if (setparkeddomains($self) != 0) {$self->{error} = 1; return $self;}
     if (lookup_ssl_info($self)  != 0) {$self->{error} = 1; return $self;}
     if (setaddons($self)        != 0) {$self->{error} = 1; return $self;}
     if (setsubdomains($self)    != 0) {$self->{error} = 1; return $self;}
     if (setnameservers($self)   != 0) {$self->{error} = 1; return $self;}
     return $self;
}

# Look up all of the email addresses for this user.
# Input:  Nothing
# Output: $self->{email_path} will be populated with all if this account's email addresses.
sub lookup_email_info {
     my $self = shift;
     $self->lookup_email_bydomain($self->{primarydomain});
     foreach my $addon (@{ $self->{addons} }) {
          $addon =~ s/:.*//;  #Remove the unnecessary subdomain info.
          $self->lookup_email_bydomain($addon);
     }
     foreach my $parked (keys %{$self->{parked_parkeddir}}) {   #todo: test
          $self->lookup_email_bydomain($parked);
     }
}

# List the email accounts for an archive in a domain
# Input:  domain name
#         Name of the archive directory.
# Output: $self->{email_path} hash array will be populated.
#           i.e. $self->{info@mydomain.com} = "/home/user/mail/mydomain.com/info";
#         Return value: 0 = OK and populated
#                       1 = No email accounts listed
#                       2 = Error
sub lookup_email_bydomain {
     my $self       = shift;
     my $domain     = $_[0];                #Domain name to list the email accounts for.
     my $archivedir = $self->{archivedir};  #i.e. Dir of extracted archive such as cpmove-myuser
     #my $emaillist  = $_[2];  #Array reference to populate.
     my $ret        = 0;
     # If we're restoring a --skiphomedir backup, the homedir won't exist.  If the transfer admin has made a homedir.tar with
     # the email content, we will need this directory.
     if (-d "$archivedir/homedir") {
          # homedir exists.
     }else {
          # homedir doesn't exist.  Make it.
          if (!$self->mkdir("$archivedir/homedir")) {
               $self->logg("Could not make the directory $archivedir/homedir.  Not extracting any files for $domain email accounts.\n",1);
               return 2;
          }
     }
     # Extract the files that contain the email addresses.
     my @output = `tar -C $archivedir/homedir -xf $archivedir/homedir.tar ./etc/$domain 2> /dev/null`;
     foreach my $out (@output) {

          #$self->logg($out,1);   #We would normally show the output, but this will error out if the domain has no email addresses.
                         # which will be common and normal.
     }
     if (($? >> 8) > 0) {     #Check the return code, and exit if the external call failed.
          $ret = ($? >> 8);
          #$self->logg("Error running tar in archive_list_email_accounts: $ret\n",1);
          #return 2;
     }
     unless (-s "$archivedir/homedir/etc/$domain/shadow") {  #Check to see if a shadow file is there for this domain's email accounts.
          $self->logg("No email shadow file found for $domain email accounts.  Skipping email for $domain.\n",1);
          return 1;                                                # It isn't, so let's return without extracting anything.
     }
     eval {
          open (INFILE, "$archivedir/homedir/etc/$domain/shadow");
          while (my $line = <INFILE>) {
               chomp($line);
               if ($line =~ /^.*:/) {
                    $line          =~ /(.*?):(.*?):.*/;  # Capture the username and password into $1 and $2. from a line like "user:$1$OgEc4rUM$y6KYO0HDq9AXFdt6i9gTq0:15513::::::"
                    my $email_user =  $1;
                    my $email      =  $email_user . "\@" . $domain;
                    my $pass       =  $2;
                    my $email_path = "/" . $self->{partition} . "/" . $self->{username} . "/mail/" . $domain . "/" . $email_user;
                    $self->{email_path}{$email} = $email_path;
                    $self->{email_pass}{$email} = $pass;
               }
          }
          close INFILE;
     } or do {
          $self->logg("Error reading $archivedir/homedir/etc/$domain/shadow",1);
          return 2;
     };
     return 0;
}

# Find forwarders line for an email address.
#  (i.e. where real email address is on left and email addresses to forward to are on the right)
# Input:  email address
# Output: Forwarder line.
#         "" if there's a problem.
sub lookup_forwarders {
     my $self   = shift;
     my $email  = shift;
     my $acct   =  $email;
     $acct      =~ s/\@.*//;  #i.e. joe
     my $domain =  $email;
     $domain    =~ s/.*\@//;  #i.e. jones.com
     my $archivedir = $self->{archivedir};
     my @file;
     my $forwarder  = "";
     unless (-s "$archivedir/va/$domain") {  #Check to see if the email forwarder file for this email address exists.
          $self->logg("File not found: $archivedir/va/$domain.  Cannot look for email forwarders for $email\n",1);
          return "";                                 # It does't, so let's return without doing anything.
     }
     eval {                                          #Now that we know the ftp file is there, read it.
          open (INFILE, "$archivedir/va/$domain");
          @file = <INFILE>;                          #Sluuuuurp
          close INFILE;
     } or do {
          $self->logg("Error reading file $archivedir/va/$domain");
          return "";
     };
     foreach my $line (@file) {
          chomp($line);
          if ($line =~ /$email:/) {
               $forwarder = $line;
               $forwarder =~ s/.*: //;
               last;
          }
     }
     return $forwarder
}

# Find aliases (i.e. where email alias is on the left and real email address is on the right.)
# Example: info@mydomain.com: joe@mydomain.com
#          admin@mydomain.com: joe@mydomain.com
#          ^^^^^^^^^^^^^^^^^^  ^^^^^^^^^^^^^^^^
#               Alias          local email address
#
#Input:  email address                               (i.e. joe@mydomain.com)
#Output: reference to an array. of email aliases.    (i.e. array with info and admin members)
# plrestorepkg will have to keep track of what aliases have already been used.  Plesk doesn't allow an alias to be added to more than one email address.
sub lookup_aliases {
     my $self    = shift;
     my $email   = shift;
     my $aliases = [];
     my $acct    =  $email;
     $acct       =~ s/\@.*//;  #i.e. joe
     my $domain  =  $email;
     $domain     =~ s/.*\@//;  #i.e. jones.com
     my $alias;
     my $archivedir = $self->{archivedir};
     my @file;
     unless (-s "$archivedir/va/$domain") {  #Check to see if the email forwarder file for this email address exists.
          $self->logg("File not found: $archivedir/va/$domain.  Cannot look for email forwarders for $email\n",1);
          return "";                                 # It does't, so let's return without doing anything.
     }
     eval {                                          #Now that we know the ftp file is there, read it.
          open (INFILE, "$archivedir/va/$domain");
          @file = <INFILE>;                          #Sluuuuurp
          close INFILE;
     } or do {
          $self->logg("Error reading file $archivedir/va/$domain");
          return "";
     };
     foreach my $line (@file) {
          chomp($line);
          if ($line =~ /:.*$email/) {
               my $fullalias = $line;   #i.e. "info@mydomain.com: joe@mydomain.com"
               $fullalias =~ s/:.*//;#i.e. "info@mydomain.com"
               $alias = $line;       #i.e. "info@mydomain.com: joe@mydomain.com"
               $alias =~ s/\@.*//;   #i.e. "info"
               if ($self->{email_path}{$fullalias}) {
                    # The alias is a local email address.  Skip it.
                    next;
               }
               push(@{$aliases}, $alias);
          }
     }
     return $aliases;
}

sub lookup_ssl_info {
     my $self       = shift;
     my $user       = $self->{username};
     my $archivedir = $self->{archivedir};
     my @cpanel_ssl_files = `ls -1 $archivedir/sslcerts`;
     if (($? >> 8) > 0) {
          $self->logg("**** Error ****\n", 1);
          foreach my $line (@cpanel_ssl_files) { #Something went wrong.  Print the output and exit.
               $self->logg($line, 1);
          }
          return 1;
     }
     foreach my $cert (@cpanel_ssl_files) {
          chomp($cert);
          if ($cert =~ /\.crt$/) {
               set_cert_info($self, "$archivedir/sslcerts/$cert");
          }
     }
     return 0;
}

# Input: full path filename to the certificate file.
# Output: SSL info is pushed onto the following arrays:
#         $self->{sslstart}
#         $self->{sslend}
#         $self->{sslcerts}
#         $self->{sslstatus}
#         Return: 0=OK, 1=Error
sub set_cert_info {
     my $self     = shift;
     my $certfile = $_[0];
     my @sslmembers;
     my $status;
     $certfile =~ s/\*/\\\*/;
     if (lookup_cert_info($self, $certfile, \@sslmembers) > 0) {
          return 1;
     }
     push (@{ $self->{sslcerts} }, @sslmembers[0]);
     push (@{ $self->{sslstart} }, @sslmembers[1]);
     push (@{ $self->{sslend}   }, @sslmembers[2]);
     $status = check_cert($self, $certfile);         #Check and record the status of the certificate.
     if ($status == 0) {
          push(@{ $self->{sslstatus} }, "OK");
     }elsif ($status == 1) {
          push(@{ $self->{sslstatus} }, "Not valid yet");
     }elsif ($status == 2) {
          push(@{ $self->{sslstatus} }, "Expired");
     }else {
          push(@{ $self->{sslstatus} }, "Error");
     }
     return 0;
}

#Check to see if a certificate is valid.
# Input: User object
#        Certificate file including full path.
#Output: 0 = OK - Appears to be valid.
#        1 = Not valid yet (i.e. today is before the start date)
#        2 = Expired       (i.e. today is after the end data)
#        3 = Error
sub check_cert {
     my $self  = shift;
     my $certfile = $_[0];
     my @sslmembers;
     my $start_date;
     my $start_year;
     my $start_month;
     my $start_day;
     my $end_date;
     my $end_year;
     my $end_month;
     my $end_day;
     my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
     my $now = sprintf("%04d%02d%02d", $year+1900, $mon+1, $mday);
     my %months = ("Jan", 1, "Feb", 2, "Mar", 3, "Apr", 4, "May", 5, "Jun", 6, "Jul", 7, "Aug", 8, "Sep", 9, "Oct", 10, "Nov", 11, "Dec", 12);
     if (lookup_cert_info($self, $certfile, \@sslmembers) > 0) {
          $self->logg("Error looking up certificate info.\n", 1);
          return 3;
     }
     #**test** $sslmembers[0] = "Self signed: C=US, ST=TX, L=Houston, O=HG, OU=TR, CN=mssdomain1.com/emailAddress=mstreeter\@hostgator.com";
     #**test** $sslmembers[1] = "Not Before: Sep  2 15:49:30 2011 GMT";
     #**test** $sslmembers[2] = "Not After : Sep  4 15:49:30 2011 GMT";

     #At this point, the array is populated with something like this:
     # $sslmembers[0] = Self signed: C=US, ST=TX, L=Houston, O=HG, OU=TR, CN=mssdomain1.com/emailAddress=mstreeter@hostgator.com
     # $sslmembers[1] = Not Before: Sep  2 15:49:30 2011 GMT
     # $sslmembers[2] = Not After : Sep  1 15:49:30 2012 GMT
     if ($sslmembers[0] =~ /Self signed/) {   #If it's self signed, then return a 1.
          return 1;
     }
     $start_year = $sslmembers[1];
     $start_year =~ s/ [A-Z][A-Z][A-Z]$//;
     $start_year =~ s/.* //;
     $start_month = $sslmembers[1];
     $start_month =~ s/Not Before: //;
     $start_month =~ s/ .*//;
     $start_day = $sslmembers[1];
     $start_day =~ s/Not Before: [A-Za-z][A-Za-z][A-Za-z] *//;
     $start_day =~ s/ .*//;
     $start_date = sprintf("%04d%02d%02d", $start_year, $months{$start_month}, $start_day);
     $end_year = $sslmembers[2];
     $end_year =~ s/ [A-Z][A-Z][A-Z]$//;
     $end_year =~ s/.* //;
     $end_month = $sslmembers[2];
     $end_month =~ s/Not After : //;
     $end_month =~ s/ .*//;
     $end_day = $sslmembers[2];
     $end_day =~ s/Not After : [A-Za-z][A-Za-z][A-Za-z] *//;
     $end_day =~ s/ .*//;
     $end_date = sprintf("%04d%02d%02d", $end_year, $months{$end_month}, $end_day);
     #After all of this parsing, we have 3 variables: $now, $start_date, and $end_date in yyyymmdd form that can be compared to check the date validity.
     if ($now < $start_date) {
          return 1;             #Certificate is not valid yet. Return a 1.
     }
     if ($now > $end_date) {
          return 2;
     }
     return 0;
}


# Input: full path filename to the certificate file.
#        Reference to an $array that can be populated.
# Output: SSL info is pushed onto the following arrays:
#         $array[0] = sslcerts
#         $array[1] = sslstart
#         $array[2] = sslend
#         Return: 0=OK, 1=Error
sub lookup_cert_info {
     my $self       = shift;
     my $certfile   = $_[0];
     my $sslmembers = $_[1];
     my $flag       = 0;
     my $sslissuer;
     my $sslsubject;
     my $selfsigned;      #Contains "" or "Self signed: " to indicate a self-signed certificate.
     my $sslstart;
     my $sslend;
     my $sslaltname;
     my @certinfo = `openssl x509 -in $certfile -text`;
     if (($? >> 8) > 0) {
          foreach my $line (@certinfo) {
               $self->logg($line, 1);
          }
          return 1;
     }
     foreach my $line (@certinfo) {
          chomp ($line);

          if ($line =~ /Issuer: /) {       #Look for and set the Issuer line (we compare later to the Subject to see if it's self-signed).
               $sslissuer = $line;
               $sslissuer =~ s/Issuer: //;
               $sslissuer =~ s/ *//;
          }
          if ($line =~ /Subject: /) {      #Look for and set the Subject line.
               $sslsubject = $line;
               $sslsubject =~ s/Subject: //;
               $sslsubject =~ s/ *//;
          }

          if ($line =~ /Not Before: /) {   #Look for and set the starting date.
               $sslstart = $line;
               $sslstart =~ s/ *//;
          }
          if ($line =~ /Not After : /) {   #Look for and set the ending date.
               $sslend = $line;
               $sslend =~ s/ *//;
          }
          if ($line =~ /Subject Alternative Name:/) { #Look for the "Subject Alternative Name:" line.  The line following it contains valid domain names.
               $flag = 1;
               next;
          }
          if ($flag == 1) {
               $sslaltname = $line;
               $sslaltname =~ s/ *//;
               $flag = 0;
          }
     }
     if (length($sslsubject)==0 || length($sslstart)==0 || length($sslend)==0) {
          return 1; #If the 4 varialbes aren't set, then something went wrong.
     }
     if ($sslissuer eq $sslsubject) {
          $selfsigned = "Self signed: ";
     }
     if (length($sslaltname) > 0) {
          $sslsubject = $sslaltname;
     }
     push (@{ $sslmembers }, $selfsigned . $sslsubject);
     push (@{ $sslmembers }, $sslstart);
     push (@{ $sslmembers }, $sslend);
     return 0;
}


# Input: _SSL filename in /var/cpanel/userdata/user
# Output: filename of the SSL certificate.
sub lookup_ssl_cert {
     my $self    = shift;
     my $sslfile = $_[0];
     my $user    = $self->{username};
     my $currversion = +(split /\./,`cat /usr/local/cpanel/version`)[1];
     my $crtfile;
     my @file;
     eval {
          open (my $INFILE, "/var/cpanel/userdata/$user/$sslfile");
          @file = <$INFILE>;
          close $INFILE;
     } or do {
          $self->logg("Error opening /var/cpanel/userdata/$user/$sslfile\n", 1);
          return 1;
     };
     if ($currversion >= 68){
          $sslfile =~ s/_SSL//;
          return "/var/cpanel/ssl/apache_tls/$sslfile/certificates";
     }
     else{
          foreach my $line (@file) {
               chomp($line);
               if ($line =~ /^sslcertificatefile: /) {
                   $crtfile = $line;
                   $crtfile =~ s/^sslcertificatefile: //;
                   return $crtfile;
               }
          }
     }
     return "";
}

# This method is here to keep client programs from erroring out when they try to call it, but all of the needed db info
# is looked up in the lookup_diskusage method since it already lists the databases in the tar file.
sub lookup_db_info {
     my $self = shift;
     return 0;
}

sub lookup_diskusage {
     my $self           = shift;
     my $archivefile    = $self->{archivefile};
     my $archivedir     = $self->{archivedir};
     my $databases      = 0;
     my $mysqldiskusage = 0;
     my $totaldiskusage = 0;
     my $diskusage      = 0;
     my @output = `tar -tvzf $archivefile`;
     foreach my $out (@output) {
          if ($out =~ /$archivedir\/mysql\/.*\.sql/ && $out !~ /roundcube\.sql/ && $out !~ /horde\.sql/) {#If it's a db file in the /mysql dir, then
               $databases++;                                                                              #add its size to the total $mysqldiskusage.
               my @line = split(/\s+/, $out);
               $mysqldiskusage = $mysqldiskusage + $line[2];
               my $dblist_name = $line[5];
               $dblist_name =~ s/.*\///;
               $dblist_name =~ s/\.sql//;
               push (@{$self->{dblist_name}}, $dblist_name);
               $self->{dblist_size}{$dblist_name}   = $line[2];
               $self->{dblist_tables}{$dblist_name} = "?"; #Tables is not supported because it would take too long to run  Use a "?".
          }
          if ($out !~ /$archivedir\/bandwidth/ && $out !~ /$archivedir\/mysql\//) {
               my @line = split(/\s+/, $out);
               $totaldiskusage = $totaldiskusage + $line[2];
          }
     }
     if (($? >> 8) > 0) {     #Check the return code, and exit if the external call failed.
          #logg("Extract failed.\n");
          my $ret = ($? >> 8);
          return $ret;
     }
     $diskusage = $totaldiskusage - $mysqldiskusage;
     $diskusage = $self->to_units($diskusage);
     $diskusage =~ m/([0-9.]+) ([A-Z]+).*/; # Example before the match: "123 MB"
     $self->{diskusage}      = $1;          # 123
     $self->{diskunits}      = $2;          # MB
     $mysqldiskusage = $self->to_units($mysqldiskusage);
     $mysqldiskusage =~ m/([0-9.]+) ([A-Z]+).*/;
     $self->{mysqldiskusage} = $1;
     $self->{mysqlunits}     = $2;
     $self->{databases}      = $databases;
     $self->{totaldiskusage} = $totaldiskusage;
     $self->{totalunits}     = "Bytes";
}

# Convert a number from bytes into a more readable format with units.
# Input:  bytes
# Output example: "23.45 MB"
sub to_units {
     my $self  = shift;
     my $value = shift;
     if ($value > 1073741824) {
          $value = sprintf("%.2f", $value / 1073741824);
          $value = $value . " GB";
     }elsif ($value > 1048576){
          $value = sprintf("%.2f", $value / 1048576);
          $value = $value . " MB";
     }elsif ($value > 1024) {
          $value = sprintf("%.2f", $value / 1024);
          $value = $value . " KB";
     }else {
          $value = $value . " Bytes";
     }
     return $value;
}

# Populate $self->{ns1}, $self->{ns2}, $self->{ns1ip}, $self->{ns2ip}
# Input: $self
#        Extracted archive with the primary domain's zone file extracted. 
# Output: 0=OK, 1=Error.
sub setnameservers {
     my $self       = shift;
     my $zonefile   = $self->{primarydomain} . ".db";
     my @file;
     my $archivedir = $self->{archivedir};
     $self->{ns1} = "";
     $self->{ns2} = "";
     eval { #Read the userdata/main file from the archive into @file.
          open (my $INFILE, "$archivedir/dnszones/$zonefile");
          @file = <$INFILE>;
          close $INFILE;
     } or do {
          $self->logg("Error opening $archivedir/dnszones/$zonefile\n", 1);
          return 1;
     };
     foreach my $line (@file) { #Build a list of subdomains associated with the addon domains.
          if ($line =~ /IN.*NS/) {
               chomp ($line);
               $line =~ s/ *$//;          #Make sure there are no trailing spaces on the NS line.
               $line =~ s/\t$//;
               $line =~ s/.* //;     #Remove spaces and tabs before the nameserver.
               $line =~ s/.*\t//;
               $line =~ s/\.$//;     #Remove the trailing dot.
               if ($self->{ns1} eq "") {
                    $self->{ns1} = $line;
               }else {
                    $self->{ns2} = $line;
               }
          }
     }
     $self->{ns1ip} = "N/A";
     $self->{ns2ip} = "N/A";
     return 0;
}

sub setsubdomains {
     my $self = shift;
     my $archivedir = $self->{archivedir};
     my $line = "";
     my @file;
     my @addonsubs;
     my @allsubs;
     my @standalonesubs;
     my $docroot;
     my $trigger = 0;    # Trigger to start looking for subdomains *only* after we see "sub_domains" in the file.  Otherwise, we might mistakenly list parked domains as if they were subdomains.
     eval { #Read the userdata/main file from the archive into @file.
          open (INFILE, "$archivedir/userdata/main");
          @file = <INFILE>;
          close INFILE;
     } or do {
          push (@addonsubs, "Error");
          return @addonsubs;
     };
     foreach $line (@file) { #Build a list of subdomains associated with the addon domains.
          if ($line =~ /^  .*:/) {
               $line =~ s/.*: //;
               chomp ($line);
               push (@addonsubs, $line);
          }
     }
     $trigger = 0;
     foreach $line (@file) { #Build a list of all subdomains.
          if ($line =~ /^sub_domains/) {
               $trigger = 1;
          }
          if ($line =~ /^  - / && $trigger == 1) {
               $line =~ s/^  - //;
               chomp ($line);
               if ($line =~ /\*/) {
                    #logg("Ignoring wildcard subdomain $line.  It may be necessary to manually add a wildcard domain.\n");
               }else {
                    push (@allsubs, $line);
               }
          }
     }
     # Each line that is in @allsubs but missing from @addonsubs will be added to @standalonesubs.
     my $found = 0; #Initialize found flag to false.
     foreach my $line1 (@allsubs){
         $found = 0;
         foreach my $line2 (@addonsubs){
             if ($line1 eq $line2) {
                 $found = 1; #We've found a duplicated line between allsubs and list2.
             }
         }
         if ($found == 0) {
             push (@{ $self->{subdomains} }, $line1); #add the subdomain to the subdomain array.
             $docroot = lookup_domfile_docroot($archivedir, $line1);
             push (@{ $self->{subdomaindirs} }, $docroot);
             $self->{subdomain_subdomaindir}{$line1} = $docroot;
             $self->{subdomaindir_subdomain}{$docroot} = $line1;
         }
     }
     return 0;
}

# Find out if our subdomain array already has a given subdomain.
# Input:  $self
#         Subdomain
# Output: 0 = no
#         1 = yes
sub havesubdomain {
     my $self      = shift;
     my $subdomain = $_[0];
     my $ret       = 0;
     foreach my $line (@{ $self->{addonsubdomains} }) {
          if ($line eq $subdomain) {
               $ret = 1;
               last;
          }
     }
     return $ret;
}

# List the parked domains in the archive.
# Input:  The following members must be populated (i.e. call setprimaryinfo first):
#           $self->{archivedir}
#           $self->{partition}
#           $self->{username} 
# Output: Array of parked domains
#         or empty array if no subdomains
#         or $array[0] = "Error" if there was an error.
sub setparkeddomains {
     my $self       = shift;
     my $archivedir = $self->{archivedir};
     my $parked     = "";
     my @file;
     my @parkeddomains;
     my $parkeddir  = "/$self->{partition}/$self->{username}/public_html";
     my $trigger    = 0;    # Trigger to stop looking for parked domains after we see "sub_domains" in the file.
                            #  Otherwise, we might mistakenly list subdomains as if they were parked domains.
     eval { #Read the userdata/main file from the archive into @file.
          open (INFILE, "$archivedir/userdata/main");
          @file = <INFILE>;
          close INFILE;
     } or do {
          return 1;
     };
     $trigger = 0;
     foreach $parked (@file) { #Build a list of parked domains.
          if ($parked =~ /^sub_domains/) {
               $trigger = 1;
          }
          if ($parked =~ /^  - / && $trigger == 0) {
               $parked =~ s/^  - //;
               chomp($parked);
               $self->{parked_parkeddir}{$parked}    = $parkeddir;
               $self->{parkeddir_parked}{$parkeddir} = $parked;
          }
     }
     return 0;
}


# Call the cPanel API to list the addon domains, then add them to our addon list.
# Input:  $self
# Output: Addons added to $self->{addons}
#         Subdomains that are associated with the addons are also added to addonsubdomains.
#         Addon directories that are associated with the addons are also added to addondirs.
#         Domain keys that are associated with the addons are also added to domainkeys.
#         Returns 0 if ok, 1 if error.
sub setaddons {
     my $self = shift;
     my $archivedir = $self->{archivedir};
     my $line = "";
     my $addon;
     my $addonsubdomain;
     my $domainkey;
     my $domfile;
     my $docroot;
     my @lines;
     eval {
          open (my $INFILE, "$archivedir/userdata/main"); #Slurp the primary domain file so we can set multiple class members at the same time.
          @lines = <$INFILE>;
          close $INFILE;
     } or do {
          return 1;
     };
     foreach my $line (@lines) {
          chomp ($line);
          if ($line =~ /^  .*:/) {
               $addon = $line;                   
               $addon =~ s/^  //;
               $addon =~ s/: /:/;
               push (@{ $self->{addons} }, $addon);
               $addonsubdomain = $line;
               $addonsubdomain =~ s/^  //;
               $addonsubdomain =~ s/.*: //; #i.e. mssdom2.mssdom21.com
               push (@{ $self->{addonsubdomains} }, $addonsubdomain);
               $addon =~ s/:.*//; #i.e. Change mssdom2.com:mssdom2.mssdom21.com to mssdom2.com
               $self->{addon_addonsubdomain}{$addon} = $addonsubdomain;
               $domainkey =  $line;
               $domainkey =~ s/.*: //;
               $domainkey =~ s/\./_/;
               push (@{ $self->{domainkeys} }, $domainkey);
               $domfile = $line;
               $domfile =~ s/.*: //;
               $docroot = lookup_domfile_docroot($archivedir, $domfile);
               push (@{ $self->{addondirs} }, $docroot);
          }
     }
     return 0;
}

sub lookup_domfile_docroot {
     my $archivedir = $_[0];
     my $domfile    = $_[1];
     my $docroot    = "";
     eval {
          open (my $INFILE, "$archivedir/userdata/$domfile");
          while (my $line = <$INFILE>) {
               chomp($line);
               if ($line =~ /^documentroot: /) {
                    $line =~ s/^documentroot: //;
                    $docroot = $line;
               }
          }
          close $INFILE;
     } or do {
          return "Error";
     };
     return $docroot;
}

# $self->{primarydomain}
# $self->{username}
# $self->{ip} = $ip;
# $self->{owner} = $owner;
# $self->{partition} = $partition;
# $self->{plan} = $plan;
sub setprimaryinfo {
     my $self = shift;
     my $archivedir = $self->{archivedir};
     my $primarydomain;
     my $primarydomain = `grep 'main_domain:' $archivedir/userdata/main |sed 's/^main_domain: //'`;
     chomp($primarydomain);
     $self->{primarydomain} = $primarydomain;

     open (my $INFILE, "$archivedir/userdata/$primarydomain"); #Slurp the primary domain file so we can set multiple class members at the same time.
     my @lines = <$INFILE>;
     close $INFILE;
     
     foreach my $line (@lines) {
          chomp ($line);
          if ($line =~ /^user: /) {
               $self->{username} = $line;
               $self->{username} =~ s/^user: //;
          }
          if ($line =~ /^ip: /) {
               $self->{ip} = $line;
               $self->{ip} =~ s/^ip: //;
          }
          if ($line =~ /owner: /) {
               $self->{owner} = $line;
               $self->{owner} =~ s/^owner: //;
          }
          if ($line =~ /homedir: /) {
               $self->{partition} = $line;
               $self->{partition} =~ s/^homedir: \///;
               $self->{partition} =~ s/\/.*//;
          }
     }
     
     open (my $CPFILE, "$archivedir/cp/$self->{username}"); #Slurp the backup equivalent of /var/cpanel/users/username file so we can set multiple class members at the same time.
     my @cplines = <$CPFILE>;
     close $CPFILE;
     foreach my $cpline (@cplines) {
          chomp ($cpline);
          if ($cpline =~ /PLAN=/) {
               $self->{plan} = $cpline;
               $self->{plan} =~ s/PLAN=//;
               chomp($self->{plan});
          }
          if ($cpline =~ /CONTACTEMAIL=/) {
               $self->{contact_email} = $cpline;
               $self->{contact_email} =~ s/CONTACTEMAIL=//;
               chomp($self->{contact_email});
          }
     }
     return 0;
}


sub DESTROY {
     my $self = shift;
     my $archivedir = $self->{archivedir};
     if (($archivedir =~ /cpmove/ || $archivedir =~ /backup/) && $self->{extractedbak} == 1) { #Since we're doing an rm -rf, let's at least do a little bit of sanity checking.
          if (-d "$archivedir") {                        #Let's also make sure the directory exists.
               my $temp = `rm -rf $archivedir`;
          }
     }else {
          #$self->logg("Not deleting the archive directory because it doesn't look like a typical archive directory.\n", 1);
     }
}


# Extract the archive into the current directory.
# Input:  0=Only extract the files that have the info. to summarize the account.
#         1=Full extraction.
# Output: return value of the tar command
#         Directory extracted from the tar archive.
#         $self->{archivedir} is populated.
sub extractbackup {
     my $self = shift;
     my $full = $_[0];   #Flag that determines whether to extract the full cPanel backup file, or only certain directories. 1=Full.
     my $archivefile = $self->{archivefile};
     my $archivedir;
     my $archivedir = `tar -tzf $archivefile |head -n 1`; #Extract the top level  directory name from the archive.
     $archivedir =~ s/\///;
     chomp($archivedir);
     $self->{archivedir} = $archivedir;

     if (-d $archivedir) {                               #If that directory exists, exit with an error.
          $self->logg("Error: $archivedir already exists.\n", 1);
          return 1;
     }
     if ($full == 0) {                                   #If we aren't doing a full extraction, then narrow it down to certain directories.
          $archivedir = "$archivedir/userdata $archivedir/cp $archivedir/dnszones $archivedir/sslcerts";
     }
     #logg("Extracting the archive $archivefile...\n");
     my @output = `/bin/tar -xzf $archivefile $archivedir`;
     #foreach my $out (@output) { #Print the output from the external call.
     #     logg($out);
     #}
     if (($? >> 8) > 0) {     #Check the return code, and exit if the external call failed.
          #logg("Extract failed.\n");
          my $ret = ($? >> 8);
          return $ret;
     }
     $self->{extractedbak} = 1; #Set the flat that says to delete the directory when this object is destroyed since we extracted it.
     return 0;
}

sub dump {
     my $self = shift;
     $self->logg("User:        " . $self->{username} . "\n", 1);
     $self->logg("Primary Dom: " . $self->{primarydomain} . "\n", 1);
     $self->logg("IP:          " . $self->{ip} . "\n", 1);
     $self->logg("Owner:       " . $self->{owner} . "\n", 1);
     $self->logg("Partition:   " . $self->{partition} . "\n", 1);
     $self->logg("Plan:        " . $self->{plan} . "\n", 1);
     $self->logg("Addons:\n", 1);
     my $index = 0;
     foreach my $addon (@{ $self->{addons} }) {
          $addon =~ s/:.*//;
          $self->logg($addon . " - " . @{ $self->{addondirs}}[$index] . "\n", 1);
          $index = $index + 1;
     }
     $self->logg("Subdomains:\n", 1);
     my $index = 0;
     foreach my $subdomain (@{ $self->{subdomains} }) {
          $self->logg($subdomain . " - " . @{ $self->{subdomaindirs}}[$index] . "\n", 1);
          $index = $index + 1;
     }
}

# Input:  Domain
#         Dest Userdata object.
# Output: AWStats .txt files are copied from the backup into the new account.
#         Naming conventions for AWStats files are like these examples:
#           awstats032014.mssdom2.com.txt for a primary domain mssdom2.com.
#           awstats032014.mssdom2.mssdom21.com.txt for an addon domain mssdom2.com under a primary domain of mssdom21.com.
#         The files are renamed accordingly depending on what type of domain the source and destination are.
#         Return value: 1=OK, 0=Fail
sub copy_awstats {
     my $self        = shift;
     my $domain      = shift;
     my $dst_user    = shift;
     my $src_domaintype;
     my $dst_domaintype;
     my $archivedir  = $self->{archivedir};   #Directory name of the archive

     # If the awstats dir of the extracted backup isn't pouplated, try to extract it from homedir.tar.
     if (!-s "$archivedir/homedir/tmp/awstats") {
          if (!$self->mkdir("$archivedir/homedir/tmp/awstats")) {
               $self->{error_msg} = "Failed to create $archivedir/homedir/tmp while transferring Awstats.";
               return 0;
          }
          $self->logg("Extracting tmp directory from homedir.tar.\n", 1);
          $self->logg(YELLOW . "tar -C $archivedir/homedir/tmp --strip-components=2 -xf $archivedir/homedir.tar ./tmp/awstats\n" . RESET, 1);
          my @output = `tar -C $archivedir/homedir/tmp --strip-components=2 -xf $archivedir/homedir.tar ./tmp/awstats 2>/dev/null`;
          foreach my $out (@output) { #Print the output from the external call.
          #logg($out);   #We would normally show the output, but this will error out if there are no stats.
                         # which will be common and normal.
          }
          if (($? >> 8) > 0) {     #Check the return code, and exit if the external call failed.
               my $ret = ($? >> 8);
               $self->logg("Error: $ret\n", 1);
          }
     }

     if ($self->{primarydomain} eq $domain) {
          $src_domaintype = "primary";
     }else{
          $src_domaintype = "addon";
     }
     if ($dst_user->{primarydomain} eq $domain) {
          $dst_domaintype = "primary";
     }else{
          $dst_domaintype = "addon";
     }

     if ($src_domaintype eq "primary" && $dst_domaintype eq "primary") {
          return $self->copy_awstats_primary_primary($domain, $dst_user);
     }elsif ($src_domaintype eq "primary" && $dst_domaintype eq "addon") {
          return $self->copy_awstats_primary_addon($domain, $dst_user);
     }elsif ($src_domaintype eq "addon" && $dst_domaintype eq "primary") {
          return $self->copy_awstats_addon_primary($domain, $dst_user);
     }elsif ($src_domaintype eq "addon" && $dst_domaintype eq "addon") {
          return $self->copy_awstats_addon_addon($domain, $dst_user);
     }
}

sub copy_awstats_primary_primary {
     my $self        = shift;
     my $domain      = shift;
     my $dst_user     = shift;
     return $self->_copy_awstats($domain, $domain, $dst_user);
}

sub copy_awstats_primary_addon {
     my $self        = shift;
     my $domain      = shift;
     my $dst_user     = shift;
     my $dst_domain  = $dst_user->{addon_addonsubdomain}{$domain};
     return $self->_copy_awstats($domain, $dst_domain, $dst_user);
}

sub copy_awstats_addon_primary {
     my $self        = shift;
     my $domain      = shift;
     my $dst_user     = shift;
     my $src_domain  = $self->{addon_addonsubdomain}{$domain};
     return $self->_copy_awstats($src_domain, $domain, $dst_user);
}

sub copy_awstats_addon_addon {
     my $self        = shift;
     my $domain      = shift;
     my $dst_user     = shift;
     my $src_domain  = $self->{addon_addonsubdomain}{$domain};
     my $dst_domain  = $dst_user->{addon_addonsubdomain}{$domain};
     #$src_domain and $dst_domain will both be the subdomain since this is addon to addon (i.e. mydom.primary.com)
     return $self->_copy_awstats($src_domain, $dst_domain, $dst_user);
}

sub _copy_awstats {
     my $self        = shift;
     my $src_domain  = shift; # Will be either domain.tld or domain.primary.tld.
     my $dst_domain  = shift; # Will be either domain.tld or domain.primary.tld.
     my $dst_user     = shift;
     my $src_homedir = "$self->{archivedir}/homedir";
     my $dst_homedir = "/$dst_user->{partition}/$dst_user->{username}";  #i.e. /home/myuser      
     my $dh;
     # List the files to copy
     if (!opendir ($dh, "$src_homedir/tmp/awstats")) {
          $self->{error_msg} = "Failed to open directory $src_homedir/tmp/awstats.  $!";
          return 0;
     }
     my @src_files = grep { /awstats[0-9]{6}.$src_domain.txt/ && -f "$src_homedir/tmp/awstats/$_" } readdir($dh);
     closedir $dh;
     if (scalar(@src_files) == 0) {
          $self->{error_msg} = "No Awstats found for $src_domain";
          return 0;
     }
     my %files; #Make hash array of source -> destination filenames. (i.e. where the source filename is the key.)
     foreach my $src_file (@src_files) { #Rename the destination files.
          my $dst_file      =  $src_file;
          $dst_file         =~ s/$src_domain/$dst_domain/;
          $files{$src_file} =  $dst_file;
     }
     # Create the awstats directory if needed.
     if (not -d "$dst_homedir/tmp/awstats") {
          if (!$self->mkdir("$dst_homedir/tmp/awstats")) {
               $self->{error_msg} = "Failed to create $dst_homedir/tmp/awstats to copy Awstats data.";
               return 0;
          }
     }
     # Copy the files
     foreach my $file (keys %files) {
          if (!copy ("$src_homedir/tmp/awstats/$file", "$dst_homedir/tmp/awstats/$files{$file}")) {
               $self->{error_msg} = "File copy of $src_homedir/tmp/awstats/$file to $dst_homedir/tmp/awstats/$files{$file} failed: $!";
               return 0;
          }
     }
     return 1;
}

sub copy_mail {
     my $self         = shift;   #Userdata object for the user that we are copying from.
     my $domain       = $_[0];   #Domain whose mail we are copying.
     my $ud_user      = $_[1];
     my $archivedir   = $self->{archivedir};   #Directory name of the archive
     if (-d "$archivedir/homedir/mail") {      #If the homedir/mail dir exists, then rsync the files directly.
          $self->logg("rsyncing mail from extracted archive homedir directory.\n", 1);
          $self->rsync_copy_mail($domain, $ud_user); #Copy files from homedir directory.
     }else {
          $self->logg("Untarring mail from archive homedir.tar.\n", 1);
          $self->tar_copy_mail($domain, $ud_user); #Otherwise, copy from homedir.tar
     }
}


# Rsync the email from this user to the home directory of another user.
# Input: Domain of the email addresses                       i.e. mydomain.com
#        User object of the destination user.
# Output: 0=OK
sub rsync_copy_mail {
     my $self             = shift;
     my $domain           = $_[0];
     my $ud_user          = $_[1];
     my $user_homedir     = "/" . $ud_user->{partition} . "/" . $ud_user->{username};  #i.e. /home/myuser
     my $from_mailaccts   = $self->{archivedir} . "/homedir/etc/"  . $domain;
     my $from_mailcontent = $self->{archivedir} . "/homedir/mail/" . $domain;
     my $to_mailaccts     = $user_homedir . "/etc/";
     my $to_mailcontent   = $user_homedir . "/mail/";
     my $to_passwd        = $to_mailaccts . $domain . "/passwd";
     $self->rsync_files($from_mailaccts, $to_mailaccts, "");
     $self->rsync_files($from_mailcontent, $to_mailcontent, "");
     if (-e $to_passwd) {
          $self->replace_text("\/" . $self->{username} . "\/", "\/" . $ud_user->{username} . "\/", $to_passwd); # Update the username within the passwd file.
     }else {
          return 1; #The passwd file isn't there, so don't try to update it.
     }
     return 0;
}


# Extract email accounts and messages from the cPanel archive.
# Input: Domain of the email address                         i.e. mydomain.com
#        User object of the user we are transferring to.
# Output: 0=OK
sub tar_copy_mail {
     my $self         = shift;
     my $domain       = $_[0];
     my $ud_user      = $_[1];
     my $user_homedir = "/$ud_user->{partition}/$ud_user->{username}";
     my $archivedir   = $self->{archivedir};
     my $ret          = 0;
     my $to_passwd    = $user_homedir . "/etc/" . $domain . "/passwd";
     # Untar the home directory files in the archive.
     $self->logg("Extracting any email accounts for $domain...\n", 1);
     $self->logg(YELLOW . "tar -C $user_homedir/etc --strip-components=2 -xf $archivedir/homedir.tar ./etc/$domain\n" . RESET, 1);
     my @output = `tar -C $user_homedir/etc --strip-components=2 -xf $archivedir/homedir.tar ./etc/$domain 2>/dev/null`;
     foreach my $out (@output) { #Print the output from the external call.
     #logg($out);   #We would normally show the output, but this will error out if the domain has no email addresses.
                    # which will be common and normal.
     }
     if (($? >> 8) > 0) {     #Check the return code, and exit if the external call failed.
          $ret = ($? >> 8);
          $self->logg("Error: $ret\n", 1);
     }
     $self->logg("Extracting email messages for $domain...\n", 1);
     $self->logg(YELLOW . "tar -C $user_homedir/mail --strip-components=2 -xf $archivedir/homedir.tar ./mail/$domain\n" . RESET, 1);
     my @output = `tar -C $user_homedir/mail --strip-components=2 -xf $archivedir/homedir.tar ./mail/$domain 2>/dev/null`;
     foreach my $out (@output) { #Print the output from the external call.
     #logg($out);   #We would normally show the output, but this will error out if the domain has no email addresses.
                    # which will be common and normal.
     }
     if (($? >> 8) > 0) {     #Check the return code, and exit if the external call failed.
          $ret = ($? >> 8);
          $self->logg("Error: $ret\n", 1);
     }
     if (-e $to_passwd) {
          $self->replace_text("\/" . $self->{username} . "\/", "\/" . $ud_user->{username} . "\/", $to_passwd); # Update the username within the passwd file.
     }else {
          return 1; #The passwd file isn't there, so don't try to update it.
     }
     return 0;
}

# Clone email.  This is like copy_mail except that the mail is being copied to a new domain.
sub clone_mail {
     my $self         = shift;   #Userdata object for the user that we are copying from.
     my $domain       = shift;   #Domain whose mail we are copying.
     my $clone_domain = shift;   #Domain we are capying the mail to.
     my $ud_user      = shift;
     my $archivedir   = $self->{archivedir};   #Directory name of the archive
     if (-d "$archivedir/homedir/mail") {      #If the homedir/mail dir exists, then rsync the files directly.
          $self->logg("rsyncing mail from extracted archive homedir directory.\n", 1);
          $self->rsync_clone_mail($domain, $clone_domain, $ud_user); #Copy files from homedir directory.
     }else {
          $self->logg("Untarring mail from archive homedir.tar.\n", 1);
          $self->tar_clone_mail($domain, $clone_domain, $ud_user); #Otherwise, copy from homedir.tar
     }
}

# Rsync the email from this user to the home directory of another user.
# Input: Domain of the email addresses                       i.e. mydomain.com
#        User object of the destination user.
# Output: 0=OK
sub rsync_clone_mail {
     my $self             = shift;
     my $domain           = shift;
     my $clone_domain     = shift;
     my $ud_user          = shift;
     my $user_homedir     = "/" . $ud_user->{partition} . "/" . $ud_user->{username};  #i.e. /home/myuser
     my $from_mailaccts   = $self->{archivedir} . "/homedir/etc/"  . $domain . "/";
     my $from_mailcontent = $self->{archivedir} . "/homedir/mail/" . $domain . "/";
     my $to_mailaccts     = $user_homedir . "/etc/" . $clone_domain . "/";
     my $to_mailcontent   = $user_homedir . "/mail/". $clone_domain . "/";
     my $to_passwd        = $to_mailaccts . $clone_domain . "/passwd";
     #Make sure the destination directories exist.
     if (!-d $to_mailaccts) {
          if (!$self->mkdir($to_mailaccts)) {
               return 1;
          }
     }
     if (!-d $to_mailcontent) {
          if (!$self->mkdir($to_mailcontent)) {
                return 1;
          }
     }
     $self->rsync_files($from_mailaccts, $to_mailaccts, "");
     $self->rsync_files($from_mailcontent, $to_mailcontent, "");
     if (-e $to_passwd) {
          $self->replace_text("\/" . $self->{username} . "\/", "\/" . $ud_user->{username} . "\/", $to_passwd); # Update the username within the passwd file.
     }else {
          return 1; #The passwd file isn't there, so don't try to update it.
     }
     return 0;
}


# Extract email accounts and messages from the cPanel archive.
# Input: Domain of the email address                         i.e. mydomain.com
#        User object of the user we are transferring to.
# Output: 0=OK
sub tar_clone_mail {
     my $self         = shift;
     my $domain       = shift;
     my $clone_domain = shift;
     my $ud_user      = shift;
     my $user_homedir = "/$ud_user->{partition}/$ud_user->{username}";
     my $to_mailaccts     = $user_homedir . "/etc/" . $clone_domain . "/";
     my $to_mailcontent   = $user_homedir . "/mail/". $clone_domain . "/";
     my $archivedir   = $self->{archivedir};
     my $ret          = 0;
     my $to_passwd    = $user_homedir . "/etc/" . $domain . "/passwd";
     #Make sure the destination directories exist.
     if (!-d $to_mailaccts) {
          if (!$self->mkdir($to_mailaccts)) {
               return 1;
          }
     }
     if (!-d $to_mailcontent) {
          if (!$self->mkdir($to_mailcontent)) {
                return 1;
          }
     }
     # Untar the home directory files in the archive.
     $self->logg("Extracting any email accounts for $domain to $clone_domain...\n", 1);
     $self->logg(YELLOW . "tar -C $user_homedir/etc/$clone_domain --strip-components=3 -xf $archivedir/homedir.tar ./etc/$domain\n" . RESET, 1);
     my @output = `tar -C $user_homedir/etc/$clone_domain --strip-components=3 -xf $archivedir/homedir.tar ./etc/$domain 2>/dev/null`;
     foreach my $out (@output) { #Print the output from the external call.
     #logg($out);   #We would normally show the output, but this will error out if the domain has no email addresses.
                    # which will be common and normal.
     }
     if (($? >> 8) > 0) {     #Check the return code, and exit if the external call failed.
          $ret = ($? >> 8);
          $self->logg("Error: $ret\n", 1);
     }
     $self->logg("Extracting email messages for $domain to $clone_domain...\n", 1);
     $self->logg(YELLOW . "tar -C $user_homedir/mail/$clone_domain --strip-components=3 -xf $archivedir/homedir.tar ./mail/$domain\n" . RESET, 1);
     my @output = `tar -C $user_homedir/mail/$clone_domain --strip-components=3 -xf $archivedir/homedir.tar ./mail/$domain 2>/dev/null`;
     foreach my $out (@output) { #Print the output from the external call.
     #logg($out);   #We would normally show the output, but this will error out if the domain has no email addresses.
                    # which will be common and normal.
     }
     if (($? >> 8) > 0) {     #Check the return code, and exit if the external call failed.
          $ret = ($? >> 8);
          $self->logg("Error: $ret\n", 1);
     }
     if (-e $to_passwd) {
          $self->replace_text("\/" . $self->{username} . "\/", "\/" . $ud_user->{username} . "\/", $to_passwd); # Update the username within the passwd file.
     }else {
          return 1; #The passwd file isn't there, so don't try to update it.
     }
     return 0;
}

sub copy_document_root {
     my $self         = shift;   #Userdata object for the user that we are copying from.
     my $domain       = $_[0];   #Domain whose document root we are copying.
     my $dest_docroot = $_[1];   #Document root of the destination account.
     my $archivedir   = $self->{archivedir};   #Directory name of the archive
     if (-d "$archivedir/homedir/public_html") { #If the homedir/public_html directory exists, then homedir.tar must already be extracted.
          $self->logg("rsyncing document root from extracted archive homedir directory.\n", 1);
          $self->rsync_copy_document_root($domain, $dest_docroot); #Copy files from homedir directory.
     }else {
          $self->logg("Untarring document root from archive homedir.tar.\n", 1);
          $self->tar_copy_document_root($domain, $dest_docroot); #Otherwise, copy from homedir.tar
     }
}

#Input: Domain or subdomain
#       Destination directory
sub rsync_copy_document_root {
     my $self           = shift;
     my $domain         = $_[0];
     my $dest_docroot   = $_[1];
     my $archivedir     = $self->{archivedir};   #Directory name of the archive
     my $src_docroot    = lookup_docroot($self, $domain);
     my $archivehomedir = "/" . $self->{partition} . "/" . $self->{username};
     $src_docroot       =~ s/$archivehomedir/$archivedir\/homedir/;
     if (length($src_docroot) == 0) { #if the docroot couldn't be looked up, something went wrong.
          return;                    #Since we don't return a value, return without doing anything.
     }

     if ($src_docroot !~ /\/$/) {             #If src directory doesn't end with a "/", then add one so rsync will copy the contents of the directory.
          $src_docroot = $src_docroot . "/";
     }
     $self->rsync_files($src_docroot, $dest_docroot, find_excludes($self, $domain));    #rsync the document root.
}

#Input: Source directory
#       Dest   directory
#       Excludes (i.e. --exclude='mydir1' --exclude='mydir2')
sub rsync_files {
     my $self     = shift;
     my $src      = $_[0];
     my $dest     = $_[1];
     my $excludes = $_[2];
     my $cmdline = "rsync -av --progress $excludes $src $dest 2>&1";
     $self->logg(YELLOW . $cmdline . RESET . "\n", 1);
     my @output = `$cmdline`;
     if (($? >> 8) > 0) {     #Check the return code, and exit if the external call failed.
          return ($? >> 8);
     }
     foreach my $line (@output) { #Put the addon domains that are in @addons into the object's addon array.
          chomp ($line);
          $self->logg($line . "\n", 1);
     }
}

# Extract homedir.tar from the archive to the document root of the newly created account.
# Input:  Domain that we want to extract the document root for.
#         Directory that we want to extract to.
# Output: Return value of the tar command.
sub tar_copy_document_root {
     my $self           = shift;   #Userdata object for the user that we are copying from.
     my $domain         = $_[0];   #Domain whose document root we are copying.
     my $dest_docroot   = $_[1];   #Document root of the destination account.
     my $archivedir     = $self->{archivedir};   #Directory name of the archive
     my $archivehomedir = "/" . $self->{partition} . "/" . $self->{username};
     my $archivedocroot = lookup_docroot($self, $domain);
     my $ret           = 0;
     my $excludes;
     #Find out the document root of our newly created account.
     if (length($dest_docroot) == 0) {
          $self->logg("Error: The name of the document root is empty.\n", 1);
          return 1;
     }
     if (length($archivedocroot) == 0) {
          $self->logg("Error: The name of the archive document root is empty.\n", 1);
          return 2;
     }
     unless (-e "$archivedir/homedir.tar") {  #Check to see if homedir.tar is in the archive.
          $self->logg("$archivedir/homedir.tar does not exist.  Not extracting any files for the document root.\n", 1);
          return 0;                               # It isn't, so let's return without extracting anything.
     }
     $archivedocroot =~ s/$archivehomedir//;    #Remove the acct home directory part of the path so we only have the part that is relative to the new acct home dir.
                                                #i.e. convert /home/renew/public_html/mytestdom1.com to /public_html/mytestdom1.com
     # Example $archivedocroot        Needed $stripcomponents value
     #/public_html                              2
     #/public_html/mydom.com                    3
     #/public_html/domains/mydom.com            4
     #/mydom.com                                2
     # From the above example, we see that we can count the forward slashes and add 1 to obtain the needed --strip-components value for the tar command.
     my $stripcomponents = 0;
     my $index = 0;
     while ($index < length($archivedocroot)) {
          if (substr($archivedocroot,$index,1) eq "/") {
               $stripcomponents = $stripcomponents + 1;
          }
          $index = $index + 1;
     }
     $stripcomponents = $stripcomponents + 1;

     $excludes = find_excludes($self, $domain);

     # Untar the home directory files in the archive.
     $self->logg("Untarring the document root to $dest_docroot...\n", 1);
     $self->logg(YELLOW . "tar $excludes -C $dest_docroot --strip-components=$stripcomponents -xf $archivedir/homedir.tar .$archivedocroot\n" . RESET, 1);
     my @output = `tar $excludes -C $dest_docroot --strip-components=$stripcomponents -xf $archivedir/homedir.tar .$archivedocroot`;
     foreach my $out (@output) { #Print the output from the external call.
          $self->logg($out, 1);
     }
     if (($? >> 8) > 0) {     #Check the return code, and exit if the external call failed.
          $ret = ($? >> 8);
          $self->logg("Error: $ret\n", 1);
     }
     return $ret;
}

#Input: domain
#       Userdata (or cpbdata) object.
#Output: All of the --exclude options to be used with rsync that exclude addon document roots within the passed domains's document root.
sub find_excludes {
     my $self   = shift;
     my $domain = $_[0];
     my @dirs;
     make_exclude_list($self, \@dirs, $domain);
     my $domaindir = lookup_docroot($self, $domain) . "/";
     my $rsync = "";
     foreach my $line (@dirs) {
          $line =~ s/$domaindir//;
          $rsync = $rsync . "--exclude='" . $line . "' ";
     }
     return $rsync;
}

# Make a list of directories to exclude from an rsync.
#Input:  Userdata object
#        Reference to an array to populate with the output list.
#        Domain to transfer, excluding all other domains.
sub make_exclude_list {
     my $self    = shift;
     my $dirlist = $_[0];  #Final array of directories that we return.
     my $domain  = $_[1];
     my @dirs;             #Working array of directories.
     my $dir = lookup_docroot($self, $domain);
     lookup_docrootlist($self, \@dirs, $domain);
     lookup_subdomain_docrootlist($self, \@dirs, $domain);
     foreach my $line (@dirs) {
          if (($line =~ $dir || $dir =~ $line) && length($line) >= length($dir)) {
               push(@{$dirlist}, $line);
          }
     }
}

# Look up the document root of a domain or subdomain.
# Input: A domain name or subdomain name.
# Output: The document root in a string.
#         or "" if not found.
sub lookup_docroot {
     my $self   = shift; #UserData object
     my $domain = $_[0];
     my $docroot;
     $docroot = lookup_domain_docroot($self, $domain);
     if ($docroot eq "") {
          $docroot = lookup_subdomain_docroot($self, $domain);
     }
     return $docroot;
}

#Input:  UserData object.
#        Domain whose directory we are searching for.
#Output: Document root for that domain.
sub lookup_domain_docroot {
     my $self        = shift; #UserData object
     my $domain    = $_[0]; #Domain whose directory we are searching.
     my $domaindir = "";
     my $counter   = 0;
     if ($domain eq $self->{primarydomain}) {
          $domaindir = "/" . $self->{partition} . "/" . $self->{username} . "/public_html";
     }else {
          #Search for our domain in the addon domains.
          foreach my $line (@{$self->{addons}}) { #Search through the addon domains.
               $line =~ s/:.*//;
               if ($line eq $domain) {           #Is this the addon we're looking for?
                    $domaindir = @{$self->{addondirs}}[$counter];
                    last;
               }
               $counter++;
          }
     }
     return $domaindir;
}

# Make a list of addon domain directories for a cPanel account, excluding the domain we pass.
# Input:  cPanel Userdata object
#         Reference to an array (i.e. \@myarray)
#         Domain to exclude.
# Output: The array in the second argument is populated with the document roots of all domains in the account except the domain passed in the 3rd argument.
#         i.e. /home/user/public_html/addon1dir
#              /home/user/public_html/addon2dir
#              etc...
sub lookup_docrootlist {
     my $self            = shift; 
     my $dirlist       = $_[0];
     my $domain        = $_[1];
     my $primarydocroot = "/" . $self->{partition} . "/" . $self->{username} . "/public_html";
     my $docroot        = lookup_docroot($self, $domain);
     if ($primarydocroot ne $docroot) { #If the primary domain isn't the excluded domain, then add it to the list.
          push(@{$dirlist}, $primarydocroot);
     }
     my $index = 0;
     foreach my $addon (@{$self->{addons}}) {
          chomp ($addon);
          $addon =~ s/:.*//;
          my $addondocroot = lookup_docroot($self, $addon);
          if ($addondocroot ne $docroot) {
               my $addondir = @{$self->{addondirs}}[$index];
               push(@{$dirlist}, $addondir);
          }
          $index++;
     }
}

#Find the document roots for all subdomains in an account except for that of the domain we're transferring.
#Input:  Userdata object
#        Reference to an array to populate with the output list.
#        Domain to exclude from the list.
#Oupput: The array in the second argument is populated with the document roots of all domains in the account except the domain passed in the 3rd argument.
sub lookup_subdomain_docrootlist {
     my $self          = shift;
     my $dirlist       = $_[0];
     my $domain        = $_[1];
     my $docroot       = lookup_docroot($self, $domain);
     my $index = 0;
     foreach my $subdomain (@{$self->{subdomains}}) { #Loop through the subdomains.
          chomp ($subdomain);
          my $subdomaindocroot = lookup_docroot($self, $subdomain);
          if ($subdomaindocroot ne $docroot) {
               my $subdomaindir = @{$self->{subdomaindirs}}[$index];
               push(@{$dirlist}, $subdomaindir);
          }
          $index++;
      }
}

#Input:  UserData object.
#        Domain whose directory we are searching for.
#Output: Document root for that domain.
sub lookup_subdomain_docroot {
     my $self         = shift; #UserData object passed by reference.
     my $subdomain    = $_[0]; #Domain whose directory we are searching.
     my $subdomaindir = "";
     my $index        = 0;
     foreach my $sub (@{$self->{subdomains}}) { #Search through the addon domains.
          chomp ($sub); 
          if ($sub =~ $subdomain) {           #Is this the addon we're looking for?
               $subdomaindir = @{$self->{subdomaindirs}}[$index];
               last;
          }
          $index++;
     }
     return $subdomaindir;
}

#Replace text in a file
#Input:  Text pattern to search for
#        Text pattern to replace the first pattern with.
#        Filename to update
#Output: Updates the file.  If there's a serious error: crash and burn!
sub replace_text {
     my $self = shift;
     my $search_pattern  = $_[0];
     my $replace_pattern = $_[1];
     my $filenam         = $_[2];

     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam or die "Error updating file $filenam\n";

     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line =~ /$search_pattern/) {
              $line =~ s/$search_pattern/$replace_pattern/g;
         }
     }
     untie @lines;
}


# Make a directory including its path as needed.
# Input:  Directory to make
# Output: 1=OK, 0=Error
sub mkdir {
     my $self = shift;
     my $dir  = shift;
     my @output = `mkdir -p $dir 2>&1`;
     if (($? >> 8) > 0) {        #Check the return code, and exit if the external call failed.
          foreach my $out (@output) {
               $self->logg ($out,1);
          }
          return 0;
     }
     return 1;
}

#Print or log the passed argument.
# Input:  A text string
# Output: If $self->{loggobj} is defined then log to the logg object.  Otherwise, print the info.
sub logg {
     my $self = shift;
     my $info_to_log = $_[0];
     my $loglevel    = $_[1];
     if ($self->{loggobj}) {
          $self->{loggobj}->logg($info_to_log, $loglevel);
     }else {
          print $info_to_log;
     }
     return 0;
}

1;
###########"
# plbackup Perl module
# A module that gathers information about a Plesk backup file, with some functions to copy data out of the backup.
# Please submit all bug reports at jira.endurance.com"
# 
# Git URL for this module: NA yet.
# (C) 2011 - HostGator.com, LLC"
###########"

=pod

=head1 Example usage for plbackup.pm:

 my $ud = plbackup->new("backup_renewableideas.info_info_1111220922.xml.tar");
 print $ud->{primarydomain}; #Print the primary domain from the backup.

=head2 Example of copying a document root from the backup to a new directory:
 
 $ud->copy_document_root("renewableideas.info", "/home/newuser/public_html");

=cut

package plbackup;
use Term::ANSIColor qw(:constants);
use Tie::File;
use Data::Dumper;
use strict;

sub new {                          #Constructor
     my $class = shift;
     my $self  = {};
     $self->{class}         = $class;
     $self->{archivefile}   = $_[0];
     $self->{loggobj}       = $_[1];
     $self->{archivedir}    = undef;
     $self->{username}      = undef;
     $self->{primarydomain} = undef;
     $self->{ip}            = undef;
     $self->{owner}         = undef;
     $self->{partition}     = undef;
     $self->{plan}          = undef;
     $self->{relative_docroot} = undef;
     $self->{addons}          = [];       #Array that holds the addon domains.
     $self->{addonsubdomains} = [];       #Array that holds subdomains associated with the addon domains. i.e. mssdomain004a.info:mssdomain004a.mssdomain1.com
     $self->{addondirs}       = [];       #Array that holds addon domain directories.                     i.e. /home/mss001/public_html/mssdomain004a.info
     $self->{domainkeys}      = [];       #Array that holds the domain keys for the addon domains.        i.e. mssdomain004a_mssdomain1.com
     $self->{subdomains}      = [];       #Array that holds the subdomains not already associated with addon domains.
     $self->{subdomaindirs}   = [];       #Array that holds subdomain directories.    (currently only populated by cPanel servers)
     $self->{subdomain_subdomaindir} = {};#Hash with subdomain as the key and subdomaindir as the value
     $self->{subdomaindir_subdomain} = {};#Hash with subdomaindir as the key and subdomain as the value
     $self->{addon_addondir}  = {};#Hash with addon as the key and addondir as the value. i.e. {mssdomain10.com} = /home/mss001/public_html/mssdomain10.com
     $self->{addondir_addon}  = {};#Hash with addondir as the key and addon as the value. i.e. {/home/mss001/public_html/mssdomain10.com} = mssdomain10.com
     $self->{parked_parkeddir}= {};#Hash with parked domain as the key and its dir as the value. i.e. {mydomain.com} = /home/mss001/public_html
     $self->{parkeddir_parked}= {};#Hash with parked domain dir as the key and the domain as the value. i.e. {/home/mss001/public_html} = mydomain.com
     $self->{ns1}             = undef;
     $self->{ns2}             = undef;
     $self->{ns1ip}           = undef;
     $self->{ns2ip}           = undef;
     $self->{diskusage}       = undef;
     $self->{diskunits}       = undef;
     $self->{mysqldiskusage}  = undef;
     $self->{mysqlunits}      = undef;
     $self->{totaldiskusage}  = undef;
     $self->{totalunits}      = undef;
     $self->{databases}       = undef;
     $self->{dblist_name}     = [];       #An array of databases.
     $self->{dblist_size}     = {};       #A hash array of database sizes where an element of dblist_name is the key.
     $self->{dblist_tables}   = {};       #A hash array showing the number of tables in each database where an element of dblist_name is the key.
     $self->{db_path}         = {};       #A hash array showing the path to the database within $self->{archivedir}. (i.e. databases/renew_wp1_1 with key of renew_wp1)
     $self->{db_content}      = {};       #A hash array showing the filename of a database within the database archive (i.e. backup_renew_wp1_1_1111281009.tgz with key of renew_wp1).
     $self->{sslcerts}        = [];       #Array of strings showing SSL info.  Each element represents 1 cert, and shows the valid domains.
     $self->{sslstart}        = [];       #Array of strings showing starting date/time that the same element in sslcerts is valid.
     $self->{sslend}          = [];       #Array of strings showing ending date/time that the same element in sslcerts is valid.
     $self->{sslstatus}       = [];       #
     $self->{error}           = 0;        #Error indicator.  This will be set to 1 if there was any problem gathering the data.
     $self->{extractedbak}    = 0;        #0=We did not extract the backup dir (so don't delete it). 1=We extracted the backup, so ok to delete it.
     $self->{metadata_file}   = undef;    #Filename of the XML metadata file in the backup archive.
     $self->{docroots_file}   = undef;    #Filename of the archive file that contains the web files.
     $self->{mail_file}       = undef;    #Filename of the archive file that contains the email files.
     $self->{metadata}        = undef;    #Data structure produced by XMLin.
     $self->{mail_dir}        = {};       #Hash with email address (i.e. user1) as the keys and the dir within the archive that contains the messages (i.e. test/Maildir) is the keyed data.
     $self->{mail_pass}       = {};       #Hash with email address (i.e. user1) as the keys and the password as the keyed data.
     $self->{mail_passtype}   = {};       #Hash with email address (i.e. user1) as the keys and the password type as the keyed data.

     if (eval {require XML::Simple;}) {  # Dynamically load XML::Simple.  We have to load it like this (instead of use XML::Simple) because this
          require XML::Simple;           # module is part of the transfer modules.  Even though this module is used on cPanel, it's loaded on Plesk where
     }else {                             # XML::Simple is not available.  Loading it with use would cause an error even though it's dormant on Plesk servers.
          print "XML::Simple perl module not found.  Please install it or have a level 2 install it if this is a shared server.\n";
     }

     bless($self, $class);
     if (-d $self->{archivefile}) {       #If the archive filename we were given is a directory, then skip the extraction.
          $self->logg("$self->{archivefile} appears to be a directory.  Skipping extraction.\n", 1);
          $self->{archivedir} = $self->{archivefile};
     }else {                              #Otherwise, extract the archive.
          if (extractbackup($self, $self->{full}) > 0) {
               $self->{error} = 1;
               return $self;
          }
     }
     
     if (setprimaryinfo($self)   != 0) {$self->{error} = 1; return $self;}
     if (setaddons($self)        != 0) {$self->{error} = 1; return $self;}
     if (setmail($self)          != 0) {$self->{error} = 1; return $self;}
     if (setdbs($self)           != 0) {$self->{error} = 1; return $self;}
     if (dump_dbs($self)         != 0) {$self->{error} = 1; return $self;}
     return $self;
}

# Go through the databases in the backup and dump each one to archivedir/mysql.
sub dump_dbs {
     my $self = shift;
     mkdir "$self->{archivedir}/mysql";
     $self->logg("Extracting databases.\n", 1);
     foreach my $db (keys %{$self->{db_path}}) {
         my $dbarchive = "$self->{archivedir}/$self->{db_path}{$db}/$self->{db_content}{$db}"; #filename of the database archive file for this db.

         #Find out the name of the tar extracted file.
         $self->logg("tar -tvzf $dbarchive |head -n 1\n", 0);
         my $dbname = `tar -tvzf $dbarchive |head -n 1`;
         if (($? >> 8) > 0) {
              $self->logg("Error extracting the database filename from $dbarchive.\n", 1); #If the external call errored, then log it and move on.
              return 1;
         }
         $dbname =~ s/.* //;                                                 #Remove all but the name of the file in the archive.
         chomp($dbname);

         #Extract the file to mysql.
         $self->logg("tar -C $self->{archivedir}/mysql -xvzf $dbarchive\n", 0);
         my @ret = `tar -C $self->{archivedir}/mysql -xvzf $dbarchive`;
         if (($? >> 8) > 0) {
              $self->logg("Error extracting the database $dbarchive.\n", 1); #If the external call errored, then log it and
              foreach my $line (@ret) {                                      # print the output of the external call.
                   chomp ($line);
                   print "$line\n";
              }
              return 1;
         }

         #Rename the extracted file with a .sql extension.
         rename ("$self->{archivedir}/mysql/$dbname","$self->{archivedir}/mysql/$db.sql");
     }
}

sub setdbs {
     my $self = shift;
     my $db;
     my $dbarchive;
     my $dbdir;
     my $databases = $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{databases}->{database};
     if ($databases->{name}) {
          if ($databases->{type} eq "mysql") {
               push (@{$self->{dblist_name}}, $databases->{name});
               $self->{db_path}{$databases->{name}}    = $databases->{content}->{cid}->{path};
               $self->{db_content}{$databases->{name}} = $databases->{content}->{cid}->{"content-file"}->{content};
          }
     }else {
          foreach my $key (keys %{$databases}) {
               if ($databases->{$key}->{type} eq "mysql") {
					push (@{$self->{dblist_name}}, $key);
                    $self->{db_path}{$key}    = $databases->{$key}->{content}->{cid}->{path};
                    $self->{db_content}{$key} = $databases->{$key}->{content}->{cid}->{"content-file"}->{content};
               }
          }
     }
}

sub setmail {
     my $self = shift;
     my $mail_dir;
     my $user;
     my $pass;
     my $passtype;
     # List the email addresses in the primary domain.
     if ($self->{metadata}->{Data}->{"migration-dump"}->{domain}->{mailsystem}->{mailusers}->{mailuser}->{name}) { #If there's just one email address, then the email info has to be accessed this way:
          $mail_dir = $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{mailsystem}->{mailusers}->{mailuser}->{preferences}->{mailbox}->{content}->{cid}->{offset}; #i.e. 
          $user     = $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{mailsystem}->{mailusers}->{mailuser}->{name};                                               #i.e. "test"
          $user     = $user . "@" . $self->{primarydomain};
          $pass     = $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{mailsystem}->{mailusers}->{mailuser}->{properties}->{password}->{content};                  #i.e. "mysecret"
          $passtype = $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{mailsystem}->{mailusers}->{mailuser}->{properties}->{password}->{type};
          $self->{mail_dir}{$user}  = $mail_dir;
          $self->{mail_pass}{$user} = $pass;
          $self->{mail_passtype}{$user} = $passtype;
     }else {                                                                                                       #If > 1 email address, then the email has to be accessed like this:
          foreach my $userkey (keys %{$self->{metadata}->{Data}->{"migration-dump"}->{domain}->{mailsystem}->{mailusers}->{mailuser}}) {
               $mail_dir = $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{mailsystem}->{mailusers}->{mailuser}->{$userkey}->{preferences}->{mailbox}->{content}->{cid}->{offset};
               $user     = $userkey . "@" . $self->{primarydomain};
               $pass     = $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{mailsystem}->{mailusers}->{mailuser}->{$userkey}->{properties}->{password}->{content};
               $passtype     = $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{mailsystem}->{mailusers}->{mailuser}->{$userkey}->{properties}->{password}->{type};
               $self->{mail_dir}{$user}  = $mail_dir;
               $self->{mail_pass}{$user} = $pass;
               $self->{mail_passtype}{$user} = $passtype;
          }
     }
     # List the email addresses in the addon domains.

     my $domain = $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}->{name};
     if ($domain) {#If there's only one addon
          if (! $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}->{"parent-domain-name"}) { #Only process if it's an addon (not a subdomain).
               if ($self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}->{mailsystem}->{mailusers}->{mailuser}->{name}) { #If there's just 1 email address, then access this way:
                    $mail_dir = $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}->{mailsystem}->{mailusers}->{mailuser}->{preferences}->{mailbox}->{content}->{cid}->{offset};
                    $user     = $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}->{mailsystem}->{mailusers}->{mailuser}->{name};
                    $user     = $user . "@" . $domain;
                    $pass     = $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}->{mailsystem}->{mailusers}->{mailuser}->{properties}->{password}->{content}; #i.e. "mysecret"
                    $passtype = $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}->{mailsystem}->{mailusers}->{mailuser}->{properties}->{password}->{type};
                    $self->{mail_dir}{$user}  = $mail_dir;
                    $self->{mail_pass}{$user} = $pass; 
                    $self->{mail_passtype}{$user} = $passtype;
               }else {                                                                                                #If > 1 email address, then the email has to be accessed like this:
                    foreach my $userkey (keys %{$self->{metadata}->{Data}->{"migration-dump"}->{domain}->{mailsystem}->{mailusers}->{mailuser}}) {
                         $mail_dir = $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}->{mailsystem}->{mailusers}->{mailuser}->{$userkey}->{preferences}->{mailbox}->{content}->{cid}->{offset};
                         $user     = $userkey . "@" . $self->{primarydomain};
                         $pass     = $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}->{mailsystem}->{mailusers}->{mailuser}->{$userkey}->{properties}->{password}->{content};
                         $passtype     = $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}->{mailsystem}->{mailusers}->{mailuser}->{$userkey}->{properties}->{password}->{type};
                         $self->{mail_dir}{$user}  = $mail_dir;
                         $self->{mail_pass}{$user} = $pass;
                         $self->{mail_passtype}{$user} = $passtype;
                    }
               }
          }
     }else {                                                                                                           #If there is more than one addon:
          foreach my $domkey (keys %{$self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}}) {  #Loop through the addon domains.
               if (! $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}->{$domkey}->{"parent-domain-name"}) { #Only process if it's an addon (not a subdomain).
                    if ($self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}->{$domkey}->{mailsystem}->{mailusers}->{mailuser}->{name}) { #If there's just 1 email address, then access this way:
                         $mail_dir = $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}->{$domkey}->{mailsystem}->{mailusers}->{mailuser}->{preferences}->{mailbox}->{content}->{cid}->{offset};
                         $user     = $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}->{$domkey}->{mailsystem}->{mailusers}->{mailuser}->{name};
                         $user     = $user . "@" . $domkey;
                         $pass     = $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}->{$domkey}->{mailsystem}->{mailusers}->{mailuser}->{properties}->{password}->{content}; #i.e. "mysecret"
                         $passtype = $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}->{$domkey}->{mailsystem}->{mailusers}->{mailuser}->{properties}->{password}->{type};
                         $self->{mail_dir}{$user}  = $mail_dir;
                         $self->{mail_pass}{$user} = $pass;
                         $self->{mail_passtype}{$user} = $passtype;
                    }else {                                                                                                #If > 1 email address, then the email has to be accessed like this:
                         foreach my $userkey (keys %{$self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}->{$domkey}->{mailsystem}->{mailusers}->{mailuser}}) {
                              $mail_dir = $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}->{$domkey}->{mailsystem}->{mailusers}->{mailuser}->{$userkey}->{preferences}->{mailbox}->{content}->{cid}->{offset};
                              $user     = $userkey . "@" . $domkey;
                              $pass     = $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}->{$domkey}->{mailsystem}->{mailusers}->{mailuser}->{$userkey}->{properties}->{password}->{content};
                              $passtype     = $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}->{$domkey}->{mailsystem}->{mailusers}->{mailuser}->{$userkey}->{properties}->{password}->{type};
                              $self->{mail_dir}{$user}  = $mail_dir;
                              $self->{mail_pass}{$user} = $pass;
                              $self->{mail_passtype}{$user} = $passtype;
                         }
                    }
               }
          }
     }
     return 0;
}

# Extract email accounts and messages from the cPanel archive.
# Input: Domain of the email address                         i.e. mydomain.com
#        Archive directory.                                  i.e. /home/cpmove-myoldusr.tar.gz
#        Home directory of the user we are transferring to.  i.e. /home/myuser
# Output: 0=OK
sub copy_mail {
     my $self           = shift;
     my $domain         = $_[0];  #Domain to copy the mail for.
     my $ud_user        = $_[1];  #Userdata object of the destination account.
     my $archivedir     = $self->{archivedir};
     my $touser_homedir = "/$ud_user->{partition}/$ud_user->{username}";
     my $ret        = 0;

     $self->create_mail_accounts($domain, $ud_user);
     
     foreach my $email (keys %{$self->{mail_dir}}) {
          my $edomain =   $email;
          $edomain    =~  s/.*\@//;
          $email =~ s/\@.*//;  #We only need the username part of the email address.
          if ($edomain eq $domain) { #If the domain of the current email address is the domain we're after, then copy the messages.
               $self->logg("Extracting email messages for $email\@$domain...\n", 1);
               my @output = `tar -C $touser_homedir/mail/$domain/$email --strip-components=2 -xf $archivedir/$self->{mail_file} $email/Maildir 2>/dev/null`;
               foreach my $out (@output) { #Print the output from the external call.
               #logg($out);   #We would normally show the output, but this will error out if the domain has no email addresses.
                              # which will be common and normal.
               }
               if (($? >> 8) > 0) {     #Check the return code, and exit if the external call failed.
                    $ret = ($? >> 8);
                    $self->logg("Error: $ret\n", 1);
               }
          }
     }
     return $ret;
}

sub create_mail_accounts {
     my $self    = shift;
     my $domain  = $_[0];
     my $ud_user = $_[1];
     foreach my $emailaddr (keys %{$self->{mail_dir}}) {
          my $email   =   $emailaddr;
          $email      =~  s/\@.*//;
          my $edomain =   $emailaddr;
          $edomain    =~  s/.*\@//;
          if ($edomain eq $domain) { #If the domain of the current email address is the domain we're after, then create it.
               my @xml = $self->local_gocpanel("localhost", "xml-api/cpanel?user=$ud_user->{username}&cpanel_xmlapi_module=Email&cpanel_xmlapi_func=addpop&cpanel_xmlapi_apiversion=2&domain=$domain&email=$email&password=$self->{mail_pass}{$emailaddr}");
               #foreach my $line (@xml) {
               #     print $line . "\n";
               #}
               if ($self->{mail_passtype}{$emailaddr} ne "plain") { #If the password is not plain,
                    #Update the shadow file with the encrypted password.
                    my $to_homedir = "/$ud_user->{partition}/$ud_user->{username}";
                    my $shadowfile = $to_homedir . "/etc/$domain/shadow";
                    if (-e $shadowfile) { #Make sure the email shadow file exists before continuing.
                         $self->update_shadow_pass($shadowfile, $self->{mail_pass}{$emailaddr});
                    }else{
                         $self->logg("Cannot locate the shadow file $shadowfile in the destination account for $emailaddr", 1)
                    }
               }
          }
     }
}

# Update the email shadow file with the new encrypted password.
sub update_shadow_pass {
     my $self = shift;
     my $file = $_[0];
     my $user = $_[1];
     my $pass = $_[2];
     my $temp;
     tie my @lines, 'Tie::File', $file;
     foreach my $line (@lines) {        #Look for the shadow file entry of the $user.
          my $left  =  $line;
          my $right =  $line;
          $left     =~ s/:.*/:/;        #Turn "user:pass:1234::::::" into "user:"
          $right    =~ s/^.*?:.*?:/:/;  #Turn "user:pass:1234::::::" into ":1234::::::"
          if ($left eq "$user:") {
              $line = $left . $pass . $right; #Update the shadow file with the new password.
          }
          last;
     }
     untie @lines;
}

# Extract the archive into the current directory.
# Input:  0=Only extract the files that have the info. to summarize the account.
#         1=Full extraction.
# Output: return value of the tar command
#         Directory extracted from the tar archive.
#         $self->{archivedir} is populated.
sub extractbackup {
     my $self = shift;
     my $full = $_[0];   #Flag that determines whether to extract the full cPanel backup file, or only certain directories. 1=Full.
     my $archivefile = $self->{archivefile};
     my $archivedir  = $archivefile;
     chomp($archivedir);
     $archivedir  =~ s/\.tar$//;  #Chop off the .tar from the backup filename and use that as the archive directory.
     $archivedir  =~ s/.*\///;
     $self->{archivedir} = $archivedir;

     if (-d $archivedir) {                               #If that directory exists, exit with an error.
          $self->logg("Error: $archivedir already exists.\n", 1);
          return 1;
     }else {
          mkdir $archivedir;
     }

     # Extract the backup file.
     $self->logg("Extracting the archive $archivefile to $archivedir...\n");
     my $ret = $self->run_cmd("/bin/tar -C $archivedir -xf $archivefile");
     if ($ret > 0) {
          $self->logg("Extract failed.\n", 1);
          return $ret;
     }

     $self->{extractedbak} = 1;
     return 0;
}

# Run a command.
# Input:  A command line to run.
# Output: Output of the command is printed.
#         Return value from the command is returned.
sub run_cmd {
     my $self = shift;
     my $command = $_[0];
     my @output;
     $self->logg("$command\n", 1);
     @output = `$command`;
     foreach my $line (@output) { #Show the output from the failed command.
          $self->logg($line, 1);
     }
     return ($? >> 8);
}


sub DESTROY {
     my $self = shift;
     my $archivedir = $self->{archivedir};
     if ($archivedir =~ /backup/ && $self->{extractedbak} == 1) { #Since we're doing an rm -rf, let's at least do a little bit of sanity checking.
          if (-d "$archivedir") {                        #Let's also make sure the directory exists.
               my $temp = `rm -rf $archivedir`;
          }
     }else {
          #$self->logg("Not deleting the archive directory because it doesn't look like a typical archive directory.\n", 1);
     }
}



# ----- Some functions do nothing but are here to prevent errors from a caller that might use these functions from a different class -------

sub lookup_ssl_info {
     my $self       = shift;
}


# Input: full path filename to the certificate file.
# Output: SSL info is pushed onto the following arrays:
#         $self->{sslstart}
#         $self->{sslend}
#         $self->{sslcerts}
#         $self->{sslstatus}
#         Return: 0=OK, 1=Error
sub set_cert_info {
     my $self     = shift;
}


#Check to see if a certificate is valid.
# Input: User object
#        Certificate file including full path.
#Output: 0 = OK - Appears to be valid.
#        1 = Not valid yet (i.e. today is before the start date)
#        2 = Expired       (i.e. today is after the end data)
#        3 = Error
sub check_cert {
     my $self  = shift;
}

# Input: full path filename to the certificate file.
#        Reference to an $array that can be populated.
# Output: SSL info is pushed onto the following arrays:
#         $array[0] = sslcerts
#         $array[1] = sslstart
#         $array[2] = sslend
#         Return: 0=OK, 1=Error
sub lookup_cert_info {
     my $self       = shift;
}

# Input: _SSL filename in /var/cpanel/userdata/user
# Output: filename of the SSL certificate.
sub lookup_ssl_cert {
     my $self    = shift;
}

# This method is here to keep client programs from erroring out when they try to call it, but all of the needed db info
# is looked up in the lookup_diskusage method since it already lists the databases in the tar file.
sub lookup_db_info {
     my $self = shift;
     return 0;
}

sub lookup_diskusage {
     my $self           = shift;
}

# Populate $self->{ns1}, $self->{ns2}, $self->{ns1ip}, $self->{ns2ip}
# Input: $self
#        Extracted archive with the primary domain's zone file extracted. 
# Output: 0=OK, 1=Error.
sub setnameservers {
     my $self       = shift;
}


# Empty method because subdomain info is stored in the backup file along with addons.
#  So setaddons() takes care of subdomains too.
sub setsubdomains {
     my $self = shift;
}


# Find out if our subdomain array already has a given subdomain.
# Input:  $self
#         Subdomain
# Output: 0 = no
#         1 = yes
sub havesubdomain {
     my $self      = shift;
     my $subdomain = $_[0];
     my $ret       = 0;
     foreach my $line (@{ $self->{addonsubdomains} }) {
          if ($line eq $subdomain) {
               $ret = 1;
               last;
          }
     }
     return $ret;
}


# Call the cPanel API to list the addon domains, then add them to our addon list.
# Input:  $self
# Output: Addons added to $self->{addons}
#         Subdomains that are associated with the addons are also added to addonsubdomains.
#         Addon directories that are associated with the addons are also added to addondirs.
#         Domain keys that are associated with the addons are also added to domainkeys.
#         Returns 0 if ok, 1 if error.
sub setaddons {
     my $self = shift;

     #Set any subdomains of the primary domain.
     if ($self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{subdomains}->{subdomain}->{name}) {#If there's only one subdomain under the primary domain
          my $sub = $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{subdomains}->{subdomain}->{name};
          my $subdomain_dir = $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{subdomains}->{subdomain}->{"www-root"};
          push (@{$self->{subdomains}}, "$sub.$self->{primarydomain}");
          push (@{$self->{subdomaindirs}}, "/home/$self->{username}/$subdomain_dir");
          $self->{subdomain_subdomaindir}{"$sub.$self->{primarydomain}"} = "/home/$self->{username}/$subdomain_dir";
          $self->{subdomaindir_subdomain}{"/home/$self->{username}/$subdomain_dir"} = "$sub.$self->{primarydomain}";
     }else {                                                                                                      #If there's > 1 subdomain under the primary domain
          foreach my $sub (keys %{$self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{subdomains}->{subdomain}}) {
               my $subdomain_dir = $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{subdomains}->{subdomain}->{$sub}->{"www-root"};
               push (@{$self->{subdomains}}, "$sub.$self->{primarydomain}");
               push (@{$self->{subdomaindirs}}, "/home/$self->{username}/$subdomain_dir");
               $self->{subdomain_subdomaindir}{"$sub.$self->{primarydomain}"} = "/home/$self->{username}/$subdomain_dir";
               $self->{subdomaindir_subdomain}{"/home/$self->{username}/$subdomain_dir"} = "$sub.$self->{primarydomain}";
          }
     }


     if ($self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}->{name}) {#If there's only one addon
          my $domain    = $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}->{name};


          #New subdomain code added 12-14-2011
          my $subdomain_dir;
          if ($self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}->{$domain}->{phosting}->{subdomains}->{subdomain}->{name}) {#If there's only one subdomain
               my $sub = $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}->{$domain}->{phosting}->{subdomains}->{subdomain}->{"name"};#Add info. for the one sub.
               $subdomain_dir = $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}->{$domain}->{phosting}->{subdomains}->{subdomain}->{"www-root"};
               push (@{$self->{subdomains}}, "$sub.$domain");
               push (@{$self->{subdomaindirs}}, "/home/$self->{username}/$subdomain_dir");
               $self->{subdomain_subdomaindir}{"$sub.$domain"} = "/home/$self->{username}/$subdomain_dir";
               $self->{subdomaindir_subdomain}{"/home/$self->{username}/$subdomain_dir"} = "$sub.$domain";
          }else {                                                                                                                                           #If there's > one subdomain
               foreach my $sub (keys %{$self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}->{$domain}->{phosting}->{subdomains}->{subdomain}}) {# loop through the subs.
                    $subdomain_dir = $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}->{$domain}->{phosting}->{subdomains}->{subdomain}->{$sub}->{"www-root"};
                    push (@{$self->{subdomains}}, "$sub.$domain");
                    push (@{$self->{subdomaindirs}}, "/home/$self->{username}/$subdomain_dir");
                    $self->{subdomain_subdomaindir}{"$sub.$domain"} = "/home/$self->{username}/$subdomain_dir";
                    $self->{subdomaindir_subdomain}{"/home/$self->{username}/$subdomain_dir"} = "$sub.$domain";
               }
          }



          if ($self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}->{"parent-domain-name"}) { #If parent-domain-name key exists, then it's a subdomain.
               foreach my $cid (@{$self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}->{phosting}->{content}->{cid}}) {
                    if ($cid->{type} eq "docroot") {                      #Find the docroot info, then populate the subdomain info.
                         push (@{$self->{subdomains}}, $domain);
                         push (@{$self->{subdomaindirs}}, "/home/$self->{username}/$cid->{offset}");
                         $self->{subdomain_subdomaindir}{$domain} = "/home/$self->{username}/$cid->{offset}";
                         $self->{subdomaindir_subdomain}{"/home/$self->{username}/$cid->{offset}"} = $domain;
                         #print "Content: " . $cid->{"content-file"}->{content} . "\n";
                         #print "Dir:     " . $cid->{offset} . "\n";
                         last;
                    }
               }
          }else {                                                                                                             #If parent-domain-name doesn't exist, then it's an addon.
               foreach my $cid (@{$self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}->{phosting}->{content}->{cid}}) {
                    if ($cid->{type} eq "docroot") {                      #Find the docroot info, then populate the addon info.
                         push (@{$self->{addons}}, $domain);
                         push (@{$self->{addondirs}}, "/home/$self->{username}/$cid->{offset}");
                         $self->{addon_addondir}{$domain} = "/home/$self->{username}/$cid->{offset}";
                         $self->{addondir_addon}{"/home/$self->{username}/$cid->{offset}"} = $domain;
                         #print "Content: " . $cid->{"content-file"}->{content} . "\n";
                         #print "Dir:     " . $cid->{offset} . "\n";
                         last;
                    }
               }
          }
     }else {                                                                                            #If there is more than one addon
          foreach my $key (keys %{$self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}}) {


               #New subdomain code added 12-14-2011
               my $subdomain_dir;
               if ($self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}->{$key}->{phosting}->{subdomains}->{subdomain}->{name}) { #If there's only one subdomain
                    my $sub = $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}->{$key}->{phosting}->{subdomains}->{subdomain}->{"name"};#Add info. for the one sub.
                    $subdomain_dir = $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}->{$key}->{phosting}->{subdomains}->{subdomain}->{"www-root"};
                    push (@{$self->{subdomains}}, "$sub.$key");
                    push (@{$self->{subdomaindirs}}, "/home/$self->{username}/$subdomain_dir");
                    $self->{subdomain_subdomaindir}{"$sub.$key"} = "/home/$self->{username}/$subdomain_dir";
                    $self->{subdomaindir_subdomain}{"/home/$self->{username}/$subdomain_dir"} = "$sub.$key";
               }else {                                                                                                                                             #If there's > one subdomain
                    foreach my $sub (keys %{$self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}->{$key}->{phosting}->{subdomains}->{subdomain}}) {# loop through the subs.
                         $subdomain_dir = $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}->{$key}->{phosting}->{subdomains}->{subdomain}->{$sub}->{"www-root"};
                         push (@{$self->{subdomains}}, "$sub.$key");
                         push (@{$self->{subdomaindirs}}, "/home/$self->{username}/$subdomain_dir");
                         $self->{subdomain_subdomaindir}{"$sub.$key"} = "/home/$self->{username}/$subdomain_dir";
                         $self->{subdomaindir_subdomain}{"/home/$self->{username}/$subdomain_dir"} = "$sub.$key";
                    }
               }





               if ($self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}->{$key}->{"parent-domain-name"}) { #If parent-domain-name key exists, then it's a subdomain.
                    foreach my $cid (@{$self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}->{$key}->{phosting}->{content}->{cid}}) {
                         if ($cid->{type} eq "docroot") {                      #Find the docroot info, then populate the subdomain info.
                              push (@{$self->{subdomains}}, $key);
                              push (@{$self->{subdomaindirs}}, "/home/$self->{username}/$cid->{offset}");
                              $self->{subdomain_subdomaindir}{$key} = "/home/$self->{username}/$cid->{offset}";
                              $self->{subdomaindir_subdomain}{"/home/$self->{username}/$cid->{offset}"} = $key;
                              #print "Content: " . $cid->{"content-file"}->{content} . "\n";
                              #print "Dir:     " . $cid->{offset} . "\n";
                              last;
                         }
                    }
               }else {                                                                                                                     #If parent-domain-name doesn't exist, then it's an addon.
                    foreach my $cid (@{$self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{sites}->{site}->{$key}->{phosting}->{content}->{cid}}) {
                         if ($cid->{type} eq "docroot") {                      #Find the docroot info, then populate the addon info.
                              push (@{$self->{addons}}, $key);
                              push (@{$self->{addondirs}}, "/home/$self->{username}/$cid->{offset}");
                              $self->{addon_addondir}{$key} = "/home/$self->{username}/$cid->{offset}";
                              $self->{addondir_addon}{"/home/$self->{username}/$cid->{offset}"} = $key;
                              #print "Content: " . $cid->{"content-file"}->{content} . "\n";
                              #print "Dir:     " . $cid->{offset} . "\n";
                              last;
                         }
                    }
               }
          }
     }
}

sub lookup_domfile_docroot {
}


sub setprimaryinfo {
     my $self = shift;

     # List the files in the backup so we can look for the xml file with the metadata. 
     my @metadata_filelist = `ls -1 $self->{archivedir}`;
     if (($? >> 8) > 0) {
          $self->logg ("Could not list the files in the archive directory.\n", 1);
          return ($? >> 8);
     }
     foreach my $file (@metadata_filelist) {
          chomp ($file);
          if ($file =~ /\.xml/) {
               $self->{metadata_file} = $file;
               last;
          }
     }

     # Import the XML file.
     eval { $self->{metadata} = XML::Simple::XMLin("$self->{archivedir}/$self->{metadata_file}"); };
     if (! $self->{metadata}) {
         $self->logg ("Error reading the XML metadata file.\n", 1);
         return 1;
     }

     $self->{primarydomain}    = $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{name};
     $self->{username}         = $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{preferences}->{sysuser}->{name};
     $self->{ip}               = $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{properties}->{ip}->{"ip-address"};
     $self->{owner}            = "";     #Owner info. not available.
     $self->{partition}        = "home"; #Partition is not in the backup.  So fake it.
     $self->{plan}             = "";
     $self->{relative_docroot} = $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{"www-root"};
     foreach my $cid (@{$self->{metadata}->{Data}->{"migration-dump"}->{domain}->{phosting}->{content}->{cid}}) {
          if ($cid->{type} eq "docroot") {                      #Find the docroot info, then
               $self->{docroots_file} = $cid->{"content-file"}->{content}; # set the document roots file (the file that contains the web files).
               last;
          }
     }
     $self->{mail_file} = $self->{metadata}->{Data}->{"migration-dump"}->{domain}->{mailsystem}->{content}->{cid}->{"content-file"}->{content};
     return 0; 
}


sub dump {
     my $self = shift;
     $self->logg("User:        " . $self->{username} . "\n", 1);
     $self->logg("Primary Dom: " . $self->{primarydomain} . "\n", 1);
     $self->logg("IP:          " . $self->{ip} . "\n", 1);
     $self->logg("Owner:       " . $self->{owner} . "\n", 1);
     $self->logg("Partition:   " . $self->{partition} . "\n", 1);
     $self->logg("Plan:        " . $self->{plan} . "\n", 1);
     $self->logg("Docroot:     " . $self->{relative_docroot} . "\n", 1);
     $self->logg("Addons:", 1);
     my $index = 0;
     foreach my $addon (@{ $self->{addons} }) {
          $addon =~ s/:.*//;
          $self->logg($addon . " - " . @{ $self->{addondirs}}[$index] . "\n", 1);
          $index = $index + 1;
     }
     $self->logg("Subdomains:\n", 1);
     my $index = 0;
     foreach my $subdomain (@{ $self->{subdomains} }) {
          $self->logg($subdomain . " - " . @{ $self->{subdomaindirs}}[$index] . "\n", 1);
          $index = $index + 1;
     }
}

# Extract homedir.tar from the archive to the document root of the newly created account.
# Input:  Domain that we want to extract the document root for.
#         Directory that we want to extract to.
# Output: Return value of the tar command.
sub copy_document_root {
     my $self           = shift;   #Userdata object for the user that we are copying from.
     my $domain         = $_[0];   #Domain whose document root we are copying.
     my $dest_docroot   = $_[1];   #Document root of the destination account.
     my $archivedir     = $self->{archivedir};   #Directory name of the archive
     my $archivehomedir = "/" . $self->{partition} . "/" . $self->{username};
     my $archivedocroot = lookup_docroot($self, $domain);
     my $ret           = 0;
     my $excludes;
     #Find out the document root of our newly created account.
     if (length($dest_docroot) == 0) {
          $self->logg("Error: The name of the document root is empty.\n", 1);
          return 1;
     }
     if (length($archivedocroot) == 0) {
          $self->logg("Error: The name of the archive document root is empty.\n", 1);
          return 2;
     }
     unless (-e "$archivedir/$self->{docroots_file}") {  #Check to see if homedir.tar is in the archive.
          $self->logg("$archivedir/$self->{docroots_file} does not exist.  Not extracting any files for the document root.\n", 1);
          return 0;                               # It isn't, so let's return without extracting anything.
     }
     $archivedocroot =~ s/$archivehomedir\///;    #Remove the acct home directory part of the path so we only have the part that is relative to the new acct home dir.
                                                #i.e. convert /home/renew/public_html/mytestdom1.com to /public_html/mytestdom1.com
     # Example $archivedocroot        Needed $stripcomponents value
     # httpdocs                             1
     # httpdocs/mydom.com                   2
     # httpdocs/domains/mydom.com           3
     # mydom.com                            1
     # From the above example, we see that we can count the forward slashes and add 1 to obtain the needed --strip-components value for the tar command.
     my $stripcomponents = 0;
     my $index = 0;
     while ($index < length($archivedocroot)) {
          if (substr($archivedocroot,$index,1) eq "/") {
               $stripcomponents = $stripcomponents + 1;
          }
          $index = $index + 1;
     }
     $stripcomponents = $stripcomponents + 1;

     $excludes = find_excludes($self, $domain);

     # Untar the home directory files in the archive.
     $self->logg("Untarring the document root to $dest_docroot...\n", 1);
     $self->logg(YELLOW . "tar $excludes -C $dest_docroot --strip-components=$stripcomponents -xzf $archivedir/$self->{docroots_file} $archivedocroot\n" . RESET, 1);
     my @output = `tar $excludes -C $dest_docroot --strip-components=$stripcomponents -xzf $archivedir/$self->{docroots_file} $archivedocroot`;
     foreach my $out (@output) { #Print the output from the external call.
          $self->logg($out, 1);
     }
     if (($? >> 8) > 0) {     #Check the return code, and exit if the external call failed.
          $ret = ($? >> 8);
          $self->logg("Error: $ret\n", 1);
     }
     return $ret;
}

#Input: domain
#       Userdata (or cpbdata) object.
#Output: All of the --exclude options to be used with rsync that exclude addon document roots within the passed domains's document root.
sub find_excludes {
     my $self   = shift;
     my $domain = $_[0];
     my @dirs;
     make_exclude_list($self, \@dirs, $domain);
     my $domaindir = lookup_docroot($self, $domain) . "/";
     my $rsync = "";
     foreach my $line (@dirs) {
          $line =~ s/$domaindir//;
          $rsync = $rsync . "--exclude='" . $line . "' ";
     }
     return $rsync;
}

# Make a list of directories to exclude from an rsync.
#Input:  Userdata object
#        Reference to an array to populate with the output list.
#        Domain to transfer, excluding all other domains.
sub make_exclude_list {
     my $self    = shift;
     my $dirlist = $_[0];  #Final array of directories that we return.
     my $domain  = $_[1];
     my @dirs;             #Working array of directories.
     my $dir = lookup_docroot($self, $domain);
     lookup_docrootlist($self, \@dirs, $domain);
     lookup_subdomain_docrootlist($self, \@dirs, $domain);
     foreach my $line (@dirs) {
          if (($line =~ $dir || $dir =~ $line) && length($line) >= length($dir)) {
               push(@{$dirlist}, $line);
          }
     }
}

# Look up the document root of a domain or subdomain.
# Input: A domain name or subdomain name.
# Output: The document root in a string.
#         or "" if not found.
sub lookup_docroot {
     my $self   = shift; #UserData object
     my $domain = $_[0];
     my $docroot;
     $docroot = lookup_domain_docroot($self, $domain);
     if ($docroot eq "") {
          $docroot = lookup_subdomain_docroot($self, $domain);
     }
     return $docroot;
}

#Input:  UserData object.
#        Domain whose directory we are searching for.
#Output: Document root for that domain.
sub lookup_domain_docroot {
     my $self      = shift; #UserData object
     my $domain    = $_[0]; #Domain whose directory we are searching.
     my $domaindir = "";
     my $counter   = 0;
     if ($domain eq $self->{primarydomain}) {
          $domaindir = "/" . $self->{partition} . "/" . $self->{username} . "/" . $self->{relative_docroot};
     }else {
          #Search for our domain in the addon domains.
          foreach my $line (@{$self->{addons}}) { #Search through the addon domains.
               $line =~ s/:.*//;
               if ($line eq $domain) {           #Is this the addon we're looking for?
                    $domaindir = @{$self->{addondirs}}[$counter];
                    last;
               }
               $counter++;
          }
     }
     return $domaindir;
}

# Make a list of addon domain directories for a cPanel account, excluding the domain we pass.
# Input:  cPanel Userdata object
#         Reference to an array (i.e. \@myarray)
#         Domain to exclude.
# Output: The array in the second argument is populated with the document roots of all domains in the account except the domain passed in the 3rd argument.
#         i.e. /home/user/public_html/addon1dir
#              /home/user/public_html/addon2dir
#              etc...
sub lookup_docrootlist {
     my $self            = shift; 
     my $dirlist       = $_[0];
     my $domain        = $_[1];
     my $primarydocroot = "/" . $self->{partition} . "/" . $self->{username} . "/public_html";
     my $docroot        = lookup_docroot($self, $domain);
     if ($primarydocroot ne $docroot) { #If the primary domain isn't the excluded domain, then add it to the list.
          push(@{$dirlist}, $primarydocroot);
     }
     my $index = 0;
     foreach my $addon (@{$self->{addons}}) {
          chomp ($addon);
          $addon =~ s/:.*//;
          my $addondocroot = lookup_docroot($self, $addon);
          if ($addondocroot ne $docroot) {
               my $addondir = @{$self->{addondirs}}[$index];
               push(@{$dirlist}, $addondir);
          }
          $index++;
     }
}

#Find the document roots for all subdomains in an account except for that of the domain we're transferring.
#Input:  Userdata object
#        Reference to an array to populate with the output list.
#        Domain to exclude from the list.
#Oupput: The array in the second argument is populated with the document roots of all domains in the account except the domain passed in the 3rd argument.
sub lookup_subdomain_docrootlist {
     my $self          = shift;
     my $dirlist       = $_[0];
     my $domain        = $_[1];
     my $docroot       = lookup_docroot($self, $domain);
     my $index = 0;
     foreach my $subdomain (@{$self->{subdomains}}) { #Loop through the subdomains.
          chomp ($subdomain);
          my $subdomaindocroot = lookup_docroot($self, $subdomain);
          if ($subdomaindocroot ne $docroot) {
               my $subdomaindir = @{$self->{subdomaindirs}}[$index];
               push(@{$dirlist}, $subdomaindir);
          }
          $index++;
      }
}

#-------------------------------not done
#Input:  UserData object.
#        Domain whose directory we are searching for.
#Output: Document root for that domain.
sub lookup_subdomain_docroot {
     my $self         = shift; #UserData object passed by reference.
     my $subdomain    = $_[0]; #Domain whose directory we are searching.
     my $subdomaindir = "";
     my $index        = 0;
     foreach my $sub (@{$self->{subdomains}}) { #Search through the addon domains.
          chomp ($sub); 
          if ($sub =~ $subdomain) {           #Is this the addon we're looking for?
               $subdomaindir = @{$self->{subdomaindirs}}[$index];
               last;
          }
          $index++;
     }
     return $subdomaindir;
}

#------------------------------------------------------------------
# Make a cPanel API call locally.
# Input: cpanel API request (i.e. "accountsummary?user=$cpuser")
# Output: Array showing the XML output of the API call.
sub local_gocpanel {
     my $self           = shift;
     my ($server, $url) = @_;
     my $apistring      = $_[0];
     my @result;
     #Hashchk 
     if ( ! -s '/root/.accesshash' ) {
           system('export REMOTE_USER="root"; /usr/local/cpanel/bin/realmkaccesshash');
     }
     # Read the access hash.
     local( $/ ) ;
     open( my $fh, "/root/.accesshash" ) or die "Failed to open /root/.accesshash\n";
     my $hash = <$fh>;
     $hash =~ s/\n//g;
     my $auth = "WHM root:" . $hash;
     my $browser = LWP::UserAgent->new;
     $browser->ssl_opts( 'verify_hostname' => 0);
     $browser->ssl_opts( 'SSL_verify_mode' => '0');
     my $request = HTTP::Request->new( GET => "https://localhost:2087/xml-api/$url" );
     $request->header( Authorization => $auth );
     my $response = $browser->request( $request );
     #$self->logg($response->content . "\n", 1);
     if ($response->is_error()) {
          $self->logg(RED . "Error: " . $response->status_line() . RESET . "\n", 1);
          if ($response->status_line() =~ /403 Forbidden/) {
               $self->logg("This error is often caused by the WHM cPHulk Brute Force Protection.  Try logging into WHM to confirm this.\nIf the WHM error confirms this, find out your external IP address from a site such as whatsmyip.org, then whitelist it on the server with this script:\n/scripts/cphulkdwhitelist <IP Address>\nThen log into WHM to flush the cPHulk database or to temporarily disable cPHulk Brute Force Protection.\n", 1);
          }
          if ($response->status_line() =~ /500/) {
               $self->logg("This error is often caused by an improperly licensed cPanel installation.  Please try logging into WHM to confirm this.\n", 1);
          }
         push (@result, "Error");
         return @result;
     }
     @result = split(/\n/, $response->content);
     return @result;
}


#Print or log the passed argument.
# Input:  A text string
# Output: If $self->{loggobj} is defined then log to the logg object.  Otherwise, print the info.
sub logg {
     my $self = shift;
     my $info_to_log = $_[0];
     my $loglevel    = $_[1];
     if ($self->{loggobj}) {
          $self->{loggobj}->logg($info_to_log, $loglevel);
     }else {
          print $info_to_log;
     }
     return 0;
}

1;
###########
# dbconnect Perl module
# A module that is used to find php script config files, import databases, and update database configs in the config files.
# Please submit all bug reports at jira.endurance.com
# 
# Git URL for this module: NA yet.
# (C) 2011 - HostGator.com, LLC"
###########

=pod

=head1 Example Usage of dbconnect.pm:

 my $dbc = dbconnect->new();
 $dbc->cpanel_dbconnect("/home/myuser/mss001_wrdp410", "/home/mss001/public_html/wp-config.php", 1, "myuser");

=head2 Example of the dbclist function:

 my $dbc = dbconnect->new();
 my @dirlist = ("/home/mss001/public_html", "/home/mss001/myaddon");
 $dbc->dbclist("/home/mss001/database_dumps", \@dirlist);

=cut

package dbconnect;
use strict;
use lib "/usr/local/cpanel/";
#use Cpanel::PasswdStrength::Generate;
#use Cpanel::PasswdStrength::Check;
use Tie::File;
use Cwd 'abs_path';
use Cwd;
use LWP::UserAgent;
use URI::Escape;
use DBI;
use DBD::mysql;
use Term::ANSIColor;
use cPanel::PublicAPI;
use JSON;

if (eval {require Cpanel::PasswdStrength::Generate;}) {#Cpanel::PasswdStrength modules will only be on cPanel servers.
     require Cpanel::PasswdStrength::Generate;         # If we're on Plesk, these won't load, but they won't be needed.
}
if (eval {require Cpanel::PasswdStrength::Check;}) {
     require Cpanel::PasswdStrength::Check;
}

sub new {                          #Constructor
     my $class = shift;
     my $self  = {};
     $self->{class}         = $class;
     $self->{loggobj}       = $_[0];  #Logg object
     $self->{token}	    = $_[1];
     $self->{dbinfolist}    = [];
     $self->{configlist}    = [];
     $self->{prompt}        = 1;
     bless($self, $class);

     if (!-e "/root/bin/myimport.pm") {   #Load the myimport module.
          print "The myimport module does not appear to be on the server.  Please install it or have a level 2 admin install it if this is a shared/reseller server.\n";
          print "If this is not a shared server, please reinstall the ESO-utils RPM or contact Level 2 Support for further assistance.\n";
          return 0;
     }else {
          require "/root/bin/myimport.pm";
     }

     return $self;
}


# This is similar to prompt_cpanel_dbconnect except that it does not create a new database or database user, and it does not import the database.
#  It is used by dbclist to update a config file when the database has already been "connected" to some other config file with the same database info.
# Input: $_[0] = New database name
#        $_[1] = Config filename, including path as necessary (Can be a full path or a relative path).
#        $_[2] = Prompt flag: 0=Prompting off, 1=prompting on.
#
sub prompt_updatedb {
    my $self          = shift;
    my $newdbnam     = $_[0];
    my $dbconfigfile = $_[1];
    my $prompt       = $_[2];                             #0=Prompting off, 1=Prompting on.

    my @dbinfo = extract_db($self, $dbconfigfile);               #Show database settings from config file.
    $self->logg("Hostname:      " . $dbinfo[0] . "\n", 1);
    $self->logg("Database:      " . $dbinfo[1] . "\n", 1);
    $self->logg("Database User: " . $dbinfo[2] . "\n", 1);
    $self->logg("Password:      " . $dbinfo[3] . "\n", 1);
    if ($prompt >0) {
         $self->logg("This is the old config data.  If it is blank or looks like garbage, don't continue.\n", 1);
         $self->logg("**** A database of this name has already been created, so we will only update the config file this time.\n", 1);
         $self->logg("**** The database and database user will be updated to $newdbnam\n", 1);
         $self->logg("Continue (Enter = yes, c = Continue without prompting)?  ", 1); #Give the user a chance to see the config
         my $in = <STDIN>;                                     # settings and stop the process if something
         chomp($in);                                           # isn't right.
         my $continueflag = 0; #0=Don't continue.  1=Continue.
         if ($in eq "c" || $in eq "C") {
              if ($self->prompt_confirm() == 0) {
                   $prompt = 0;                                #Turn off prompting since the user has confirmed that this is what they want.
              }
              $continueflag = 1;
         }
         if ($continueflag == 0 && ($in ne "y" && $in ne "Y" && length($in) > 0)) {
              $continueflag = 0;
         }else {
              $continueflag = 1;
         }
         if ($continueflag == 0) {
              $self->logg("Not continuing.\n", 1);
              my @retvals;
              push (@retvals, "");
              push (@retvals, 1);
              return @retvals;
         }
    }
    if (backup_configfile($self, $dbconfigfile) != 0) {
         return "";
    }
    $self->logg("Updating configuration file.\n", 1);
    update_db ($self, $newdbnam, $newdbnam, $dbconfigfile);      #Update the configuration file w/new db details.
    my @retvals;
    push (@retvals, $newdbnam);
    push (@retvals, $prompt);
    return @retvals;
}


# "Connect" the database.  IOW, create thd db/user, import the dump and update the config file.
#  This is just like cpanel_dbconnect except that it returns an array that tells the caller whether or not to continue prompting the user.
#  If the prompting flag in element [1] of the array is 0, it means that the user chose to continue connecting databases without prompting.
# Input: $_[0] = Database dump filename.  The filename has to end with .sql, but the argument should be passed without ".sql" at the end.
#        $_[1] = Config filename, including path as necessary (Can be a full path or a relative path).
#        $_[2] = Prompt flag: 0=Prompting off, 1=prompting on.
#        $_[3] = cPanel username of the account you are importing the database for.
# Output: Array with: New database name (or empty string if not imported) in element [0]
#                     0 or 1 in element [1].  0=Don't prompt, 1=prompt
#
sub prompt_cpanel_dbconnect {
    my $self          = shift;
    my $dbdumpfile   = $_[0] . ".sql";
    my $dbconfigfile = $_[1];
    my $prompt       = $_[2];                             #0=Prompting off, 1=Prompting on.
    my $cpuser       = $_[3];

    my @dbinfo = extract_db($self, $dbconfigfile);               #Show database settings from config file.
    $self->logg("Hostname:      " . $dbinfo[0] . "\n", 1);
    $self->logg("Database:      " . $dbinfo[1] . "\n", 1);
    $self->logg("Database User: " . $dbinfo[2] . "\n", 1);
    $self->logg("Password:      " . $dbinfo[3] . "\n", 1);
    if ($prompt >0) {
         $self->logg("This is the old config data.  If it is blank or looks like garbage, don't continue.\n", 1);
         $self->logg("Continue (Enter = yes, c = Continue without prompting)?  ", 1);                    #Give the user a chance to see the config
         my $in = <STDIN>;                                     # settings and stop the process if something
         chomp($in);                                           # isn't right.
         my $continueflag = 0; #0=Don't continue.  1=Continue.
         if ($in eq "c" || $in eq "C") {
              if ($self->prompt_confirm() == 0) {
                   $prompt = 0;                                #Turn off prompting since the user has confirmed that this is what they want.
              }
              $continueflag = 1;
         }
         if ($continueflag == 0 && ($in ne "y" && $in ne "Y" && length($in) > 0)) {
              $continueflag = 0;
         }else {
              $continueflag = 1;
         }
         if ($continueflag == 0) {
              $self->logg("Not continuing.\n", 1);
              my @retvals;
              push (@retvals, "");
              push (@retvals, 1);
              return @retvals;
         }
    }
    if (backup_configfile($self, $dbconfigfile) != 0) {
         return "";
    }
    my $newdbnam = findnewdbname ($self, $dbinfo[1], $cpuser, $prompt);   #Find a suitable new database name.
    $self->logg("Adding database and database user.\n", 1);
    my $ret = adddbuser ($self, $cpuser, $newdbnam, $newdbnam, $dbinfo[3]);#Add the database and database user.
    if ($ret > 0) {
         $self->logg("Error while adding database/database user.\n", 1);
         return "";
    }
    $self->logg("Updating configuration file.\n", 1);
    update_db ($self, $newdbnam, $newdbnam, $dbconfigfile);      #Update the configuration file w/new db details.
    $self->logg("Importing database dump.\n", 1);
    my $sqlimport = myimport->new($newdbnam, $dbdumpfile);
    my $ret = $sqlimport->check_and_import();                               #Import the database dump into the new database.
    
    if ($ret != 0) {
         $self->logg("Error importing database.\n", 1);
    }else {
         $self->logg("Done!\n\n", 1);
    }
    my @retvals;
    push (@retvals, $newdbnam);
    push (@retvals, $prompt);
    return @retvals;
}

# Confirm whether or not the user wants to continue.
# Input: nothing.
# Output: 0=Don't prompt (i.e. The user said they want to continue without prompting)
#         1=Prompt.
sub prompt_confirm {
     my $self = shift;
     $self->logg("         ________________\n", 1);
     $self->logg("        /                \\\n", 1);
     $self->logg("       /      O     O     \\    ____________________\n", 1);
     $self->logg("       |                  |   /                    \\\n", 1);
     $self->logg("       |         L        |  |    Oh noooooooooo!   |\n", 1);
     $self->logg("       |                  | / \\____________________/ \n", 1);
     $self->logg("       |         __       |/\n", 1);
     $self->logg("       |        /  \\      |\n", 1);
     $self->logg("       |        \\__/      |\n", 1);
     $self->logg("        \\                /\n", 1);
     $self->logg("         \\______________/\n", 1);
     $self->logg("\n", 1);
     $self->logg("Are you sure you want to continue without prompting?\n", 1);
     $self->logg("This could make a big mess if anything goes wrong!\n", 1);
     $self->logg("If you are not 101% sure, enter 'n' now.\n", 1);
     $self->logg("Otherwise, press 'y' to continue without prompting.\n", 1);
     my $in = <STDIN>;
     $in =~ s/\n//;
     if ($in eq "y" || $in eq "Y") {
         return 0;                                         #Stop prompting.
     }
     return 1                                              #Continue prompting.
}


# "Connect" the database.  IOW, create thd db/user, import the dump and update the config file.
# Input: $_[0] = Database dump filename.  The filename has to end with .sql, but the argument should be passed without ".sql" at the end.
#        $_[1] = Config filename, including path as necessary (Can be a full path or a relative path).
#        $_[2] = Prompt flag: 0=Prompting off, 1=prompting on.
#        $_[3] = cPanel username of the account you are importing the database for.
# Output: New database name (or empty string if not imported).
#
sub cpanel_dbconnect {
    my $self         = shift;
    my $dbdumpfile   = $_[0] . ".sql";
    my $dbconfigfile = $_[1];
    my $prompt       = $_[2];                             #0=Prompting off, 1=Prompting on.
    my $cpuser       = $_[3];

    my @dbinfo = extract_db($self, $dbconfigfile);               #Show database settings from config file.
    $self->logg("Hostname:      " . $dbinfo[0] . "\n", 1);
    $self->logg("Database:      " . $dbinfo[1] . "\n", 1);
    $self->logg("Database User: " . $dbinfo[2] . "\n", 1);
    $self->logg("Password:      " . $dbinfo[3] . "\n", 1);
    if ($prompt >0) {
         $self->logg("This is the old config data.  If it is blank or looks like garbage, don't continue.\n", 1);
         $self->logg("Continue (Enter = yes)?\n", 1);                    #Give the user a chance to see the config
         my $in = <STDIN>;                                     # settings and stop the process if something
         $in =~ s/\n//;                                        # isn't right.
         if ($in ne "y" && $in ne "Y" && length($in) > 0) {
              $self->logg("Not continuing.\n", 1);
              return "";
         }
    }
    if (backup_configfile($self, $dbconfigfile) != 0) {
         return "";
    }
    my $newdbnam = findnewdbname ($self, $dbinfo[1], $cpuser, $prompt);   #Find a suitable new database name.
    $self->logg("Adding database and database user.\n", 1);
    my $ret = adddbuser ($self, $cpuser, $newdbnam, $newdbnam, $dbinfo[3]);#Add the database and database user.
    if ($ret > 0) {
         $self->logg("Error while adding database/database user.\n", 1);
         return "";
    }
    $self->logg("Updating configuration file.\n", 1);
    update_db ($self, $newdbnam, $newdbnam, $dbconfigfile);      #Update the configuration file w/new db details.
    $self->logg("Importing database dump.\n", 1);
    #my $ret = importdb ($self, $newdbnam, $dbdumpfile);                    #Import the database dump into the new database.
    my $sqlimport = myimport->new($newdbnam, $dbdumpfile);
    my $ret = $sqlimport->check_and_import();                               #Import the database dump into the new database.
    if ($ret != 0) {
         $self->logg("Error importing database.\n", 1);
    }else {
         $self->logg("Done!\n\n", 1);
    }
    return $newdbnam;
}

# "Connect" the database.  IOW, create thd db/user, import the dump and update the config file.
# Input: $_[0] = Database dump filename.  The filename has to end with .sql, but the argument should be passed without ".sql" at the end.
#        $_[1] = Config filename, including path as necessary (Can be a full path or a relative path).
#        $_[2] = Prompt flag: 0=Prompting off, 1=prompting on.
#        $_[3] = primary domain name of the account you are importing the database for.  If this database is for an addon domain,
#                the primary domain of the account is still expected here.
# Output: New database name (or empty string if not imported).
#
# Example: This example connects the database dump file renew_wdps1312.sql with wp-config, with prompting, in the account with a primary domain
#          of "myprimarydomain.info".
#my $newdbnam = dbconnect::plesk_dbconnect ("/home/renew/public_html/mytestdom1.com/renew_wdps1312", "/var/www/vhosts/renewableideas.info/httpdocs/mytestdom1.com/wp-config.php", 1, "myprimarydomain.info");
#print "New database name is: $newdbnam\n";
#
#<?php
#require_once("dbconnect.pm");
#?>
#
sub plesk_dbconnect {
     my $self         = shift;
     my $dbdumpfile   = $_[0] . ".sql";
     my $dbconfigfile = $_[1];
     my $prompt       = $_[2];                             #0=Prompting off, 1=Prompting on.
     my $domain       = $_[3];

     my @dbinfo = extract_db($self, $dbconfigfile);               #Show database settings from config file.
     $self->logg("Hostname:      " . $dbinfo[0] . "\n", 1);
     $self->logg("Database:      " . $dbinfo[1] . "\n", 1);
     $self->logg("Database User: " . $dbinfo[2] . "\n", 1);
     $self->logg("Password:      " . $dbinfo[3] . "\n", 1);

     if ($prompt >0) {
          $self->logg("This is the old config data.  If it is blank or looks like garbage, don't continue.\n", 1);
          $self->logg("Continue (Enter = yes)?\n", 1);                    #Give the user a chance to see the config
          my $in = <STDIN>;                                     # settings and stop the process if something
          $in =~ s/\n//;                                        # isn't right.
          if ($in ne "y" && $in ne "Y" && length($in) > 0) {
               $self->logg("Not continuing.\n", 1);
               return "";
          }
     }

     #Show the Plesk username for convenience in case user wants to name the db based on the username.
     my $username = `/usr/local/psa/bin/domain -i $domain |grep "Provider's contact name:"|cut -d'(' -f2|cut -d')' -f1`;
     $self->logg("Username: $username\n", 1);
     if (backup_configfile($self, $dbconfigfile) != 0) {
          return "";
     }
     my $newdbnam = plesk_findnewdbname ($self, $dbinfo[1], $prompt);   #Find a suitable new database name.
     $self->logg("Adding database and database user.\n", 1);
     my $ret = plesk_adddbuser ($self, $domain, $newdbnam, $newdbnam, $dbinfo[3]);#Add the database and database user.
     if ($ret > 0) {
          $self->logg("Error while adding database/database user.\n", 1);
          exit(1);
     }
     $self->logg("Updating configuration file.\n", 1);
     update_db ($self, $newdbnam, $newdbnam, $dbconfigfile);      #Update the configuration file w/new db details.
     
     $self->logg("Importing database dump.\n", 1);
     my $sqlimport = myimport->new($newdbnam, $dbdumpfile);
     my $ret = $sqlimport->check_and_import();                               #Import the database dump into the new database.

     if ($ret != 0) {
          $self->logg("Error importing database.\n", 1);
     }else {
          $self->logg("Done!\n\n", 1);
     }
     return $newdbnam;
}

# "Connect" the database.  IOW, create thd db/user, import the dump and update the config file.
# Input: $_[0] = Database dump filename.  The filename has to end with .sql, but the argument should be passed without ".sql" at the end.
#        $_[1] = Config filename, including path as necessary (Can be a full path or a relative path).
#        $_[2] = Prompt flag: 0=Prompting off, 1=prompting on.
#        $_[3] = primary domain name of the account you are importing the database for.  If this database is for an addon domain,
#                the primary domain of the account is still expected here.
# Output: New database name (or empty string if not imported).
#
# Example: This example connects the database dump file renew_wdps1312.sql with wp-config, with prompting, in the account with a primary domain
#          of "myprimarydomain.info".
#my @info = dbconnect::plesk_dbconnect ("/home/renew/public_html/mytestdom1.com/renew_wdps1312", "/var/www/vhosts/renewableideas.info/httpdocs/mytestdom1.com/wp-config.php", 1, "myprimarydomain.info");
#print "New database name is: " . $info[0] . "\n";
#print "Continue prompting: " . $info[1] . "\n";
#
#<?php
#require_once("dbconnect.pm");
#?>
#
sub prompt_plesk_dbconnect {
     my $self         = shift;
     my $dbdumpfile   = $_[0] . ".sql";
     my $dbconfigfile = $_[1];
     my $prompt       = $_[2];                             #0=Prompting off, 1=Prompting on.
     my $domain       = $_[3];
     my @dbinfo = extract_db($self, $dbconfigfile);               #Show database settings from config file.
     $self->logg("Hostname:      " . $dbinfo[0] . "\n", 1);
     $self->logg("Database:      " . $dbinfo[1] . "\n", 1);
     $self->logg("Database User: " . $dbinfo[2] . "\n", 1);
     $self->logg("Password:      " . $dbinfo[3] . "\n", 1);
     if ($prompt >0) {
          $self->logg("This is the old config data.  If it is blank or looks like garbage, don't continue.\n", 1);
          $self->logg("Continue (Enter = yes, c = Continue without prompting)?  ", 1);                    #Give the user a chance to see the config
          my $in = <STDIN>;                                     # settings and stop the process if something
          chomp($in);                                           # isn't right.
          my $continueflag = 0; #0=Don't continue.  1=Continue.
          if ($in eq "c" || $in eq "C") {
               if ($self->prompt_confirm() == 0) {
                    $prompt = 0;                                #Turn off prompting since the user has confirmed that this is what they want.
               }
               $continueflag = 1;
          }
          if ($continueflag == 0 && ($in ne "y" && $in ne "Y" && length($in) > 0)) {
               $continueflag = 0;
          }else {
               $continueflag = 1;
          }
          if ($continueflag == 0) {
               $self->logg("Not continuing.\n", 1);
               my @retvals;
               push (@retvals, "");
               push (@retvals, 1);
               return @retvals;
          }
     }
     #Show the Plesk username for convenience in case user wants to name the db based on the username.
     my $username = `/usr/local/psa/bin/domain -i $domain |grep "Provider's contact name:"|cut -d'(' -f2|cut -d')' -f1`;
     $self->logg("Username: $username\n", 1);
     if (backup_configfile($self, $dbconfigfile) != 0) {
          return "";
     }
     my $newdbnam = plesk_findnewdbname ($self, $dbinfo[1], $prompt);   #Find a suitable new database name.
     $self->logg("Adding database and database user.\n", 1);
     my $ret = plesk_adddbuser ($self, $domain, $newdbnam, $newdbnam, $dbinfo[3]);#Add the database and database user.
     if ($ret > 0) {
          $self->logg("Error while adding database/database user.\n", 1);
          exit(1);
     }
     $self->logg("Updating configuration file.\n", 1);
     update_db ($self, $newdbnam, $newdbnam, $dbconfigfile);      #Update the configuration file w/new db details.
     
     $self->logg("Importing database dump.\n", 1);
     my $sqlimport = myimport->new($newdbnam, $dbdumpfile);
     my $ret = $sqlimport->check_and_import();                               #Import the database dump into the new database.

     if ($ret != 0) {
          $self->logg("Error importing database.\n", 1);
     }else {
          $self->logg("Done!\n\n", 1);
     }
     my @retvals;
     push (@retvals, $newdbnam);
     push (@retvals, $prompt);
     return @retvals;
}

# Show the module version and supported configuration files.
# Input: Nothing
# Output: Version and list of supported configuration files.
# Example: show_supported_configs();
sub show_supported_configs {
     my $self = shift;
     my @configs = (
                     "bbPress", 
                     "CakePHP", 
                     "concrete5", 
                     "Coppermine", 
                     "CubeCart", 
                     "DAP", 
                     "Drupal", 
                     "E107", 
                     "Elgg", 
                     "Gallery", 
                     "HelpCenterLive", 
                     "Joomla!", 
                     "Lazarus Guestbook", 
                     "Magento", 
                     "MediaWiki", 
                     "Moodle", 
                     "MyBB", 
                     "OpenCart", 
                     "osCommerce", 
                     "phpBB", 
                     "phpList", 
                     "PHP-Nuke", 
                     "PHP Weby", 
                     "Piwik", 
                     "Prestashop", 
                     "Prosper202", 
                     "Simple Machines Forum", 
                     "SugarCRM", 
                     "TomatoCart", 
                     "TYPO3", 
                     "vBulletin", 
                     "WHMCS", 
                     "Wordpress", 
                     "X-Cart", 
                     "Zen Cart"
     );

     # Print the array in 2 column format.
     my $index = 0;
     do { 
          if ($index == 0) {
               $self->logg("Supports: ", 1);
          }else{
               $self->logg("          ", 1);
          }
          my $index2 = $index + int((scalar(@configs) / 2)+.5);
          $self->logg(sprintf("%-20s%s\n", $configs[$index], $configs[$index2]));
          $index++;
     }while ($index < int((scalar(@configs)/2)+.5));
}


#Make a backup of the config file so it can be recovered if necessary.
#Input:  Filename, including full path, to back up.
#Output: The file is added to a tar file called dbconnect-backup.tar in the current directory.
#        If dbconnect-backup.tar in the current directory doesn't exist, it is created.
#        Return value is 0 if all is OK, or nonzero if there was a problem.
#The dbconnect functions normally use this, but it can also be independently called.
sub backup_configfile {
     my $self         = shift;
     my $dbconfigfile = $_[0];
     my $currentdir   = getcwd();
     my @output;
     my $counter = 0;                                      #This block makes sure the directory isn't more than 2 deep in order to prevent
     my $matches = 0;                                      # backup files with database passwords from being created in document roots.
     my $workdir    = "";                                  #
     for (my $x=0; $x<length($currentdir) && $matches<3; $x++) {  #
          $workdir = $workdir . substr($currentdir, $x, 1);       #
          if (substr($currentdir, $x, 1) eq "\/") {               #
               $matches++;                                 #
          }                                                #
     }                                                     #
     $workdir =~ s/\/$//;                                  #
     if (-d $dbconfigfile) {
          $self->logg("The configuration file appears to be a directory.\n", 1);
          return 1;
     }
     $self->logg("Backing up the config file $dbconfigfile to $workdir/dbconnect-backup.tar\n", 1);
     $dbconfigfile =~ s/ /\\ /g;
     if (-e "$workdir/dbconnect-backup.tar") {
          @output = `tar -rvf $workdir/dbconnect-backup.tar $dbconfigfile 2>&1`;    #If the tar file already exists, add to it.
     }else {
          @output = `tar -cvf $workdir/dbconnect-backup.tar $dbconfigfile 2>&1`;    #Otherwise, create a new tar file.
     }
     foreach my $out (@output) { #Print the output from the external call.
          $self->logg($out, 1);
     }
     if (($? >> 8) > 0) {     #Check the return code, and exit if the external call failed.
          my $ret = ($? >> 8);
          $self->logg("Backup of old config file failed.\n", 1);
          return $ret;
     }
     return 0;
}

# Input: an array with 4 elements (i.e. normally database info)
# Output: 0=Not all 4 elements are populated.
#         1=All 4 elements are populated.
sub fields_populated {
     if (length($_[0]) > 0 && length($_[1]) > 0 && length($_[2]) > 0 && length($_[3]) > 0) {
          return 1;
     }
     return 0;
}

#Determine what type of configuration file it is and call the appropriate sub to extract the data.
#Input: Config filename
#Ouput: Return db configs from the file in an array.
sub extract_db {
     my $self = shift;
     my $configwithpath = $_[0];
     my $config = removedirpath($configwithpath);
     my @db;
     if ($config eq "configuration.php") {
          @db = $self->extract_db_joom15($configwithpath);
          if (fields_populated(@db)) {
               return @db;                             #Joomla! 1.5
          }
          @db = $self->extract_db_joom10($configwithpath);
          if (fields_populated(@db)) {
               return @db;                             #Joomla! 1.0
          }
          @db = $self->extract_db_joom16($configwithpath);
          if (fields_populated(@db)) {
               return @db;                             #Joomla! 1.6
          }
          @db = $self->extract_db_whmcs($configwithpath);
          if (fields_populated(@db)) {
               return @db;                             #WHMCS
          }
     }elsif ($config eq "wp-config.php") {
          @db = $self->extract_db_wp($configwithpath);
          if (fields_populated(@db)) {
               return @db;                             #Wordpress
          }
     }elsif ($config eq "bb-config.php") {
          @db = $self->extract_db_bbpress($configwithpath);
          if (fields_populated(@db)) {
               return @db;                             #bbPress
          }
     }elsif ($config eq "config.php") {
          @db = $self->extract_db_phpbb($configwithpath);
          if (fields_populated(@db)) {
               return @db;                             #phpBB
          }
          @db = $self->extract_db_vb($configwithpath);
          if (fields_populated(@db)) {
               return @db;                             #vBulletin
          }
          @db = $self->extract_db_gallery($configwithpath);
          if (fields_populated(@db)) {
               return @db;                             #Gallery
          }
          @db = $self->extract_db_phpweby($configwithpath);
          if (length($db[1]) > 0 && length($db[2]) > 0 && length($db[3]) > 0) { #Can't use fields_populated bc PHP Weby has been known to not populate host.
               return @db;                             #PHP Weby http://phpweby.com
          }
          @db = $self->extract_db_phpnuke($configwithpath);
          if (fields_populated(@db)) {
               return @db;                             #PHP-Nuke
          }
          @db = $self->extract_db_opencart($configwithpath);
          if (fields_populated(@db)) {
               return @db;                             #OpenCart
          }
          @db = $self->extract_db_moodle($configwithpath);
          if (fields_populated(@db)) {
               return @db;                             #Moodle
          }
          @db = $self->extract_db_phplist($configwithpath);
          if (fields_populated(@db)) {
               return @db;                             #phpList
          }
          @db = $self->extract_db_mybb($configwithpath);
          if (fields_populated(@db)) {
               return @db;                             #MyBB
          }
          @db = $self->extract_db_sugarcrm($configwithpath);
          if (fields_populated(@db)) {
               return @db;                             #SugarCRM
          }
          @db = $self->extract_db_hcl($configwithpath);
          if (fields_populated(@db)) {
               return @db;                             #HelpCenterLive
          }
          @db = $self->extract_db_xcart($configwithpath);
          if (fields_populated(@db)) {
               return @db;                             #X-Cart
          }
     }elsif ($config eq "local.xml") {
          @db = $self->extract_db_magento($configwithpath);
          if (fields_populated(@db)) {
               return @db;                             #Magento
          }
     }elsif ($config eq "env.php") {
          @db = $self->extract_db_magento20($configwithpath);
          if (fields_populated(@db)) {
               return @db;                             #Magento2.0
          }
     }elsif ($config eq "settings.php") {
          @db = $self->extract_db_drupal($configwithpath);
          if (fields_populated(@db)) {
               return @db;                             #Drupal
          }
          @db = $self->extract_db_drupal7($configwithpath);
          if (fields_populated(@db)) {
               return @db;                             #Drupal 7
          }
          @db = $self->extract_db_elgg($configwithpath);
          if (fields_populated(@db)) {
               return @db;                             #Elgg
          }
     }elsif ($config eq "Settings.php") {
          @db = $self->extract_db_smf($configwithpath);
          if (fields_populated(@db)) {
               return @db;                             #Simple Machines Forum
          }
     }elsif ($config eq "configure.php") {
          @db = $self->extract_db_osc($configwithpath);
          if (fields_populated(@db)) {
               return @db;                             #osCommerce/Zen Cart
          }
          @db = $self->extract_db_oscadmin($configwithpath);
          if (fields_populated(@db)) {
               return @db;                             #osCommerce/Zen Cart Admin/TomatoCart
          }
     }elsif ($config eq "site.php") {
          @db = $self->extract_db_concrete5($configwithpath);
          if (fields_populated(@db)) {
               return @db;                             #concrete5
          }
     }elsif ($config eq "settings.inc.php") {
          @db = $self->extract_db_presta($configwithpath);
          if (fields_populated(@db)) {
               return @db;                             #Prestashop
          }
     }elsif ($config eq "LocalSettings.php") {
          @db = $self->extract_db_mediawiki($configwithpath);
          if (fields_populated(@db)) {
               return @db;                             #MediaWiki
          }
     }elsif ($config eq "config.inc.php") {
          @db = $self->extract_db_coppermine($configwithpath);
          if (fields_populated(@db)) {
               return @db;                             #Coppermine
          }
          @db = $self->extract_db_lgb($configwithpath);
          if (fields_populated(@db)) {
               return @db;                             #Lazarus Guestbook
          }
     }elsif ($config eq "config.ini.php") {
          @db = $self->extract_db_piwik($configwithpath);
          if (fields_populated(@db)) {
               return @db;                             #piwik
          }
     }elsif ($config eq "dap-config.php") {
          @db = $self->extract_db_dap($configwithpath);
          if (fields_populated(@db)) {
               return @db;                             #DAP
          }
     }elsif ($config eq "global.inc.php") {
          @db = $self->extract_db_cubecart($configwithpath);
          if (fields_populated(@db)) {
               return @db;                             #CubeCart
          }
     }elsif ($config eq "202-config.php") {
          @db = $self->extract_db_prosper202($configwithpath);
          if (fields_populated(@db)) {
               return @db;                             #Prosper202
          }
     }elsif ($config eq "e107_config.php") {
          @db = $self->extract_db_e107($configwithpath);
          if (fields_populated(@db)) {
               return @db;                             #E107
          }
     }elsif ($config eq "LocalConfiguration.php") {
          @db = $self->extract_db_typo3($configwithpath);
          if (fields_populated(@db)) {
               return @db;                             #TYPO3
          }
     }elsif ($config eq "localconf.php") {
          @db = $self->extract_db_typo3l($configwithpath);
          if (fields_populated(@db)) {
               return @db;                             #TYPO3 Legacy
          }
     }elsif ($config eq "database.php") {
          @db = $self->extract_db_cakephp($configwithpath);
          if (fields_populated(@db)) {
               return @db;                             #CakePHP
          }
          @db = $self->extract_db_codeignitor($configwithpath);
          if (fields_populated(@db)) {
               return @db;                             #CodeIgnitor
          }
     }else {  
          return @db;                                  #Unrecognized config file.
     }
     return @db;
}


#Determine what type of configuration file it is and call the appropriate sub to update the config file.
# Input: dbname, dbuser, configfile
#Ouput: Updated configuration file.
sub update_db {
     my $self           = shift;
     my $configwithpath = $_[2];
     my $config = removedirpath($configwithpath);
     my @db;
     if ($config eq "configuration.php") {
          @db = $self->extract_db_joom15($configwithpath);
          if (fields_populated(@db)) {
               $self->update_db_joom15(@_);                   #Joomla! 1.5
               $self->update_path_joom15($configwithpath);
               return @db;
          }
          @db = $self->extract_db_joom10($configwithpath);
          if (fields_populated(@db)) {
               $self->update_db_joom10(@_);                   #Joomla! 1.0
               $self->update_path_joom10($configwithpath);
               return @db;
          }
          @db = $self->extract_db_joom16($configwithpath);
          if (fields_populated(@db)) {
               $self->update_db_joom16(@_);                   #Joomla! 1.6
               $self->update_path_joom16($configwithpath);
               return @db;
          }
          @db = $self->extract_db_whmcs($configwithpath);
          if (fields_populated(@db)) {
               $self->update_db_whmcs(@_);                    #WHMCS
               return @db;
          }
     }elsif ($config eq "wp-config.php") {
          @db = $self->extract_db_wp($configwithpath);
          if (fields_populated(@db)) {
               $self->update_db_wp(@_);                       #Wordpress
          }
     }elsif ($config eq "bb-config.php") {
          @db = $self->extract_db_bbpress($configwithpath);
          if (fields_populated(@db)) {
               $self->update_db_bbpress(@_);                  #bbPress
          }
     }elsif ($config eq "config.php") {
          @db = $self->extract_db_phpbb($configwithpath);
          if (fields_populated(@db)) {
               $self->update_db_phpbb(@_);                    #phpBB
               return @db;
          }
          @db = $self->extract_db_vb($configwithpath);
          if (fields_populated(@db)) {
               $self->update_db_vb(@_);                       #vBulletin
               return @db;
          }
          @db = $self->extract_db_gallery($configwithpath);
          if (fields_populated(@db)) {
               $self->update_db_gallery(@_);                  #Gallery
               return @db;
          }
          @db = $self->extract_db_phpweby($configwithpath);
          if (length($db[1]) > 0 && length($db[2]) > 0 && length($db[3]) > 0) { #Can't use fields_populated bc PHP Weby has been known to not populate host.
               $self->update_db_phpweby(@_);                  #PHP Weby http://phpweby.com
               return @db;
          }
          @db = $self->extract_db_phpnuke($configwithpath);
          if (fields_populated(@db)) {
               $self->update_db_phpnuke(@_);                  #PHP-Nuke
               return @db;
          }
          @db = $self->extract_db_opencart($configwithpath);
          if (fields_populated(@db)) {
               $self->update_db_opencart(@_);                 #OpenCart
               return @db;
          }
          @db = $self->extract_db_moodle($configwithpath);
          if (fields_populated(@db)) {
               $self->update_db_moodle(@_);                   #Moodle
               return @db;
          }
          @db = $self->extract_db_phplist($configwithpath);
          if (fields_populated(@db)) {
               $self->update_db_phplist(@_);                  #phpList
               return @db;
          }
          @db = $self->extract_db_mybb($configwithpath);
          if (fields_populated(@db)) {
               $self->update_db_mybb(@_);                     #MyBB
               return @db;
          }
          @db = $self->extract_db_sugarcrm($configwithpath);
          if (fields_populated(@db)) {
               $self->update_db_sugarcrm(@_);                 #SugarCRM
               return @db;
          }
          @db = $self->extract_db_hcl($configwithpath);
          if (fields_populated(@db)) {
               $self->update_db_hcl(@_);                      #HelpCenterLive
               return @db;
          }
          @db = $self->extract_db_xcart($configwithpath);
          if (fields_populated(@db)) {
               $self->update_db_xcart(@_);                    #X-Cart
               return @db;
          }
     }elsif ($config eq "local.xml") {
          @db = $self->extract_db_magento($configwithpath);
          if (fields_populated(@db)) {
               $self->update_db_magento(@_);                  #Magento
          }
     }elsif ($config eq "env.php") {
          @db = $self->extract_db_magento20($configwithpath);
          if (fields_populated(@db)) {
               $self->update_db_magento20(@_);                  #Magento2.0
          }
     }elsif ($config eq "settings.php") {
          @db = $self->extract_db_drupal($configwithpath);
          if (fields_populated(@db)) {
               $self->update_db_drupal(@_);                   #Drupal
          }
          @db = $self->extract_db_drupal7($configwithpath);
          if (fields_populated(@db)) {
               $self->update_db_drupal7(@_);                   #Drupal 7
          }
          @db = $self->extract_db_elgg($configwithpath);
          if (fields_populated(@db)) {
               $self->update_db_elgg(@_);                     #Elgg
          }
     }elsif ($config eq "Settings.php") {
          @db = $self->extract_db_smf($configwithpath);
          if (fields_populated(@db)) {
               $self->update_db_smf(@_);                      #Simple Machines Forum
               $self->update_path_smf(@_[2]);
          }
     }elsif ($config eq "configure.php") {
          @db = $self->extract_db_osc($configwithpath);
          if (fields_populated(@db)) {
               $self->update_db_osc(@_);                      #osCommerce/Zen Cart
               $self->update_path_osc(@_[2]);
               return @db;
          }
          @db = $self->extract_db_oscadmin($configwithpath);
          if (fields_populated(@db)) {
               $self->update_db_oscadmin(@_);                 #osCommerce/Zen Cart Admin/TomatoCart
               $self->update_path_oscadmin(@_[2]);
               return @db;
          }
     }elsif ($config eq "site.php") {
          @db = $self->extract_db_concrete5($configwithpath);
          if (fields_populated(@db)) {
               $self->update_db_concrete5(@_);                #concrete5
               return @db;
          }
     }elsif ($config eq "settings.inc.php") {
          @db = $self->extract_db_presta($configwithpath);
          if (fields_populated(@db)) {
               $self->update_db_presta(@_);                   #Prestashop
               return @db;
          }
     }elsif ($config eq "LocalSettings.php") {
          @db = $self->extract_db_mediawiki($configwithpath);
          if (fields_populated(@db)) {
               $self->update_db_mediawiki(@_);                #MediaWiki
               return @db;
          }
     }elsif ($config eq "config.inc.php") {
          @db = $self->extract_db_coppermine($configwithpath);
          if (fields_populated(@db)) {
               $self->update_db_coppermine(@_);               #Coppermine
               return @db;
          }
          @db = $self->extract_db_lgb($configwithpath);
          if (fields_populated(@db)) {
               $self->update_db_lgb(@_);                      #Lazarus Guestbook
               return @db;
          }
     }elsif ($config eq "config.ini.php") {
          @db = $self->extract_db_piwik($configwithpath);
          if (fields_populated(@db)) {
               $self->update_db_piwik(@_);                    #Piwik
               return @db;
          }
     }elsif ($config eq "dap-config.php") {
          @db = $self->extract_db_dap($configwithpath);
          if (fields_populated(@db)) {
               $self->update_db_dap(@_);                      #DAP
               return @db;
          }
     }elsif ($config eq "global.inc.php") {
          @db = $self->extract_db_cubecart($configwithpath);
          if (fields_populated(@db)) {
               $self->update_db_cubecart(@_);                 #CubeCart
               return @db;
          }
     }elsif ($config eq "202-config.php") {
          @db = $self->extract_db_prosper202($configwithpath);
          if (fields_populated(@db)) {
               $self->update_db_prosper202(@_);               #Prosper202
               return @db;
          }
     }elsif ($config eq "e107_config.php") {
          @db = $self->extract_db_e107($configwithpath);
          if (fields_populated(@db)) {
               $self->update_db_e107(@_);                     #E107
               return @db;
          }
     }elsif ($config eq "LocalConfiguration.php") {
          @db = $self->extract_db_typo3($configwithpath);
          if (fields_populated(@db)) {
               $self->update_db_typo3(@_);                    #TYPO3
               return @db;
          }
     }elsif ($config eq "localconf.php") {
          @db = $self->extract_db_typo3l($configwithpath);
          if (fields_populated(@db)) {
               $self->update_db_typo3l(@_);                   #TYPO3 Legacy
               return @db;
          }
     }elsif ($config eq "database.php") {
          @db = $self->extract_db_cakephp($configwithpath);
          if (fields_populated(@db)) {
               $self->update_db_cakephp(@_);                  #CakePHP
               return @db;
          }
     }else {  
          return @db;                                         #Unrecognized config file.
     }
     return @db;
}

sub extract_db_codeignitor {
     my $self = shift;
     my $filenam = $_[0];
     my $host = "";             #Initialize the variables.
     my $db   = "";
     my $user = "";
     my $pass = "";
     my $line = "";
     my @spconfig;
     open (INFILE, $filenam);
     while ($line = <INFILE>) {
         $db   = $1 if $line =~ m{^\$db\[\'default\'\]\[\'database\'\] \= \'(.*)\'\;};
         $user = $1 if $line =~ m{^\$db\[\'default\'\]\[\'username\'\] \= \'(.*)\'\;};
         $host = $1 if $line =~ m{^\$db\[\'default\'\]\[\'hostname\'\] \= \'(.*)\'\;};
         $pass = $1 if $line =~ m{^\$db\[\'default\'\]\[\'password\'\] \= \'(.*)\'\;};
     }
     if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
     push (my @list, $host);
     push (@list, $db);
     push (@list, $user);
     push (@list, $pass);
     push (@list, "CodeIgniter");
     return @list;
}
# ------------------------------------------------------------------------------
# ------------------------ CakePHP Subroutines  ---------------------------------
# ------------------------------------------------------------------------------
#
# Sample CakePHP app/Config/database.php:
# var $default = array('driver'      => 'mysql',
#                      'persistent'  => false,
#                      'host'        => 'localhost',
#                      'login'       => 'cakephpuser',
#                      'password'    => 'c4k3roxx!',
#                      'database'    => 'my_cakephp_project',
#                      'prefix'      => '');
#Extract information out of a CakePHP config file.
#Input: CakePHP config file path/name.
#Output: An array with the hostname, database name, db username, and password in that order.
sub extract_db_cakephp {
     my $self = shift;
     my $filenam = $_[0];
     my $host = "";             #Initialize the variables.
     my $db   = "";
     my $user = "";
     my $pass = "";
     my $line = "";
     my @spconfig;
     open (INFILE, $filenam);
     while ($line = <INFILE>) {
         if ($line !~ /\/\/.*database/ && $line !~ /#.*database/ && length($db) == 0 &&
             $line !~ /\*.*database/ && $line =~ /'\s*database\s*'\s*=>/) { #If this is db config line,
             @spconfig = splitconfigline($line);          #Extract the db name.
             $db = $spconfig[1];
         }
         if ($line !~ /\/\/.*login/ && $line !~ /#.*login/ && length($user) == 0 &&
             $line !~ /\*.*login/ && $line =~ /'\s*login\s*'\s*=>/) { #If this is db user config line,
             @spconfig = splitconfigline($line);          #Extract the db user name.
             $user = $spconfig[1];
         }
         if ($line !~ /\/\/.*host/ && $line !~ /#.*host/ && length($host) == 0 &&
             $line !~ /\*.*host/ && $line =~ /'\s*host\s*'\s*=>/) { #If this is the hostname config line,
             @spconfig = splitconfigline($line);          #Extract the host name.
             $host = $spconfig[1];
         }
         if ($line !~ /\/\/.*password/ && $line !~ /#.*password/ && length($pass) == 0 &&
             $line !~ /\*.*password/ && $line =~ /'\s*password\s*'\s*=>/) { #If this is the password config line,
             @spconfig = splitconfigline($line);          #Extract the password.
             $pass = $spconfig[1];
         }
     }
     close INFILE;
     if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
     push (my @list, $host);
     push (@list, $db);
     push (@list, $user);
     push (@list, $pass);
     push (@list, "CakePHP");
     return @list;
}

# Update a CakePHP config file.
# Input: dbname, dbuser, configfile
# Ouput: Updated CakePHP configuration file.
sub update_db_cakephp {
     my $self     = shift;
     my $dbname   = @_[0];
     my $username = @_[1];
     my $filenam  = @_[2];
     my @spconfig;
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;
     
     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\/.*database/ && $line !~ /#.*database/ &&
             $line !~ /\*.*database/ && $line =~ /database.*=>/) { #If this is db config line,
             $self->logg("Old DB: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $dbname . $spconfig[2];
             $self->logg("New DB: $line\n", 1);
         }
         if ($line !~ /\/\/.*login/ && $line !~ /#.*login/ &&
             $line !~ /\*.*login/ && $line =~ /login.*=>/) { #If this is db user config line,
             $self->logg("Old User: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $username . $spconfig[2];
             $self->logg("New User: $line\n", 1);
         }
         if ($line !~ /\/\/.*host/ && $line !~ /#.*host/ &&
             $line !~ /\*.*host/ && $line =~ /host.*=>/) { #If this is the hostname config line,
             $self->logg("Old Host: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . "localhost" . $spconfig[2];
             $self->logg("New Host: $line\n", 1);
         }
     }
     untie @lines;
}


# ------------------------------------------------------------------------------
# -------------------------------- X-Cart --------------------------------------
# ------------------------------------------------------------------------------
# Example config file: config.php in the root of an X-Cart install.
# $sql_host ='localhost';
# $sql_db ='myuser_db';
# $sql_user ='myuser_db';
# $sql_password ='mysecret';
#Extract information out of an X-Cart config file.
#Input: X-Cart config file path/name.
#Output: An array with the hostname, database name, db username, password and human readable script name in that order.
sub extract_db_xcart {
     my $self    = shift;
     my $filenam = $_[0];
     my $host = "";             #Initialize the variables.
     my $db   = "";
     my $user = "";
     my $pass = "";
     my $line = "";
     my @spconfig;
     open (INFILE, $filenam);
     while ($line = <INFILE>) {
         if ($line !~ /\/\/.*\$sql_db[^_]/ && $line !~ /#.*\$sql_db[^_]/ &&
             $line =~ /\$sql_db[^_].*=/) { #If this is db config line,
             @spconfig = splitconfigline($line);          #Extract the db name.
             $db = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$sql_user/ && $line !~ /#.*\$sql_user/ &&
             $line =~ /\$sql_user.*=/) { #If this is db user config line,
             @spconfig = splitconfigline($line);          #Extract the db user name.
             $user = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$sql_host/ && $line !~ /#.*\$sql_host/ &&
             $line =~ /\$sql_host.*=/) { #If this is hostname config line,
             @spconfig = splitconfigline($line);          #Extract the host name.
             $host = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$sql_password/ && $line !~ /#.*\$sql_password/ &&
             $line =~ /\$sql_password.*=/) { #If this is password config line,
             @spconfig = splitconfigline($line);          #Extract the password.
             $pass = $spconfig[1];
         }
     }
     close INFILE;
     if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
     push (my @list, $host);
     push (@list, $db);
     push (@list, $user);
     push (@list, $pass);
     push (@list, "X-Cart");
     return @list;
}

# Update a X-Cart config file.
# Input: dbname, dbuname, configfile
# Ouput: Updated X-Cart configuration file.
sub update_db_xcart {
     my $self     = shift;
     my $dbname   = @_[0];
     my $username = @_[1];
     my $filenam  = @_[2];
     my @spconfig; 
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;
     
     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\/.*\$sql_db[^_]/ && $line !~ /#.*\$sql_db[^_]/ &&
             $line =~ /\$sql_db[^_].*=/) { #If this is db config line,
             $self->logg("Old DB: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $dbname . $spconfig[2];
             $self->logg("New DB: $line\n", 1);
         }
         if ($line !~ /\/\/.*\$sql_user/ && $line !~ /#.*\$sql_user/ &&
             $line =~ /\$sql_user.*=/) { #If this is db user config line,
             $self->logg("Old User: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $username . $spconfig[2];
             $self->logg("New User: $line\n", 1);
         }
         if ($line !~ /\/\/.*\$sql_host/ && $line !~ /#.*\$sql_host/ &&
             $line =~ /\$sql_host.*=/) { #If this is hostname config line,
             $self->logg("Old Host: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . "localhost" . $spconfig[2];
             $self->logg("New Host: $line\n", 1);
         }
     }
     untie @lines;
}



# ------------------------------------------------------------------------------
# -------------------------------- TYPO3 Legacy ----------------------------------------
# ------------------------------------------------------------------------------
# Example TYPO3 Legacy config file: typo3conf/localconf.php
# $typo_db_username = 'user_typo3';     //  Modified or inserted by TYPO3 Install Tool.
# $typo_db_password = 'mysecret';        //  Modified or inserted by TYPO3 Install Tool.
# $typo_db_host = 'localhost';    //  Modified or inserted by TYPO3 Install Tool.
# $typo_db = 'user_typo3';      //  Modified or inserted by TYPO3 Install Tool.
#Extract information out of an TYPO3 Legacy config file.
#Input: TYPO3 Legacy config file path/name.
#Output: An array with the hostname, database name, db username, and password in that order.
sub extract_db_typo3l {
     my $self    = shift;
     my $filenam = $_[0];
     my $host = "";             #Initialize the variables.
     my $db   = "";
     my $user = "";
     my $pass = "";
     my $line = "";
     my @spconfig;
     open (INFILE, $filenam);
     while ($line = <INFILE>) {
         if ($line !~ /\/\/.*\$typo_db[^_]/ && $line !~ /#.*\$typo_db[^_]/ &&
             $line =~ /\$typo_db[^_].*=/) { #If this is db config line,
             @spconfig = splitconfigline($line);          #Extract the db name.
             $db = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$typo_db_username/ && $line !~ /#.*\$typo_db_username/ &&
             $line =~ /\$typo_db_username.*=/) { #If this is db user config line,
             @spconfig = splitconfigline($line);          #Extract the db user name.
             $user = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$typo_db_host/ && $line !~ /#.*\$typo_db_host/ &&
             $line =~ /\$typo_db_host.*=/) { #If this is hostname config line,
             @spconfig = splitconfigline($line);          #Extract the host name.
             $host = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$typo_db_password/ && $line !~ /#.*\$typo_db_password/ &&
             $line =~ /\$typo_db_password.*=/) { #If this is password config line,
             @spconfig = splitconfigline($line);          #Extract the password.
             $pass = $spconfig[1];
         }
     }
     close INFILE;
     if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
     push (my @list, $host);
     push (@list, $db);
     push (@list, $user);
     push (@list, $pass);
     push (@list, "TYPO3 Legacy");
     return @list;
}

# Update a TYPO3 Legacy config file.
# Input: dbname, dbuname, configfile
# Ouput: Updated TYPO3 Legacy configuration file.
sub update_db_typo3l {
     my $self     = shift;
     my $dbname   = @_[0];
     my $username = @_[1];
     my $filenam  = @_[2];
     my @spconfig; 
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;
     
     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\/.*\$typo_db[^_]/ && $line !~ /#.*\$typo_db[^_]/ &&
             $line =~ /\$typo_db[^_].*=/) { #If this is db config line,
             $self->logg("Old DB: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $dbname . $spconfig[2];
             $self->logg("New DB: $line\n", 1);
         }
         if ($line !~ /\/\/.*\$typo_db_username/ && $line !~ /#.*\$typo_db_username/ &&
             $line =~ /\$typo_db_username.*=/) { #If this is db user config line,
             $self->logg("Old User: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $username . $spconfig[2];
             $self->logg("New User: $line\n", 1);
         }
         if ($line !~ /\/\/.*\$typo_db_host/ && $line !~ /#.*\$typo_db_host/ &&
             $line =~ /\$typo_db_host.*=/) { #If this is hostname config line,
             $self->logg("Old Host: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . "localhost" . $spconfig[2];
             $self->logg("New Host: $line\n", 1);
         }
     }
     untie @lines;
}

# ------------------------------------------------------------------------------
# ---------------------------------- TYPO3 -------------------------------------
# ------------------------------------------------------------------------------
#
# Sample TYPO3 typo3conf/LocalConfiguration.php:
#        'DB' => array(
#                'database' => 'mss001_typo3',
#                'extTablesDefinitionScript' => 'extTables.php',
#                'host' => 'localhost',
#                'password' => 'oVlL2lVTPT5X',
#                'username' => 'mss001_typo3',
#        ),
#Extract information out of a TYPO3 config file.
#Input: TYPO3 config file path/name.
#Output: An array with the hostname, database name, db username, and password in that order.
sub extract_db_typo3 {
     my $self = shift;
     my $filenam = $_[0];
     my $host = "";             #Initialize the variables.
     my $db   = "";
     my $user = "";
     my $pass = "";
     my $line = "";
     my @spconfig;
     open (INFILE, $filenam);
     while ($line = <INFILE>) {
         if ($line !~ /\/\/.*database/ && $line !~ /#.*database/ && length($db) == 0 &&
             $line !~ /\*.*database/ && $line =~ /'\s*database\s*'\s*=>/) { #If this is db config line,
             @spconfig = splitconfigline($line);          #Extract the db name.
             $db = $spconfig[1];
         }
         if ($line !~ /\/\/.*username/ && $line !~ /#.*username/ && length($user) == 0 &&
             $line !~ /\*.*username/ && $line =~ /'\s*username\s*'\s*=>/) { #If this is db user config line,
             @spconfig = splitconfigline($line);          #Extract the db user name.
             $user = $spconfig[1];
         }
         if ($line !~ /\/\/.*host/ && $line !~ /#.*host/ && length($host) == 0 &&
             $line !~ /\*.*host/ && $line =~ /'\s*host\s*'\s*=>/) { #If this is the hostname config line,
             @spconfig = splitconfigline($line);          #Extract the host name.
             $host = $spconfig[1];
         }
         if ($line !~ /\/\/.*password/ && $line !~ /#.*password/ && length($pass) == 0 &&
             $line !~ /\*.*password/ && $line =~ /'\s*password\s*'\s*=>/) { #If this is the password config line,
             @spconfig = splitconfigline($line);          #Extract the password.
             $pass = $spconfig[1];
         }
     }
     close INFILE;
     if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
     push (my @list, $host);
     push (@list, $db);
     push (@list, $user);
     push (@list, $pass);
     push (@list, "TYPO3");
     return @list;
}

# Update a TYPO3 config file.
# Input: dbname, dbuser, configfile
# Ouput: Updated TYPO3 configuration file.
sub update_db_typo3 {
     my $self     = shift;
     my $dbname   = @_[0];
     my $username = @_[1];
     my $filenam  = @_[2];
     my @spconfig;
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;
     
     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\/.*database/ && $line !~ /#.*database/ &&
             $line !~ /\*.*database/ && $line =~ /database.*=>/) { #If this is db config line,
             $self->logg("Old DB: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $dbname . $spconfig[2];
             $self->logg("New DB: $line\n", 1);
         }
         if ($line !~ /\/\/.*username/ && $line !~ /#.*username/ &&
             $line !~ /\*.*username/ && $line =~ /username.*=>/) { #If this is db user config line,
             $self->logg("Old User: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $username . $spconfig[2];
             $self->logg("New User: $line\n", 1);
         }
         if ($line !~ /\/\/.*host/ && $line !~ /#.*host/ &&
             $line !~ /\*.*host/ && $line =~ /host.*=>/) { #If this is the hostname config line,
             $self->logg("Old Host: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . "localhost" . $spconfig[2];
             $self->logg("New Host: $line\n", 1);
         }
     }
     untie @lines;
}


# ------------------------------------------------------------------------------
# ------------------------------ LazarusGuestbook --------------------------------
# ------------------------------------------------------------------------------
# Example LazarusGuestbook admin/config.inc.php
# $GB_DB['dbName'] = 'mss001_laz'; // The name of your MySQL Database
# $GB_DB['host']   = 'localhost'; // The server your database is on. localhost is usualy correct
# $GB_DB['user']   = 'mss001_laz'; // Your MySQL username
# $GB_DB['pass']   = 'YNwc8V6UQ7eEhNM'; // Your MySQL password
#Extract information out of a LazarusGuestbook config file.
#Input: LazarusGuestbook config file path/name.
#Output: An array with the hostname, database name, db username, password, and App name in that order.
sub extract_db_lgb {
     my $self    = shift;
     my $filenam = $_[0];
     my $host = "";             #Initialize the variables.
     my $db   = "";
     my $user = "";
     my $pass = "";
     my $line = "";
     my @spconfig;
     open (my $INFILE, $filenam);
     while ($line = <$INFILE>) {
         if ($line !~ /\/\/.*\$GB_DB\['dbName'\]/ && $line !~ /#.*\$GB_DB\['dbName'\]/ &&
             $line =~ /\$GB_DB\['dbName'\].*=/) { #If this is db config line,
             @spconfig = splitconfigline($line);          #Extract the db name.
             $db = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$GB_DB\['user'\]/ && $line !~ /#.*\$GB_DB\['user'\]/ &&
             $line =~ /\$GB_DB\['user'\].*=/) { #If this is db user config line,
             @spconfig = splitconfigline($line);          #Extract the db user name.
             $user = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$GB_DB\['host'\]/ && $line !~ /#.*\$GB_DB\['host'\]/ &&
             $line =~ /\$GB_DB\['host'\].*=/) { #If this is hostname config line,
             @spconfig = splitconfigline($line);          #Extract the host name.
             $host = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$GB_DB\['pass'\]/ && $line !~ /#.*\$GB_DB\['pass'\]/ &&
             $line =~ /\$GB_DB\['pass'\].*=/) { #If this is password config line,
             @spconfig = splitconfigline($line);          #Extract the password.
             $pass = $spconfig[1];
         }
     }
     close $INFILE;
     if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
     push (my @list, $host);
     push (@list, $db);
     push (@list, $user);
     push (@list, $pass);
     push (@list, "LazarusGuestbook");
     return @list;
}

# Update a LazarusGuestbook config file.
# Input: dbname, dbuname, configfile
# Ouput: Updated LazarusGuestbook configuration file.
sub update_db_lgb {
     my $self     = shift;
     my $dbname   = @_[0];
     my $username = @_[1];
     my $filenam  = @_[2];
     my @spconfig; 
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;
     
     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\/.*\$GB_DB\['dbName'\]/ && $line !~ /#.*\$GB_DB\['dbName'\]/ &&
             $line =~ /\$GB_DB\['dbName'\].*=/) { #If this is db config line,
             $self->logg("Old DB: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $dbname . $spconfig[2];
             $self->logg("New DB: $line\n", 1);
         }
         if ($line !~ /\/\/.*\$GB_DB\['user'\]/ && $line !~ /#.*\$GB_DB\['user'\]/ &&
             $line =~ /\$GB_DB\['user'\].*=/) { #If this is db user config line,
             $self->logg("Old User: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $username . $spconfig[2];
             $self->logg("New User: $line\n", 1);
         }
         if ($line !~ /\/\/.*\$GB_DB\['host'\]/ && $line !~ /#.*\$GB_DB\['host'\]/ &&
             $line =~ /\$GB_DB\['host'\].*=/) { #If this is hostname config line,
             $self->logg("Old Host: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . "localhost" . $spconfig[2];
             $self->logg("New Host: $line\n", 1);
         }
     }
     untie @lines;
}

# ------------------------------------------------------------------------------
# ------------------------------ HelpCenterLive --------------------------------
# ------------------------------------------------------------------------------
# Example HelpCenterLive config.php
#        $conf['host'] = 'localhost';
#        $conf['database'] = 'mss001_hcl';
#        $conf['username'] = 'mss001_hcl';
#        $conf['password'] = 'p6kx9ip7D2ss7gD';
#Extract information out of a HelpCenterLive config file.
#Input: HelpCenterLive config file path/name.
#Output: An array with the hostname, database name, db username, password, and App name in that order.
sub extract_db_hcl {
     my $self    = shift;
     my $filenam = $_[0];
     my $host = "";             #Initialize the variables.
     my $db   = "";
     my $user = "";
     my $pass = "";
     my $line = "";
     my @spconfig;
     open (my $INFILE, $filenam);
     while ($line = <$INFILE>) {
         if ($line !~ /\/\/.*\$conf\['database'\]/ && $line !~ /#.*\$conf\['database'\]/ &&
             $line =~ /\$conf\['database'\].*=/) { #If this is db config line,
             @spconfig = splitconfigline($line);          #Extract the db name.
             $db = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$conf\['username'\]/ && $line !~ /#.*\$conf\['username'\]/ &&
             $line =~ /\$conf\['username'\].*=/) { #If this is db user config line,
             @spconfig = splitconfigline($line);          #Extract the db user name.
             $user = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$conf\['host'\]/ && $line !~ /#.*\$conf\['host'\]/ &&
             $line =~ /\$conf\['host'\].*=/) { #If this is hostname config line,
             @spconfig = splitconfigline($line);          #Extract the host name.
             $host = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$conf\['password'\]/ && $line !~ /#.*\$conf\['password'\]/ &&
             $line =~ /\$conf\['password'\].*=/) { #If this is password config line,
             @spconfig = splitconfigline($line);          #Extract the password.
             $pass = $spconfig[1];
         }
     }
     close $INFILE;
     if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
     push (my @list, $host);
     push (@list, $db);
     push (@list, $user);
     push (@list, $pass);
     push (@list, "HelpCenterLive");
     return @list;
}

# Update a HelpCenterLive config file.
# Input: dbname, dbuname, configfile
# Ouput: Updated HelpCenterLive configuration file.
sub update_db_hcl {
     my $self     = shift;
     my $dbname   = @_[0];
     my $username = @_[1];
     my $filenam  = @_[2];
     my @spconfig; 
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;
     
     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\/.*\$conf\['database'\]/ && $line !~ /#.*\$conf\['database'\]/ &&
             $line =~ /\$conf\['database'\].*=/) { #If this is db config line,
             $self->logg("Old DB: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $dbname . $spconfig[2];
             $self->logg("New DB: $line\n", 1);
         }
         if ($line !~ /\/\/.*\$conf\['username'\]/ && $line !~ /#.*\$conf\['username'\]/ &&
             $line =~ /\$conf\['username'\].*=/) { #If this is db user config line,
             $self->logg("Old User: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $username . $spconfig[2];
             $self->logg("New User: $line\n", 1);
         }
         if ($line !~ /\/\/.*\$conf\['host'\]/ && $line !~ /#.*\$conf\['host'\]/ &&
             $line =~ /\$conf\['host'\].*=/) { #If this is hostname config line,
             $self->logg("Old Host: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . "localhost" . $spconfig[2];
             $self->logg("New Host: $line\n", 1);
         }
     }
     untie @lines;
}


# ------------------------------------------------------------------------------
# --------------------------------- SugarCRM -----------------------------------
# ------------------------------------------------------------------------------
#
# Sample SugarCRM config.php:
#'dbconfig' =>
#array (
#  'db_host_name' => 'localhost',
#  'db_host_instance' => 'SQLEXPRESS',
#  'db_user_name' => 'mss001_sugar',
#  'db_password' => 'hBkupoHVjZwS9f2',
#  'db_name' => 'mss001_sugar',
#  'db_type' => 'mysql',
#  'db_port' => '',
#  'db_manager' => 'MysqliManager',
#),
#Extract information out of a SugarCRM config file.
#Input: SugarCRM config file path/name.
#Output: An array with the hostname, database name, db username, and password in that order.
sub extract_db_sugarcrm {
     my $self = shift;
     my $filenam = $_[0];
     my $host = "";             #Initialize the variables.
     my $db   = "";
     my $user = "";
     my $pass = "";
     my $line = "";
     my @spconfig;
     open (INFILE, $filenam);
     while ($line = <INFILE>) {
         if ($line !~ /\/\/.*db_name/ && $line !~ /#.*db_name/ && length($db) == 0 &&
             $line !~ /\*.*db_name/ && $line =~ /'\s*db_name\s*'\s*=>/) { #If this is db config line,
             @spconfig = splitconfigline($line);          #Extract the db name.
             $db = $spconfig[1];
         }
         if ($line !~ /\/\/.*db_user_name/ && $line !~ /#.*db_user_name/ && length($user) == 0 &&
             $line !~ /\*.*db_user_name/ && $line =~ /'\s*db_user_name\s*'\s*=>/) { #If this is db user config line,
             @spconfig = splitconfigline($line);          #Extract the db user name.
             $user = $spconfig[1];
         }
         if ($line !~ /\/\/.*db_host_name/ && $line !~ /#.*db_host_name/ && length($host) == 0 &&
             $line !~ /\*.*db_host_name/ && $line =~ /'\s*db_host_name\s*'\s*=>/) { #If this is the hostname config line,
             @spconfig = splitconfigline($line);          #Extract the host name.
             $host = $spconfig[1];
         }
         if ($line !~ /\/\/.*db_password/ && $line !~ /#.*db_password/ && length($pass) == 0 &&
             $line !~ /\*.*db_password/ && $line =~ /'\s*db_password\s*'\s*=>/) { #If this is the password config line,
             @spconfig = splitconfigline($line);          #Extract the password.
             $pass = $spconfig[1];
         }
     }
     close INFILE;
     if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
     push (my @list, $host);
     push (@list, $db);
     push (@list, $user);
     push (@list, $pass);
     push (@list, "SugarCRM");
     return @list;
}

# Update a SugarCRM config file.
# Input: dbname, dbuser, configfile
# Ouput: Updated SugarCRM configuration file.
sub update_db_sugarcrm {
     my $self     = shift;
     my $dbname   = @_[0];
     my $username = @_[1];
     my $filenam  = @_[2];
     my @spconfig;
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;
     
     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\/.*db_name/ && $line !~ /#.*db_name/ &&
             $line !~ /\*.*db_name/ && $line =~ /db_name.*=>/) { #If this is db config line,
             $self->logg("Old DB: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $dbname . $spconfig[2];
             $self->logg("New DB: $line\n", 1);
         }
         if ($line !~ /\/\/.*db_user_name/ && $line !~ /#.*db_user_name/ &&
             $line !~ /\*.*db_user_name/ && $line =~ /db_user_name.*=>/) { #If this is db user config line,
             $self->logg("Old User: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $username . $spconfig[2];
             $self->logg("New User: $line\n", 1);
         }
         if ($line !~ /\/\/.*db_host_name/ && $line !~ /#.*db_host_name/ &&
             $line !~ /\*.*db_host_name/ && $line =~ /db_host_name.*=>/) { #If this is the hostname config line,
             $self->logg("Old Host: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . "localhost" . $spconfig[2];
             $self->logg("New Host: $line\n", 1);
         }
     }
     untie @lines;
}


# ------------------------------------------------------------------------------
# -------------------------------- E107 ----------------------------------------
# ------------------------------------------------------------------------------
# Example e107_config.php:
# $mySQLserver         = 'localhost';
# $mySQLuser           = 'mss001_e107';
# $mySQLpassword       = 'Zom9chak';
# $mySQLdefaultdb      = 'mss001_e107';
#Extract information out of an E107 config file.
#Input: E107 config file path/name.
#Output: An array with the hostname, database name, db username, and password in that order.
sub extract_db_e107 {
     my $self    = shift;
     my $filenam = $_[0];
     my $host = "";             #Initialize the variables.
     my $db   = "";
     my $user = "";
     my $pass = "";
     my $line = "";
     my @spconfig;
     open (INFILE, $filenam);
     while ($line = <INFILE>) {
         if ($line !~ /\/\/.*\$mySQLdefaultdb/ && $line !~ /#.*\$mySQLdefaultdb/ &&
             $line =~ /\$mySQLdefaultdb.*=/) { #If this is db config line,
             @spconfig = splitconfigline($line);          #Extract the db name.
             $db = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$mySQLuser/ && $line !~ /#.*\$mySQLuser/ &&
             $line =~ /\$mySQLuser.*=/) { #If this is db user config line,
             @spconfig = splitconfigline($line);          #Extract the db user name.
             $user = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$mySQLserver/ && $line !~ /#.*\$mySQLserver/ &&
             $line =~ /\$mySQLserver.*=/) { #If this is hostname config line,
             @spconfig = splitconfigline($line);          #Extract the host name.
             $host = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$mySQLpassword/ && $line !~ /#.*\$mySQLpassword/ &&
             $line =~ /\$mySQLpassword.*=/) { #If this is password config line,
             @spconfig = splitconfigline($line);          #Extract the password.
             $pass = $spconfig[1];
         }
     }
     close INFILE;
     if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
     push (my @list, $host);
     push (@list, $db);
     push (@list, $user);
     push (@list, $pass);
     push (@list, "E107");
     return @list;
}

# Update an E107 config file.
# Input: dbname, dbuname, configfile
# Ouput: Updated E107 configuration file.
sub update_db_e107 {
     my $self     = shift;
     my $dbname   = @_[0];
     my $username = @_[1];
     my $filenam  = @_[2];
     my @spconfig; 
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;
     
     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\/.*\$mySQLdefaultdb/ && $line !~ /#.*\$mySQLdefaultdb/ &&
             $line =~ /\$mySQLdefaultdb.*=/) { #If this is db config line,
             $self->logg("Old DB: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $dbname . $spconfig[2];
             $self->logg("New DB: $line\n", 1);
         }
         if ($line !~ /\/\/.*\$mySQLuser/ && $line !~ /#.*\$mySQLuser/ &&
             $line =~ /\$mySQLuser.*=/) { #If this is db user config line,
             $self->logg("Old User: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $username . $spconfig[2];
             $self->logg("New User: $line\n", 1);
         }
         if ($line !~ /\/\/.*\$mySQLserver/ && $line !~ /#.*\$mySQLserver/ &&
             $line =~ /\$mySQLserver.*=/) { #If this is hostname config line,
             $self->logg("Old Host: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . "localhost" . $spconfig[2];
             $self->logg("New Host: $line\n", 1);
         }
     }
     untie @lines;
}

# ------------------------------------------------------------------------------
# -------------------------------- Elgg ----------------------------------------
# ------------------------------------------------------------------------------
# Example settings.php:
# $CONFIG->dbuser = 'elgg123';
# $CONFIG->dbpass = 'mysecret';
# $CONFIG->dbname = 'elgg123';
# $CONFIG->dbhost = 'somemysqlhost';
#Extract information out of an Elgg config file.
#Input: Elgg config file path/name.
#Output: An array with the hostname, database name, db username, and password in that order.
sub extract_db_elgg {
     my $self    = shift;
     my $filenam = $_[0];
     my $host = "";             #Initialize the variables.
     my $db   = "";
     my $user = "";
     my $pass = "";
     my $line = "";
     my @spconfig;
     open (INFILE, $filenam);
     while ($line = <INFILE>) {
         if ($line !~ /\/\/.*\$CONFIG->dbname/ && $line !~ /#.*\$CONFIG->dbname/ &&
             $line =~ /\$CONFIG->dbname.*=/) { #If this is db config line,
             @spconfig = splitconfigline($line);          #Extract the db name.
             $db = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$CONFIG->dbuser/ && $line !~ /#.*\$CONFIG->dbuser/ &&
             $line =~ /\$CONFIG->dbuser.*=/) { #If this is db user config line,
             @spconfig = splitconfigline($line);          #Extract the db user name.
             $user = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$CONFIG->dbhost/ && $line !~ /#.*\$CONFIG->dbhost/ &&
             $line =~ /\$CONFIG->dbhost.*=/) { #If this is hostname config line,
             @spconfig = splitconfigline($line);          #Extract the host name.
             $host = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$CONFIG->dbpass/ && $line !~ /#.*\$CONFIG->dbpass/ &&
             $line =~ /\$CONFIG->dbpass.*=/) { #If this is password config line,
             @spconfig = splitconfigline($line);          #Extract the password.
             $pass = $spconfig[1];
         }
     }
     close INFILE;
     if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
     push (my @list, $host);
     push (@list, $db);
     push (@list, $user);
     push (@list, $pass);
     push (@list, "Elgg");
     return @list;
}

# Update an Elgg config file.
# Input: dbname, dbuname, configfile
# Ouput: Updated Elgg configuration file.
sub update_db_elgg {
     my $self     = shift;
     my $dbname   = @_[0];
     my $username = @_[1];
     my $filenam  = @_[2];
     my @spconfig; 
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;
     
     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\/.*\$CONFIG->dbname/ && $line !~ /#.*\$CONFIG->dbname/ &&
             $line =~ /\$CONFIG->dbname.*=/) { #If this is db config line,
             $self->logg("Old DB: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $dbname . $spconfig[2];
             $self->logg("New DB: $line\n", 1);
         }
         if ($line !~ /\/\/.*\$CONFIG->dbuser/ && $line !~ /#.*\$CONFIG->dbuser/ &&
             $line =~ /\$CONFIG->dbuser.*=/) { #If this is db user config line,
             $self->logg("Old User: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $username . $spconfig[2];
             $self->logg("New User: $line\n", 1);
         }
         if ($line !~ /\/\/.*\$CONFIG->dbhost/ && $line !~ /#.*\$CONFIG->dbhost/ &&
             $line =~ /\$CONFIG->dbhost.*=/) { #If this is hostname config line,
             $self->logg("Old Host: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . "localhost" . $spconfig[2];
             $self->logg("New Host: $line\n", 1);
         }
     }
     untie @lines;
}


# ------------------------------------------------------------------------------
# -------------------------------- Prosper202 ------------------------------------
# ------------------------------------------------------------------------------
# Prosper202
# Example 202-config.php:
#$dbname = 'putyourdbnamehere';
#$dbuser = 'usernamehere';
#$dbpass = 'yourpasswordhere';
#$dbhost = 'localhost';
#Extract information out of a Prosper202 config file.
#Input: Prosper202 config file path/name.
#Output: An array with the hostname, database name, db username, and password in that order.
sub extract_db_prosper202 {
     my $self    = shift;
     my $filenam = $_[0];
     my $host = "";             #Initialize the variables.
     my $db   = "";
     my $user = "";
     my $pass = "";
     my $line = "";
     my @spconfig;
     open (INFILE, $filenam);
     while ($line = <INFILE>) {
         if ($line !~ /\/\/.*\$dbname/ && $line !~ /#.*\$dbname/ &&
             $line =~ /\$dbname.*=/) { #If this is db config line,
             @spconfig = splitconfigline($line);          #Extract the db name.
             $db = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$dbuser/ && $line !~ /#.*\$dbuser/ &&
             $line =~ /\$dbuser.*=/) { #If this is db user config line,
             @spconfig = splitconfigline($line);          #Extract the db user name.
             $user = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$dbhost/ && $line !~ /#.*\$dbhost/ &&
             $line =~ /\$dbhost.*=/) { #If this is hostname config line,
             @spconfig = splitconfigline($line);          #Extract the host name.
             $host = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$dbpass/ && $line !~ /#.*\$dbpass/ &&
             $line =~ /\$dbpass.*=/) { #If this is password config line,
             @spconfig = splitconfigline($line);          #Extract the password.
             $pass = $spconfig[1];
         }
     }
     close INFILE;
     if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
     push (my @list, $host);
     push (@list, $db);
     push (@list, $user);
     push (@list, $pass);
     push (@list, "Prosper202");
     return @list;
}

# Update a Prosper202 config file.
# Input: dbname, dbuname, configfile
# Ouput: Updated Prosper202 configuration file.
sub update_db_prosper202 {
     my $self     = shift;
     my $dbname   = @_[0];
     my $username = @_[1];
     my $filenam  = @_[2];
     my @spconfig; 
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;
     
     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\/.*\$dbname/ && $line !~ /#.*\$dbname/ &&
             $line =~ /\$dbname.*=/) { #If this is db config line,
             $self->logg("Old DB: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $dbname . $spconfig[2];
             $self->logg("New DB: $line\n", 1);
         }
         if ($line !~ /\/\/.*\$dbuser/ && $line !~ /#.*\$dbuser/ &&
             $line =~ /\$dbuser.*=/) { #If this is db user config line,
             $self->logg("Old User: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $username . $spconfig[2];
             $self->logg("New User: $line\n", 1);
         }
         if ($line !~ /\/\/.*\$dbhost/ && $line !~ /#.*\$dbhost/ &&
             $line =~ /\$dbhost.*=/) { #If this is hostname config line,
             $self->logg("Old Host: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . "localhost" . $spconfig[2];
             $self->logg("New Host: $line\n", 1);
         }
     }
     untie @lines;
}





# ------------------------------------------------------------------------------
# -------------------------------- CubeCart ------------------------------------
# ------------------------------------------------------------------------------
# CubeCart
# Example Cubecart includes/global.inc.php
#$glob['dbdatabase']     = 'mss001_cube';           // e.g. cubecart 
#$glob['dbhost']         = 'mysqlserver.com';       // e.g. localhost (Can be domain or ip address)
#$glob['dbusername']     = 'someuser';              // username that has access to the db
#$glob['dbpassword']     = 'kl$#E2v5ke3';           // password for username
#Extract information out of a CubeCart config file.
#Input: CubeCart config file path/name.
#Output: An array with the hostname, database name, db username, and password in that order.
sub extract_db_cubecart {
     my $self    = shift;
     my $filenam = $_[0];
     my $host = "";             #Initialize the variables.
     my $db   = "";
     my $user = "";
     my $pass = "";
     my $line = "";
     my @spconfig;
     open (INFILE, $filenam);
     while ($line = <INFILE>) {
         if ($line !~ /\/\/.*\$glob\['dbdatabase'\]/ && $line !~ /#.*\$glob\['dbdatabase'\]/ &&
             $line =~ /\$glob\['dbdatabase'\].*=/) { #If this is db config line,
             @spconfig = splitconfigline($line);          #Extract the db name.
             $db = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$glob\['dbusername'\]/ && $line !~ /#.*\$glob\['dbusername'\]/ &&
             $line =~ /\$glob\['dbusername'\].*=/) { #If this is db user config line,
             @spconfig = splitconfigline($line);          #Extract the db user name.
             $user = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$glob\['dbhost'\]/ && $line !~ /#.*\$glob\['dbhost'\]/ &&
             $line =~ /\$glob\['dbhost'\].*=/) { #If this is hostname config line,
             @spconfig = splitconfigline($line);          #Extract the host name.
             $host = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$glob\['dbpassword'\]/ && $line !~ /#.*\$glob\['dbpassword'\]/ &&
             $line =~ /\$glob\['dbpassword'\].*=/) { #If this is password config line,
             @spconfig = splitconfigline($line);          #Extract the password.
             $pass = $spconfig[1];
         }
     }
     close INFILE;
     if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
     push (my @list, $host);
     push (@list, $db);
     push (@list, $user);
     push (@list, $pass);
     push (@list, "CubeCart");
     return @list;
}

# Update a CubeCart config file.
# Input: dbname, dbuname, configfile
# Ouput: Updated CubeCart configuration file.
sub update_db_cubecart {
     my $self     = shift;
     my $dbname   = @_[0];
     my $username = @_[1];
     my $filenam  = @_[2];
     my @spconfig; 
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;
     
     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\/.*\$glob\['dbdatabase'\]/ && $line !~ /#.*\$glob\['dbdatabase'\]/ &&
             $line =~ /\$glob\['dbdatabase'\].*=/) { #If this is db config line,
             $self->logg("Old DB: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $dbname . $spconfig[2];
             $self->logg("New DB: $line\n", 1);
         }
         if ($line !~ /\/\/.*\$glob\['dbusername'\]/ && $line !~ /#.*\$glob\['dbusername'\]/ &&
             $line =~ /\$glob\['dbusername'\].*=/) { #If this is db user config line,
             $self->logg("Old User: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $username . $spconfig[2];
             $self->logg("New User: $line\n", 1);
         }
         if ($line !~ /\/\/.*\$glob\['dbhost'\]/ && $line !~ /#.*\$glob\['dbhost'\]/ &&
             $line =~ /\$glob\['dbhost'\].*=/) { #If this is hostname config line,
             $self->logg("Old Host: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . "localhost" . $spconfig[2];
             $self->logg("New Host: $line\n", 1);
         }
     }
     untie @lines;
}

# ------------------------------------------------------------------------------
# -------------------------------- DAP -----------------------------------------
# ------------------------------------------------------------------------------
# DAP is a WordPress Membership Plugin.  
# Example dap/dap-config.php
#define('DB_NAME_DAP', 'chiroweb_wrdp1');    // The name of the database
#define('DB_USER_DAP', 'chiroweb_wrdp1');     // Your MySQL username
#define('DB_PASSWORD_DAP', 'UpWVpCQ0NohuKSe8'); // ...and password
#define('DB_HOST_DAP', 'localhost');    // 99% chance you won't need to change this value
#Extract information out of a dap config file.
#Input: DAP config file path/name.
#Output: An array with the hostname, database name, db username, and password in that order.
sub extract_db_dap {
    my $self = shift;
    my $filenam = $_[0];
    my $host = "";             #Initialize the variables.
    my $db   = "";
    my $user = "";
    my $pass = "";
    my $line = "";
    open (INFILE, $filenam);
    while ($line = <INFILE>) {
        if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ && $line =~ /define/ && $line =~ /DB_NAME_DAP/) { #If this is db config line,
            $db = $line;                               #Extract the db name.
            $db =~ s/'\s*\);.*//;
            $db =~ s/.*'//;
            $db =~ s/\n//;
            $db =~ s/\r//;
        }
        if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ && $line =~ /define/ && $line =~ /DB_USER_DAP/) { #If this is the username config line,
            $user = $line;                             #Extract it.
            $user =~ s/'\s*\);.*//;
            $user =~ s/.*'//;
            $user =~ s/\n//;
            $user =~ s/\r//;
        }
        if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ && $line =~ /define/ && $line =~ /DB_HOST_DAP/) { #If this is the host config line,
            $host = $line;                             #Extract it.
            $host =~ s/'\s*\);.*//;
            $host =~ s/.*'//;
            $host =~ s/\n//;
            $host =~ s/\r//;
        }
        if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ && $line =~ /define/ && $line =~ /DB_PASSWORD_DAP/) { #If this is the password config line,
            $pass = $line;                                 #Extract it.
            $pass =~ s/'\s*\);.*//;
            $pass =~ s/.*'//;
            $pass =~ s/\n//;
            $pass =~ s/\r//;
        }
    }
    close INFILE;
    if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
    push (my @list, $host);
    push (@list, $db);
    push (@list, $user);
    push (@list, $pass);
    push (@list, "DAP");
    return @list;
}

# Update an DAP config file.
# Input: dbname, dbuser, configfile
# Ouput: Updated DAP configuration file.
sub update_db_dap {
     my $self     = shift;
     my $dbname   = @_[0];
     my $username = @_[1];
     my $filenam  = @_[2];

     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;

     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /DB_NAME_DAP/) { #If this is db config line,
             $self->logg("Old DB: $line\n", 1);
             $line =~ s/',.*'.*'\);/', '$dbname');/;     #replace it with the new db name.
             $self->logg("New DB: $line\n", 1);
         }
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /DB_USER_DAP/) { #If this is the username config line,
             $self->logg("Old User: $line\n", 1);
             $line =~ s/',.*'.*'\);/', '$username');/;     #replace it with the new user name.
             $self->logg("New User: $line\n", 1);
         }
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /DB_HOST_DAP/) { #If this is the host config line,
             $self->logg("Old Host: $line\n", 1);
             $line =~ s/',.*'.*'\);/', 'localhost');/;     #replace it with the new host name.
             $self->logg("New Host: $line\n", 1);
         }
     }
     untie @lines;
}

# ------------------------------------------------------------------------------
# -------------------------------- Piwik ---------------------------------------
# ------------------------------------------------------------------------------
# Piwik is a web analytics script that is integrated into Piwik.
# Example ext/piwik/config/config.ini.php:
#host = "localhost"
#username = "mss001_tmtc13"
#password = "JgLrYYyhFmTJhlSM"
#dbname = "mss001_tmtc13"
#Extract information out of a Piwik config file.
#Input: Piwik config file path/name.
#Output: An array with the hostname, database name, db username, and password in that order.
sub extract_db_piwik {
     my $self    = shift;
     my $filenam = $_[0];
     my $host = "";             #Initialize the variables.
     my $db   = "";
     my $user = "";
     my $pass = "";
     my $line = "";
     my @spconfig;
     open (INFILE, $filenam);
     while ($line = <INFILE>) {
         if ($line !~ /\/\/.*dbname/ && $line !~ /#.*dbname/ &&
             $line =~ /dbname.*=/) { #If this is db config line,
             @spconfig = splitconfigline($line);          #Extract the db name.
             $db = $spconfig[1];
         }
         if ($line !~ /\/\/.*username/ && $line !~ /#.*username/ &&
             $line =~ /username.*=/) { #If this is db user config line,
             @spconfig = splitconfigline($line);          #Extract the db user name.
             $user = $spconfig[1];
         }
         if ($line !~ /\/\/.*host/ && $line !~ /#.*host/ &&
             $line =~ /host.*=/) { #If this is hostname config line,
             @spconfig = splitconfigline($line);          #Extract the host name.
             $host = $spconfig[1];
         }
         if ($line !~ /\/\/.*password/ && $line !~ /#.*password/ &&
             $line =~ /password.*=/) { #If this is password config line,
             @spconfig = splitconfigline($line);          #Extract the password.
             $pass = $spconfig[1];
         }
     }
     close INFILE;
     if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
     push (my @list, $host);
     push (@list, $db);
     push (@list, $user);
     push (@list, $pass);
     push (@list, "Piwik");
     return @list;
}

# Update a Piwik config file.
# Input: dbname, dbuname, configfile
# Ouput: Updated Piwik configuration file.
sub update_db_piwik {
     my $self     = shift;
     my $dbname   = @_[0];
     my $username = @_[1];
     my $filenam  = @_[2];
     my @spconfig; 
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;
     
     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\/.*dbname/ && $line !~ /#.*dbname/ &&
             $line =~ /dbname.*=/) { #If this is db config line,
             $self->logg("Old DB: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $dbname . $spconfig[2];
             $self->logg("New DB: $line\n", 1);
         }
         if ($line !~ /\/\/.*username/ && $line !~ /#.*username/ &&
             $line =~ /username.*=/) { #If this is db user config line,
             $self->logg("Old User: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $username . $spconfig[2];
             $self->logg("New User: $line\n", 1);
         }
         if ($line !~ /\/\/.*host/ && $line !~ /#.*host/ &&
             $line =~ /host.*=/) { #If this is hostname config line,
             $self->logg("Old Host: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . "localhost" . $spconfig[2];
             $self->logg("New Host: $line\n", 1);
         }
     }
     untie @lines;
}

# ------------------------------------------------------------------------------
# -------------------------------- MyBB ----------------------------------------
# ------------------------------------------------------------------------------
# Example MyBB inc/config.php file.
#$config['database']['database'] = 'mss001_mybb2';
#$config['database']['hostname'] = 'localhost';
#$config['database']['username'] = 'mss001_mybb2';
#$config['database']['password'] = 'BFAjOpp6kbsyPuO9';
#Extract information out of a Coppermine config file.
#Input: Coppermine config file path/name.
#Output: An array with the hostname, database name, db username, and password in that order.
sub extract_db_mybb {
     my $self    = shift;
     my $filenam = $_[0];
     my $host = "";             #Initialize the variables.
     my $db   = "";
     my $user = "";
     my $pass = "";
     my $line = "";
     my @spconfig;
     open (INFILE, $filenam);
     while ($line = <INFILE>) {
         if ($line !~ /\/\/.*\$config\['database'\]\['database'\]/ && $line !~ /#.*\$config\['database'\]\['database'\]/ &&
             $line =~ /\$config\['database'\]\['database'\].*=/) { #If this is db config line,
             @spconfig = splitconfigline($line);          #Extract the db name.
             $db = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$config\['database'\]\['username'\]/ && $line !~ /#.*\$config\['database'\]\['username'\]/ &&
             $line =~ /\$config\['database'\]\['username'\].*=/) { #If this is db user config line,
             @spconfig = splitconfigline($line);          #Extract the db user name.
             $user = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$config\['database'\]\['hostname'\]/ && $line !~ /#.*\$config\['database'\]\['hostname'\]/ &&
             $line =~ /\$config\['database'\]\['hostname'\].*=/) { #If this is hostname config line,
             @spconfig = splitconfigline($line);          #Extract the host name.
             $host = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$config\['database'\]\['password'\]/ && $line !~ /#.*\$config\['database'\]\['password'\]/ &&
             $line =~ /\$config\['database'\]\['password'\].*=/) { #If this is password config line,
             @spconfig = splitconfigline($line);          #Extract the password.
             $pass = $spconfig[1];
         }
     }
     close INFILE;
     if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
     push (my @list, $host);
     push (@list, $db);
     push (@list, $user);
     push (@list, $pass);
     push (@list, "MyBB");
     return @list;
}

# Update a Coppermine config file.
# Input: dbname, dbuname, configfile
# Ouput: Updated Coppermine configuration file.
sub update_db_mybb {
     my $self     = shift;
     my $dbname   = @_[0];
     my $username = @_[1];
     my $filenam  = @_[2];
     my @spconfig; 
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;
     
     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\/.*\$config\['database'\]\['database'\]/ && $line !~ /#.*\$config\['database'\]\['database'\]/ &&
             $line =~ /\$config\['database'\]\['database'\].*=/) { #If this is db config line,
             $self->logg("Old DB: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $dbname . $spconfig[2];
             $self->logg("New DB: $line\n", 1);
         }
         if ($line !~ /\/\/.*\$config\['database'\]\['username'\]/ && $line !~ /#.*\$config\['database'\]\['username'\]/ &&
             $line =~ /\$config\['database'\]\['username'\].*=/) { #If this is db user config line,
             $self->logg("Old User: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $username . $spconfig[2];
             $self->logg("New User: $line\n", 1);
         }
         if ($line !~ /\/\/.*\$config\['database'\]\['hostname'\]/ && $line !~ /#.*\$config\['database'\]\['hostname'\]/ &&
             $line =~ /\$config\['database'\]\['hostname'\].*=/) { #If this is hostname config line,
             $self->logg("Old Host: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . "localhost" . $spconfig[2];
             $self->logg("New Host: $line\n", 1);
         }
     }
     untie @lines;
}

# ------------------------------------------------------------------------------
# ----------------------------- phpList ----------------------------------------
# ------------------------------------------------------------------------------
# Example phpList config/config.php file.
# $database_host = "localhost";
# $database_name = "mss001_phpl1";
# $database_user = "mss001_phpl1";
# $database_password = 'dIPI8OHzoewNVouw';
#
#Extract information out of a phpList config file.
#Input: phpList config file path/name.
#Output: An array with the hostname, database name, db username, and password in that order.
sub extract_db_phplist {
     my $self    = shift;
     my $filenam = $_[0];
     my $host = "";             #Initialize the variables.
     my $db   = "";
     my $user = "";
     my $pass = "";
     my $line = "";
     my @spconfig;
     open (INFILE, $filenam);
     while ($line = <INFILE>) {
         if ($line !~ /\/\/.*\$database_name/ && $line !~ /#.*\$database_name/ &&
             $line =~ /\$database_name.*=/) { #If this is db config line,
             @spconfig = splitconfigline($line);          #Extract the db name.
             $db = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$database_user/ && $line !~ /#.*\$database_user/ &&
             $line =~ /\$database_user.*=/) { #If this is db user config line,
             @spconfig = splitconfigline($line);          #Extract the db user name.
             $user = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$database_host/ && $line !~ /#.*\$database_host/ &&
             $line =~ /\$database_host.*=/) { #If this is hostname config line,
             @spconfig = splitconfigline($line);          #Extract the host name.
             $host = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$database_password/ && $line !~ /#.*\$database_password/ &&
             $line =~ /\$database_password.*=/) { #If this is password config line,
             @spconfig = splitconfigline($line);          #Extract the password.
             $pass = $spconfig[1];
         }
     }
     close INFILE;
     if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
     push (my @list, $host);
     push (@list, $db);
     push (@list, $user);
     push (@list, $pass);
     push (@list, "phpList");
     return @list;
}

# Update a phpList config file.
# Input: dbname, dbuname, configfile
# Ouput: Updated phpList configuration file.
sub update_db_phplist {
     my $self     = shift;
     my $dbname   = @_[0];
     my $username = @_[1];
     my $filenam  = @_[2];
     my @spconfig; 
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;
     
     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\/.*\$database_name/ && $line !~ /#.*\$database_name/ &&
             $line =~ /\$database_name.*=/) { #If this is db config line,
             $self->logg("Old DB: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $dbname . $spconfig[2];
             $self->logg("New DB: $line\n", 1);
         }
         if ($line !~ /\/\/.*\$database_user/ && $line !~ /#.*\$database_user/ &&
             $line =~ /\$database_user.*=/) { #If this is db user config line,
             $self->logg("Old User: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $username . $spconfig[2];
             $self->logg("New User: $line\n", 1);
         }
         if ($line !~ /\/\/.*\$database_host/ && $line !~ /#.*\$database_host/ &&
             $line =~ /\$database_host.*=/) { #If this is hostname config line,
             $self->logg("Old Host: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . "localhost" . $spconfig[2];
             $self->logg("New Host: $line\n", 1);
         }
     }
     untie @lines;
}

# ------------------------------------------------------------------------------
# ------------------------------ Coppermine ------------------------------------
# ------------------------------------------------------------------------------
# Example Coppermine include/config.inc.php file.
#$CONFIG['dbserver'] =                         'localhost';        // Your database server
#$CONFIG['dbuser'] =                         'mss001_cppr1';        // Your mysql username
#$CONFIG['dbpass'] =                         'vfP44dgqryYynuJY';                // Your mysql password
#$CONFIG['dbname'] =                         'mss001_cppr1';        // Your mysql database name
#Extract information out of a Coppermine config file.
#Input: Coppermine config file path/name.
#Output: An array with the hostname, database name, db username, and password in that order.
sub extract_db_coppermine {
     my $self    = shift;
     my $filenam = $_[0];
     my $host = "";             #Initialize the variables.
     my $db   = "";
     my $user = "";
     my $pass = "";
     my $line = "";
     my @spconfig;
     open (INFILE, $filenam);
     while ($line = <INFILE>) {
         if ($line !~ /\/\/.*\$CONFIG\['dbname'\]/ && $line !~ /#.*\$CONFIG\['dbname'\]/ &&
             $line =~ /\$CONFIG\['dbname'\].*=/) { #If this is db config line,
             @spconfig = splitconfigline($line);          #Extract the db name.
             $db = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$CONFIG\['dbuser'\]/ && $line !~ /#.*\$CONFIG\['dbuser'\]/ &&
             $line =~ /\$CONFIG\['dbuser'\].*=/) { #If this is db user config line,
             @spconfig = splitconfigline($line);          #Extract the db user name.
             $user = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$CONFIG\['dbserver'\]/ && $line !~ /#.*\$CONFIG\['dbserver'\]/ &&
             $line =~ /\$CONFIG\['dbserver'\].*=/) { #If this is hostname config line,
             @spconfig = splitconfigline($line);          #Extract the host name.
             $host = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$CONFIG\['dbpass'\]/ && $line !~ /#.*\$CONFIG\['dbpass'\]/ &&
             $line =~ /\$CONFIG\['dbpass'\].*=/) { #If this is password config line,
             @spconfig = splitconfigline($line);          #Extract the password.
             $pass = $spconfig[1];
         }
     }
     close INFILE;
     if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
     push (my @list, $host);
     push (@list, $db);
     push (@list, $user);
     push (@list, $pass);
     push (@list, "Coppermine");
     return @list;
}

# Update a Coppermine config file.
# Input: dbname, dbuname, configfile
# Ouput: Updated Coppermine configuration file.
sub update_db_coppermine {
     my $self     = shift;
     my $dbname   = @_[0];
     my $username = @_[1];
     my $filenam  = @_[2];
     my @spconfig; 
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;
     
     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\/.*\$CONFIG\['dbname'\]/ && $line !~ /#.*\$CONFIG\['dbname'\]/ &&
             $line =~ /\$CONFIG\['dbname'\].*=/) { #If this is db config line,
             $self->logg("Old DB: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $dbname . $spconfig[2];
             $self->logg("New DB: $line\n", 1);
         }
         if ($line !~ /\/\/.*\$CONFIG\['dbuser'\]/ && $line !~ /#.*\$CONFIG\['dbuser'\]/ &&
             $line =~ /\$CONFIG\['dbuser'\].*=/) { #If this is db user config line,
             $self->logg("Old User: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $username . $spconfig[2];
             $self->logg("New User: $line\n", 1);
         }
         if ($line !~ /\/\/.*\$CONFIG\['dbserver'\]/ && $line !~ /#.*\$CONFIG\['dbserver'\]/ &&
             $line =~ /\$CONFIG\['dbserver'\].*=/) { #If this is hostname config line,
             $self->logg("Old Host: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . "localhost" . $spconfig[2];
             $self->logg("New Host: $line\n", 1);
         }
     }
     untie @lines;
}

# ------------------------------------------------------------------------------
# ------------------------------- Moodle ---------------------------------------
# ------------------------------------------------------------------------------
# Example Moodle config.php (in the root of the Moodle installation):
# $CFG->dbhost    = 'localhost';
# $CFG->dbname    = 'mss001_mdln1';
# $CFG->dbuser    = 'mss001_mdln1';
# $CFG->dbpass    = '04TNfwAA7i4tibtn';
#Extract information out of a Moodle config file.
#Input: Moodle config file path/name.
#Output: An array with the hostname, database name, db username, and password in that order.
sub extract_db_moodle {
     my $self    = shift;
     my $filenam = $_[0];
     my $host = "";             #Initialize the variables.
     my $db   = "";
     my $user = "";
     my $pass = "";
     my $line = "";
     my @spconfig;
     open (INFILE, $filenam);
     while ($line = <INFILE>) {
         if ($line !~ /\/\/.*\$CFG->dbname/ && $line !~ /#.*\$CFG->dbname/ &&
             $line =~ /\$CFG->dbname.*=/) { #If this is db config line,
             @spconfig = splitconfigline($line);          #Extract the db name.
             $db = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$CFG->dbuser/ && $line !~ /#.*\$CFG->dbuser/ &&
             $line =~ /\$CFG->dbuser.*=/) { #If this is db user config line,
             @spconfig = splitconfigline($line);          #Extract the db user name.
             $user = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$CFG->dbhost/ && $line !~ /#.*\$CFG->dbhost/ &&
             $line =~ /\$CFG->dbhost.*=/) { #If this is hostname config line,
             @spconfig = splitconfigline($line);          #Extract the host name.
             $host = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$CFG->dbpass/ && $line !~ /#.*\$CFG->dbpass/ &&
             $line =~ /\$CFG->dbpass.*=/) { #If this is password config line,
             @spconfig = splitconfigline($line);          #Extract the password.
             $pass = $spconfig[1];
         }
     }
     close INFILE;
     if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
     push (my @list, $host);
     push (@list, $db);
     push (@list, $user);
     push (@list, $pass);
     push (@list, "Moodle");
     return @list;
}

# Update a Moodle config file.
# Input: dbname, dbuname, configfile
# Ouput: Updated Moodle configuration file.
sub update_db_moodle {
     my $self     = shift;
     my $dbname   = @_[0];
     my $username = @_[1];
     my $filenam  = @_[2];
     my @spconfig; 
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;
     
     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\/.*\$CFG->dbname/ && $line !~ /#.*\$CFG->dbname/ &&
             $line =~ /\$CFG->dbname.*=/) { #If this is db config line,
             $self->logg("Old DB: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $dbname . $spconfig[2];
             $self->logg("New DB: $line\n", 1);
         }
         if ($line !~ /\/\/.*\$CFG->dbuser/ && $line !~ /#.*\$CFG->dbuser/ &&
             $line =~ /\$CFG->dbuser.*=/) { #If this is db user config line,
             $self->logg("Old User: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $username . $spconfig[2];
             $self->logg("New User: $line\n", 1);
         }
         if ($line !~ /\/\/.*\$CFG->dbhost/ && $line !~ /#.*\$CFG->dbhost/ &&
             $line =~ /\$CFG->dbhost.*=/) { #If this is hostname config line,
             $self->logg("Old Host: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . "localhost" . $spconfig[2];
             $self->logg("New Host: $line\n", 1);
         }
     }
     untie @lines;
}



# ------------------------------------------------------------------------------
# ------------------------------- MediaWiki ------------------------------------
# ------------------------------------------------------------------------------
# Example MediaWiki LocalSettings.php
#$wgDBserver         = "localhost";
#$wgDBname           = "mss001_mdwk1";
#$wgDBuser           = "mss001_mdwk1";
#$wgDBpassword       = "ah4yXN0MX5WQFd8q";
#
#Extract information out of a MediaWiki config file.
#Input: MediaWiki config file path/name.
#Output: An array with the hostname, database name, db username, and password in that order.
sub extract_db_mediawiki {
     my $self    = shift;
     my $filenam = $_[0];
     my $host = "";             #Initialize the variables.
     my $db   = "";
     my $user = "";
     my $pass = "";
     my $line = "";
     my @spconfig;
     open (INFILE, $filenam);
     while ($line = <INFILE>) {
         if ($line !~ /\/\/.*\$wgDBname/ && $line !~ /#.*\$wgDBname/ &&
             $line =~ /\$wgDBname.*=/) { #If this is db config line,
             @spconfig = splitconfigline($line);          #Extract the db name.
             $db = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$wgDBuser/ && $line !~ /#.*\$wgDBuser/ &&
             $line =~ /\$wgDBuser.*=/) { #If this is db user config line,
             @spconfig = splitconfigline($line);          #Extract the db user name.
             $user = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$wgDBserver/ && $line !~ /#.*\$wgDBserver/ &&
             $line =~ /\$wgDBserver.*=/) { #If this is hostname config line,
             @spconfig = splitconfigline($line);          #Extract the host name.
             $host = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$wgDBpassword/ && $line !~ /#.*\$wgDBpassword/ &&
             $line =~ /\$wgDBpassword.*=/) { #If this is password config line,
             @spconfig = splitconfigline($line);          #Extract the password.
             $pass = $spconfig[1];
         }
     }
     close INFILE;
     if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
     push (my @list, $host);
     push (@list, $db);
     push (@list, $user);
     push (@list, $pass);
     push (@list, "MediaWiki");
     return @list;
}

# Update a MediaWiki config file.
# Input: dbname, dbuname, configfile
# Ouput: Updated MediaWiki configuration file.
sub update_db_mediawiki {
     my $self     = shift;
     my $dbname   = @_[0];
     my $username = @_[1];
     my $filenam  = @_[2];
     my @spconfig; 
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;
     
     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\/.*\$wgDBname/ && $line !~ /#.*\$wgDBname/ &&
             $line =~ /\$wgDBname.*=/) { #If this is db config line,
             $self->logg("Old DB: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $dbname . $spconfig[2];
             $self->logg("New DB: $line\n", 1);
         }
         if ($line !~ /\/\/.*\$wgDBuser/ && $line !~ /#.*\$wgDBuser/ &&
             $line =~ /\$wgDBuser.*=/) { #If this is db user config line,
             $self->logg("Old User: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $username . $spconfig[2];
             $self->logg("New User: $line\n", 1);
         }
         if ($line !~ /\/\/.*\$wgDBserver/ && $line !~ /#.*\$wgDBserver/ &&
             $line =~ /\$wgDBserver.*=/) { #If this is hostname config line,
             $self->logg("Old Host: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . "localhost" . $spconfig[2];
             $self->logg("New Host: $line\n", 1);
         }
     }
     untie @lines;
}





# ------------------------------------------------------------------------------
# ------------------------------- OpenCart -------------------------------------
# ------------------------------------------------------------------------------
# Example OpenCart config.php:
#define('DB_HOSTNAME', 'localhost');
#define('DB_USERNAME', 'shaws4p_shaws4adam');
#define('DB_PASSWORD', 'gkhJknbn980TY');
#define('DB_DATABASE', 'shaws4p_shaws4adam');
#
#Extract information out of a opencart config file.
#Input: OpenCart config file path/name.
#Output: An array with the hostname, database name, db username, and password in that order.
sub extract_db_opencart {
    my $self = shift;
    my $filenam = $_[0];
    my $host = "";             #Initialize the variables.
    my $db   = "";
    my $user = "";
    my $pass = "";
    my $line = "";
    open (INFILE, $filenam);
    while ($line = <INFILE>) {
        if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ && $line =~ /define/ && $line =~ /DB_DATABASE/) { #If this is db config line,
            $db = $line;                               #Extract the db name.
            $db =~ s/'\s*\);.*//;
            $db =~ s/.*'//;
            $db =~ s/\n//;
            $db =~ s/\r//;
        }
        if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ && $line =~ /define/ && $line =~ /DB_USERNAME/) { #If this is the username config line,
            $user = $line;                             #Extract it.
            $user =~ s/'\s*\);.*//;
            $user =~ s/.*'//;
            $user =~ s/\n//;
            $user =~ s/\r//;
        }
        if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ && $line =~ /define/ && $line =~ /DB_HOSTNAME/) { #If this is the host config line,
            $host = $line;                             #Extract it.
            $host =~ s/'\s*\);.*//;
            $host =~ s/.*'//;
            $host =~ s/\n//;
            $host =~ s/\r//;
        }
        if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ && $line =~ /define/ && $line =~ /DB_PASSWORD/) { #If this is the host config line,
            $pass = $line;                                 #Extract it.
            $pass =~ s/'\s*\);.*//;
            $pass =~ s/.*'//;
            $pass =~ s/\n//;
            $pass =~ s/\r//;
        }
    }
    close INFILE;
    if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
    push (my @list, $host);
    push (@list, $db);
    push (@list, $user);
    push (@list, $pass);
    push (@list, "OpenCart");
    return @list;
}

# Update an OpenCart config file.
# Input: dbname, dbuser, configfile
# Ouput: Updated OpenCart configuration file.
sub update_db_opencart {
     my $self     = shift;
     my $dbname   = @_[0];
     my $username = @_[1];
     my $filenam  = @_[2];

     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;

     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /DB_DATABASE/) { #If this is db config line,
             $self->logg("Old DB: $line\n", 1);
             $line =~ s/',.*'.*'\);/', '$dbname');/;     #replace it with the new db name.
             $self->logg("New DB: $line\n", 1);
         }
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /DB_USERNAME/) { #If this is the username config line,
             $self->logg("Old User: $line\n", 1);
             $line =~ s/',.*'.*'\);/', '$username');/;     #replace it with the new user name.
             $self->logg("New User: $line\n", 1);
         }
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /DB_HOSTNAME/) { #If this is the host config line,
             $self->logg("Old Host: $line\n", 1);
             $line =~ s/',.*'.*'\);/', 'localhost');/;     #replace it with the new host name.
             $self->logg("New Host: $line\n", 1);
         }
     }
     untie @lines;
}

# ------------------------------------------------------------------------------
# ------------------------------ Prestashop ------------------------------------
# ------------------------------------------------------------------------------
# Example Prestashop settings.inc.php:
#define('_DB_NAME_', 'adwords_adwords');
#define('_DB_SERVER_', 'localhost');
#define('_DB_USER_', 'adwords_adwords');
#define('_DB_PASSWD_', 'kk55kk66');
#
#Extract information out of a Prestashop config file.
#Input: Prestashop config file path/name.
#Output: An array with the hostname, database name, db username, and password in that order.
sub extract_db_presta {
        my $self = shift;
        my $filenam = $_[0];
        my $host = "";             #Initialize the variables.
        my $db   = "";
        my $user = "";
        my $pass = "";
        my $line = "";
        my @spconfig;
        open (INFILE, $filenam);
        while ($line = <INFILE>) {
                if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ && $line =~ /define/ && $line =~ /_DB_NAME_/) { #If this is db config line,
                        $db = $line;                               #Extract the db name.
                        $db =~ s/'\);.*//;
                        $db =~ s/.*'//;
                        $db =~ s/\n//;
                        $db =~ s/\r//;
                }
                if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ && $line =~ /define/ && $line =~ /_DB_USER_/) { #If this is the username config line,
                        $user = $line;                             #Extract it.
                        $user =~ s/'\);.*//;
                        $user =~ s/.*'//;
                        $user =~ s/\n//;
                        $user =~ s/\r//;
                }
                if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ && $line =~ /define/ && $line =~ /_DB_SERVER_/) { #If this is the host config line,
                        $host = $line;                             #Extract it.
                        $host =~ s/'\);.*//;
                        $host =~ s/.*'//;
                        $host =~ s/\n//;
                        $host =~ s/\r//;
                }
                if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ && $line =~ /define/ && $line =~ /_DB_PASSWD_/) { #If this is the host config line,
                        $pass = $line;                                 #Extract it.
                        $pass =~ s/'\);.*//;
                        $pass =~ s/.*'//;
                        $pass =~ s/\n//;
                        $pass =~ s/\r//;
                }
        }
        close INFILE;
        if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
        push (my @list, $host);
        push (@list, $db);
        push (@list, $user);
        push (@list, $pass);
        push (@list, "Prestashop");
        return @list;
}

# Update a Prestashop config file.
# Input: dbname, dbuser, configfile
# Ouput: Updated Prestashop configuration file.
sub update_db_presta {
     my $self     = shift;
     my $dbname   = @_[0];
     my $username = @_[1];
     my $filenam  = @_[2];

     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;

     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /_DB_NAME_/) { #If this is db config line,
             $self->logg("Old DB: $line\n", 1);
             $line =~ s/',.*'.*'\);/', '$dbname');/;     #replace it with the new db name.
             $self->logg("New DB: $line\n", 1);
         }
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /_DB_USER_/) { #If this is the username config line,
             $self->logg("Old User: $line\n", 1);
             $line =~ s/',.*'.*'\);/', '$username');/;     #replace it with the new user name.
             $self->logg("New User: $line\n", 1);
         }
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /_DB_SERVER_/) { #If this is the host config line,
             $self->logg("Old Host: $line\n", 1);
             $line =~ s/',.*'.*'\);/', 'localhost');/;     #replace it with the new host name.
             $self->logg("New Host: $line\n", 1);
         }
     }
     untie @lines;
}


# ------------------------------------------------------------------------------
# ------------------------------ PHP-Nuke --------------------------------------
# ------------------------------------------------------------------------------
# Example PHP-Nuke config.php:
#$dbhost = "localhost";
#$dbuname = "mss001_phpn1";
#$dbpass = "60Bk5p7irjVYd6io";
#$dbname = "mss001_phpn1";
#
#Extract information out of a PHP-Nuke config file.
#Input: PHP-Nuke config file path/name.
#Output: An array with the hostname, database name, db username, and password in that order.
sub extract_db_phpnuke {
     my $self    = shift;
     my $filenam = $_[0];
     my $host = "";             #Initialize the variables.
     my $db   = "";
     my $user = "";
     my $pass = "";
     my $line = "";
     my @spconfig;
     open (INFILE, $filenam);
     while ($line = <INFILE>) {
         if ($line !~ /\/\/.*\$dbname/ && $line !~ /#.*\$dbname/ &&
             $line =~ /\$dbname.*=/) { #If this is db config line,
             @spconfig = splitconfigline($line);          #Extract the db name.
             $db = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$dbuname/ && $line !~ /#.*\$dbuname/ &&
             $line =~ /\$dbuname.*=/) { #If this is db user config line,
             @spconfig = splitconfigline($line);          #Extract the db user name.
             $user = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$dbhost/ && $line !~ /#.*\$dbhost/ &&
             $line =~ /\$dbhost.*=/) { #If this is hostname config line,
             @spconfig = splitconfigline($line);          #Extract the host name.
             $host = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$dbpass/ && $line !~ /#.*\$dbpass/ &&
             $line =~ /\$dbpass.*=/) { #If this is password config line,
             @spconfig = splitconfigline($line);          #Extract the password.
             $pass = $spconfig[1];
         }
     }
     close INFILE;
     if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
     push (my @list, $host);
     push (@list, $db);
     push (@list, $user);
     push (@list, $pass);
     push (@list, "PHP-Nuke");
     return @list;
}

# Update a PHP-Nuke config file.
# Input: dbname, dbuname, configfile
# Ouput: Updated PHP-Nuke configuration file.
sub update_db_phpnuke {
     my $self     = shift;
     my $dbname   = @_[0];
     my $username = @_[1];
     my $filenam  = @_[2];
     my @spconfig; 
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;
     
     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\/.*\$dbname/ && $line !~ /#.*\$dbname/ &&
             $line =~ /\$dbname.*=/) { #If this is db config line,
             $self->logg("Old DB: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $dbname . $spconfig[2];
             $self->logg("New DB: $line\n", 1);
         }
         if ($line !~ /\/\/.*\$dbuname/ && $line !~ /#.*\$dbuname/ &&
             $line =~ /\$dbuname.*=/) { #If this is db user config line,
             $self->logg("Old User: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $username . $spconfig[2];
             $self->logg("New User: $line\n", 1);
         }
         if ($line !~ /\/\/.*\$dbhost/ && $line !~ /#.*\$dbhost/ &&
             $line =~ /\$dbhost.*=/) { #If this is hostname config line,
             $self->logg("Old Host: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . "localhost" . $spconfig[2];
             $self->logg("New Host: $line\n", 1);
         }
     }
     untie @lines;
}


# ------------------------------------------------------------------------------
# ------------------------ concrete5 Subroutines ------------------------------
# ------------------------------------------------------------------------------
# Sample concrete5 site.php config:
#define('DB_SERVER', 'localhost');
#define('DB_USERNAME', 'mss001_cncr16');
#define('DB_PASSWORD', 'FKRIGH493dk');
#define('DB_DATABASE', 'mss001_cncr16');

#Extract information out of a concrete5 config file.
#Input: concrete5 config file path/name.
#Output: An array with the hostname, database name, db username, and password in that order.
sub extract_db_concrete5 {
     my $self    = shift;
     my $filenam = $_[0];
     my $host = "";             #Initialize the variables.
     my $db   = "";
     my $user = "";
     my $pass = "";
     my $line = "";
     open (INFILE, $filenam); 
     while ($line = <INFILE>) {
          if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /DB_DATABASE/) { #If this is db config line,
             $db = $line;                               #Extract the db name.
             $db =~ s/'\);.*//;
             $db =~ s/.*'//;
             $db =~ s/\n//;
             $db =~ s/\r//;
         }
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /DB_USERNAME/) { #If this is the username config line,
             $user = $line;                             #Extract it.
             $user =~ s/'\);.*//;
             $user =~ s/.*'//;
             $user =~ s/\n//;
             $user =~ s/\r//;
         }
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /DB_SERVER/) { #If this is the host config line,
             $host = $line;                             #Extract it.
             $host =~ s/'\);.*//;
             $host =~ s/.*'//;
             $host =~ s/\n//;
             $host =~ s/\r//;
         }
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /DB_PASSWORD/) { #If this is the host config line,
             $pass = $line;                                 #Extract it.
             $pass =~ s/'\);.*//;
             $pass =~ s/.*'//;
             $pass =~ s/\n//;
             $pass =~ s/\r//;
         }
     }
     close INFILE;
     if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
     push (my @list, $host);
     push (@list, $db);
     push (@list, $user);
     push (@list, $pass);
     push (@list, "concrete5");
     return @list;     
}


# Update a concrete5 config file.
# Input: dbname, dbuser, configfile
# Ouput: Updated concrete5 configuration file.
sub update_db_concrete5 {
     my $self     = shift;
     my $dbname   = @_[0];
     my $username = @_[1];
     my $filenam  = @_[2];

     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;

     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /DB_DATABASE/) { #If this is db config line,
             $self->logg("Old DB: $line\n", 1);
             $line =~ s/',.*'.*'\);/', '$dbname');/;     #replace it with the new db name.
             $self->logg("New DB: $line\n", 1);
         }
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /DB_USERNAME/) { #If this is the username config line,
             $self->logg("Old User: $line\n", 1);
             $line =~ s/',.*'.*'\);/', '$username');/;     #replace it with the new user name.
             $self->logg("New User: $line\n", 1);
         }
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /DB_SERVER/) { #If this is the host config line,
             $self->logg("Old Host: $line\n", 1);
             $line =~ s/',.*'.*'\);/', 'localhost');/;     #replace it with the new host name.
             $self->logg("New Host: $line\n", 1);
         }
     }
     untie @lines;     
}

# ------------------------------------------------------------------------------
# -------------------------- PHP Weby Subroutines ------------------------------
# ------------------------------------------------------------------------------

#Extract information out of a PHP Weby config file.
#Input: PHP Weby config file path/name.
#Output: An array with the hostname, database name, db username, and password in that order.
sub extract_db_phpweby {
     my $self    = shift;
     my $filenam = $_[0];
     my $host = "";             #Initialize the variables.
     my $db   = "";
     my $user = "";
     my $pass = "";
     my $line = "";
     open (INFILE, $filenam);
     while ($line = <INFILE>) {
          if ($line !~ /^\/\// && $line !~ /^\/\*/ && $line !~ /^#/ && $line =~ /define.*DB_HOST/) { #If this is the host config line,
             $host = $line;                           #Extract the host name.
             $host =~ s/.*DB_HOST' *, *'//;           #Remove the part before the host name.
             $host =~ s/ *'.*//;                      #Remove the part after the host name.
             $host =~ s/\n//;
             $host =~ s/\r//;
         }
         if ($line !~ /^\/\// && $line !~ /^\/\*/ && $line !~ /^#/ && $line =~ /define.*DB_USER/) {  #If this is the username config line,
             $user = $line;                           #Extract the database user.
             $user =~ s/.*DB_USER' *, *'//;           #Remove the part before the username.
             $user =~ s/ *'.*//;                      #Remove the part after the username.
             $user =~ s/\n//;
             $user =~ s/\r//;
         }
         if ($line !~ /^\/\// && $line !~ /^\/\*/ && $line !~ /^#/ && $line =~ /define.*DB_PASS/) {  #If this is the password config line,
             $pass = $line;                           #Extract the password.
             $pass =~ s/.*DB_PASS' *, *'//;           #Remove the part before the password.
             $pass =~ s/ *'.*//;                      #Remove the part after the password.
             $pass =~ s/\n//;
             $pass =~ s/\r//;
         }
         if ($line !~ /^\/\// && $line !~ /^\/\*/ && $line !~ /^#/ && $line =~ /define.*DB_DB/) {  #If this is the database config line,
             $db = $line;                             #Extract the database name.
             $db =~ s/.*DB_DB' *, *'//;               #Remove the part before the database name.
             $db =~ s/ *'.*//;                        #Remove the part after the database name.
             $db =~ s/\n//;
             $db =~ s/\r//;
         }
     }
     close INFILE;
     if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
     push (my @list, $host);
     push (@list, $db);
     push (@list, $user);
     push (@list, $pass);
     push (@list, "PHP Weby");
     return @list;
}

# Update a PHP Weby config file.
# Input: dbname, dbuser, configfile
# Ouput: Updated PHP Weby configuration file.
sub update_db_phpweby {
     my $self     = shift;
     my $dbname   = @_[0];
     my $username = @_[1];
     my $filenam  = @_[2];
     my $left;              #Represents everything in a line of text to the left  of what we are replacing.
     my $right;             #Represents everything in a line of text to the right of what we are replacing.
     my $temp;              #Throw away variable used when finding parts of a line before and after the target to replace.
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;
     
     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /^\/\// && $line !~ /^\/\*/ && $line !~ /^#/ && $line =~ /define.*DB_HOST/) { #If this is the host config line,
             $temp   =  $line;
             $temp   =~ s/.*DB_HOST' *, *'//;               #Drop everything to the left of the host name.
             $left   =  $&;                                 #Save the dropped part.
             $temp   =~ s/ *'.*//;                          #Remove everything after the host name.
             $right  =  $&;                                 #Save the dropped part.
             $line   =  $left . "localhost" . $right;
         }
         if ($line !~ /^\/\// && $line !~ /^\/\*/ && $line !~ /^#/ && $line =~ /define.*DB_USER/) { #If this is the host config line,
             $temp   =  $line;
             $temp   =~ s/.*DB_USER' *, *'//;               #Drop everything to the left of the host name.
             $left   =  $&;                                 #Save the dropped part.
             $temp   =~ s/ *'.*//;                          #Remove everything after the host name.
             $right  =  $&;                                 #Save the dropped part.
             $line   =  $left . $username . $right;
         }
         if ($line !~ /^\/\// && $line !~ /^\/\*/ && $line !~ /^#/ && $line =~ /define.*DB_DB/) { #If this is the host config line,
             $temp   =  $line;
             $temp   =~ s/.*DB_DB' *, *'//;                 #Drop everything to the left of the host name.
             $left   =  $&;                                 #Save the dropped part.
             $temp   =~ s/ *'.*//;                          #Remove everything after the host name.
             $right  =  $&;                                 #Save the dropped part.
             $line   =  $left . $dbname . $right;
         }
     }
     untie @lines;
}

# ------------------------------------------------------------------------------
# --------------------------- WHMCS Subroutines --------------------------------
# ------------------------------------------------------------------------------
#
#Extract database information out of a WHMCS config file.
#Input: WHMCS config file path/name.
#Output: An array with the hostname, database name, db username, and password in that order.
sub extract_db_whmcs {
     my $self = shift;
     my $filenam = $_[0];
     my $host = "";             #Initialize the variables.
     my $db   = "";
     my $user = "";
     my $pass = "";
     my $line = "";
     my @spconfig;
     open (INFILE, $filenam);
     while ($line = <INFILE>) {
         if ($line !~ /\/\/.*\$db_name/ && $line !~ /#.*\$db_name/ &&
             $line =~ /\$db_name.*=/) { #If this is db config line,
             @spconfig = splitconfigline($line);          #Extract the db name.
             $db = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$db_username/ && $line !~ /#.*\$db_username/ &&
             $line =~ /\$db_username.*=/) { #If this is db user config line,
             @spconfig = splitconfigline($line);          #Extract the db user name.
             $user = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$db_host/ && $line !~ /#.*\$db_host/ &&
             $line =~ /\$db_host.*=/) { #If this is hostname config line,
             @spconfig = splitconfigline($line);          #Extract the host name.
             $host = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$db_password/ && $line !~ /#.*\$db_password/ &&
             $line =~ /\$db_password.*=/) { #If this is password config line,
             @spconfig = splitconfigline($line);          #Extract the password.
             $pass = $spconfig[1];
         }
     }
     close INFILE;
     if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
     push (my @list, $host);
     push (@list, $db);
     push (@list, $user);
     push (@list, $pass);
     push (@list, "WHMCS");
     return @list;
}

# Update a WHMCS config file.
# Input: dbname, dbuser, configfile
# Ouput: Updated WHMCS configuration file.
sub update_db_whmcs {
     my $self     = shift;
     my $dbname   = @_[0];
     my $username = @_[1];
     my $filenam  = @_[2];
     my @spconfig;
     $self->logg("******\n", 1);
     $self->logg("****** Warning: Only database info. is updated.  Please manually check other settings in the WHMCS configuration file *******\n", 1);
     $self->logg("****** such as \$templates_compiledir, \$attachments_dir and \$downloads_dir                                             *******\n", 1);
     $self->logg("******\n", 1);
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;
     
     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\/.*\$db_name/ && $line !~ /#.*\$db_name/ &&
             $line =~ /\$db_name.*=/) { #If this is db config line,
             $self->logg("Old DB: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $dbname . $spconfig[2];
             $self->logg("New DB: $line\n", 1);
         }
         if ($line !~ /\/\/.*\$db_username/ && $line !~ /#.*\$db_username/ &&
             $line =~ /\$db_username.*=/) { #If this is db user config line,
             $self->logg("Old User: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $username . $spconfig[2];
             $self->logg("New User: $line\n", 1);
         }
         if ($line !~ /\/\/.*\$db_host/ && $line !~ /#.*\$db_host/ &&
             $line =~ /\$db_host.*=/) { #If this is hostname config line,
             $self->logg("Old Host: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . "localhost" . $spconfig[2];
             $self->logg("New Host: $line\n", 1);
         }
     }
     untie @lines;
}

# ------------------------------------------------------------------------------
# ---------------- Simple Machines Forum Subroutines ---------------------------
# ------------------------------------------------------------------------------
#
#Extract information out of a Simple Machines Forum config file.
#Input: Simple Machines Forum config file path/name.
#Output: An array with the hostname, database name, db username, and password in that order.
sub extract_db_smf {
     my $self = shift;
     my $filenam = $_[0];
     my $host = "";             #Initialize the variables.
     my $db   = "";
     my $user = "";
     my $pass = "";
     my $line = "";
     my @spconfig;
     open (INFILE, $filenam);
     while ($line = <INFILE>) {
         if ($line !~ /\/\/.*\$db_name/ && $line !~ /#.*\$db_name/ &&
             $line =~ /\$db_name.*=/) { #If this is db config line,
             @spconfig = splitconfigline($line);          #Extract the db name.
             $db = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$db_user/ && $line !~ /#.*\$db_user/ &&
             $line =~ /\$db_user.*=/) { #If this is db user config line,
             @spconfig = splitconfigline($line);          #Extract the db user name.
             $user = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$db_server/ && $line !~ /#.*\$db_server/ &&
             $line =~ /\$db_server.*=/) { #If this is hostname config line,
             @spconfig = splitconfigline($line);          #Extract the host name.
             $host = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$db_passwd/ && $line !~ /#.*\$db_passwd/ &&
             $line =~ /\$db_passwd.*=/) { #If this is password config line,
             @spconfig = splitconfigline($line);          #Extract the password.
             $pass = $spconfig[1];
         }
     }
     close INFILE;
     if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
     push (my @list, $host);
     push (@list, $db);
     push (@list, $user);
     push (@list, $pass);
     push (@list, "Simple Machines Forum");
     return @list;
}

# Update a Simple Machines Forum config file.
# Input: dbname, dbuser, configfile
# Ouput: Updated Simple Machines Forum configuration file.
sub update_db_smf {
     my $self     = shift;
     my $dbname   = @_[0];
     my $username = @_[1];
     my $filenam  = @_[2];
     my @spconfig;
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;
     
     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\/.*\$db_name/ && $line !~ /#.*\$db_name/ &&
             $line =~ /\$db_name.*=/) { #If this is db config line,
             $self->logg("Old DB: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $dbname . $spconfig[2];
             $self->logg("New DB: $line\n", 1);
         }
         if ($line !~ /\/\/.*\$db_user/ && $line !~ /#.*\$db_user/ &&
             $line =~ /\$db_user.*=/) { #If this is db user config line,
             $self->logg("Old User: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $username . $spconfig[2];
             $self->logg("New User: $line\n", 1);
         }
         if ($line !~ /\/\/.*\$db_server/ && $line !~ /#.*\$db_server/ &&
             $line =~ /\$db_server.*=/) { #If this is hostname config line,
             $self->logg("Old Host: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . "localhost" . $spconfig[2];
             $self->logg("New Host: $line\n", 1);
         }
     }
     untie @lines;
}

# Update the path config lines in a Simple Machines Forum config file.
# Input: Configuration file
# Output: $boarddir and $sourcedir lines will be updated with the new path.
#         Will also confirm that the "Sources directory exists in the new path where we expect it.
sub update_path_smf {
     my $self     = shift;
     my $filenam  = $_[0];
     my @spconfig;
     my $newsrcpath;
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;
     my $dirpath = finddirpath($filenam);
     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\/.*\$boarddir/ && $line !~ /#.*\$boarddir/ &&
             $line !~ /__FILE__/ && $line !~ /\$sourcedir = \$boarddir/ &&
             $line =~ /\$boarddir.*=/) { #If this is boarddir config line,
              $self->logg("Old boarddir path: $line\n", 1);
              @spconfig = splitconfigline($line);
              $line = $spconfig[0] . $dirpath . $spconfig[2];
              $self->logg("New boarddir path: $line\n", 1);
         }
         if ($line !~ /\/\/.*\$sourcedir/ && $line !~ /#.*\$sourcedir/ &&
             $line !~ /__FILE__/ && $line !~ /\$sourcedir = \$boarddir/ &&
             $line =~ /\$sourcedir.*=/) { #If this is sourcedir config line,
              $self->logg("Old Sources dir path: $line\n", 1);
              @spconfig = splitconfigline($line);
              $newsrcpath = $dirpath . "/Sources";
              if (-d $newsrcpath) {
                   $line = $spconfig[0] . $newsrcpath . $spconfig[2]; #Update line in the file since the dir exists.
                   $self->logg("New Sources dir path: $line\n", 1);
              }else {
                   $self->logg("$newsrcpath does not exist.  Update Sources dir path manually.\n", 1);
              }
         }
     }
     untie @lines;
}

# ------------------------------------------------------------------------------
# ------------------------ Drupal 7 Subroutines  ---------------------------------
# ------------------------------------------------------------------------------
#
# Sample Drupal 7 settings.php config:
#$databases = array (
#  'default' =>
#  array (
#    'default' =>
#    array (
#      'database' => 'mss001_drpl1',
#      'username' => 'mss001_drpl1',
#      'password' => 'V2SUOBt99w1I9aJ4',
#      'host' => 'localhost',
#      'port' => '',
#      'driver' => 'mysql',
#      'prefix' => 'drpl_',
#    ),
#  ),
#);
#Extract information out of a Drupal 7 config file.
#Input: Drupal 7 config file path/name.
#Output: An array with the hostname, database name, db username, and password in that order.
sub extract_db_drupal7 {
     my $self = shift;
     my $filenam = $_[0];
     my $host = "";             #Initialize the variables.
     my $db   = "";
     my $user = "";
     my $pass = "";
     my $line = "";
     my @spconfig;
     open (INFILE, $filenam);
     while ($line = <INFILE>) {
         if ($line !~ /\/\/.*database/ && $line !~ /#.*database/ && length($db) == 0 &&
             $line !~ /\*.*database/ && $line =~ /'\s*database\s*'\s*=>/) { #If this is db config line,
             @spconfig = splitconfigline($line);          #Extract the db name.
             $db = $spconfig[1];
         }
         if ($line !~ /\/\/.*username/ && $line !~ /#.*username/ && length($user) == 0 &&
             $line !~ /\*.*username/ && $line =~ /'\s*username\s*'\s*=>/) { #If this is db user config line,
             @spconfig = splitconfigline($line);          #Extract the db user name.
             $user = $spconfig[1];
         }
         if ($line !~ /\/\/.*host/ && $line !~ /#.*host/ && length($host) == 0 &&
             $line !~ /\*.*host/ && $line =~ /'\s*host\s*'\s*=>/) { #If this is the hostname config line,
             @spconfig = splitconfigline($line);          #Extract the host name.
             $host = $spconfig[1];
         }
         if ($line !~ /\/\/.*password/ && $line !~ /#.*password/ && length($pass) == 0 &&
             $line !~ /\*.*password/ && $line =~ /'\s*password\s*'\s*=>/) { #If this is the password config line,
             @spconfig = splitconfigline($line);          #Extract the password.
             $pass = $spconfig[1];
         }
     }
     close INFILE;
     if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
     push (my @list, $host);
     push (@list, $db);
     push (@list, $user);
     push (@list, $pass);
     push (@list, "Drupal 7");
     return @list;
}

# Update a Drupal 7 config file.
# Input: dbname, dbuser, configfile
# Ouput: Updated Drupal 7 configuration file.
sub update_db_drupal7 {
     my $self     = shift;
     my $dbname   = @_[0];
     my $username = @_[1];
     my $filenam  = @_[2];
     my @spconfig;
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;
     
     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\/.*database/ && $line !~ /#.*database/ &&
             $line !~ /\*.*database/ && $line =~ /database.*=>/) { #If this is db config line,
             $self->logg("Old DB: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $dbname . $spconfig[2];
             $self->logg("New DB: $line\n", 1);
         }
         if ($line !~ /\/\/.*username/ && $line !~ /#.*username/ &&
             $line !~ /\*.*username/ && $line =~ /username.*=>/) { #If this is db user config line,
             $self->logg("Old User: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $username . $spconfig[2];
             $self->logg("New User: $line\n", 1);
         }
         if ($line !~ /\/\/.*host/ && $line !~ /#.*host/ &&
             $line !~ /\*.*host/ && $line =~ /host.*=>/) { #If this is the hostname config line,
             $self->logg("Old Host: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . "localhost" . $spconfig[2];
             $self->logg("New Host: $line\n", 1);
         }
     }
     untie @lines;
}


# ------------------------------------------------------------------------------
# ------------------ Drupal Subroutines for versions < 7 -----------------------
# ------------------------------------------------------------------------------
#Extract information out of a Drupal config file.
#Input: Drupal config file path/name.
#Output: An array with the hostname, database name, db username, and password in that order.
sub extract_db_drupal {
     my $self    = shift;
     my $filenam = $_[0];
     my $host = "";             #Initialize the variables.
     my $db   = "";
     my $user = "";
     my $pass = "";
     my $line = "";
     my @spconfig;
     open (INFILE, $filenam);
     while ($line = <INFILE>) {
         if ($line !~ /\/\/.*\$db_url/ && $line !~ /#.*\$db_url/ &&
             $line !~ /\*.*\$db_url/   && $line =~ /\$db_url.*=/) { #If this is db config line,
              $line =~ s/\n//;
              $line =~ s/\r//;
              $host = $line;
              $host =~ s/.*\@//;
              $host =~ s/\/.*//;
              $db   = $line;
              $db   =~ s/.*\///;
              $db   =~ s/'.*//;
              $user = $line;
              $user =~ s/.*:\/\///;
              $user =~ s/:.*//;
              $pass = $line;
              $pass =~ s/.*$user://;
              $pass =~ s/\@.*//;
         }
     }
     close INFILE;
     if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
     $pass = uri_unescape($pass);
     push (my @list, $host);
     push (@list, $db);
     push (@list, $user);
     push (@list, $pass);
     push (@list, "Drupal");
     return @list;
}

# Update a Drupal config file.
# The config line we're working on is like this:
#   $db_url = 'mysqli://username:password@localhost/databasename';
# Input: dbname, dbuser, configfile
# Ouput: Updated Drupal configuration file.
sub update_db_drupal {
     my $self     = shift;
     my $dbname   = @_[0];
     my $username = @_[1];
     my $filenam  = @_[2];
     my $pass = "";
     my $temp = "";   
     my $startofline = "";
     my $endofline   = "";
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;
     
     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\/.*\$db_url/ && $line !~ /#.*\$db_url/ &&
             $line !~ /\*.*\$db_url/   && $line =~ /\$db_url.*=/) { #If this is db config line,
              $self->logg("Old config line: $line\n", 1);
              $temp = $line;
              $temp =~ s/\n//;
              $temp =~ s/\r//;
              $pass = $temp;
              $pass =~ s/.*://;
              $pass =~ s/\@.*//;
              $startofline = $temp;
              $startofline =~ s/:\/\/.*/:\/\//;
              $endofline   = $line;
              $endofline   =~ s/.*'/'/;
              $line = $startofline . $username . ":" . $pass . "\@localhost/" . $dbname . $endofline;
              $self->logg("New config line: $line\n", 1);
         }
     }
     untie @lines;
}

# ------------------------------------------------------------------------------
# --------------------------- Magento Subroutines --------------------------------
# ------------------------------------------------------------------------------
#Extract information out of a Magento config file.
#Input: Magento config file path/name.
#Output: An array with the hostname, database name, db username, and password in that order.
sub extract_db_magento {
     my $self    = shift;
     my $filenam = $_[0];
     my $host = "";             #Initialize the variables.
     my $db   = "";
     my $user = "";
     my $pass = "";
     my $line = "";
     open (INFILE, $filenam);
     while ($line = <INFILE>) {
         if ($line =~ /<dbname><\!\[CDATA\[/) { #If this is db config line,
             $db = $line;                               #Extract the db name.
             $db =~ s/.*CDATA\[//;
             $db =~ s/\].*//;
             $db =~ s/\n//;
             $db =~ s/\r//;
         }
         if ($line =~ /<username><\!\[CDATA\[/) { #If this is db userconfig line,
             $user = $line;                               #Extract the db user name.
             $user =~ s/.*CDATA\[//;
             $user =~ s/\].*//;
             $user =~ s/\n//;
             $user =~ s/\r//;
         }
         if ($line =~ /<host><\!\[CDATA\[/) { #If this is hostname config line,
             $host = $line;                               #Extract the host name.
             $host =~ s/.*CDATA\[//;
             $host =~ s/\].*//;
             $host =~ s/\n//;
             $host =~ s/\r//;
         }
         if ($line =~ /<password><\!\[CDATA\[/) { #If this is password config line,
             $pass = $line;                               #Extract the password.
             $pass =~ s/.*CDATA\[//;
             $pass =~ s/\].*//;
             $pass =~ s/\n//;
             $pass =~ s/\r//;
         }
     }
     close INFILE;
     if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
     push (my @list, $host);
     push (@list, $db);
     push (@list, $user);
     push (@list, $pass);
     push (@list, "Magento");
     return @list;
}

sub extract_db_magento20 {
     my $self    = shift;
     my $filenam = $_[0];
     my $host = "";             #Initialize the variables.
     my $db   = "";
     my $user = "";
     my $pass = "";
     my $line = "";
     open (INFILE, $filenam);
     while ($line = <INFILE>) {
         if ($line =~ /host/) {
             $host = $line;
             $host =~ s/.*\'host\' \=\> \'//;
             $host =~ s/\',\n//;
         }
         if ($line =~ /dbname/) {
             $db = $line;
             $db =~ s/.*\'dbname\' \=\> \'//;
             $db =~ s/\',\n//;
         }
         if ($line =~ /username/) {
             $user = $line;
             $user =~ s/.*\'username\' \=\> \'//;
             $user =~ s/\',\n//;
         }
         if ($line =~ /password/) {
             $pass = $line;
             $pass =~ s/.*\'password\' \=\> \'//;
             $pass =~ s/\',\n//;
         }
     }
     close INFILE;
     if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
     push (my @list, $host);
     push (@list, $db);
     push (@list, $user);
     push (@list, $pass);
     push (@list, "Magento2.0");
     return @list;
}

# Update a Magento config file.
# Input: dbname, dbuser, configfile
# Ouput: Updated Magento configuration file.
sub update_db_magento {
     my $self     = shift;
     my $dbname   = @_[0];
     my $username = @_[1];
     my $filenam  = @_[2];
     
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;
     
     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line =~ /<dbname><\!\[CDATA\[/) { #If this is db config line,
             $self->logg("Old DB: $line\n", 1);
             $line =~ s/CDATA\[.*\]\]/CDATA\[$dbname\]\]/;                 #replace it with the new db name.
             $self->logg("New DB: $line\n", 1);
         }
         if ($line =~ /<username><\!\[CDATA\[/) { #If this is db userconfig line,
             $self->logg("Old User: $line\n", 1);
             $line =~ s/CDATA\[.*\]\]/CDATA\[$username\]\]/;                #replace it with the new user name.
             $self->logg("New User: $line\n", 1);
         }
         if ($line =~ /<host><\!\[CDATA\[/) { #If this is hostname config line,
             $self->logg("Old Host: $line\n", 1);
             $line =~ s/CDATA\[.*\]\]/CDATA\[localhost\]\]/;              #replace it with the new host name.
             $self->logg("New Host: $line\n", 1);
         }
     }
     untie @lines;
}

sub update_db_magento20 {
     my $self     = shift;
     my $dbname   = @_[0];
     my $username = @_[1];
     my $filenam  = @_[2];
     
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;

     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line =~ /dbname/) {
             $self->logg("Old DB:$line\n", 1);
             $line =~ s/dbname.*/dbname\' \=\> \'$dbname\',/;
             $self->logg("New DB: $line\n", 1);
         }
         if ($line =~ /username/) {
             $self->logg("Old User:$line\n", 1);
             $line =~ s/username.*/username\' \=\> \'$username\',/;
             $self->logg("New User: $line\n", 1);
         }
         if ($line =~ /host/) {
             $self->logg("Old Host:$line\n", 1);
             $line =~ s/host.*/host\' \=\> \'localhost',/;
             $self->logg("New Host: $line\n", 1);
         }
     }
     untie @lines;
}

# ------------------------------------------------------------------------------
# --------------------------- phpBB Subroutines --------------------------------
# ------------------------------------------------------------------------------
#Extract information out of a phpBB config file.
#Input: phpBB config file path/name.
#Output: An array with the hostname, database name, db username, and password in that order.
sub extract_db_phpbb {
     my $self    = shift;
     my $filenam = $_[0];
     my $host = "";             #Initialize the variables.
     my $db   = "";
     my $user = "";
     my $pass = "";
     my $line = "";
     my @spconfig;
     open (INFILE, $filenam);
     while ($line = <INFILE>) {
         if ($line !~ /\/\/.*\$dbname/ && $line !~ /#.*\$dbname/ &&
             $line =~ /\$dbname.*=/) { #If this is db config line,
             @spconfig = splitconfigline($line);          #Extract the db name.
             $db = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$dbuser/ && $line !~ /#.*\$dbuser/ &&
             $line =~ /\$dbuser.*=/) { #If this is db user config line,
             @spconfig = splitconfigline($line);          #Extract the db user name.
             $user = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$dbhost/ && $line !~ /#.*\$dbhost/ &&
             $line =~ /\$dbhost.*=/) { #If this is hostname config line,
             @spconfig = splitconfigline($line);          #Extract the host name.
             $host = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$dbpasswd/ && $line !~ /#.*\$dbpasswd/ &&
             $line =~ /\$dbpasswd.*=/) { #If this is password config line,
             @spconfig = splitconfigline($line);          #Extract the password.
             $pass = $spconfig[1];
         }
     }
     close INFILE;
     if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
     push (my @list, $host);
     push (@list, $db);
     push (@list, $user);
     push (@list, $pass);
     push (@list, "phpBB");
     return @list;
}

# Update a phpBB config file.
# Input: dbname, dbuser, configfile
# Ouput: Updated phpBB configuration file.
sub update_db_phpbb {
     my $self     = shift;
     my $dbname   = @_[0];
     my $username = @_[1];
     my $filenam  = @_[2];
     my @spconfig; 
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;
     
     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\/.*\$dbname/ && $line !~ /#.*\$dbname/ &&
             $line =~ /\$dbname.*=/) { #If this is db config line,
             $self->logg("Old DB: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $dbname . $spconfig[2];
             $self->logg("New DB: $line\n", 1);
         }
         if ($line !~ /\/\/.*\$dbuser/ && $line !~ /#.*\$dbuser/ &&
             $line =~ /\$dbuser.*=/) { #If this is db user config line,
             $self->logg("Old User: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $username . $spconfig[2];
             $self->logg("New User: $line\n", 1);
         }
         if ($line !~ /\/\/.*\$dbhost/ && $line !~ /#.*\$dbhost/ &&
             $line =~ /\$dbhost.*=/) { #If this is hostname config line,
             $self->logg("Old Host: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . "localhost" . $spconfig[2];
             $self->logg("New Host: $line\n", 1);
         }
     }
     untie @lines;
}

# ------------------------------------------------------------------------------
# --------------------------- Gallery Subroutines --------------------------------
# ------------------------------------------------------------------------------
#Extract information out of a Gallery config file (config.php in root of installation).
#Input: Gallery config file path/name.
#Output: An array with the hostname, database name, db username, and password in that order.
sub extract_db_gallery {
     my $self    = shift;
     my $filenam = $_[0];
     my $host = "";             #Initialize the variables.
     my $db   = "";
     my $user = "";
     my $pass = "";
     my $line = "";
     my @spconfig;
     open (INFILE, $filenam);
     while ($line = <INFILE>) {
         if ($line !~ /\/\/.*\$storeConfig.*database/ && $line !~ /#.*\$storeConfig.*database/ &&
             $line =~ /\$storeConfig.*database.*=/) { #If this is db config line,
             @spconfig = splitconfigline($line);          #Extract the db name.
             $db = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$storeConfig.*username/ && $line !~ /#.*\$storeConfig.*username/ &&
             $line =~ /\$storeConfig.*username.*=/) { #If this is db user config line,
             @spconfig = splitconfigline($line);          #Extract the db user name.
             $user = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$storeConfig.*hostname/ && $line !~ /#.*\$storeConfig.*hostname/ &&
             $line =~ /\$storeConfig.*hostname.*=/) { #If this is the hostname user config line,
             @spconfig = splitconfigline($line);          #Extract the host name.
             $host = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$storeConfig.*password/ && $line !~ /#.*\$storeConfig.*password/ &&
             $line =~ /\$storeConfig.*password.*=/) { #If this is password config line,
             @spconfig = splitconfigline($line);          #Extract the password.
             $pass = $spconfig[1];
         }
     }
     close INFILE;
     if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
     push (my @list, $host);
     push (@list, $db);
     push (@list, $user);
     push (@list, $pass);
     push (@list, "Gallery");
     return @list;
}

# Update a Gallery config file.
# Input: dbname, dbuser, configfile
# Ouput: Updated Gallery configuration file.
sub update_db_gallery {
     my $self     = shift;
     my $dbname   = @_[0];
     my $username = @_[1];
     my $filenam  = @_[2];
     my @spconfig; 
     $self->logg("******\n", 1);
     $self->logg("****** Warning: Check the data.gallery.base file path in $filenam *******\n", 1);
     $self->logg("******\n", 1);
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;
     
     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\/.*\$storeConfig.*database/ && $line !~ /#.*\$storeConfig.*database/ &&
             $line =~ /\$storeConfig.*database.*=/) { #If this is db config line,
             $self->logg("Old DB: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $dbname . $spconfig[2];
             $self->logg("New DB: $line\n", 1);
         }
         if ($line !~ /\/\/.*\$storeConfig.*username/ && $line !~ /#.*\$storeConfig.*username/ &&
             $line =~ /\$storeConfig.*username.*=/) { #If this is db user config line,
             $self->logg("Old User: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $username . $spconfig[2];
             $self->logg("New User: $line\n", 1);
         }
         if ($line !~ /\/\/.*\$storeConfig.*hostname/ && $line !~ /#.*\$storeConfig.*hostname/ &&
             $line =~ /\$storeConfig.*hostname.*=/) { #If this is the hostname user config line,
             $self->logg("Old Host: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . "localhost" . $spconfig[2];
             $self->logg("New Host: $line\n", 1);
         }
     }
     untie @lines;
}

# ------------------------------------------------------------------------------
# --------------------------- vBulletin Subroutines --------------------------------
# ------------------------------------------------------------------------------
#Extract information out of a vBulletin config file.
#Input: vBulletin config file path/name.
#Output: An array with the hostname, database name, db username, and password in that order.
sub extract_db_vb {
     my $self    = shift;
     my $filenam = $_[0];
     my $host = "";             #Initialize the variables.
     my $db   = "";
     my $user = "";
     my $pass = "";
     my $line = "";
     my @spconfig;
     open (INFILE, $filenam);
     while ($line = <INFILE>) {
         if ($line !~ /\/\/.*\$config.*Database.*dbname/ && $line !~ /#.*\$config.*Database.*dbname/ &&
             $line =~ /\$config.*Database.*dbname.*=/) { #If this is db config line,
             @spconfig = splitconfigline($line);          #Extract the db name.
             $db = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$config.*MasterServer.*username/ &&
             $line !~ /#.*\$config.*MasterServer.*username/ &&
             $line =~ /\$config.*MasterServer.*username.*=/) { #If this is db user config line,
             @spconfig = splitconfigline($line);          #Extract the db user name.
             $user = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$config.*MasterServer.*servername/ &&
             $line !~ /#.*\$config.*MasterServer.*servername/ &&
             $line =~ /\$config.*MasterServer.*servername.*=/) { #If this is hostname config line,
             @spconfig = splitconfigline($line);          #Extract the host name.
             $host = $spconfig[1];
         }
         if ($line !~ /\/\/.*\$config.*MasterServer.*password/ &&
             $line !~ /#.*\$config.*MasterServer.*password/ &&
             $line =~ /\$config.*MasterServer.*password.*=/) { #If this is password config line,
             @spconfig = splitconfigline($line);          #Extract the password.
             $pass = $spconfig[1];
         }
     }
     close INFILE;
     if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
     push (my @list, $host);
     push (@list, $db);
     push (@list, $user);
     push (@list, $pass);
     push (@list, "vBulletin");
     return @list;
}

# Update a vBulletin config file.
# Input: dbname, dbuser, configfile
# Ouput: Updated vBulletin configuration file.
sub update_db_vb {
     my $self     = shift;
     my $dbname   = @_[0];
     my $username = @_[1];
     my $filenam  = @_[2];
     my @spconfig; 
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;
     
     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\/.*\$config.*Database.*dbname/ && $line !~ /#.*\$config.*Database.*dbname/ &&
             $line =~ /\$config.*Database.*dbname.*=/) { #If this is db config line,
             $self->logg("Old DB: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $dbname . $spconfig[2];
             $self->logg("New DB: $line\n", 1);
         }
         if ($line !~ /\/\/.*\$config.*MasterServer.*username/ &&
             $line !~ /#.*\$config.*MasterServer.*username/ &&
             $line =~ /\$config.*MasterServer.*username.*=/) { #If this is db user config line,
             $self->logg("Old User: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . $username . $spconfig[2];
             $self->logg("New User: $line\n", 1);
         }
         if ($line !~ /\/\/.*\$config.*MasterServer.*servername/ &&
             $line !~ /#.*\$config.*MasterServer.*servername/ &&
             $line =~ /\$config.*MasterServer.*servername.*=/) { #If this is hostname config line,
             $self->logg("Old Host: $line\n", 1);
             @spconfig = splitconfigline($line);
             $line = $spconfig[0] . "localhost" . $spconfig[2];
             $self->logg("New Host: $line\n", 1);
         }
     }
     untie @lines;
}

# ------------------------------------------------------------------------------
# --------------------------- Joomla! 1.0 Subroutines ------------------------------
# ------------------------------------------------------------------------------
#Extract information out of a Joomla! config file.
#Input: Joomla! config file path/name.
#Output: An array with the hostname, database name, db username, and password in that order.
sub extract_db_joom10 {
     my $self    = shift;
     my $filenam = $_[0];
     my $host = "";             #Initialize the variables.
     my $db   = "";
     my $user = "";
     my $pass = "";
     my $line = "";
     open (INFILE, $filenam);
     while ($line = <INFILE>) {
         if ($line !~ /\/\*.*mosConfig_/ && $line !~ /#.*mosConfig_/ && $line !~ /\/\/.*mosConfig_/ &&
             $line =~ /mosConfig_db/ && $line !~ /mosConfig_dbprefix/) { #If db config line,
             $db = $line;                               #Extract the db name.
             $db =~ s/.*?'//;
             $db =~ s/'.*//;
             $db =~ s/\n//;
             $db =~ s/\r//;
         }
         if ($line !~ /\/\*.*mosConfig_/ && $line !~ /#.*mosConfig_/ && $line !~ /\/\/.*mosConfig_/ &&
             $line =~ /mosConfig_user/ && $line !~ /mosConfig_useractivation/) { #If user config line,
             $user = $line;                             #Extract it.
             $user =~ s/.*?'//;
             $user =~ s/'.*//;
             $user =~ s/\n//;
             $user =~ s/\r//;
         }
         if ($line !~ /\/\*.*mosConfig_/ && $line !~ /#.*mosConfig_/ && $line !~ /\/\/.*mosConfig_/ &&
             $line =~ /mosConfig_host/) { #If host config line,
             $host = $line;                             #Extract it.
             $host =~ s/.*?'//;
             $host =~ s/'.*//;
             $host =~ s/\n//;
             $host =~ s/\r//;
         }
         if ($line !~ /\/\*.*mosConfig_/ && $line !~ /#.*mosConfig_/ && $line !~ /\/\/.*mosConfig_/ &&
             $line =~ /mosConfig_password/) { #If password config line,
             $pass = $line;                                 #Extract it.
             $pass =~ s/.*?'//;
             $pass =~ s/'.*//;
             $pass =~ s/\n//;
             $pass =~ s/\r//;
         }
     }
     close INFILE;
     if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
     push (my @list, $host);
     push (@list, $db);
     push (@list, $user);
     push (@list, $pass);
     push (@list, "Joomla! 1.0");
     return @list;
}

# # Update database entries in the Joomla! config file.
# Input: dbname, dbuser, configfile
#Ouput: Updated Joomla! configuration file.
sub update_db_joom10 {
     my $self     = shift;
     my $dbname   = @_[0];
     my $username = @_[1];
     my $filenam  = @_[2];

     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;

     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\*.*mosConfig_/ && $line !~ /#.*mosConfig_/ && $line !~ /\/\/.*mosConfig_/ &&
             $line =~ /mosConfig_db/ && $line !~ /mosConfig_dbprefix/) { #If db config line,
             $self->logg("Old DB: $line\n", 1);
             $line =~ s/'.*'/'$dbname'/;     #replace it with the new db name.
             $self->logg("New DB: $line\n", 1);
         }
         if ($line !~ /\/\*.*mosConfig_/ && $line !~ /#.*mosConfig_/ && $line !~ /\/\/.*mosConfig_/ &&
             $line =~ /mosConfig_user/ && $line !~ /mosConfig_useractivation/) { #If user config line,
             $self->logg("Old User: $line\n", 1);
             $line =~ s/'.*'/'$username'/;     #replace it with the new db username.
             $self->logg("New User: $line\n", 1);
         }
         if ($line !~ /\/\*.*mosConfig_/ && $line !~ /#.*mosConfig_/ && $line !~ /\/\/.*mosConfig_/ &&
             $line =~ /mosConfig_host/) { #If host config line,
             $self->logg("Old hostname: $line\n", 1);
             $line =~ s/'.*'/'localhost'/;     #replace it with localhost.
             $self->logg("New hostname: $line\n", 1);
         }
     }
     untie @lines;
}

# $mosConfig_absolute_path = '/home/mstreete/public_html';
# $mosConfig_cachepath = '/home/mstreete/public_html/cache';
# Update the path config lines in a Joomla! config file.
# Input: Configuration file
# Output: $mosConfig_absolute_path and $mosConfig_cachepath lines will be updated with the new path.
#         Will also confirm that the directories exist in the new path where we expect them.
sub update_path_joom10 {
     my $self     = shift;
     my $filenam  = $_[0];
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;
     my $dirpath = finddirpath($filenam);
     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\*.*mosConfig_absolute_path/ && $line !~ /#.*mosConfig_absolute_path/ &&
             $line !~ /\/\/.*mosConfig_absolute_path/ &&
             $line =~ /\$mosConfig_absolute_path/) {   #If we're at the mosConfig_absolute_path line...
             $self->logg("Old mosConfig_absolute_path: $line\n", 1);
             my $configline = $line;                    #Work with a temp variable $configline
             $configline =~ s/'.*'/'$dirpath'/;    #Update the config line with the new path.
             my $newabspath = $configline;
             $newabspath =~ s/';//;                  #Remove all but the config path so we can
             $newabspath =~ s/.*'//;                 # see if the directory exists.
             if (-d $newabspath) {
                  $line = $configline;               #Update the line in the file since the dir exists.
             }else {
                  $self->logg("$newabspath does not exist.  Update mosConfig_absolute_path manually.\n", 1);
             }
             $self->logg("New mosConfig_absolute_path: $line\n", 1);
         }
         if ($line !~ /\/\*.*mosConfig_cachepath/ && $line !~ /#.*mosConfig_cachepath/ &&
             $line !~ /\/\/.*mosConfig_cachepath/ &&
             $line =~ /\$mosConfig_cachepath/) {           #If we're at the tmp_path line...
             $self->logg("Old mosConfig_cachepath: $line\n", 1);
             my $configline = $line;                    #Work with a temp variable $configline
             $configline =~ s/'.*\//'$dirpath\//;    #Update the config line with the new path.
             my $newcachepath = $configline;
             $newcachepath =~ s/';//;                  #Remove all but the config path so we can
             $newcachepath =~ s/.*'//;                 # see if the directory exists.
             if (-d $newcachepath) {
                  $line = $configline;               #Update the line in the file since the dir exists.
                  $self->logg("New mosConfig_cachepath: $line\n", 1);
             }else {
                  $self->logg("$newcachepath does not exist.  Update mosConfig_cachepath manually.\n", 1);
             }
         }
     }
     untie @lines;
}


# ------------------------------------------------------------------------------
# --------------------------- Joomla! 1.5 Subroutines ------------------------------
# ------------------------------------------------------------------------------
#Extract information out of a Joomla! config file.
#Input: Joomla! config file path/name.
#Output: An array with the hostname, database name, db username, and password in that order.
sub extract_db_joom15 {
     my $self     = shift;
     my $filenam = $_[0];
     my $host = "";             #Initialize the variables.
     my $db   = "";
     my $user = "";
     my $pass = "";
     my $line = "";
     open (INFILE, $filenam);
     while ($line = <INFILE>) {
         if ($line !~ /\/\*.*var/ && $line !~ /#.*var/ && $line !~ /\/\/.*var/ &&
             $line =~ /var.*\$db/ && $line !~ /var.*\$dbtype/ &&
             $line !~ /var.*\$dbprefix/) { #If db config line,
             $db = $line;                               #Extract the db name.
             $db =~ s/.*?'//;
             $db =~ s/'.*//;
             $db =~ s/\n//;
             $db =~ s/\r//;
         }
         if ($line !~ /\/\*.*var/ && $line !~ /#.*var/ && $line !~ /\/\/.*var/ &&
             $line =~ /var.*\$user/) { #If db user config line,
             $user = $line;                             #Extract it.
             $user =~ s/.*?'//;
             $user =~ s/'.*//;
             $user =~ s/\n//;
             $user =~ s/\r//;
         }
         if ($line !~ /\/\*.*var/ && $line !~ /#.*var/ && $line !~ /\/\/.*var/ &&
             $line =~ /var.*\$host/) { #If db host config line,
             $host = $line;                             #Extract it.
             $host =~ s/.*?'//;
             $host =~ s/'.*//;
             $host =~ s/\n//;
             $host =~ s/\r//;
         }
         if ($line !~ /\/\*.*var/ && $line !~ /#.*var/ && $line !~ /\/\/.*var/ &&
             $line =~ /var.*\$password/) { #If password config line,
             $pass = $line;                                 #Extract it.
             $pass =~ s/.*?'//;
             $pass =~ s/'.*//;
             $pass =~ s/\n//;
             $pass =~ s/\r//;
         }
     }
     close INFILE;
     if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
     push (my @list, $host);
     push (@list, $db);
     push (@list, $user);
     push (@list, $pass);
     push (@list, "Joomla! 1.5");
     return @list;
}


# # Update database entries in the Joomla! config file.
# Input: dbname, dbuser, configfile
#Ouput: Updated Joomla! configuration file.
sub update_db_joom15 {
     my $self     = shift;
     my $dbname   = @_[0];
     my $username = @_[1];
     my $filenam  = @_[2];
     
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;
     
     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\*.*var/ && $line !~ /#.*var/ && $line !~ /\/\/.*var/ &&
             $line =~ /var.*\$db/ && $line !~ /var.*\$dbtype/ &&
             $line !~ /var.*\$dbprefix/) { #If db config line,
             $self->logg("Old DB: $line\n", 1);
             $line =~ s/'.*'/'$dbname'/;     #replace it with the new db name.
             $self->logg("New DB: $line\n", 1);
         }
         if ($line !~ /\/\*.*var/ && $line !~ /#.*var/ && $line !~ /\/\/.*var/ &&
             $line =~ /var.*\$user/) { #If db user config line,
             $self->logg("Old User: $line\n", 1);
             $line =~ s/'.*'/'$username'/;     #replace it with the new db username.
             $self->logg("New User: $line\n", 1);
         }
         if ($line !~ /\/\*.*var/ && $line !~ /#.*var/ && $line !~ /\/\/.*var/ &&
             $line =~ /var.*\$host/) { #If db host config line,
             $self->logg("Old hostname: $line\n", 1);
             $line =~ s/'.*'/'localhost'/;     #replace it with localhost.
             $self->logg("New hostname: $line\n", 1);
         }
     }
     untie @lines;
}

# var $log_path = '/home/mstreete/public_html/joomla15/logs';
# var $tmp_path = '/home/mstreete/public_html/joomla15/tmp';
# Update the path config lines in a Joomla! config file.
# Input: Configuration file
# Output: $log_path and tmp_path lines will be updated with the new path.
#         Will also confirm that the directories exist in the new path where we expect them.
sub update_path_joom15 {
     my $self     = shift;
     my $filenam  = $_[0];
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;
     my $dirpath = finddirpath($filenam);
     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\*.*var/ && $line !~ /#.*var/ && $line !~ /\/\/.*var/ &&
             $line =~ /var.*\$log_path/) {           #If we're at the log_path line...
             $self->logg("Old log_path: $line\n", 1);
             my $configline = $line;                    #Work with a temp variable $configline
             $configline =~ s/'.*\//'$dirpath\//;    #Update the config line with the new path.
             my $newlogpath = $configline;
             $newlogpath =~ s/';//;                  #Remove all but the config path so we can
             $newlogpath =~ s/.*'//;                 # see if the directory exists.
             if (-d $newlogpath) {
                  $line = $configline;               #Update the line in the file since the dir exists.
             }else {
                  $self->logg("$newlogpath does not exist.  Update log_path manually.\n", 1);
             }
             $self->logg("New log_path: $line\n", 1);
         }
         if ($line !~ /\/\*.*var/ && $line !~ /#.*var/ && $line !~ /\/\/.*var/ &&
             $line =~ /var.*\$tmp_path/) {           #If we're at the tmp_path line...
             $self->logg("Old tmp_path: $line\n", 1);
             my $configline = $line;                    #Work with a temp variable $configline
             $configline =~ s/'.*\//'$dirpath\//;    #Update the config line with the new path.
             my $newlogpath = $configline;
             $newlogpath =~ s/';//;                  #Remove all but the config path so we can
             $newlogpath =~ s/.*'//;                 # see if the directory exists.
             if (-d $newlogpath) {
                  $line = $configline;               #Update the line in the file since the dir exists.
                  $self->logg("New tmp_path: $line\n", 1);
             }else {
                  $self->logg("$newlogpath does not exist.  Update tmp_path manually.\n", 1);
             }
         }
     }
     untie @lines;
}

# ------------------------------------------------------------------------------
# --------------------------- Joomla! 1.6 Subroutines ------------------------------
# ------------------------------------------------------------------------------
#Extract information out of a Joomla! config file.
#Input: Joomla! config file path/name.
#Output: An array with the hostname, database name, db username, and password in that order.
sub extract_db_joom16 {
     my $self    = shift;
     my $filenam = $_[0];
     my $host = "";             #Initialize the variables.
     my $db   = "";
     my $user = "";
     my $pass = "";
     my $line = "";
     open (INFILE, $filenam);
     while ($line = <INFILE>) {
         if ($line !~ /\/\*.*public/ && $line !~ /#.*public/ && $line !~ /\/\/.*public/ &&
             $line =~ /public.*\$db/ && $line !~ /public.*\$dbtype/ &&
             $line !~ /public.*\$dbprefix/) { #If db config line,
             $db = $line;                               #Extract the db name.
             $db =~ s/.*?'//;
             $db =~ s/'.*//;
             $db =~ s/\n//;
             $db =~ s/\r//;
         }
         if ($line !~ /\/\*.*public/ && $line !~ /#.*public/ && $line !~ /\/\/.*public/ &&
             $line =~ /public.*\$user/) { #If db user config line,
             $user = $line;                             #Extract it.
             $user =~ s/.*?'//;
             $user =~ s/'.*//;
             $user =~ s/\n//;
             $user =~ s/\r//;
         }
         if ($line !~ /\/\*.*public/ && $line !~ /#.*public/ && $line !~ /\/\/.*public/ &&
             $line =~ /public.*\$host/) { #If db host config line,
             $host = $line;                             #Extract it.
             $host =~ s/.*?'//;
             $host =~ s/'.*//;
             $host =~ s/\n//;
             $host =~ s/\r//;
         }
         if ($line !~ /\/\*.*public/ && $line !~ /#.*public/ && $line !~ /\/\/.*public/ &&
             $line =~ /public.*\$password/) { #If password config line,
             $pass = $line;                                 #Extract it.
             $pass =~ s/.*?'//;
             $pass =~ s/'.*//;
             $pass =~ s/\n//;
             $pass =~ s/\r//;
         }
     }
     close INFILE;
     if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
     push (my @list, $host);
     push (@list, $db);
     push (@list, $user);
     push (@list, $pass);
     push (@list, "Joomla! 1.6");
     return @list;
}


# # Update database entries in the Joomla! config file.
# Input: dbname, dbuser, configfile
#Ouput: Updated Joomla! configuration file.
sub update_db_joom16 {
     my $self     = shift;
     my $dbname   = @_[0];
     my $username = @_[1];
     my $filenam  = @_[2];
     
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;
     
     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\*.*public/ && $line !~ /#.*public/ && $line !~ /\/\/.*public/ &&
             $line =~ /public.*\$db/ && $line !~ /public.*\$dbtype/ &&
             $line !~ /public.*\$dbprefix/) { #If db config line,
             $self->logg("Old DB: $line\n", 1);
             $line =~ s/'.*'/'$dbname'/;     #replace it with the new db name.
             $self->logg("New DB: $line\n", 1);
         }
         if ($line !~ /\/\*.*public/ && $line !~ /#.*public/ && $line !~ /\/\/.*public/ &&
             $line =~ /public.*\$user/) { #If db user config line,
             $self->logg("Old User: $line\n", 1);
             $line =~ s/'.*'/'$username'/;     #replace it with the new db username.
             $self->logg("New User: $line\n", 1);
         }
         if ($line !~ /\/\*.*public/ && $line !~ /#.*public/ && $line !~ /\/\/.*public/ &&
             $line =~ /public.*\$host/) { #If db host config line,
             $self->logg("Old hostname: $line\n", 1);
             $line =~ s/'.*'/'localhost'/;     #replace it with localhost.
             $self->logg("New hostname: $line\n", 1);
         }
     }
     untie @lines;
}

# public $log_path = '/home/mstreete/public_html/joomla15/logs';
# public $tmp_path = '/home/mstreete/public_html/joomla15/tmp';
# Update the path config lines in a Joomla! config file.
# Input: Configuration file
# Output: $log_path and tmp_path lines will be updated with the new path.
#         Will also confirm that the directories exist in the new path where we expect them.
sub update_path_joom16 {
     my $self     = shift;
     my $filenam  = $_[0];
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;
     my $dirpath = finddirpath($filenam);
     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\*.*public/ && $line !~ /#.*public/ && $line !~ /\/\/.*public/ &&
             $line =~ /public.*\$log_path/) {           #If we're at the log_path line...
             $self->logg("Old log_path: $line\n", 1);
             my $configline = $line;                    #Work with a temp variable $configline
             $configline =~ s/'.*\//'$dirpath\//;    #Update the config line with the new path.
             my $newlogpath = $configline;
             $newlogpath =~ s/';//;                  #Remove all but the config path so we can
             $newlogpath =~ s/.*'//;                 # see if the directory exists.
             if (-d $newlogpath) {
                  $line = $configline;               #Update the line in the file since the dir exists.
             }else {
                  $self->logg("$newlogpath does not exist.  Update log_path manually.\n", 1);
             }
             $self->logg("New log_path: $line\n", 1);
         }
         if ($line !~ /\/\*.*public/ && $line !~ /#.*public/ && $line !~ /\/\/.*public/ &&
             $line =~ /public.*\$tmp_path/) {           #If we're at the tmp_path line...
             $self->logg("Old tmp_path: $line\n", 1);
             my $configline = $line;                    #Work with a temp variable $configline
             $configline =~ s/'.*\//'$dirpath\//;    #Update the config line with the new path.
             my $newlogpath = $configline;
             $newlogpath =~ s/';//;                  #Remove all but the config path so we can
             $newlogpath =~ s/.*'//;                 # see if the directory exists.
             if (-d $newlogpath) {
                  $line = $configline;               #Update the line in the file since the dir exists.
                  $self->logg("New tmp_path: $line\n", 1);
             }else {
                  $self->logg("$newlogpath does not exist.  Update tmp_path manually.\n", 1);
             }
         }
     }
     untie @lines;
}

# ------------------------------------------------------------------------------
# ------------------------- Wordpress Subroutines ------------------------------
# ------------------------------------------------------------------------------

#Extract information out of a Wordpress config file.
#Input: wordpress config file path/name.
#Output: An array with the hostname, database name, db username, and password in that order.
sub extract_db_wp {
     my $self    = shift;
     my $filenam = $_[0];
     my $host = "";             #Initialize the variables.
     my $db   = "";
     my $user = "";
     my $pass = "";
     my $line = "";
     open (INFILE, $filenam);
     while ($line = <INFILE>) {
          if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /DB_NAME/) { #If this is db config line,
             $db = $line;                               #Extract the db name.
             $db =~ s/'\s*\);.*//;
             $db =~ s/.*'//;
             $db =~ s/\n//;
             $db =~ s/\r//;
         }
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /DB_USER/) { #If this is the username config line,
             $user = $line;                             #Extract it.
             $user =~ s/'\s*\);.*//;
             $user =~ s/.*'//;
             $user =~ s/\n//;
             $user =~ s/\r//;
         }
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /DB_HOST/) { #If this is the host config line,
             $host = $line;                             #Extract it.
             $host =~ s/'\s*\);.*//;
             $host =~ s/.*'//;
             $host =~ s/\n//;
             $host =~ s/\r//;
         }
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /DB_PASSWORD/) { #If this is the host config line,
             $pass = $line;                                 #Extract it.
             $pass =~ s/'\s*\);.*//;
             $pass =~ s/.*'//;
             $pass =~ s/\n//;
             $pass =~ s/\r//;
         }
     }
     close INFILE;
     if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
     push (my @list, $host);
     push (@list, $db);
     push (@list, $user);
     push (@list, $pass);
     push (@list, "Wordpress");
     return @list;
}

# Update a Wordpress config file.
# Input: dbname, dbuser, configfile
# Ouput: Updated Wordpress configuration file.
sub update_db_wp {
     my $self     = shift;
     my $dbname   = @_[0];
     my $username = @_[1];
     my $filenam  = @_[2];
     
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;
     
     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /DB_NAME/) { #If this is db config line,
             $self->logg("Old DB: $line\n", 1);
             $line =~ s/',.*'.*'\s*\);/', '$dbname');/;     #replace it with the new db name.
             $self->logg("New DB: $line\n", 1);
         }
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /DB_USER/) { #If this is the username config line,
             $self->logg("Old User: $line\n", 1);
             $line =~ s/',.*'.*'\s*\);/', '$username');/;     #replace it with the new user name.
             $self->logg("New User: $line\n", 1);
         }
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /DB_HOST/) { #If this is the host config line,
             $self->logg("Old Host: $line\n", 1);
             $line =~ s/',.*'.*'\s*\);/', 'localhost');/;     #replace it with the new host name.
             $self->logg("New Host: $line\n", 1);
         }
     }
     untie @lines;
}

# ------------------------------------------------------------------------------
# --------------------------- bbPress Subroutines ------------------------------
# ------------------------------------------------------------------------------

#Extract information out of a bbPress config file.
#Input: bbPress config file path/name.
#Output: An array with the hostname, database name, db username, and password in that order.
sub extract_db_bbpress {
     my $self    = shift;
     my $filenam = $_[0];
     my $host = "";             #Initialize the variables.
     my $db   = "";
     my $user = "";
     my $pass = "";
     my $line = "";
     open (INFILE, $filenam);
     while ($line = <INFILE>) {
          if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /BBDB_NAME/) { #If this is db config line,
             $db = $line;                               #Extract the db name.
             $db =~ s/' *\);.*//;
             $db =~ s/.*'//;
             $db =~ s/\n//;
             $db =~ s/\r//;
         }
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /BBDB_USER/) { #If this is the username config line,
             $user = $line;                             #Extract it.
             $user =~ s/' *\);.*//;
             $user =~ s/.*'//;
             $user =~ s/\n//;
             $user =~ s/\r//;
         }
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /BBDB_HOST/) { #If this is the host config line,
             $host = $line;                             #Extract it.
             $host =~ s/' *\);.*//;
             $host =~ s/.*'//;
             $host =~ s/\n//;
             $host =~ s/\r//;
         }
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /BBDB_PASSWORD/) { #If this is the host config line,
             $pass = $line;                                 #Extract it.
             $pass =~ s/' *\);.*//;
             $pass =~ s/.*'//;
             $pass =~ s/\n//;
             $pass =~ s/\r//;
         }
     }
     close INFILE;
     if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
     push (my @list, $host);
     push (@list, $db);
     push (@list, $user);
     push (@list, $pass);
     push (@list, "bbPress");
     return @list;
}

# Update a bbPress config file.
# Input: dbname, dbuser, configfile
# Ouput: Updated bbPress configuration file.
sub update_db_bbpress {
     my $self     = shift;
     my $dbname   = @_[0];
     my $username = @_[1];
     my $filenam  = @_[2];
     
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;
     
     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /BBDB_NAME/) { #If this is db config line,
             $self->logg("Old DB: $line\n", 1);
             $line =~ s/',.*'.*' *\);/', '$dbname');/;     #replace it with the new db name.
             $self->logg("New DB: $line\n", 1);
         }
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /BBDB_USER/) { #If this is the username config line,
             $self->logg("Old User: $line\n", 1);
             $line =~ s/',.*'.*' *\);/', '$username');/;     #replace it with the new user name.
             $self->logg("New User: $line\n", 1);
         }
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /BBDB_HOST/) { #If this is the host config line,
             $self->logg("Old Host: $line\n", 1);
             $line =~ s/',.*'.*' *\);/', 'localhost');/;     #replace it with the new host name.
             $self->logg("New Host: $line\n", 1);
         }
     }
     untie @lines;
}

# ------------------------------------------------------------------------------
# ------------------------- osCommerce/Zen Cart Subroutines --------------------
# ------------------------------------------------------------------------------

#Extract information out of a osCommerce config file.  Zen Cart has an identical config file.
#Input: osCommerce config file path/name.
#Output: An array with the hostname, database name, db username, and password in that order.
sub extract_db_osc {
     my $self    = shift;
     my $filenam = $_[0];
     my $host = "";             #Initialize the variables.
     my $db   = "";
     my $user = "";
     my $pass = "";
     my $line = "";
     my $adminflag = 0;
     open (INFILE, $filenam);
     while ($line = <INFILE>) {
          if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /DB_DATABASE/) { #If this is db config line,
             $db = $line;                               #Extract the db name.
             $db =~ s/'\);.*//;
             $db =~ s/.*'//;
             $db =~ s/\n//;
             $db =~ s/\r//;
         }
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /DB_SERVER_USERNAME/) { #If this is the username config line,
             $user = $line;                             #Extract it.
             $user =~ s/'\);.*//;
             $user =~ s/.*'//;
             $user =~ s/\n//;
             $user =~ s/\r//;
         }
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line !~ /DB_SERVER_USERNAME/ && $line !~ /DB_SERVER_PASSWORD/ &&
             $line =~ /define/ && $line =~ /DB_SERVER/) { #If this is the host config line,
             $host = $line;                             #Extract it.
             $host =~ s/'\);.*//;
             $host =~ s/.*'//;
             $host =~ s/\n//;
             $host =~ s/\r//;
         }
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /DB_SERVER_PASSWORD/) { #If this is the host config line,
             $pass = $line;                                 #Extract it.
             $pass =~ s/'\);.*//;
             $pass =~ s/.*'//;
             $pass =~ s/\n//;
             $pass =~ s/\r//;
         }
         if ($line =~ /DIR_FS_ADMIN/) {
             $adminflag = 1;
         }
     }
     close INFILE;
     if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
     my @list;
     if ($adminflag == 0) {
         push (@list, $host);
         push (@list, $db);
         push (@list, $user);
         push (@list, $pass);
         push (@list, "osCommerce");
     }else {
         @list =();
     }
     return @list;
}

# Update an osCommerce config file.
# Input: dbname, dbuser, configfile
# Ouput: Updated osCommerce configuration file.
sub update_db_osc {
     my $self     = shift;
     my $dbname   = @_[0];
     my $username = @_[1];
     my $filenam  = @_[2];
     
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;
     
     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /DB_DATABASE/) { #If this is db config line,
             $self->logg("Old DB: $line\n", 1);
             $line =~ s/',.*'.*'\);/', '$dbname');/;     #replace it with the new db name.
             $self->logg("New DB: $line\n", 1);
         }
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /DB_SERVER_USERNAME/) { #If this is the username config line,
             $self->logg("Old User: $line\n", 1);
             $line =~ s/',.*'.*'\);/', '$username');/;     #replace it with the new user name.
             $self->logg("New User: $line\n", 1);
         }
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line !~ /DB_SERVER_USERNAME/ && $line !~ /DB_SERVER_PASSWORD/ &&
             $line =~ /define/ && $line =~ /DB_SERVER/) { #If this is the host config line,
             $self->logg("Old Host: $line\n", 1);
             $line =~ s/',.*'.*'\);/', 'localhost');/;     #replace it with the new host name.
             $self->logg("New Host: $line\n", 1);
         }
     }
     untie @lines;
}

# public $log_path = '/home/mstreete/public_html/osc/includes';
# public $tmp_path = '/home/mstreete/public_html/osc/tmp';
# Update the path config lines in a Joomla! config file.
# Input: Configuration file
# Output: $log_path and tmp_path lines will be updated with the new path.
#         Will also confirm that the directories exist in the new path where we expect them.
sub update_path_osc {
     my $self     = shift;
     my $filenam  = $_[0];
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;
     my $dirpath = finddirpath($filenam);
     my $dirpath = chopbottomdir($dirpath);
     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /'DIR_FS_CATALOG'/) { #If this is db config line,
             $self->logg("Old path: $line\n", 1);
             my $configline = $line;                    #Work with a temp variable $configline
             $configline =~ s/,.*'.*\//, '$dirpath\//;    #Update the config line with the new path.
             my $newpath = $configline;
             $newpath =~ s/'\).*;//;                  #Remove all but the config path so we can
             $newpath =~ s/.*'//;                 # see if the directory exists.
             if (-d $newpath) {
                  $line = $configline;               #Update the line in the file since the dir exists.
             }else {
                  $self->logg("$newpath does not exist.  Update path manually.\n", 1);
             }
             $self->logg("New path: $line\n", 1);
         }
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /'DIR_FS_SQL_CACHE'/) { #If this is db config line,
             $self->logg("Old path: $line\n", 1);
             my $configline = $line;                    #Work with a temp variable $configline
             $configline =~ s/,.*'.*\//, '$dirpath\//;    #Update the config line with the new path.
             my $newpath = $configline;
             $newpath =~ s/'\).*;//;                  #Remove all but the config path so we can
             $newpath =~ s/.*'//;                 # see if the directory exists.
             if (-d $newpath) {
                  $line = $configline;               #Update the line in the file since the dir exists.
             }else {
                  $self->logg("$newpath does not exist.  Update path manually.\n", 1);
             }
             $self->logg("New path: $line\n", 1);
         }
     }
     untie @lines;
}

# ------------------------------------------------------------------------------
# ------------------------- osCommerce/Zen Cart Admin Subroutines --------------
# ------------------------------------------------------------------------------
# Example config lines from TomatoCart in includes/configure.php.
#  define('DB_SERVER', 'localhost');
#  define('DB_SERVER_USERNAME', 'mss001_tmtc1');
#  define('DB_SERVER_PASSWORD', 'JgLrYYyhFmTJhlSM');
#  define('DB_DATABASE', 'mss001_tmtc1');
#  define('DB_DATABASE_CLASS', 'mysql');
#Extract information out of a osCommerce config file.  Zen Cart and TomatoCart have a nearly identical admin config file.
#Input: osCommerce config file path/name.
#Output: An array with the hostname, database name, db username, and password in that order.
sub extract_db_oscadmin {
     my $self    = shift;
     my $filenam = $_[0];
     my $host = "";             #Initialize the variables.
     my $db   = "";
     my $user = "";
     my $pass = "";
     my $line = "";
     my $adminflag = 0;
     open (INFILE, $filenam);
     while ($line = <INFILE>) {
          if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line !~ /DB_DATABASE_CLASS/ && $line =~ /DB_DATABASE/) { #If this is db config line,
             $db = $line;                               #Extract the db name.
             $db =~ s/'\);.*//;
             $db =~ s/.*'//;
             $db =~ s/\n//;
             $db =~ s/\r//;
         }
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /DB_SERVER_USERNAME/) { #If this is the username config line,
             $user = $line;                             #Extract it.
             $user =~ s/'\);.*//;
             $user =~ s/.*'//;
             $user =~ s/\n//;
             $user =~ s/\r//;
         }
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line !~ /DB_SERVER_USERNAME/ && $line !~ /DB_SERVER_PASSWORD/ &&
             $line =~ /define/ && $line =~ /DB_SERVER/) { #If this is the host config line,
             $host = $line;                             #Extract it.
             $host =~ s/'\);.*//;
             $host =~ s/.*'//;
             $host =~ s/\n//;
             $host =~ s/\r//;
         }
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /DB_SERVER_PASSWORD/) { #If this is the host config line,
             $pass = $line;                                 #Extract it.
             $pass =~ s/'\);.*//;
             $pass =~ s/.*'//;
             $pass =~ s/\n//;
             $pass =~ s/\r//;
         }
         if ($line =~ /DIR_FS_ADMIN/) {
             $adminflag = 1;
         }
     }
     close INFILE;
     if ($db =~ /\$/ or $user =~ /\$/ or $host =~ /\$/ ) {return 0;}
     my @list;
     if ($adminflag == 1) {
         push (@list, $host);
         push (@list, $db);
         push (@list, $user);
         push (@list, $pass);
         push (@list, "osCommerce Admin");
     }else {
         @list =();
     }
     return @list;
}

# Update an osCommerce config file.
# Input: dbname, dbuser, configfile
# Ouput: Updated osCommerce configuration file.
sub update_db_oscadmin {
     my $self     = shift;
     my $dbname   = @_[0];
     my $username = @_[1];
     my $filenam  = @_[2];
     
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;
     
     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line !~ /DB_DATABASE_CLASS/ && $line =~ /DB_DATABASE/) { #If this is db config line,
             $self->logg("Old DB: $line\n", 1);
             $line =~ s/',.*'.*'\);/', '$dbname');/;     #replace it with the new db name.
             $self->logg("New DB: $line\n", 1);
         }
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /DB_SERVER_USERNAME/) { #If this is the username config line,
             $self->logg("Old User: $line\n", 1);
             $line =~ s/',.*'.*'\);/', '$username');/;     #replace it with the new user name.
             $self->logg("New User: $line\n", 1);
         }
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line !~ /DB_SERVER_USERNAME/ && $line !~ /DB_SERVER_PASSWORD/ &&
             $line =~ /define/ && $line =~ /DB_SERVER/) { #If this is the host config line,
             $self->logg("Old Host: $line\n", 1);
             $line =~ s/',.*'.*'\);/', 'localhost');/;     #replace it with the new host name.
             $self->logg("New Host: $line\n", 1);
         }
     }
     untie @lines;
}

# public $log_path = '/home/mstreete/public_html/osc/includes';
# public $tmp_path = '/home/mstreete/public_html/osc/tmp';
# Update the path config lines in a Joomla! config file.
# Input: Configuration file
# Output: $log_path and tmp_path lines will be updated with the new path.
#         Will also confirm that the directories exist in the new path where we expect them.
sub update_path_oscadmin {
     my $self     = shift;
     my $filenam  = $_[0];
     # Tie the config file to the @lines array so we can modify the file the same way we mod an array.
     tie my @lines, 'Tie::File', $filenam;
     my $dirpath = finddirpath($filenam);
     my $dirpath = chopbottomdir($dirpath);
     my $dirpath = chopbottomdir($dirpath);
     # Loop through each line of the file, looking for the lines to change.
     foreach my $line (@lines) {
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /'DIR_FS_CATALOG'/) { #If this is db config line,
             $self->logg("Old path: $line\n", 1);
             my $configline = $line;                    #Work with a temp variable $configline
             $configline =~ s/,.*'.*\//, '$dirpath\//;    #Update the config line with the new path.
             my $newpath = $configline;
             $newpath =~ s/'\).*;//;                  #Remove all but the config path so we can
             $newpath =~ s/.*'//;                 # see if the directory exists.
             if (-d $newpath) {
                  $line = $configline;               #Update the line in the file since the dir exists.
             }else {
                  $self->logg("$newpath does not exist.  Update path manually.\n", 1);
             }
             $self->logg("New path: $line\n", 1);
         }
         if ($line !~ /\/\*.*define/ && $line !~ /#.*define/ && $line !~ /\/\/.*define/ &&
             $line =~ /define/ && $line =~ /'DIR_FS_SQL_CACHE'/) { #If this is db config line,
             $self->logg("Old path: $line\n", 1);
             my $configline = $line;                    #Work with a temp variable $configline
             $configline =~ s/,.*'.*\//, '$dirpath\//;    #Update the config line with the new path.
             my $newpath = $configline;
             $newpath =~ s/'\).*;//;                  #Remove all but the config path so we can
             $newpath =~ s/.*'//;                 # see if the directory exists.
             if (-d $newpath) {
                  $line = $configline;               #Update the line in the file since the dir exists.
             }else {
                  $self->logg("$newpath does not exist.  Update path manually.\n", 1);
             }
             $self->logg("New path: $line\n", 1);
         }
     }
     print "Path updates for this file cannot always be set accurately.  Please ***** double-check *****\n";
     untie @lines;
}



# ------------------------------------------------------------------------------
# ----------------------------- cPanel Subroutines ---------------------------
# ------------------------------------------------------------------------------
# Create a database and add a database user
# Input: cpanel user, database user, database, password. 
# Output: Added db user.  Returns 0 for success or 1 for failure.
sub adddbuser {
     my $self   = shift;
     my $result = 0;
     my $cpuser = @_[0];
     my $dbuser = @_[1];
     my $db     = @_[2];
     my $pass   = @_[3];
     my $temppass;
     my $token  = $self->{token};
     my $auth;
     my $apic;
     $dbuser =~ s/.*_//;   #If the db name or username start with something_ then remove that part.
     $db     =~ s/.*_//;   #i.e. wrdp1
     $cpuser = uri_escape($cpuser); #Escape the variables so they aren't corrupted when being passed through the URL.
     $dbuser = uri_escape($dbuser); 
     $db = uri_escape($db);

     my $prefix_db; #Database name including the prefix.  i.e. user_wrdp1
     if (length($cpuser)>8) {
          $prefix_db = substr($cpuser,0,8) . "\_$db";
     }else{
          $prefix_db = "$cpuser\_$db";
     }
     my $prefix_dbuser = $prefix_db; #$prefix_db and $prefix_dbuser are exactly the same.  The only purpose
                                     # of $prefix_dbuser is to clarify the code.
     #If token is defined, use it for auth.
     if ( $token ) {
        $apic = cPanel::PublicAPI->new(ssl_verify_mode => '0', api_token => "$token");
     } else {
        if ( !-s "/root/.accesshash" ) {
                $ENV{'REMOTE_USER'} = 'root';
                system('/usr/local/cpanel/bin/realmkaccesshash');
        }
        $apic = cPanel::PublicAPI->new(ssl_verify_mode => '0');
     }

     # ----- Add the database -------
     $self->logg("Adding the database..........\n", 1);
     my $response = $apic->cpanel_api2_request('whostmgr', { 'module' => 'MysqlFE', 'func' => 'createdb', 'user' => "$cpuser"},{ 'db' => "$prefix_db"}, 'json');
     my $json = from_json($response);
     if ($json->{'cpanelresult'}->{'event'}->{'result'} != 1) {
         $self->logg("Error: " . $json->{'cpanelresult'}->{'data'}->{'reason'} . "\n", 1);
         $result = 1;
         return $result;
     }

     # Generate a temporary password.
     do {
          $temppass = Cpanel::PasswdStrength::Generate::generate_password(12);
     } while (!Cpanel::PasswdStrength::Check::check_password_strength('pw' => $temppass, 'app' => "mysql"));
     $temppass = uri_escape($temppass);
     # ------- Add the database user -------
     $self->logg("Adding the user.........\n", 1);
     $response = $apic->cpanel_api2_request('whostmgr', { 'module' => 'MysqlFE', 'func' => 'createdbuser', 'user' => "$cpuser"}, { 'dbuser' => "$prefix_dbuser", 'password' => "$temppass" }, 'json');
     $json = from_json($response);
     if ($json->{'cpanelresult'}->{'event'}->{'result'} != 1) {
         $self->logg("Error: " . $json->{'cpanelresult'}->{'event'}->{'reason'} . "\n", 1);
         $result = 1;
         return $result;
     }

     # We created the the database user with a password that passes cPanel's strength test in order to avoid a cPanel error.
     # But in a migration, there could be additional files that have their old password.
     # Therefore, the migration is more reliable if we do not change their original database password.
     # So let's set the database user's password back to what is in the config file.
     set_mysql_password($prefix_dbuser, $pass); 

     # ------- Add the user to the database ------------------
     $self->logg("Adding the user to the database.........\n", 1);
     $response = $apic->cpanel_api2_request('whostmgr', { 'module' => 'MysqlFE', 'func' => 'setdbuserprivileges', 'user' => "$cpuser"}, { 'db' => "$prefix_db", 'dbuser' => "$prefix_dbuser", 'privileges' => 'ALL' }, 'json');
     $json = from_json($response);
     if ($json->{'cpanelresult'}->{'event'}->{'result'} != 1) {
         $self->logg("Error: " . $json->{'cpanelresult'}->{'event'}->{'reason'} . "\n", 1);
         $result = 1;
         return $result;
     }

     return $result;
}

# Set a new mysql password for the given user.
# Input:  MySql user
#         MySql password
# Output: 0=Error, 1=OK
# DBI Connect is not properly reading the password in /root/.my.cnf if it has quotes, which all on our farm do. Replaced with /scripts/mysqlpasswd
sub set_mysql_password {
     my $mysql_user = shift;
     my $mysql_pass = shift;
     $mysql_pass =~ s/\\/\\\\/; #MySql needs \ escaped. (i.e. if password has \, change it to \\).
     system "/scripts/mysqlpasswd", $mysql_user, $mysql_pass;
#     my $db = DBI->connect("DBI:mysql:mysql:127.0.0.1;mysql_read_default_file=/root/.my.cnf", "", "");
#     if (!$db) {
#          print "Failed to connect to import database. $DBI::errstr";
#          return 0;
#     }

#     my $sth = $db->prepare("set password for ?\@'localhost' = PASSWORD(?)");
#     my $result = $db->do("update user set password=PASSWORD(?) where User=?", undef, $mysql_pass, $mysql_user); #This appears to be more effective than prepare/execute
#     my $result = $sth->execute($mysql_user, $mysql_pass);
#     if (!$result) {
#          print "Failed to update the password for $mysql_user.\n";
#          $db->disconnect();
#          return 0;
#     }
#     $db->disconnect();
     return 1;
}

# Find a suitable database name that conforms to the cPanel naming convention.
# Input: Old database name, cPanel username.
# Output: New database name.
sub findnewdbname {
     my $self   = shift;
     my $olddb  = $_[0];
     my $cpuser = $_[1];
     my $prompt = $_[2];
     my $newdb  = "";
     my $checkdb_result;
     $olddb =~ s/\.sql$//;            #Change dbname.sql to dbname.
     if (length($cpuser)>8) {         #If username > 8 characters, only use the first 8 for the db prefix.
          $cpuser = substr($cpuser,0,8);
     }
     if ($self->cpanel_compat($olddb, $cpuser) == 0) {
          $newdb = $olddb;
     }else {
          my $dbtrunc = $olddb;
          $dbtrunc =~ s/.*_//;           #If the old db name has an _, chop it and everything before.
          $dbtrunc =~ s/[^A-Za-z0-9]//g; #Remove invalid characters.
          if (length($dbtrunc) == 0) {   #If nothing is left after removing invalid characters,
               $dbtrunc = "db";          # then start out with "db"
          }
          if (length($cpuser) + length($dbtrunc) > 12) { #Max length is 16 so allow room for the _ and 3 digits.
               $dbtrunc = substr($dbtrunc, 0, 12-length($cpuser));
          }
          my $x = 0;
          do {                       #Keep trying database names until we find a suitable one.
               if ($x == 0) {
                    $newdb = $cpuser . "_" . $dbtrunc;  #Try a dbname without adding a number first.
               }else {
                    $newdb = $cpuser . "_" . $dbtrunc . $x; #If that's not acceptable, try it with a
               }                                            # number.
               $checkdb_result = $self->cpanel_checkdb($newdb);
               $x++;
          }while ($checkdb_result == 1 && $x < 1000);
          if ($checkdb_result == 1) {
               $self->logg("********** Warning ************ A suitable new database name could not be found.  Please enter one manually.\n", 1);
               $newdb = "invalid";
          }
     }
     if ($prompt > 0) {
          my $dbconfirmed = 0;            #Initialize dbconfirmed.
          do {                            #Now that we have a database name, confirm it with the user.
               $self->logg("Please enter a new database name (Enter = $newdb): ", 1);
               my $dbentered = <STDIN>;
               $dbentered =~ s/\n//;
               if (length($dbentered) > 0) {
                    $newdb = $dbentered;
               }
               if ($self->cpanel_compat($newdb, $cpuser)>0) {; # keep asking for it until they enter
                                                            #an acceptable one.
                    $self->logg("Please enter a different database name.  This one exists or does not ", 1);
                    $self->logg("fit the cPanel naming convention, or is not for this cPanel user.\n\n", 1);
                    $dbconfirmed = 0;
               }else {                                 #User entered a suitable db name.
                    $dbconfirmed = 1;
               }
          }while ($dbconfirmed == 0);
     }
     return $newdb;
}

#Determine whether or not the old database name (or an entered one) can be used as the new db name.
# Input: database name, cPanel username.
# Output: 0 = yes
#         1 = no
sub cpanel_compat {
     my $self = shift;
     my $olddb = $_[0];
     my $cpuser = $_[1];
     my $ret = 1;             #Default to "no".
     if ($olddb =~ /_/) {  #If the old database name has an underscore, see if we can use
          my $temp1 = $olddb; # the same datbase name.
          $temp1 =~ s/_.*//;  #remove underscore and after, leaving just the username.
          if ($temp1 eq $cpuser        && #username part has to match the cPanel username.
              length($olddb) <= 16     && #Database name has to be <= 16 characters long.
              $olddb !~ /[^A-Za-z0-9_]/ && #Database name cannot contain any invalid characters.
              $self->cpanel_checkdb($olddb) == 0) { #Make sure the database doesn't already exist.
               $ret = 0;   #The old database name looks suitable.
          }
     }
     return $ret;
}

#Check to see if a database exists.
#Input: Database name
#Output: 0 = Does not exist
#        1 = Database or database user exists
#        2 = error
sub cpanel_checkdb {
     my $self       = shift;
     my $dbtestname = @_[0];
     my $status = 0;
     open (FILE, "mysqlshow|") || die "Cannot run mysqlshow: $!";
     if ($? != 0) {
          return 2;  #Return Error.  Something went wrong with the mysql command.
     }
     while (<FILE>) {
          if ($_ =~ /_/ && $_ !~ /information_schema/) {
               my $line = $_;
               $line =~ s/\| *//;             #remove stuff before the db name
               $line =~ s/ *\|.*//;           #remove stuff after the db name
               $line =~ s/\n//;               #remove newline.
               if ($line eq $dbtestname) {
                    $self->logg("**************** Database $dbtestname already exists ****************\n", 1);
                    $status = 1;
               }
          }
     }
     close FILE;
     # Also check to see if the database user exists.
     my $usercount = `mysql -ss -e \"select count(*) from user where user = '$dbtestname';\" mysql`;
     if ($? != 0) { #If mysql returned an error, then we too will return an error.
          return 2;
     }
     chomp($usercount);
     if ($usercount > 0) {
          $self->logg("**************** Database User $dbtestname already exists ****************\n", 1);
          $status = 1;
     }
     return $status;
}

# ------------------------------------------------------------------------------
# ----------------------------- Plesk Subroutines ----------------------------
# ------------------------------------------------------------------------------

# Determine whether or not this is a Plesk server.
# Input:  Nothing
# Output: 1 = Yes
#         0 = No
sub is_plesk {
     my $self = shift;
     if (-s "/etc/psa/.psa.shadow") {
          return 1;
     }else{
          return 0;
     }
}

## Create a database and add a database user
## Input: domain (i.e. mysite.com), database user, database, password. 
## Output: Added db user.  Returns 0 for success or 1 for failure.
sub plesk_adddbuser {
     my $self   = shift;
     my $domain = @_[0];
     my $dbuser = @_[1];
     my $db     = @_[2];
     my $pass   = @_[3];
     my $out = "";
     my $ret = 0;
     $domain = lc($domain);
     $self->logg("Creating Database...\n", 1);
     $self->logg("/usr/local/psa/bin/database -c $db -domain $domain -type mysql\n", 1);
     my @output = `/usr/local/psa/bin/database -c $db -domain $domain -type mysql`;
     foreach $out (@output) { #Print the output from the external call.
          $self->logg($out, 1);
     }
     if (($? >> 8) > 0) {     #Check the return code, and exit if the external call failed.
          $ret = ($? >> 8);
          return $ret;
     }
     $self->logg("Creating User and adding to database...\n", 1);
     $self->logg("/usr/local/psa/bin/database -u $db -add_user $dbuser -passwd '$pass'", 1);
     @output = `/usr/local/psa/bin/database -u $db -add_user $dbuser -passwd '$pass'`;
     foreach $out (@output) { #Print the output from the external call.
          $self->logg($out, 1);
     }
     if (($? >> 8) > 0) {     #Check the return code, and exit if the external call failed.
          $ret = ($? >> 8);
          return $ret;
     }
     return $ret;
}

# Find a suitable database name that conforms to the length limits and doesn't already exist.
# Input: Old database name.
#        Prompting flag (0=Don't prompt user to confirm/enter database name, 1=Prompt)
# Output: New database name.
sub plesk_findnewdbname {
     my $self   = shift;
     my $olddb  = $_[0];              #Old database name
     my $prompt = $_[1];
     my $newdb = "";
     my $checkdb_result;
     $olddb =~ s/\.sql$//;            #Change dbname.sql to dbname.
     if ($self->plesk_compat($olddb) == 0) {
          $newdb = $olddb;
     }else {
          my $dbtrunc = $olddb;
          if (length($dbtrunc) > 13) {
               $dbtrunc = substr($dbtrunc,0,13);
          }
          my $x = 0;
          do {                       #Keep trying database names until we find a suitable one.
               if ($x == 0) {
                    $newdb = $dbtrunc;  #Try a dbname without adding a number first.
               }else {
                    $newdb = $dbtrunc . $x; #If that's not acceptable, try it with a
               }                                            # number.
               $checkdb_result = $self->plesk_checkdb($newdb);
               $x++;
          }while ($checkdb_result == 1 && $x < 1000);
          if ($checkdb_result == 1) {
               $self->logg("********** Warning ************ A suitable new database name could not be found.  Please enter one manually.\n", 1);
          }
     }
     if ($prompt > 0) {
          my $dbconfirmed = 0;            #Initialize dbconfirmed.
          do {                            #Now that we have a database name, confirm it with the user.
               $self->logg("Please enter a new database name (Enter = $newdb): ", 1);
               my $dbentered = <STDIN>;
               $dbentered =~ s/\n//;
               if (length($dbentered) > 0) {
                    $newdb = $dbentered;
               }
               if ($self->plesk_compat($newdb)>0) {; # keep asking for it until they enter
                                                       #an acceptable one.
                    $self->logg("Please enter a different database name.  This one exists or does not ", 1);
                    $self->logg("fit the naming requirements.\n\n", 1);
                    $dbconfirmed = 0;
               }else {                                 #User entered a suitable db name.
                    $dbconfirmed = 1;
               }
          }while ($dbconfirmed == 0);
     }
     return $newdb;
}

#Determine whether or not the database name (or an entered one) can be used as the new db name.
# Input: database name.
# Output: 0 = yes
#         1 = no
sub plesk_compat {
     my $self   = shift;
     my $dbname = @_[0];
     my $ret = 1;             #Default to "no".
     if (length($dbname) <= 16 && $self->plesk_checkdb($dbname) == 0) {
          $ret = 0;   #The old database name looks suitable.
     }
     return $ret;
}

#Check to see if a database exists.
#Input: Database name
#Output: 0 = Does not exist
#        1 = Database or database user exists
#        2 = error
sub plesk_checkdb {
     my $self       = shift;
     my $dbtestname = @_[0];
     my $status = 0;
     my $mysqlpass = `cat /etc/psa/.psa.shadow`; #Grab MySQL password.
     chomp($mysqlpass);
     open (FILE, "mysqlshow -u'admin' -p'$mysqlpass'|") || die "Cannot run mysqlshow: $!";
     if ($? != 0) {
          return 2;  #Return Error.  Something went wrong with the mysql command.
     }
     while (<FILE>) {
          if ($_ !~ /information_schema/) {
               my $line = $_;
               $line =~ s/\| *//;             #remove stuff before the db name
               $line =~ s/ *\|.*//;           #remove stuff after the db name
               $line =~ s/\n//;               #remove newline.
               if ($line eq $dbtestname) {
                    $self->logg("**************** Database $dbtestname already exists ****************\n", 1);
                    $status = 1;
               }
          }
     }
     close FILE;
     # Also check to see if the database user exists.
     my $usercount = `mysql -ss -uadmin -p'$mysqlpass' -e \"select count(*) from user where user = '$dbtestname';\" mysql`;
     if ($? != 0) { #If mysql returned an error, then we too will return an error.
          return 2;
     }
     chomp($usercount);
     if ($usercount > 0) {
          $self->logg("**************** Database User $dbtestname already exists ****************\n", 1);
          $status = 1;
     }
     return $status;
}

#Find the domain name
#Input: No arguments needed (obtains current directory from getcwd)
#Output: The domain name of the account whose directory you are in.
sub plesk_finddomain {
     my $domain = "";
     my $mysqlpass = `cat /etc/psa/.psa.shadow`; #Grab MySQL password.
     chomp($mysqlpass);
     #Read the list of document roots into @docroots array.
     my @docroots = `mysql -ss -u'admin' -p'$mysqlpass' -e"select www_root from hosting;" psa`;
     my $dir = getcwd();                    #Look up the current directory.
     my $webspaceid = 0;
     #Go through the account directories (document roots with httpdocs chopped off) looking for one that matches the
     # directory we are in.  If we find it, we can then look up the domain associated with that directory.
     foreach my $line (@docroots) {
          chomp($line);
          my $choppedline = chopbottomdir($line);
          if ($dir =~ /$choppedline/) {
               $webspaceid = `mysql -ss -u'admin' -p'$mysqlpass' -e"select domains.webspace_id from domains inner join hosting on domains.id=hosting.dom_id where hosting.www_root = '$line' limit 1;" psa`;
               if ($webspaceid == 0) { #If the webspaceid is 0, then we're in the directory for the primary domain.  Look up the primary domain based on the directory.
                    $domain = `mysql -ss -u'admin' -p'$mysqlpass' -e"select domains.name from domains inner join hosting on domains.id=hosting.dom_id where hosting.www_root = '$line' limit 1;" psa`;
               }else {                 #If the webspaceid is not 0, then we're in an addon directory, and the webspaceid is domain ID of the primary domain.  Look up the primary domain based on the webspaceid.
                    $domain = `mysql -ss -u'admin' -p'$mysqlpass' -e"select domains.name from domains where domains.id=$webspaceid limit 1;" psa`;
               }
          }
     }
     chomp($domain);
     return $domain
}

# Just like dbclist except that this takes a single directory as its second argument rather than an array of directories.
# Input:  $_[0] = The directory the databases are in.
#         $_[1] = String containing the path/name of a single directory to search for config files.
# Output: Whatever dbclist outputs.
sub singledir_dbclist() {
     my $self        = shift;
     my $dbdir       = $_[0];
     my $dirtosearch = $_[1];
     my @dirlist;
     push (@dirlist, $dirtosearch);
     return $self->dbclist ($dbdir, \@dirlist);
}

# -----------------------------------------------------------------------------
# -------------- dbclist subroutines (cPanel and Plesk) -----------------------
# -----------------------------------------------------------------------------

#dbconnect a list of databases
#Input: $_[0] = The directory the databases are in.
#       $_[1] = Reference to an array listing the directories to search for config files.
#
#          Issue: database names are expected without the full paths.  Current directory provides the path.
#Output: No value is returned, but the directory is searched for config files.  Database names in those config files are matched against the

sub dbclist () {
     my $self    = shift;
     $self->{dbinfolist} = [];    #Make sure there is no leftover data in the arrays.
     $self->{configlist} = [];
     my $dbdir        = $_[0];
     my $dirlist      = $_[1];
     my @finaldirlist;
     my @summary      = ();
     $self->prune_dirs($dirlist, \@finaldirlist); #Prune out unnecessary directories from the list.
 
     opendir my $dirhandle, $dbdir;
     my @dblist = readdir $dirhandle;
     close $dirhandle;

     #my @dblist = `ls -1 $dbdir/*.sql`;
     foreach my $db (@dblist){   #Go through the database array (passed in $_[1]) and create a DBInfo object for each one.
         chomp($db);
         if ($db =~ /\.sql$/) {
              $db =~ s/\.sql$//;
              my $dbinfoobject = DBInfo->new($dbdir . "/" . $db, $self);   #Add a DBInfo object for this dump file to the array.
              push (@{$self->{dbinfolist}}, $dbinfoobject);
         }
     }

     if (! $self->{dbinfolist}) {                #If dbinfolist is not defined, then exit.
          $self->logg("No database dumps found\n", 1);
          return 0;
     }
     if (scalar(@{$self->{dbinfolist}}) == 0) {     #If dbinfolist has no elements, then also exit.
          $self->logg("No database dumps found\n", 1);
          return 0;
     }
    
     $self->find_configs(\@finaldirlist); # Find the config files in these directories and populate $self->{configlist}

     # At this point we have a populated array of DBInfo objects as well as a populated array of ConfigInfo objects.
     foreach my $config (@{$self->{configlist}}) {
         my $dbdump = $self->find_db_dump($config->{olddb});   #Try to match a DBInfo object against the old database name from the config file object.
         if ($dbdump != 0) {
             $self->logg($config->{appname} . " config file " . $config->{configfile} . " matched with database " . $dbdump->{name} . "\n", 1);
             if ($dbdump->{dbfound} == 1) {      #This database has already been created/imported.  Only update the config file.
                  #Keep in mind that we are going through the config list one by one and searching for matching db_dump files.
                  #Since we have found a db_dump file that is flagged as "dbfound" (i.e. it has already been connected),
                  # we now have to search back through the config file objects to find the one that matches the old database
                  # name and also has the new database name populated.  We can then pass the new database name from that object
                  # to $self->prompt_updatedb.
                  foreach my $config_search (@{$self->{configlist}}) {
                       if ($config_search->{olddb} eq $config->{olddb} && length($config_search->{newdb}) > 0) {
                            $config->{newdb} = $config_search->{newdb};
                            last;
                       }
                  }
                  my @dbcinfo = $self->prompt_updatedb($config->{newdb}, $config->{configfile}, $self->{prompt});
                  $config->{newdb} = $dbcinfo[0];
                  $self->{prompt}  = $dbcinfo[1];
             }else {
                  #This database has not yet been created/imported.  Call dbconnect.
                  my @dbcinfo = ();
                  if ($self->is_plesk()) {
                       @dbcinfo = $self->prompt_plesk_dbconnect($dbdump->{fullname}, $config->{configfile}, $self->{prompt}, $config->{domain});
                  }else{
                       @dbcinfo = $self->prompt_cpanel_dbconnect($dbdump->{fullname}, $config->{configfile}, $self->{prompt}, $config->{cpuser});
                  }
                  $config->{newdb} = $dbcinfo[0];
                  $self->{prompt}  = $dbcinfo[1];
                  if (length($config->{newdb}) > 0) {
                      $dbdump->{dbfound} = 1;
                  }
             }
         }else{
             $config->{newdb} = "";
         }
     }

     $self->logg("\nUnmatched config files:\n", 1);
     foreach my $config (@{$self->{configlist}}) {
         if (length($config->{newdb}) == 0) {
             $self->logg($config->{appname} . ": " . $config->{configfile} . " (Database: " . $config->{olddb} . ")\n", 1);
         }
     }

     $self->logg("\nUnmatched dump files:\n", 1);
     foreach my $db (@{$self->{dbinfolist}}){
         if ($db->{dbfound} == 0) {
             $self->logg($db->{name} . "\n", 1);
         }
     }

     $self->logg("\nConnected Databases:\n", 1);
     $self->logg("Olddb --> Newdb --> Configfile\n", 1);
     foreach my $config (@{$self->{configlist}}) {
         if (length($config->{newdb}) > 0) {
             push (@summary, $config->{olddb} . " --> " . $config->{newdb} . " --> " . $config->{configfile} . "\n");
             $self->logg($config->{olddb} . " --> " . $config->{newdb} . " --> " . $config->{configfile} . "\n", 1);
         }
     }
     return @summary;
}

sub plesk_dbclist () { #Deprecated.  Use dbclist instead.
     my $self    = shift;
     my $dbdir        = $_[0];
     my $dirlist      = $_[1];
     $self->dbclist($dbdir, $dirlist);
}

# Search the array of DBinfo objects to see if a database dump file matches the database name we want to search for.
# Input: Old database name
# Output:
sub find_db_dump {
     my $self = shift;
     my $olddb = $_[0];
     foreach my $db (@{$self->{dbinfolist}}) {
          if ($db->{name} eq $olddb) {
               return $db;
          }
     }
     return 0;
}

# Find all of the known config files in a list of directories.
# Input:  Ref to an array of directories.
# Output: Ref to an array of ConfigInfo objects.
sub find_configs {
     my $self         = shift;
     my $finaldirlist = shift;
     # Traverse the user home directories, looking for config files.
     #http://stackoverflow.com/questions/5502218/how-do-i-insert-new-fields-into-self-in-perl-from-a-filefind-callback
     # "wanted" is a closure referencing the address of the wanted sub because this is the only way you can pass additional
     # arguments to the wanted sub.  Since the wanted sub is in an object, we have to pass the object hash.
     $self->{configlist} = [];
     File::Find::find(sub {$self->wanted()}, @{$finaldirlist});
     return $self->{configlist}; # <-- Populated by the wanted sub.
}

# Callback subroutine used by File::find::find in dbclist sub above.
sub wanted {
    my $self = shift;
    my $filename = $File::Find::name;
    $filename =~ s/.*\///;
    #$self->logg("File: $filename\n", 1);
    if ($self->is_supported_filename($filename)) {
        my @info = $self->extract_db($File::Find::name);
        if (fields_populated(@info)) {
            my $configinfoobject = ConfigInfo->new($File::Find::name);
            $configinfoobject->{configfile} = $File::Find::name;
            $configinfoobject->{dbhost}     = $info[0];
            $configinfoobject->{olddb}      = $info[1];
            my $temp = $File::Find::name;
            $temp =~ s/\/home\d?\///;   #Remove the part of the dir before and after the username.
            $temp =~ s/\/.*//;
            if ($self->is_plesk()) {
                 $temp = plesk_finddomain($temp);      #Convert the directory into its corresponding domain name.
                 $configinfoobject->{domain} = $temp;
            }else{
                 $configinfoobject->{cpuser} = $temp;
            }
            $configinfoobject->{dbuser}     = $info[2];
            $configinfoobject->{password}   = $info[3];
            $configinfoobject->{appname}    = $info[4];
            push (@{$self->{configlist}}, $configinfoobject);
        }else{
            #$self->logg("Skipping because it has one or more empty fields.\n", 1);
        }
    }
}

# Determine whether or not a filename is a config file of a supported web app.
# Input:  Filename
# Output: 1=Supported, 0=Not supported.
sub is_supported_filename {
     my $self     = shift;
     my $filename = shift;
     if ($filename eq "wp-config.php"      || $filename eq "bb-config.php"     || $filename eq "configuration.php"
        || $filename eq "config.php"       || $filename eq "local.xml"         || $filename eq "settings.php"
        || $filename eq "Settings.php"     || $filename eq "configure.php"     || $filename eq "site.php"
        || $filename eq "settings.inc.php" || $filename eq "LocalSettings.php" || $filename eq "config.inc.php"
        || $filename eq "config.ini.php"   || $filename eq "dap-config.php"    || $filename eq "global.inc.php"
        || $filename eq "202-config.php"   || $filename eq "e107_config.php"   || $filename eq "LocalConfiguration.php"
        || $filename eq "localconf.php"    || $filename eq "database.php"      || $filename eq "env.php") {
          return 1;
     }
     return 0;
}

# Prune a directory list, removing subdirectories that are already under a higher-level directory
#  from another part of the list.
# Input:  A reference to an array of full directory paths.
#         A reference to an empty array to populate.
# Output: Output array (which is also the second input array) is populated with the pruned list of directories.
#
sub prune_dirs {
     my $self        = shift;
     my $input_dirs  = shift;
     my $output_dirs = shift;
     my @sorted_dirs;
     # We need to make sure that no directories are searched twice. i.e. if there's a dir "/home/user/public_html
     #                                                    then we don't want to also have "/home/user/public_html/myaddon.com
     @sorted_dirs = sort {length $a <=> length $b} (@{$input_dirs}); #Sort the directory list by length with the shortest first.
     my $dirflag = 0; # 0=No 
     foreach my $sorteddir (@sorted_dirs) {
          chomp($sorteddir);
          $dirflag = 0;
          foreach my $finaldir(@{$output_dirs}) {
               if ($sorteddir =~ /$finaldir/) {
                    #If the directory from the sorteddir list (the longer one) contains the dir we're checking on from the finaldir list,
                    # (i.e. it's under the finaldir we're checking) then exclude this sorteddir entry from the finaldir list.
                    $dirflag = 1;
                    last;
               }
          }
          if ($dirflag == 0) {
               push (@{$output_dirs}, $sorteddir);
          }
     }
     return;
}


# ------------------------------------------------------------------------------
# ----------------------------- General Subroutines ----------------------------
# ------------------------------------------------------------------------------

# Find the directory where the configuration file is.
# Input: Filename of the configuration file as passed to the program.
#        (i.e. configuration.php, /home/user/public_html/configuration.php, etc)
# Output: The directory it is in.
#        (i.e. /home/user/public_html)
sub finddirpath {
     my $configpath = abs_path($_[0]);
     #Find last "/" in the configpath and put its index into $lastloc.
     my $loc = 0;
     my $lastloc = 0; #Init the variable.
     while ($loc >= 0) {
          $lastloc = $loc;
          $loc = index($configpath, "/", $loc+1);
     }
     my $dirpath = substr $configpath,0,$lastloc;
     return $dirpath;
}

# Remove the directory where the configuration file is, leaving only the filename.
# Input: Filename of the configuration file as passed to the program.
#        (i.e. configuration.php, /home/user/public_html/configuration.php, etc)
# Output: The directory it is in.
#        (i.e. configuration.php)
sub removedirpath {
     my $configpath = abs_path($_[0]);
     #Find last "/" in the configpath and put its index into $lastloc.
     my $loc = 0;
     my $lastloc = 0; #Init the variable.
     while ($loc >= 0) {
          $lastloc = $loc;
          $loc = index($configpath, "/", $loc+1);
     }
     my $dirpath = substr $configpath, $lastloc+1, length($configpath);
     return $dirpath;
}

# Find the directory where the configuration file is.
# Input: Full directory path (i.e. /var/www/vhosts/mydomain.tld/httpdocs)
# Output: Rightmost directory chopped (i.e. /var/www/vhosts/mydomain.tld)
sub chopbottomdir {
     my $fullpath = $_[0];
     #Find last "/" in the fullpath and put its index into $lastloc.
     my $loc = 0;
     my $lastloc = 0; #Init the variable.
     while ($loc >= 0) {
          $lastloc = $loc;
          $loc = index($fullpath, "/", $loc+1);
     }
     my $dirpath = substr $fullpath,0,$lastloc;
     return $dirpath;
}

#Split a configuration line into an array.  Designed around Drupal config files.
#                                           Used also for Simple Machines Forum.
# Input: String such as:
#        $dbname = mydb;
#     or $dbname = 'mydb';
#     or $dbname = "mydb";
# Output: An array with (for example):
#        @array[0] = "$dbname = "
#        @array[0] = "mydb"
#        @array[0] = ";"
sub splitconfigline {
        my $line = $_[0];
        #Looking for somedbname in a line like ...= 'somedbname';
        #or                                    ...= somedbname;
        #or                                    ...= "somedbname";
        # index1 separates everything before somedbname from somedbname.
        my $index1 = index($line, "=");
        if (index($line, "'", $index1+1) > $index1) {
             $index1 = index($line, "'", $index1+1);
        }
        if (index($line, "\"", $index1+1) > $index1) {
             $index1 = index($line, "\"", $index1+1);
        }
        $index1 = $index1 + 1; # $index1 should now be the index of the last character before the db name.
        while (substr($line, $index1, 1) eq " " && $index1 < length($line)) { #Move past any spaces.
             $index1 = $index1 + 1;
        }
        my $index2 = $index1 + 1;
        while ($index2 < length($line) &&
               substr($line, $index2, 1) ne ";" &&
               substr($line, $index2, 1) ne " " &&
               substr($line, $index2, 1) ne "\"" &&
               substr($line, $index2, 1) ne "'") {
            $index2 = $index2 + 1;
        }
        #index2 should now be the index of the character just after the db name.
        push (my @list, substr($line, 0, $index1));                  
        push (@list, substr($line, $index1, $index2 - $index1));
        push (@list, substr($line, $index2, length($line)-$index2));
        return @list;
}

#Print or log the passed argument.
# Input:  A text string
# Output: If $self->{loggobj} is defined then log to the logg object.  Otherwise, print the info.
sub logg {
     my $self = shift;
     my $info_to_log = $_[0];
     my $loglevel    = $_[1];
     if ($self->{loggobj}) {
          $self->{loggobj}->logg($info_to_log, $loglevel);
     }else {
          print $info_to_log;
     }
     return 0;
}

# ------------------------------------------------------------------------------
# ------------------------- Packages used by dbclist ---------------------------
# ------------------------------------------------------------------------------

# Database Info class which is used to keep track of the details of one database.
package DBInfo;
use strict;

sub new {                          #Constructor
     my $class = shift;
     my $self  = {};
     $self->{name}            = $_[0]; #Database name (i.e. myuser_wp1).  This will match against the "olddb" member of the ConfigInfo class.
     $self->{fullname}        = $_[0]; #Full path to database.  If full path was provided, this will remain the same.  {name} will have path removed.
     $self->{dbfound}         = 0;
     bless($self, $class);
     $self->{name}            = dbconnect::removedirpath($self->{name});
     return $self;
}


# Config Info class which keeps track of the details of one configuration file.
package ConfigInfo;
use strict;

sub new {                          #Constructor
     my $class = shift;
     my $self  = {};
     $self->{configfile}      = $_[0];
     $self->{appname}         = undef; # Human readable php script name.
     $self->{olddb}           = undef; # Database name in config file before any changes.  This member will match against the "name" member of the DBInfo class.
     $self->{cpuser}          = undef; # cpuser is used for cPanel
     $self->{domain}          = undef; # domain is used in place of cpuser in Plesk.
     $self->{dbhost}          = undef; # Datbase Host name or IP of the database server (from the config file).
     $self->{dbuser}          = undef; # Database user (from the config file).
     $self->{password}        = undef; # Database password (from the config file).
     $self->{newdb}           = undef; # New database name (Used by dbconnect)
     $self->{tblcount}        = undef; # Number of tables in the database ((Used by dbchecker)
     $self->{DBC}             = undef; # Whether or not the db connection works (Used by dbchecker)
     $self->{errstr}          = undef; # Error string if connection doesn't work (Used by dbchecker)
}
###########
# logg Perl module
# A module that is used to log in /var/log/hgtransfer with optional printing to the screen.
# Please submit all bug reports at jira.endurance.com
# 
# Git URL for this module: NA yet.
# (C) 2011 - HostGator.com, LLC"
###########

=pod

=head1 Example usage for logg.pm:

 my $l = logg->new();
 $l->logg("Logging to the log file only.\n", 0);
 $l->logg("Logging to the log file and screen.\n", 1);

=cut

package logg;
use strict;

sub new {                          #Constructor
     my $class = shift;
     my $self  = {};
     $self->{class}         = $class;
     $self->{shortname}     = $_[0];  #Directory name passed when the object is instantiated.  Will be part of the workdir name.
     $self->{filename}      = undef;
     $self->{nolog}         = $_[1];  #This is the final work directory name created.
     $self->{sec}           = undef;  #--- Time related members
     $self->{min}           = undef;  #-
     $self->{hour}          = undef;  #-
     $self->{mday}          = undef;  #-
     $self->{mon}           = undef;  #-
     $self->{year}          = undef;  #-
     $self->{wday}          = undef;  #-
     $self->{yday}          = undef;  #-
     $self->{error}         = "";
     $self->{filehandle}    = undef;
     $self->{log_entries}   = [];     # Anything logged with a print flag of 3 is also saved in this array.
     bless($self, $class);

     ($self->{sec}, $self->{min}, $self->{hour}, $self->{mday}, $self->{mon}, $self->{year},
      $self->{wday}, $self->{yday}, $self->{isdst}) = localtime(time);

     if ($self->{nolog} == 0) {
          $self->{filename} = "/var/log/hgtransfer/" . $self->{shortname} . sprintf("%04d%02d%02d%02d%02d%02d", $self->{year}+1900, $self->{mon}+1, $self->{mday}, $self->{hour}, $self->{min}, $self->{sec});
          eval {
                    unless (-d "/var/log/hgtransfer") {
                         mkdir "/var/log/hgtransfer";
                    }
                    open ($self->{filehandle}, ">>$self->{filename}");
               } or do {
                    print "Error opening the log file: $self->{filename}";
                    return 1;
          };
          $self->logg ("Logging to $self->{filename}. See this log for more detail.\n", 1);
     }
     return $self;
}

# Print info. to the screen and log if the --logfile option was specified.
# Input: String of info. to print/log.
#        Print flag: 0=log only
#                    1=log and print to screen
#                    2=log and save to array
#                    3=log, print to screen and save to array.
# Output: Info. is printed and, if necessary, logged.
sub logg {
     my $self      = shift;
     my $data      = shift;
     my $printflag = shift;
     if ($self->{nolog} == 0) {
          print {$self->{filehandle}} $data;       #Send to log file if logging is on.
     }
     if (($printflag & 1) == 1) {
          print $data;               #Print to the screen
     }
     if (($printflag & 2) == 2) {
          push(@{$self->{log_entries}}, $data);          #Add to array.
     }
     return 0;
}

# Sort $self->{log_entries} then print them to the screen.
sub print_sorted_entries {
     my $self = shift;
     @{$self->{log_entries}} = sort(@{$self->{log_entries}});
     foreach my $line (@{$self->{log_entries}}) {
          print $line;
     }
}

# Print info. to the screen and log if the --logfile option was specified.
# Input: Ref to an array with lines to print.
#        Print flag: 0=log only
#                    1=log and print to screen
#                    2=log and save to array
#                    3=log, print to screen and save to array.
# Output: Info. is printed and, if necessary, logged.
sub loggarray {
     my $self      = shift;
     my $data      = shift;
     my $printflag = shift;
     foreach my $line (@{$data}) {
          $self->logg($line, $printflag);
     }
     return 0;
}

sub DESTROY {                        #Destructor.  Stop logging.
     my $self = shift;
     if ($self->{nolog} == 0) {
          close $self->{filehandle}; #Close the log file if we are logging to a file.
     }
}

1;
