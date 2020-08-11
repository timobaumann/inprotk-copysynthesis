#!/usr/bin/perl

use strict;
use warnings;

require "MyBrew.pm";
use sort 'stable'; # assert stable sorting behaviour

my @consonants = ("\\?", 'p', 'b', 't', 'd', 'k', 'g', 'Q',
#	     'pf', 'ts', 'tS', 
	     'f', 'v', 'T', 's', 'z', 'S', 'Z', 'C', 'j', 'x', 'h', 
	     'm', 'n', 'N', 'w', 'l', 'r', 
	     'l:');
my @vowels = ('i', 'I', 'e', 'E', 'a', 'o', 'O', 'u', 'U', 'y', 'Y', '2', '9', 
	     'i:', 'e:', 'E:', 'a:', 'o:', 'O:', 'u:', 'y:', '2:', 
	     'aI', 'aU', 'OY', 
	     'a~', 'a~:', 'o~:', 
	     '@', '6');
my @sampa = ('#', '"', "'", "\\.", "\\+", "#", "<sil>"
	    );
push @sampa, @consonants;
push @sampa, @vowels;

# prepare regular expressions
@sampa = sort {length $b <=> length $a } @sampa; 
my $sampaRE = "(" . join("|", @sampa) . ")";
my $consonantRE = "(" . join("|", @consonants) . ")";

package Lexeme;

# create a new lexeme
sub new {
	# $spelling is a string
	# $canonicalPron is the prototypical pronunciation
	my ($spelling, $canonicalPron) = @_;
#	$canonicalPron =~ m/ / or die "badly formatted: $canonicalPron";
	return bless {  spelling => $spelling, 
			canonic => $canonicalPron, 
			instances => [], # list of phone-lists that determine actual/seen pronunciations
			pronunciations => {} }; # contains (textual) pronuncations as keys and occurrence counts as values
}

sub instantiateCanonicalPronunciation {
	my $self = $_[0];
	my @phones = split " ", $self->{canonic};
	push @{$self->{instances}}, \@phones;
}

sub removePhoneFromPronunciations {
	my ($self, $phone) = @_;
	foreach my $instance (@{$self->{instances}}) {
		$instance = [grep { $_ ne $phone } @{$instance}];
	}
}

sub replacePhoneInPronunciations {
	my ($self, $oldPhone, $newPhone) = @_;
	foreach my $instance (@{$self->{instances}}) {
		$instance = [map { $_ eq $oldPhone ? $newPhone : $_ } @{$instance}];
	}
}

sub pronunciationHash {
	my @pronunciation = @_;
	return join " ", map { $_->{text} } @pronunciation; # sort of hash at least
}

sub addPronunciation {
	# @pronunciation is *one* pronunciation (a sequence of MAU: labels)
	my ($self, @pronunciation) = @_;
	$self->{pronunciations}->{pronunciationHash(@pronunciation)}++;
	push @{$self->{instances}}, \@pronunciation; # store this occurrence for later reference
}

sub getOccurrences {
	my $self = $_[0];
	my $count = 0;
	map { $count += $_ } values %{$self->{pronunciations}};
	return $count;
}

sub mostCommonStrings {
	my $self = $_[0];
	return "" unless ($self->getOccurrences() > 0);
	my $returnString = $self->{spelling} . "\t";
	my %prons = %{$self->{pronunciations}};
	my @prons = keys %prons;
	if ($self->{canonic}) {
		@prons = sort { MyBrew::distance($a, $self->{canonic}, {-output => 'distance'}) <=>
				MyBrew::distance($b, $self->{canonic}, {-output => 'distance'}) } @prons;
	}
	my @sortedProns = sort { $prons{$b} <=> $prons{$a} } @prons;
	if ($self->getOccurrences() > 2) {
		my $accVariants = 0.0;
		my $numVariants = 0;
		while (($accVariants < 0.65) && ($numVariants < 5)) {
			my $pron = shift @sortedProns;
			my $pronProb = $prons{$pron} / $self->getOccurrences();
			last if (($pronProb < 0.20) && ($numVariants > 0));
			$returnString .= $self->{spelling} . "($numVariants)\t" if ($numVariants > 0);
			$returnString .= $pron . "\n";
			$accVariants += $pronProb;
			$numVariants++;
		}
	} else {
		$returnString .= (shift @sortedProns) . "\n";
	}
	return $returnString;
}

sub mostCommonString {
	my $self = $_[0];
	my $returnString = $self->{spelling} . "\t";
	my %prons = %{$self->{pronunciations}};
	my @sortedProns = sort { $prons{$b} <=> $prons{$a} } keys %prons;
	$returnString .= shift @sortedProns;
	$returnString .= "\n";
	return $returnString;
}

sub toString {
	my $self = $_[0];
	my $returnString = $self->{spelling} . "(" . $self->getOccurrences() . "): ";
	my %prons = %{$self->{pronunciations}};
	my @prons = keys %prons;
	if (defined $self->{canonic}) {
		$returnString .= "{$self->{canonic}} ";
		@prons = sort { MyBrew::distance($a, $self->{canonic}, {-output => 'distance'}) <=>
				MyBrew::distance($b, $self->{canonic}, {-output => 'distance'}) } @prons;
	}
	$returnString .= "[" . join ", ", map { "$_ ($prons{$_})" } sort { $prons{$b} <=> $prons{$a} } @prons;
	$returnString .= "]\n";
	return $returnString;
}

sub toSimpleString {
	my $self = $_[0];
	return $self->{spelling} . "\t" . $self->{canonic} . "\n";
}

sub tokenizeSampa {
	my $sampa = pop;
	# sort symbols based on length
	$sampa =~ s/$sampaRE/$1 /g;
	$sampa =~ s/  +/ /g;
	$sampa =~ s/ +$//;
	return $sampa;
}

sub vmToUnicode {
	my $self = $_[0];
	my $spelling = $self->{spelling};
	$spelling =~ s/"a/ä/g;
	$spelling =~ s/"o/ö/g;
	$spelling =~ s/"u/ü/g;
	$spelling =~ s/"A/Ä/g;
	$spelling =~ s/"O/Ö/g;
	$spelling =~ s/"U/Ü/g;
	$spelling =~ s/"s/ß/g;
	$self->{spelling} = $spelling;
}

sub postProcessSampa {
	my ($self, $skipAccents, $skipGlottalStop, $skipSylBounds) = @_;
#	my @canonic = split " ", $self->{canonic};
	my $canonic = $self->{canonic};
	$canonic =~ s/# #/./g; # get rid of phrasal boundaries (but insert syllable boundary!)
	$canonic =~ s/# \+//g; # get rid of inflectional boundaries
	$canonic =~ s/\+//g; # get rid of derivational or enclitic boundary
	if ($skipSylBounds) {
		$canonic =~ s/#//g; # get rid of all compound boundaries
		$canonic =~ s/\.//g; # get rid of all syllable boundaries
	} else {
		# replace compound boundaries with syllable boundaries if appropriate, and delete if not:
		# first get rid of multiple whitespace for simplicity
		$canonic =~ s/  +/ /g;
		$canonic =~ s/ +$//;
		# in .C# contexts, # does not imply a syllable boundary:
		$canonic =~ s/\. $consonantRE #/. $1/g;
		# in all other contexts, it does:
			$canonic =~ s/#/./g;
	}
	$canonic =~ s/'//g if ($skipAccents);
	$canonic =~ s/\?//g if ($skipGlottalStop);
	$canonic =~ s/  +/ /g;
	$canonic =~ s/ +$//;
	$self->{canonic} = $canonic; #join " ", @canonic;
}

return 1;
