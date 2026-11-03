package Perl::Critic::Policy::ControlStructures::ProhibitMutatingListFunctionsStricter;

# ABSTRACT: Do not change $_ in a list function, directly or through a sub that the block calls.

use strict;
use warnings FATAL => 'all';
use 5.014;
use re '/aa';
use Readonly;
use List::Util                 qw{any first};
use Scalar::Util               ();
use Perl::Critic::Distribution ();
use Perl::Critic::Document     ();
use Perl::Critic::Utils        qw{ :severities is_function_call first_arg };

use parent qw{Perl::Critic::Policy::ControlStructures::ProhibitMutatingListFunctions};

=head1 DESCRIPTION

The block of C<map>, C<grep>, C<first> and the other list functions sees each
element of its list as C<$_>, and C<$_> is an alias: a change to C<$_> changes
the list.  C<ControlStructures::ProhibitMutatingListFunctions> reports a block
that changes C<$_>.  It cannot see a block that calls a sub that changes it:

    sub trim { s/\s+\z//; return }
    ...
    my @tidy = map { trim(); $_ } @lines;    # reported: @lines is trimmed too

This policy reports everything that the core policy reports, and that call.
Enable it in place of the core policy, not beside it, or each direct case is
reported twice.

=head2 What changes $_

The definition of the core policy, which this policy subclasses: an assignment
to C<$_>, a substitution or a transliteration that binds to it without C</r>,
C<chop>, C<chomp>, and a four-argument C<substr> of it.  The C<list_funcs> and
C<add_list_funcs> parameters of the core policy work here too.

One addition: C<chomp;> and C<chop;>, written with the semicolon that ends their
statement.  The core policy takes that semicolon for an argument, and misses
them.

=head2 A sub that changes $_

A sub whose body changes C<$_>, by the definition above, and does not make
C<$_> its own first.  These do not count, because there C<$_> is not the
caller's:

=over

=item * the body of a C<foreach> with no loop variable, and a statement with a
postfix C<for>,

=item * the block of a list function inside the sub,

=item * an inner sub, named or anonymous.

=back

A sub that declares C<local $_> anywhere does not count at all.

The sub can be in the same file, by its name.  It can be in another file of the
same distribution, which L<Perl::Critic::Distribution> reads: a package sub,
called by its full name, or by its bare name from the same package.  A bare call
from another package is left alone, because what that package imports is not
known.  A method call is left alone, because the method that runs can be another
sub of the same name.

Only one call deep: a sub that calls a sub that changes C<$_> is not reported.

=head2 A local $_ in the block

A C<local $_> at the top level of the block gives the block a C<$_> of its
own.  A sub that is called after it changes that copy, and not the list, so
those calls do not count.  Say it before the first call:

    my @tidy = map { local ($_) = $_; trim(); $_ } @lines;    # OK!

A call in the C<local> statement itself still counts:
C<local ($_) = trim()> calls C<trim> before C<$_> is localized.  So does a
call before it, and a C<local $_> inside an inner block covers nothing.

C<local $_;> and C<local $_ = $_;> work as well.  But the second is reported
as a change to C<$_> by the core policy, so by this one, and
C<Variables::RequireInitializationForLocalVars> reports the first.

A change to C<$_> in the block itself, after the C<local>, is still reported.
It is the core policy's test, and that test does not read the C<local>.

=head1 CONFIGURATION

The C<list_funcs> and C<add_list_funcs> of
L<Perl::Critic::Policy::ControlStructures::ProhibitMutatingListFunctions>.

=cut

Readonly::Scalar my $CORE        => 'Perl::Critic::Policy::ControlStructures::ProhibitMutatingListFunctions';
Readonly::Scalar my $DESC        => q{Don't modify $_ in list functions};
Readonly::Scalar my $DESC_CALLED => q{A sub that modifies $_ is called in a list function};
Readonly::Scalar my $EXPL        => [114];

Readonly::Hash my %CHOPS         => map { $_ => 1 } qw{ chop chomp };
Readonly::Hash my %LOOP          => map { $_ => 1 } qw{ for foreach };
Readonly::Hash my %LIST_FUNCTION => map { $_ => 1 } split m/\s+/xs, ( first { $_->{name} eq 'list_funcs' } $CORE->supported_parameters )->{default_string};

# Change it when what the collector returns changes shape.
Readonly::Scalar my $DATA_FORMAT => 1;

# The definition of what changes $_ is the core policy's, in a sub that it does
# not export.  Said at load, not at the first file.
my $core_side_effect = $CORE->can('_has_topic_side_effect') or die "$CORE has no _has_topic_side_effect, which this policy reuses\n";

# The part of a name after its last ::, which is all of a bare name.
my $bare_name = sub {
    my ($name) = @_;
    my $at     = rindex $name, '::';
    return $at < 0 ? $name : substr $name, $at + 2;
};

=head2 METHODS

=head3 supported_parameters

=head3 default_severity

=head3 default_themes

=head3 applies_to

Those of the core policy.

=head3 initialize_if_enabled

What the core policy does, and registers what this policy needs from each file
of a distribution with L<Perl::Critic::Distribution>: the package subs that
change C<$_>.  A lexical sub is left out, because no other file can call it.

=cut

sub initialize_if_enabled {
    my ( $self, $config ) = @_;

    Perl::Critic::Distribution->register(
        name    => __PACKAGE__,
        version => join( q{/}, $DATA_FORMAT, $CORE->VERSION, Perl::Critic::Distribution->stamp(__FILE__) // q{} ),
        collect => sub {
            my ($ppi) = @_;
            my $doc = Perl::Critic::Document->new( -source => $ppi );
            return { mutating_subs => [ map { $_->[1] } grep { !$_->[0]->type } mutating_subs_in( $doc, packages_in($doc) ) ] };
        },
    );
    return $self->SUPER::initialize_if_enabled($config);
}

=head3 violates

=cut

sub violates {
    my ( $self, $elem, $doc ) = @_;

    my @core = $self->SUPER::violates( $elem, $doc );
    return @core if @core;

    # The list functions as the core policy configured them, from its
    # list_funcs and add_list_funcs.
    return if !$self->{_all_list_funcs}{$elem} || !is_function_call($elem);
    my $block = first_arg($elem);
    return if !$block || !$block->isa('PPI::Structure::Block');

    return $self->violation( $DESC, $EXPL, $elem ) if chops_topic($block);

    my $known = $self->known_subs($doc);
    foreach my $word ( map { @{ $_->find('PPI::Token::Word') || [] } } aliased_statements($block) ) {
        my $name = $word->content;
        next if !$known->{local}{$name} && !$known->{bare}{ $bare_name->($name) };
        next if !is_function_call($word);

        my $full = index( $name, '::' ) >= 0 ? $name : package_at( $word, $known->{packages} ) . "::$name";
        return $self->violation( $DESC_CALLED, $EXPL, $elem ) if $known->{local}{$name} || $known->{remote}{$full};
    }
    return;
}

=head3 known_subs

The subs that change C<$_>, for a document: those of the document by their
name, and those of the rest of its distribution by their full name.  Worked
out once for each document, since C<violates> is called once for each word.

=cut

sub known_subs {
    my ( $self, $doc ) = @_;

    # The document is held, not just its address, so the address cannot be
    # handed to the next document while this still answers for it.
    my $last = $self->{_known};
    return $last->{subs} if $last && Scalar::Util::refaddr( $last->{doc} ) == Scalar::Util::refaddr($doc);

    my $packages = packages_in($doc);
    my %subs     = ( packages => $packages, local => { map { ( $_->[0]->name => 1 ) } mutating_subs_in( $doc, $packages ) } );

    my $filename = $doc->filename;
    if ( my $dist = defined $filename && Perl::Critic::Distribution->for_file($filename) ) {
        $subs{remote} = {
            map {
                map { ( $_ => 1 ) }
                  @{ $_->{mutating_subs} }
            } values %{ $dist->collected(__PACKAGE__) }
        };
    }
    $subs{bare} = { map { ( $bare_name->($_) => 1 ) } keys %{ $subs{remote} // {} } };

    $self->{_known} = { doc => $doc, subs => \%subs };
    return \%subs;
}

=head2 FUNCTIONS

The steps of C<violates>, for its tests.

=head3 mutating_subs_in

    my @found = mutating_subs_in( $doc, packages_in($doc) );

Each sub of a L<Perl::Critic::Document> that changes C<$_>, as a pair of its
statement and its full name.  L</A sub that changes $_> says which.

=cut

sub mutating_subs_in {
    my ( $doc, $packages ) = @_;

    my @found;
    foreach my $sub ( @{ $doc->find('PPI::Statement::Sub') || [] } ) {
        my $block = $sub->block or next;
        next if any {
            $_->type eq 'local' && any { $_ eq q{$_} }
              $_->variables
        } @{ $block->find('PPI::Statement::Variable') || [] };
        next if !mutates_topic( own_topic_removed($block), $doc );

        my $name = $sub->name;
        push @found, [ $sub, index( $name, '::' ) >= 0 ? $name : package_at( $sub, $packages ) . "::$name" ];
    }
    return @found;
}

=head3 own_topic_removed

A copy of a block without the parts where C<$_> is not the caller's: a
C<foreach> with no loop variable, a statement with a postfix C<for>, the block
of a list function, and an inner sub.

=cut

sub own_topic_removed {
    my ($block) = @_;

    my $copy = $block->clone;
    my @gone;
    foreach my $statement ( @{ $copy->find('PPI::Statement') || [] } ) {
        my @parts = $statement->schildren;
        if ( $statement->isa('PPI::Statement::Compound') ) {
            push @gone, $statement if $LOOP{ $parts[0] // q{} } && $parts[1] && $parts[1]->isa('PPI::Structure::List');
        }
        elsif ( $statement->isa('PPI::Statement::Sub') || any { $_->isa('PPI::Token::Word') && $LOOP{ $_->content } } @parts[ 1 .. $#parts ] ) {
            push @gone, $statement;
        }
    }
    foreach my $word ( @{ $copy->find('PPI::Token::Word') || [] } ) {
        my $next = $word->snext_sibling;
        push @gone, $next if $next && $next->isa('PPI::Structure::Block') && ( $word->content eq 'sub' || $LIST_FUNCTION{ $word->content } );
    }

    # An element inside one that is already gone is gone with it.
    foreach my $elem (@gone) {
        $elem->delete if $elem->top == $copy;
    }
    return $copy;
}

=head3 mutates_topic

Whether a block changes C<$_>: the core policy's test, and C<chomp;> or
C<chop;>, which it misses.  C<$doc> is a L<Perl::Critic::Document>, which the
core test reads a regular expression with.

=cut

sub mutates_topic {
    my ( $block, $doc ) = @_;
    return 1 if $core_side_effect->( $block, $doc );
    return chops_topic($block);
}

=head3 aliased_statements

    my @statements = aliased_statements($block);

The statements at the top level of a block, up to and with the first that
says C<local $_>.  The statements after it run with a C<$_> of the block's
own.

=cut

sub aliased_statements {
    my ($block) = @_;

    my @statements;
    foreach my $statement ( $block->schildren ) {
        push @statements, $statement;
        last if $statement->isa('PPI::Statement::Variable') && $statement->type eq 'local' && any { $_ eq q{$_} } $statement->variables;
    }
    return @statements;
}

=head3 chops_topic

Whether a block calls C<chop> or C<chomp> with no argument, including one that
ends its statement, as C<chomp;>.

=cut

sub chops_topic {
    my ($block) = @_;
    return any {
        my $arg = first_arg($_);
        $CHOPS{ $_->content } && is_function_call($_) && ( !$arg || ( $arg->isa('PPI::Token::Structure') && $arg->content eq q{;} ) )
    } @{ $block->find('PPI::Token::Word') || [] };
}

=head3 packages_in

The C<package> statements of a document, in order, for C<package_at>.  A
document is searched once, and not once for each element.

=cut

sub packages_in {
    my ($ppi) = @_;
    return $ppi->find('PPI::Statement::Package') || [];
}

=head3 package_at

    my $package = package_at( $elem, packages_in($ppi) );

The package that an element is in: that of the block of a C<package NAME { }>
around it, or else that of the last C<package NAME;> before it, or C<main>.

=cut

sub package_at {
    my ( $elem, $packages ) = @_;

    my $package = 'main';
    foreach my $statement (@$packages) {
        my $block = first { $_->isa('PPI::Structure::Block') } $statement->schildren;
        if ($block) {
            for ( my $up = $elem->parent; $up; $up = $up->parent ) {
                return $statement->namespace if $up == $block;
            }
            next;
        }
        my ( $line,    $col )    = @{ $statement->location }[ 0, 1 ];
        my ( $at_line, $at_col ) = @{ $elem->location }[ 0, 1 ];
        $package = $statement->namespace if $line < $at_line || ( $line == $at_line && $col < $at_col );
    }
    return $package;
}

1;
