#!/usr/bin/perl
#

use DBI;
use Data::Dumper;

my $dbh = DBI->connect("dbi:CSV:","","", 
	{AutoCommit => 1, RaiseError => 1, f_dir => "./",f_ext => ".csv/r", csv_eol => "\n", csv_sep_char => ";", csv_tables => {hb => {f_file => "hb_log.csv"}, log1 => {f_file => "log1.csv"}} }) or die ("cannot connect! $DBI::errstr\n");

#my $sth = $dbh->prepare("SELECT col1 from log1");


#$sth->execute();

#my $value = $sth->fetchrow_array;

#$dbh->do ("CREATE TABLE PRONO (id INTEGER, col1 INTEGER, col2 INTEGER, date CHAR (64))");
#$dbh->do ("INSERT INTO asd VALUES(1,2,3,4)");
#$dbh->do ("INSERT INTO asd VALUES(2,2,3,4)");


open(MYF, '>>hb_new.csv');

my $query = "SELECT * FROM hb";
my $sth   = $dbh->prepare ($query);
$sth->execute ();
while (my $row = $sth->fetchrow_hashref) {
	print MYF $row->{h},":", $row->{m},";",$row->{c1},";",$row->{c2},"\n";
	#print Dumper($row);

}

close(MYF);
$sth->finish ();
$dbh->disconnect();
