package Object::Declare;
$Object::Declare::VERSION = '0.07';

use 5.006;
use strict;
use warnings;
use Carp;
use Sub::Override;

sub import {
    my $class       = shift;
    my %args        = ((@_ and ref($_[0])) ? (mapping => $_[0]) : @_) or return; 
    my $from        = caller;
    my $mapping     = $args{mapping} or return;
    my $declarator  = $args{declarator} || 'declare';
    my $copula      = $args{copula} || ['is', 'are'];

    if (ref($mapping) eq 'ARRAY') {
         # rewrite "MyApp::Foo" into simply "foo"
         $mapping = {map {
             my $helper = $_;
             $helper =~ s/.*:://;
             (lc($helper) => $_);
         } @$mapping};
    }

    if (ref($declarator) ne 'ARRAY') {
        $declarator = [$declarator];
    }

    if (ref($copula) ne 'ARRAY') {
        $copula = [$copula];
    }

    no strict 'refs';

    # Install declarator functions into caller's package
    *{"$from\::$_"} = sub (&) {
        unshift @_, ($mapping, $copula);
        goto &_declare;
    } for @$declarator;

    # Establish prototypes (same as "use subs") so Sub::Override can work
    *{"$from\::$_"}     = \&{"$from\::$_"} for keys %$mapping;
    *{"UNIVERSAL::$_"}  = \&{"UNIVERSAL::$_"} for @$copula;
    *{"$_\::AUTOLOAD"}  = \&{"$_\::AUTOLOAD"} for @$copula;
}

sub _declare {
    my ($mapping, $copula, $code) = @_;
    my $from = caller;

    # Table of collected objects.
    my @objects;

    no strict 'refs';
    no warnings 'redefine';
    my $override = Sub::Override->new;

    # in DSL mode; install &AUTOLOAD to collect all unrecognized calls
    # into a katamari structure and analyze it later.
    foreach my $sym (@$copula) {
        $override->replace("UNIVERSAL::$sym" => \&_universal);
        $override->replace("$sym\::AUTOLOAD" => \&_autoload);
    }

    while (my ($sym, $class) = each %$mapping) {
        $override->replace("$from\::$sym" => _make_object($class => \@objects));
    }

    # Let's play katamari!
    $code->();

    # In scalar context, returns hashref; otherwise preserve ordering
    return(wantarray ? @objects : { @objects });
}

# Turn "is some_field" into "some_field is 1"
sub _universal {
    push @_, 1;
    bless(\@_, 'Object::Declare::Katamari');
}

# Handle "some_field is $some_value"
sub _autoload {
    shift;
    my $field = our $AUTOLOAD;
    $field =~ s/.*:://;
    unshift @_, $field;
    bless(\@_, 'Object::Declare::Katamari');
}

# Make a star from the katamari!
sub _make_object {
    my ($class, $schema) = @_;

    return sub {
        my $name = shift;
        push @$schema, $name => scalar $class->new(map { $_->unroll } @_);
    };
}

package Object::Declare::Katamari;

sub unroll {
    my @katamari = @{$_[0]} or return ();
    my $field = shift @katamari or return ();
    my @unrolled;

    unshift @unrolled, pop(@katamari)->unroll
        while ref($katamari[-1]) eq __PACKAGE__; 

    if (@katamari == 1) {
        # single value: "is foo"
        return($field => @katamari, @unrolled);
    }
    else {
        # Multiple values: "are qw( foo bar baz )"
        return($field => \@katamari, @unrolled);
    }
}

1;

__END__

=head1 NAME

Object::Declare - Declarative object constructor

=head1 SYNOPSIS

    use Object::Declare ['MyApp::Column', 'MyApp::Param'];

    my %objects = declare {

    param foo =>
        is immutable,
        valid_values are qw( more values );

    column bar =>
        field1 is 'value',
        field2 is 'some_other_value';

    };

    print $objects{foo}; # a MyApp::Param object
    print $objects{bar}; # a MyApp::Column object

=head1 DESCRIPTION

This module exports one function, C<declare>, for building named
objects with a declarative syntax, similar to how L<Jifty::DBI::Schema>
defines its columns.

In list context, C<declare> returns a list of name/object pairs in the
order of declaration (allowing duplicates), suitable for putting into a hash.
In scalar context, C<declare> returns a hash reference.

Using a flexible C<import> interface, one can change exported helper
functions names (I<declarator>), words to link labels and values together
(I<copula>), and the table of named classes to declare (I<mapping>):

    use Object::Declare
        declarator  => 'declare',       # this is the default
        copula      => ['is', 'are'],   # this is the default
        mapping     => {
            column => 'MyApp::Column',
            param  => 'MyApp::Param',
        };

After the declarator block finishes execution, all helper functions are
removed from the package.  Same-named functions (such as C<&is> and C<&are>)
that existed before the declarator's execution are restored correctly.

=head1 AUTHORS

Audrey Tang E<lt>cpan@audreyt.orgE<gt>

=head1 COPYRIGHT (The "MIT" License)

Copyright 2006 by Audrey Tang <cpan@audreyt.org>.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is fur-
nished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FIT-
NESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE X
CONSORTIUM BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

=cut
