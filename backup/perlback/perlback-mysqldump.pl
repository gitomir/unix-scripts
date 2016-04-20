#!/usr/bin/perl
#use strict;
#use warnings;
use DBI;
use DBD::mysql;
use Net::SSH::Perl;
use Net::SFTP::Foreign;
use Getopt::Long;
use Time::HiRes qw( time );
use Parallel::ForkManager;
use Digest::MD5; 
use File::Pid;
use Data::Dumper;
use Switch;

sub Usage{
        print "die, Unknown option: @_\n" if (@_);
        print "Usage: $0\n --verbose\tBe more social\n --nice-factor=<n>\tmysqldump niceness (default 17)\n";
        exit(0);
}

sub dumpsrv{
	my ($srv_id) = shift;

	my $dbhs = DBI->connect('DBI:mysql:perlback','perlback','Z9HAjA9GVXpLlGCxnd7S') || die "Cannot connect to db : $DBI::errstr";

	my $query = "SELECT srv_ip, srv_user, srv_name, mysql_user, mysql_pass, mysqldump_opts, srv_dumpdir FROM cfg WHERE id = ?";
	my $qh = $dbhs->prepare($query);
	$qh->execute($srv_id);
	
	my $rh = $qh->fetchrow_hashref;
	my $mu = $rh->{'mysql_user'};
	my $mp = $rh->{'mysql_pass'};
	my $mo = $rh->{'mysqldump_opts'};
	my $dd = $rh->{'srv_dumpdir'};
	my $dt = `date '+%d%b%Y'`; # TODO FIXME use perl / POSIX funct
	chomp($dt);
	my $srv_ip = $rh->{'srv_ip'};
	my $srv_us = $rh->{'srv_user'};
	my $srv_na = $rh->{'srv_name'};
	
	logtofile("[SSH] Logging to $srv_na [$srv_us\@$srv_ip:$dd] MySQL[$mu:********](OPTS: $mo)");

	my $ssh = Net::SSH::Perl->new($srv_ip, debug=>0, identity_files=>\@KEYFILE);
	$ssh->login($srv_us);# || logtofile("[SSH] FATAL! cannot login at $srv_na"); TODO FIXME detect login error
	#TODO adjust -j8 with actual cpu configuration for each server
	my $dumpcmd = "mysql -u$mu -p$mp -e 'show databases' -s --skip-column-names | egrep -v \"^(test|mysql|performance_schema|information_schema)\$\" | parallel --gnu -j8 \"mysqldump -u$mu -p$mp --routines $mo {} | lbzip2 > $dd/{}.$dt.bz2\"";

	logtofile("[CMD] [$ssh->{'host'}] Dumping DBs for $srv_ip to $dd");

	manifestdump('start', $srv_id, '','','');

	my $ts = time();
	my ($stdout_dump, $stderr_dump, $exit_dump) = $ssh->cmd($dumpcmd);
	my $te = time();
	my $tt = $te - $ts;

	if ($exit_dump != '0' || $stderr_dump){
		logtofile("[ERR] [$ssh->{'host'}] $stdout_dump $stderr_dump");
		manifesterror($srv_id, $dumpcmd, "ERR CODE:($exit_dump) STDOUT:$stdout_dump STDERR:$stderr_dump");
		return;
	}
	
	my $filecmd = "/usr/bin/du -Sb $dd/*$dt*";

	#FIXME FILE SIZE in KB
	#FILES NAMES are stored into an array
	my ($stdout_files, $stderr_files, $exit_files) = $ssh->cmd($filecmd);
	my (@files_names,$files_size);

	chomp($stdout_files);

	foreach (split(/\n/, $stdout_files)) {
		my ($fs,$fn) = (split(/\t/,$_));
		push (@files_names, $fn);
		$files_size += $fs;
	}

	if ($exit_files != '0' || $stderr_files) {
		logtofile("[ERR] [$ssh->{'host'}] $stdout_files $stderr_files");
		manifesterror($srv_id, $filecmd, "ERR CODE:($exit_files) STDOUT:$stdout_files STDERR:$stderr_files");
		return;
	}
	if ($exit_dump == '0' and $exit_files == '0') {
		#todo log success
		logtofile("[CMD] [$ssh->{'host'}] Dump OK took ".$tt."sec. total filesize ".$files_size."B");
		manifestdump('end', $srv_id, $tt, $files_size, @files_names); # SUCCESS!! array shoult be at the end of arguments
	}
	else {
	    	manifesterror($srv_id, 'OTHER', "[DUMP]ERR CODE:($exit_dump) STDOUT:$stdout_dump STDERR:$stderr_dump\n[FILES]ERR CODE:($exit_files) STDOUT:$stdout_files STDERR:$stderr_files");
	}

	$qh->finish;
	$dbhs->disconnect;
}

sub manifestdump{
    	my ($state, $srv_id, $tt, $size, @files_names) = @_;
	my $stxt;

	my $filelist = join(',',@files_names); # merge array into csv string
	my $dbhm = DBI->connect('DBI:mysql:perlback','perlback','Z9HAjA9GVXpLlGCxnd7S') || die "Cannot connect to db : $DBI::errstr";
	
	switch($state){
	    case "start" {
		$stxt = "inserted";
		my $query = "INSERT INTO dumps SET sid = ?, srv_id = ?, ts_start = UNIX_TIMESTAMP(), fetched = '0'";
		my $qh = $dbhm->prepare($query);
		$qh->execute($sid, $srv_id);
	    }
	    case "end" {
		$stxt = "updated";
		my $query = "UPDATE dumps SET time_exec = ?, size = ?, filelist = ?, ts_end = UNIX_TIMESTAMP() WHERE sid = ? AND srv_id = ?";
		my $qh = $dbhm->prepare($query);
		$qh->execute($tt, $size, $filelist, $sid, $srv_id);
	    }
	    else {
		logtofile("[SYS] Fatal error in manifestdump state switch.. DEAD");
		die();
	    }
	}

	if ($DBI::errstr) {
	    logtofile("[DBI] ERR CODE ($DBI::err) > $DBI::errstr");
	}else{
	    logtofile("[DBI] Sucessfully $stxt dump for srv_id $srv_id to DB");
	}

	$dbhm->disconnect;
}

sub manifestfetchdump{
    my ($dump_id, @files) = @_;

    my $dbhf = DBI->connect('DBI:mysql:perlback','perlback','Z9HAjA9GVXpLlGCxnd7S') || die "Cannot connect to db : $DBI::errstr";
    my $query = "UPDATE dumps SET fetched = '1' WHERE id = ?";
    my $qh = $dbhf->prepare($query);
    $qh->execute($dump_id);
    
    if ($dbhf->err){
	logtofile("[DBI] ERROR CODE ($DBI::err) > $DBI::errstr");
    }else{
	logtofile("[DBI] Sucessfuly updated dump_id=$dump_id to state='fetched'");
    }

    $qh->finish;
}

sub manifestfetchfile{
	my ($state, $dump_id, $remote_filepath, $local_filepath, $tt) = @_;
	my $stxt;	
	my $dbhf = DBI->connect('DBI:mysql:perlback','perlback','Z9HAjA9GVXpLlGCxnd7S') || die "Cannot connect to db : $DBI::errstr";

	switch($state){
	    case "start" {
		$stxt = "inserted";
		my $query = "INSERT INTO fetches SET dump_id = ?, filename_remote = ?, filename_local = ?, ts_start = UNIX_TIMESTAMP(), fetched = '0'";
		my $qh = $dbhf->prepare($query);
		$qh->execute($dump_id, $remote_filepath, $local_filepath);
	    }
	    case "end" {
		$stxt = "updated";
		my $query = "UPDATE fetches SET fetched = '1', ts_end = UNIX_TIMESTAMP(), time_exec = ? WHERE dump_id = ? AND filename_remote = ?";
		my $qh = $dbhf->prepare($query);
		$qh->execute($tt, $dump_id, $remote_filepath);
	    }
	    else {
		logtofile("[SYS] Fatal error switching the manifestfetchfile state .. DEAD");
		die();
	    }
	}

	if ($dbhf->err){ logtofile("[DBI] ERROR CODE ($DBI::err) > $DBI::errstr");}

#	logtofile("[DBI] Sucessfully $stxt record for dump_id $dump_id to DB");
	
	$dbhf->disconnect;
}

sub manifesterror{
	my ($srv_id, $error_stage, $error_text) = @_;

	my $dbhe = DBI->connect('DBI:mysql:perlback','perlback','Z9HAjA9GVXpLlGCxnd7S') || die "Cannot connect to db : $DBI::errstr";
	my $query = "INSERT INTO errors SET sid = ?, srv_id = ?, stage = ?, error = ?";
	my $qh = $dbhe->prepare($query);
	$qh->execute($sid, $srv_id, $error_stage, $error_text);

	if ($dbhe->err){
	    	logtofile("[DBI] ERROR CODE ($DBI::err) > $DBI::errstr");
	}else{
	    	logtofile("[DBI] Sucessfully inserted error to DB");
	}

	$qh->finish;
	$dbhe->disconnect;
}

sub fetchdump{
	my ($dump_id) = shift;
	
	my $dbhe = DBI->connect('DBI:mysql:perlback','perlback','Z9HAjA9GVXpLlGCxnd7S') || die "Cannot connect to db : $DBI::errstr";
	my $query = "SELECT dmp.id, dmp.size, dmp.filelist, dmp.srv_id, srv.srv_ip, srv.srv_user, srv.backup_dir FROM dumps dmp JOIN cfg srv on srv.id = dmp.srv_id WHERE dmp.id = ?";
	my $qh = $dbhe->prepare($query);
	$qh->execute($dump_id);

	my $rh = $qh->fetchrow_hashref;
	my $d_id = $rh->{'id'};
	my $d_size = $rh->{'size'};
	my $d_filelist = $rh->{'filelist'};
	my $d_srv_id = $rh->{'srv_id'};
	my $d_srv_ip = $rh->{'srv_ip'};
	my $d_srv_us = $rh->{'srv_user'};
	my $local_dir = $rh->{'backup_dir'};

	my @files = split /,/,$d_filelist; #put files to array

	#create sft session
	my $sftp = Net::SFTP::Foreign->new(host => $d_srv_ip, user => $d_srv_us, key_path => @KEYFILE, more => '-q');

	if ($sftp->error) {
	    	logtofile("[SYS] ERR SFTP Fatal -> ".$sftp->error);
		manifesterror($d_srv_id, "SFTP->CONNECT ($d_srv_us\@$d_srv_ip)",$sftp->error);
		return;
	}

	foreach $remote_filepath (@files) {
	    	my $local_filepath = $local_dir."/".(split '/', $remote_filepath)[-1];

		logtofile("[GET] [$d_srv_ip] [D:$d_id] $remote_filepath (".$d_size."KB) to $local_filepath");
		manifestfetchfile('start', $dump_id, $remote_filepath, $local_filepath, '');

		my $ts = time();
		$sftp->get($remote_filepath, $local_filepath); 
		my $te = time();
		my $tt = $te - $ts;

		if ($sftp->error) {
		    	logtofile("[GET] ERR fetching $remote_filepath from $d_srv_ip to $local_filepath");
			manifesterror($d_srv_id,"SFTP->GET ($d_id)$remote_filepath from ($d_srv_id)$d_srv_ip to $local_filepath",$sftp->error);
			return;
		}
		logtofile("[GOT] [$d_srv_ip] [D:$d_id] OK fetch $remote_filepath took $tt sec");
		manifestfetchfile('end', $dump_id, $remote_filepath, $local_filepath, $tt);
	}

	manifestfetchdump($dump_id,@files); #SUCCESS!


	#TODO Implement file size per file of whole dump (all files)
	$sftp->disconnect;

}

sub logtofile{ #todo, all logs to ref this func
	my (@logmsg) = @_;
	$| = 1; #make it hot
	print LOG localtime."\t@logmsg\n";
	$| = 0; #make it not
	return 1;
}


my ($help, $verbose, $nicefactor);

Usage() if (! GetOptions('verbose' => \$verbose, 'nice-factor=i' => \$nicefactor ) or defined $help);

#OPTs
if (!defined $nicefactor) { $nicefactor='17'; }
our $maxproc = 5;
our $logfile = "/var/log/perlback/perlback-mysqldump.log";
our $pidfile = "/var/run/perlback/perlback-mysqldump.pid";
our @KEYFILE = ("/root/.ssh/id_rsa"); #id_rsa for ssh auth
#Generate SID
our $sid = Digest::MD5::md5_base64( rand );

# CREATE PID FILE
my $pid = File::Pid->new( { file => $pidfile });
$pid->write || die ("Fatal: Cannot write to pid file ($pidfile)");

# OPEN LOG FILE
open (LOG, ">>$logfile") or die("Fatal: Cannot open log file ($logfile)");

logtofile("------------------- $0 STARTED sid($sid) pid($$)--------------------");

# MAINA
# DEF local vars
my ($dbh, $qh, $fm);
my ($ssh, $cmd, $stdout, $stderr, $exit);
my ($srv_id, $srv_name);

$fm = new Parallel::ForkManager($maxproc);

$fm->run_on_finish( sub {
	my ($pid, $exit_code, $ident) = @_;
	logtofile("[SYS] [$ident] just got out of the pool with PID $pid and exit code: $exit_code");
});

$fm->run_on_start( sub {
	my ($pid,$ident)=@_;
	logtofile("[SYS] [$ident] started, pid: $pid");
});

$fm->run_on_wait( sub {
	logtofile("[SYS] Waiting for one children ...");
	},1.5
);

#DUMP SRV
$dbh = DBI->connect('DBI:mysql:perlback','perlback','Z9HAjA9GVXpLlGCxnd7S', { RaiseError => 1, AutoCommit => 1, mysql_auto_reconnect=>1}) || die "Cannot connect to db : $DBI::errstr";
$qh = $dbh->prepare("SELECT id, srv_name  FROM cfg WHERE enabled='1' ORDER BY priority");
$qh->execute();
$qh->bind_columns(\$srv_id, \$srv_name);

logtofile("[CFG] Found ".$qh->rows." servers configured");

while ($qh->fetch()) { #server loop

	my $pid_dumpsrv = $fm->start("dumpsrv:$srv_name") and next; #fork a child proc foreach server

	dumpsrv($srv_id);

	$fm->finish; #close child
}

logtofile("[SYS] Waiting for Children after dumpsrv...");
$fm->wait_all_children;
logtofile("[SYS] Everybody is out of the pool (dumpsrv)!");

$qh->finish;

#TRANSFER DUMPS
$qh = $dbh->prepare("SELECT id, srv_id, filelist FROM dumps WHERE sid = ?");
$qh->execute($sid);
$qh->bind_columns(\$dump_id, \$dump_srv_id, \$dump_filelist);

logtofile("[CFG] Found ".$qh->rows." dumps from session $sid to be transferred to archive");

while ($qh->fetch()) { #dump loop

	my $pid_fetchdump = $fm->start("fetchdump:$srv_id:$dump_id") and next; #fork a child for each transfer

	fetchdump($dump_id);

	$fm->finish; #close child
}

logtofile("[SYS] Waiting for Children after dumpsrv...");
$fm->wait_all_children;
logtofile("[SYS] Everybody is out of the pool (fetchdump)!");

$qh->finish;

#VERIFY

#NOTHING TO DO
$dbh->disconnect || logtofile("[SYS] Error disconnecting from DB: $DBI::errstr");

#END
logtofile("-------------------- $0 ENDED sid($sid) --------------------");
close LOG;
$pid->remove if defined $pid;
