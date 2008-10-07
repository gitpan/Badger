package Badger;

use 5.008;
use Carp;
use Badger::Hub;
use Badger::Class
    debug     => 0,
    version   => 0.03,
    base      => 'Badger::Base',
    utils     => 'UTILS',
    import    => 'class',
    words     => 'HUB',
    constants => 'PKG',
    exports   => { 
        fail  => \&_export_handler,
    };

our $VERSION = '0.03';
our $HUB     = 'Badger::Hub';
our $AUTOLOAD;

sub _export_handler {
    my ($class, $target, $key, $symbols) = @_;
    croak "You didn't specify a value for the '$key' load option."
        unless @$symbols;
    my $module = join(PKG, $class, $key);
    my $option = shift @$symbols;
    class($module)->load;
    $module->export($target, $option);
    return 1;
}


sub init {
    my ($self, $config) = @_;
    my $hub = $config->{ hub } || $self->class->any_var(HUB);
    unless (ref $hub) {
        UTILS->load_module($hub);
        $hub = $hub->new($config);
    }
    $self->{ hub } = $hub;
    return $self;
}

sub hub {
    my $self = shift;

    if (ref $self) {
        return @_
            ? ($self->{ hub } = shift)
            :  $self->{ hub };
    }
    else {
        return @_
            ? $self->class->var(HUB => shift)
            : $self->class->var(HUB)
    }
}

sub codec {
    shift->hub->codec(@_);
}

sub config {
    my $self = shift;
    return $self->hub->config;
}

# TODO: AUTOLOAD method which polls hub to see what it supports

1;

__END__

=head1 NAME

Badger - Perl Application Programming Toolkit

=head1 SYNOPSIS

    use Badger;
	
    # 1) have more fun
    # 2) get the job done quicker
    # 3) make your code shinier
    # 4) finish work early
    # 5) go skateboarding
    # 6) enjoy life

=head1 WARNING

This is the third version of the Badger Toolkit. It should treated as
I<alpha> quality code, edging towards I<beta>.

The code as it stands is quite possibly packed with fragments of B<FAIL> 
and should be handled as if it could explode when dropped onto a hard
surface from a height.  Everything is still subject to change, but not
without prior warning.  B<Mr T pities the fool that attempts to builds a
production system based on Badger version 0.03 without first evaluating it 
carefully and reading the documentation>.

That said, the code is I<believed> to be reliable and the release of versions
0.01 and 0.02 didn't throw up any major problems. Badger is based on code and
concepts that have been used in production systems for a number of years. Most
of the API is well-defined and unlikely to change significantly in future
versions. However, we're not ruling anything out given that the Badger has
only just been incarnated in his current form.

Despite the fact that Badger is built on (mostly) tried and tested code, the
entire code base has been rebuilt from the ground up, shuffled about, jiggled
around, extended, reduced, recycled and repackaged many times over. As such,
it is inevitable that some things will be broken. You should start out with
the assumption that these modules still contain a handful of careless bugs,
incorrect design decisions, bad implementation choices, and various other
shades of B<FAIL> that need to be corrected. That way you'll be pleasantly
surprised when you find that it actually works as advertised.

The documentation isn't complete, but it's not far off. Most, if not all of
the important core modules are fully documented and believed to be accurate.
Those that aren't fully documented yet should have skeleton documentation
annotated with TODO points.

The test suite is comprehensive but incomplete. It currently contains over a
thousand tests, all of which pass on the system that it has been tested on
(Linux, Mac OSX, Windows XP).

Having read this warning in detail (as I'm sure you have), you will now
understand why caution is advised before embarking on a major project
based around Badger.  You would be well advised to discuss it on the 
Badger mailing list first to make sure you've got the latest information.

So, with that warning nailed firmly to the door and a "welcome" mat reading
"HEED THE SIGN ON THE DOOR!" lest anyone should miss it, pray come hither 
and let the dance of the happy badgers begin!

=head1 DESCRIPTION

The Badger toolkit is a collection of Perl modules designed to simplify the
process of building object-oriented Perl applications. It provides a set of
I<foundation> classes upon which you can quickly build robust and reliable
systems that are simple, sexy and scalable. All modulo the warnings above.

=head2 Overview

Let's take a quick frolic through the feature list forest to get an idea
what C<Badger> is all about.

=over

=item Foundation classes for OO programming

Badger includes base classes for creating regular objects (L<Badger::Base>),
mixin objects (L<Badger::Mixin>), prototypes/singletons
(L<Badger::Prototype>), factory classes (L<Badger::Factory>) and central
resource hubs (L<Badger::Hub>).

=item Class Metaprogramming

The L<Badger::Class> module employs metaprogramming techniques to simplify
the process of defining object classes.  It provides methods to automate
many of the annoying trivial tasks required to "bootstrap" an object
class: specifying base classes, version numbers, exportable symbols, 
defining constants, loading utility functions from external modules, 
creating accessor and mutator methods, and so on.  There are also methods
that simplify the process of accessing class data (e.g. package variables)
to save all that mucking about in symbols tables.  Some of these methods
will also account for inheritance between related classes, making it much
easier to share default configuration values between related classed,
for example.

L<Badger::Class> can itself be subclassed, allowing you to build your own
metaprogramming modules tailored to your particular needs.

=item Error handling and debugging

Base classes and mixin modules provide functionality for both I<hard errors>
in the form of exception-based error handling and I<soft errors> for declining
requests (e.g. to fetch a resource that doesn't exist) that aren't failures
but require special handling. Methods for debugging (see L<Badger::Debug>) and
raising general warnings are also provided. Generic hooks are provided for
receiving notification of, or implementing custom handling for errors,
warnings and declines. Running alongside this is a generic message formatting
system that allow you to define all error/warning/debug messages in one place
where they can easily be localised (e.g. to a different spoken language) or
customised (e.g. to generate HTML format instead of plain text).

=item Symbol Exporter

Badger implements an object oriented version of the L<Exporter> module
in the form of L<Badger::Exporter>.  It works correctly with respect to
class inheritance (that is, a subclass automatically inherits the exportable
symbols from its base classes) and provides a number of additional features
to simplify the process of defining exportable symbols and adding custom 
import hooks.

=item Standard utilities and constants.

The L<Badger::Utils> module provides a number of simple utility functions. It
also acts as a delegate to various other standard utility modules
(L<Scalar::Util>, L<List::Util>, L<List::MoreUtils>, L<Hash::Util> and
L<Digest::MD5>). L<Badger::Constants> defines various constants used by the
Badger modules and also of general use. Both these modules are designed to be
subclassed so that you can create your own collections of utility functions,
constants, and so on.

=item Filesystem modules

The L<Badger::Filesystem> module and friends provide an object-oriented
interface to a filesystem. Files and directories are represented as
L<Badger::Filesystem::File> and L<Badger::Filesystem::Directory> objects
respectively. As well as being useful for general filesystem manipulation (in
this respect, they are very much like the L<Path::Class> modules), the same
modules can also be used to represent virtual filesystems via the
L<Badger::Filesystem::Virtual> module. This allows you to "mount" a virtual
file system under a particular directory (useful when you're dealing with web
sites to map page URLs, e.g. F</example/page.html>, to the source files, e.g.
F</path/to/example/page.html>). You can also create a virtual file system that
is a composite of several root directories (if you're familiar with the
Template Toolkit then think of the way the C<INCLUDE_PATH> works).

=item Codec modules

Going hand-in-hand with many basic filesystem operations, the codec modules
provide a simple object interface for encoding and decoding data to and 
from any particular format.  The underlying functionality is provided by
existing Perl modules (e.g. L<MIME::Base64>, L<Storable>, L<YAML>, etc).
The codec modules are wrappers that provide a standard interface to these 
various different modules.  It provides both functional and object oriented
interfaces, regardless of how the underlying module works.  It also provides
the relevant hooks that allow codec objects to be composed into pipeline
sequences.

=item Free

Badger is Open Source and "free" in both "free beer" and "free speech" senses
of the word. It's 100% pure Perl and has no external dependencies on any
modules that aren't part of the Perl core. Badger is the base platform for
version 3 of the Template Toolkit (coming RSN) and has portability and ease of
installation as primary goals. Non-core Badger add-on modules can make as much
use of CPAN as they like (something that is usually to be encouraged) but the
Badger core will always be dependency-free to keep it upload-to-your-ISP
friendly.

=back

=head2 What's New?

Version 0.03 features some improvements to the front-end L<Badger> module,
L<Badger::Filesystem>, L<Badger::Class>, and various other cleanups and
bug fixes.

=head2 Background

This section goes into a little more detail into the whys and wherefores
of how the Badger came to be.  You can safely skip onto the next section
if you're in a hurry.

The Badger modules originated in the development of version 3 of the Template
Toolkit. Badger is all the generic bits that form the basis of TT3, not to
mention a few dozen other Perl-based applications (mainly of the web variety)
that I've written over the past few years. The code has evolved and stabilised
over that time and is finally approaching a fit state suitable for human
consumption.

The Badger is a I<toolkit>, not a I<framework>. What's the difference? Good
question. For the purpose of this discussion, a framework is something that
requires you to structure your code in a particular way so as to fit into the
framework. In contrast a toolkit doesn't concern itself too much with how you
write your code (other than some basic principles of structured programming).
Instead it provides a set of tools that you can add into your applications
as you see fit.  

You can use all, some or none of the Badger modules in a project and they'll
play together nicely (convivial play is a central theme of Badger, as is
foraging in the forest for nuts and berries). However, there's no rigid
framework that you have to adjust your mindset to, and very litte "buy-in"
required to start playing Badger games. Use the bits you want and ignore the
rest. Modularity is good. Monolithicity probably isn't even a real word, but
it would be a bad one if it was.

Of course nothing is ever black and white (henceforth known as the "even
badgers have grey fur" principle).  There's a good deal of overlap between 
the two approaches and benefits to be had from them both.  We embrace
a bit of frameworky-ness when it makes good sense, but generally try and
keep things as toolkit-like as possible.

The Badger is dependency free (mind alterating substances notwithstanding).
The basic Badger toolkit requires nothing more than the core modules
distributed with modern versions of Perl (5.8+, maybe 5.6 at a pinch). This is
important (for me at least) because the Badger will be the basis for TT3 and
other forthcoming modules that require minimal dependencies (e.g. for ease of
installation on an ISP or other restricted server). That's not because we
don't love CPAN. Far from it - we luurrrve CPAN. We've borrowed liberally
from CPAN and tried to make as many things inter-play-nicely-able with
existing CPAN modules as possible. But ultimately, one of the goals of Badger
is to provide a self-contained and self-consistent set of modules that all
work the same way, talk the same way, and don't require you to first descend
fifteen levels deep into CPAN dependency hell before you can write a line of
code.

Now, where's that crack pipe?

=head1 MODULES

=head2 Badger

The C<Badger> module is little more than a front-end module.  It doesn't
do much at the moment, other than act as a convenient front door to which
we can nail messages of dire warning.

The ultimate goal is that this will be a I<facade> to the other modules
in the Badger toolkit.  There's a few methods in there at present to 
demonstrate that, but not much.  The plan is to add C<Badger::Facade>
to implement the generic facade pattern that's shared by both L<Badger>
and L<Badger::Hub> (which also needs to be refactored at the same time).
Then L<Badger> will just be a thin sub-class of C<Badger::Facade>.

So, sorry, but there's not much to see here right now.  Please move along.

=head2 Badger::Base

This is a handy base class from which you can create your own object classes.
It's the successor to L<Class::Base> and provides the usual array of methods
for construction, error reporting, debugging and other common functionality.

Here's a teaser:

    package My::Badger::Module;
    use base 'Badger::Base';
    
    sub hello {
        my $self = shift;
        my $name = $self->{ config }->{ name } || 'World';
        return "Hello $name!\n";
    }

    package main;
    
    my $obj = My::Badger::Module->new;
    print $obj->hello;             # Hello World!
    
    my $obj = My::Badger::Module->new( name => 'Badger' );
    print $obj->hello;             # Hello Badger!

=head2 Badger::Prototype

Another handy base class (itself derived from L<Badger::Base>) which allows
you to create prototype objects. To cut a long story short, it means you can
call class methods and have them get automagically applied to a default
object (the prototype). It's a little like a singleton, but slightly more
flexible.

    Badger::Example->method;        # delegated to prototype object

The benefit is that you don't have to worry about providing support in
your methods for both class and object method calls.  Simply call the 
C<prototype()> method and it'll make sure that any class method calls
are "upgraded" to object calls.

    sub example {
        my $self = shift->prototype;
        # $self is *always* an object now
    }

=head2 Badger::Mixin

Yet another handy base class, this time for creating mixin objects that can 
be mixed into other objects, rather like a generous handful of nuts and 
berries being mixed into an ice cream sundae.  Yummy!  Is it tea-time yet?

    package My::Sundae;
    
    use Badger::Class
        mixin => 'My::Nuts My::Berries';

=head2 Badger::Class

This is a class metaprogramming module. Yeah, I know, it sounds like rocket
science doesn't it? Actually it's pretty simple stuff. You know all those
things you have to do when you start writing a new module? Like setting a
version number, specifying a base class, defining some constants (or perhaps
loading them from a shared constants module), declaring any exportable items,
and so on? Well L<Badger::Class> makes all that easy. It provides an object
that has methods for manipulating classes, simple as that.  Never mind all
that nasty mucking about with package variables.  Let the Badger do the 
digging so you can pop off and enjoy a nice game of tennis.  Fifteen Love!

    package My::Badger::Module;
    
    use Badger::Class 'class';
    
    class->version(3.14);
    class->base('Badger::Base');
    class->exports( any => 'foo bar baz' );

These methods can be chained together like this:

    class->version(3.14)
         ->base('Badger::Base')
         ->exports( any => 'foo bar baz' );

You can also specify class metaprogramming options as import hooks.  Like 
this:

    package My::Badger::Module;
    
    use Badger::Class
        version => 3.14,
        base    => 'Badger::Base',
        accessors => 'foo bar',
        mutators  => 'wiz bang',
        constant  => {
            message => 'Hello World',
        },
        exports => {
            any => 'foo wiz',
        };

We like this. We think it makes code easier to read when you set a whole bunch
of class-related items in one place instead of using a dozen different
modules, methods and magic variables to achieve the same thing (we do that for
you behind the scenes). We like Schwern too. He understands the virtue of
I<skimmable> code. He was probably a badger in a former life.

=head2 Badger::Exporter

This exports things. Just like the L<Exporter> module, but better
(approximately 2.718 times better in badger reckoning) because it understands
objects and knows what inheritance means. It provides some nice methods to
declare your exportable items so you don't have to go mucking about with
package variables (we do that for you behind the scenes, but you're welcome to
do it yourself if getting your hands dirty is your thing).

Oh go on then, I'll give you a quick peek.

    package My::Badger::Module;
    use base 'Badger::Exporter';
    
    __PACKAGE__->export_all('foo bar $BAZ');
    __PACKAGE__->export_any('$WIZ $BANG');
    __PACKAGE__->export_tags({
        set1 => 'wam bam',
        set2 => 'ding dong'
    });

As well as mandatory (export_all) and optional (export_any) exportable items,
and the ability to define tag sets of items, the L<Badger::Exporter> module
also makes it easy to define your own export hooks.

    __PACKAGE__->export_hooks({
        one => sub { ... },
        two => sub { ... },
    });

The Badger uses export hooks a lot.  They make life easy.  For example, you
can use the C<exports> hook with L<Badger::Class> and then you don't have
to worry about L<Badger::Exporter> at all.

    package My::Badger::Module;
    
    use Badger::Class
        exports  => {
            all  => 'foo bar $BAZ',
            any  => '$WIZ $BANG',
            tags => {
                set1 => 'wam bam',
                set2 => 'ding dong'
            },
            hooks => {
                one => sub { ... },
                two => sub { ... },
            },
        };

=head2 Badger::Constants

This defines some constants commonly used with the Badger modules.  It also
provides a base class from which you can derive your own constants modules.

    use Badger::Constants 'TRUE FALSE ARRAY';
    
    sub is_this_an_array_ref {
        my $thingy = shift;
        return ref $thingy eq ARRAY ? TRUE : FALSE;
    }

=head2 Badger::Debug

This provides some debugging methods that you can mix into your own modules as
and when required. It supports both compile time and run time debugging
statements ("compile time" in the sense that we can eliminate debugging
statements at compile time so that they don't have any performance impact,
"run time" statements aren't eliminated but can be turned on or off by a
flag). And hey, we can do colour! woot! Thirty Love!

=head2 Badger::Exception

An exception object used by the Badger's inbuilt error handling system.
Try.  Throw.  Catch.  Forty Love!

=head2 Badger::Filesystem

This is a whole badger sub-system dedicated to manipulating files and 
directories in real and virtual filesystems.  But I'm only going to show
you a two-line example in case you get too excited.

    use Badger::Filesystem 'File';
    print File('hello.txt')->text;

Sorry, you'll have to read the L<Badger::Filesystem> documentation for 
further information.

=head2 Badger::Codec

Codecs are for encoding and decoding data between all sorts of different 
formats: Unicode, Base 64, JSON, YAML, Storable, and so on.  Codecs are 
simple wrappers around existing modules that make it trivially easy to 
transcode data, and even allow you compose multiple codecs into a single
codec container.

    use Badger::Codecs
        codec => 'storable+base64';
    
    my $encoded = encode('Hello World');
    # now encoded with Storable and Base64
    print decode($encoded);                 # Hello World

=head2 Badger::Rainbow

Somewhere over the rainbow, way up high, there's a Badger debugging module
that relies on some colour definitions. They live here. One day we'll have a
yellow brick road with birds, flowers and little munchkins running around
singing and dancing. But for now, we'll have to make do with a rainbow with
a pot of strong coffee brewing at the end.

=head2 Badger::Test

It's a test module.  Just like all the other test modules, except that this
one plays nicely with other Badger modules.  And it does colour thanks to 
the Rainbow someone left lying around in our back garden! 

=head2 Badger::Utils

Rather like the kitchen drawer where you put all the things that don't have a
place of their own, the L<Badger::Utils> module provides a resting place for
all the miscellaneous bits and pieces. It defines some basic utility functions
of its own and also acts as a delegate in case you need any of the functions
from L<Scalar::Util>, L<List::Util>, L<List::MoreUtils>, L<Hash::Util> or
L<Digest::MD5>. It can also act as a base class if and when you need to define
your own custom utility collection modules. You are *so* lucky.

Game, set and match: Mr Badger.

=head1 METHODS

Some, but not properly documented yet.  Use the source, Luke.

=head2 hub()

Returns a L<Badger::Hub> object.  This is going to be (re-)factored RSN.

=head2 codec()

Delegates to the L<Badger::Hub> L<codec()|Badger::Hub/codec()> method to 
return a L<Badger::Codec> object.

    my $base64  = Badger->codec('base64');
    my $encoded = $base64->encode($uncoded);
    my $decoded = $base64->decode($encoded);

=head2 config()

Delegates to the L<Badger::Hub> L<codec()|Badger::Hub/codec()> method to 
return a L<Badger::Config> object.  This is still experimental.

=head1 TODO

This module doesn't actually do much at the moment.  It's just the front
door.  Or the frame where the front door is supposed to go.

=head1 AUTHOR

Andy Wardley  E<lt>abw@wardley.orgE<gt>

=head1 COPYRIGHT

Copyright (C) 1996-2008 Andy Wardley.  All Rights Reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<http://badgerpower.com/>

=cut

# Local Variables:
# mode: perl
# perl-indent-level: 4
# indent-tabs-mode: nil
# End:
#
# vim: expandtab shiftwidth=4:
