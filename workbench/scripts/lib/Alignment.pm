#!/usr/bin/perl

# perl module that defines an alignment which contains labels
package Alignment;

use strict;
use warnings;
use Carp;
require "Util.pm";
require "Label.pm";
require "IUEdit.pm";
use Scalar::Util qw/blessed/; # to check whether a parameter is of type label
require "MyBrew.pm";
use Switch;
use Statistics::Lite qw/:all/;

########## creation and checks ##########

# create a new Alignment object
sub new {
	# $name: name, 
	# $xmin: start-time of alignment, 
	# $xmax: end-time of alignment, 
	# $labels: reference to a list of labels (see Label.pm)
	# $format: if set to "lax", xmin and xmax will be set automatically 
	# 	to the time spanned by the label sequence
	my ($name, $xmin, $xmax, $labels, $format, $time) = @_;
	my ($labelXMin, $labelXMax) = checkLabels($labels);
	$time = 0 unless (defined $time);
	($xmin, $xmax) = ($labelXMin, $labelXMax) if ((defined $format) && ($format eq 'lax'));
	return bless { name => $name, xmin => $xmin, xmax => $xmax, labels => $labels, time => $time };
}

# create a new, empty Alignment object
sub newEmptyAlignment {
	my $label = Label::new(0.0, 0.0, '<sil>');
	return bless { name => '', xmin => 0, xmax => 0, labels => [$label], time => 0 };
}

# checks that a list (given a reference to it as argument)
# only contains objects of type Label (see Label.pm),
# that the labels are ordered sequentially and are non-overlapping
# returns the time that is spanned by the label sequence
sub checkLabels {
	my @labels = @{$_[0]};
	if ($#labels == -1) {
		return (0, 0);
	} else {
		my $precLabel = $labels[0];
		confess 'labels must be of Type Label: $label!' unless (ref($precLabel) eq 'Label');
		my $xmin = $precLabel->{xmin};
		my $xmax = $precLabel->{xmax};
		foreach my $label (@labels[1..$#labels]) {
			confess "labels must be of Type Label: $label!" unless (ref($label) eq 'Label');
			if ($precLabel->{xmax} > $label->{xmin} + 0.05) { # let's just accept small overlaps, right?
				warn "labels must be sequentially ordered: $precLabel->{text} ends at $precLabel->{xmax} > but $label->{text} starts at $label->{xmin}\n";
				warn "moving the second label\n";
				$label->{xmin} = $precLabel->{xmax};
			}
			$precLabel = $label;
		}
		$xmax = $labels[-1]->{xmax};
		return ($xmin, $xmax);
	}
}

sub connectLabels {
	my ($prevLabel, @labels) = @{$_[0]->{labels}};
	foreach my $label (@labels) {
		$prevLabel->setSuccessor($label);
		$prevLabel = $label;
	}
}

sub groundedInFromTimes {
	my ($self, $lower) = @_;
	for my $label ($self->getLabels()) {
		for my $grounding ($lower->getSpan($label)->getLabels()) {
			$grounding->setGrounds($label);
		}
	}
}

########## general object stuff ##########

use Storable qw/dclone/; # deep copy an object

sub clone {
	my $self = shift;
	return dclone($self);
}

# two alignments are equals iff the labels of both alignments are equal
# and their xmax, xmin and time fields are equal
# NOTE: the alignment time or name does not matter for equality
# $mode allows to relax the behaviour:
# - 'lax': do not check xmax, xmin and time
# - 'prefix': only check whether $self is a prefix of $other
# - 'laxprefix': prefix check only the label text
sub equals {
	my ($self, $other, $mode) = @_;
	$mode = 'strict' unless (defined $mode);
	my $lax = ($mode =~ m/^lax/) ? 'lax' : '';
	$lax .= 'NOCASE' if ($mode =~ m/nocase/i);
	my $prefix = ($mode =~ m/prefix/) ? 'prefix' : '';
	my $selfLabels = $self->{labels};
	my $otherLabels = $other->{labels};
	my $same = $prefix ? ($#{$selfLabels} <= $#{$otherLabels}) : ($#{$selfLabels} == $#{$otherLabels});
	if ($same) {
		for my $i (0..$#{$selfLabels}) {
			unless ($selfLabels->[$i]->equals($otherLabels->[$i], $lax)) {
				$same = 0;
				last;
			}
		}
	}
	return $same;
}

########## TextGrid IO ##########

# creates a new Alignment object from given text data (syntactically forming TextGrid data)
sub newAlignmentFromTextGridLines { 
	my @lines = @_;
	my $line;
	my $type = Util::parseLine(shift @lines, 'class = "(Interval|Text)Tier"');
	my $name = Util::parseLine(shift @lines, 'name = "(.*)"');
	my $xmin = Util::parseLine(shift @lines, 'xmin = (\d*(\.\d+)?)');
	my $xmax = Util::parseLine(shift @lines, 'xmax = (\d*(\.\d+)?)');
	my $typename = ($type eq 'Interval') ? 'intervals' : 'points';
	my $size = Util::parseLine(shift @lines, "$typename: size = (\\d+)");
	my @labels;
	print STDERR "parsing Tier $name from $xmin to $xmax with $size intervals.\n" if (Util->DEBUG > 0);
	my $labelStart = "0.0";
	for my $i (1..$size) {
		my @labelLines;
		confess "there is too little data in alignment $name. expected $size intervals, but dying after $i; input was:\n" . join("\n", @_) if ($#lines < 0);
		Util::parseLine(shift @lines, "$typename\\s*\\[\\d+\\]:");
		my $nextI = $i + 1;
		while (($#lines > -1) && ($lines[0] !~ m/^\s*$typename\s*\[\d+\]:\s*$/)) {
			push @labelLines, shift @lines;
		}
		my $label = Label::newLabelFromTextGridLines($typename, @labelLines);
		if ($typename eq 'points') {
			$label->{xmin} = $labelStart;
			$labelStart = $label->{xmax};
		}
		push @labels, $label;
	}
	confess("newAlignmentFromTextGridLines: there is still data to be processed, but I don't know how to process it: " . join "", @lines) if ($#lines != -1);
	# remove empty labels (they're useless)
	@labels = grep { !($_->isEmpty()) } @labels;
	return new($name, $xmin, $xmax, \@labels);
}

# create written TextGrid data from an Alignment object
sub toTextGridLines {
	my $self = shift;
	# insert empty labels where necessary (otherwise, the TextGrid will not be well-formed)
	$self->makeContinuous();
	my @lines;
	push @lines, "class = \"IntervalTier\" \n";
	push @lines, "name = \"$self->{name}\" \n";
	push @lines, "xmin = $self->{xmin} \n";
	push @lines, "xmax = $self->{xmax} \n";
	my $size = $#{$self->{labels}} + 1;
	push @lines, "intervals: size = $size \n";
	my $i = 1;
	foreach my $label (@{$self->{labels}}) {
		push @lines, "intervals [$i]:\n";
		push @lines, map { "    " . $_ } $label->toTextGridLines();
		$i++;
	}
	return @lines;
}

########## Wavesurfer IO ##########

# create a new Alignment object from text data (syntactically forming a Waversurfer file)
sub newAlignmentFromWavesurferLines {
	my @lines = grep { $_ !~ m/^$/ } @_; # skip empty lines
	my @labels = map { Label::newLabelFromWavesurferLine($_) } @lines;
	return new("wavesurfer-data", 0, 0, \@labels, "lax");
}

# create a new Alignment object from a given file (data must syntactically form a Wavesurfer file)
sub newAlignmentFromWavesurferFile {
	my $filename = shift;
	open inFile, '<', $filename or confess "Could not open $filename \n";;
	my @lines = <inFile>;
	close inFile;
	my $newAlignment = newAlignmentFromWavesurferLines(@lines);
	$newAlignment->{name} .= " from file $filename";
	return $newAlignment;
}

# create written Wavesurfer data from a Alignment object
sub toWavesurferLines {
	my $self = shift;
	my @lines;
	push @lines, map { $_->toWavesurferLine() } @{$self->{labels}};
	return @lines;
}

# save an Alignment object to a Wavesurfer file
sub saveToWavesurferFile {
	my $self = shift;
	my $filename = shift;
	open outFile, '>', $filename or confess "Could not write to file $filename\n";
	print outFile join "", $self->toWavesurferLines();
	close outFile;
}

########## Sphinx formatted Input ##########

# create a new Alignment object from text data (syntactically forming a Sphinx file)
sub newAlignmentFromSphinxLines {
	my ($timeLine, @labelLines) = @_;
	chomp $timeLine; chomp $timeLine;
	$timeLine =~ m/^Time: ((?:\d*(?:\.\d*)?)|gold)(?:\t(.*))?$/ or confess "AlignmentFromSphinxLines: Cannot parse line $timeLine\n";
	my $time = $1;
	my %additionalInfo;
	if (defined $2) {
		my $additionalInfo = $2;
		%additionalInfo = (split /=|, /, $additionalInfo);
	}
	my @labels = map { Label::newLabelFromWavesurferLine($_) } @labelLines;
	my @printLabels; # these are silence labels that are removed from the end of the alignment, 
			 # we still need them for perfect toString() output
	# remove trailing silent labels (but not the first label!)
	while (($#labels >= 1) && ($labels[-1]->isSilent())) {
		unshift @printLabels, pop @labels;
	}
	my $alignment = new("", 0, 0, \@labels, 'lax');
	if ($time eq 'gold') { 
		$alignment->{time} = undef;
		$alignment->{gold} = (1 == 1); # true;
	} else {
		$alignment->{time} = $time;
		$alignment->{gold} = (1 == 0); # false;
	}
	$alignment->{additionalInfo} = \%additionalInfo;
	$alignment->{trailingPrintLabels} = \@printLabels; # needed for perfect toString()
	return $alignment;
}

# create written Sphinx data from a Alignment object
sub toSphinxLines {
	my $self = shift;
	my $time = $self->isGold() ? "gold" : $self->{time};
	my @lines = ("Time: $time\n");
	push @lines, map { $_->toWavesurferLine() } (@{$self->{labels}}, @{$self->{trailingPrintLabels}});
	return @lines;
}

# create written XML data for TEDview from an Alignment object
sub toTEDXMLLines {
	my ($self, $orig, $diamond) = @_;
	$orig = 'INTELIDAasr' unless ($orig);
	$diamond = 'wrap' unless (defined($diamond));
	my $time = int($self->{time} * 1000);
	# add content
	my @lines = map { $_->toTEDXMLLine($orig) } (@{$self->{labels}}, @{$self->{trailingPrintLabels}});
	# wrap in diamond event if applicable
	if($diamond eq 'wrap'){
		my $colSpec = '';
		if (exists $self->{color}) {
			$colSpec .= "color='$self->{color}' ";
		}
		if (exists $self->{outlineColor}) {
			$colSpec .= "outlinecolor='$self->{outlineColor}' ";
		}
		unshift @lines, "<event time='$time' originator='$orig' $colSpec>";
		push @lines, "</event>";
	}
	return @lines;
}

# create an SVG subtree (represented as objects from the SVG package) for display
use SVG;
sub toSVG {
	my ($self, $svg, $transformSpec) = @_;
	$svg = new SVG(
		"style" => "stroke: black; stroke-width: 0.01; text-anchor: middle; font-size: 0.1;",
	) unless (defined $svg);
	$transformSpec = "" unless (defined $transformSpec);
	my $group = $svg->group(transform => $transformSpec);
	foreach my $label ($self->getLabels()) {
		$label->toSVG($group);
	}
	return $svg;
}

########## getters/setters ##########

# get the name property of the Alignment
sub getName {
	my $self = shift;
	return $self->{name};
}

# set the name property of the Alignment
sub setName {
	my ($self, $name) = @_;
	$self->{name} = $name;
}

# get all labels in the Alignment
sub getLabels {
	my $self = shift;
	return @{$self->{labels}};
}

# set list of labels in the Alignment
sub setLabels {
	my ($self, @labels) = @_;
	$self->{labels} = \@labels;
}

# get the time of the Alignment
sub getTime {
	my $self = shift;
	return $self->{time};
}

# whether this is a gold-standard transcription instead of a timed alignment
sub isGold {
	my $self = shift;
	return $self->{gold};
}

########## fancier adders/getters ##########

# get the end of the last label
sub getEndOfLastLabel {
	my $self = shift;
	return $self->{labels}->[-1]->{xmax};
}

# return a label that spans (that is, starts on or before and ends on or after) the given point in time
# returns undef if no such label exists
sub getLabelAt {
	my ($self, $time) = @_;
	my @labels = @{$self->{labels}};
	return undef if ($labels[0]->{xmin} > $time);
	return undef if ($labels[-1]->{xmax} < $time);
	# use binary search which *really* helps performance
	my $minpos = 0;
	my $maxpos = $#labels + 1;
	my $lastpos = int(($minpos + $maxpos) / 2) - 1;
	my $pos;
	my $found = (0 == 1); # false
	while ($maxpos - $minpos > 0) {
		$pos = int(($minpos + $maxpos) / 2);
		my $label = $labels[$pos];
		# see if we've found the label
		if (($label->{xmin} <= $time) && ($label->{xmax} >= $time)) {
			return $label;
		}
		# if we have found a label, return it. otherwise return undef
		return undef if ($lastpos == $pos); # just to be sure that the algorithm always terminates
		my $cmp = $time - $labels[$pos]->{xmin};
		if ($cmp > 0) {
			$minpos = $pos;
		} else {
			$maxpos = $pos;
		}
		$lastpos = $pos;
	}
	return undef;
}

# get all words inside the Alignments' labels
# parameter: 	'remove': remove silence marks (this is the default),
# 		'keep': keep silence, 
#		'dotted': add dots for silences, number of dots indicates silence durations (one dot per 1/3 of a second)
#		'dottedlog': add dots for silences, number of dots indicates silence durations (one dot per 1/3 of a second)
sub getWords {
	my ($self, $style) = @_;
	$style = '' unless (defined $style);
	if ($style =~ m/^keep/) {
		return map { $_->{text} } @{$self->{labels}};
	} elsif ($style eq 'dotted') {
		return map { $_->isSilent() ? $_->durationInDots(1/3) : $_->{text} } @{$self->{labels}};
	} elsif ($style eq 'dottedlog') {
		return map { $_->isSilent() ? $_->durationInDots(1/4, 'log') : $_->{text} } @{$self->{labels}};
	} else {
		return map { $_->isSilent() ? () : $_->{text} } @{$self->{labels}};
	}
}

# get all words in the Alignment's labels up to a given time
sub getWordsUpTo {
	my ($self, $time, $style) = @_;
	my $span = $self->getSpan(0, $time, 'overlap');
	return $span->getWords($style);
}

# get a sub-alignment from one continuous span starting at $spanStart upto $spanEnd
# as an additional feature, giving one label as parameter will extract spanStart and end from that label
# $mode determines behaviour:
# 'strict': only labels completely within $spanStart and $spanEnd are included
# 'overlap': all labels (partially) within $spanStart and $spanEnd are included
# 'crop': include overlapping labels but crop them to $spanStart and $spanEnd
sub getSpan {
	my ($self, $spanStart, $spanEnd, $mode) = @_;
	if (blessed($spanStart) && blessed($spanStart) eq "Label") {
		my $label = $spanStart;
		$mode = $spanEnd; # shift the mode parameter to the correct variable
		$spanStart = $label->{xmin};
		$spanEnd = $label->{xmax};
	}
	$spanStart = $self->{xmin} unless (defined $spanStart);
	$spanEnd = $self->{xmax} unless (defined $spanEnd);
	$mode = 'strict' unless (defined $mode);
	my @labels;
	@labels = ($mode eq 'strict') ? (grep {
		(($_->{xmin} >= $spanStart) && ($_->{xmax} <= $spanEnd)) } @{$self->{labels}})
				      : (grep {
		((($_->{xmin} >= $spanStart) && ($_->{xmin} <= $spanEnd)) || (($_->{xmax} <= $spanEnd) && ($_->{xmax} >= $spanStart))) } @{$self->{labels}});
	if (($mode eq 'crop') && $#labels >= 0) {
		$labels[0]->{xmin} = $spanStart if ($labels[0]->{xmin} < $spanStart);
		$labels[-1]->{xmax} = $spanEnd if ($labels[0]->{xmax} > $spanEnd);
	}
	bless { xmin => $spanStart, xmax => $spanEnd, labels => \@labels, 'time' => $self->getTime() };
}

# add the specified label to an Alignment object
sub addLabel {
	my ($self, $label) = @_;
	confess "labels must be of Type Label: $label!" unless (ref($label) eq 'Label');
	confess "labels must not overlap!" if ((defined $self->{labels}->[-1]) && ($self->{labels}->[-1]->{xmax} > $label->{xmin}));
	push @{$self->{labels}}, $label;
	$self->{xmax} = $label->{xmax};
}

# integrate the labels from another alignment into this alignment
# labels in an alignment may not overlap. 
# to ensure this, an alignment can only be integrated if its labels are all *after* the labels in the current alignment
sub integrateLabelsFromAlignment {
	my ($self, $other, $lax) = @_;
	my @labels = @{$self->{labels}};
	my ($xmin, $xmax) = checkLabels(\@labels);
	$self->{xmax} = $xmax;
	my @newLabels = @{$other->{labels}};
	# if there are no labels to add, then don't do anything.
	return if ($#newLabels == -1); 
	# otherwise integrate them if the new alignment doesn't overlap the current alignment
	if ($self->{xmax} <= $newLabels[0]->{xmin}) {
		push @labels, @newLabels;
		$self->{xmax} = $other->{xmax};
	} elsif ($lax) { # if there is an overlap, but we are being lax about it, try to shorten the labels to the left and right
		warn "Warning: Problem when integrating Labels from " . $other->{name} . " containing:\n";
		warn $labels[$#labels]->toWavesurferLine();
		warn join "", map { $_->toWavesurferLine() } @newLabels;
		my $overlap = $self->{xmax} - $newLabels[0]->{xmin};
		warn "Labels overlap by $overlap; trying to shorten labels to the left and right...\n";
		$labels[$#labels]->{xmax} -= $overlap / 2;
		confess "Error: lastLabel duration becomes negative.\n" if (($labels[$#labels]->{xmax} - $labels[$#labels]->{xmin}) < 0);
		$newLabels[0]->{xmin} += $overlap / 2;
		confess "Error: newLabel duration becomes negative.\n" if (($newLabels[0]->{xmax} - $newLabels[0]->{xmin}) < 0);
		push @labels, @newLabels;
		$self->{xmax} = $labels[$#labels]->{xmax};
	} else {
		confess "Error: Cannot integrate alignment when contained labels overlap.\n" 
		  . "self:\n" . $self->{name} . "\n" . (join "", $self->toWavesurferLines())
		  . "other:\n" . $other->{name} . "\n" . join "", $other->toWavesurferLines();
		# diese Bedingung muss vielleicht etwas aufgeweicht werden,
		# es reicht ja, dass die labels nicht überlappen.
	}
	$self->{labels} = \@labels;
}

########## silence handling ##########

# checks whether the alignment contains anything but silent labels
sub isSilent {
	my $self = shift;
	return ! scalar grep { !$_->isSilent() } @{$self->{labels}};
}

# remove all silent labels from the Alignment
sub removeSilentLabels {
	my $self = shift;
	@{$self->{labels}} = grep { !($_->isSilent()) } @{$self->{labels}};
}


# remove all empty labels from the Alignment
# (which is the opposite of makeContinuous) 
sub removeEmptyLabels {
	my $self = shift;
	my @labels = @{$self->{labels}};
	@{$self->{labels}} = grep { !($_->isEmpty()) } @labels;
}

# remove leading and trailing silent labels and adjust start- and end-time accordingly
sub crop {
	my $self = shift;
	my @labels = $self->getLabels();
	shift @labels while (($#labels >= 0) && ($labels[0]->isSilent()));
	pop @labels while (($#labels >= 0) && ($labels[-1]->isSilent()));
	$self->setLabels(@labels);
}

# shift the overall times of the Alignment by a given value
sub timeShift {
	my ($self, $time) = @_;
	$self->{xmin} += $time;
	$self->{xmax} += $time;
	map { $_->timeShift($time) } @{$self->{labels}};
}

########## filtering, continuity ##########

# make the labels in the alignment continuous (max_n == min_{n+1})
# by inserting empty labels between non-continuous labels (where max_n < min_{n+1})
# and also insert a label from alignment->xmin to min_1 and from max_N to alignment->xmax
sub makeContinuous {
	my $self = shift;
	my @labels = @{$self->{labels}};
	my @newLabels;
	my $lastMax = $self->{xmin}; # set to min of alignment, thus a leading label will be inserted if necessary
	foreach my $label (@labels) {
		if ($lastMax < $label->{xmin}) {
			push @newLabels, Label::new($lastMax, $label->{xmin}, '');
		}
		$lastMax = $label->{xmax};
		push @newLabels, $label;
	}
	# add a last label if necessary
	if ($lastMax < $self->{xmax}) {
		push @newLabels, Label::new($lastMax, $self->{xmax}, '');
	}
	$self->{labels} = \@newLabels;
}

# whenever multiple identical silence tags follow each other, they are 
# collapsed into one 
sub collapseMultipleSils {
	my ($self) = @_;
	my @labels = @{$self->{labels}};
	my $i = 1;
	my $prevIsSilent = $labels[0]->isSilent();
	while ($i <= $#labels) {
		my $thisIsSilent = $labels[$i]->isSilent();
		if ($prevIsSilent && $thisIsSilent && 
		    ($labels[$i - 1]->{text} eq $labels[$i]->{text})) {
			my $newLabel = Label::new($labels[$i - 1]->{xmin}, 
						  $labels[$i]->{xmax},
						  $labels[$i]->{text});
			@labels = (@labels[0..$i - 2], $newLabel, @labels[$i + 1..$#labels]);
			$i--;
		}
		my $prevIsSilent = $thisIsSilent;
		$i++;
	}
	$self->{labels} = \@labels;
}

########## differencing ############

# return a list of IUEdits that, when applied to $other makes $other.equals($self, 'lax')
# DANGER: this is older code than diffInIUEdits!! make sure to re-validate it before use
#sub diffInIUEditsUpTo {
#	my ($self, $other, $time, $nofiller, $subst) = @_;
#	my @selfWords = $self->getWordsUpTo($time, $nofiller);
#	my @otherWords = $other->getWordsUpTo($time, $nofiller);
#	return IUEdit::makeIUEditList(\@selfWords, \@otherWords, $subst);
#}

# TODO: shortcut getSpan() und use getWords() directly instead (and refactor both this and diffInIUEditsUpTo and this for common code)
sub diffInIUEdits {
	my ($self, $other, $nofiller, $subst) = @_;
	my @selfWords = $self->getWords('keepsilence');
	my @otherWords = $other->getWords('keepsilence');
	my @edits = IUEdit::makeIUEditList(\@selfWords, \@otherWords, $subst);
	unless (defined $nofiller && $nofiller =~ m/^keep/) {
		@edits = grep { !$_->isSilenceEdit() } @edits;
	}
	return @edits;
}

# create an edit list of Levenshtein operations between this and another alignment
sub labelDiffToOtherAlignment {
	my ($self, $other) = @_;
	my @selfWords = $self->getWords();
	my @otherWords = $other->getWords();
	return MyBrew::distance(\@selfWords, \@otherWords, 
# the 3 prefers add/remove-pairs over substitutions
				{-output => 'edits', -cost => [0, 1, 1, 3]});
# 'flexible prefers substitutions, in particular for almost-matching pairs
#				{-output => 'edits', -cost => [0, 1, 1, 'flexible']});
}

########## merging edits ###########

sub applyIUEdits {
	#TODO
}

########## (partial) copying ############

# copy the content of the Alignment up to a given time
sub copyUpTo {
	my ($self, $time) = @_;
	my @labels = grep { $_->{xmin} <= $time } @{$self->{labels}};
	my $new = new('', 0, $time, \@labels, 'lax');
	$new->{time} = $self->{time};
	return $new;
}

# checks whether two Alignments are equal up to a given time
# true iff $self and $other are equal (see above, especially concerning $mode) up to time $time
sub equalsUpTo {
	my ($self, $other, $time, $mode) = @_;
	$self->getSpan(0, $time, 'crop')->equals($other->getSpan(0, $time, 'crop'), $mode);
}

# checks whether an Alignment is a prefix of another Alignment up to a given time
# true iff $self is a prefix of $other up to time $time
# $mode relaxes the behaviour:
# 'lax': ignore label times
sub prefixUpTo {
	my ($self, $other, $time, $mode) = @_;
	$self->getSpan(0, $time, 'crop')->equals($other, $mode . 'prefix');
}

########## collapse sequences of silences and non-silences ############

sub collapse {
	my $self = shift;
	$self->makeContinuous();
	my @oldLabels = $self->getLabels();
	my $inSilence = Util->TRUE;
	my $startTime = 0;
	my @newLabels;
	@newLabels = map { 
		if ($inSilence != $_->isSilent()) {
			# a state change
			my $lab = Label::new($startTime, $_->{xmin}, $inSilence ? "SIL" : "noSIL");
			$startTime = $_->{xmin};
			$inSilence = !$inSilence;
			$lab;
		} else {
			# state doesn't change, remove this label
			();
		}
	} @oldLabels;
	$self->setLabels(@newLabels);
}

# get talk spurts in the Alignment
sub getTalkSpurts {
	my ($self, $other, $allowedSilenceDuration) = @_;
	# silences shorter than 180 ms are ignored, as they are not
	# generally perceived as real pauses, but only as short breaks
	$allowedSilenceDuration = 0.180 unless ($allowedSilenceDuration);
	# we must clone ourselves, because we don't want side-effects from collapsing
	$self = $self->clone();
	$other = $other->clone();
	$self->collapse();
	$other->collapse();
	# now we have continuous sequences of SIL and noSIL tags for self and other
	#
	# find talk spurts and look at their beginnings
	#
	# Norwine & Murphy (1938) (cited after Edlund et al., 2008): 
	# "A _talkspurt_ is speech by one party, including her pauses, 
	# which is preceded and followed, with or without intervening
	# pauses, by speech of the other party perceptible to the one 
	# producing the talkspurt."
	# 
	# * a talkspurt contains all silences during which the other does not talk
	# * all other silences delimit talkspurts
	my @selfSpurts;	
	my $startTime = -1;
	my $endTime = -1;
	foreach my $label ($self->getLabels()) {
		if ($label->isSilent() && $label->duration() > $allowedSilenceDuration) {
			if (!($other->getSpan($label->{xmin}, $label->{xmax}, 'overlap')->isSilent())) {
				# new spurt starts, store old spurt
				push @selfSpurts, Label::new($startTime, $endTime, 'spurt') if ($endTime > 0);
				$startTime = -1;
			}
		} else {
			$startTime = $label->{xmin} if ($startTime < 0);
		}
		$endTime = $label->{xmax};
	}
	return new($self->{name}, $self->{xmin}, $self->{xmax}, \@selfSpurts);
}

# compute the timing differences between this and a given Alignment, 
# uses edit distance and allows for "match" and "matchsubst" timing comparison
# return is either lists of "raw" start/end times and mean/stddev in a hash, or just RMSE of start times
# !! beware, after using this operations, silences will be removed from both alignments
# returns ... 
sub computeTimingErrors {
	my ($self, $other, $matchsubst, $output) = @_;
	$self->removeSilentLabels();
	$other->removeSilentLabels();
	$matchsubst = 'match' unless (defined $matchsubst);
	print "$matchsubst\n";
	$output = '' unless (defined $output);
	my @selfWords = $self->getWords();
	my @otherWords = $other->getWords();
	my $edits = MyBrew::distance(\@selfWords, \@otherWords, 
				{-output => 'edits', -cost => [0, 1, 1, 'flexible']});
	my $selfCounter = 0;
	my $otherCounter = 0;
	my @startErrors;
	my @endErrors;	
	foreach my $edit (@{$edits}) {
#print "$edit\n";
		switch ($edit) {
			case 'INITIAL' { } # ignore initial edit
			case 'INS' { # only advance selfCounter for insertions
				$otherCounter++; }
			case 'DEL' { # only advance otherCounter for deletions
				$selfCounter++; }
			case ['MATCH', 'SUBST'] { 
				next if ($matchsubst ne 'matchsubst' && $edit eq 'SUBST');
				my $selfLabel = ($self->getLabels())[$selfCounter];
				my $otherLabel = ($other->getLabels())[$otherCounter];
				push @startErrors, $otherLabel->{xmin} - $selfLabel->{xmin};
				push @endErrors, $otherLabel->{xmax} - $selfLabel->{xmax};
				$selfCounter++; 
				$otherCounter++;
			}
		}
	}
#print join ", ", @startErrors;
	my $startMean = mean(@startErrors);
	my $startStddev = stddev(@startErrors);
	my $rmse = sqrt($startMean**2 + $startStddev**2);
	if ($output eq '' || $output eq 'RMSE') {
		return $rmse;
	} else {	
		return { start => \@startErrors, end => \@endErrors };
	}
}


# help perl's garbage collection
sub DESTROY {
	my $self = shift;
	$self->{labels} = undef;
}

return 1;

