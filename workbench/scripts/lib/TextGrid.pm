#!/usr/bin/perl

package TextGrid;
# perl module that defines a collection of alignments (i.e. a TextGrid)

use utf8;
binmode STDIN, ":encoding(utf8)";
binmode STDOUT, ":encoding(utf8)";

use strict;
use warnings;
use IO::Socket; # to output to TED
use Carp qw(cluck confess carp croak);

require "Util.pm";
require "Alignment.pm";

# create a new TextGrid object
sub new {
	# $xmin: start-time of TextGrid, 
	# $xmax: end-time of TextGrid, 
	# $alignments: reference to a list of alignments (see Alignment.pm)
	# $format: if set to "lax", xmin and xmax will be set automatically 
	# 	to the time spanned by the alignment list
	my ($xmin, $xmax, $alignments, $format, $name) = @_;
	$name = '' unless (defined $name);
	# first check alignments
	my ($alignmentXMin, $alignmentXMax) = checkAlignments($alignments);
	# check that boundaries of alignments are within the TextGrids limits
	if (($alignmentXMin < $xmin) || ($alignmentXMax > $xmax)) {
		print STDERR "some alignments exceed the min/max given for the TextGrid: ($alignmentXMin < $xmin) || ($alignmentXMax > $xmax)" if ((Util->WARN > 0) && ($format ne 'lax'));
		print STDERR "resetting TG boundaries\n" if ((Util->DEBUG > 0) && ($format eq 'lax'));
		$xmin = $alignmentXMin if ($format eq 'lax');
		$xmax = $alignmentXMax if ($format eq 'lax');
	}
	return bless { xmin => $xmin, xmax => $xmax, alignments => $alignments, name => $name };
}

# check that all alignments are of type "Alignment" and calculate the limits 
sub checkAlignments {
	my @alignments = @{$_[0]};
	if ($#alignments == -1) {
		return (0, 0);
	} else {
		my $xmin;
		my $xmax;
		foreach my $alignment (@alignments) {
			die "[TextGrid::checkAlignments] alignments must be of Type Alignment: $alignment!" unless (ref($alignment) eq 'Alignment');
			$xmin = Util::min($xmin, $alignment->{xmin});
			$xmax = Util::max($xmax, $alignment->{xmax});
		}
		return ($xmin, $xmax);
	}
}

# creates a new TextGrid object from given text data (syntactically forming a TextGrid file)
sub newTextGridFromLines {
	my @lines = @_;
	my $line;
	Util::parseLine(shift @lines, 'File type = "ooTextFile"');
	Util::parseLine(shift @lines, 'Object class = "TextGrid"');
	# most TGs contain one empty line next, but this is missing from AuToBI-generated TGs:
	shift @lines if ($lines[0] =~ m/^\s*$/);
	my $xmin = Util::parseLine(shift @lines, 'xmin = (\d*(\.\d+)?)');
	my $xmax = Util::parseLine(shift @lines, 'xmax = (\d*(\.\d+)?)');
	my $hasTiers = Util::parseLine(shift @lines, 'tiers\? (<exists>)?');
	die "[TextGrid::newTextGridFromLines] This TextGrid doesn't have any tiers. You're weird. \n$line\n" unless ($hasTiers);
	my $size = Util::parseLine(shift @lines, 'size = (\d+)\s*');
	my @alignments;
	print STDERR "[TextGrid::newTextGridFromLines] parsing TextGrid data from $xmin to $xmax with $size alignments.\n" if (Util->DEBUG > 0);
	$line = shift @lines;
	if (Util::parseLine($line, 'item \[(.*)\]:')) {
		unshift @lines, $line;
		print STDERR "[TextGrid::newTextGridFromLines] using quirk for MAUS TextGrid...\n" if (Util->DEBUG > 0);
	}
	for my $i (1..$size) {
		my @tierLines;
		Util::parseLine(shift @lines, "item \\[$i\\]:");
		my $nextI = $i + 1;
		while (($#lines > -1) && ($lines[0] !~ m/^\s*item\s*\[$nextI\]:\s*$/)) {
			push @tierLines, shift @lines;
		}
		push @alignments, Alignment::newAlignmentFromTextGridLines(@tierLines);
	}
	die ("[TextGrid::newTextGridFromLines] there is still data to be processed, but I don't know how to process it: " . join "", @lines) if ($#lines != -1);
	return new($xmin, $xmax, \@alignments);
}

# create a new, empty TextGrid object
sub newEmptyTextGrid {
	return new(0, 0, []);
}

# create a new TextGrid object from a given file (supported file types are autosensed)
sub newTextGridFromFile {
	my $filename = shift;
	my $tg;
	if ($filename =~ m/\.s[12]h$/) {
		print STDERR "I autosensed a s1h/s2h-file.\n" if (Util->DEBUG > 0);
		$tg = TextGrid::newTextGridFromS1HFile($filename);
	} elsif ($filename =~ m/\.par$/) {
		print STDERR "I autosensed a par-file.\n" if (Util->DEBUG > 0);
		$tg = TextGrid::newTextGridFromPARFile($filename);
	} elsif ($filename =~ m/\.TextGrid$|\.tg$/) {
		$tg = TextGrid::newTextGridFromTextGridFile($filename);
	} elsif ($filename =~ m/\.json$/) {
		$tg = TextGrid::newTextGridFromJSONFile($filename);
	} else {
		print STDERR "I could not autosense file type. Assuming TextGrid. Proceed at your own risk.\n";
		$tg = TextGrid::newTextGridFromTextGridFile($filename);		
	}
	return $tg;
}

# create a new TextGrid object from a given file (data must syntactically form a TextGrid) 
sub newTextGridFromTextGridFile {
	my $filename = shift;
	use Encode::Guess;
	open inFile, '<', $filename or die "Cannot open file $filename: $!";
	binmode(inFile);
	local $/;
	my $content = <inFile>;
	close inFile;
	my $enc = guess_encoding($content, qw/iso-8859-15 UTF-16LE UTF-16BE/);
	# if it may be multiple things, try just UTF-8
	if ($enc =~ m/ or /) {
		$enc = guess_encoding($content);
	}
        confess "Unable to guess encoding: $enc" unless (ref $enc);
	#warn "guessing encoding ", $enc->name, "\n" unless ($enc->name =~  m'iso-8859-15|ascii');
	my @lines = split /\n/, $enc->decode($content);
	# if it's there, remove the unicode byte-order-mark BOM
	$lines[0] =~ s/^\N{U+FEFF}// and warn "BOM found and removed.\n";
	my $tg;
	# try
	eval { $tg = newTextGridFromLines(@lines); };
	# catch
	die "error opening $filename: $@\n" if ($@);
	$tg->{name} = $filename;
	return $tg;
}

# create a new TextGrid object from a given S1H file (Kiel Corpus)
sub newTextGridFromS1HFile {
	my $DEBUG = (1 == 1);
	my $filename = shift;
	print "now processing $filename\n" if ($DEBUG);
	open S1H, '<', $filename or die "Cannot open file $filename: $!";
	my $line;
	$line = <S1H>; chomp $line; chomp $line; # first line contains the filename
	if ($filename !~ /$line$/) { # disregard (path) prefix in filename
		die "filename ($filename) and infile-filename ($line) do not match.\n";
	}
	my $S2H_MODE = ($filename =~ m/.s2h$/);
	my $words; # bekommt den Wortstring
	while ($line = <S1H>, $line !~ m/^oend/) {
		chomp $line; chomp $line;
		$words .= $line;
	}
	# remove speaker ID which is incorporated in S2H files (but not S1H files)
	($S2H_MODE == ($words =~ m/^[A-Z]{3}[0-9]{3}: /)) or warn "I expect S2H-files to start with a speaker ID, AND I expect S1H-files NOT to start with a speaker ID: $words";
	if ($S2H_MODE) {
		$words =~ s/^[A-Z]{3}[0-9]{3}: //;
	}
	$words =~ tr/[\\]{|}~/ÄÖÜäöüß/; # convert awkward symbols to umlauts and ess-zett
	$words =~ s/[\,\.\:\!\?\-]//g; # remove punctuation
	$words =~ s/\s+/ /g; # change all whitespace to one simple space
	my @words = split " ", $words; # split the words into a word-array
	print STDERR (join " ", @words) if ($DEBUG);

	while ($line = <S1H>, $line !~ m/^hend/) {
		# ignore the canonical and the actual transcription
	};

	my @accents; # saves accentuation markers until the exact position (vowel) is reached

	my $sampleduration = 1 / 16000;
	my $time;
	my $lastsegment = '_';
	my $printlastsegment = 1;
	my $lasttime = 0.0;
	my $wordstart = 0.0;

	my $wordAlignment = Alignment::new("words", 0, 0, [], "lax");
	my $phoneAlignment = Alignment::new("phones", 0, 0, [], "lax");
	my $accentAlignment = Alignment::new("accents", 0, 0, [], "lax");
	my $phraseAlignment = Alignment::new("phrases", 0, 0, [], "lax");

	while ($line = <S1H>) {
		chomp $line; chomp $line;
		(my ($sample, $label), $time) = split ' ', $line; # split on whitespace while ignoring leading whitespace
		# check sanity of sample and time information
		if (abs($sample * $sampleduration - $time) > 0.0001) {
			die "Problem with time vs. samples in file $filename, (line: $line)\n";
		}
		
		# print last segment (now that we know, when it ends)
		if ($printlastsegment) {
			# do not print plosive releases,
			unless (($label =~ m/^\$-h\+?/) && ($lastsegment =~ m/[ptkbdg]/)) {
				my $phoneLabel = Label::new($lasttime, $time, $lastsegment);
				$phoneAlignment->addLabel($phoneLabel);
				print STDERR "added a PHONE label:" . (join " ", $phoneLabel->toWavesurferLine()) if ($DEBUG);
#				if ($sampa2ibm{$lastsegment}) { # check, that only sampa-symbols are emitted
#					print SEG "\t$time\t121\t$sampa2ibm{$lastsegment}\n";
##					print  "\t$time\t121\t$sampa2ibm{$lastsegment}\n";
#				}
#				else { # not in the sampa2ibm-list. check, if this is a diphthong with schwa
#					$lastsegment =~ m/^(.+)6$/;
#					my $firstpart = $1;
#					$sampa2ibm{$firstpart} or die "Segment not in sampa-format: $lastsegment.\n";
#					# for schwa-diphthongs give first segment 2/3 and schwa 1/3 of the time
#					my $t = $time - (($time - $lasttime) / 3);
#					($time != $lasttime) or die "time and lasttime must be different.\n";
#					print SEG "\t$t\t121\t$sampa2ibm{$firstpart}\n";
#					print SEG "\t$time\t121\t$sampa2ibm{'6'}\n";
#				}
			} else {
				next; # but go on to next segment
			}
			$printlastsegment = 0;
		}

		# analyse the current label 
		if ($label =~ m/&/) { # prosodic information
			$label =~ s/^[\#\$]//; # remove first sign (it does not contain any relevant information
			# handle phrase boundaries
			if ($label =~ m/PGn/) { 
				next if ($label =~ m/%/); # ignore uncertain phrase boundaries
				$phraseAlignment->addLabel(Label::new($time, $time, "PGn"));
				next;
			}
			# push accentuation marks to @accents
			if (($label =~ m/([123])[\^\(\)\[\]]/) && ($label !~ m/HP/)) {
				push @accents, $1;
				next;
			}
			# other well defined, but unimportant labels
#			die "This should not be reached ($label)\n";
		}
		else { # segmental (and word boundary) information
			if ($label =~ s/^\#\#//) {
				unless ($wordstart == 0.0) { # ignore first beginning of a word
					my $word = shift @words or die "Error in file $filename: No word left for line $line.\n";
					my $wordLabel = Label::new($wordstart, $time, $word);
					$wordAlignment->addLabel($wordLabel);
					print STDERR "added a PHONE label:" . (join " ", $wordLabel->toWavesurferLine()) if ($DEBUG);
				}
				$wordstart = $time;
			}
			$label =~ s/^[\#\$]+//; # remove first sign (it does not contain any relevant information
			if (($label eq "''") || ($label =~ /\'/)) { # handle accentuations
				my $accent = shift @accents; # or die "No accent left in file $filename!\n";
				$accentAlignment->addLabel(Label::new($time, $time, "a")) if (($accent) && ($accent > 1)); # ignore partial accentuations
				next if ($label eq "''");
			}
			next if ($label =~ m/[cz]:/); # next on sentence boundary (c:) and hesitational lengthening (z:)
			next if ($label =~ m/[\!\?\,\.]/); # next on pronunciation label
			next if ($label =~ m/-[kp]?q/); # ignore creaky voice label
			$label =~ s/[%\+]//g; # remove function word (+) and uncertainty (%) markers
			# words may contain silence as their last phoneme,
			# which should rather reside in separate silence words
			if ($label =~ m/[phsv]:/) { # convert all types of pauses to underscore
				$label =~ s/[phsv]:/_/; 
				my $word = shift @words or die "Error in file $filename: No word left for line $line.\n";
				my $wordLabel = Label::new($wordstart, $time, $word);
				$wordAlignment->addLabel($wordLabel);
				print STDERR "added a PHONE label:" . (join " ", $wordLabel->toWavesurferLine()) if ($DEBUG);
				unshift @words, '_';
				$wordstart = $time;
			}
			$label =~ s/.*-//; # remove parts that were not realized
			$label =~ s/[\'\"]//; # remove the accentuation information
			next if ($label eq '~'); # remove nasalization label
			next if ($label eq ':k'); # no idea what the label means, we don't want it.
			$label =~ s/=6/6/; # do not handle schwa after vowel differently
			next unless ($label); # if nothing is left of the label, then continue to the next
			next if (($lastsegment eq '_') && ($label eq 'Q')); # ignore uncertain glottal stops after pauses
			$lastsegment = $label; # print the label in the next loop
			$lasttime = $time;
			$printlastsegment = 1;
		}
	}
	my $word = shift @words or die "Error in file $filename: No word left for line $line!\n";
	my $wordLabel = Label::new($wordstart, $time, $word);
	$wordAlignment->addLabel($wordLabel);
	print STDERR "added a PHONE label:" . (join " ", $wordLabel->toWavesurferLine()) if ($DEBUG);
	close S1H;
	if (@words) { confess "Error in file $filename: There is still some word left to be processed (" . join (", ", @words) . ")\n"; }
	if (@accents) { warn "Error in file $filename: There is still some accent left to be processed (" . join (", ", @accents) . ")\n"; }
	return new(0, 0, [$wordAlignment, $phoneAlignment, $accentAlignment, $phraseAlignment], "lax", $filename);
}

# create a new TextGrid object from a given PAR file (Verbmobil Corpus)
sub newTextGridFromPARFile {
	my $filename = shift;
	open PAR, '<', $filename or die "Cannot open file $filename: $!";
	my $line;
	my $sampling;
	my @words; # words will be hashes containing the word's orthography, and start/end times
	my @phoneLabels;
	while ($line = <PAR>) {
		chomp $line; chomp $line;
		$line =~ m/^([A-Z0-9]{3}\:)(.*)$/ or die "malformatted line $line in $filename.";
		my $type = $1;
		my $payload = $2;
		if ($type eq 'SAM:') {
			$payload =~ m/^ (\d+)$/ or die "malformatted payload in line $line in $filename.";
			$sampling = $1;
		} elsif ($type eq 'ORT:') {
			$payload =~ m/^\s(\d+)\s(.+)$/ or die "malformatted payload in line $line in $filename.";
			my ($wordID, $label) = ($1, $2);
			$label =~ s/\"a/ä/g;
			$label =~ s/\"o/ö/g;
			$label =~ s/\"u/ü/g;
			$label =~ s/\"A/Ä/g;
			$label =~ s/\"O/Ö/g;
			$label =~ s/\"U/Ü/g;
			$label =~ s/\"s/ß/g;
			die "redefinition of word $wordID in line $line in $filename" if (defined $words[$wordID]);
			$words[$wordID] = { label => $label };
		} elsif ($type eq 'MAU:') {
			$payload =~ m/^\t(\d+)\t(\d+)\t(\-1|\d+)\t(.+)$/ or die "malformatted payload in line $line in $filename.";
			my ($start, $end, $wordID, $label) = ($1 / $sampling, ($1 + $2) / $sampling, $3, $4);
			push @phoneLabels, Label::new($start, $end, $label);
			if ($wordID != -1) {
				if (!exists $words[$wordID]->{start}) {
					$words[$wordID]->{start} = $start;
				}
				$words[$wordID]->{end} = $end;
			}
		}
	}
	close PAR;
	my $phoneAlignment = Alignment::new('MAU:', 0, 0, \@phoneLabels, 'lax');
	my @wordLabels;
	for my $word (@words) {
		if (!exists $word->{start}) {
			print STDERR "WARNING: word $word->{label} does not have phones attached. I'll leave it out.\n";
		} else {
			push @wordLabels, Label::new($word->{start}, $word->{end}, $word->{label});
		}
	}
	my $wordAlignment = Alignment::new('ORT:', 0, 0, \@wordLabels, 'lax');
	return new(0, 0, [$wordAlignment, $phoneAlignment], 'lax');
}

use JSON;
use utf8;
use Encode qw/encode/;

sub newTextGridFromJSONFile {
	my $filename = shift;
	open JSON, '<', $filename or die "Cannot open file $filename: $!";
	my $json = decode_json(encode("utf8", (join " ", <JSON>)));
	close JSON;
	my @wordLabels;
	foreach my $word (@{$json->{'words'}}) {
		my $start = $word->{'start'};
		my $end = $word->{'stop'};
		my $label = $word->{'normalized'};
		push @wordLabels, Label::new($start * .001, $end * .001, $label) if (defined $start && defined $end && $label ne '');
	}
	my $wordAlignment = Alignment::new('words', 0, 0, \@wordLabels, 'lax');
	return new (0, 0, [$wordAlignment], 'lax');
}

# create written TextGrid data from a TextGrid object
sub toTextGridLines {
	my $self = shift;
	my @lines;
	push @lines, "File type = \"ooTextFile\"\n";
	push @lines, "Object class = \"TextGrid\"\n";
	push @lines, "\n";
	push @lines, "xmin = $self->{xmin} \n";
	push @lines, "xmax = $self->{xmax} \n";
	push @lines, "tiers? <exists> \n";
	my $size = 1 + $#{$self->{alignments}};
	push @lines, "size = $size \n";
	push @lines, "item []: \n";
	my $i = 1;
	foreach my $alignment (@{$self->{alignments}}) {
		# assert that the alignments are of the same dimensions as the TextGrid itself
		$alignment->{xmin} = $self->{xmin};
		$alignment->{xmax} = $self->{xmax};
		push @lines, "    item [$i]:\n";
		push @lines, map { "        " . $_ } $alignment->toTextGridLines();
		$i++;
	}
	return @lines;
}

# create written XML data for TEDview from a TextGrid object
sub toTEDXMLLines {
	my ($self, $noTopLevelElement) = @_;
	$noTopLevelElement = '' unless (defined $noTopLevelElement);
	my @lines;
	foreach my $alignment (@{$self->{alignments}}) {
		my $orig = $alignment->{name};
		#push @lines, "<control originator='$orig' action='clear' />";
		push @lines, $alignment->toTEDXMLLines($orig, 'nowrap');
	}
	return ($noTopLevelElement ne 'nowrap') ? 
			("<dialogue id='" . 
			(defined $self->{name} ? $self->{name} : '') .
			"'>", 
				 @lines, 
			"</dialogue>") :
			@lines;
}

# this function can turn a TextGrid created by MAUS (or WebMAUS) into the correspondingly timed MaryXML
sub toMaryXMLLines {
	my $self = shift;
	my $lf0File = shift;
	my $wordAlignments = $self->getAlignmentByName('^ORT-MAU$') or die "this textgrid does not contain a MAUS orthography layer (ORT-MAU) and hence cannot be turned into MaryTTS";
	my $phoneAlignments = $self->getAlignmentByName('^MAU$') or die "this textgrid does not contain a MAUS segment alignment layer (MAU) and hence cannot be turned into MaryTTS";
	$wordAlignments->groundedInFromTimes($phoneAlignments);
	$wordAlignments->makeContinuous();
	if ($lf0File) {
		open LF0, '<', $lf0File;
		my @f0;
		for my $line (<LF0>) {
			chomp $line; chomp $line;
			push @f0, int(exp($line)+.5);
		}
		for (my $i = 0; $i <= $#f0; $i++) {
			my $time = $i * .005; # one frame every 5 ms.
			#print $phoneAlignments->getLabelAt($time)->toWavesurferLine();
			push @{$phoneAlignments->getLabelAt($time)->{f0}}, $f0[$i];
			#print join ",", @{$phoneAlignments->getLabelAt($time)->{f0}};
		}
	}

	my $xml = '<?xml version="1.0" encoding="UTF-8"?>
<maryxml xmlns="http://mary.dfki.de/2002/MaryXML" version="0.5" xml:lang="de"><phrase>
';
	for my $word ($wordAlignments->getLabels()) {
#		print $word->toIUStructure();
		$xml .= $word->toMaryXML();
	}
	$xml .= '</phrase></maryxml>
';
	return $xml;
}

# send data (TextGrid object) to TEDview
sub toTED {
	my ($self, $IP, $port) = @_;
	$IP = '127.0.0.1' unless ($IP);
	$port = 2000 unless ($port);
	my $sock = new IO::Socket::INET(PeerAddr => $IP, PeerPort => $port, Proto => 'tcp');
	print $sock join "\n", $self->toTEDXMLLines('wrap');
	close $sock;
}

# save a TextGrid object to a file
sub saveToTextGridFile {
	my $self = shift;
	my $filename = shift;
	open outFile, '>:encoding(latin1)', $filename or die "Could not write to file $filename\n";
	print outFile join "", $self->toTextGridLines();
	close outFile;
}

# save a TextGrid object to a file, as TEDXML
sub saveToTEDXMLFile {
	my $self = shift;
	my $filename = shift;
	open outFile, '>:encoding(utf8)', $filename or die "Could not write to file $filename\n";
	print outFile join "", $self->toTEDXMLLines('withTopLevelElement');
	close outFile;
}

sub saveToMaryXMLFile {
	my $self = shift;
	my $filename = shift;
	open outFile, '>:encoding(utf8)', $filename or die "Could not write to file $filename\n";
	print outFile join "", $self->toMaryXMLLines(@_);
	close outFile;
}

# create a list of all tier names found in the TextGrid object
sub getAlignmentNames {
	my $self = shift;
	return map { $_->getName() } @{$self->{alignments}};
}

# get all alignments that match a given string
sub getAlignmentsByName {
	my $self = shift;
	my $name = shift;
	return grep { $_->getName() =~ m/$name/ } @{$self->{alignments}};
}

# get the first alignment that matches a given string
sub getAlignmentByName {
	my $self = shift;
	my $name = shift;
	my @matchingAlignments = $self->getAlignmentsByName($name);
	cluck "no or several alignments (" . ($#matchingAlignments + 1) . ") match the name '$name'. I'll give you the first one.\n" if (($#matchingAlignments != 0) && (Util->WARN > 0));
	return $matchingAlignments[0];
}

# check if a TextGrid object has an alignment with the specified name  
sub hasAlignment {
	my $self = shift;
	my $name = shift;
	no warnings;
	return ((scalar $self->getAlignmentsByName($name)) > 0);
}

# add the specified alignment to a TextGrid object 
sub addAlignment {
	my $self = shift;
	my @alignments = @{$self->{alignments}};
	my $newAlignment = shift;
	die "I can't add an alignment that already exists" if ($self->hasAlignment($newAlignment->getName()));
	my $position = shift;
	if (!defined $position) {
		$position = $#alignments + 1;
	}
	print "DEBUG: inserting alignment at position $position\n" if (Util->DEBUG > 0);
	splice @alignments, $position, 0, $newAlignment;
	$self->{alignments} = \@alignments;
	$self->{xmin} = Util::min($self->{xmin}, $newAlignment->{xmin});
	$self->{xmax} = Util::max($self->{xmax}, $newAlignment->{xmax});
}

# add the specified alignment after another specified alignment in the TextGrid object at a specified position
sub addAlignmentAfter {
	my ($self, $newAlignment, $name) = @_;
	my $position;
	my $i = 0;
	map { $i++; if ($_->getName() =~ m/$name/) { $position = $i } } @{$self->{alignments}};
	print "DEBUG: inserting alignment after name $name at position $position\n" if (Util->DEBUG > 0);
	$self->addAlignment($newAlignment, $position);
}

# remove the alignment with the specified name
sub removeAlignmentByName {
	my $self = shift;
	my $name = shift;
	warn "no such alignment $name!\n" unless $self->hasAlignment($name);
	my @newAlignments = grep { $_->getName() ne $name } @{$self->{alignments}};
	$self->{alignments} = \@newAlignments;
}

# replace the alignment with the specified name with a specified alignment
sub replaceAlignmentByName {
	my $self = shift;
	my $name = shift;
	my $alignment = shift;
	@{$self->{alignments}} = map { ($_->getName() eq $name) ? $alignment : $_ } @{$self->{alignments}};
}

# shift the overall times of all Alignments by a given value
sub timeShift {
	my ($self, $time) = @_;
	foreach my $al (@{$self->{alignments}}) {
		$al->timeShift($time);
	}
}


return 1;
