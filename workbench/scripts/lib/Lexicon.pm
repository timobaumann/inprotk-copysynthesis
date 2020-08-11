#!/usr/bin/perl

use strict;
use warnings;

package Lexicon;
require "Lexeme.pm";

sub new {
	my %entries;
	return bless { entries => \%entries };
}

sub newFromFile {
	my ($filename) = @_;
	my $lex = new();
	$lex->openCanonicalLexicon($filename);
	return $lex;
}

sub openCanonicalLexicon {
	my ($self, $filename) = @_;
	open(LEX, '<', $filename) or die "Cannot open lexicon $filename: $!";
	while (my $line = <LEX>) {
		chomp $line; chomp $line;
		next if ($line =~ m/^#/); # allow comments
		next if ($line =~ m/^$/); # skip empty lines
		$line =~ m/(.+)\t(.+)/ or die "malformatted line $line in lexicon $filename\n";
		my ($spelling, $pronunciation) = ($1, $2);
		my $variant = 0;
		if ($spelling =~ m/(.*)\((\d+)\)$/) {
			$spelling = $1;
			$variant = $2;
		}
		$pronunciation = Lexeme::tokenizeSampa($pronunciation);
		!$self->hasEntry($spelling) && $variant==0 or warn "ignoring multiple occurence of $spelling in lexicon $filename\n";
		$self->addCanonical($spelling, $pronunciation);
	}
}

sub addCanonical {
	my ($self, $spelling, $pronunciation) = @_;
	$self->{entries}->{$spelling} = Lexeme::new($spelling, $pronunciation);
}

sub instantiateCanonicalPronunciations {
	my ($self) = @_;
	map { $_->instantiateCanonicalPronunciation() } values %{$self->{entries}};
}

sub toPhoneset {
	my ($self) = @_;
	my %phoneset;
	foreach my $lexeme (values %{$self->{entries}}) {
		foreach my $instance (@{$lexeme->{instances}}) {
			foreach my $phone (@{$instance}) {
				$phoneset{$phone}++;
			}
		}
	}
	return %phoneset;
}

sub add {
	my ($self, $spelling, @pronunciation) = @_;
	if ($pronunciation[$#pronunciation]->{text} eq '_') {
		pop @pronunciation;
	}
	$self->{entries}->{$spelling} = Lexeme::new($spelling, undef) unless ($self->hasEntry($spelling));
	$self->{entries}->{$spelling}->addPronunciation(@pronunciation);
}

sub hasEntry {
	my ($self, $spelling) = @_;
	return exists $self->{entries}->{$spelling};
}

# lookup a spelling, trying various normalizations (lc, uc, maybe recodings)
# return false if normalization fails
sub getNormalizedSpelling {
	my ($self, $spelling) = @_;
	return $spelling if ($spelling =~  m/<s>|<\/s>|<sil>/);
	return $spelling if ($self->hasEntry($spelling));
	# try all lowercase
	$spelling = lc($spelling);
	return $spelling if ($self->hasEntry($spelling));
	# try upper-casing the first character
	# FOR spellings (which start with $), we want to uppercase the second character
	$spelling =~  s/^(\$?.)/uc($1)/e;
	return $spelling if ($self->hasEntry($spelling));
	# give up
	return ();
}

sub outputByFrequency {
	my $self = $_[0];
	my @sortedList = sort { $a->getOccurrences() <=> $b->getOccurrences() } values %{$self->{entries}};
	foreach my $lexeme (@sortedList) {
		print $lexeme->toString();
	}
}

sub outputOnlyMostCommonPronunciations {
	my $self = $_[0];
	my @sortedList = sort { $a->getOccurrences() <=> $b->getOccurrences() } values %{$self->{entries}};
#	my @sortedList = map { $self->{entries}->{$_} } sort { lc($a) cmp lc($b) } keys %{$self->{entries}};
	foreach my $lexeme (@sortedList) {
		print $lexeme->mostCommonStrings();
	}	
}

sub outputByLexicalOrder {
	my $self = $_[0];
	my @sortedList = map { $self->{entries}->{$_} } sort { lc($a) cmp lc($b) } keys %{$self->{entries}};
	foreach my $lexeme (@sortedList) {
		print $lexeme->toSimpleString();
	}
}

return 1;
