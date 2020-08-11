#!/usr/bin/perl

package Wave;

use strict;
use warnings;
use Audio::Wav;
use Audio::Wav::Read;
use Audio::Wav::Write;
use POSIX;

my $AUDIO_PROCESSOR = Audio::Wav::new();

sub newFromFile {
	my ($filename) = @_;
	my $audio = $AUDIO_PROCESSOR->Audio::Wav::read($filename) or die "Could not open wavefile $filename\n";
	return bless { filename => $filename, audio => $audio };
}

sub saveSpan {
	my ($self, $startTime, $endTime, $outfilename) = @_;
	my $duration = $endTime - $startTime;
	my $audio = $self->{audio};
	my $audio_details = $audio->details();
	# move to the start in inAudio
	$audio->move_to_sample($self->time2sample($startTime));
	# read data from inAudio into buffer
	my $buffer = $audio->read_raw_samples($self->time2sample($duration));
	# open outAudio
#print STDERR "I should be writing a file called $outfilename\n";
	my $outAudio = $AUDIO_PROCESSOR->Audio::Wav::write($outfilename, $audio_details);
	# write data from buffer to outAudio
	$outAudio->write_raw_samples($buffer);
	# close outAudio
	$outAudio->finish();
}

sub time2sample {
	my ($self, $time) = @_;
	my $samplingRate = $self->{audio}->details()->{'sample_rate'};
	return POSIX::floor($time * $samplingRate);
}

return 1;
