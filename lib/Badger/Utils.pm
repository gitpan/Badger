#========================================================================
#
# Badger::Utils
#
# DESCRIPTION
#   Module implementing various useful utility functions.
#
# AUTHOR
#   Andy Wardley   <abw@wardley.org>
#
#========================================================================

package Badger::Utils;

use strict;
use warnings;
use base 'Badger::Exporter';
use File::Path;
use Scalar::Util qw( blessed );
use Badger::Constants 'HASH PKG DELIMITER BLANK';
use Badger::Debug 
    import  => ':dump',
    default => 0;
use overload;
use constant {
    UTILS  => 'Badger::Utils',
    CLASS  => 0,
    FILE   => 1,
    LOADED => 2,
};

our $VERSION  = 0.01;
#our $DEBUG    = 0 unless defined $DEBUG;
our $ERROR    = '';
our $WARN     = sub { warn @_ };  # for testing - see t/core/utils.t
our $MESSAGES = { };
our $HELPERS  = {       # keep this compact in case we don't need to use it
    'Digest::MD5'       => 'md5 md5_hex md5_base64',
    'Scalar::Util'      => 'blessed dualvar isweak readonly refaddr reftype 
                            tainted weaken isvstring looks_like_number 
                            set_prototype',
    'List::Util'        => 'first max maxstr min minstr reduce shuffle sum',
    'List::MoreUtils'   => 'any all none notall true false firstidx 
                            first_index lastidx last_index insert_after 
                            insert_after_string apply after after_incl before 
                            before_incl indexes firstval first_value lastval 
                            last_value each_array each_arrayref pairwise 
                            natatime mesh zip uniq minmax',
    'Hash::Util'        => 'lock_keys unlock_keys lock_value unlock_value
                            lock_hash unlock_hash hash_seed',
    'Badger::Timestamp' => 'TS Timestamp Now',
    'Badger::Logic'     => 'LOGIC Logic',
};
our $DELEGATES;         # fill this from $HELPERS on demand
our $RANDOM_NAME_LENGTH = 32;
our $TEXT_WRAP_WIDTH    = 78;


__PACKAGE__->export_any(qw(
    UTILS blessed is_object numlike textlike params self_params plural 
    odd_params xprintf dotid random_name camel_case CamelCase wrap
    permute_fragments
));

__PACKAGE__->export_fail(\&_export_fail);

# looks_like_number() is such a mouthful.  I prefer numlike() to go with textlike()
*numlike = \&Scalar::Util::looks_like_number;

# it would be too confusing not to have this alias
*CamelCase = \&camel_case;


sub _export_fail {    
    my ($class, $target, $symbol, $more_symbols) = @_;
    $DELEGATES ||= _expand_helpers($HELPERS);
    my $helper = $DELEGATES->{ $symbol } || return 0;
    require $helper->[FILE] unless $helper->[LOADED];
    $class->export_symbol($target, $symbol, \&{ $helper->[CLASS].PKG.$symbol });
    return 1;
}

sub _expand_helpers {
    # invert { x => 'a b c' } into { a => 'x', b => 'x', c => 'x' }
    my $helpers = shift;
    return {
        map {
            my $name = $_;                      # e.g. Scalar::Util
            my $file = module_file($name);      # e.g. Scalar/Util.pm
            map { $_ => [$name, $file, 0] }     # third item is loaded flag
            split(DELIMITER, $helpers->{ $name })
        }
        keys %$helpers
    }
}
        
sub is_object($$) {
    blessed $_[1] && $_[1]->isa($_[0]);
}

sub textlike($) {
    !  ref $_[0]                        # check if $[0] is a non-reference
    || blessed $_[0]                    # or an object with an overloaded
    && overload::Method($_[0], '""');   # '""' stringification operator
}

sub params {
    # enable $DEBUG to track down calls to params() that pass an odd number 
    # of arguments, typically when the rhs argument returns an empty list, 
    # e.g. $obj->foo( x => this_returns_empty_list() )
    my @args = @_;
    local $SIG{__WARN__} = sub {
        odd_params(@args);
    } if DEBUG;

    @_ && ref $_[0] eq HASH ? shift : { @_ };
}

sub self_params {
    my @args = @_;
    local $SIG{__WARN__} = sub {
        odd_params(@args);
    } if DEBUG;
    
    (shift, @_ && ref $_[0] eq HASH ? shift : { @_ });
}

sub odd_params {
    my $method = (caller(2))[3];
    $WARN->(
        "$method() called with an odd number of arguments: ", 
        join(', ', map { defined $_ ? $_ : '<undef>' } @_),
        "\n"
    );
    my $i = 3;
    while (1) {
        my @info = caller($i);
        last unless @info;
        my ($pkg, $file, $line, $sub) = @info;
        $WARN->(
            sprintf(
                "%4s: Called from %s in %s at line %s\n",
                '#' . ($i++ - 2), $sub, $file, $line
            )
        );
    }
}
    

sub plural {
    my $name = shift;

    if ($name =~ /(ss|sh|ch|x)$/) {
        $name .= 'es';
    }
    elsif ($name =~ s/([^aeiou])y$//) {
        $name .= $1.'ies';
    }
    elsif ($name =~ /([^s\d\W])$/) {
        $name .= 's';
    }
    return $name;
}

sub module_file {
    my $file = shift;
    $file  =~ s[::][/]g;
    $file .= '.pm';
}

sub xprintf {
    my $format = shift;
    my @args   = @_;
    $format =~ 
        s{ < (\d+) 
             (?: :( [#\-\+ ]? [\w\.]+ ) )?
             (?: \| (.*?) )?
           > 
         }
         {   defined $3
                ? _xprintf_ifdef(\@args, $1, $2, $3)
                : '%' . $1 . '$' . ($2 || 's') 
        }egx;
    sprintf($format, @_);
}

sub _xprintf_ifdef {
    my ($args, $n, $format, $text) = @_;
    if (defined $args->[$n-1]) {
        $format = 's' unless defined $format;
        $format = '%' . $n . '$' . $format;
        $text =~ s/\?/$format/g;
        return $text;
    }
    else {
        return '';
    }
}

sub dotid {
    my $text = shift;       # munge $text to canonical lower case and dotted form
    $text =~ s/\W+/./g;     # e.g. Foo::Bar ==> Foo.Bar
    return lc $text;        # e.g. Foo.Bar  ==> foo.bar
}

sub camel_case {
    join(
        BLANK, 
        map {
            map { ucfirst $_ } 
            split '_'
        } 
        @_
    );
}

sub random_name {
    my $length = shift || $RANDOM_NAME_LENGTH;
    my $name   = '';
    require Digest::MD5;
    
    while (length $name < $length) {
        $name .= Digest::MD5::md5_hex(
            time(), rand(), $$, { }, @_
        );
    }
    return substr($name, 0, $length);
}

sub alternates {
    my $text = shift;
    return  [ 
        $text =~ /\|/
            ? split(qr<\|>, $text, -1)  # alternates: (foo|bar) as ['foo', 'bar']
            : ('', $text)               # optional (foo) as (|foo) as ['', 'foo']
    ];
}

sub wrap {
    my $text   = shift;
    my $width  = shift || $TEXT_WRAP_WIDTH;
    my $indent = shift || 0;
    my @words = split(/\s+/, $text);
    my (@lines, @line, $length);
    my $total = 0;
    
    while (@words) {
        $length = length $words[0] || (shift(@words), next);
        if ($total + $length > 74 || $words[0] eq '\n') {
            shift @words if $words[0] eq '\n';
            push(@lines, join(" ", @line));
            @line = ();
            $total = 0;
        }
        else {
            $total += $length + 1;      # account for spaces joining words
            push(@line, shift @words);
        }
    }
    push(@lines, join(" ", @line)) if @line;
    return join(
        "\n" . (' ' x $indent), 
        @lines
    );
}


sub permute_fragments {
    my $input = shift;
    my (@frags, @outputs);

    # Lookup all the (a) optional fragments and (a|b|c) alternate fragments
    # replace them with %s.  This gives us an sprintf format that we can later
    # user to re-fill the fragment slots.  Meanwhile create a list of @frags
    # with each item corresponding to a (...) fragment which is represented 
    # by a list reference containing the alternates.  e.g. the input
    # string 'Fo(o|p) Ba(r|z)' generates @frags as ( ['o','p'], ['r','z'] ),
    # leaving $input set to 'Fo%s Ba%s'.  We treat (foo) as sugar for (|foo), 
    # so that 'Template(X)' is permuted as ('Template', 'TemplateX'), for 
    # example.
    
    $input =~ 
        s/ 
            \( ( .*? ) \) 
        /
            push(@frags, alternates($1));
            '%s';
        /gex;

    # If any of the fragments have multiple values then $format will still contain
    # one or more '%s' tokens and @frags will have the same number of list refs
    # in it, one for each fragment.  To iterate across all permutations of the 
    # fragment values, we calculate the product P of the sizes of all the lists in 
    # @frags and loop from 0 to P-1.  Then we use a div and a mod to get the right 
    # value for each fragment, for each iteration.  We divide $n by the product of
    # all fragment lists to the right of the current fragment and mod it by the size
    # of the current fragment list.  It's effectively counting with a different base
    # for each column. e.g. consider 3 fragments with 7, 3, and 5 values respectively
    #   [7]            [3]           [5]         P = 7 * 3 * 5 = 105
    #   [n / 15 % 7]   [n / 5 % 3]   [n % 5]     for 0 < n < P 

    if (@frags) {
        my $product = 1; $product *= @$_ for @frags;
        for (my $n = 0; $n < $product; $n++) {
            my $divisor = 1;
            my @args = reverse map {
                my $item = $_->[ $n / $divisor % @$_ ];
                $divisor *= @$_;
                $item;
            } reverse @frags;   # working backwards from right to left
            push(@outputs, sprintf($input, @args));
        }
    }
    else {
        push(@outputs, $input);
    }
    return wantarray
        ?  @outputs
        : \@outputs;
}

sub _debug {
    print STDERR @_;
}

1;

__END__

=head1 NAME

Badger::Utils - various utility functions

=head1 SYNOPSIS

    use Badger::Utils 'blessed params';
    
    sub example {
        my $self   = shift;
        my $params = params(@_);
        
        if (blessed $self) {
            print "self is blessed\n";
        }
    }
    

=head1 DESCRIPTION

This module implements a number of utility functions.  It also provides 
access to all of the utility functions in L<Scalar::Util>, L<List::Util>,
L<List::MoreUtils>, L<Hash::Util> and L<Digest::MD5> as a convenience.

    use Badger::Utils 'blessed reftype first max any all lock_hash md5_hex';

The single line of code shown here will import C<blessed> and C<reftype> from
L<Scalar::Util>, C<first> and C<max> from L<List::Util>, C<any> and C<all>
from L<List::Util>, C<lock_hash> from L<Hash::Util>, and C<md5_hex> from 
L<Digest::MD5>.

These modules are loaded on demand so there's no overhead incurred if you
don't use them (other than a lookup table so we know where to find them).

=head1 EXPORTABLE FUNCTIONS

C<Badger::Utils> can automatically load and export functions defined in the
L<Scalar::Util>, L<List::Util>, L<List::MoreUtils>, L<Hash::Util> and
L<Digest::MD5> Perl modules.

It also does the same for functions and constants defined in the Badger 
modules L<Badger::Timestamp> (L<TS|Badger::Timestamp/TS>,
L<Timestamp()|Badger::Timestamp/Timestamp()> and
L<Now()|Badger::Timestamp/Now()>) and L<Badger::Logic>
(L<LOGIC|Badger::Logic/LOGIC> and L<Logic()|Badger::Logic/Logic()>).

For example:

    use Badger::Utils 'Now';
    print Now->year;            # prints the current year

The following exportable functions are also defined in C<Badger::Utils>

=head2 UTILS

Exports a C<UTILS> constant which contains the name of the C<Badger::Utils>
class.  

=head2 is_object($class,$object)

Returns true if the C<$object> is a blessed reference which isa C<$class>.

    use Badger::Filesystem 'FS';
    use Badger::Utils 'is_object';
    
    if (is_object( FS => $object )) {       # FS == Badger::Filesystem
        print $object, ' isa ', FS, "\n";
    }

=head2 textlike($item)

Returns true if C<$item> is a non-reference scalar or an object that
has an overloaded stringification operator.

    use Badger::Filesystem 'File';
    use Badger::Utils 'textlike';
    
    # Badger::Filesystem::File objects have overloaded string operator
    my $file = File('example.txt'); 
    print $file;                                # example.txt
    print textlike $file ? 'ok' : 'not ok';     # ok

=head2 numlike($item)

This is an alias to the C<looks_like_number()> function defined in 
L<Scalar::Util>.  

=head2 params(@args)

Method to coerce a list of named parameters to a hash array reference.  If the
first argument is a reference to a hash array then it is returned.  Otherwise
the arguments are folded into a hash reference.

    use Badger::Utils 'params';
    
    params({ a => 10 });            # { a => 10 }
    params( a => 10 );              # { a => 10 }

Pro Tip: If you're getting warnings about an "Odd number of elements in
anonymous hash" then try enabling debugging in C<Badger::Utils>. To do this,
add the following to the start of your program before you've loaded
C<Badger::Utils>:

    use Badger::Debug
        modules => 'Badger::Utils'

When debugging is enabled in C<Badger::Utils> you'll get a full stack 
backtrace showing you where the subroutine was called from.  e.g.

    Badger::Utils::self_params() called with an odd number of arguments: <undef>
    #1: Called from Foo::bar in /path/to/Foo/Bar.pm at line 210
    #2: Called from Wam::bam in /path/to/Wam/Bam.pm at line 420
    #3: Called from main in /path/to/your/script.pl at line 217

=head2 self_params(@args)

Similar to L<params()> but also expects a C<$self> reference at the start of
the argument list.

    use Badger::Utils 'self_params';
    
    sub example {
        my ($self, $params) = self_params(@_);
        # do something...
    }

If you enable debugging in C<Badger::Utils> then you'll get a stack backtrace
in the event of an odd number of parameters being passed to this function.
See L<params()> for further details.

=head2 odd_params(@_)

This is an internal function used by L<params()> and L<self_params()> to 
report any attempt to pass an odd number of arguments to either of them.
It can be enabled by setting C<$Badger::Utils::DEBUG> to a true value.

    use Badger::Utils 'params';
    $Badger::Utils::DEBUG = 1;
    
    my $hash = params( foo => 10, 20 );    # oops!

The above code will raise a warning showing the arguments passed and a 
stack backtrace, allowing you to easily track down and fix the offending
code.  Apart from obvious typos like the above, this is most likely to 
happen if you call a function or methods that returns an empty list.  e.g.

    params(
        foo => 10,
        bar => get_the_bar_value(),
    );

If C<get_the_bar_value()> returns an empty list then you'll end up with an
odd number of elements being passed to C<params()>.  You can correct this
by providing C<undef> as an alternative value.  e.g.

    params(
        foo => 10,
        bar => get_the_bar_value() || undef,
    );

=head2 plural($noun)

The function makes a very naive attempt at pluralising the singular noun word
passed as an argument. 

If the C<$noun> word ends in C<ss>, C<sh>, C<ch> or C<x> then C<es> will be
added to the end of it.

    print plural('class');      # classes
    print plural('hash');       # hashes
    print plural('patch');      # patches 
    print plural('box');        # boxes 

If it ends in C<y> then it will be replaced with C<ies>.

    print plural('party');      # parties

In all other cases, C<s> will be added to the end of the word.

    print plural('device');     # devices

It will fail miserably on many common words.

    print plural('woman');      # womans     FAIL!
    print plural('child');      # childs     FAIL!
    print plural('foot');       # foots      FAIL!

This function should I<only> be used in cases where the singular noun is known
in advance and has a regular form that can be pluralised correctly by the
algorithm described above. For example, the L<Badger::Factory> module allows
you to specify C<$ITEM> and C<$ITEMS> package variable to provide the singular
and plural names of the items that the factory manages.

    our $ITEM  = 'person';
    our $ITEMS = 'people';

If the singular noun is sufficiently regular then the C<$ITEMS> can be 
omitted and the C<plural> function will be used.

    our $ITEM  = 'codec';       # $ITEMS defaults to 'codecs'

In this case we know that C<codec> will pluralise correctly to C<codecs> and
can safely leave C<$ITEMS> undefined.

For more robust pluralisation of English words, you should use the
L<Lingua::EN::Inflect> module by Damian Conway. For further information on the
difficulties of correctly pluralising English, and details of the
implementation of L<Lingua::EN::Inflect>, see Damian's paper "An Algorithmic
Approach to English Pluralization" at
L<http://www.csse.monash.edu.au/~damian/papers/HTML/Plurals.html>

=head2 module_file($name)

Returns the module name passed as an argument as a relative filesystem path
suitable for feeding into C<require()>

    print module_file('My::Module');     # My/Module.pm

=head2 camel_case($string) / CamelCase($string)

Converts a lower case string where words are separated by underscores (e.g.
C<like_this_example>) into CamelCase where each word is capitalised and words
are joined together (e.g. C<LikeThisExample>).

According to Perl convention (and personal preference), we use the lower case
form wherever possible. However, Perl's convention also dictates that module
names should be in CamelCase.  This function performs that conversion.

=head2 wrap($text, $width, $indent)

Simple subroutine to wrap C<$text> to a fixed C<$width>, applying an optional
indent of C<$indent> spaces.  It uses a trivial algorithm which splits the 
text into words, then rejoins them as lines.  It has an additional hack to 
recognise the literal sequence '\n' as a magical word indicating a forced 
newline break.  It must be specified as a separate whitespace delimited word.

    print wrap('Foo \n Bar');

If anyone knows how to make L<Text::Wrap> handle this, or knows of a better
solution then please let me know.

=head2 dotid($text)

The function returns a lower case representation of the text passed as
an argument with all non-word character sequences replaced with dots.

    print dotid('Foo::Bar');            # foo.bar

=head2 xprintf($format,@args)

A wrapper around C<sprintf()> which provides some syntactic sugar for 
embedding positional parameters.

    xprintf('The <2> sat on the <1>', 'mat', 'cat');
    xprintf('The <1> costs <2:%.2f>', 'widget', 11.99);

=head2 random_name($length,@data)

Generates a random name of maximum length C<$length> using any additional 
seeding data passed as C<@args>.  If C<$length> is undefined then the default
value in C<$RANDOM_NAME_LENGTH> (32) is used.

    my $name = random_name();
    my $name = random_name(64);

=head2 permute_fragments($text)

This function permutes any optional or alternate fragments embedded in 
parentheses. For example, C<Badger(X)> is permuted as (C<Badger>, C<BadgerX>)
and C<Badger(X|Y)> is permuted as (C<BadgerX>, C<BadgerY>).

    permute('Badger(X)');           # Badger, BadgerX
    permute('Badger(X|Y)');         # BadgerX, BadgerY

Multiple fragments may be embedded. They are expanded in order from left to
right, with the rightmost fragments changing most often.

    permute('A(1|2):B(3|4)')        # A1:B3, A1:B4, A2:B3, A2:B4

=head2 alternates($text)

This function is used internally by the L<permute_fragments()> function. It
returns a reference to a list containing the alternates split from C<$text>.

    alternates('foo|bar');          # returns ['foo','bar']
    alternates('foo');              # returns ['','bar']

If the C<$text> doesn't contain the C<|> character then it is assumed to be
an optional item.  A list reference is returned containing the empty string
as the first element and the original C<$text> string as the second.

=head1 AUTHOR

Andy Wardley L<http://wardley.org/>

=head1 COPYRIGHT

Copyright (C) 1996-2009 Andy Wardley.  All Rights Reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

# Local Variables:
# mode: perl
# perl-indent-level: 4
# indent-tabs-mode: nil
# End:
#
# vim: expandtab shiftwidth=4:
