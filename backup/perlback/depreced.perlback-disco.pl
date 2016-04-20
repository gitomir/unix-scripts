#!/usr/bin/perl
#use strict;
#use warnings;
use DBI;
use DBD::mysql;
use Net::SSH::Perl;
use Getopt::Long;
use Data::Dumper;

my ($help, $verbose, $skipdbsizecalcul, $logfile);

@KEYFILE = ("/root/.ssh/id_rsa"); #id_rsa for ssh auth

Usage() if (! GetOptions('verbose' => \$verbose, 'skip-db-size-calcul' => \$skipdbsizecalcul) or defined $help);

# OPEN LOG FILE
$logfile = "/var/log/perlback/perlback-disco.log";
open (LOG, ">$logfile") or die("Fatal: Cannot open log file");

sub Usage{
        print "die, Unknown option: @_\n" if (@_);
        print "Usage: $0 --verbose (Be more social) --skip-db-size-calcul (Skip DB size calculation, faster execution)\n";
        exit(0);
}

# MAINA 
# DEF local vars
my ($dbh, $query_cfg, $query_size, $query_insert, $qh);
my ($ssh, $cmd, $stdout, $stderr, $exit);
my ($srv_name, $srv_ip, $srv_user, $mysql_user, $mysql_pass, $ks, $ds, $tmpq, @tmpa);
my %resulthash;

$query_cfg = "SELECT srv_name, srv_ip, srv_user, mysql_user, mysql_pass FROM cfg WHERE enabled = '1' ORDER BY priority ASC";

if (defined $skipdbsizecalcul) {
	$query_size = "SHOW DATABASES";	
}
else {
	$query_size = "SELECT table_schema \"DB\", sum( data_length + index_length ) / 1024 / 1024 \"Size\" FROM information_schema.TABLES GROUP BY table_schema"; 
}

$dbh = DBI->connect('DBI:mysql:perlback','perlback','Z9HAjA9GVXpLlGCxnd7S') || die "Cannot connect to db : $DBI::errstr";

$qh = $dbh->prepare($query_cfg);
$qh->execute();

$qh->bind_columns(\$srv_name, \$srv_ip, \$srv_user, \$mysql_user, \$mysql_pass);

# Cycle trough servers and get databases

while ($qh->fetch()) {
	@resultarray=();
	if (defined $verbose) { print "SRV[$srv_name->$srv_user\@$srv_ip] MySQL[$mysql_user:$mysql_pass]\n"; }
	$ssh = Net::SSH::Perl->new($srv_ip, debug=>$verbose, identity_files=>\@KEYFILE);
	$ssh->login($srv_user);
	$cmd = "mysql -u$mysql_user -p$mysql_pass -e '$query_size'";
	($stdout, $stderr, $exit) = $ssh->cmd($cmd);
	#todo check exit code

	foreach (split(/\n/,$stdout)) {
		push (@resultarray,$_);
	}

	$resulthash->{ $srv_name } = join(',', @resultarray);
}

# Put databases name into local dbs database

#print Dumper($resulthash);

while (($ks, $ds) = each $resulthash) {
	@tmpa = (); #temporary array to hold databases
	@tmpa = split(',',$ds);

	foreach (@tmpa) {
		$tmpq = (); #temporary string to hold each insert query
		$tmpq = "INSERT IGNORE INTO dbs SET srv_id=(SELECT id FROM cfg WHERE srv_name='$ks'), db_name='$_'"; #if srv_id and db_name constraint already exists, will ignore
		if (defined $verbose) { print "[SQL]\t$tmpq\n"; }
		$qh = $dbh->prepare($tmpq);
		$qh->execute();
	}
} 
