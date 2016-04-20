#!/usr/bin/perl

use DBI;
use Linux::LVM;

use strict;
use warnings;

my $dbg="y";
my $dbh;
my $dbhost;
my $dbdb;
my $dbuser;
my $dbpass;

#define propre vgname without /dev
my $vgname = "vg_axslinuxsofia";
#define propre lvnames /data->LgoVol03 , /home->lv_home, /mysql->LogVol04
my %lvnames = (
        'data'=>'LogVol03',
        'home'=>'lv_home',
        'mysql'=>'LogVol04'
);

our $bkptarget = "file://tmp/test";
our $keepdays = "15";
our $dup_options = "";

sub mysql_flush {

        $dbh = DBI->connect("DBI:mysql:host=$dbhost;database=$dbdb", $dbuser, $dbpass) || die;
        if ($dbg) { print "DBG: Connected to $dbhost on $dbdb with user $dbuser\n"; }
        $dbh->do('FLUSH TABLES WITH READ LOCK;');
        if ($dbg) { print "DBG: Flushing MySQL tables with read lock ...\n"; }

        $dbh->do('UNLOCK TABLES;');

        $dbh->disconnect();
}

sub create_lvm_snapshot {
        my $clvms = "/dev/$vgname/".$lvnames{shift(@_)};
        my $lvmsnap = $_."_snap";
        my $ssize = "1G";

        if ($dbg) { print "DBG: Creating $ssize lvmsnapshot for $clvms with name $lvmsnap\n"; }
        print ("\t/sbin/vgcreate -L$ssize -s -n $lvmsnap $clvms\n");
}

sub mount_lvm_volume {
        my $lvmsnap = $_."_snap";
        if ($dbg) { print "DBG: Mounting volume $lvmsnap at /mnt/snaps/$lvmsnap\n" ; }
        print ("\t/bin/mount /dev/$vgname/$lvmsnap /mnt/snaps/$lvmsnap\n");
}

sub unmount_lvm_volume {
        my $lvmsnap = $_."_snap";
        if ($dbg) { print "DBG: Unmounting volume $lvmsnap from /mnt/snaps/$lvmsnap\n" ; }
        print ("\t/bin/umount /mnt/snaps/$lvmsnap\n");
}

sub destroy_lvm_snapshot {
        my $lvmsnap = $_."_snap";
        if ($dbg) { print "DBG: Destroing snapshot $lvmsnap\n"; }
        print ("\t/sbin/lvremove -f /dev/$vgname/$lvmsnap\n");
}

sub backup_create {
        my $lvmsnap = $_;
        print ("\t/usr/bin/duplicity $dup_options /mnt/snaps/$lvmsnap $bkptarget/$lvmsnap\n");
}

sub backup_cleanup {
        my $lvmsnap = $_;
        if ($dbg) { print "DBG: DUPLICITY: cleaning up $bkptarget/$lvmsnap for files older than $keepdays days\n"; }
        print ("\t/usr/bin/duplicity remove-all-but-n-full $keepdays --froce $bkptarget/$lvmsnap\n");
}

sub mail_summary {
        print "YOU HAVE NEW MAIL\n";
}


# MAINa

if ($dbg) { print "\nDBG: lv (data)->/dev/$vgname/$lvnames{'data'}, lv (home)->/dev/$vgname/$lvnames{'home'}, lv (mysql)->/dev/$vgname/$lvnames{'mysql'}\n\n";}


foreach (keys %lvnames) {
        create_lvm_snapshot($_);
        mount_lvm_volume($_);
        backup_cleanup($_);
        backup_create($_);
        unmount_lvm_volume($_);
        destroy_lvm_snapshot($_);
}

mail_summary();

if ($dbg) { print "DONE\n"; }
