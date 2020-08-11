package IUEdit;

use strict;
use warnings;

# actually, this package defines EDITS, not IUs. I hope renaming things
# does not cause too much breakage (TIMO20110826)

require "Label.pm";

sub newIUEdit {
	my ($type, $word, $word2) = @_; # word2 only for substitutions!
	die "unknown type of IUEdit for word $word: $type" unless ($type =~ m/(add|revoke|subst)/);
	return bless { type => $type, word => $word, word2 => $word2 };
}

sub toString {
	my $self = shift;
	return ($self->{type} . "(" . $self->{word} . ($self->isSubst() ? ", " . $self->{word2} : '') . ")");
}

sub isSilenceEdit {
	my $self = shift;
	return (Label::isSilentText($self->{word}));
}

sub equals {
	my ($self, $other) = @_;
	return (1 == 0) unless (defined $other); # comparing to null will still work (and result in false)
	return (($self->{type} eq $other->{type}) && ($self->{word} eq $other->{word}));
}

sub isRevoke {
	my $self = shift;
	return ($self->{type} eq 'revoke');
}

sub isAdd {
	my $self = shift;
	return ($self->{type} eq 'add');
}

sub isSubst {
	my $self = shift;
	return ($self->{type} eq 'subst');	
}

# return a list of EDITS! that, when applied to one word list results in the other word list
# $mode further determines behaviour:
# - 'subst': output substitutions instead of add/revoke pairs
sub makeIUEditList {
	my @list1 = @{$_[0]};
	my @list2 = @{$_[1]};
	my $mode = (defined $_[2] ? $_[2] : '');
	my $i = 0;
	$i++ while ((defined $list1[$i]) && (defined $list2[$i]) && ($list1[$i] eq $list2[$i]));
	my @IUEdits = ();
	if ($mode eq 'subst') {
		@list1 = @list1[$i..$#list1];
		@list2 = reverse @list2[$i..$#list2];
		$i = 0;
		while (($i <= $#list1) && ($i <= $#list2)) {
			push @IUEdits, newIUEdit('subst', $list2[$i], $list1[$i]);
			$i++;
		}
		unshift @IUEdits, map { newIUEdit('revoke', $_) } @list2[$i..$#list2];
	} else {
		push @IUEdits, map { newIUEdit('revoke', $_) } reverse @list2[$i..$#list2];
	}
	push @IUEdits, map { newIUEdit('add', $_) } @list1[$i..$#list1];
	return @IUEdits;
}

return 1;
