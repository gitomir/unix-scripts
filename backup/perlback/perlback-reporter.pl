#!/usr/bin/perl
#use strict;
#use warnings;
use POSIX qw( strftime );
use DBI;
use DBD::mysql;
use Getopt::Long;
use Data::Dumper;
use MIME::Lite;
use Format::Human::Bytes;

my ($help, $verbose, $skipdbsizecalcul, $logfile);

$| = 1; #google suffering from buffering

Usage() if (! GetOptions('verbose' => \$verbose) or defined $help);

# OPEN LOG FILE
$logfile = "/var/log/perlback/perlback-reporter.log";
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

sub generatetmplogfile{
    my ($sid,$dt) = @_;
    my $output = `cat /var/log/perlback/perlback-mysqldump.log |  sed -n '/STARTED sid($sid/,/ENDED sid($sid/p' > /sofia-nas/cronjobs/perlback/reports/perlback-mysql-$dt.log`;
    return "perlback-mysql-$dt.log";
}

sub striplogforjobid{
    my ($jobid, $dbh_b) = @_;
    $query = "SELECT Time, LogText FROM Log WHERE JobId = ?";
    my $qh = $dbh_b->prepare($query);
       $qh->execute($jobid);
    my $result = $qh->fetchall_arrayref;
    return $result;
}

sub checksidforerrors{
	my ($sid, $dbh) = @_;
	my $query = "SELECT srv_id, stage, error FROM errors WHERE sid = ?";
	my $qh = $dbh->prepare($query);
	   $qh->execute($sid);
	my $result = $qh->fetchall_arrayref;
	return $result;
}

sub checksrvidforerrorspersid{
    	my ($sid, $srv_id, $dbh) = @_;
	my $query = "SELECT COUNT(id) AS CNT FROM errors WHERE sid = ? AND srv_id = ?";
	my $qh = $dbh->prepare($query);
	   $qh->execute($sid,$srv_id);
	my $result = $qh->fetchrow_hashref();
	return $result->{'CNT'};
}

sub countfetchesfordump{
    my ($dump_id,$dbh) = @_;
    my $query = "SELECT COUNT(id) AS CNT FROM fetches WHERE dump_id = ?";
    my $qh = $dbh->prepare($query);
       $qh->execute($dump_id);
    my $result = $qh->fetchrow_hashref;
    return $result->{'CNT'};
}

# MAINA 

$msg_head = "	<head>
		<style>
			table, tr.h, td { border: 1px solid black; font-size: 1em;}
			table { border-collapse: collapse; width: 100%; }
			tr.h { background-color: #A7C942; color: #FFFFFF; padding-top: 4px; padding-bottom: 3px; text-align: center; vertical-align: center;}
			tr.e { background-color: #B40404; color: #FFFFFF; padding-top: 4px; padding-bottom: 3px; text-align: center; vertical-align: center;}
			tr.y { background-color: #F3F781; color: #000000; padding-top: 4px; padding-bottom: 3px; text-align: center; vertical-align: center;}
			tr { background-color: #FFFFFF; color: #000000; padding-top: 4px; padding-bottom: 3px; text-align: center; vertical-align: center;}
			td { text-align: center; vertical-align: center; padding: 6px;}
			td.l { text-align: left; vertical-align: center; padding: 6px;}
			td.r { text-align: right; vertical-align: center; padding: 6px;}
			h3 { text-align: center; font-size: 1em; text-decoration: underline;}
		</style>
		</head>";

my $bh = Format::Human::Bytes->new();

my $dbh = DBI->connect('DBI:mysql:perlback','perlback','Z9HAjA9GVXpLlGCxnd7S') || die "Cannot connect to db : $DBI::errstr";

my $query_lastrun = "SELECT timestamp FROM reports ORDER BY id desc LIMIT 1";

my $qh = $dbh->prepare($query_lastrun);
   $qh->execute();
my $result = $qh->fetchrow_hashref();
my $lastrun_ts = $result->{'timestamp'};
undef $result; undef $qh;

my $sid = 'ZQ3ntonhpLH2Kim17qKGzQ';

#my $query_dumps = "SELECT d.id, d.sid, s.srv_ip, d.time_taken, d.time_exec, d.size FROM dumps d, cfg s WHERE d.srv_id = s.id AND d.time_taken > ?;";
my $query_dumps = "SELECT d.id, d.sid, s.id, s.srv_ip, s.srv_name, d.ts_start, d.ts_end, SEC_TO_TIME(d.time_exec), d.size FROM dumps d, cfg s WHERE d.srv_id = s.id AND d.sid = ?;";
my $qh = $dbh->prepare($query_dumps);
#   $qh->execute($lastrun_ts);
   $qh->execute($sid);
   $qh->bind_columns(\$d_id, \$d_sid, \$d_srv_id, \$d_srv_ip, \$d_srv_name, \$d_ts_start, \$d_ts_end, \$d_time_ex, \$d_size );

my $dt = `date '+%d%b%Y'`;
chomp $dt;


#generate info table
$msg_body = "<h3>Database Backup Report for session $sid / $dt</h3><table width=\"600px\">
		<tr class=\"h\">
			<td><b>Server</b></td>
			<td><b>IP</b></td>
			<td><b>Start</b></td>
			<td><b>End</b></td>
			<td><b>Duration</b></td>
			<td><b>Size</b></td>
			<td><b>Count DBs</b></td>
			<td><b>Errors</b></td>
		</tr>
		";
my $etr;
while ($qh->fetch()) { #server loop

    	$d_ts_start = strftime("%H:%M:%S",localtime($d_ts_start));
	$d_ts_end = strftime("%H:%M:%S",localtime($d_ts_end));
	my $errors = checksrvidforerrorspersid($d_sid, $d_srv_id, $dbh);
	my $cnt_dbs = countfetchesfordump($d_id, $dbh);
	if ($errors > 0) {
	    $etr="Y";
	    $msg_body = $msg_body."<tr class=\"e\"><td class=\"l\">$d_srv_name</td><td>$d_srv_ip</td><td>$d_ts_start</td><td>$d_ts_end</td><td>$d_time_ex</td><td class=\"r\">".$bh->base2($d_size,2)."</td><td>$cnt_dbs</td><td>$errors</td></tr>";
	}
	else {
	    $msg_body = $msg_body."<tr><td class=\"l\">$d_srv_name</td><td>$d_srv_ip</td><td>$d_ts_start</td><td>$d_ts_end</td><td>$d_time_ex</td><td class=\"r\">".$bh->base2($d_size,2)."</td><td>$cnt_dbs</td><td>$errors</td></tr>";
	}
}

undef $qh;

$msg_body = $msg_body."</table>";

#generate errors table
if ($etr eq "Y"){
	$msg_body = $msg_body."<br/><br/><h3>Backup Error Report for session $sid / $dt</h3>";
	$msg_body = $msg_body."<table width=\"600px\">
		<tr class=\"h\">
			<td><b>Server</b></td>
			<td><b>IP</b></td>
			<td><b>Stage</b></td>
			<td><b>Error</b></td>
		</tr>
		";


	my $query_errors = "SELECT s.srv_name, s.srv_ip, e.stage, e.error FROM cfg s, errors e WHERE e.srv_id = s.id AND e.sid = ?";
	my $qh = $dbh->prepare($query_errors);
	   $qh->execute('ZQ3ntonhpLH2Kim17qKGzQ');
	   $qh->bind_columns(\$e_srv_name, \$e_srv_ip, \$e_stage, \$e_error);

	while ($qh->fetch()) { #error loop
	    $msg_body = $msg_body."<tr><td class=\"l\">$e_srv_name</td><td>$e_srv_ip</td><td class=\"l\">$e_stage</td><td class=\"l\">$e_error</td></tr>";
	}

	$msg_body = $msg_body."</table>";
}

#generate bacula report
$msg_body = $msg_body."<br/><br/><hr/><br/><br/><h3>Systems Backup Report (Bacula) for $dt</h3>";
$msg_body = $msg_body."<table width=\"600px\">
		<tr class=\"h\">
			<td><b>Client Name</b></td>
			<td><b>FileSet:Type</b></td>
			<td><b>Start</b></td>
			<td><b>End</b></td>
			<td><b>Duration</b></td>
			<td><b>Files</b></td>
			<td><b>Size</b></td>
			<td><b>Errors</b></td>
		</tr>
		";

my $dbh_b = DBI->connect('DBI:mysql:bacula','bacula','crim73') || die "Cannot connect to db : $DBI::errstr";

my $query_bacula = "SELECT Job.JobId, Client.Name AS client, FileSet.FileSet AS fileset, Level AS level, DATE_FORMAT(StartTime,'%H:%i:%s') AS starttime, DATE_FORMAT(EndTime,'%H:%i:%s') AS endtime, 
		SEC_TO_TIME(UNIX_TIMESTAMP(EndTime) - UNIX_TIMESTAMP(StartTime)) AS duration, JobFiles AS jobfiles, JobBytes AS jobbytes, JobStatus AS jobstatus, JobErrors AS joberrors  
	FROM Client, Job  LEFT JOIN FileSet  ON (Job.FileSetId = FileSet.FileSetId) 
	WHERE Client.ClientId=Job.ClientId AND ( UNIX_TIMESTAMP(starttime) > ( UNIX_TIMESTAMP(NOW()) - (86400)  ) OR starttime = '0000-00-00 00:00:00' ) 
	ORDER BY JobStatus, JobErrors DESC;";

my $qh_b = $dbh_b->prepare($query_bacula);
   $qh_b->execute();
   $qh_b->bind_columns(\$b_jobid, \$b_client, \$b_fileset, \$b_level, \$b_starttime, \$b_endtime, \$b_duration, \$b_jobfiles, \$b_jobbytes, \$b_jobstatus,\$b_errors);

while ($qh_b->fetch()) { #bacula loop
    
    $b_logs{$b_jobid} = striplogforjobid($b_jobid,$dbh_b);
    
    if ($b_jobstatus eq "T") {
	$msg_body = $msg_body."<tr><td class=\"l\">$b_client</td><td class=\"l\">$b_fileset:$b_level</td><td>$b_starttime</td><td>$b_endtime</td><td>$b_duration</td><td>$b_jobfiles</td><td class=\"r\">".$bh->base2($b_jobbytes,2)."</td><td>$b_errors</td></tr>";
    }
    else {
	$msg_body = $msg_body."<tr class=\"y\"><td class=\"l\">$b_client</td><td class=\"l\">$b_fileset:$b_level</td><td>$b_starttime</td><td>$b_endtime</td><td>$b_duration</td><td>$b_jobfiles</td><td class=\"r\">".$bh->base2($b_jobbytes,2)."</td><td>$b_errors</td></tr>";
    }
}


#TODO ponedelnik aggregate bacula logs
#print Dumper $b_logs{'674'};exit;

#generate log file for today in reports dir
my $tmp_logfile = generatetmplogfile($d_sid, $dt);
#my $tmp_bacfile = generatetmpbacfile($jobids);

# CREATE MAIL
if ($etr eq "Y") { $bkp_state = "ERR"; }
else { $bkp_state = "OK"; }

my $mail_subject = "[BACKUP][$bkp_state] Report for $dt";

$MIME::Lite::AUTO_CONTENT_TYPE = 1;
my $mail_msg = MIME::Lite->new(
    From	=>	'nas.relay@axsmarine.com',
    To		=>	'miroslav.nikolov@axsmarine.com',
    Subject	=>	$mail_subject,
    Encoding	=>	'8bit',
    Type	=>	'multipart/mixed') or die "Cannot build Mail $!";

$mail_msg->attach(
    Type	=>	'text/html',
    Data	=>	qq{
    				$msg_head
    				<body>
				$msg_body
				</body>
    }) or die "Cannot attach mail body $!";
$mail_msg->attach(
    Type	=>	'AUTO',
    Disposition	=>	'attachment',
    Encoding	=>	'quoted-printable',
    Filename	=>	"perlback.log",
    Path	=>	"/sofia-nas/cronjobs/perlback/reports/$tmp_logfile") or die ("Cannot attach tmp logfile $!");

$mail_msg->send('sendmail','localhost', Debug=>1);
#END
logtofile("-------------------- $0 END --------------------");

