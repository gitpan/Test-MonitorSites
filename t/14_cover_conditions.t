#!/usr/bin/perl -w
use strict;
use warnings;
use Test::Builder::Tester;
use Test::More tests => 12;
use Data::Dumper;
use WWW::Mechanize;

use lib qw{lib};
use Test::MonitorSites;

my $cwd = `pwd`;
chomp($cwd);
my $config_file = "$cwd/t/testsuite_addtl.ini";
# diag('We\'re using as our config file: ');
# diag("     " . $config_file);
my $tester = Test::MonitorSites->new( { 'config_file' => $config_file } );

test_out("ok 1 - Successfully linked to http://www.perlmonks.com.",
   "ok 2 -  . . . and found expected content at http://www.perlmonks.com");

my $results = $tester->test_sites();

test_test( name => "Test suite produced the expected successes and errors.",
       skip_out => 1 );

my $test_output = '/tmp/test_sites_output_addtl_ok';
my $test_diagnostics = '/tmp/test_sites_output_addtl_diag';

my ($site,$test_number);
my $ok = 0;
my $not_ok = 0;
my $skip = 0;
my $todo = 0;
open('TESTS','<',$test_output);
while(<TESTS>){
  if(m/^ok/){ $ok++; }
  if(m/^not ok/){ $not_ok++; }
  if(m/# SKIP/){ $skip++; }
  if(m/^# TODO/){ $todo++; }
  if(m/- Successfully linked/){ 
    $test_number = $_;
    $test_number =~ s/ - Succ.*$//;
    $test_number =~ s/^.*ok //;
    $test_number = $test_number + 1;
    $site = $_;
    $site =~ s/^.*linked to //;
    if($site !~ m/example.com/) {
      like($_,qr/^ok /,"Successfully linked to $site");
    } else {
      like($_,qr/^not ok /,"Not able to find non-existent site: $site");
    }
  }
  if(m/$test_number/ && m/found expected content/){
    if($site !~ m/example.com/) {
      like($_,qr/^ok/,"  .  .  .  and found expected content for $site");
    } else {
      like($_,qr/^not ok/,"  .  .  .  and did not find expected content for non-existent site: $site");
    }
  }
  if(m/checked all links/){
    like($_,qr/ok/,"  .  .  .  checked all links on this page");
  }
  if(m/html content is valid/){
    like($_,qr/ok/,"  .  .  .  and the validity of the html code was tested");
  }
}
close('TESTS');

like($tester->{'error'},qr/there were no critical_failures/,'All tests passed, no text message sent');
like($tester->{'error'},qr/Configuration file disabled email dispatch of results log./,'Configuration file set send_summary = 0, no email sent');
like($tester->{'error'},qr/Configuration file disabled email dispatch of diagnostic log./,'Configuration file set send_diagnostics = 0, so diagnostics not  sent');
# like($tester->{'error'},qr//,'');

$tester->_test_tests();

my $log = $tester->_return_result_log();
like($log,qr/tmp\/test_sites_output_addtl/,'Seems to return the correct result_log');

$tester->{'config'}->param('global.report_by_ip') = undef;
$tester->test_sites();

TODO:
{
  local $TODO = "Looking for an elegant way to test this, that works.";
  # $tester->{'error'} = undef;
  # $tester->{'config'}->param('global.results_recipients') = undef;
  # $tester->test_sites();

  like($tester->{'error'},qr/no result_recipient defined/,'No result_recipient defined, so no email will be sent.');
}

1;

