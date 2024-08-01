#! /usr/bin/perl -w
use strict;

use lib '/home/rpete/local/perlmods';

use CXC::Archive;
use Cwd;
use Getopt::Long;
use File::Path;
use Carp;

my %default_opts = (
		    outbase => '.',
		    clobber => 1,
		    detector => 'hrc',
		    level => 1,
		    dataset => 'flight',
		    version => 'last',
		    verbose => 0,
		    server => 'arcocc',
		    user => 'rpete',
		    obsids => [ ],
		    arc4gl => '/home/ascds/DS.release/bin/arc4gl',
		    lib_path => '/home/ascds/DS.release/lib:/home/ascds/DS.release/ots/lib',
		    );
my %opts = %default_opts;
GetOptions(\%opts,
	   'password=s', 'server=s', 'user=s', 'outbase=s', 'filename=s', 'filetype=s',
	   'obsids=s@',
	   'clobber!', 'verbose!', 'exec!', 'help!',
	   'level=s', 'dataset=s', 'version=s', 'detector=s', 'subdetector=s',
	   'debug!', 'arc4gl=s', 'lib_path=s',
	   ) or die "Try \`$0 --help\' for more information.\n";
$opts{help} and help();

if ($opts{debug}) {
  $SIG{__WARN__} = \&Carp::cluck;
  $SIG{__DIE__} = \&Carp::croak;
}

-x $opts{arc4gl} or die "cannot execute $opts{arc4gl}, try the --arc4gl=s option, and also --lib_path=s\n";

@ARGV and die "Usage: $0 [options]\ntry --help for more information\n";

defined $opts{password} or
  die "$0: password not specified\nTry \`$0 --help\' for more information.\n";

#
# parse obsids
#
my @obsids = ();
for my $expression (@{$opts{obsids}}) {
  my @tmp = eval $expression;
  die "$0: error evaluating obsid express = '$expression'\n" if ($@ ne '');
  push @obsids, @tmp;
}

#@obsids or
#    die "$0: no obsids!\n";
$opts{verbose} and @obsids and
  print "obsids = ".join(' ',@obsids)."\n";

#
# create the archive object
#
my %archive_attributes = (
			  Server => $opts{server},
			  User => $opts{user},
			  Password => $opts{password},
			  Auto_cd_Reconnect => 1,
			  Verbose => 1,
			  arc4gl => $opts{arc4gl},
			  lib_path => $opts{lib_path},
			 );
my $arc = new CXC::Archive \%archive_attributes;

#
# template request
#
my @required = qw( dataset detector level version );
my %req_base;
@req_base{@required} = @opts{@required};

my @optional = qw( filename filetype subdetector );
exists $opts{$_} and $req_base{$_} = $opts{$_} for @optional;

# some cases the user doesn't want to specify an obsid
@obsids = (undef) unless @obsids;

foreach my $obsid (@obsids) {
  my %req = %req_base;

#  $req{supporting} = 'y';
  $req{operation} = 'browse';
  $req{obsid} = $obsid if defined $obsid;

  my $res = $arc->browse(\%req);
  @$res or
    warn("*** No files" .(defined $obsid ? " for obsid $obsid" : '')." ***\n"),
      next;

  # retain original results
  my @ofiles = map $res->[$_]{name}, 0..$#{$res};
  my @osizes = map $res->[$_]{size}, 0..$#{$res};
  my @otimes = map $res->[$_]{time}, 0..$#{$res};

  # make copies
  my @files = @ofiles;
  my @sizes = @osizes;
  my @times = @otimes;

  #
  # create directory if it does not exist already
  #
  my $newdir = $opts{outbase}.(defined $obsid ? "/$obsid" : '');
  if ($opts{exec}) {
    -d $newdir or mkpath($newdir) or
      die "$0: could not create directory '$newdir': $!\n";
  }

  # obsid and filename options don't work together in arc4gl,
  # instead it's as if filename wasn't even given. This is an attempt
  # to do what the user would expect
  if (defined $obsid and $opts{filename}) {
    delete $req{obsid};
    my @filenames = split ',', $opts{filename};
    s/^\s+//, s/\s+$// for @filenames;
    my(@tfiles, @tsizes, @ttimes, %tfiles);
    for my $name (@filenames) {
      my @i = grep { $files[$_] =~ /$name/ and !exists $tfiles{$files[$_]} }
	0..$#files;
      if (@i) {
	@tfiles{@files[@i]} = ();
	push @tfiles, @files[@i];
	push @tsizes, @sizes[@i];
	push @ttimes, @times[@i];
      }
    }
    @tfiles or
      warn("*** no files to retrieve".(defined $obsid ? " for obsid=$obsid" : '').", due to --filename ***\n"),
	next;
    @files = @tfiles;
    @sizes = @tsizes;
    @times = @ttimes;
  }

  #
  # modify list of filenames, if necessary
  #
  if (!$opts{clobber}) {
    my (@tfiles, @tsizes, @ttimes);
    foreach my $i (0..$#files) {
      if (
	  ! -f "$newdir/$files[$i]" &&
	  ! -f "$newdir/$files[$i].gz"
	 ) {
	push @tfiles, $files[$i];
	push @tsizes, $sizes[$i];
	push @ttimes, $times[$i];
      }
    }
    @tfiles or
      warn("*** no files to retrieve".(defined $obsid ? " for obsid=$obsid" : '').", due to no --clobber ***\n"),
	next;
    @files = @tfiles;
    @sizes = @tsizes;
    @times = @ttimes;
  }

  if (@files == @ofiles) {
    warn("*** ".(defined $obsid ? "obsid=$obsid, " : '')."retrieving all files ***\n");
    if ($opts{verbose}) {
      warn(join("\n",map
		{
		  (defined $obsid ? "obsid=$obsid, " : '') . "$files[$_], $sizes[$_], $times[$_] "}
		(0..$#files)
	       )."\n");
    }

    if ($opts{exec}) {
      my $olddir = getcwd;
      chdir $newdir;
      $req{operation} = 'retrieve';
      $arc->retrieve(\%req);
      chdir $olddir;
    }

  } else {
    delete $req{obsid} if defined $obsid;
    warn("*** ".(defined $obsid ? "obsid=$obsid, " : '')."retrieving ".(scalar @files).'/'.(scalar @ofiles)." files ***\n");
    if ($opts{verbose}) {
      warn(join("\n",map
		{
		  (defined $obsid ? "obsid=$obsid, " : '') . "$files[$_], $sizes[$_], $times[$_] "}
		(0..$#files)
	       )."\n");
    }

    if ($opts{exec}) {
      my $olddir = getcwd;
      chdir $newdir;
      $req{operation} = 'retrieve';
      $req{filename} = join(', ',@files);
      $arc->retrieve(\%req);

      chdir $olddir;
    }
  }
}

exit 0;

sub help {
  print <<EOP;
Usage: $0 [options] -p your_archive_password

Retrieve files from the archive server. Note that --exec must be given
for any files to actually be retrieved.

  --help                    show help and exit
  --outbase=dir             specify where to put output directories
                            default is $default_opts{outbase}
  --exec                    actually retrieve files
  --noclobber               do not overwrite existing files
  --verbose                 print filenames that are to be retrieved
  --server=server           database server to use
                            default is $default_opts{server}
  --user=user               user to log in as, default is $default_opts{user}
  --password=password       password to use (required)
  --obsids=code             string to eval() for determining which obsids to
                            use, more than one --obsid specification may be
                            given
  --dataset=dataset         default is $default_opts{dataset}
  --detector=detector       default is $default_opts{detector}
  --level=level             default is $default_opts{level}
  --version=version         default is $default_opts{version}
  --filename=spec           no default
  --filetype=spec           no default
  --subdetector=sub         no default

EOP

  exit 0;
}
