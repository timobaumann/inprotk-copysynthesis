#!/usr/bin/perl

package Label;
# perl module that defines a label which spans a certain time
# such a label has three mandatory attributes:
# - the start time of the label (in seconds)
# - the end time of the label (in seconds)
# - the label text itself (a string of characters except new line (\n))
# plus one optional attribute:
# - color: the color of the label when displayed in TEDview.
#   this attribute can only be set and exported to TEDview, 
#   there's no way to save this to a TextGrid or label file


use strict;
use warnings;
use XML::Quote;
require "Util.pm";
use Carp;
use Scalar::Util qw/weaken/; # to allow garbage collection despite circular references

sub new {
#	my ($xmin, $xmax, $text) = @_;
#	die "The label $text must not start ($xmin) after it's end ($xmax)!\n" if ($xmin > $xmax);
#	die "The label text must noch contain a new-line: $text\n" if ($text =~ m/\n/);
#	return bless { xmin => $xmin, xmax => $xmax, text => $text };
# faster version:
#	die "The label $_[2] must not start ($_[0]) after it's end ($_[1])!\n" if ($_[0] > $_[1]);
	confess "err: negative label duration: $_[2]\n" if ($_[0] > $_[1]);
#	die "The label text must noch contain a new-line: $_[2]\n" if ($_[2] =~ m/\n/);
	die "err: label contains newline\n" if ($_[2] =~ m/\n/);
	bless { xmin => $_[0], xmax => $_[1], text => $_[2] };
}

sub newLabelFromTextGridLines {
	my ($typename, @lines) = @_;
	my $line;
	if ($typename eq 'intervals') {
		my $xmin = Util::parseLine(shift @lines, 'xmin = (\d*(\.\d+)?)\s*');
		my $xmax = Util::parseLine(shift @lines, 'xmax = (\d*(\.\d+)?)\s*');
		my $text = Util::parseLine(shift @lines, 'text = "(.*)"\s*');
		return new($xmin, $xmax, $text);
	} elsif ($typename eq 'points') {
		my $time = Util::parseLine(shift @lines, 'time = (\d*(\.\d+)?)\s*');
		my $text = Util::parseLine(shift @lines, 'mark = "(.*)"\s*');
		return new($time, $time, $text);
	}
}

sub newLabelFromWavesurferLine {
#	my $line = shift;
#	chomp $line; chomp $line;
#	$line =~ m/(\d*(?:\.\d+)?)\s+(\d*(?:\.\d+)?)\s+(.*)$/ or die "Could not parse Wavesurfer line: $line\n";
#	my ($xmin, $xmax, $text) = ($1, $2, $3);
#	return new($xmin, $xmax, $text);
# faster version: 
#	chomp $_[0]; chomp $_[0]; # unnecessary, the $ in the regexp does this for us
	$_[0] =~ m/^(\-?\d*(?:\.\d+)?)\s+(\d*(?:\.\d+)?)\s+([^\t\n]*)(?:\t(.*))?$/ or die "errL0 : $_[0]";
		#die "Could not parse Wavesurfer line: $_[0]\n";
# calling new() is just too expensive
#	return new($1, $2, $3);
	confess "errL1\n" if ($1 > $2);
	if (defined $4) {
		my ($xmin, $xmax, $text, $addInfo) = ($1, $2, $3, $4);
		my %additionalInfo = (split /=|, /, $addInfo);
		return bless { xmin => $xmin, xmax => $xmax, text => $text, additionalInfo => \%additionalInfo };
	} else {
		return bless { xmin => $1, xmax => $2, text => $3 };
	}
}

sub toWavesurferLine {
#	my $self = shift;
#	return "$self->{xmin}\t$self->{xmax}\t$self->{text}\n";
	return join "\t", $_[0]->{xmin}, $_[0]->{xmax}, ($_[0]->{text} . "\n");
}

sub toTextGridLines {
	my $self = shift;
	return ("xmin = $self->{xmin} \n", "xmax = $self->{xmax} \n", "text = \"$self->{text}\" \n");
}

sub toTEDXMLLine {
	my $self = shift;
	my $orig = shift;
	my $start = int($self->{xmin} * 1000);
	my $dur = int($self->duration() * 1000);
	my $hasColor = exists $self->{color};
	return "<event time='$start' duration='$dur'" . 
	  (defined($orig) ? " originator='$orig'" : "") .
	    ($hasColor ? " color='" . XML::Quote::xml_quote($self->{color}) . "'>" : ">") . 
		XML::Quote::xml_quote($self->{text}) . "</event>";
}

use SVG;
sub toSVG {
	my ($self, $svg, $height) = @_;
	$svg = new SVG(
		"style" => "stroke: black; stroke-width: 0.01; text-anchor: middle; font-size: 0.1;",
	) unless (defined $svg);
#	$height = 0.3 unless (defined $height);
	$height = 1 unless (defined $height);
	my $group = $svg->group();
	$group->rectangle(
		"x" => $self->{xmin} + 0.015, 
		"y" => 0, 
		"rx" => $height * 0.05, 
		"ry" => $height * 0.05, 
		"width" => $self->duration - 0.015,
		"height" => $height,
		"style" => "fill: none; ",
		
	);
	$group->text(
		"x" => ($self->{xmin} + $self->{xmax}) / 2, 
		"y" => 5/6 * $height,
		"style" => "stroke: none; ",
	)->cdata($self->isSilent() ? "" : $self->{text});
	return $svg;
}

sub isEmpty {
	return ($_[0]->{text} eq '');
}

sub isSilent {
	$_[0]->{text} =~ m/^(?:\<(?:sil(?:ence)?|p:|\\?s)\>||SIL|_)$/;
}

use Carp;
# helper that checks a string for whether it's silence as defined by isSilent
sub isSilentText {
	confess unless (defined $_[0]);
	$_[0] =~ m/^(?:<(?:sil(?:ence)?|p:)>||SIL|_)$/;
}

sub timeShift {
	my ($self, $time) = @_;
	$self->{xmin} += $time;
	$self->{xmax} += $time;
}

# check whether two labels are equal
# $mode: 
# 'lax': only label text must be identical
# 'nocase': ignore case in label text comparison
# 'strict': label boundaries must be equal as well
# TODO: 'time': only label boundaries must be equal, text is ignored
sub equals {
	my ($self, $other, $mode) = @_;
	$mode = 'strict' unless (defined $mode);
	return (($self->{text} eq $other->{text}) || (($mode =~ m/nocase/i) && uc($self->{text}) eq uc($other->{text}))) &&
		(($mode =~ m/lax/) || (($self->{xmin} == $other->{xmin}) && ($self->{xmax} == $other->{xmax})));
}

sub clone {
	my $self = shift;
	return new($self->{xmin}, $self->{xmax}, $self->{text});
}

sub duration {
	my $self = shift;
	return ($self->{xmax} - $self->{xmin});
}

sub durationInDots {
	my $self = shift;
	my $dotDuration = shift;
	my $mode = shift;
	$mode = 'linear' unless ($mode);
	my $dots = "";
	my $duration = $self->duration();
	$duration = log($duration + 1) if ($mode =~ m/log/);
	while ($duration > 0) {
		$dots .= '.';
		$duration -= $dotDuration;
	}
	return $dots;
}

# for a given time return the absolute differences between this label's start-time and end-time 
# and a relative position of the given time normalized by the word's duration
sub getTimings {
	my $self = shift;
	my $time = shift;
	my $start = $self->{xmin};
	my $end = $self->{xmax};
	my $duration = $end - $start;
	my $from_start = $time - $start;
	my $to_end = $time - $end;
	my $word_rel = ($duration != 0) ? $from_start / $duration : 1; # avoid division by zero 
	return ($from_start, $to_end, $word_rel);
}

# get the temporal middle of this label
sub getCenter {
	my $self = shift;
	return ($self->{xmin} + $self->{xmax}) / 2;
}

# set a color property on this label
# colors are only relevant when exporting to TEDview XML; 
# that's why there's currently no getter to this property
sub setColor {
	my $self = shift;
	my $color = shift;
	$self->{color} = $color;
}

sub setGrounds {
	my $self = shift;
	my $upper = shift;
	weaken($self->{grounds} = $upper);
	push @{$upper->{groundedIn}}, $self;
}

sub setSuccessor {
	my $self = shift;
	my $next = shift;
	weaken($self->{succ} = $next);
	weaken($next->{pred} = $self);
}

sub getPredecessor {
	my $self = shift;
	return exists $self->{pred} ? $self->{pred} : ();
}

sub getSuccessor {
	my $self = shift;
	return exists $self->{succ} ? $self->{succ} : ();
}

sub toIUStructure {
	my $self = shift;
	return $self->toWavesurferLine() . ( exists $self->{groundedIn} ? "\t" . join "\t", map { $_->toIUStructure() } @{$self->{groundedIn}} : "" );
}

# called recursively, however, this needs to account for maryxml structural information (whether a layer is words or phonemes). 
sub toMaryXML {
	my $self = shift;
	my $layer = (shift or 'words');
	# word tokens:
	if ($layer eq 'words') {
		if (exists $self->{groundedIn}) {
			return "  <t>" . $self->{text} . "<syllable>\n" . ( join "", map { $_->toMaryXML('phonemes'); } @{$self->{groundedIn}} ) . "  </syllable></t>\n";
		} else {
			return "<boundary breakindex='1' duration='" . int($self->duration * 1000 + .5) . "'/>\n";
		}
	# phoneme segments:
	} else {
		my $f0String = "";
		if (exists $self->{f0}) {
			$f0String = "f0='";
			my $numf0 = $#{$self->{f0}};
			for (my $i = 0; $i <= $numf0; $i++) {
				$f0String .= 
					"(" . 
					int($i * 100 / $numf0 + .5) . 
					"," .
					$self->{f0}[$i] .
					")";
				$f0String .= " " if ($i < $numf0);
			}
			$f0String .= "' ";
		}
		return "    <ph d='" . int($self->duration * 1000 + .5) . 
			"' end='" . $self->{xmax} . 
			"' p='" . $self->{text} . "' " . 
			$f0String . "/>\n";
	}
}

return 1;
