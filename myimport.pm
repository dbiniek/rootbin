###########
# myimport module
# Perl module that can used in other scripts that need the dbimport functionality.
# Please see how myimport is implemented, for an example on how to use this module.
# https://confluence.endurance.com/display/HGS2/MyImport
# https://stash.endurance.com/projects/HGADMIN/repos/myimport/browse
#
# (C) 2013 - HostGator.com, LLC
###########

package myimport;
use strict;
use Term::ANSIColor;
use LWP::UserAgent;

sub new {

	my $class = shift;
	my $self  = {};
	$self->{class}      = $class;
	$self->{dbname}     = shift;
	$self->{sqlfile}    = shift;
	$self->{iscpanel}   = 0;
	$self->{isplesk}    = 0;
	$self->{rootmysql}  = undef;
	$self->{rootmydump} = undef;
	$self->{fresh}      = shift;
	$self->{super}      = shift;
	$self->{usecs}      = shift;
	$self->{mysqlv}     = undef;
	$self->{prefix}     = undef;

	###For Clean up functionality...
	$self->{tempdbuser} = undef;
	$self->{unlist1}    = undef;
	$self->{unlist2}    = undef;
	$self->{cpuser}     = undef;

	bless($self, $class);
	return $self;
}

sub check_and_import {
	my $self    = shift;
	my $ret     = 0;

	if ( -s "/etc/psa/.psa.shadow" ){
		open(FILE, "</etc/psa/.psa.shadow");
		my $mysqlpass = do { local $/; <FILE> }; 
		chomp $mysqlpass;

		$self->{rootmysql} = "mysql -uadmin -p\'$mysqlpass\'";
		$self->{rootmydump} = "mysqldump -uadmin -p\'$mysqlpass\'";

		my $ver = `$self->{rootmysql} -ss -e \"select version();\"`;
		chomp $ver;
		$self->{mysqlv} = $ver;
		$self->{isplesk} = 1;
	} elsif ( -s "/usr/local/cpanel/cpanel"){
		$self->{rootmysql} = "mysql -uroot";
		$self->{rootmydump} = "mysqldump -uroot";
		my $ver = `$self->{rootmysql} -ss -e \"select version();\"`;
		chomp $ver;
		$self->{mysqlv} = $ver;

		$self->{iscpanel} = 1;

		# cPanel users can use > 8 char usernames. This just sets variables based on that.
		$self->{prefix} = (split(/_/, $self->{dbname}))[0];
		if (-e "/var/cpanel/users/$self->{prefix}") {
			$self->{cpuser} = $self->{prefix};
		} elsif (length($self->{prefix}) > 7) {
			open(my $FH, "<", "/etc/trueuserdomains");
			($self->{cpuser}) = grep { chomp; s/^[^:]+: (\Q$self->{prefix}\E.*)$/\1/ } <$FH>;
			close($FH);
		}
	} else {
		print "[!] Neither cPanel nor Plesk detected. You will be most likely prompted for the root mysql password.\n";
		$self->{rootmysql} = "mysql -uroot -p";
		$self->{rootmydump} = "mysqldump -uroot -p";

		my $ver = `$self->{rootmysql} -ss -e \"select version();\"`;
		chomp $ver;
		$self->{mysqlv} = $ver;
	}

	if (!-e "$self->{sqlfile}"){
		print "[!] The SQL file specified: '$self->{sqlfile}', does not exist.\n";
		return 1;
	}

	if (!($self->{sqlfile} =~ m/\.gz$/) && !($self->{sqlfile} =~ m/\.sql$/)){
		print "[!] Only .sql and .gz files are accepted... Rejecting $self->{sqlfile}\n";
		return 1;
	}

	if ($self->validdb()){ 
		if ($self->{iscpanel}){
			$self->{unlist1} = 1;
			$self->{unlist2} = 1;

			if ( $self->{cpuser} eq "" || ( !-e "/var/cpanel/users/$self->{cpuser}" ) ) {
				print "[*] Appears that the cPanel username could not be parsed from the database name. Skipping whitelisting procedures...\n";
				$ret = $self->dbimport();
				return $ret;
			}

			if (-e "/opt/hgmods/kill_usage2.pl"){
				if (!-e "/etc/kill_whitelist"){
					system("touch /etc/kill_whitelist");
				}
				open(my $killwhitelist, "<", "/etc/kill_whitelist");
				my $check1 = grep(/\b$self->{cpuser}\b/, <$killwhitelist>);
				close($killwhitelist);

				if ($check1){
					$self->{unlist1} = 0;
				} else {
					open my $whitelist, ">>", "/etc/kill_whitelist" or die "Could not open file: /etc/kill_whitelist";
					print $whitelist $self->{cpuser};
					close $whitelist;
				}
			} else {
				$self->{unlist1} = 0;
			}

			if (-e "/usr/local/hg_stats/mysql_kill.pl"){
				if (!-e "/etc/kill_dbwhitelist"){
					system("touch /etc/kill_dbwhitelist");
				}
				open(my $killdb, "<", "/etc/kill_dbwhitelist");
				my $check2 = grep(/\b$self->{cpuser}\b/, <$killdb>);
				close($killdb);

				if ($check2) {
					$self->{unlist2} = 0;
				} else {
					open my $whitelist1, ">>", "/etc/kill_dbwhitelist" or die "Could not open file: /etc/kill_dbwhitelist";
					print $whitelist1 $self->{cpuser};
					close $whitelist1;
				}
			} else {
				$self->{unlist2} = 0;
			}

			$ret = $self->dbimport();
			$self->cleanup($self->{unlist1}, $self->{unlist2}, $self->{cpuser});
			return $ret;
		} else {
			$ret = $self->dbimport();
			return $ret;
		}
	} else {
		print "[!] Sanity tests came back negative - Not proceeding.\n";
		return 1;
	}
	return 0;
}

sub validdb {

	my $self = shift;
	my $check = `$self->{rootmysql} -ss -e"show databases like \'$self->{dbname}\';"`;
	chomp $check;

	#free space check
	my $datadir = `$self->{rootmysql} -ss -e \"show variables like 'datadir';\"`;
	$datadir =~ s/datadir\s+//;
	chomp $datadir;

	my %df = get_df();
	my $mountp = mountinfo($datadir);
	my $freecheck;
	if (exists $df{$mountp}) {
		$freecheck = freecheck($df{$mountp});
	} else {
		$freecheck = freecheck($df{'/'});
	}

	if ($freecheck) {
		print "[!] ".color("red")."WARNING".color("reset").": The partition for MySQL's datadir ('$datadir') has less than 5 percent of disk space free! Proceed anyway? y/n - ";
		my $answer = <STDIN>;
		chomp $answer;
		if ($answer ne 'y'){
			return 0;
		}
	}

	if (!$self->baddb($self->{dbname})){
		if ($check eq "") {
			print "[*] $self->{dbname} does not exist on this server. Should I create it? y/n - ";
			my $answer = <STDIN>;
			chomp $answer;
			if ($answer ne 'y'){
				return 0;
			} else {
				if ($self->{isplesk}){
					my $ret = $self->createdbplesk($self->{dbname});
					return $ret;
				} elsif ($self->{iscpanel}){
					my $ret = $self->createdbcpanel($self->{dbname});
					return $ret;
				} else {
					print "[!] This server is not a cPanel or Plesk server. I am not smart enough to do this. Please create the database properly and try again.\n";
					return 0;
				}
			}
		} else {
			$datadir .= "/$self->{dbname}";
			if (-l $datadir) {
				print "[!] NOTE: ".color("green").$self->{dbname}.color("reset")." is currently SYMLINKED to ".color("red").readlink($datadir).color("reset")."!\n";
			}
			return 1;
		}
	}
	return 0;
}

sub createdbplesk {

	my $self = shift;
	my $dbname = $_[0];
	print "[*] Plesk server detected, in order to create the database properly, I will need the domain name under which this database needs to be setup.\n";
	print "[*] Domain name for $dbname: ";
	my $answer = <STDIN>;
	chomp $answer;
	if ($answer eq ""){
		print "[!] Invalid domain name...\n";
		return 0;
	} else {
		my $output = `/usr/local/psa/bin/database --create $dbname -domain $answer -type mysql 2>&1`;
		chomp $output;
		if (!$output){
			print "[+] Database successfully created: $dbname\n";
			return 0;
		} else {
			print "[!] Failed to create $dbname, error from plesk:\n";
			print "$output\n";
			return 1;
		}
	}
	return 1;
}

sub createdbcpanel {

	my $self = shift;
	my $database = $_[0];

	if ($self->{cpuser} eq "" || !-e "/var/cpanel/users/$self->{cpuser}"){
		print "[!] I was unable to parse a cPanel username out of the database name provided. I will only create databases under user accounts. If you are attempting something else, please create the database manually.\n";
		return 0;
	}

	system("$self->{rootmysql} -e \"CREATE database \\`$database\\`;\"");
	my $output = `/usr/local/cpanel/bin/dbmaptool $self->{cpuser} --type mysql --dbs \'$database\' 2>&1`;

	my $check = `$self->{rootmysql} -ss -e"show databases like \'$database\';"`;
	chomp $check;
	if ($check){
		return 1;
	} else {
		return 0;
	}
}

sub dbimport {

	my $self = shift;
	my $ret = 0;
	my $validgz = 0;

	if ($self->{sqlfile} =~ /.gz$/){
		my $chk = `file $self->{sqlfile}`;
		chomp $chk;
		if ($chk =~ m/gzip compressed data/){
			my $chk2 = `gunzip -cd $self->{sqlfile} | file -`;
			chomp $chk2;
			if ($chk2 =~ m/text, with very long lines$/){
				$validgz = 1;
			} else {
				print "[!] The content of GZip archive does not appear to be a MySQL file... Aborting\n";
				return 1;
			}
		} else {
			print "[!] The GZip file that was passed is not valid. Aborting...\n";
			return 1;
		}
	}

	my $newuser = "";	
	do { 
		$newuser = $self->randoms(8);
		if ($self->{iscpanel}){
			my ($prefix, $db) = split(/_/, $self->{dbname});
			if ( !($self->{cpuser} eq "") && ( -e "/var/cpanel/users/$self->{cpuser}" ) ) {
				$newuser = $prefix."_".$newuser;
				if (length($newuser) > 16){
					$newuser = substr($newuser, 0, 15);
				}
			}
		}
	} while($self->userexists($newuser));

	my $newpass = $self->randoms(8);
	$self->{tempdbuser} = $newuser;

	print "[*] Creating temporary dbuser: $newuser with password: $newpass\n";
	system("$self->{rootmysql} -e \"CREATE USER '$newuser'\@'localhost' IDENTIFIED BY '$newpass';\"");
	if ($self->{super}) {
		print "[*] Assigning SUPER privileges to $newuser..\n";
		system("$self->{rootmysql} -e \"GRANT SUPER ON \*.\* TO '$newuser'\@'localhost';\"");
	}
	system("$self->{rootmysql} -e \"GRANT ALL PRIVILEGES ON \\`$self->{dbname}\\`.\* TO '$newuser'\@'localhost'; flush privileges;\"");

	if ($self->{fresh} == 5) {	
		#both --fresh and --nobackup were passed
		print "[!] You requested that the database be dropped and no backup be made - Are you sure about this? y/n - ";
		my $answer = <STDIN>;
		chomp $answer;
		if (!($answer eq 'y')){
			return 1;
		}
		my $test2 = $self->redodb($self->{dbname});
		if ($test2) {
			print "[!] Errors found with recreating $self->{dbname} - Aborting.\n";
			return 1;
		}
		print "[*] No backup made! '$self->{dbname}' was recreated as requested!\n";
	} elsif ($self->{fresh} == 3){
		#print nothing out.
	} elsif ($self->{fresh} == 2) {
		my $test1 = $self->backdb($self->{dbname});
		my $test2;
		if (!$test1) {
			$test2 = $self->redodb($self->{dbname}); 
		} else {
			print "[!] Backup procedure for $self->{dbname} failed. Aborting.\n";
			return 1;
		}

		if ($test2){
			print "[!] Recreation process for $self->{dbname} failed. Aborting.\n";
			return 1;
		}
		print "[*] Dropped and recreated '$self->{dbname}' for a fresh import!\n";
	} else {
		my $test = $self->backdb($self->{dbname});
		if ($test){
			print "[!] Backup of $self->{dbname} failed!. Aborting.\n";
			return 1;
		}
	}

	print "[*] Database import of mysqldump file: '$self->{sqlfile}' to database: '$self->{dbname}' ... ";

	# temporarily increase max_allowed_packet settings to avoid issues with imports.
	my $curmaxsetting = `$self->{rootmysql} -ss -e \"show global variables like 'max_allowed_packet';\"`;
	chomp $curmaxsetting;
	$curmaxsetting =~ s/max_allowed_packet//g;
	$curmaxsetting =~ s/\s+//g;

	if ($curmaxsetting < 67108864 ) {
		system ("$self->{rootmysql} -e \"set global max_allowed_packet = 67108864;\"");
	}

	my $cmd;
	if ($validgz){
		$cmd = "gunzip -cd \"$self->{sqlfile}\" | mysql -u\'$newuser\' -p\'$newpass\' -fo $self->{dbname}";
	} else {
		$cmd = "mysql -u\'$newuser\' -p\'$newpass\' -fo $self->{dbname} \< \"$self->{sqlfile}\"";
	}

	if ($self->{usecs}) {
		$cmd .= " --default-character-set=\"$self->{usecs}\" 2>&1";
	} else {
		$cmd .= " 2>&1";
	}

	my $output = `$cmd`;

	if (!$output || ($output =~ /^Warning: Using a password on the command line interface can be insecure\.$/)){
		print color("green")."Completed!".color("reset")." No errors to report.\n";
		$ret = 0;
	} else {
		print color("red")."\n[!] Database import came back with errors ".color("reset")."- $self->{sqlfile} to $self->{dbname}: \n";
		print scalar($output)."\n";
		$ret = 1;
	}

	system("$self->{rootmysql} -e \"set global max_allowed_packet = $curmaxsetting;\"");
	system("$self->{rootmysql} -e \"DROP USER '$newuser'\@'localhost'; flush privileges\"");
	return $ret;
}

sub redodb {

	my $self = shift;
	my $dbname = $_[0];
	
	my $output1 = `$self->{rootmysql} -e \"DROP DATABASE \\\`$dbname\\\`;\" 2>&1`;
	chomp $output1;
	if ($output1){
		print "[!] Failed to drop database: $dbname\n";
		print "$output1\n";
		return 1;
	}
	my $output2 = `$self->{rootmysql} -e \"CREATE DATABASE \\\`$dbname\\\`;\" 2>&1`;
	chomp $output2;
	if ($output2){
		print "[!] Failed to re-create database: $dbname\n";
		print "$output2\n";
		return 1;
	}
	return 0;
}

sub backdb {

	my $self = shift;
	my $dbname = $_[0];
	my $dbsize;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	my $date = sprintf("%4d%02d%02d",$year+1900,$mon+1,$mday);

	my $bkupdir;
	if (-w "/home/hgtransfer") {
		$bkupdir="/home/hgtransfer";
	} else  {
		$bkupdir="/home1/hgtransfer";
	}

	my $backupfile = "$bkupdir/myimport-backups-$date/$dbname.sql";
	my $dbtbls = `$self->{rootmysql} -ss -e \"show tables;\" '$dbname' | wc -l`;
	chomp $dbtbls;

	if ($self->{mysqlv} =~ m/^4.*/) {
		return dobackup($backupfile);
	}
		
	if ($dbtbls != 0) {

		my @dbtype = `$self->{rootmysql} -ss -e \"SELECT engine FROM INFORMATION_SCHEMA.TABLES WHERE table_schema=DATABASE();\" '$dbname'`;
	
		my $isInno = 0;
		foreach my $entry (@dbtype){
			if ($entry =~ m/InnoDB/){
				$isInno = 1;
			}
		}
	
		if ($isInno){
			$dbsize = `$self->{rootmysql} -ss -e \"SELECT CONCAT(sum(ROUND(((DATA_LENGTH + INDEX_LENGTH) / 1024 / 1024),2))) AS Size FROM INFORMATION_SCHEMA.TABLES where TABLE_SCHEMA = '$dbname';\"`;
			chomp $dbsize;
		} else {
			my $datadir = `$self->{rootmysql} -ss -e \"show variables like 'datadir';\"`;
			$datadir =~ s/datadir\s+//;
			chomp $datadir;
			$datadir .= "$dbname/";

			if (-d "$datadir"){
				my $datadu = `du -b $datadir 2>&1`;
				$datadu =~ s/$datadir//;
				chomp $datadu;
				$dbsize = sprintf("%.2f", ($datadu / 1024 / 1024));
			} else {
				print "[!] Unable to determine the datadir for '$dbname', therefore unable to determine db size properly.\n";
				print "[!] This is typical when the database name has hyphens, and other 'special' characters in it.\n";
				print "[*] Skip the backup process? (if 'n' then an attempt to backup the database with mysqldump will be made) - y/n - ";
				my $answer = <STDIN>;
				chomp $answer;
				if ($answer eq 'y'){
					print "[*] Skipping backup process per user input.\n";
					return 0;
				} elsif ($answer eq 'n') {
					$dbsize = 0.00;
				} else {
					print "[!] Aborting due to improper user input\n";
					return 1;
				}
			}
		}
	} else {
		print "[+] '$dbname' is empty, so skipping backup process\n";
		return 0;
	}

	if ($dbsize > 100.00){
		print "[!] '$dbname' is too large, $dbsize MB, to backup automatically - Please make sure you have backed this up manually. Proceed? y/n - ";
		my $answer = <STDIN>;
		chomp $answer;
		if ($answer eq 'y'){
			return 0;
		} else {
			return 1;
		}
	}

	return dobackup($backupfile);

	sub dobackup {

		my $backupfile = shift;
		my @dirs = split(/\//, $backupfile);
		pop (@dirs);
		my $backdir = join("/", @dirs);

		if (!-d "$backdir"){
			system("mkdir -p $backdir");
			if (!-d "$backdir") {
				print "[!] Failed to create $backdir - Unable to backup Databases properly. Aborting!\n";
				return 1;
			}
		}

		do {
			my $x = sprintf("%4d-%02d-%02d-%02d-%02d-%02d",$year+1900,$mon+1,$mday, $hour, $min, $sec);
			$backupfile =~ s|$dbname|$dbname.$x|i;
		} while (-e "$backupfile");

		my $backup = `$self->{rootmydump} $dbname > $backupfile 2>&1`;
		chomp $backup;

		if ($backup){
			print "[!] Backing up of $dbname failed. Errors:\n";
			print "$backup\n";
			return 1;
		} else {
			print "[+] Backup successful: $dbname to $backupfile\n";
			return 0;
		}
	}
}

sub cleanup {

	my $self = shift;
	my $check1 = $_[0];
	my $check2 = $_[1];
	my $cpuser = $_[2];

	if ($check1) {
		system("sed -i 's|\\s*$cpuser\\s*||g' /etc/kill_whitelist");
	}

	if ($check2) {
		system("sed -i 's|\\s*$cpuser\\s*||g' /etc/kill_dbwhitelist");
	}
}

sub userexists {

	my $self   = shift;
	my $dbuser = shift;

	my $check = `$self->{rootmysql} -ss -e"SELECT user FROM mysql.user WHERE user=\'$dbuser\';"`;
	if ($check){
		return 1;
	} else {
		return 0;
	}
}

sub get_df {

	my %df;
	my @output = grep(/^\/dev/, `df -Pl`);
	foreach my $dev (@output) {
		my @splitz = split(/\s+/, $dev);
		my $mount = lc $splitz[5];
		my $free  = lc $splitz[4];
		$df{$mount} = $free;
	}

	return %df;
}

sub mountinfo {

	my $dir = $_[0];
	my $mountpoint = (split(/\//, $dir))[1];
	return "/$mountpoint";
}

sub randoms {

        my $self = shift;
	my $limit = $_[0];
	my $possible = 'abcdefghijkmnpqrstuvwxyz';
	my $string = "";

	while (length($string) < $limit){
		$string .= substr( $possible, ( int( rand( length($possible) ) ) ), 1 );
	}

	return $string;
}

sub freecheck {

	my $freepercent = $_[0];
	$freepercent =~ s/[^0-9]//g;
	$freepercent = 100 - $freepercent;

	if ($freepercent < 5) {
		return 1;
	} else {
		return 0;
	}
}

sub interrupt {

	my $self = shift;
	print "\n[!] Interrupt caught. Cleaning up and exiting...\n";
	$self->cleansql();
	$self->cleanup($self->{unlist1}, $self->{unlist2}, $self->{cpuser});

	exit(1);
}	

sub cleansql {

	my $self = shift;
	my @myqueries = grep(/$self->{tempdbuser}/, `mysql -ss -e \'show processlist;\'`);
	foreach my $query (@myqueries) {
		my $id = (split(/\s/, $query))[0];
		system("$self->{rootmysql} -e \"kill $id;\"");
	}
	if ($self->{tempdbuser}) {
		system("$self->{rootmysql} -e \"DROP USER '$self->{tempdbuser}'\@'localhost'; flush privileges\"");
	}
}

sub baddb {

        my $self = shift;
	my $u = $_[0];
	my @badnames = qw / mysql roundcube horde information_schema cphulkd eximstats modsec leechprotect psa /;
	return exists {map { $_ => 1 } @badnames}->{$u};
}

1;
