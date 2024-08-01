#! /usr/bin/perl -w
use strict;

=head1 NAME

xpipe_get.pl - retrieve archive files required for xpipe processing

=head1 SYNOPSIS

perl xpipe_get.pl -u USER -p PASSWORD obsid1 obsid2 ...

=head1 DESCRIPTION

This script is a simple wrapper around F<archive_get.pl>. It attempts
to retrieve asol1, bias0, pbk, bpix1, aoff1, flt1, msk1, evt1 and evt2
files for each requested obsid. The archive files will go into a
subdirectory, named F<obsidNNN>, of the current working directory.

=head1 OPTIONS

=over 4

=item --help

Show help and exit.

=item --version

Show version and exit.

=item --u=s

Archive username.

=item --p=s

Archive password.

=item --noexec

Do not retrieve files, but show the F<archive_get.pl> calls which
would be made.

=item --outbase=s

Retrieve files under the given directory instead of the current working
directory.

=item --archiveget=s

Path to the F<archive_get.pl> script.

=item --noenvcheck

Do not attempt to ensure the ASC environment is setup correctly.

=item --noerrcheck

Continue even when an F<archive_get.pl> command fails.

=back

=head1 AUTHOR

Pete Ratzlaff E<lt>pratzlaff@cfa.harvard.eduE<gt> September 2005

=head1 SEE ALSO

perl(1).

=cut

my $version = '0.1';

use FindBin;
use Config;
use Carp;
use Data::Dumper;

use Getopt::Long;
my %default_opts = (
		    archiveget => '/data/legs/rpete/flight/dev/archive_get.pl',
		    envcheck => 1,
		    exec => 1,
		    );
my %opts = %default_opts;
GetOptions(\%opts,
	   'help!', 'version!', 'debug!',
	   'archiveget=s', 'outbase=s', 'envcheck!', 'errignore!',
	   'u=s', 'p=s', 'exec!',
	   ) or die "Try --help for more information.\n";
if ($opts{debug}) {
  $SIG{__WARN__} = \&Carp::cluck;
  $SIG{__DIE__} = \&Carp::confess;
}
$opts{help} and _help();
$opts{version} and _version();

(@ARGV and exists $opts{u} and exists $opts{p})
  or die "Usage: $0 -u USER -p PASSWORD obsid1 obsid2 ...\n";
my @obsids = @ARGV;

if (!exists $ENV{DB_LOCAL_SQLSRV} and $opts{envcheck}) {
  die "ASC environment not detected, have you sourced your .ascrc?\n";
}

my @outbase_args = $opts{outbase} ? ('--outbase', $opts{outbase}) : ();

for (@obsids) {
  /^\d+$/ or die "invalid obsid = '$_'\n";
}

for my $obsid (@obsids) {
  # obs0a.par
  _run_command('perl', $opts{archiveget}, '-u', $opts{u}, '-p', $opts{p},
	       '-obsid', $obsid, '-verbose', '-exec', '-detector', 'obi',
	       @outbase_args, '-subdetector', 'obspar', '-l', '0',
	       );
  # asol1
  _run_command('perl', $opts{archiveget}, '-u', $opts{u}, '-p', $opts{p},
	       '-obsid', $obsid, '-verbose', '-exec', '-detector', 'pcad',
	       @outbase_args, '-subdetector', 'aca', '-filename', 'asol1',
	       );
  # bias0
  _run_command('perl', $opts{archiveget}, '-u', $opts{u}, '-p', $opts{p},
	       '-obsid', $obsid, '-verbose', '-exec', '-detector', 'acis',
	       @outbase_args, '-l', '0', '-filetype', 'bias0',
	       );
  # pbk
  _run_command('perl', $opts{archiveget}, '-u', $opts{u}, '-p', $opts{p},
	       '-obsid', $obsid, '-verbose', '-exec', '-detector', 'acis',
	       @outbase_args, '-l', '0', '-filetype', 'pbk',
	       );
  # bpix1, aoff1, flt1, msk1, evt1
  _run_command('perl', $opts{archiveget}, '-u', $opts{u}, '-p', $opts{p},
	       '-obsid', $obsid, '-verbose', '-exec', '-detector', 'acis',
	       @outbase_args,
	       );
  # evt2
  _run_command('perl', $opts{archiveget}, '-u', $opts{u}, '-p', $opts{p},
	       '-obsid', $obsid, '-verbose', '-exec', '-detector', 'acis',
	       @outbase_args, '-l', '2', '-filetype', 'evt2',
	       );
}

exit 0;

sub _run_command {
  my ($cmd, @args) = @_;
  print STDERR join(' ', $cmd, map ( "'$_'", @args)),"\n\n";
  if ($opts{'exec'}) {
    system($cmd, @args);
    die unless ($opts{errignore} or $? == 0);
  }
}

sub _help {
  exec("$Config{installbin}/perldoc", '-F', $FindBin::Bin . '/' . $FindBin::RealScript);
}

sub _version {
  print $version,"\n";
  exit 0;
}
