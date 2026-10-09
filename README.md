# NAME

Perl::Critic::Policy::ControlStructures::ProhibitMutatingListFunctionsStricter - Do not change $\_ in a list function, directly or through a sub that the block calls.

# VERSION

version 0.001

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

# CONFIGURATION

The `list_funcs` and `add_list_funcs` of
[Perl::Critic::Policy::ControlStructures::ProhibitMutatingListFunctions](https://metacpan.org/pod/Perl%3A%3ACritic%3A%3APolicy%3A%3AControlStructures%3A%3AProhibitMutatingListFunctions).

## METHODS

### supported\_parameters

### default\_severity

### default\_themes

### applies\_to

Those of the core policy.

### initialize\_if\_enabled

What the core policy does, and registers what this policy needs from each file
of a distribution with [Perl::Critic::Distribution](https://metacpan.org/pod/Perl%3A%3ACritic%3A%3ADistribution): the package subs that
change `$_`.  A lexical sub is left out, because no other file can call it.

### violates

### known\_subs

The subs that change `$_`, for a document: those of the document by their
name, and those of the rest of its distribution by their full name.  Worked
out once for each document, since `violates` is called once for each word.

## FUNCTIONS

The steps of `violates`, for its tests.

### mutating\_subs\_in

```perl
my @found = mutating_subs_in( $doc, packages_in($doc) );
```

Each sub of a [Perl::Critic::Document](https://metacpan.org/pod/Perl%3A%3ACritic%3A%3ADocument) that changes `$_`, as a pair of its
statement and its full name.  ["A sub that changes $\_"](#a-sub-that-changes-_) says which.

### own\_topic\_removed

A copy of a block without the parts where `$_` is not the caller's: a
`foreach` with no loop variable, a statement with a postfix `for`, the block
of a list function, and an inner sub.

### mutates\_topic

Whether a block changes `$_`: the core policy's test, and `chomp;` or
`chop;`, which it misses.  `$doc` is a [Perl::Critic::Document](https://metacpan.org/pod/Perl%3A%3ACritic%3A%3ADocument), which the
core test reads a regular expression with.

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
