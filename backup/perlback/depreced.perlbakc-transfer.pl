#!/usr/bin/perl
#use strict;
#use warnings;
use DBI;
use DBD::mysql;
use Net::SFTP::Foreign;
use Getopt::Long;
use Data::Dumper;

my ($help, $verbose, $skipdbsizecalcul, $logfile);
my ($dbh, $qh, $query_dumps, $dump_id, $srv_id, $db_id, $dump_filename);

$| = 1; #google suffering from buffering

@KEYFILE = ("/root/.ssh/id_rsa"); #id_rsa for ssh auth

Usage() if (! GetOptions('verbose' => \$verbose) or defined $help);

# OPEN LOG FILE
$logfile = "/var/log/perlback/perlback-transfer.log";
open (LOG, ">$logfile") or die("Fatal: Cannot open log file");

logtofile("------------------- $0 STARTED --------------------");

sub Usage{
	print "die, Unknown option: @_\n" if (@_);
        print "Usage: $0 --verbose (Be more social) --skip-db-size-calcul (Skip DB size calculation, faster execution)\n";
	exit(0);
}

sub logtofile{ #todo, all logs to ref this func
        my (@logmsg) = @_;
	print LOG localtime."\t@logmsg\n";
	return 1;
}

sub copyarchive{
	my ($dbh, $dump_id) = @_;

	my ($sftp, $srv_ip, $srv_user, $backup_dir, $remote_abs_filename, $remote_filename, $local_abs_filename, $dump_size, $local_size, $query, $qh, $hash);

	$query = "SELECT srv_ip, srv_user, backup_dir FROM cfg WHERE id = (SELECT srv_id FROM dumps WHERE id = ?)"; #Query to get server credentials
	$qh = $dbh->prepare($query);
	$qh->execute($dump_id);

	$hash = $qh->fetchrow_hashref;

	$srv_ip = $hash->{'srv_ip'};
	$srv_user = $hash->{'srv_user'};
	$backup_dir = $hash->{'backup_dir'};

	$query = "SELECT dump_filename, dump_size FROM dumps WHERE id = ?"; #Query to get filename and store path
	$qh = $dbh->prepare($query);
	$qh->execute($dump_id);

	$hash = $qh->fetchrow_hashref;

	$remote_abs_filename = $hash->{'dump_filename'};
	$dump_size = $hash->{'dump_size'};

	if ($dump_size < 1) {
	    logtofile("[CFG] Found record for dump id($dump_id) with $dump_size size! Check mysqldumper!");
	    return;
	}

	$sftp = Net::SFTP::Foreign->new(host=>$srv_ip, user=>$srv_user, key_path=>@KEYFILE, ssh_cmd=>"/usr/bin/ssh", more=>"-q");
	if ($sftp->error != '0') { logtofile ("[SFTP] ".$sftp->error); }

	$remote_filename = (split '/', $remote_abs_filename)[-1]; #get the last element in path
	$local_abs_filename = $backup_dir."/".$remote_filename;
	logtofile("[SFTP] Transferring remote[$remote_abs_filename] to local[$local_abs_filename] size[$dump_size]");

	$sftp->get($remote_abs_filename,$local_abs_filename);
	if ($sftp->error != '0') { 
	    logtofile ("[SFTP] ".$sftp->error);
	    return;
	}
	
	$local_size = `/usr/bin/stat -c %s $local_abs_filename`;
	
	if ($dump_size == $local_size) {
		logtofile("[SYS] Matched dump size $dump_size to $local_size");
		updatearchive($dbh,$dump_id,'1'); #1 is for success
	}
	else {
	    	logtofile("[SYS] Missmatched dump size $dump_size to $local_size");
		updatearchive($dbh,$dump_id,'X'); #X is for size missmatch
		return;
	}

	$sftp->disconnect();
}

sub updatearchive{
	my ($dbh, $dump_id, $trans_code) = @_;
	my ($query, $qh, $hash);

	$query = "UPDATE dumps SET trans_code = ?, trans_timestamp=NOW() WHERE id = ?";
	$qh = $dbh->prepare($query);
	$qh->execute($trans_code,$dump_id);

	if ($trans_code == '1') {
	    	$trans_text = "transferred";
	}
	elsif ($trans_code == 'X') {
	    	$trans_text = "size missmatched";
	}
	
	logtofile("[SQL] Updated record for dump id($dump_id) as $trans_text");
}

# MAINA 

$dbh = DBI->connect('DBI:mysql:perlback','perlback','Z9HAjA9GVXpLlGCxnd7S') || die "Cannot connect to db : $DBI::errstr";

$query_dumps = "SELECT id FROM dumps WHERE result_code = '1' and trans_code = '0'";

$qh = $dbh->prepare($query_dumps);
$qh->execute();

$qh->bind_columns(\$dump_id);

logtofile("[CFG] Found ".$qh->rows." dumps to be transferred");

while ($qh->fetch()) { #server loop

#	logtofile("[CFG] Transferring $dump_id:$dump_filename from $srv_id:$db_id"); #TODO add srvid2name, dbid2name
	copyarchive($dbh, $dump_id);


}

#END
logtofile("-------------------- $0 END --------------------");

