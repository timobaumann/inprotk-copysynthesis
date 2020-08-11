#!/usr/bin/perl

# perl module that defines a sequence of alignments and the corresponding gold alignment
package NBestAlignmentSequence;

use strict;
use warnings;
require "Util.pm";
require "Alignment.pm";
require "NBestList.pm";
require "SingularAlignmentSequence.pm";
use Storable;
use Carp;

#create a new NBestAlignmentSequence
sub new {
	# $gold: gold standard alignment associated with this alignment sequence
	# @nblists: nbest alignments contained in this sequence
	my ($gold, $nblists) = @_;
	return bless { gold => $gold, nblists => $nblists };
}

######## INPUT Functions #########

sub newNBestSeqFromFile {
	my $filename = shift;
	$filename =~ s/.pls(.gz)?//;
	my $seq;
	# read a serialized cached file if available
	if ( -e "$filename.pls") {
		print STDERR "[NBestAlignmentSequence::newNBestSeqFromFile] serving from $filename.pls\n";
		$seq = retrieve "$filename.pls";
	} elsif ( -e "$filename.pls.gz") {
		#print STDERR "[NBestAlignmentSequence::newNBestSeqFromFile] serving from CACHED $filename.pls.gz\n";
		open PLS, "gunzip -c $filename.pls.gz | " or die "oups: $!";
		$seq = Storable::retrieve_fd(*PLS);
		close PLS;
	} else {
		if ($filename =~ m/\.bz2$/) {
			open inFile, "bunzip2 -c $filename | " or die "oups: $!";
		} else {
			open inFile, '<:crlf', $filename or die "opening $filename: $!";
		}
		my @lines = <inFile>;
		close inFile;
		$seq = newNBestSeqFromLines(@lines);
		# create a cache file to speed up the next access
		open PLS, "|gzip -c > $filename.pls.gz" or open PLS, ">$filename.pls" or die "oups: $!, $^E";
		Storable::store_fd $seq, *PLS;
		close PLS;
	}
	return $seq;
}

sub newNBestSeqFromLines {
	my @lines = @_;
	my @alignments = ();
	my @alLines = ();
	my $goldAlignment;
	foreach my $line (@lines) {
		if ($line eq "\n") {
			next unless (@alLines); # be robust to multiple blank lines
			my $alignment = Alignment::newAlignmentFromSphinxLines(@alLines);
			if ($alignment->isGold()) {
				$goldAlignment = $alignment;
			} else {
				push @alignments, $alignment;
			}
			@alLines = ();
		} else {
			push @alLines, $line;
		}
	}
	push @alignments, Alignment::newAlignmentFromSphinxLines(@alLines) if (@alLines);
	use sort 'stable';
	my @sortedAlignments = sort { $a->{time} <=> $b->{time} } @alignments;
	if (!Util::listEqual(\@sortedAlignments, \@alignments)) {
		warn "something is wrong with the ordering of alignments, fixing silently.\n";
		@alignments = @sortedAlignments;
	}
	my @nblists = ();
	my $time = $alignments[0]->{time};
	my @currAlignments = shift @alignments;
	foreach my $alignment (@alignments) {
		if ($alignment->{time} > $time) {
#print STDERR "now at time $alignment->{time}\nadding";
#print STDERR join "", map { $_->toSphinxLines() } @currAlignments;
#print STDERR "\n";
			push @nblists, NBestList::new(@currAlignments);
			$time = $alignment->{time};
			@currAlignments = ($alignment);
		} elsif ($alignment->{time} == $time) {
			push @currAlignments, $alignment;
		} else {
			die "something is wrong with the ordering of alignments at time $time.\n";
		}
	}
	push @nblists, NBestList::new(@currAlignments);
#	die "nbest-sequences must contain alignments from at least two nbest-lists (instead of just $#nblists)!" if ($#nblists < 1);
	
	$goldAlignment = $nblists[-1]->getNth(0) if (!defined $goldAlignment);
	return new($goldAlignment, \@nblists);
}

######## OUTPUT Functions #########

sub saveToSphinxFile {
	my $self = shift;
	my $filename = shift;
	open outFile, '>', $filename or die "Could not write to file $filename\n";
	print outFile join "", $self->toSphinxLines();
	close outFile;
}

sub toSphinxLines {
	my $self = shift;
	return map { $_->toSphinxLines() } @{$self->{nblists}};
}

######## simple getters/setters ##########

sub getGold {
	my $self = shift;
	return $self->{gold};
}

sub setGold {
	my ($self, $gold, $mode) = @_;
	$mode = 'non' unless (defined $mode);
	$self->{gold} = $gold;
	# if mode is 'recursively', then propagate the gold words to the nbest lists
	if ($mode =~ m/recur/) {
		foreach my $nblist (@{$self->{nblists}}) {
			$nblist->setGoldWords($gold->getWordsUpTo($nblist->{time}));
		}
	}
}

# given a word list, this will select (one of the) final alignments with the least WER compared to @gold as future gold-alignment
sub selectBestFinalAsGold {
	my ($self, @gold) = @_;
	my ($WER, $pos);
	my $finalList = $self->getNBestListAt(99999);
	$finalList->setGoldWords(@gold);
	($WER, $pos, $self->{gold}) = $finalList->getLeastWER(@gold);
	print STDERR "[NBestAlignmentSequence::selectBestFinalAsGold]: Gold is at pos $pos and has WER of $WER\n" if (($WER != 0) && ($pos != 0));
	return $self->{gold};
}

######## N-Best handling ##########

sub limitN {
	my ($self, $N) = @_;
	map { $_->limitN($N) } @{$self->{nblists}};
}

# return a SingularAlignmentSequence by getting the n'th best hypothesis 
# from each n-best list (if there is an n'th best hypothesis at that time)
# by default, get the best hypothesis
sub toSingularAlignmentSequence {
	my ($self, $N) = @_;
	$N = 0 unless (defined $N);
	my @bestAls;
	foreach my $nblist (@{$self->{nblists}}) {
		if ($nblist->getN() > $N) {
			push @bestAls, $nblist->getNth($N);
		}
	}
#	my @bestAls = map { $_->getNth(0) } @{$self->{nblists}};
	return SingularAlignmentSequence::new($self->getGold(), \@bestAls);
}

# crop away all n-best-lists that are outside of the "active" phase of the gold standard (whatever that is at the moment!)
# the active phase consists of all n-best-lists from the start of the first word up to the end of
# the last word (excluding silence) in gold
# NOTE: this is different from what SingularAlignmentSequence::cropSequence() does!
# this is restricted to the active phase according to gold, while the other is restricted to the active phase according to ASR
# TODO/FIXME: why do we do this?
sub cropSequence {
	my $self = shift;
	my @nblists = @{$self->{nblists}};
	my $gold = $self->getGold();
	my ($xmin, $xmax) = ($gold->{labels}->[0]->{xmin}, $gold->{labels}->[-1]->{xmax});
	@nblists = grep { (($_->{time} >= $xmin) && ($_->{time} <= $xmax)) } @nblists;
	@{$self->{nblists}} = @nblists;
}

######## somewhat advanced getters #########

# get the NBestList with the highest getTime() which still has getTime() <= $time
sub getNBestListAt {
	my ($self, $time) = @_;
	my @nblists = @{$self->{nblists}};
	return NBestList::newEmptyNBestList() if ($nblists[0]->{time} > $time);
	# use binary search which *really* helps performance
	my $minpos = 0;
	my $maxpos = $#nblists + 1;
	my $lastpos = int(($minpos + $maxpos) / 2) - 1;
	my $pos;
	while ($maxpos - $minpos > 0) {
		$pos = int(($minpos + $maxpos) / 2);
		last if ($lastpos == $pos); # just to be sure that the algorithm always terminates
		my $cmp = $time - $nblists[$pos]->{time};
		last if (abs($cmp) < 0.00001); # avoid floating point annoyances
		if ($cmp > 0) {
			$minpos = $pos;
		} else {
			$maxpos = $pos;
		}
		$lastpos = $pos;
	}
	return $nblists[$pos];
}

###### evaluation ######

# get the delays (relative to the gold alignment) of first occurrence of each
# word (with proper prefix) in gold
# as implemented, the final alignment must match to gold
sub getFODelays {
	my $self = shift;
	my $refAlignment = $self->getGold();
	# get all labels
	my @refLabels = $refAlignment->getLabels();
	carp "there are no words in this file:" . $self->{filename}  . "\n"if ($#refLabels < 0);
	my $currentWord = 0;
	my @nbestlists = (@{$self->{nblists}}); # all nbest lists, we'll unshift until we're done
	my @prefix = (); # this will be filled with more and more words
	my %delay_FO = ( from_start => [], to_end => [], word_rel => [] );
	for my $refLabel (@refLabels) {
		my $refWord = $refLabel->{text};
		push @prefix, $refWord; # add one more word to the prefix
		my $nbestlist = $nbestlists[0];
		while (!$nbestlist->matchesPrefix(@prefix)) {
			$nbestlist = shift @nbestlists;
		}
		#print STDERR join (":", @prefix) . " matches at time " . $nbestlist->{time} . "\n";
		unless ($refLabel->isSilent()) {
			my ($from_start, $to_end, $word_rel) = 
				$refLabel->getTimings($nbestlist->{time});
			push @{$delay_FO{from_start}}, $from_start;
			push @{$delay_FO{to_end}}, $to_end;
			push @{$delay_FO{word_rel}}, $word_rel;
		}
		last unless (@nbestlists);
	}
	return %delay_FO;
}

#sub getFODelays {
#	my $self = shift;
#	my $refAlignment = $self->getGold();
#	# get all labels
#	my @refLabels = $refAlignment->getLabels();
#	# and the corresponding words
#	my @refWords = map { $_->{text} } @refLabels;
#	
#	my $numWords = $#refWords;
#	carp "there are no words in this file:" . $self->{filename}  . "\n"if ($numWords < 0);
#	my $currentWord = 0;
#	my %delay_FO = ( from_start => [], to_end => [], word_rel => [] );
#	for my $alignment ($self->getAlignments()) {
#		croak "assertion: trying beyond $numWords in file " . $self->{filename} . "\n" . $alignment->getTime() if (($currentWord > $numWords) && $numWords > -1);
#		my @currWords = $alignment->getWords('keepsilences');
#		while (($#currWords >= $currentWord) &&
## Frage: müsste man list_starts_with anstatt list_same nehmen?
## Antwort: nein, denn wir werten die Listen jeweils nur bis $currentWord aus. 
#		    (Util::listEqual(\@{[@refWords[0..$currentWord]]}, \@{[@currWords[0..$currentWord]]}))) {
#			# do not measure for silence words:
#			if (!Label::isSilentText($currWords[$currentWord])) {
#				my ($from_start, $to_end, $word_rel) = 
#					$refLabels[$currentWord]->getTimings($alignment->getTime());
#				push @{$delay_FO{from_start}}, $from_start;
#				push @{$delay_FO{to_end}}, $to_end;
#				push @{$delay_FO{word_rel}}, $word_rel;
#			}
#			$currentWord++;
#			# we're done, once all words are processed
#			last if ($currentWord > $numWords);
#		}
#		last if ($currentWord > $numWords);
#	}
#	return %delay_FO;
#}


sub DESTROY {
	my $self = shift;
	$self->{gold} = undef;
	$self->{nblists} = undef;
}

return 1;
