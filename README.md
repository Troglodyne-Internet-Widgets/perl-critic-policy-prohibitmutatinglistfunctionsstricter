# NAME

Perl::Critic::Policy::ControlStructures::ProhibitMutatingListFunctionsStricter - Do not change $\_ in a list function, directly or through a sub that the block calls.

# VERSION

version 0.002

# DESCRIPTION

The block of `map`, `grep`, `first` and the other list functions sees each
element of its list as `$_`, and `$_` is an alias: a change to `$_` changes
the list.  `ControlStructures::ProhibitMutatingListFunctions` reports a block
that changes `$_`.  It cannot see a block that calls a sub that changes it:

```perl
sub trim { s/\s+\z//; return }
...
my @tidy = map { trim(); $_ } @lines;    # reported: @lines is trimmed too
```

This policy reports everything that the core policy reports, and that call.
Enable it in place of the core policy, not beside it, or each direct case is
reported twice.

Two more reports are off by default.  One is a call in the block to a sub or
method that this policy cannot read, ["Calls that this policy cannot read"](#calls-that-this-policy-cannot-read).
The other is a call in a statement with a postfix `for`, ["A postfix for"](#a-postfix-for).

## What changes $\_

The definition of the core policy, which this policy subclasses: an assignment
to `$_`, a substitution or a transliteration that binds to it without `/r`,
`chop`, `chomp`, and a four-argument `substr` of it.  The `list_funcs` and
`add_list_funcs` parameters of the core policy work here too.

One addition: `chomp;` and `chop;`, written with the semicolon that ends their
statement.  The core policy takes that semicolon for an argument, and misses
them.

## A sub that changes $\_

A sub whose body changes `$_`, by the definition above, and does not make
`$_` its own first.  These do not count, because there `$_` is not the
caller's:

- the body of a `foreach` with no loop variable, and a statement with a
postfix `for`,
- the block of a list function inside the sub,
- an inner sub, named or anonymous.

A sub that declares `local $_` anywhere does not count at all.

The sub can be in the same file, by its name.  It can be in another file of the
same distribution, which [Perl::Critic::Distribution](https://metacpan.org/pod/Perl%3A%3ACritic%3A%3ADistribution) reads: a package sub,
called by its full name, or by its bare name from the same package.  A bare call
from another package is left alone, because what that package imports is not
known.  A method call is left alone, because the method that runs can be another
sub of the same name.

Only one call deep: a sub that calls a sub that changes `$_` is not reported.

## A local $\_ in the block

A `local $_` at the top level of the block gives the block a `$_` of its
own.  A sub that is called after it changes that copy, and not the list, so
those calls do not count.  Say it before the first call:

```perl
my @tidy = map { local ($_) = $_; trim(); $_ } @lines;    # OK!
```

A call in the `local` statement itself still counts:
`local ($_) = trim()` calls `trim` before `$_` is localized.  So does a
call before it, and a `local $_` inside an inner block covers nothing.

`local $_;` and `local $_ = $_;` work as well.  But the second is reported
as a change to `$_` by the core policy, so by this one, and
`Variables::RequireInitializationForLocalVars` reports the first.

A change to `$_` in the block itself, after the `local`, is still reported.
It is the core policy's test, and that test does not read the `local`.

## Calls that this policy cannot read

Off unless `report_unresolved_calls` turns it on.

The rules above can judge only a sub whose body they can read.  A method, a
code reference, or a sub of another distribution can change `$_` just the
same, and the commonest case is a `while (<$fh`)> in some helper of another
module:

```perl
sub first_line {
    my ($file) = @_;
    open my $fh, '<', $file or die "$file: $!";
    while (<$fh>) { last }     # assigns each line to $_
    return $_;
}

my @heads = map { first_line($_) } @files;
# @files now holds the first line of each file, or undef for an empty one
```

With `report_unresolved_calls`, a call in the block of a list function to a
callee that this policy cannot read is reported, before any `local $_` at the
top of the block.  The fix is the one in ["A local $\_ in the block"](#a-local-_-in-the-block):

```perl
my @heads = map { local ($_) = $_; first_line($_) } @files;    # OK!
```

A copy, such as `my $file = $_;`, is no fix, because the callee still writes
`$_`, which is still the element.

These are calls that cannot be read:

```perl
f($_)                     # a sub defined in no file of the distribution
Some::Where::f($_)        # the same, by its full name
$_->is_ok                 # a method
Some::Class->new($_)      # a class method
$o->$name                 # a method by its name in a variable
$code->($_)               # a code reference
&$code  &f                # with an ampersand
PI                        # a constant is a sub too
```

These are not calls that cannot be read:

```perl
lc  CORE::lc($_)          # a builtin
trim()                    # a sub that this policy reads, as above
$_->isa('Some::Class')    # a method named in allow_calls
```

A sub is read when it is found as ["A sub that changes $\_"](#a-sub-that-changes-_) finds it: by its
name in the same file, or by its full name in the distribution.  So a bare call
from another package, whose import is not known, cannot be read, and is
reported.  A method is never read, because the method that runs can be another
sub of the same name.

The list functions are those of `list_funcs` and `add_list_funcs`, and also
these, with or without the package.  On perl 5.44, a callee that assigns to
`$_` changed the elements of each of them:

```
map grep
List::Util       first any all none notall
List::MoreUtils  any all none notall true false firstidx first_index
List::SomeUtils  lastidx last_index firstval first_value lastval
                 last_value firstres first_result lastres last_result
                 onlyidx only_index onlyval only_value onlyres
                 only_result indexes after after_incl before
                 before_incl part insert_after
List::UtilsBy    max_by min_by
```

The core's `list_funcs` names only the full names of the functions of CPAN,
and code calls them by the name that it imported.  With
`report_unresolved_calls`, every report of this policy uses this longer list,
so a change to `$_` in the block of a bare `any` is reported too.
`map EXPR, LIST` and `grep EXPR, LIST` alias `$_` as the block forms do, so
their expression counts as a block.

These do not alias `$_`, and are not list functions here: `sort` and
`reduce`, which set `$a` and `$b`; `apply` of List::MoreUtils, and
`sort_by`, `uniq_by` and the other functions of List::UtilsBy, which give the
block a copy.  `insert_after_string`, which the core lists, takes no block.

In the block, a call does not count where `$_` belongs to another construct:
in the places that ["A sub that changes $\_"](#a-sub-that-changes-_) lists, which are reported on
their own or run later.

## A postfix for

Off unless `report_postfix_for_calls` turns it on.

A statement with a postfix `for` makes `$_` an alias to each element, as a
list function does.  It has no block to put a `local` in, and it cannot name
its variable.  With `report_postfix_for_calls`, the part of the statement
before the `for` is reported when it calls a sub that changes `$_`, by
["A sub that changes $\_"](#a-sub-that-changes-_), or a call that cannot be read, by
["Calls that this policy cannot read"](#calls-that-this-policy-cannot-read).  Write it as a block `for` with a
lexical variable, which does not make `$_` an alias at all:

```perl
$_->load for @documents;                  # reported
for my $doc (@documents) { $doc->load }   # OK!

print for @lines;                         # OK! a builtin
s/\s+\z// for @lines;                     # OK! a change on purpose
sub has_x { return /x/ } has_x() for @x;  # OK! read, and it does not change $_
```

A block `foreach` with no loop variable makes `$_` an alias as well, but it
can name one.  [Perl::Critic::Policy::Variables::ProhibitTopicIterator](https://metacpan.org/pod/Perl%3A%3ACritic%3A%3APolicy%3A%3AVariables%3A%3AProhibitTopicIterator), in
Perl-Critic-Grape, reports each of them, and this policy does not.

## Caveats

A call that perl makes for the code, and that the code does not spell, is not
seen: an overloaded operator, a tied variable, a `DESTROY`, `sort SUBNAME`,
`require` and `do FILE`.

Some lists are not the caller's data, and a call there is reported all the
same.  `keys` returns copies, so a write to `$_` in `for (keys %h)` changes
nothing that lasts.  A write to an element of a literal list, as in
`for (1, 2)`, dies with "Modification of a read-only value attempted".
`values` does return aliases.

# CONFIGURATION

The `list_funcs` and `add_list_funcs` of
[Perl::Critic::Policy::ControlStructures::ProhibitMutatingListFunctions](https://metacpan.org/pod/Perl%3A%3ACritic%3A%3APolicy%3A%3AControlStructures%3A%3AProhibitMutatingListFunctions).

`report_unresolved_calls` reports a call in a list function block that this
policy cannot read, as ["Calls that this policy cannot read"](#calls-that-this-policy-cannot-read) says.  Off by
default.

`report_postfix_for_calls` reports a call in a statement with a postfix
`for`, as ["A postfix for"](#a-postfix-for) says.  Off by default.

`allow_calls` names subs and methods that those two take as not writing `$_`.
A sub is matched as it is written in the call, so `Some::g` does not allow
`g`, and a method by its name alone.  It does not cover a sub that this policy
reads and finds to change `$_`.  The default is `can DOES isa VERSION`, the
methods of `UNIVERSAL`, which perl provides.  A list replaces the default, so
name them too to keep them.

```perl
[ControlStructures::ProhibitMutatingListFunctionsStricter]
report_unresolved_calls  = 1
report_postfix_for_calls = 1
allow_calls = can DOES isa VERSION to_string id name

my @r = map { f($_) } @x;                      # reported
my @r = map { $_->id } @x;                     # OK! in allow_calls
my @r = map { local ($_) = $_; f($_) } @x;     # OK!
$_->save for @objects;                         # reported
for my $object (@objects) { $object->save }    # OK!
```

## METHODS

### supported\_parameters

Those of the core policy, and `report_unresolved_calls`,
`report_postfix_for_calls` and `allow_calls`.

### default\_severity

### default\_themes

### applies\_to

Those of the core policy.

### initialize\_if\_enabled

What the core policy does, and registers what this policy needs from each file
of a distribution with [Perl::Critic::Distribution](https://metacpan.org/pod/Perl%3A%3ACritic%3A%3ADistribution): the package subs that
change `$_`, and all the package subs.  A lexical sub is left out, because no
other file can call it.

### violates

### first\_call

```perl
my $call = $self->first_call( $known, $mutating_too, \@owned, @elements );
```

The first token of `@elements`, or inside them, that calls a sub or method
that this policy cannot read, and is not in `allow_calls`.  With
`$mutating_too`, a call of a sub that changes `$_` counts as well.  Nothing
inside an element of `@owned`, from `topic_owned_in`, counts.  `$known` is
from `known_subs`.

### is\_unsafe\_call

```perl
my $unsafe = $self->is_unsafe_call( $token, $known, $mutating_too );
```

Whether a token calls a sub or method that `first_call` counts: one that this
policy cannot read and `allow_calls` does not name, or, with
`$mutating_too`, a sub that changes `$_`.  A builtin is not a call.

### known\_subs

The subs of a document and of the rest of its distribution, for
`calls_sub_in`: under `mutating` those that change `$_`, and under
`defined` all of them.  Each holds the names in the document under `local`,
the full names under `remote`, and the part after the last `::` of each full
name under `bare`.  Worked out once for each document, since `violates` is
called once for each word.

## FUNCTIONS

The steps of `violates`, for its tests.

### precedes

```perl
my $earlier = precedes( $elem, $mark );
```

Whether `$elem` starts before `$mark` in the document.

### is\_inside

```perl
my $inside = is_inside( $elem, \%by_address );
```

Whether `$elem`, or a node around it, is in a hash keyed by the address of
each element.

### calls\_sub\_in

```perl
my $found = calls_sub_in( $elem, $name, $known->{mutating}, $known->{packages} );
```

Whether a call of `$name` at `$elem` runs a sub of a set from `known_subs`:
one of the document by its name, or one of the distribution by its full name,
where a bare name is in the package of `$elem`.

### postfix\_statement

The statement of `$elem`, when `$elem` is the `for` or `foreach` of a
postfix `for`.

### subs\_in

```perl
my @found = subs_in( $doc, packages_in($doc) );
```

Each sub of a [Perl::Critic::Document](https://metacpan.org/pod/Perl%3A%3ACritic%3A%3ADocument) that has a body, as a pair of its
statement and its full name.

### mutating\_subs\_in

```perl
my @found = mutating_subs_in( $doc, packages_in($doc) );
```

Each sub of a [Perl::Critic::Document](https://metacpan.org/pod/Perl%3A%3ACritic%3A%3ADocument) that changes `$_`, as a pair of its
statement and its full name.  ["A sub that changes $\_"](#a-sub-that-changes-_) says which.

### own\_topic\_removed

A copy of a block without the parts that `topic_owned_in` finds.

### topic\_owned\_in

```perl
my @owned = topic_owned_in( $node, \%list_functions );
```

The parts of a node where `$_` is not the caller's: a `foreach` with no loop
variable, a statement with a postfix `for`, the block of a list function, and
an inner sub.  The list functions are those of the core's `list_funcs` unless
`\%list_functions` names others.

### mutates\_topic

Whether a block changes `$_`: the core policy's test, and `chomp;` or
`chop;`, which it misses.  `$doc` is a [Perl::Critic::Document](https://metacpan.org/pod/Perl%3A%3ACritic%3A%3ADocument), which the
core test reads a regular expression with.

### aliased\_statements

```perl
my @statements = aliased_statements($block);
```

The statements at the top level of a block, up to and with the first that
says `local $_`.  The statements after it run with a `$_` of the block's
own.

### chops\_topic

Whether a block calls `chop` or `chomp` with no argument, including one that
ends its statement, as `chomp;`.

### packages\_in

The `package` statements of a document, in order, for `package_at`.  A
document is searched once, and not once for each element.

### package\_at

```perl
my $package = package_at( $elem, packages_in($ppi) );
```

The package that an element is in: that of the block of a `package NAME { }`
around it, or else that of the last `package NAME;` before it, or `main`.

# BUGS

Please report any bugs or feature requests on the bugtracker website
[https://github.com/teodesian/perl-critic-policy-prohibitmutatinglistfunctionsstricter/issues](https://github.com/teodesian/perl-critic-policy-prohibitmutatinglistfunctionsstricter/issues)

When submitting a bug or request, please include a test-file or a
patch to an existing test-file that illustrates the bug or desired
feature.

# AUTHORS

Current Maintainers:

- George S. Baugh <george@troglodyne.net>

# CONTRIBUTOR

troglodyne-bot <morpheus@troglodyne.net>

# COPYRIGHT AND LICENSE

Copyright (c) 2026 Troglodyne LLC

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
