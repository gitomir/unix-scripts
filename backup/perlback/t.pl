#!/usr/bin/perl

use Net::SFTP::Foreign;


my $sftp = Net::SFTP::Foreign->new(host=>'192.168.9.120',, user=>'mkn', key_path=>'/root/.ssh/id_rsa', ssh_cmd=>"/usr/bin/ssh", more=>"-v -v -v");
$sftp->rget('/data/perlback-dumps/*','/tmp/');

print $sftp->error;
