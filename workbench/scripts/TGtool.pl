#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/lib";

use strict;
use warnings;

use File::Temp; # the edit command places tiers into temporary files

require "TextGrid.pm";
require "Util.pm";

package TGshell;
require Term::Shell;
use base qw(Term::Shell);
use Scalar::Util qw(looks_like_number);

my $lastfilename = '';
my $hasChanges = Util->FALSE;
my $tg;
run_new();

sub new {
    my $cls = shift;
    my $o = bless {
        term    => eval {
            # Term::ReadKey throws ugliness all over the place if we're not
            # running in a terminal, which we aren't during "make test", at
            # least on FreeBSD. Suppress warnings here.
            local $SIG{__WARN__} = sub { };
            Term::ReadLine->new('shell', *STDIN, *STDOUT);
        } || undef,
    }, ref($cls) || $cls;

    # Set up the API hash:
    $o->{command} = {};
    $o->{API} = {
        args            => \@_,
        case_ignore     => ($^O eq 'MSWin32' ? 1 : 0),
        check_idle      => 0,   # changing this isn't supported
        class           => $cls,
        command         => $o->{command},
        cmd             => $o->{command}, # shorthand
        match_uniq      => 1,
        pager           => $ENV{PAGER} || 'internal',
        readline        => eval { $o->{term}->ReadLine } || 'none',
        script          => (caller(0))[1],
        version         => 0.02,
    };

    # Note: the rl_completion_function doesn't pass an object as the first
    # argument, so we have to use a closure. This has the unfortunate effect
    # of preventing two instances of Term::ReadLine from coexisting.
    my $completion_handler = sub {
        $o->rl_complete(@_);
    };
    if ($o->{API}{readline} eq 'Term::ReadLine::Gnu') {
        my $attribs = $o->{term}->Attribs;
        $attribs->{completion_function} = $completion_handler;
    }
    elsif ($o->{API}{readline} eq 'Term::ReadLine::Perl') {
        $readline::rl_completion_function = 
        $readline::rl_completion_function = $completion_handler;
    }
    $o->find_handlers;
    $o->init;
    $o;
}


sub prompt_str { "tg> " }


########## directory handling commands ##########

sub smry_ls { "list the directory" }
sub run_ls {
	my ($o, @args) = @_;
	system 'ls ' . join " ", @args;
}

sub smry_cd { "change directory" }
sub run_cd {
	my ($o, $dir) = @_;
	($dir) ? chdir $dir : chdir;
}

sub smry_pwd { "print working directory" }
sub run_pwd {
	my ($o, $dir) = @_;
	system 'pwd';
}

########## file handling commands ##########

sub smry_load { "load a file" }
sub help_load {
<<'END';
load  <filename> 	load a file
END
}

sub run_load {
	my ($o, $filename) = @_;
	if (!defined $filename) {
		run_new();
	} else {
		if ($hasChanges) {
			print "Discarding changes. I can't yet save automatically. Sorry for that.\n";
		}
		$tg = TextGrid::newTextGridFromFile($filename);
		if ($filename =~ m/\.s[12]h$/) {
			$filename =~ s/\.s[12]h$/\.TextGrid/;
		} elsif ($filename =~ m/\.par$/) {
			$filename =~ s/\.par$/\.TextGrid/;
		}
		$lastfilename = $filename;
		$hasChanges = Util->FALSE;
	}
}

sub comp_load {
	my @comps = glob "*";
	return @comps;
}

sub smry_save { "save tier or textgrid to a file" }
sub help_save { 
<<'END';
save [[<tier>] <filename>] 	if tier is given, write the tier to file, if no tier is given, write textgrid to file, if no filename is given, write to the filename last opened
END
}

sub run_save {
	my ($o, $tier, $filename) = @_;
	if (!defined $filename) {
		$filename = $tier;
		undef $tier;
	}
	if (defined $tier) {
		$tg->getAlignmentByName($tier)->saveToWavesurferFile($filename);
	} else {
		if (!defined $filename) {
			warn "overwriting your file $lastfilename.\n";
			$filename = $lastfilename;
		}
		$tg->saveToTextGridFile($filename);
	}
}

sub run_savemaryxml {
	my ($o, $filename, $lf0filename) = @_;
	$tg->saveToMaryXMLFile($filename, $lf0filename);
}

sub smry_new { "create a new TextGrid" }
sub run_new {
	if ($hasChanges) {
		print "Discarding changes. I can't yet save automatically. Sorry for that.\n";
	}
	$tg = TextGrid::new(0, 0, []);
}

########## TextGrid handling commands ##########

sub smry_show { "show alignment names or contents" }
sub help_show {
<<'END';
show [<tiername>] 	list the given tier or list the tier names if no tiername is given
END
}

sub printAlignments {
	my $tg = shift;
	print "TextGrid $lastfilename contains the following tiers:\n";
	print join "\n", $tg->getAlignmentNames();
	print "\n";
}

sub run_show {
	my ($o, $tiername) = @_;
	if (defined $tiername) {
		my $alignment = $tg->getAlignmentByName($tiername);
		if (defined $alignment) {
			print join "", $alignment->toWavesurferLines();
		} else {
			print "this tier doesn't exist. ";
			printAlignments($tg);
		}
	} else {
		printAlignments($tg);
	}
}

sub comp_show {
	return $tg->getAlignmentNames();
}

sub smry_TEDview { "show TextGrid in TEDview" }
sub help_TEDview { 
<<'END';
TEDview <port>	show TextGrid in TEDview (listening on <port>)
	        <port> defaults to 2000 (TEDview's default port)
END
}

sub run_TEDview {
	my ($o, $port) = @_;
	$port = 2000 unless ($port);
	$tg->toTED('127.0.0.1', $port);
}

sub smry_mark { "mark labels with colors" }
sub help_mark { 
<<'END';
mark [<tiername>] [<start> <end>] color		mark the labels in the given or all tiers between start and end (or all of times are omitted) in the given color; TEDview will now display the corresponding labels in the given color
END
}

sub run_mark {
	my ($o , @args) = @_;
	if ($#args < 0) {
		print "I need more arguments. Type \"help mark\".\n";
		return;
	}
	my $color = pop @args;
	if ($#args > 2) {
		print "I need less arguments. Type \"help mark\".\n";
		return;
	}
	my ($start, $end) = (-9999999, 9999999); # FIXME: weak approximation of +-infinity
	if ($#args > 0) { # start- and end-time are given
		$end = pop @args;
		$start = pop @args;
	}
	my @alignments;
	if ($#args >= 0) { # tiername is given
		@alignments = ($tg->getAlignmentByName($args[0]));
	} else {
		@alignments = $tg->{alignments};
	}
	foreach my $al (@alignments) {
		map { $_->setColor($color) }
			$al->getSpan($start, $end, 'strict')->getLabels();
	}
}

########## TextGrid handling commands ##########

sub smry_part { "show parts of an alignment" }
sub help_part {
<<'END';
part <tiername> <start> <end>	list the part of the given tiername from start-time to end-time
END
}

sub run_part {
	my ($o, $tiername, $start, $end) = @_;
	my $alignment = $tg->getAlignmentByName($tiername);
	if (defined $alignment) { 
		my $subAlignment = $alignment->getSpan($start, $end);
		print join "", $subAlignment->toWavesurferLines();
	} else {
		print "I need more arguments. Type \"help part\".\n";
	}
}

########## TextGrid search commands ##########

sub smry_grep { "grep in labels" }
sub help_grep { 
<<'END';
grep <regexp> [<tiername> ...]	search all or specific tiers for labeltext matching the regexp
END
}

sub run_grep {
	my ($o, $regexp, @tiers) = @_;
	if (!defined $regexp) {
		print "I need more arguments. Type \"help grep\".\n";
		return;
	}
	@tiers = $tg->getAlignmentNames() unless (@tiers);
	foreach my $tiername (@tiers) {
		my $tier = $tg->getAlignmentByName($tiername);
		print "occurences in $tiername:\n";
		print join "", 
			map { $_->toWavesurferLine() } 
				grep { $_->{text} =~ m/$regexp/ } 
					$tier->getLabels();
	}
}

########## TextGrid editing commands ##########

sub smry_srepl { "search/replace on labels" }
sub help_srepl { 
<<'END';
repl <search> <replace> [<tiername> ...]	search and replace the labels on all or specific tiers with a s///g regexp
END
}

sub run_srepl {
	my ($o, $search, $replace, @tiers) = @_;
	if (!defined $replace) {
		print "I need more arguments. Type \"help sed\".\n";
		return;
	}
	@tiers = $tg->getAlignmentNames() unless (@tiers);
	foreach my $tiername (@tiers) {
		my $tier = $tg->getAlignmentByName($tiername);
		map { $_->{text} =~ s/$search/$replace/g; } $tier->getLabels();
	}
}

sub smry_shift { "shift all one one specific alignment" }
sub help_shift {
<<'END';
shift <seconds> [<tiername> ...]	shift the given alignments (or all alignments if none given) by the number of seconds specified
END
}

sub run_shift {
	my ($o, $time, @tiers) = @_;
	if (!defined $time || !looks_like_number($time)) {
		print "I need a number as first argument Type \"help shift\".\n";
		return;
	}
	@tiers = map { "^$_\$" } $tg->getAlignmentNames() unless (@tiers);
	foreach my $tiername (@tiers) {
		my $tier = $tg->getAlignmentByName($tiername);
		$tier->timeShift($time);
	}
}

sub smry_edit { "edit an alignment" }
sub help_edit {
<<'END';
edit <tiername>	edit the tier in nedit
END
}

sub run_edit {
	my ($o, $tiername) = @_;
	if ((!defined $tiername) || (!defined $tg->getAlignmentByName($tiername))) {
		print "I need a tier name as argument. Type \"help edit\".\n";
		return;
	}
	my ($fh, $filename) = File::Temp::tempfile("${tiername}XXXX");
	print { $fh } join "", $tg->getAlignmentByName($tiername)->toWavesurferLines();
	close $fh;
	`\$EDITOR $filename`;
	my $alignment = Alignment::newAlignmentFromWavesurferFile($filename);
	unlink $filename;
	$alignment->setName($tiername);
	$tg->replaceAlignmentByName($tiername, $alignment);
}

sub comp_edit {
	return $tg->getAlignmentNames();
}

sub smry_add { "add an alignment" }
sub help_add {
<<'END';
add <filename> [<name> [<prev>]]	add the WS tier from filename to the textgrid
				with <name>, after the last tier which matches <prev>
END
}

sub run_add {
	my ($o, $filename, $tiername, $prevTiername) = @_;
	if (!defined $filename) {
		print "I need at least one argument. Type \"help add\".\n";
	}
	$tiername = "newTier" unless defined ($tiername);
	$prevTiername = "" unless defined ($prevTiername);
	my $alignment = Alignment::newAlignmentFromWavesurferFile($filename);
	$alignment->setName($tiername);
	$tg->addAlignmentAfter($alignment, $prevTiername);
}


sub smry_repl { "replace an alignment" }
sub help_repl { 
<<'END';
repl <tiername> <filename> replace the tier with an alignment read from filename
END
}

sub run_repl {
	my ($o, $tiername, $filename) = @_;
	if (!defined $filename) {
		print "I need two arguments. Type \"help repl\".\n";
		return;
	}
	my $alignment = Alignment::newAlignmentFromWavesurferFile($filename);
	$alignment->setName($tiername);
	$tg->replaceAlignmentByName($tiername, $alignment);
}

sub smry_rm { "remove an alignment" }
sub help_rm {
<<'END';
rm <tiername>	remove the tier from the textgrid
END
}

sub run_rm {
	my ($o, $tiername) = @_;
	$tg->removeAlignmentByName($tiername);
}

########## main package ##########

package main;

my $myshell = TGshell->new;
if (@ARGV) {
	foreach my $arg (@ARGV) {
		$myshell->cmd($arg);
	}
} else {
	STDIN->clearerr();
	$myshell->cmdloop;
}
