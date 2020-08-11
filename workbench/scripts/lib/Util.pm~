#!/usr/bin/perl

package Util;
# some utils for parsing text grid data

use strict;
use warnings;
use Digest::MD5 qw(md5_hex);
use Carp;
use FindBin;
use List::Util;
require "MyBrew.pm";

use constant DEBUG => scalar 0; # 0: nothing, 1: some, 2: a lot
use constant WARN => scalar 1; # 0: nothing, 1: some, 2: a lot
use constant TRUE => (0 == 0);
use constant FALSE => (0 == 1);

my $TMPDIR = "$FindBin::Bin/runCache/";

sub min {
	my $a = shift;
	my $b = shift;
	if (defined $a) {
		if (defined $b) {
			return ($a < $b) ? $a : $b;
		} else {
			return;
		}
	} else {
		return $b;
	}
}

sub max {
	my $a = shift;
	my $b = shift;
	if (defined $a) {
		if (defined $b) {
			return ($a > $b) ? $a : $b;
		} else {
			return;
		}
	} else {
		return $b;
	}
}

# return whether two lists are equal with regard to the string 'eq' comparison
sub listEqual {
	my @a = @{$_[0]}; 
	my @b = @{$_[1]};
	return (0 == 0) if (!@a and !@b);
	return (1 == 0) if (!@a and @b);
	return (1 == 0) if (@a and !@b);
	confess "I can't compare empty lists!" unless (@a);
#	print join ":", @a;
#	print "\n";
	confess "I can't compare empty lists!" unless (@b);
#	print join ":", @b;
#	print "\n";
	return (1 == 0) if ($#a != $#b);
	my $i = 0;
	while ($i <= $#a) {
		return (1 == 0) if (($a[$i] or "") ne ($b[$i] or ""));
		$i++;
	}
	return (0 == 0);
}

# return whether the first list is a prefix of the second list 
# (i.e., elements are equal with regard to the string 'eq' comparison)
sub listPrefix {
	my @a = @{$_[0]};
	my @b = @{$_[1]};
	return (1 == 0) if ($#a > $#b);
	my @bshort = @b[0..$#a];
	return listEqual(\@a, \@bshort);
}

sub parseLine {
	my $line = shift;
	my $re = shift;
	$re =~ s/ /\\s*/g;
	print STDERR "re: '$re'\n" if (DEBUG > 2);
	confess "this is not a TextGrid I could understand: '$line'" unless ($line =~ m/^\s*$re\s*$/);
	return $1;
}

sub tokenize {
	my $line = shift;
#	$s =~ s/\[ .*? \]//g; # remove passages marked as "bad"
	$line =~ s/\;|\?|\.|\,|:|\!|\(|\)|\+|\_|\[|\]|\{|\}//g; # remove punctuation
	my @w = split /\s+/, $line;
	return @w;
}

# the following used to be 
# shamelessly stolen and adapted from http://www.merriampark.com/ldperl.htm
#
# Return the Levenshtein distance (also called Edit distance) 
# between two lists
#
# The Levenshtein distance (LD) is a measure of similarity between two
# lists, denoted here by s1 and s2. The distance is the number of
# deletions, insertions or substitutions required to transform s1 into
# s2. The greater the distance, the more different the lists are.
#
# The algorithm employs a proximity matrix, which denotes the distances
# between sublists of the two given lists. Read the embedded comments
# for more info. If you want a deep understanding of the algorithm, print
# the matrix for some test lists and study it
#
# The beauty of this system is that nothing is magical - the distance
# is intuitively understandable by humans
#
# The distance is named after the Russian scientist Vladimir
# Levenshtein, who devised the algorithm in 1965
#
#
# Meanwhile, more input from CPAN (Text::Brew) has been used to not
# only output the least cost but also the edit operations involved.
# This allows to reconstruct which words in two sequences go together.
# Unfortunately, I had to fork Text::Brew, because they don't support lists
# instead of strings. See MyBrew.pm for implementation details 
# (just very few changes compared to the original)
#
# actually change levenshtein to use MyBrew.pm
#
sub levenshtein {
    # $s1 and $s2 are the two strings
    # $len1 and $len2 are their respective lengths
    #
    my ($ref1, $ref2) = @_;
    my @ar1 = @{$ref1};
    my @ar2 = @{$ref2};
    my ($len1, $len2) = ($#ar1 + 1, $#ar2 + 1);
#print "levenshteining the following two lists: \n";
#print join " ", @ar1;
#print "\n and\n" . join (" ", @ar2) . "\n";
    # If one of the strings is empty, the distance is the length
    # of the other string
    #
    return $len2 if ($len1 == 0);
    return $len1 if ($len2 == 0);

    my %mat;

    # Init the distance matrix
    #
    # The first row to 0..$len1
    # The first column to 0..$len2
    # The rest to 0
    #
    # The first row and column are initialized so to denote distance
    # from the empty string
    #
    for (my $i = 0; $i <= $len1; ++$i) {
        for (my $j = 0; $j <= $len2; ++$j) {
            $mat{$i}{$j} = 0;
            $mat{0}{$j} = $j;
        }
        $mat{$i}{0} = $i;
    }

    # Some char-by-char processing is ahead, so prepare
    # array of chars from the strings
    #
#    my @ar1 = split(//, $s1);
#    my @ar2 = split(//, $s2);

    for (my $i = 1; $i <= $len1; ++$i) {
        for (my $j = 1; $j <= $len2; ++$j) {
            # Set the cost to 1 iff the ith char of $s1
            # equals the jth of $s2
            # 
            # Denotes a substitution cost. When the char are equal
            # there is no need to substitute, so the cost is 0
            #
            my $cost = ($ar1[$i-1] eq $ar2[$j-1]) ? 0 : 1;

            # Cell $mat{$i}{$j} equals the minimum of:
            #
            # - The cell immediately above plus 1
            # - The cell immediately to the left plus 1
            # - The cell diagonally above and to the left plus the cost
            #
            # We can either insert a new char, delete a char or
            # substitute an existing char (with an associated cost)
            #
            $mat{$i}{$j} = List::Util::min($mat{$i-1}{$j} + 1,
                                $mat{$i}{$j-1} + 1,
                                $mat{$i-1}{$j-1} + $cost);
        }
    }

    # Finally, the Levenshtein distance equals the rightmost bottom cell
    # of the matrix
    #
    # Note that $mat{$x}{$y} denotes the distance between the substrings
    # 1..$x and 1..$y
    #
    return $mat{$len1}{$len2};
}

###############

# runCached allows to ask questions to a processor concerning
sub runCached {
	my ($question, $processor, $command) = @_;
	my $hash = md5_hex($question);
	chomp $hash;
	print "hash for *$question* is *$hash*\n" if (DEBUG > 0);
	# create tmpdir if necessary
	`mkdir $TMPDIR` unless ( -e "$TMPDIR");
	`mkdir $TMPDIR/$processor` unless ( -e "$TMPDIR/$processor");
	if ( -e "$TMPDIR/$processor/$hash.info") {
		# check that info file matches what we expect, die or warn otherwise
		open INFO, '<', "$TMPDIR/$processor/$hash.info";
		my ($oldQuestion, $oldCommand) = <INFO>;
		chomp $oldQuestion; chomp $oldQuestion;
		chomp $oldCommand; chomp $oldCommand;
		close INFO;
		die "hash collision or cache corruption for question $question, hash $hash" if ($oldQuestion ne $question);
		warn "the command for the processor $processor has changed." if ($oldCommand ne $command);
	} else {
		# create info file
		open INFO, '>', "$TMPDIR/$processor/$hash.info";
		print INFO "$question\n$command\n";
		close INFO;
	}
	# create result file if it doesn't exist
	unless ( -e "$TMPDIR/$processor/$hash.result") {
		system "echo $question | $command > $TMPDIR/$processor/$hash.result";
	}
	open RESULT, '<', "$TMPDIR/$processor/$hash.result";
	my @result = <RESULT>;
	close RESULT;
	return wantarray ? @result : join "\n", @result;
}

sub readSphinx3Transcript {
	my $filename = $_[0];
	open GOLD, '<', $filename or die "could not open gold file $filename\n";
	my %gold;
	# read the gold-file (which must be in sphinx-3 transcript format) into the hash
	# the keys are the file-IDs, the values the transcript
	map { m/^(.*) \((.*)\)$/ or die "something did not match in transcript $filename: $_\n"; $gold{$2} = lc($1); } <GOLD>;
	close GOLD;
	return %gold;
}

sub filterTranscript {
	my $line = $_[0];
	$line =~ s/_/ /g; 
#	$line =~ s/ \.+ / <sil> /g; # change silence marker
        $line =~ s/ \.+ / /g; # remove silence marker
	my ($commentmarker) = $line =~ s/<(.+?)>/ /g; # remove ALL markers
print STDERR "removed \"<>\" marker: $1\n" if ($commentmarker);
	my ($ctmarker) = $line =~ s/\[ct(.+?)\]/ /g; # remove ct markers (corrected transcription)
print STDERR "removed \"[ct\" marker: $1\n" if ($ctmarker);
	$line =~ s/\-/ /g; # S-Teil should become S Teil, not STeil
 	$line =~ s/[\{\}\(\)\.\+\,\:\!\?\[\]\\\"\/\`\|]//g; # remove punctuation
	$line =~ s/\s+/ /g; # change all whitespace to one simple space
	$line =~ s/^\s+//g; # remove leading whitespace
	$line =~ s/\s+$//g; # remove trailing whitespace
	return $line;
}

return 1;
