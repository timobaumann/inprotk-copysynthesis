#!/usr/bin/perl

# perl module that defines a lattice of alignments
package Lattice;

use strict;
use warnings;

require "NBestList.pm";
require "Alignment.pm";

# create a new lattice/tree from an n-best list
sub new {
	my ($nbestList) = @_;
	my $lat = bless { time => $nbestList->{time}, root => Node::new('<s>') };
	foreach my $alignment (@{$nbestList->{alignments}}) {
		$lat->integrate($alignment);
	}
	return $lat;
}

# integrate an alignment into the lattice
sub integrate {
	my ($self, $alignment) = @_;
	my @words = $alignment->getWords('keep');
	$self->{root}->integrate(@words);
}

sub markGoldPath {
	my ($self, $path, $gold) = @_;
	my @path = $path->getWords('keep'); # path through the tree
	my @goldWords = $gold->getWords('keep');
	$self->{root}->markGoldPath(\@path, \@goldWords);
}

# shorten the lattice's (common) root so that a maximum of ARG steps remains
sub shortenTo {
	my ($self, $MAX) = @_;
	my $longestPath = $self->{root}->getLongestPath();
	my $root = $self->{root};
	while ($longestPath > $MAX) {
		my @subNodes = $root->getNodes();
		last if ($#subNodes < 0 || $#subNodes > 1);
		$root = $subNodes[0];
		$root->{name} = "..." . $root->{name};
		$longestPath--;
	}
	return $root;
}

# return a string representation of this tree
sub toText {
	my ($self) = @_;
	return $self->{root}->toText();
}

# return a string in the DOT language that describes this tree
sub toDot {
	my ($self) = @_;
	return 'digraph tree {
graph [ rankdir = LR ];
edge [ arrowtail = diamond, arrowhead = none, dir = back ];
node [ shape = none ];
' . $self->shortenTo(8)->toDot() . "}\n";
}

return 1;

# package that defines a node in a tree.
# a node has a name, count and a list of successor nodes
package Node;
use List::Util qw(max); # used in getLongestPath()

my $id = 0;

sub new {
	my ($name) = @_;
	return bless { name => $name, count => 0, nodes => {}, id => $id++ };
}

# get a sub node or create one if there's none matching the given name yet
sub getNode {
	my ($self, $name) = @_;
#print "Searching for node $name within $self->{name}\n";
	unless (exists $self->{nodes}->{$name}) {
#		print "Creating node $name within $self->{name}\n";
		$self->{nodes}->{$name} = Node::new($name);
	}
	return $self->{nodes}->{$name};
}

sub getNodes {
	my ($self) = @_;
	return values %{$self->{nodes}};
}

sub getLongestPath {
	my ($self) = @_;
	if (scalar $self->getNodes() == 0) {
		return 1;
	} else {
		return 1 + max(map { $_->getLongestPath() } $self->getNodes());
	}
}

#recursively integrate a path (given as word tokens) into the tree
sub integrate {
	my ($self, @names) = @_;
	$self->{count}++;
	if (@names) {
		my $next = shift @names;
		my $nextNode = $self->getNode($next);
		$nextNode->integrate(@names);
	}
}

sub markGoldPath {
	my ($self, $path, $gold) = @_;
	my $nextNode = shift @{$path};
	return unless ($nextNode);
	my $goldNode = shift @{$gold};
	my $color = 'green';
	if ($nextNode ne $goldNode) {
		$color = 'red';
		unshift @{$gold}, 'XXX_THIS_SHOULD_NOT_BE_IN_THE_ASR_XXX'; # to avoid marking anything green later on
	}
	$self->{color} = $color;
	$self->{marked} = $nextNode;
	$self->getNode($nextNode)->markGoldPath($path, $gold);
}

sub toText {
	my ($self) = @_;
	my $subText = "";
	map { $subText .= $_->toText() } $self->getNodes();
	return "[Node with ID " . $self->{id} . " and name " . $self->{name} . " with count " . $self->{count} . 
	       ($subText ne "" ? " and sub nodes " : "") . $subText . "]";
}

sub countWeights {
	my ($self) = @_;
	my $count = 0;
	map { $count += $_->{count} } $self->getNodes();
	return $count;
}

sub toDot {
	my ($self) = @_;
	my $myID = $self->{id};
	my $text = "$myID [label=\"$self->{name}\"];\n";
	my $weightTotal = $self->countWeights();
	map {	my $edgeWeight = 3 * $_->{count} / $weightTotal;
		my $color = ($self->{marked} && $self->{marked} eq $_->{name}) ? (", color=" . $self->{color}) : ('');
		$text .= $_->toDot() . "$myID -> " . $_->{id} . " [penwidth=\"$edgeWeight\"$color];\n" 
		} $self->getNodes();
	return $text;
}

return 1;
