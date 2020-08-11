package Histogram;

use strict;
use warnings;
use Statistics::Lite qw/min max/;
use Carp;

sub new {
	my $data = $_[0];
	return bless { data => $data };
}

# supports the following modes: 
# 'equidistant' with parameters width and start_at and number_of_bins
# (e.g. createBinBoundaries('equidistant', 1, -0.5, 101)
# 'bins' which creates a given number of bins between min and max values in the data
# (e.g. createBinBoundaries('bins', 10)
sub createBinBoundaries {
	my $self = shift @_;
	my $mode = @_ ? shift @_ : 'default';
	my @binBoundaries;
	if ($mode eq 'equidistant') {
		my $width = @_ ? shift @_ : croak("no width given");
		$self->{width} = $width;
		my $start_at = @_ ? shift @_ : -0.5;
		my $bins = @_ ? shift @_ : 999;
		@binBoundaries = map { $_ += $start_at } map { $_ *= $width } (0..$bins);
	} elsif ($mode eq 'exponential') {
#		my 
		@binBoundaries = (0.4783, 0.5314, 0.5905, 0.6561, 0.729, 0.9, 1.0, 1.1111, 1.2346, 1.3717, 1.5242, 1.6935, 1.8817, 2.0908);
	} else {
		@binBoundaries = (0..100);
	}
	$self->{binBoundaries} = \@binBoundaries;
}

sub assertBinBoundaries {
	my ($self) = @_;
	$self->createBinBoundaries() unless (defined $self->{binBoundaries});
}

# private sub (if this existed for perl) to compute the binID for a given value
sub getBinForValue {
	my ($value, @binBoundaries) = @_;
	my $i = 1;
	while (defined $binBoundaries[$i] && $value > $binBoundaries[$i]) {
		$i++;
	}
	$i--; # we're looking for the preceeding bin, the one which is not larger
	return $i; 
}

# find out the filling status of all bins
sub getBinCounts {
	my ($self) = @_;
	$self->assertBinBoundaries();
	my @binBoundaries = @{$self->{binBoundaries}};
	my @binCounts;
	for my $data (@{$self->{data}}) {
		$binCounts[getBinForValue($data, @binBoundaries)]++;
	}
	if ($self->usePercent()) {
		map { $_ ? $_ /= scalar @{$self->{data}}  : undef } @binCounts;
	}
	return @binCounts;
}

sub usePercent {
	my ($self) = @_;
	return (defined $self->{usePercent} && $self->{usePercent});
}

sub accumulateCounts {
	my ($self) = @_;
	return (defined $self->{accumulateCounts} && $self->{accumulateCounts});
}

sub getBinNames {
	my ($self, $mode) = @_;
	my @names;
	if (defined $self->{binNames}) {
		@names = $self->{binNames};
	} elsif (!defined $mode || $mode eq 'basic') {
		my @binBoundaries = @{$self->{binBoundaries}};
		my @binCounts = $self->getBinCounts();
		foreach my $binID (0..$#binBoundaries - 1) {
			push @names, defined $binCounts[$binID] ? "from $binBoundaries[$binID] (excluding) to $binBoundaries[$binID+1] (including):" : undef;
		}
	} elsif ($mode eq 'gnuplot') {
		my @binBoundaries = @{$self->{binBoundaries}};
		my @binCounts = $self->getBinCounts();
		while (!defined $binCounts[0]) {
			shift @binCounts;
			shift @binBoundaries;
		}
		foreach my $binID (0..$#binBoundaries - 1) {
			my $binCenter = ($binBoundaries[$binID + 1] + $binBoundaries[$binID]) / 2;
			$binCenter = 0 if (abs($binCenter) < 0.00001);
#			if (defined $binCounts[$binID]) {
				push @names, "$binCenter";
#			}			
		}
	} else {
		croak("unknown bin-name mode $mode");
	}
	return @names;
}

sub toString {
	my ($self) = @_;
	my @binNames = $self->getBinNames('basic');
	my $binID = 0;
	my @binCounts = $self->getBinCounts();
	if ($self->usePercent()) {
		map { $_ ? $_ = sprintf("%4.1f %%", $_ * 100) : undef } @binCounts;
	}
	foreach my $binCount (@binCounts) {
		print "$binNames[$binID] $binCount\n" if (defined $binCount);
		$binID++;
	}
}

sub toGnuplotString {
	my ($self) = @_;
	my @binNames = $self->getBinNames('gnuplot');
	my $output = '
set style fill solid 0.25 border -1
';#set xtics (';
#	$output .= join ", ", map { "'$_' $_" } grep { defined } @binNames;
#	$output .= ")\n";
	if ($self->usePercent()) {
		$output .= "set ylabel '%' rotate by 0\n";
		#$output .= "set yrange [0:100]\n";
	}
	$output .= "plot '-' with " . ($self->accumulateCounts() ? "lines" : "boxes") . " lt 1\n";
	my @binCount = $self->getBinCounts();
	while (!defined $binCount[0]) {
		shift @binCount;
	}
	@binCount = map { $_ ? $_ : 0 } @binCount;
	if ($self->accumulateCounts()) {
		my $acc = 0;
		@binCount = map { $acc += $_; $acc } @binCount;
	}
	my $binName = 0;
	foreach my $binCount (@binCount) {
			$binCount *= 100 if ($self->usePercent());
			$binName = @binNames ? shift @binNames : $binName + $self->{width} * 2;
			$output .= "$binName $binCount\n";
	}
	$output .= "e\n";
	return $output;
}

sub showInGnuplot {
	my ($self) = @_;
	my $gnuplotcmd = $self->toGnuplotString();
	print STDERR "plotting command is: \n$gnuplotcmd\n";
	`echo \"$gnuplotcmd\" | gnuplot -p`;
}

use File::Temp qw/ :mktemp /;

# returns the name of a newly created temporary file with the plot
sub getTempImage {
	my ($self, $type, $options) = @_;
	my $gnuplotcmd = "set terminal $type $options\nset key off\n" . $self->toGnuplotString();
	my $file = mktemp("/tmp/gpXXXX") . ".$type";
	`echo \"$gnuplotcmd\" | gnuplot > $file`;
	return $file;
}

return 1;

__END__


#nice function to plot normal distributions:
#invsqrt2pi = 0.398942280401433
#normal(x,mu,sigma)=sigma<=0?1/0:invsqrt2pi/sigma*exp(-0.5*((x-mu)/sigma)**2)

	
