package Test::MonitorSites;

use warnings;
use strict;
use Carp;
use Cwd;
use Config::Simple;
use WWW::Mechanize;
use Test::WWW::Mechanize;
use Test::HTML::Tidy;
use HTTP::Request::Common;
use Test::More;
use Data::Dumper;
use Test::Builder;
use Mail::Mailer;
# use Mail::Mailer qw(mail);

use vars qw($VERSION);
$VERSION = '0.04';

1; # Magic true value required at end of module

sub new {
  my $class = shift;
  my $args = shift;
  my $self = {};
  my ($cfg,%sites,@sites,$site);

  if (defined($args->{'config_file'})){
    my $config_file = $args->{'config_file'};
    if(-s $config_file){
      $cfg = new Config::Simple($config_file);
      if(!defined($cfg->{'_DATA'})){
        $self->{'config_file'} = undef;
        $self->{'error'} .= 'No configuration data is available.';
      } else {
        foreach my $key (keys %{$cfg->{'_DATA'}}){
          if($key =~ m/^site_/){
            $site = $key;
            $site =~ s/^site_//;
            push @sites, $site;
          }
        }
        # print STDERR @sites, "\n";
        $self->{'sites'} = \@sites;
        my $cwd = getcwd();
        # {
          # no strict 'refs';
          # $cwd = `pwd`;
        # }
        # print STDERR "The current working directory is: $cwd.\n";
        if(defined($cfg->param('global.result_log'))){
          if($cfg->param('global.result_log') !~ m/^\//){
            $self->{'result_log'} = $cwd . '/' . $cfg->param('global.result_log');
          } else {
            $self->{'result_log'} = $cfg->param('global.result_log');
          }
        } else {
          $self->{'result_log'} = "$cwd/Test_MonitorSites_result.log"; 
        }
      }
    } else {
      $self->{'config_file'} = undef;
      $self->{'error'} .= 'The config_file was not found, or was empty.';
    }
  } else {
    $self->{'config_file'} = undef;
    $self->{'error'} .= 'The config_file was not set in the constructor.';
  }
  $self->{'config'} = $cfg;
  my $agent = WWW::Mechanize->new();
  my $mech = Test::WWW::Mechanize->new();
  $self->{'agent'} = $agent;
  $self->{'mech'} = $mech;

  bless $self, $class;
  return $self;
}

sub test_sites {
  my $self = shift;
  my $sites = shift;
  my(%sites);
  if(defined($sites)){
    %sites = %{$sites};
  } elsif(defined($self->{'config'}->{'_DATA'})) {
    %sites = %{$self->{'config'}->{'_DATA'}};
    foreach my $key (keys %sites){
      if($key !~ m/^site_/){
        delete $sites{$key};
      }
    }
  } else {
    $self->{'error'} .= 'No sites have been identified for testing.  Please add sites to: ' . $self->{'config_file'};
  }

  my ($key, $url, $expected_content,$expected);
  my(@url,@expected,@sites,@test_links,@test_valid_html);
  my $agent = $self->{'agent'};
  my $mech = $self->{'mech'};
  # print STDERR Dumper(\%sites);
  my $log_file = $self->{'result_log'};
  my $log_file_ok = $log_file . '_ok';
  my $log_file_diag = $log_file . '_diag';
  my $log_file_todo = $log_file . '_todo';

  my $Test = Test::Builder->new;
  my @handle_names = qw/ output failure_output todo_output /;
  my %old;
  $old{$_} = $Test->$_ for @handle_names;
  $Test->$_(\*STDOUT) for @handle_names;

  {
    $Test->output($log_file_ok);
    $Test->failure_output($log_file_diag);
    $Test->todo_output($log_file_todo);

    # print STDERR Dumper(\%sites);
    foreach my $site (keys %sites){
      if($site !~ m/^site_/){ next; }
      $site =~ s/^site_//;
      push @sites, $site;
      # diag("The site is $site");
      # diag("The hash key is site_$site");
      $url = $self->{'config'}->{'_DATA'}->{"site_$site"}->{'url'};
      $expected = $self->{'config'}->{'_DATA'}->{"site_$site"}->{'expected_content'};
      @url = @{$url};
      @expected = @{$expected};
      # $self->_test_tests();
      $self->_test_site($agent,$url[0],$expected[0]);
      @test_links = @{$sites{"site_$site"}{'test_links'}};
      if ($test_links[0] == 1) {
        $self->_test_links($mech,$url[0]) 
      } else {
        diag("Skipping tests of links at: $site.");
      }
      @test_valid_html = @{$sites{"site_$site"}{'test_valid_html'}};
      if ($test_valid_html[0] == 1) {
        $self->_test_valid_html($mech,$url[0]) 
      } else {
        diag("Skipping tests of html validity at: $site.");
      }
  
    }
  }
  $Test->todo_output(*STDOUT);
  $Test->failure_output(*STDERR);
  $Test->output(*STDOUT);

  my $critical_failures = $self->_analyze_test_logs();  
  if($critical_failures->{'count'} > 0){
    print STDERR "Next we send an sms message.\n";
    $self->sms($critical_failures);
  } else {
    $self->{'error'} .= "We won't send an sms, there were no critical_failures.\n";
    print STDERR "We won't send an sms, there were no critical_failures.\n";
  }

  if(defined($self->{'config'}->param('global.results_recipients'))){
    print STDERR "Next we send some email.\n";
    $self->email();
  } else {
    $self->{'error'} .= "We won't send an email, there was no result_recipient defined in the configuration file.\n";
  }

  my %result = (
         'sites' => $self->{'sites'},
         'planned' => '',
         'run' => '',
         'passed' => '',
         'failed' => '',
         'critical_failues' => $critical_failures,
       );

  return \%result;
}

sub _analyze_test_logs {
  my $self = shift;
  my $critical_failures = 0;
  my %critical_failures;
  foreach my $test ('linked_to','expected_content','all_links','valid'){
    print STDERR "This \$test is $test.\n";
    if($self->{'config'}->param("critical_failure.$test") == 1){
      $critical_failures{"$test"} = 1;
    }
  }
  my ($url,$test,$test_string,$ip,$param_name,@ip);
  open('SUMMARY','<',$self->{'config'}->param('global.result_log') . '_ok');
  while(<SUMMARY>){
    if(m/^not ok/){
      $url = $_;
      chomp($url);
      $url =~ s/^.*http:\/\///;
      $url =~ s/\/.*$//;
      $url =~ s/\.$//;
      $param_name = 'site_' . $url;
      $ip = $self->{'config'}->{'_DATA'}->{"site_$url"}->{'ip'};
      @ip = @{$ip} if(ref($ip));
      foreach $test (keys %critical_failures){
        if($test eq 'failed_tests'){ next; }
        $test_string = $test;
        $test_string =~ s/_/ /g;
        if($_ =~ m/$test_string/){
          $critical_failures++;
          $critical_failures{'failed_tests'}{'ip'}{"$ip[0]"}{"$url"} = $_ if(ref($ip));
          $critical_failures{'failed_tests'}{'url'}{"$url"}{"$test"} = $_;
          $critical_failures{'failed_tests'}{'test'}{"$test"}{"$url"} = $_;
        }
      }
    }
  }
  close('SUMMARY');  
  $critical_failures{'count'} = $critical_failures;

  return \%critical_failures;
}

sub _return_result_log {
  my $self = shift;
  return $self->{'result_log'};
}

sub email {
  my $self = shift;
  my ($type,@args,$body);

  my %headers = (
         'To'      => $self->{'config'}->param('global.results_recipients'),
         'From'    => 'MonitorSites@gandhi.greens.org',
         'Subject' => 'MonitorSites log',
       );

  my $file = $self->{'config'}->param('global.result_log');
  if($self->{'config'}->param('global.send_summary') == 1){
    open('RESULT','<',$file . '_ok');
    while(<RESULT>){
      $body .= $_;
    }
    close('RESULT');
  } else {
    $self->{'error'} .= "Configuration file disabled email dispatch of results log.\n";
  }

  if($self->{'config'}->param('global.send_diagnostics') == 1){
    $body .= <<'End_of_Separator';

==============================================
End of Summary, Beginning of Diagnostics
==============================================

End_of_Separator

    open('RESULT','<',$file . '_diag');
    while(<RESULT>){
      $body .= $_;
    }
    close('RESULT');
  } else {
    $self->{'error'} .= "Configuration file disabled email dispatch of diagnostic log.\n";
  }

  # is(1,1,'About to send email now.');
  $type = 'sendmail';
  my $mailer = new Mail::Mailer $type, @args;
  $mailer->open(\%headers);
    print $mailer $body;
  $mailer->close;
  return 1;
}

sub sms {
  my $self = shift;
  my $critical_failures = shift;
  my %critical_failures = %{$critical_failures};
  my %headers = (
         'To'      => $self->{'config'}->param('global.sms_recipients'),
         'From'    => 'MonitorSites@gandhi.greens.org',
         'Subject' => 'Critical Failures',
       );

  my ($type,@args,$body,$test,$url,$ip);
  if(defined($self->{'config'}->param("global.report_by_ip"))){
    if($self->{'config'}->param("global.report_by_ip") == 1){
      foreach $ip (keys %{$critical_failures{'failed_tests'}{'ip'}}){
        $body = "Failures at $ip; Sites affected include: ";
        foreach $url (keys %{$critical_failures{'failed_tests'}{'ip'}{"$ip"}}){
          $body .= "Not OK: $url, ";
        }
        # is(1,1,'About to send sms now about $url.');
        my $mailer = new Mail::Mailer $type, @args;
        $mailer->open(\%headers);
          print $mailer $body;
        $mailer->close;
      }
    }
  } else {
    my $i = 0;
    foreach $url (keys %{$critical_failures{'failed_tests'}{'url'}}){
      $i++; 
      $body = "Failure: $i of $critical_failures{'count'}: $url: ";
      foreach $test (keys %{$critical_failures{'failed_tests'}{'url'}{"$url"}}){
        $body .= "Not OK: $test, ";
      }
      # is(1,1,'About to send sms now about $url.');
      my $mailer = new Mail::Mailer $type, @args;
      $mailer->open(\%headers);
        print $mailer $body;
      $mailer->close;
    }
  }

  return 1;
}

sub _test_tests {
  is(12,12,'Twelve is twelve.');
  is(12,13,'Twelve is thirteen.');
  diag("Diagnostic output from subroutine called while redirecting output.");
  return;
}

sub _test_links {
  my ($self,$mech,$url) = @_;
  $mech->get_ok($url, " . . . linked to $url");
  $mech->page_links_ok( " . . . successfully checked all links for $url" );
  return;
}

sub _test_valid_html {
  my ($self,$mech,$url) = @_;
  $mech->get_ok($url, " . . . linked to $url");
  html_tidy_ok( $mech->content(), " . . . html content is valid for $url" );
  return;
}

sub _test_site {
  my($self,$agent,$url,$expected_content) = @_;
  $agent->get("$url");
  is ($agent->success,1,"Successfully linked to $url.");
  like($agent->content,qr/$expected_content/," . . . and found expected content at $url");
  return $agent->success();
}

__END__

=head1 NAME

Test::MonitorSites - Monitor availability and function of a list of websites 

=head1 VERSION

This document describes Test::MonitorSites version 0.0.4

=head1 SYNOPSIS

    use Test::MonitorSites;
    my $tester = Test::MonitorSites->new({
            'config_file' => '/file/system/path/to/monitorsites.ini',
         });

    my $results = $tester->test_sites();
    $tester->email($results);
    if(defined($results->{'critical_failures'})){
        $tester->sms($results->{'critical_failures'});
    }

In addition to any global variables which may apply to an
entire test suite, the configuration file ought to include an
ini formatted section for each website the test suite defined
by the configuration file ought to test or exercise.  For full
details on the permitted format, read perldoc Config::Simple.
In this first example, we'll test the cpan.org site for accessible html
markup and to ensure that the links all work.  With the perlmonks site,
we'll simply confirm that the site resolves and that its expected
content can be found on the page.

=over 4

    [site_www.cpan.org]
    ip='66.39.76.93'
    url='http://www.cpan.org'
    expected_content='Welcome to CPAN! Here you will find All Things Perl.'
    test_valid_html = 1
    test_links = 1
    
    [site_www.perlmonks.com]
    ip='66.39.54.27'
    url='http://www.perlmonks.com'
    expected_content='The Monastery Gates'

=back

In the long run, as this develops, it is anticipated that
the site definitions could take on the following structure,
imagining the ability to test the functionality of a specific
web application, and powered by an application specific module
of the form Test::MonitorSites::MyWebApplication.

=over 4

    [site_www.example.com]
    ip='192.168.1.1'
    url='http://www.example.com/myapp.cgi'
    expected_content='Welcome to MyApp!'
    user_field_name='login'
    password_field_name='password'
    user='mylogin'
    password='secret'
    
    [site_civicrm.example.com]
    url='http://civicrm.example.com/index.php'
    expected_content='Welcome to MyApp!'
    application=civicrm
    
    [site_drupal.example.com]
    url='http://drupal.example.com/index.php'
    expected_content='Welcome to MyApp!'
    application=drupal
    modules='excerpt,events,local_module'

=back

=head1 DESCRIPTION

=head1 SUBROUTINES/METHODS

=head2 my $tester = Test::MonitorSites->new( 'config_file' => $config_file_path,);

Create a $tester object, giving access to other module methods.
Constructor takes a hash with a single key, 'config_file'
with a path (from root or relative) to an ini formatted
configuration file.

=head2 $results = $tester->test_sites();

This method will permit a battery of tests to be run on each
site defined in the configurations file.  It returns a hash
of results, which can then be examined and tested, or used to
make reports.

=head2 $tester->email($results);

or 

=head2 $tester->email($results,$recipients);

This method will email a report of test results to a recipients
defined either in the configuration file or in the method call.

=head2 $tester->sms($results->{'critical_failures'});

or

=head2 $tester->sms($results->{'critical_failures'},$recipients);

This method will permit a notice of Critical Failures to be
delivered by SMS messaging to a cell phone or pager device.  The
message is delivered to recipients defined in the configuration
file or in the method call.  If the global.report_by_ip
configuration parameter is assigned to '1', then a single
sms message per IP address with test failures will be sent.
Otherwise, an sms message will be sent for each individual
test failure, even for multiple failures on a single server.

=for author to fill in:
    Write a full description of the module and its features here.
    Use subsections (=head2, =head3) as appropriate.

=head1 INTERFACE 

=for author to fill in:
    Write a separate section listing the public components of the modules
    interface. These normally consist of either subroutines that may be
    exported, or methods that may be called on objects belonging to the
    classes provided by the module.

=head1 DIAGNOSTICS

=over

=item C<< No configuration data is available. >>

A configuration file was provided, but it contains no
configuration data in a valid format.  See the SYNOPSIS for
details on valid variables which ought to be defined in your
config file.  See perldoc Config::Simple for details on its
valid format.

=item C<< The config_file was not found, or was empty. >>

The config file defined in the constructor is missing from
the filesystem, or if it does exist, it is empty.

=item C<< The config_file was not set in the constructor. >>

The module's constructor, the ->new() method, was invoked
without a configuration file defined in the call.

=item C<< No sites have been identified for testing.  Please add sites to: (your config file) >>

An otherwise valid configuration file has been found, but it
does not seem to have defined any sites to be tested.

=back


=head1 CONFIGURATION AND ENVIRONMENT

The Test::MonitorSites constructor requires a configuration
file using the ini Config::Simple format which defines global
variables and contains an .ini section for each website to be
monitored by this module.

=head1 DEPENDENCIES

This module uses the following modules, available on CPAN:
Carp, Config::Simple, WWW::Mechanize, Test::WWW::Mechanize,
Test::HTML::Tidy, HTTP::Request::Common, Test::More,
Data::Dumper, Test::Builder.

=head1 INCOMPATIBILITIES

None reported.

=head1 BUGS AND LIMITATIONS

No bugs have been reported.

I welcome bug reports and feature requests at both:
<http://www.campaignfoundations.com/project/issues>
as well as through the cpan hosted channels at:
"bug-test-monitorsites@rt.cpan.org", or through the web
interface at <http://rt.cpan.org>.

=head1 AUTHOR

Hugh Esco  C<< <hesco@campaignfoundations.com> >>

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2007, Hugh Esco C<<
<hesco@campaignfoundations.com> >>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the terms of the Gnu Public License. See L<gpl>.

=head1 CREDITS

Initial development of this module done with th kind support
of the Green Party of Canada.  L<http://www.greenparty.ca/>.

=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.
