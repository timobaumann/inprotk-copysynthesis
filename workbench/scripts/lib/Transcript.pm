#!/usr/bin/perl

use strict;
use warnings;

package Transcript;

sub newFromFile {
	my ($filename) = @_;
	open TRANS, '<', $filename or die "Could not open $filename\n";
	my $self = bless { orderedEntries => [], entries => {} };
	while (my $line = <TRANS>) {
		$line =~  m/(.*) \((.*?)\)/ or die "Could not parse line $line in transcript $filename\n";
		my ($transcript, $id) = ($1, $2);
		$self->addEntry($id, $transcript);
	}
	close TRANS;
	return $self;
}

sub writeToFile {
	my ($self, $filename) = @_;
	open TRANS, '>', $filename or die "Could not open $filename\n";
	foreach my $id ($self->getIDs()) {
		my $transcript = $self->getTranscript($id);
		print TRANS "$transcript ($id)\n";
	}
	close TRANS;
}

sub addEntry {
	my ($self, $id, $transcript) = @_;
	!exists $self->{entries}->{$id} or die "ID $id is not unique.\n";
	$self->{entries}->{$id} = $transcript;
	push @{$self->{orderedentries}}, $id;
}

sub getIDs {
	my ($self) = @_;
	return @{$self->{orderedentries}};
}

sub getTranscript {
	my ($self, $id) = @_;
	return $self->{entries}->{$id};
}

sub setTranscript {
	my ($self, $id, $transcript) = @_;
	$self->{entries}->{$id} = $transcript;
}

return 1;
