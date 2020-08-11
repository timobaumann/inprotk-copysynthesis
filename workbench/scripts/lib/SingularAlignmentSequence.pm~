#!/usr/bin/perl

# perl module that defines a sequence of alignments and the corresponding gold alignment
package SingularAlignmentSequence;

use strict;
use warnings;
use Carp;
use IO::Socket; # to output to TED
use Carp;
require "Util.pm";
require "Alignment.pm";
require "Label.pm";
require "MyBrew.pm";

#create a new AlignmentSequence
sub new {
	# $gold: gold standard alignment associated with this alignment sequence
	# @alignments: alignments contained in this sequence
	my ($gold, $alignments) = @_;
	checkAlignments($alignments);
	return bless { gold => $gold, alignments => $alignments };
}

sub checkAlignments {
	my @alignments = @{$_[0]};
	# there must at least be 2 entries in @alignments!
#	confess "need at least 2 entries in \@alignments: $#alignments!\n" if ($#alignments < 2);
	my $prevTime = -99999;
	use sort 'stable';
	my @sortedAlignments = sort { $a->{time} <=> $b->{time} } @alignments;
	if (!Util::listEqual(\@sortedAlignments, \@alignments)) {
		warn "something is wrong with the ordering of alignments, fixing silently.\n";
		@alignments = @sortedAlignments;
	}
	foreach my $alignment (@alignments) {
		confess "alignments must be of Type Alignment: $alignment!" unless (ref($alignment) eq 'Alignment');
		confess "alignments are not ordered strictly sequentially: $alignment->{time}" unless ($alignment->{time} >= $prevTime);
		Alignment::checkLabels(\@{$alignment->{labels}});
		#$alignment->collapseMultipleSils();
		$prevTime = $alignment->{time};
	}
}

######## INPUT Functions #########

sub newSeqFromFile {
	my $filename = shift;
	open inFile, '<:crlf', $filename;
	my @lines = <inFile>;
	close inFile;
	my $seq = newSeqFromLines(@lines);
	$seq->{filename} = $filename;
	return $seq;
}

sub newSeqFromLines {
	my @lines = @_;
	my @alLines = ();
	my @alignments = ();
	foreach my $line (@lines) {
		if ($line =~ m/^$/) {
			next unless (@alLines); # be robust to multiple blank lines
			my $alignment = Alignment::newAlignmentFromSphinxLines(@alLines);
			push @alignments, $alignment;
			@alLines = ();
		} else {
			push @alLines, $line;
		}
	}
	confess "error creating alignment sequence: sequences must contain at least two alignments (instead of just $#alignments)!" if ($#alignments < 1);
	my $gold = $alignments[-1];
	if ($gold->isGold()) {
		pop @alignments; # get rid of the gold-alignment if it is marked as such
	}
	return new($gold, \@alignments);
}

######## OUTPUT Functions #########

sub saveToSphinxFile {
	my $self = shift;
	my $filename = shift;
	open outFile, '>', $filename or confess "Could not write to file $filename\n";
	print outFile join "", $self->toSphinxLines();
	close outFile;
}

sub toSphinxLines {
	my $self = shift;
#	my @lines = ();
#	foreach my $alignment (@{$self->{alignments}}) {
#		push @lines, $alignment->toSphinxLines();
#		push @lines, "\n";
#	}
	my @lines = map { ($_->toSphinxLines(), "\n") } @{$self->{alignments}};
	if ($self->getLastAlignment() != $self->getGold()) {
		push @lines, $self->getGold()->toSphinxLines();
		push @lines, "\n";
	}
	return @lines;
}

# turn this SingularAlignmentSequence into TEDviewXML
sub toTEDXMLLines {
	my ($self, $orig, $nowrap) = @_;
	$orig = 'INTELIDAasr' unless ($orig);
	$nowrap = (1 == 0) unless ($nowrap); # default to false
	# get content
#	my @lines = map { $_->toTEDXMLLines() } @{$self->{alignments}};
	my @lines;
	foreach my $alignment (@{$self->{alignments}}) {
		push @lines, $alignment->toTEDXMLLines($orig);
	}
	# if nowrap only return content, otherwise wrap as dialogue-XML
	return ($nowrap eq 'nowrap') ? 
			@lines : 
			("<dialogue id=''>", 
			"<control originator='$orig' action='clear' />",
				 @lines, 
			"</dialogue>");
}

sub toTED {
	my ($self, $orig, $IP, $port) = @_;
	$orig = 'INTELIDAasr' unless ($orig);
	$IP = '127.0.0.1' unless ($IP);
	$port = 2000 unless ($port);
	my $sock = new IO::Socket::INET(PeerAddr => $IP, PeerPort => $port, Proto => 'tcp');
	print $sock join "\n", $self->toTEDXMLLines($orig);
	close $sock;
}

sub toSVG {
	my ($self, $svg) = @_;
	$svg = new SVG(width => "1000px", height => "1000px",
		style => "stroke: black; stroke-width: 0.01; text-anchor: middle; font-size: 0.1;",
	) unless (defined $svg);
	my $xscaling = 1000 / $self->getDuration();
	my $yscaling = 1000 / scalar $self->getAlignments();
	my $group = $svg->group(transform => "translate(-1,-1) scale($xscaling, $yscaling)")->group();
	my $lineheight = 1.2;
	my $line = 0;
	foreach my $alignment ($self->getAlignments()) {
		$alignment->toSVG($group, "translate(0, ${line})");
		$line+=$lineheight;
	}
	return $svg;
}

######## simple getters/setters ##########

sub getGold {
	my $self = shift;
	return $self->{gold};
}

sub getAlignments {
	my $self = shift;
	return @{$self->{alignments}};
}

sub getFirstAlignment {
	my $self = shift;
	return $self->{alignments}[0];
}

sub getLastAlignment {
	my $self = shift;
	my @alignments = @{$self->{alignments}};
	return $alignments[$#alignments];
}

sub getDuration { # return time of last alignment in @alignments (this may be different than gold, e.g. when crop has been called)
	my $self = shift;
	return $self->getLastAlignment()->getTime();
}

######## somewhat advanced getters #########

# get the alignment with the highest getTime() which still has getTime() <= $time
sub getAlignmentAt {
	my ($self, $time) = @_;
	my @alignments = @{$self->{alignments}};
	return Alignment::newEmptyAlignment() if ($alignments[0]->{time} > $time);
	# use binary search which *really* helps performance
	my $minpos = 0;
	my $maxpos = scalar @alignments;
	my $lastpos = int(($minpos + $maxpos) / 2) - 1;
	my $pos;
	while ($maxpos - $minpos > 0) {
		$pos = int(($minpos + $maxpos) / 2);
		last if ($lastpos == $pos); # just to be sure that the algorithm always terminates
		my $cmp = $time - $alignments[$pos]->{time};
		last if (abs($cmp) < 0.00001); # avoid floating point annoyances
		if ($cmp > 0) {
			$minpos = $pos;
		} else {
			$maxpos = $pos;
		}
		$lastpos = $pos;
	}
	return $alignments[$pos];
}

######## sequence manipulation ##########

# if the sequence of alignments is not continuous (i.e. if there is not an alignment every 0.01 seconds)
# insert alignments for these slots containing info from the previous "real" alignment and a current timestamp
sub makeContinuous {
	my $self = shift;
	my @alignments = @{$self->{alignments}};
	my @newAlignments;

	my $prevAlignment = shift @alignments;
	my $prevTime = $prevAlignment->{time};
	push @newAlignments, $prevAlignment;
	foreach my $alignment (@alignments) {
		$prevTime += 0.01;
		while ($prevTime < $alignment->{time}) {
			my $insertedAlignment = $prevAlignment->clone();
			$insertedAlignment->{time} = $prevTime;
			push @newAlignments, $insertedAlignment;
			$prevTime += 0.01;
		}
		push @newAlignments, $alignment;
		$prevAlignment = $alignment;
	}
	$self->{alignments} = \@newAlignments;
}

# remove all alignments in the sequence where the contained wordSequence
# equals the previous alignment's wordSequence; thus, only alignments remain
# that would also result in one (or more) EditMessage
sub makeSparse {
	my $self = shift;
	my @alignments = @{$self->{alignments}};
	my @newAlignments;
	my @prevWords = ();
	foreach my $alignment (@alignments) {
		my @words = $alignment->getWords('remove');
		push @newAlignments, $alignment unless (Util::listEqual(\@words, \@prevWords));
		@prevWords = @words;
	}
	push @newAlignments, $alignments[-1];
	$self->{alignments} = \@newAlignments;
}

# crop away all alignments that are outside of the "active" phase of the recognition
# the active phase consists of all alignments from the first contentful (that is non-empty, non-silent)
# alignment and upto the first alignment after which no changes in the sequence (apart from silence) follow
sub cropSequence {
	my $self = shift;
	my @alignments = @{$self->{alignments}};
	my $alignment = shift @alignments;
	# crop away leading empty alignments 
#	while (((scalar @{$alignment->{labels}}) == 1) && ($alignment->{labels}[0]->isSilent())) { 
	while ((@alignments) && ($alignment->isSilent())) {
		$alignment = shift @alignments;
	}
	unshift @alignments, $alignment;
	# crop trailing final alignments
	$alignment = pop @alignments;
	while (($#alignments >= 0) && ($alignment->equals($alignments[$#alignments]))) {
		$alignment = pop @alignments;
	}
	push @alignments, $alignment;
	$self->{alignments} = \@alignments;
}

# useful when outputting long alignment sequences to TEDview:
# remove all words from the alignments that are not within the 
# last X (default 1.0) seconds of the alignment
sub onlyRecent {
	my ($self, $lag) = @_;
	$lag = 1.0 unless (defined $lag);
	my @alignments = @{$self->{alignments}};
	my $labelCount = 0;
	map { $labelCount += scalar $_->getLabels() } @alignments;
	print STDERR "old label count: $labelCount\t";
	@alignments = map { $_->getSpan($_->getTime() - 1,$_->getTime(), 'overlap') } @alignments;
	$labelCount = 0;
	map { $labelCount += scalar $_->getLabels() } @alignments;
	print STDERR "new label count: $labelCount\n";
	$self->{alignments} = \@alignments;
}


# im NAACL paper unter 4.1 "right context" beschrieben:
# - shorten all hypotheses (except the golden last one) by lag t
#   in case t is negative, the last word in each alignment will be extended up to t
# - output is *NOT* identical to - what?
sub fixedLagSequence {
	#print STDERR "fixedLagSequence() has not yet been verified!\n";
	my ($self, $lag) = @_;
	return if ($lag == 0);
	my @alignments = @{$self->{alignments}};
	if ($lag > 0) {
		@alignments = map { my $new = $_->getSpan(0, $_->getTime() - $lag, 'crop'); $new->{time} = $_->{time}; $new } @alignments;
	} else { # $lag < 0, $lag == 0 is already handled above
		@alignments = map { $_->getLabels()->[-1]->{xmax} -= $lag; $_->{xmax} -= $lag; $_ } @alignments;
	}
	$self->{alignments} = \@alignments;
}

# im NAACL paper unter 4.2 "message smoothing" beschrieben:
# - edit messages werden erst dann durchgelassen, wenn sie N frames alt sind (das heißt,
# wenn sie sich aus allen letzten N inkrementellen alignments ergeben)
sub smoothSequence {
#	print STDERR "test smoothSequence() if you want to really use it!\n";
	my ($self, $smoothness) = @_;
	return $self->impureSmoothSequence($smoothness, 0);
}

# new idea: allow some impurity within the smoothing window, to account for 
# short intermediate wrong hypotheses, which increase timing for otherwise good
# hypotheses (i.e. with a smoothing factor of 5, the good hypothesis below
# is delayed until time 9, but it would be nice if it only were delayed until
# time 6.
# 1 good 
# 2 good 
# 3 good 
# 4 bad 
# 5 good 
# 6 good <-- smart smoothing with factor 5 and impurity 1
# 7 good 
# 8 good 
# 9 good <-- regular smoothing with factor 5
sub impureSmoothSequence {
	my ($self, $smoothness, $impurity) = @_;
	confess "smoothing needs a positive number >= 1 (I won't do anything for 1, but you can still call me, if you like), you gave me $smoothness" 
		unless (($smoothness =~ m/\d+/) && ($smoothness > 0));
	return if ($smoothness == 1);
	confess "impurity must not be negative, you gave me $impurity" 
		unless (($impurity =~ m/\d+/) && ($impurity >= 0));

	my @alignments = @{$self->{alignments}};
	# there must at least be $smoothness entries in @alignments!
	if ($#alignments <= $smoothness) {
		warn "can't smooth with less than $smoothness entries in \@alignments: $#alignments!\n";
		$smoothness = $#alignments - 1;
	}
	my @smoothedAlignments = (Alignment::newEmptyAlignment()); # what will eventually replace $self->{alignments}
	my $outputAlignment = Alignment::newEmptyAlignment(); # w_{curr}

	# @window contains pointers to IUEdit lists relative to the current $outputAlignment
	my @window = []; # start with an empty element and then the IUEdit-lists for the first alignments
	push @window, map { [$_->diffInIUEdits($outputAlignment, "keep", '')] } @alignments[0..$smoothness - 2]; 
	# main loop through all remaining alignments 
	# sometimes in the loop, an element will be added to smoothedAlignments
	# this element will take the place of $outputAlignment
	# invariant: $#window == $smoothness - 1
	foreach my $alignment (@alignments[$smoothness - 1..$#alignments]) {
		my @currentIUEdits = $alignment->diffInIUEdits($outputAlignment, "keep", '');
		shift @window; push @window, [@currentIUEdits];
		confess "assertion: $#window != $smoothness - 1\n" if ($#window != $smoothness - 1);
		my $keepGoing = (1 == 1); # true
		my @applicableIUEdits = (); 
		# check for all the edit lists in the windows
		while (($keepGoing) & ($#currentIUEdits >= 0)) { # if there aren't any differences to what we've output, we don't need to think any further
			# find out whether all first elements in $window are the same
			my $head = shift @currentIUEdits; 
			my $headCount = 0;
			foreach my $list (@window[0..$#window]) { 
				$headCount++ if ($head->equals(@{$list}[0])); 
			}
			if ($headCount >= $smoothness - $impurity) { # we will now have to smooth
				@window = map { [@{$_}[1..$#{$_}]] } @window; # we remove $head from all lists	
				# and put it in the list of IUEdits to commit at this step
				push @applicableIUEdits, $head;	
			} else {
				$keepGoing = (0 == 1); # false, break the while loop
			}
		}
		### apply the edits that are applicable to a new, smoothed output alignment
		if ($#applicableIUEdits >= 0) {
			my @currentLabels = $alignment->getLabels();
			my @outputLabels = $outputAlignment->getLabels();
			foreach my $IUEdit (@applicableIUEdits) {
				if ($IUEdit->isRevoke()) {
					my $label = pop @outputLabels;
					if ($label->{text} ne $IUEdit->{word}) {
						print STDERR join '', $alignment->toSphinxLines(), "\n";
						print STDERR $label->toWavesurferLine(), "\n";
						print STDERR $IUEdit->toString(), "\n";
						print STDERR $self->{filename}, "\n";
						confess "revoking something that wasn't there";
					}
				} elsif ($IUEdit->isAdd()) {
					my $labelsIntoOutput = $#outputLabels;
					for my $i (0..$labelsIntoOutput) {
						if ($currentLabels[$i]->{text} ne $outputLabels[$i]->{text}) {
							print STDERR "i: $i, labelsintooutput: $labelsIntoOutput\n";
							print STDERR $alignment->{time}, "\n";
							print STDERR join ":", map { $_->toWavesurferLine() } @currentLabels;
							print STDERR "\n";
							print STDERR join ":", map { $_->toWavesurferLine() } @outputLabels;
							print STDERR "\n";
							print STDERR $self->{filename}, "\n";
							confess "trying to add, but prefix is not identical!";
						}
						# update the timing of the output labels
						$outputLabels[$i]->{xmin} = $currentLabels[$i]->{xmin};
						$outputLabels[$i]->{xmax} = $currentLabels[$i]->{xmax};
					}
					$labelsIntoOutput++; # finally add a label, yeah.
					confess "trying to add something that isn't there in file " . $self->{filename} if ($currentLabels[$labelsIntoOutput]->{text} ne $IUEdit->{word});
					push @outputLabels, $currentLabels[$labelsIntoOutput];
				}
			}
			$outputAlignment->{labels} = \@outputLabels;
			# fix @outputLabels' timing: this may sometimes be off, we should probably best
			# shorten older labels, if there's an overlap with a following label
			for (my $i = 0; $i <= $#outputLabels; $i++) {
				confess unless ($outputLabels[$i]->{xmin} < $outputLabels[$i]->{xmax});
			}
			push @smoothedAlignments, Alignment::new($alignment->{name}, 
								$alignment->{xmin}, $alignment->{xmax}, 
								\@outputLabels, '', $alignment->{time});
		}
	}

	# - the last alignment in the sequence must remain as before
	if (($#smoothedAlignments < 0) || !($smoothedAlignments[$#smoothedAlignments]->equals($self->getLastAlignment()))) {
		push @smoothedAlignments, $self->getLastAlignment();
	}
	# - an alignment sequence must contain at least 2 alignments
	if ($#smoothedAlignments < 1) {
		unshift @smoothedAlignments, $self->getFirstAlignment();
	}

	$self->{alignments} = \@smoothedAlignments;
}

use Switch;

sub _constructTimeCorrectedReferenceAlignment {
	my ($self) = @_;
	my $refTimings = $self->getGold();
	my $refAlignment = $self->getLastAlignment()->clone();
	# construct a reference alignment that uses the words of lastAlignment and the times of goldAlignment
	#my $edits = $self->getWEList();
	# construct our own list of edits (which must include all labels along the way)
	my @goldwords = $refTimings->getWords('keep');
	my @words = $refAlignment->getWords('keep');
	my $edits = MyBrew::distance(\@goldwords, \@words, {-output => 'edits', -cost => [0, 1, 1, 'flexible']});
	my $wordIndex = 0;
	my $timeIndex = 0;
	foreach my $edit (@{$edits}) {
#print "$edit\n";
		switch ($edit) {
			case 'INITIAL' { } # ignore initial edit
			case 'INS' { 
				my $refLabel = ($refAlignment->getLabels())[$wordIndex];
				$refLabel->{xmin} = $wordIndex > 0 ? ($refAlignment->getLabels())[$wordIndex - 1]->{xmax} : 0;
				$refLabel->{xmax} = ($refTimings->getLabels())[$timeIndex]->{xmin};
				$wordIndex++; } # skip ahead on insertions
			case 'DEL' { # nothing to be done for deletions
				$timeIndex++ if ($timeIndex < scalar ($refTimings->getLabels()) - 1); } 
			case ['MATCH', 'SUBST'] { 
				my $refLabel = ($refAlignment->getLabels())[$wordIndex];
				my $timeLabel = ($refTimings->getLabels())[$timeIndex];
				$refLabel->{xmin} = $timeLabel->{xmin};
				$refLabel->{xmax} = $timeLabel->{xmax};
				$timeIndex++ if ($timeIndex < scalar ($refTimings->getLabels()) - 1);
				$wordIndex++;
			}
		}
#print join "", $refAlignment->toSphinxLines();
	}
	return $refAlignment;
}

# (see NAACL-paper section 2.3)
# returns references to three lists that describe the first-correct-delays for each word in the gold alignment
# from_start => [], to_end => [], word_rel => []
# the arrays have as many entries as there are non-silence words in the gold alignment
# from_start holds the time difference between when the word was first correct 
# and start-time of the label in the gold alignment in milliseconds
# to_end similarly holds the time difference between when the word was first correct and the label's end-time
# word_rel is normalized to the word duration (from_start = 0 -> word_rel = 0; to_end = 0 _> word_rel = 1)
sub getFODelays {
	my $self = shift;
	my $refAlignment;
	if ($self->getLastAlignment() != $self->getGold()) {
		$refAlignment = $self->_constructTimeCorrectedReferenceAlignment();
	} else {
		$refAlignment = $self->getLastAlignment();
	}
	# get all labels
	my @refLabels = $refAlignment->getLabels();
	# and the corresponding words
	my @refWords = map { $_->{text} } @refLabels;
	
	my $numWords = $#refWords;
	carp "there are no words in this file:" . $self->{filename}  . "\n"if ($numWords < 0);
	my $currentWord = 0;
	my %delay_FO = ( from_start => [], to_end => [], word_rel => [] );
	for my $alignment ($self->getAlignments()) {
		croak "assertion: trying beyond $numWords in file " . $self->{filename} . "\n" . $alignment->getTime() if (($currentWord > $numWords) && $numWords > -1);
		my @currWords = $alignment->getWords('keepsilences');
		while (($#currWords >= $currentWord) &&
# Frage: müsste man list_starts_with anstatt list_same nehmen?
# Antwort: nein, denn wir werten die Listen jeweils nur bis $currentWord aus. 
		    (Util::listEqual(\@{[@refWords[0..$currentWord]]}, \@{[@currWords[0..$currentWord]]}))) {
			# do not measure for silence words:
			if (!Label::isSilentText($currWords[$currentWord])) {
				my ($from_start, $to_end, $word_rel) = 
					$refLabels[$currentWord]->getTimings($alignment->getEndOfLastLabel());
				push @{$delay_FO{from_start}}, $from_start;
				push @{$delay_FO{to_end}}, $to_end;
				push @{$delay_FO{word_rel}}, $word_rel;
			}
			$currentWord++;
			# we're done, once all words are processed
			last if ($currentWord > $numWords);
		}
		last if ($currentWord > $numWords);
	}
	return %delay_FO;
}

sub getFDDelays {
	my $self = shift;
	my $refAlignment;
	if ($self->getLastAlignment() != $self->getGold()) {
		$refAlignment = $self->_constructTimeCorrectedReferenceAlignment();
	} else {
		$refAlignment = $self->getLastAlignment();
	}
	#$self->makeContinuous();
	# get all non-silent labels
	my @refLabels = grep { !$_->isSilent() } $refAlignment->getLabels();
	# and the corresponding words
	my @refWords = map { $_->{text} } @refLabels;
	my $currentWord = $#refWords;
	# calculation of delay_FD works in reverse; in order to keep the same words at the same 
	# positions in the arrays kept in %delay_FO and %delay_FD, %delay_FO has to be reversed
	# for each file; that's why we need the following variable and only push (reversed)
	# results to %delay_FO after processing of this file has ended
	my %delay_FD = ( from_start => [], to_end => [], word_rel => [], abs_from_start => [] );
	my $alCounter = scalar $self->getAlignments(); # count backwards
	# DONE: prefix gold before alignments in order to also generate results for words that only become final in the last alignment
	foreach my $alignment (($self->getLastAlignment(), reverse $self->getAlignments())) {
		my @currWords = $alignment->getWords();
		while (!(Util::listEqual(\@{[@refWords[0..$currentWord]]}, \@{[@currWords[0..$currentWord]]}))) {
			# in fact, we're not interested in LAST WRONG, but in FIRST FINAL. for that, we have to skip to the next frame
			my ($from_start, $to_end, $word_rel) = $refLabels[$currentWord]->getTimings($alignment->getTime() + 0.01);
	#print "$currWords[$currentWord]: $from_start\n";
			push @{$delay_FD{from_start}}, $from_start;
			push @{$delay_FD{to_end}}, $to_end;
			push @{$delay_FD{word_rel}}, $word_rel;
			push @{$delay_FD{abs_from_start}}, ($self->getAlignments())[$alCounter+1]->getTime();# . " $currentWord";
			$currentWord--;
		}
		## mark (in a certain color, say, green?) all final labels
		my @labels = $alignment->getLabels();
		for (my $i = 0; $i < $currentWord + 1; $i++) {
			$labels[$i]->setColor("lightgreen");
		}
#		map { $_->setColor("lightgreen"); } $alignment->getLabels();
		$alCounter--;
	}
	while ($currentWord >= 0) {
		my ($from_start, $to_end, $word_rel) = $refLabels[$currentWord]->getTimings(0 + 0.01);
		push @{$delay_FD{from_start}}, $from_start;
		push @{$delay_FD{to_end}}, $to_end;
		push @{$delay_FD{word_rel}}, $word_rel;
		push @{$delay_FD{abs_from_start}}, ($self->getAlignments())[0]->getTime();# . " $currentWord";
		$currentWord--;
	}
	# now add reverse timings 
	@{$delay_FD{from_start}} = reverse @{$delay_FD{from_start}};
	@{$delay_FD{to_end}} = reverse @{$delay_FD{to_end}};
	@{$delay_FD{word_rel}} = reverse @{$delay_FD{word_rel}};
	@{$delay_FD{abs_from_start}} = reverse @{$delay_FD{abs_from_start}};
	return %delay_FD;
}

# calculate FO only for words that match the given transcript (letter separated words)
# mode should be one of 'match', 'matchsubst' or 'all'; 
# in the match case, FO will only be returned for words matching in the transcript
# in the matchsubst case, SUBST edits are also considered
# in the all case, this is identical to getFODelays()
sub getFODelaysWER {
	my ($self, $mode, $transcript) = @_;
	$mode eq 'match' or $mode eq 'matchsubst' or $mode eq 'all' or confess "mode $mode is not supported.";
	my %delay_IN = $self->getFODelays();
	if ($mode ne 'all') {
		return $self->_grepFOFDWER(\%delay_IN, $mode, $transcript);
	}
	return %delay_IN;
}

sub getFDDelaysWER {
	my ($self, $mode, $transcript) = @_;
	$mode eq 'match' or $mode eq 'matchsubst' or $mode eq 'all' or confess "mode $mode is not supported.";
	my %delay_IN = $self->getFDDelays();
	if ($mode ne 'all') {
		return $self->_grepFOFDWER(\%delay_IN, $mode, $transcript);
	}
	return %delay_IN;
}

sub _grepFOFDWER {
	my ($self, $delay_IN, $mode, $transcript) = @_;
	$mode eq 'match' or $mode eq 'matchsubst' or confess "mode $mode is not supported.";
	my %delay_IN = %{$delay_IN};
	my $edits = $self->getWEList($transcript);
	my %delay_OUT = ( from_start => [], to_end => [], word_rel => [] );
	my $index = 0;
	foreach my $edit (@{$edits}) {
		switch ($edit) {
			case 'INITIAL' { } # ignore initial edit
			case 'INS' { $index++; } # skip ahead on insertions
			case 'DEL' {  } # nothing to be done for deletions
			case 'SUBST' { 
				if ($mode eq 'matchsubst') {
					foreach my $list ('from_start', 'to_end', 'word_rel') {
						push @{$delay_OUT{$list}}, $delay_IN{$list}[$index];
					}
				}
				$index++;
			}
			case 'MATCH' { 
				foreach my $list ('from_start', 'to_end', 'word_rel') {
					push @{$delay_OUT{$list}}, $delay_IN{$list}[$index];
				}
				$index++;
			}
		}
	}
	return %delay_OUT;
}

# return the list of edit operations (initial/ins/del/subst/match) of the final hypothesis
sub getWEList {
	my ($self, $transcript) = @_;
	my @words = $self->getLastAlignment()->getWords();
	my @goldwords;
	if (defined $transcript) {
		@goldwords = split " ", $transcript;
	} elsif ($self->getGold() != $self->getLastAlignment()) {
		@goldwords = $self->getGold()->getWords();
	} else {
		die "WER computation needs a transcript or an alignment sequence with gold alignment!";
	}
	@goldwords = map { uc } @goldwords;
	@words = map { uc } @words;
	return MyBrew::distance(\@goldwords, \@words, {-output => 'edits'});
}

# test that FD never happens before FO (which seems to be the case)
sub checkFOFD {
	my ($self) = @_;
	# it should not matter whether we choose from_start or to_end
	my %FO = $self->getFODelays();
	my %FD = $self->getFDDelays();
	my @FO_from_start = @{$FO{from_start}};
	my @FD_from_start = @{$FD{from_start}};
	($#FO_from_start == $#FD_from_start) 
		or confess "$#FO_from_start != $#FD_from_start";
	my @goldwords = $self->getGold()->getWords('nofiller');
	for my $i (0..$#FO_from_start) {
		#print "$i, $goldwords[$i]: $FO_from_start[$i] <= $FD_from_start[$i]\n";
		($FO_from_start[$i] <= $FD_from_start[$i] + 0.000001)
	  		or confess "$i: $FO_from_start[$i] > $FD_from_start[$i]";
	}
}

# returns (in a hash) the (old-style) edit overhead, 
# and the number of adds, revokes, substitutes, and total words
# (which together allow for any sort of overhead weighing)
# tested: identical results to singCorrectnessEval.pl 
# with and without smoothing; 
# but not if fixedLagging+discounting is applied, then results differ 
# by about 0.5%
sub getEditOverheadHash {
	my ($seq) = @_;
	# read reference alignment
	my $refAlignment = $seq->getLastAlignment();
	my $duration = $seq->getDuration();
	# initialize counters
	my $totalAlignments = 0;
	my $prevAlignment = $seq->getAlignmentAt(0);
	my $addIUs = $prevAlignment->getWords('remove'); # get the number of starting add()-IUs
	my $substIUs = 0;
	my $revokeIUs = 0;
	my $time = $seq->getFirstAlignment()->{time} - 0.01; # after cropping, this will start one alignment before the cropped time.
	while ($time <= $duration) {
		my $alignment = $seq->getAlignmentAt($time);
		# statistics for edit messages
		my @IUs = $alignment->diffInIUEdits($prevAlignment, 'remove', 'subst');
		$addIUs += scalar grep { $_->isAdd() } @IUs;
		$substIUs += scalar grep { $_->isSubst() } @IUs;
		$revokeIUs += scalar grep { $_->isRevoke() } @IUs;
		$prevAlignment = $alignment;		
		$time = sprintf("%.2f", $time + 0.01);
	}
	my $changes = $addIUs + 2 * $substIUs + $revokeIUs;
	my $words = scalar $refAlignment->getWords('remove');
	# avoid dividing by zero
	carp "there are no changes in this file: " . $seq->{filename} . "\n" unless ($changes != 0);
	return (words => $words,
		addIUs => $addIUs,
		substIUs => $substIUs,
		revokeIUs => $revokeIUs,
		changes => $changes, 
		EO => ($changes != 0) ? ($changes - $words) / $changes : 0
	);
}
# format: time, correctness, fair correctness, prefixcorrectness, old-style edit overhead, number of alignments evaluated, adds, subst, revokes, words
#0.00  0.349557522123894 0.349557522123894 0.588495575221239 0.857142857142857 226 6 10 2 4

# get correctness values; 
# add a "discount" for discounted correctness evaluation
# tested: identical results to singCorrectnessEval.pl if no smoothing/fixedlag is applied, 
# similar (by ~.5%) if smoothing+discounting is applied, 
# at least if no 
# smoothing/fixedLagging+discounting is applied
sub getCorrectnessHash {
	my ($seq, $discount) = @_;
	$discount or $discount = 0;
	$seq->cropSequence(); # only look at correctness in active phase of recognition
	# read reference alignment
	my $refAlignment = $seq->getGold();
	my $duration = $seq->getDuration();
	# initialize counters
	my $totalAlignments = 0;
	my $prefixCorrectAlignments = 0;
	my $strictCorrectAlignments = 0;
	my $fairCorrectAlignments = 0;
	my $time = $seq->getFirstAlignment()->{time}; # after cropping, this will start at the beginning
	while ($time <= $duration) {
		my $alignment = $seq->getAlignmentAt($time);
		# statistics for correctness
		$totalAlignments++;
		my $isPrefixCorrect = ($alignment->prefixUpTo($refAlignment, $time, 'lax'));
		my $isFairCorrect = ($refAlignment->equalsUpTo($alignment, $time - $discount, 'lax'));
		my $isStrictCorrect = ($refAlignment->equalsUpTo($alignment, $time, 'lax'));
		$prefixCorrectAlignments++ if ($isPrefixCorrect);
		$fairCorrectAlignments++ if ($isFairCorrect);
		$strictCorrectAlignments++ if ($isStrictCorrect);
		$time = sprintf("%.2f", $time + 0.01);
	}
	print "time: $time\n";
	return (total => $totalAlignments, 
		strictCorrect => $strictCorrectAlignments,
		prefixCorrect => $prefixCorrectAlignments,
		fairCorrect => $fairCorrectAlignments
	);
}

# get at hypothesis revision times, which can be used to estimate
# hypothesis stability
#algorithm could be as follows:
#- make an (empty) list of ages that will be returned
#- keep a list of @addTimes
#- iterate over @alignments and find @IUEdits relative to previous alignment
#- if add: add time of current alignment to @addTimes
#- if revoke: remove last time from @addTimes and put this time to ages
use Data::Dumper;
sub getHypothesisAges {
	my $self = shift;
	my @ages; # counts individual add times
	my @addTimes;
	my @alignments = @{$self->{alignments}};
	my $previousAlignment = $alignments[0];
	# put the initial timing of words into @addTimes
	foreach my $word ($previousAlignment->getWords('keepsilences')) {
		push @addTimes, $previousAlignment->getTime() unless (Label::isSilentText($word));
	}
	foreach my $alignment (@alignments[1..$#alignments]) {
		my @IUEdits = $alignment->diffInIUEdits($previousAlignment, 'keepsilences');
		if (@IUEdits) {
			my $time = $alignment->getTime();
			foreach my $edit (@IUEdits) {
				# ignore silence edits
				next if (Label::isSilentText($edit->{word}));
				if ($edit->isAdd()) {
					push @addTimes, $alignment->getTime();
				} elsif ($edit->isRevoke()) {
					confess "you're revoking something that is not there " . (Dumper $edit) . "in " . (Dumper $alignment) . "in file " . $self->{filename} unless @addTimes;
					push @ages, $time - pop @addTimes;
				} else { 
					confess "There shall only be adds and revokes.";
				}
			}
		}
		$previousAlignment = $alignment;
	}
	push @ages, (0) x $#addTimes;
	return @ages;
}

return 1;

