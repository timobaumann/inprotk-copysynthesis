#!/usr/bin/perl

# perl module that defines a sequence of alignments and the corresponding gold alignment
package NBestList;

use strict;
use warnings;
require "Util.pm";
require "Alignment.pm";

#create a new NBestAlignmentSequence
sub new {
	# @alignments: alignments contained in this nbest list
	my @alignments = @_;
	my $time = $alignments[0]->{time};
# FIXME: check that all alignments have identical time information!
	return bless { time => $time, alignments => \@alignments, hasValidWEList => "false", WEList => [], goldWords => [] };
}

sub newEmptyNBestList {
	my $al = Alignment::newEmptyAlignment();
	return bless { alignments => [$al], time => 0 };
}

######## OUTPUT Functions #########

sub toSphinxLines {
	my $self = shift;
	my @lines = ();
	foreach my $alignment (@{$self->{alignments}}) {
		push @lines, $alignment->toSphinxLines();
		push @lines, "\n";
	}
	return @lines;
#	return map { ($_->toSphinxLines(), "\n") } @{$self->{alignments}};
}

######## getters/setters #########

sub getN {
	my $self = shift;
	return scalar @{$self->{alignments}};
}

sub getNth {
	my ($self, $n) = @_;
	return $self->{alignments}->[$n];
}

######## getters/setters related to WER #########

sub setGoldWords {
	my ($self, @words) = @_;
#	print STDERR "WARNING, you are setting an empty \@words (in NBestList::setGoldWords at time $self->{time})" if ($#words < 0);
	$self->{goldWords} = \@words;
	$self->invalidateWEList();
}

sub invalidateWEList {
	my $self = shift;
	$self->{hasValidWEList} = "false";
}

sub getAllWE {
	my $self = shift;
	my @WE;
	if ((exists $self->{hasValidWEList}) && ($self->{hasValidWEList} eq "true")) {
		@WE = @{$self->{WEList}};
	} else {
		my @words = @{$self->{goldWords}};
		foreach my $alignment (@{$self->{alignments}}) {
			push @WE, Util::levenshtein([$alignment->getWords()], \@words);
		}
		@{$self->{WEList}} = @WE;
		$self->{hasValidWEList} = "true";
	}
	return @WE;
}

sub getAllWER {
	my $self = shift;
	my @WE = $self->getAllWE();
	my $words = scalar @{$self->{goldWords}};
	my @WER = map { $_ / $words } @WE; 
	return @WER;
}

# either least or worst word error
sub getMaxWE {
	my ($self, $dir) = @_;
	my @words = @{$self->{goldWords}};
	# the idea is to look for the least WER with $dir=1 and for the highest WER with $dir=-1
	$dir = ($dir > 0) ? 1 : -1;
	my ($maxWE, $maxAl, $maxPos) = (99999, undef, undef);
	my $i = 0;
	foreach my $WE ($self->getAllWE()) {
#	foreach my $alignment (@{$self->{alignments}}) {
#		my $WE = $dir * Util::levenshtein([$alignment->getWords()], \@words);
		$WE *= $dir;
		if ($WE < $maxWE) {
			$maxWE = $WE;
			$maxAl = $self->{alignments}->[$i];
			$maxPos = $i;
		}
		$i++;
	}
	# for negative dir, WE was negative; so fix this
	$maxWE *= $dir;
	return ($maxWE, $maxPos, $maxAl);
}

sub getLeastWER {
	my $self = shift;
	my @words = @{$self->{goldWords}};
	my ($bestWE, $bestPos, $bestAl) = $self->getMaxWE(1, @words); 
	my $bestWER = (scalar @words != 0) ? $bestWE / ($#words + 1) : 1;
	return wantarray ? ($bestWER, $bestPos, $bestAl) : $bestWER;
}

sub getWorstWER {
	my $self = shift;
	my @words = @{$self->{goldWords}};
	my ($bestWE, $bestPos, $bestAl) = $self->getMaxWE(-1);
	my $bestWER = (scalar @words != 0) ? $bestWE / scalar @words : 1;
	return wantarray ? ($bestWER, $bestPos, $bestAl) : $bestWER;
}

# an n-best list matches a prefix if one of the contained alignments starts 
# with the given prefix of words
sub matchesPrefix {
	my ($self, @words) = @_;
	foreach my $alignment (@{$self->{alignments}}) {
		my @currWords = $alignment->getWords('keepsilences');
		return (0 == 0) if (Util::listPrefix(\@words, \@currWords));
	}
	return (0 == 1); # false
}

######## N-Best handling ##########

sub limitN {
	my ($self, $N) = @_;
	if ($#{$self->{alignments}} + 1 > $N) {
		@{$self->{alignments}} = @{$self->{alignments}}[0..$N];
		if ($self->{hasValidWEList} eq "true") {
			my @WE = @{$self->{WEList}};
			@{$self->{WEList}} = @WE[0..$N];
		}
#		$self->invalidateWEList();
	}
}

sub DESTROY {
	my $self = shift;
	$self->{goldWords} = undef;
	$self->{WEList} = undef;
	$self->{alignments} = undef;
}


