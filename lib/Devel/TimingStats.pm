package Devel::TimingStats;

use Moose;
use Time::HiRes qw/gettimeofday tv_interval/;
use Text::SimpleTable ();
use Term::Size::Guess;
use Tree::Simple qw/use_weak_refs/;
use Tree::Simple::Visitor::FindByUID;

use namespace::clean -except => 'meta';

our $VERSION = '1.00000';

has enable => (is => 'rw', required => 1, default => sub{ 1 });
has tree => (
             is => 'ro',
             required => 1,
             handles => [qw/ accept traverse /],
             lazy_build => 1,
            );
has stack => (
              is => 'ro',
              required => 1,
              lazy_build => 1,
             );

sub _build_tree {
    return Tree::Simple->new({t => [gettimeofday]});
}

sub _build_stack {
    return [ shift->tree ];
}

sub reset {
    my $self = shift;

    $self->clear_tree;
    $self->clear_stack;
}

sub profile {
    my $self = shift;

    return unless $self->enable;

    my %params;
    if (@_ <= 1) {
        $params{comment} = shift || "";
    }
    elsif (@_ % 2 != 0) {
        die "profile() requires a single comment parameter or a list of name-value pairs; found "
            . (scalar @_) . " values: " . join(", ", @_);
    }
    else {
        (%params) = @_;
        $params{comment} ||= "";
    }

    my $parent;
    my $prev;
    my $t = [ gettimeofday ];
    my $stack = $self->stack;

    if ($params{end}) {
        # parent is on stack; search for matching block and splice out
        for (my $i = $#{$stack}; $i > 0; $i--) {
            if ($stack->[$i]->getNodeValue->{action} eq $params{end}) {
                my ($node) = splice(@{$stack}, $i, 1);
                # Adjust elapsed on partner node
                my $v = $node->getNodeValue;
                $v->{elapsed} =  tv_interval($v->{t}, $t);
                return $node->getUID;
            }
        }
    # if partner not found, fall through to treat as non-closing call
    }
    if ($params{parent}) {
        # parent is explicitly defined
        $prev = $parent = $self->_get_uid($params{parent});
    }
    if (!$parent) {
        # Find previous node, which is either previous sibling or parent, for ref time.
        $prev = $parent = $stack->[-1] or return undef;
        my $n = $parent->getChildCount;
        $prev = $parent->getChild($n - 1) if $n > 0;
    }

    my $node = Tree::Simple->new({
        action  => $params{begin} || "",
        t => $t,
        elapsed => tv_interval($prev->getNodeValue->{t}, $t),
        comment => $params{comment},
    });
    $node->setUID($params{uid}) if $params{uid};

    $parent->addChild($node);
    push(@{$stack}, $node) if $params{begin};

    return $node->getUID;
}

sub created {
    return @{ shift->tree->getNodeValue->{t} };
}

sub elapsed {
    return tv_interval(shift->tree->getNodeValue->{t});
}

sub report {
    my $self = shift;

    my $column_width = Term::Size::Guess::chars - 9 - 13;
    my $t = Text::SimpleTable->new( [ $column_width, 'Action' ], [ 9, 'Time' ] );
    my @results;
    $self->traverse(
                sub {
                my $action = shift;
                my $stat   = $action->getNodeValue;
                my @r = ( $action->getDepth,
                      ($stat->{action} || "") .
                      ($stat->{action} && $stat->{comment} ? " " : "") . ($stat->{comment} ? '- ' . $stat->{comment} : ""),
                      $stat->{elapsed},
                      $stat->{action} ? 1 : 0,
                      );
                # Trim down any times >= 10 to avoid ugly Text::Simple line wrapping
                my $elapsed = substr(sprintf("%f", $stat->{elapsed}), 0, 8) . "s";
                $t->row( ( q{ } x $r[0] ) . $r[1],
                     defined $r[2] ? $elapsed : '??');
                push(@results, \@r);
                }
            );
    return wantarray ? @results : $t->draw;
}

sub _get_uid {
    my ($self, $uid) = @_;

    my $visitor = Tree::Simple::Visitor::FindByUID->new;
    $visitor->searchForUID($uid);
    $self->accept($visitor);
    return $visitor->getResult;
}

sub addChild {
    my $self = shift;
    my $node = $_[ 0 ];

    my $stat = $node->getNodeValue;

    # do we need to fake $stat->{ t } ?
    if( $stat->{ elapsed } ) {
        # remove the "s" from elapsed time
        $stat->{ elapsed } =~ s{s$}{};
    }

    $self->tree->addChild( @_ );
}

sub setNodeValue {
    my $self = shift;
    my $stat = $_[ 0 ];

    # do we need to fake $stat->{ t } ?
    if( $stat->{ elapsed } ) {
        # remove the "s" from elapsed time
        $stat->{ elapsed } =~ s{s$}{};
    }

    $self->tree->setNodeValue( @_ );
}

sub getNodeValue {
    my $self = shift;
    $self->tree->getNodeValue( @_ )->{ t };
}

__PACKAGE__->meta->make_immutable();

1;

__END__

=for stopwords addChild getNodeValue mysub rollup setNodeValue

=head1 NAME

Devel::TimingStats - Collect and Report Timing Statistics (much like Catalyst::Stats)

=head1 SYNOPSIS

    $stats = $c->stats;
    $stats->enable(1);
    $stats->profile($comment);
    $stats->profile(begin => $block_name, comment =>$comment);
    $stats->profile(end => $block_name);
    $elapsed = $stats->elapsed;
    $report = $stats->report;

=head1 DESCRIPTION

This module provides timing stats collection functionality for your
application.

You can add profiling points into your own code to get deeper insight. Typical
usage might be like this:

    my $stats = Devel::TimingStats->new;

    $stats->profile(begin => "foo");
    # code goes here
    ...
    $stats->profile("starting critical bit");
    # code here too
    ...
    $stats->profile("completed first part of critical bit");
    # more code
    ...
    $stats->profile("completed second part of critical bit");
    # more code
    ...
    $stats->profile(end => "foo");
    ...
    $stats->profile(begin => "bar");
    # more code
    $stats->profile(end => "bar");

The reported timings for the above example might look something like this:

  .----------------------------------------------------------------+-----------.
  | Action                                                         | Time      |
  +----------------------------------------------------------------+-----------+
  | foo                                                            | 0.555555s |
  |  - starting critical bit                                       | 0.111111s |
  |  - completed first part of critical bit                        | 0.333333s |
  |  - completed second part of critical bit                       | 0.111000s |
  | bar                                                            | 0.222222s |
  '----------------------------------------------------------------+-----------'

which means "foo" took 0.555555s overall, it took 0.111111s to reach the
critical bit, the first part of the critical bit took 0.333333s, and the second
part 0.111s, then "bar" took 0.222222s.


=head1 METHODS

=head2 new

Constructor.

    $stats = Devel::TimingStats->new;

=head2 enable

    $stats->enable(0);
    $stats->enable(1);

Enable or disable stats collection.  By default, stats are enabled after object
creation.

=head2 reset

    $stats->reset;

Clears all stats and sets L</created> to the current time.

=head2 profile

    $stats->profile($comment);
    $stats->profile(begin => $block_name, comment =>$comment);
    $stats->profile(end => $block_name);

Marks a profiling point.  These can appear in pairs, to time the block of code
between the begin/end pairs, or by themselves, in which case the time of
execution to the previous profiling point will be reported.

The argument may be either a single comment string or a list of name-value
pairs.  Thus the following are equivalent:

    $stats->profile($comment);
    $stats->profile(comment => $comment);

The following key names/values may be used:

=over 4

=item * begin => ACTION

Marks the beginning of a block.  The value is used in the description in the
timing report.

=item * end => ACTION

Marks the end of the block.  The name given must match a previous 'begin'.
Correct nesting is recommended, although this module is tolerant of blocks that
are not correctly nested, and the reported timings should accurately reflect the
time taken to execute the block whether properly nested or not.

=item * comment => COMMENT

Comment string; use this to describe the profiling point.  It is combined with
the block action (if any) in the timing report description field.

=item * uid => UID

Assign a predefined unique ID.  This is useful if, for whatever reason, you wish
to relate a profiling point to a different parent than in the natural execution
sequence.

=item * parent => UID

Explicitly relate the profiling point back to the parent with the specified UID.
The profiling point will be ignored if the UID has not been previously defined.

=back

Returns the UID of the current point in the profile tree.  The UID is
automatically assigned if not explicitly given.

=head2 created

    ($seconds, $microseconds) = $stats->created;

Returns the time the object was created or L</reset> called, in C<gettimeofday>
format, with Unix epoch seconds followed by microseconds.

=head2 elapsed

    $elapsed = $stats->elapsed

Get the total elapsed time (in seconds) since the object was created.

=head2 report

    print $stats->report ."\n";
    $report = $stats->report;
    @report = $stats->report;

In scalar context, generates a textual report.  In array context, returns the
array of results where each row comprises:

    [ depth, description, time, rollup ]

The depth is the calling stack level of the profiling point.

The description is a combination of the block name and comment.

The time reported for each block is the total execution time for the block, and
the time associated with each intermediate profiling point is the elapsed time
from the previous profiling point.

The 'rollup' flag indicates whether the reported time is the rolled up time for
the block, or the elapsed time from the previous profiling point.

=head1 COMPATIBILITY METHODS

Some components might expect the stats object to be a regular Tree::Simple object.
We've added some compatibility methods to handle this scenario:

=head2 accept

=head2 addChild

=head2 setNodeValue

=head2 getNodeValue

=head2 traverse

=head1 SEE ALSO

L<Catalyst::Stats>

=head1 AUTHORS

Catalyst Contributors, see Catalyst.pm

=head1 COPYRIGHT

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
