#! /usr/bin/perl -w
use strict;

=head1 NAME

adsmunge.pl - munge ADS bibtex citations

=head1 SYNOPSIS

perl adsmunge.pl [options] ADSfile1 ADSfile2 ...

=head1 DESCRIPTION

Changes article identifiers to something more easily remembered.
Citations are read from C<stdin> or a list of filenames given as
arguments. Output is sent to C<stdout>.

=head1 EXAMPLES

The effect of this program is more easily shown than explained...

=over 4

=item Simple case of fewer than three authors

	@ARTICLE{2002MNRAS.335L..29K,
	    author = {{Klu{\' z}niak}, W.~;. and {Lee}, W.~H.},

becomes

	@ARTICLE{Kluzniak.Lee:02,
	    author = {{Klu{\' z}niak}, W.~;. and {Lee}, W.~H.},

=item Multiple entries for a given author

Given the previous example, if later an ADS article appeared such as

	@ARTICLE{2002PASP.159L..13K,
	    author = {{Klu{\' z}niak}, W.~;. and {Lee}, W.~H.},

then the munged article is

	@ARTICLE{Kluzniak.Lee:02b,
	    author = {{Klu{\' z}niak}, W.~;. and {Lee}, W.~H.},

Note the "b".

=item Three or more authors

The identifier becomes the first author's name followed by "etal". For
example,

	@ARTICLE{2002ApJ...572..996D,
	    author = {{Drake}, J.~J. and {Marshall}, H.~L. and {Dreizler}, S.
	    and {Freeman}, P.~E. and {Fruscione}, A. and {Juda}, M.},

is output as

	@ARTICLE{Drake.etal:02,
	    author = {{Drake}, J.~J. and {Marshall}, H.~L. and {Dreizler}, S.
	    and {Freeman}, P.~E. and {Fruscione}, A. and {Juda}, M.},

=back

=head1 OPTIONS

=over 4

=item --help

Show help and exit.

=item --version

Show version and exit;

=item --dups

Normally, duplicate articles are not output. This option overrides the
default behaviour and outputs detected duplicates.

=item --sort

Sort articles alphabetically, by their output identifiers.

=back

=head1 AUTHOR

Pete Ratzlaff E<lt>pratzlaff@cfa.harvard.eduE<gt> May 2020

=head1 SEE ALSO

perl(1).

=cut

my $version = '05';

use Config;
use FindBin;
use Carp;

use Getopt::Long;
my %default_opts = (
		    dups => 0,
		    );
my %opts = %default_opts;
GetOptions(\%opts,
	   'help!', 'version!', 'dups!', 'debug!', 'sort!',
	   ) or die "Try --help for more information.\n";
$opts{help} and _help();
$opts{version} and _version();

if ($opts{debug}) {
  $SIG{__WARN__} = \&Carp::cluck;
  $SIG{__DIE__} = \&Carp::croak;
}

my %authorstrings;

my %ids;

# arrays to hold the article data if we're sorting before output
my (@sortstrings, @data);

while (my ($type, $article, $id) = read_article()) {

  # remove duplicates
  if (! $opts{dups}) {
    exists $ids{$id} and next;
    $ids{$id} = 1;
  }

  my ($k, $d) = parse_article($article);

  # order is preserved in $k and $d, now we want to make it easy
  # to get whichever key is needed
  my %data; @data{@$k} = @$d;

  # if we can't munge it, just print it back out
  if (!exists $data{author} or !exists $data{year}) {
    write_article($type, $id, $k, $d);
    next;
  }

  my ($year) = $data{year} =~ /(\d+)/;
  $year = substr($year, -2);

  my @authors = extract_authors($data{author});

  my $authorstring = @authors < 3 ?
    join('.',@authors).":$year"
      :
	"$authors[0].etal:$year";

  $authorstrings{$authorstring}++;
  if ($authorstrings{$authorstring} > 1) {
    $authorstring .= chr( ord('a') + $authorstrings{$authorstring} - 1);
  }

  if ($opts{sort}) {
    push @sortstrings, $authorstring;
    push @data, [$type, $authorstring, $k, $d];
  }
  else {
    write_article($type, $authorstring, $k, $d);
  }

}

if ($opts{sort}) {
  my @i = sort {lc($sortstrings[$a]) cmp lc($sortstrings[$b])} 0..$#sortstrings;

  for (@i) {
    write_article(@{$data[$_]});
  }
}

exit 0;

sub write_article {
  my ($type, $id, $keys, $data) = @_;
  print "\@$type\{$id,\n";
  for (0..$#{$keys}) {
    print "    $keys->[$_] = $data->[$_]";
    print ',' unless $_ == $#{$keys};
    print "\n";
  }
  print "\}\n\n";
}

sub extract_authors {
  my $astring = shift;

  # remove leading and trailing brackets
  $astring =~ s/^\{(.*)\},?$/$1/s or die "'$astring'";

  my @authors;

  my $bracelevel = 0;

  my $starti; # where the outer brace started

  for my $i (0..length($astring)-1) {

    my $char = substr($astring, $i, 1);

    if ($char eq '{') {
      $starti = $i if not $bracelevel;
      $bracelevel++;
      next;
    }

    if ($char eq '}') {
      $bracelevel--;
      if (not $bracelevel) {
	if (substr($astring,$i+1,1) eq ',') {
	  my $a = substr($astring, $starti+1, $i-$starti-1);
	  $starti = undef;

	  # special case for {\'\i}
	  $a =~ s/\{\\'\\i\}/i/g;

	  # special case for {\'{\i}}
	  $a =~ s/\{\\'\{\\i\}\}/i/g;

	  # special case for {\[vck]{[a-z]}}
	  $a =~ s/\{\\[vck]\{([a-z])\}\}/$1/gi;

	  # special case for {\l}
	  $a =~ s/\{\\l\}/l/g;

	  # have seen an example like {Ta{\textcommabelow s}}
	  $a =~ s/\{\\[a-z ]+\}//gi;

	  # remove funny latex stuff for things like accents
	  $a =~ s/\{\\\S\s*(\w+)\}/$1/g;

	  # remove spaces
	  $a =~ s/\s+/_/g;

	  push @authors, $a;
	}
      }
    }

  }

  return @authors;
}

sub extract_authors_old {
  my $astring = shift;

  # remove leading and trailing brackets
  $astring =~ s/^\{(.*)\},?$/$1/s or die "'$astring'";

  my @authors;

  # FIXME: used to have conditional comma here, it fixed something. What did it fix???
  # while ($astring =~ /\{(.*?)\},?/g) {
  while ($astring =~ /\{(.*?)\},/g) {
    my $a = $1;

    # remove funny latex stuff for things like accents
    $a =~ s/\{\\\S\s*(\w+)\}/$1/g;

    # special case for {\'{\i}}
    $a =~ s/\{\\'\{\\i\}\}/i/g;

    # special case for {\l}
    $a =~ s/\{\\l\}/l/g;

    # remove spaces
    $a =~ s/\s+/_/g;

    push @authors, $a;
  }
  return @authors;
}

sub read_article {
  local $_;
  my $article = '';
  my $type;
  my $id;
 ARTICLE:
  while (<>) {

    # start of an article
    if (/^\@([A-Z]+)\{(.*),\s*$/i) {
      $type = $1; # e.g., ARTICLE or INPROCEEDINGS
      $id = $2;

      # read until there's an unmatched closing brace
      my $bracecount = 0;
      while (<>) {
	my $charprev = '';
	for my $i (0..length($_)-1) {
	  my $char = substr($_, $i, 1);

	  if ($char eq '{' and $charprev ne '\\') {
	    $charprev = $char;
	    $bracecount++;
	    next;
	  }
	  if ($char eq '}' and $charprev ne '\\') {
	    $bracecount--;
	    if ($bracecount < 0) {
	      $article .= substr($_, 0, $i);
	      last ARTICLE;
	    }
	  }
	  $charprev = $char;
	}
	$article .= $_;
      }
      die "truncated ARTICLE";
    }

  }
  return unless defined;
  return ($type, $article, $id);
}

sub read_article_old {
  my @data;
  local $_;
  my $in_article = 0;
  my $article = '';
  my $type;
  my $id;
 ARTICLE:
  while (<>) {

    # start of an article
    if (/^\@([A-Z]+)\{(.*),\s*$/i) {
      $type = $1; # e.g., ARTICLE or INPROCEEDINGS
      $id = $2;
      while (<>) {

	# last ARTICLE if (/^\}\s*$/) or /(^.*\})\}$/;
	# $article .= $_;

	# closing brace at the end of a line without a following comma
	# ends the article

	if (/(\}\s*)$/) {
	  $article .= substr($_, 0, -length($1));
	  last ARTICLE;
	}
	$article .= $_;

      }
      die "truncated ARTICLE";
    }

  }
  return unless defined;
  return ($type, $article, $id);
}

sub parse_article {
  my $article = shift;
  my (@keys, @data);
  while ($article =~ /^\s*(\S+)\s+=\s+(.*?)(?:,\s*?\n(?=\s*\S+\s+=\s+)|\s*\z)/gms) {
    push @keys, lc($1);
    push @data, $2;
  }
  return \@keys, \@data;
}

sub _help {
  exec("$Config{installbin}/perldoc", '-F', $FindBin::Bin . '/' . $FindBin::RealScript);
}

sub _version {
  print $version,"\n";
  exit 0;
}
