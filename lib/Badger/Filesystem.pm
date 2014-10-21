#========================================================================
#
# Badger::Filesystem
#
# DESCRIPTION
#   OO representation of a filesystem.
#
# AUTHOR
#   Andy Wardley   <abw@wardley.org>
#
#========================================================================

package Badger::Filesystem;

use File::Spec;
use Cwd 'getcwd';
use Badger::Class
    version   => 0.01,
    debug     => 0,
    base      => 'Badger::Prototype',
    import    => 'class',
    utils     => 'params is_object',
    constants => 'HASH ARRAY TRUE REFS PKG',
    constant  => {
        virtual     => 0,
        NO_FILENAME => 1,
        FILESPEC    => 'File::Spec',
        FINDBIN     => 'FindBin',
        ROOTDIR     =>  File::Spec->rootdir,
        CURDIR      =>  File::Spec->curdir,
        UPDIR       =>  File::Spec->updir,
        FS          => 'Badger::Filesystem',
        VFS         => 'Badger::Filesystem::Virtual',
        PATH        => 'Badger::Filesystem::Path',
        FILE        => 'Badger::Filesystem::File',
        DIRECTORY   => 'Badger::Filesystem::Directory',
        VISITOR     => 'Badger::Filesystem::Visitor',
    },
    exports   => {
        any         => 'FS PATH FILE DIR DIRECTORY cwd getcwd rel2abs abs2rel',
        tags        => { 
            types   => 'Path File Dir Directory Cwd',
            dirs    => 'ROOTDIR UPDIR CURDIR',
        },
        hooks       => {
            VFS     => sub {
                # load VFS module and call its export() method
                class(shift->VFS)->load->pkg->export(shift, shift)
            },
            '$Bin'  => \&_export_findbin_hook,
        },
    },
    messages  => {
        open_failed   => 'Failed to open %s %s: %s',
        delete_failed => 'Failed to delete %s %s: %s',
        bad_volume    => 'Volume mismatch: %s vs %s',
        bad_stat      => 'Nothing known about %s',
    };

use Badger::Filesystem::File;
use Badger::Filesystem::Directory;

#-----------------------------------------------------------------------
# special export hook to make $Bin available from FindBin
#-----------------------------------------------------------------------

sub _export_findbin_hook {
    my ($class, $target) = @_;
    class($class->FINDBIN)->load;
    $class->export_symbol($target, Bin => \$FindBin::Bin);
};


#-----------------------------------------------------------------------
# aliases
#-----------------------------------------------------------------------

*DIR          = \&DIRECTORY;              # constant class name
*Dir          = \&Directory;              # constructor sub
*dir          = \&directory;              # object method
*split_dir    = \&split_directory;        # ...because typing 'directory' 
*join_dir     = \&join_directory;         #    gets tedious quickly
*collapse_dir = \&collapse_directory;     
*dir_exists   = \&directory_exists;
*create_dir   = \&create_directory;
*delete_dir   = \&delete_directory;
*open_dir     = \&open_directory;
*read_dir     = \&read_directory;
*dir_child    = \&directory_child;
*dir_children = \&directory_children;
*mkdir        = \&create_directory;
*rmdir        = \&delete_directory;
*touch        = \&touch_file;


#-----------------------------------------------------------------------
# In this base class definitive paths are the same as absolute paths.
# However, in subclasses (like Badger::Filesystem::Virtual) we want 
# to differentiate between absolute paths in a virtual filesystem
# (e.g. /about/badger.html) and the definitive paths that they map to
# in a real file system (e.g. /home/abw/web/badger/about/badger.html).
# We make the further distinction between definitive paths used for 
# reading or writing, and call the appropriate method to perform any
# virtual -> real mapping before operating on any file or directory.
# But like I said, these are just hooks for subclasses to use if they
# need them.  In the base class, we patch them straight into the plain
# old absolute() method.
#-----------------------------------------------------------------------

*definitive       = \&absolute;
*definitive_read  = \&absolute;
*definitive_write = \&absolute;


#-----------------------------------------------------------------------
# factory subroutines
#-----------------------------------------------------------------------

sub Path      { return @_ ? FS->path(@_)      : PATH      }
sub File      { return @_ ? FS->file(@_)      : FILE      }
sub Directory { return @_ ? FS->directory(@_) : DIRECTORY }
sub Cwd       { FS->directory }


#-----------------------------------------------------------------------
# generated methods
#-----------------------------------------------------------------------

class->methods(
    # define methods for path/root/updir/curdir that access a prototype 
    # object when called as class methods.
    map {
        my $name = $_;      # fresh copy of lexical for binding in closure
        $name => sub {
            $_[0]->prototype->{ $name };
        }
    }
    qw( rootdir updir curdir separator )
);


#-----------------------------------------------------------------------
# constructor methods
#-----------------------------------------------------------------------

sub init {
    my ($self, $config) = @_;

    # TODO: have filsystem "styles", e.g. URI/URL style provides defaults
    # for rootdir, updir, curdir, separator.  But this requires us to bypass
    # File::Spec, so we'll leave it for now.  KISS.
    
    # The tokens used to represent the root directory ('/'), the 
    # parent directory ('..') and current directory ('.') default to
    # constants grokked from File::Spec.  To determine the path separator
    # we have to resort to an ugly hack.  The File::Spec module hard-codes 
    # the path separator in the catdir() method so we have to make a round-
    # trip through catdir() to grok the separator in a cross-platform manner
    $self->{ rootdir   } = $config->{ rootdir   } || ROOTDIR;
    $self->{ updir     } = $config->{ updir     } || UPDIR;
    $self->{ curdir    } = $config->{ curdir    } || CURDIR;
    $self->{ separator } = $config->{ separator } || do {
        my $sep = FILESPEC->catdir(('badger') x 2);
        $sep =~ s/badger//g;
        $sep;
    };

    # flag to indicate if directory scans should return all entries
    $self->{ all_entries } = $config->{ all_entries } || 0;

    # current working can be specified explicitly, otherwise we leave it
    # undefined and let cwd() call getcwd() determine it dynamically
    $self->{ cwd } = $config->{ cwd };
    
    return $self;
}

sub path {
    Path->new( shift->_child_args( path => @_ ) );
}

sub file {
    File->new( shift->_child_args( file => @_ ) );
}

sub directory {
    my $self = shift;
    my $args = $self->_child_args( directory => @_ );
    
    # default directory is the current working directory
    $args->{ path } = $self->cwd
        if exists $args->{ path } && ! defined $args->{ path };
    
    Directory->new($args);
}

sub root {
    my $self = shift->prototype;
    $self->directory($self->{ rootdir });
}

sub cwd {
    my $cwd;
    if (@_) {
        # called as an object or class method
        my $self = shift->prototype;
        # if we have a hard-coded cwd set then return that, otherwise call 
        # getcwd to return the real current working directory.  NOTE: we don't
        # cache the dynamically resolved cwd as it'll change if chdir() is called
        $cwd = $self->{ cwd } || getcwd;
    }
    else {
        # called as a subroutine
        $cwd = getcwd;
    }
    # pass through File::Spec to sanitise path to local filesystem 
    # convention - otherwise we get /forward/slashes on Win32
    FILESPEC->canonpath($cwd);
}


#-----------------------------------------------------------------------
# path manipulation methods
#-----------------------------------------------------------------------

sub merge_paths {
    my ($self, $base, $path) = @_;
    my @p1 = FILESPEC->splitpath($base);
    my @p2 = FILESPEC->splitpath($path);

    # check volumes match
    if (defined $p2[0]) {
        $p1[0] ||= $p2[0];
        return $self->error_msg( bad_volume => $p1[0], $p1[0] )
            unless $p1[0] eq $p2[0];
    }
    shift(@p2);
    my $vol = shift(@p1) || '';
    my $file = pop @p2;
    
    FILESPEC->catpath($vol, FILESPEC->catdir(@p1, @p2), $file);
}
    
sub join_path {
    my $self = shift;
    my @args = map { defined($_) ? $_ : '' } @_[0..2];
    FILESPEC->canonpath( FILESPEC->catpath(@args) );
}

sub join_directory {
    my $self = shift;
    my $dir  = @_ == 1 ? shift : [ @_ ];
    $self->debug("join_dir(", ref $dir eq ARRAY ? '[' . join(', ', @$dir) . ']' : $dir, ")\n") if $DEBUG;
    ref $dir eq ARRAY
        ? FILESPEC->catdir(@$dir)
        : FILESPEC->canonpath($dir);
}

sub split_path {
    my $self  = shift;
    my $path  = $self->join_directory(@_);
    my @split = map { defined($_) ? $_ : '' } FILESPEC->splitpath($path);
    $self->debug("split_path($path) => ", join(', ', @split), "\n") if $DEBUG;
    return wantarray ? @split : \@split;
}

sub split_directory {
    my $self  = shift;
    my $path  = $self->join_directory(@_);
    my @split = FILESPEC->splitdir($path);
    return wantarray ? @split : \@split;
}

sub collapse_directory {
    my $self = shift->prototype;
    my @dirs = $self->split_directory(shift); 
    my ($up, $cur) = @$self{qw( updir curdir )};
    my ($node, @path);
    while (@dirs) {
        $node = shift @dirs;
        if ($node eq $cur) {
            # do nothing
        }
        elsif ($node eq $up) {
            pop @path if @path;
        }
        else {
            push(@path, $node);
        }
    }
    $self->join_directory(@path);
}

sub slash_directory {
    my $self  = shift->prototype;
    my $path  = $self->absolute(shift);
    my $slash = $self->{ slashed } ||= do { 
        my $sep = quotemeta $self->{ separator };
        qr/$sep$/;
    };
    $path .= $self->{ separator } unless $path =~ $slash;
    return $path;
}


#-----------------------------------------------------------------------
# absolute and relative path tests and transmogrifiers
#-----------------------------------------------------------------------

sub is_absolute {
    my $self = shift;
    FILESPEC->file_name_is_absolute($self->join_directory(@_)) ? 1 : 0;
}

sub is_relative {
    shift->is_absolute(@_) ? 0 : 1;
}

sub absolute {
    my $self = shift;
    my $path = $self->join_directory(shift);
    return $path if FILESPEC->file_name_is_absolute($path);
    FILESPEC->catdir(shift || $self->cwd, $path);
}

sub relative {
    my $self = shift;
    FILESPEC->abs2rel($self->join_directory(shift), shift || $self->cwd);
}


#-----------------------------------------------------------------------
# file/directory test methods
#-----------------------------------------------------------------------

sub path_exists {
    my $self = shift;
    return -e $self->definitive_read(shift);
}

sub file_exists {
    my $self = shift;
    return -f $self->definitive_read(shift);
}

sub directory_exists {
    my $self = shift;
    return -d $self->definitive_read(shift);
}

sub stat_path {
    my $self  = shift;
    my @stats = (stat($self->definitive_read(shift)), -r _, -w _, -x _, -o _);

    return $self->error_msg( bad_stat => $self->{ path } )
        unless @stats;

    return wantarray
        ?  @stats
        : \@stats;
}
    

#-----------------------------------------------------------------------
# file manipulation methods
#-----------------------------------------------------------------------

sub create_file {
    my $self = shift;
    my $path = $self->definitive_write(shift);
    unless (-e $path) {
        $self->write_file($path);
    }
    return 1;
}

sub touch_file {
    my $self = shift;
    my $path = $self->definitive_write(shift);
    if (-e $path) {
        my $now = time();
        utime $now, $now, $path;
    } 
    else {
        $self->write_file($path);
    }
}

sub delete_file {
    my $self = shift;
    my $path = $self->definitive_write(shift);
    unlink($path)
        || return $self->error_msg( delete_failed => file => $path => $! );
}

sub open_file {
    my $self = shift;
    my $name = shift;
    my $mode = $_[0] || 'r';            # leave it in @_ for IO::File
    my $path = $mode eq 'r' 
        ? $self->definitive_read($name)
        : $self->definitive_write($name);

    require IO::File;
    $self->debug("about to open file $path (", join(', ', @_), ")\n") if $DEBUG;

    return IO::File->new($path, @_)
        || $self->error_msg( open_failed => file => $path => $! );
}

sub read_file {
    my $self = shift;
    my $fh   = $self->open_file(shift, 'r');
    return wantarray
        ? <$fh>
        : do { local $/ = undef; <$fh> };
}

sub write_file {
    my $self = shift;
    my $fh   = $self->open_file(shift, 'w');
    return $fh unless @_;           # return handle if no args
    print $fh @_;                   # or print args and close
    $fh->close;
    return 1;
}

sub append_file {
    my $self = shift;
    my $fh   = $self->open_file(shift, 'a');
    return $fh unless @_;           # return handle if no args
    print $fh @_;                   # or print args and close
    $fh->close;
    return 1;
}


#-----------------------------------------------------------------------
# directory manipulation methods
#-----------------------------------------------------------------------

sub create_directory { 
    my $self = shift;
    my $path = $self->definitive_write(shift);

    require File::Path;

    eval { 
        local $Carp::CarpLevel = 1;
        File::Path::mkpath($path, @_) 
    } || return $self->error($@);
} 
    
sub delete_directory { 
    my $self = shift;
    my $path = $self->definitive_write(shift);

    require File::Path;
    File::Path::rmtree($path, @_)
}

sub open_directory {
    my $self = shift;
    my $path = $self->definitive_read(shift);

    require IO::Dir;
    $self->debug("Opening directory: $path\n") if $DEBUG;

    return IO::Dir->new($path, @_)
        || $self->error_msg( open_failed => directory => $path => $! );
}

sub read_directory {
    my $self = shift;
    my $dirh = $self->open_directory(shift);
    my $all  = shift;
    my ($path, @paths);
    while (defined ($path = $dirh->read)) {
        push(@paths, $path);
    }
    @paths = FILESPEC->no_upwards(@paths)
        unless $all || ref $self && $self->{ all_entries };

    $dirh->close;
    return wantarray ? @paths : \@paths;
}

sub directory_child {
    my $self = shift;
    my $path = $self->join_directory(@_);
    stat $self->definitive_read($path);
    -d _ ? $self->directory($path) : 
    -f _ ? $self->file($path) :
           $self->path($path);
}
    
sub directory_children {
    my $self  = shift;
    my $dir   = shift;
    my @paths = map { 
        $self->directory_child($dir, $_) 
    }   $self->read_directory($dir, @_);
    return wantarray ? @paths : \@paths;
}

sub visitor {
    my $self  = shift;
    my $vtype = $self->VISITOR;
    class($vtype)->load;
    
    return @_ && is_object($vtype => $_[0])
        ? shift
        : $vtype->new(@_);
}

sub visit {
    shift->root->visit(@_);
}

sub collect {
    shift->visit(@_)->collect;
}

sub accept {
    $_[0]->root->accept($_[1]);
}

#-----------------------------------------------------------------------
# internal methods
#-----------------------------------------------------------------------

sub _child_args {
    my $self = shift->prototype;
    my $type = shift;
    my $args;
    
    if (! @_) {
        $args = { path => undef };
    }
    elsif (@_ == 1) {
        $args = ref $_[0] eq HASH ? shift : { path => shift };
#            : ! ref $_[0] ? { path => shift }
#            : return $self->error_msg( unexpected => "$type arguments" => $_[0], 'hash ref' )
    }
    else {
        $args = { path => [@_] };
    }
    $args->{ filesystem } = $self;
    return $args;
}


# TODO: move file?


1;

__END__

=head1 NAME

Badger::Filesystem - filesystem functionality

=head1 SYNOPSIS

The C<Badger::Filesystem> module defines a number of importable constructor
functions for creating objects that represents files, directories and generic
paths in a filesystem.

    use Badger::Filesystem 'cwd Cwd Path File Dir Directory';
    use Badger::Filesystem 'cwd :types';        # same thing
    
    # cwd returns current working directory as text string, 
    # Cwd return it as a Badger::Filesystem::Directory object
    print cwd;                                  # /path/to/cwd
    print Cwd->parent;                          # /path/to
    
    # create Badger::Filesystem::Path/File/Directory objects using
    # native OS-specific paths:
    $path = Path('/path/to/file/or/dir');
    $file = File('/path/to/file');
    $dir  = Dir('/path/to/directory');           # short name
    $dir  = Directory('/path/to/directory');     # long name
    
    # or generic OS-independant paths
    $path = File('path', 'to', 'file', 'or', 'dir');
    $file = File('path', 'to', 'file');
    $dir  = Dir('path', 'to', 'directory');
    $dir  = Directory('path', 'to', 'directory');

These constructor functions are simply shortcuts to C<Badger::Filesystem>
class methods.

    use Badger::Filesystem;
    
    # we'll just show native paths from now on for brevity
    $path = Badger::Filesystem->path('/path/to/file/or/dir');
    $file = Badger::Filesystem->file('/path/to/file');
    $dir  = Badger::Filesystem->dir('/path/to/directory');

    # 'FS' is an alias for 'Badger::Filesystem' 4 lzy ppl lk me
    use Badger::Filesystem 'FS'
    
    $path = FS->path('/path/to/file/or/dir');
    $file = FS->file('/path/to/file');
    $dir  = FS->dir('/path/to/directory');

You can also create C<Badger::Filesystem> objects.

    my $fs = Badger::Filesystem->new;
    
    $path = $fs->path('/path/to/file/or/dir');
    $file = $fs->file('/path/to/file');
    $dir  = $fs->dir('/path/to/directory');

=head1 INTRODUCTION

This is the documentation for the C<Badger::Filesystem> module. You probably
don't need to read it.  If you're looking for an easy way to access and 
manipulate files and directories, then all you need to know to get started
is this:

    use Badger::Filesystem 'File Dir';
    
    my $file = File('/path/to/file');       # Badger::Filesystem::File
    my $dir  = Dir('/path/to/directory');   # Badger::Filesystem::Directory

The L<File()> and L<Dir()> subroutines are used to create
L<Badger::Filesystem::File> and L<Badger::Filesystem::Directory> objects. You
should read the documentation for those modules first as they cover pretty
much everything you need to know about working with files and directories for
simple day-to-day tasks.  In fact, you should start with the documentation
for L<Badger::Filesystem::Path> because that's the base class for both of
them.

If you want to do something a little more involved than inspecting, reading
and writing files, or if you want to find out more about the filesystem
functionality hidden behind the file and directory objects, then read on!

=head1 DESCRIPTION

The C<Badger::Filesystem> module defines an object class for accessing and
manipulating files and directories in a file system. It provides a number of
methods that encapsulate the behaviours of various other filesystem related
modules, including L<File::Spec>, L<File::Path>, L<IO::File>, L<IO::Dir> and
L<Cwd>. For example:

    # path manipulation
    my $dir  = Badger::Filesystem->join_dir('foo', 'bar', 'baz');
    my @dirs = Badger::Filesystem->split_dir('foo/bar/baz');
    
    # path inspection
    Badger::Filesystem->is_relative('foo/bar/baz');     # true
    Badger::Filesystem->is_absolute('foo/bar/baz');     # false
    
    # file manipulation
    Badger::Filesystem->write_file('/path/to/file', 'Hello World');
    Badger::Filesystem->delete_file('/path/to/file')
    
    # directory manipulation
    Badger::Filesystem->cwd;
    Badger::Filesystem->mkdir('/path/to/dir')

If you get tired of writing C<Badger::Filesystem> over and over again,
you can import the C<FS> symbol which is an alias to it (or you can define
your own alias of course).

    use Badger::Filesystem 'FS';
    
    FS->is_relative('foo/bar/baz');     # true
    FS->is_absolute('foo/bar/baz');     # false

The C<Badger::Filesystem> module also defines methods that create objects to
represent files (L<Badger::Filesystem::File>), directories
(L<Badger::Filesystem::Directory>), and generic paths
(L<Badger::Filesystem::Path>) that may refer to a file, directory, or a
resource that doesn't physically exist (e.g. a URI).

These are very similar (although not identical) to the corresponding
L<Path::Class> modules which you may already be familiar with. The main
difference between them is that C<Badger> files, directories and paths are
I<flyweight> objects that call back to the C<Badger::Filesystem> to perform
any filesystem operations. This gives us a more control over restricting
certain filesystem operations (e.g. writing files) and more flexibility in
what we define a filesystem to be (e.g. allowing virtually mounted and/or
composite file systems - see L<Badger::Filesystem::Virtual> for further
details).

    use Badger::Filesystem 'FS';
    
    # file manipulation - via Badger::Filesystem::File object
    my $file = FS->file('/path/to/file');
    print $file->size;                  # metadata
    print $file->modified;              # more metadata
    my $text = $file->read;             # read file content
    $file->write("New content");        # write file content

    # directory manipulation - via Badger::Filesystem::Directory object
    my $dir = FS->directory('/path/to/dir');
    print $dir->mode;                   # metadata
    print $dir->modified;               # more metadata
    my @entries = $dir->read;           # read directory entries
    my $file = $dir->file('foo');       # fetch a file
    my $sub  = $dir->dir('bar');        # fetch a sub-directory

The module also defines the L<Path()>, L<File()> and L<Directory()>
subroutines to easily create L<Badger::Filesystem::Path>,
L<Badger::Filesystem::File> and L<Badger::Filesystem::Directory> objects,
respectively. The L<Dir> subroutine is provided as an alias for L<Directory>.

    use Badger::Filesystem 'Path File Dir';
    
    my $path = Path('/any/generic/path');
    my $file = File('/path/to/file');
    my $dir  = Dir('/path/to/dir');

These subroutines are provided as a convenient way to call the L<path()>,
L<file()> and L<dir()> class methods. The above examples are functionally
equivalent to those shown below.

    use Badger::Filesystem;
    
    my $path = Badger::Filesystem->path('/any/generic/path');
    my $file = Badger::Filesystem->file('/path/to/file');
    my $dir  = Badger::Filesystem->dir('/path/to/dir');

The constructor subroutines and the corresponding methods behind them accept a
list (or reference to a list) of path components as well as a single path
string. This allows you to specify paths in an operating system agnostic
manner.

    # these all do the same thing (assuming you're on a Unix-like system)
    File('/path/to/file');          
    File('path', 'to', 'file');
    File(['path', 'to', 'file']);
    
    # these too
    Badger::Filesystem->file('/path/to/file');
    Badger::Filesystem->file('path', 'to', 'file');
    Badger::Filesystem->file(['path', 'to', 'file']);

The above examples assume a Unix-like filesystem using C</> as the path
separator. On a windows machine, for example, you would need to specify paths
using backslashes to satisfy their brain-dead file system. However, specifying
a list of separate path components remains portable.

    # if you're stuck on windows :-(
    File('\path\to\file');                  # OS specific
    File('path', 'to', 'file');             # OS agnostic

If you're using Perl on a windows machine then you should probably consider
getting a new machine. Try a nice shiny Mac, or an Ubuntu box. Go on, you know
you deserve better.  

You can also create a C<Badger::Filesystem> object and call object methods
against it.

    use Badger::Filesystem;
    
    my $fs   = Badger::Filesystem->new;
    my $file = $fs->file('/path/to/file');
    my $dir  = $fs->dir('/path/to/dir');

Creating an object allows you to define additional configuration parameters
for the filesystem. There aren't any interesting paramters worth mentioning in
the base class L<Badger::Filesystem> module at the moment, but subclasses
(like L<Badger::Filesystem::Virtual>) do use them.

=head1 EXPORTABLE SUBROUTINES

The C<Badger::Filesystem> module defines the L<Path>, L<File> and L<Directory>
subroutines which can be used to create L<Badger::Filesystem::Path>,
L<Badger::Filesystem::File> and L<Badger::Filesystem::Directory> objects,
respectively. The L<Dir> subroutine is provided as an alias for L<Directory>.

To use these subroutines you must import them explicitly when you 
C<use Badger::Filesystem>.

    use Badger::Filesystem 'File Dir';
    my $file = File('/path/to/file');
    my $dir  = Dir('/path/to/dir');

You can specify multiple items in a single string as shown in the example
above, or as multiple items in more traditional Perl style, as shown below.

    use Badger::Filesystem qw(File Dir);

You can pass multiple arguments to these subroutines if you want to specify
your path in a platform-agnostic way.

    my $file = File('path', 'to, 'file');
    my $dir  = Dir('path', 'to', 'dir');

A reference to a list works equally well.

    my $file = File(['path', 'to, 'file']);
    my $dir  = Dir(\@paths);

If you don't provide any arguments then the subroutines return the class name
associated with the object. For example, the L<File()> subroutine returns
L<Badger::Filesystem::File>. This allows you to use them as virtual classes,
(i.e. short-cuts) for the longer class names, if doing things the Object
Oriented way is your thing.

    my $file = File->new('path/to/file');
    my $dir  = Dir->new('path/to/dir');

The above examples are functionally identical to:

    my $file = Badger::Filesystem::File->new('path/to/file');
    my $dir  = Badger::Filesystem::Directory->new('path/to/dir');

A summary of the constructor subroutines follows.

=head2 Path(@path)

Creates a new L<Badger::Filesystem::Path> object.  You can specify the 
path as a single string or list of path components.

    $path = Path('/path/to/something');
    $path = Path('path', 'to', 'something');

=head2 File(@path)

Creates a new L<Badger::Filesystem::File> object.  You can specify the 
path as a single string or list of path components.

    $file = File('/path/to/file');
    $file = File('path', 'to', 'file');

=head2 Dir(@path) / Directory(@path)

Creates a new L<Badger::Filesystem::Directory> object.  You can specify the 
path as a single string or list of path components.

    $dir = Dir('/path/to/dir');
    $dir = Dir('path', 'to', 'dir');

=head2 Cwd()

This returns a L<Badger::Filesystem::Directory> object for the current
working directory.

    use Badger::Filesystem Cwd;
    
    print Cwd;              # /foraging/for/nuts/and/berries
    print Cwd->parent;      # /foraging/for/nuts/and

=head2 cwd

This returns a simple text string representing the current working directory.
It is a a wrapper around the C<getcwd> function in L<Cwd>.  It also 
sanitises the path (via the L<canonpath()|Path::Spec/canonpath()> function
in L<File::Spec>) to ensure that the path is returned in the local 
filesystem convention (e.g. C</> is converted to C<\> on Win32).

=head2 $Bin

This load the L<FindBin> module and exports the C<$Bin> variable into 
the caller's namespace.

    use Badger::Filesystem '$Bin';
    use lib "$Bin/../lib";

This is exactly the same as:

    use FindBin '$Bin';
    use lib "$Bin/../lib";

The benefit is that you can use it in conjunction with other import options.

    use Badger::Filesystem '$Bin Cwd File';

Compared to something like:

    use FindBin '$Bin';
    use Cwd;
    use Path::Class;

=head2 getcwd

This is a direct alias to the C<getcwd> function in L<Cwd>.

=head2 C<:types> Import Option

Specifying this an an import option will export all of the L<Path()>, 
L<File>, L<Dir>, L<Directory> and L<Cwd> subroutines to the caller.

    use Badger::Filesystem ':types';
    
    my $path   = Path('/some/where');
    my $dir    = Dir('/over/there');
    my $file   = File('example.html');
    my $parent = Cwd->parent;

=head1 CONSTRUCTOR METHODS

=head2 new(%config)

This is a constructor method to create a new C<Badger::Filesystem> object.

    my $fs = Badger::Filesystem->new;

In most cases there's no need to create a C<Badger::Filesystem> object at
all.  You can either call class methods, like this:

    my $file = Badger::Filesystem->file('/path/to/file');

Or use the constructor subroutines like this:

    use Badger::Filesystem 'File';
    my $file = File('/path/to/file');

However, you might want to create a filesystem object to pass to some other
method or object to work with.  In that case, the C<Badger::Filesystem> 
methods work equally well being called as object or class methods.

You may also want to use a subclass of C<Badger::Filesystem> such as 
L<Badger::Filesystem::Virtual> which requires configuration parameters
to be properly initialised.

=head2 path(@path)

Creates a new L<Badger::Filesystem::Path> object. This is typically used for
manipulating paths that don't relate to a specific file or directory in a real
filesystem.

    # single path (platform specific)
    my $path = $fs->path('/path/to/something');
    
    # list or list ref of path components (platform agnostic)
    my $path = $fs->path('path', 'to', 'something');
    my $path = $fs->path(['path', 'to', 'something']);

=head2 file(@path)

Creates a new L<Badger::Filesystem::File> object to represent a file in a 
filesystem.

    # single file path (platform specific)
    my $file = $fs->file('/path/to/file');
    
    # list or list ref of file path components (platform agnostic)
    my $file = $fs->file('path', 'to', 'file');
    my $file = $fs->file(['path', 'to', 'file']);

=head2 dir(@path) / directory(@path)

Creates a new L<Badger::Filesystem::Directory> object to represent a file in a
filesystem.  L<dir()> is an alias for L<directory()> to save on typing.

    # single directory path (platform specific)
    my $dir = $fs->dir('/path/to/directory');

    # list or list ref of directory path components (platform agnostic)
    my $dir = $fs->dir('path', 'to', 'directory');
    my $dir = $fs->dir(['path', 'to', 'directory']);

If you don't specify a directory path explicitly then it will default to 
the current working directory, as returned by L<cwd()>.

    my $cwd = $fs->dir;

=head1 PATH MANIPULATION METHODS

=head2 merge_paths($path1,$path2)

Joins two paths into one.  

    $fs->merge_paths('/path/one', 'path/two');      # /path/one/path/two

No attempt will be made to verify that the second argument is an absolute
path.  In fact, it is considered a feature that this method will do its
best to merge two paths even if they look like they shouldn't go together
(this is particularly relevant when using virtual filesystems - see
L<Badger::Filesystem::Virtual>)

    $fs->merge_paths('/path/one', '/path/two');     # /path/one/path/two

If either defines a volume then it will be used as the volume for the combined
path. If both paths define a volume then it must be the same or an error will
be thrown.

    $fs->merge_paths('C:\path\one', 'path\two');    # C:\path\one\path\two
    $fs->merge_paths('\path\one', 'C:\path\two');   # C:\path\one\path\two
    $fs->merge_paths('C:\path\one', 'C:\path\two'); # C:\path\one\path\two

=head2 split_path($path)

Splits a composite path into volume, directory name and file name components.
This is a wrapper around the L<splitpath()|File::Spec/splitpath()> function 
in L<File::Spec>.

    ($vol, $dir, $file) = $fs->split_path($path);

=head2 join_path($volume, $dir, $file)

Combines a filesystem volume (where applicable), directory name and file
name into a single path.  This is a wrapper around the 
L<catpath()|File::Spec/catpath()> and L<canonpath()|File::Spec/canonpath()> 
functions in L<File::Spec>.

    my $path = $fs−>join_path($volume, $directory, $file);

=head2 split_dir($dir) / split_directory($dir)

Splits a directory path into individual directory names.  This is a wrapper
around the L<splitdir()|File::Spec/splitdir()> function in L<File::Spec>.

    @dirs = $fs->split_dir($dir);

=head2 join_dir(@dirs) / join_directory(@dirs)

Combines multiple directory names into a single path.  This is a wrapper
around the L<catdir()|File::Spec/catdir()> function in L<File::Spec>.

    my $dir = $fs−>join_dir('path', 'to', 'my', 'dir');

The final element can also be a file name.   TODO: is that portable?

    my $dir = $fs−>join_dir('path', 'to', 'my', 'file');

=head2 collapse_dir($dir) / collapse_directory($dir)

Reduces a directory to its simplest form by resolving and removing any C<.>
(current directory) and C<..> (parent directory) components (or whatever the
corresponding tokens are for the current and parent directories of your
filesystem). 

    print $fs->collapse_dir('/foo/bar/../baz');   # /foo/baz

The reduction is purely syntactic. No attempt is made to verify that the
directories exist, or to intelligently resolve parent directory where symbolic
links are involved.

Note that this may not work portably across all operating systems.  If you're
using a Unix-based filesystem (including Mac OSX) or MS Windows then you 
should be OK.  If you're using an old MacOS machine (pre-OSX), VMS, or 
something made out of clockwork, then be warned that this method is untested
on those platforms.

C<collapse_dir()> is a direct alias of C<collapse_directory()> to save on 
typing.

=head2 slash_directory($path)

Returns the directory L<$path> with a trailing C</> appended (or whatever
the directory separator is for your filesystem) if it doesn't already 
have one.

    print $fs->slash_directory('foo');      # foo/

=head1 PATH INSPECTION METHODS

=head2 is_absolute($path)

Returns true if the path specified is absolute.  That is, if it starts
with a C</>, or whatever the corresponding token for the root directory is
for your file system.

    $fs->is_absolute('/foo');               # true
    $fs->is_absolute('foo');                # false

=head2 is_relative($path)

Returns true if the path specified is relative. That is, if it does not start
with a C</>, or whatever the corresponding token for the root directory is for
your file system.

    $fs->is_relative('/foo');               # false
    $fs->is_relative('foo');                # true

=head1 PATH CONVERSION METHODS

=head2 absolute($path, $base)

Converts a relative path to an absolute one.  The path passed as an argument
is assumed to be relative to the current working directory unless you 
explicitly provide a C<$base> parameter.

    $fs->cwd;                               # /foo/bar  (for example)
    $fs->absolute('baz');                   # /foo/bar/baz
    $fs->absolute('baz', '/wam/bam');       # /wam/bam/baz

Note how potentially confusing that last example is. The base path is the
I<second> argument which ends up in front of the I<first> argument.  It's
an unfortunately consequence of the way the parameters are ordered (the 
optional parameter must come after the mandatory one) and can't be avoided.

=head2 relative($path, $base)

Converts an absolute path to a relative one.  It is assumed to be relative
to the current working direct unless you explicitly provide a C<$base>
parameter.

    $fs->cwd;                               # /foo/bar  (for example)
    $fs->relative('/foo/bar/wam/bam');      # wam/bam
    $fs->relative('/baz/wam/bam', '/baz');  # wam/bam

Again note that last example where 

=head2 definitive($path)

Converts an absolute or relative path to a definitive one.  In most cases,
a definitive path is identical to an absolute one.

    $fs->definitive('/foo/bar');            # /foo/bar

However, if you're using a L<virtual filesystem|Badger::Filesystem::Virtual>
with a virtual root directory, then a I<definitive> path I<will> include the
virtual root directory, whereas a an I<absolute> path will I<not>.

    my $vfs = Badger::Filesystem::Virtual->new( root => '/my/vfs' );
    $vfs->absolute('/foo/bar');              # /foo/bar
    $vfs->definitive('/foo/bar');            # /my/vfs/foo/bar

The C<Badger::Filesystem> module uses definitive paths when performing any
operations on the file system (e.g. opening and reading files and
directories). You can think of absolute paths as being like conceptual URIs
(identifiers) and definitive paths as being like concrete URLs (locators). In
practice, they'll both have the same value unless unless you're using a
virtual file system.

In the C<Badger::Filesystem> base class, the C<definitive()> method is
mapped directly to the L<definitive_write()> method.  This has no real
effect in this module, but provides the relevant hooks that allow the 
L<Badger::Filesystem::Virtual> subclass to work properly.

=head2 definitive_read($path)

Converts an absolute or relative path to a definitive one for a read
operation.  See L<definitive()>.

=head2 definitive_write($path)

Converts an absolute or relative path to a definitive one for a write 
operation.  See L<definitive()>.

=head1 PATH TEST METHODS

=head2 path_exists($path)

Returns true if the path exists, false if not.

=head2 file_exists($path)

Returns true if the path exists and is a file, false if not.

=head2 dir_exists($path) / directory_exists($path)

Returns true if the path exists and is a directory, false if not.

=head2 stat_path($path)

Performs a C<stat()> on the filesystem path.  It returns a list (in list 
context) or a reference to a list (in scalar context) containing 17 items.
The first 13 are those returned by Perl's inbuilt C<stat()> function.  The
next 3 items are flags indicating if the file is readable, writeable and/or
executable.  The final item is a flag indicating if the file is owned by the
current user (i.e. owner of the current process.

A summary of the fields is shown below. See C<perldoc -f stat> and the
L<stat()|Badger::Filesystem::Path/stat()> method in
L<Badger::Filesystem::Path> for further details.

    Field   Description
    --------------------------------------------------------
      0     device number of filesystem
      1     inode number
      2     file mode  (type and permissions)
      3     number of (hard) links to the file
      4     numeric user ID of file’s owner
      5     numeric group ID of file’s owner
      6     the device identifier (special files only)
      7     total size of file, in bytes
      8     last access time in seconds since the epoch
      9     last modify time in seconds since the epoch
     10     inode change time in seconds since the epoch (*)
     11     preferred block size for file system I/O
     12     actual number of blocks allocated
     13     file is readable by current process
     14     file is writeable by current process
     15     file is executable by current process
     16     file is owned by current process

=head1 FILE MANIPULATION METHODS

=head2 create_file($path)

Creates an empty file if it doesn't already exist.  Returns a true value
if the file is created and a false value if it already exists.  Errors are
thrown as exceptions.

    $fs->create_file('/path/to/file');

=head2 touch_file($path) / touch($path)

Creates a file if it doesn't exists, or updates the timestamp if it does.

    $fs->touch_file('/path/to/file');

=head2 delete_file($path)

Deletes a file.

    $fs->delete_file('/path/to/file');      # Careful with that axe, Eugene!

=head2 open_file($path, $mode, $perms)

Opens a file for reading (by default) or writing/appending (by passing
C<$mode> and optionally C<$perms>). Accepts the same parameters as for the
L<IO::File::open()|IO::File> method and returns an L<IO::File> object.

    my $fh = $fs->open_file('/path/to/file');
    my $fh = $fs->open_file('/path/to/file', 'w');      
    my $fh = $fs->open_file('/path/to/file', 'w', 0644);

=head2 read_file($path)

Reads the content of a file, returning it as a list of lines (in list context)
or a single text string (in scalar context).

    my $text  = $fs->read_file('/path/to/file');
    my @lines = $fs->read_file('/path/to/file');

=head2 write_file($path, @content)

When called with a single C<$path> argument, this method opens the specified 
file for writing and returns an L<IO::File> object.

    my $fh = $fs->write_file('/path/to/file');
    $fh->print("Hello World!\n");
    $fh->close;

If any additional C<@content> argument(s) are passed then they will be 
written to the file.  The file is then closed and a true value returned 
to indicate success.  Errors are thrown as exceptions.

    $fs->write_file('/path/to/file', "Hello World\n", "Regards, Badger\n");

=head2 append_file($path, @content)

This method is similar to L<write_file()>, but opens the file for appending
instead of overwriting.  When called with a single C<$path> argument, it opens 
the file for appending and returns an L<IO::File> object.

    my $fh = $fs->append_file('/path/to/file');
    $fh->print("Hello World!\n");
    $fh->close;

If any additional C<@content> argument(s) are passed then they will be 
appended to the file.  The file is then closed and a true value returned 
to indicate success.  Errors are thrown as exceptions.

    $fs->append_file('/path/to/file', "Hello World\n", "Regards, Badger\n");

=head1 DIRECTORY MANIPULATION METHODS

=head2 create_dir($path) / create_directory($path) / mkdir($path)

Creates the directory specified by C<$path>. Errors are thrown as exceptions.

    $fs->create_dir('/path/to/directory');

Additional arguments can be specified as per the L<File::Path> C<mkpath()>
method. NOTE: this is subject to change. Better to use C<File::Path> directly
for now if you're relying on this.

=head2 delete_dir($path) / delete_directory($path) / rmdir($path)

Deletes the directory specified by C<$path>. Errors are thrown as exceptions.

    $fs->delete_dir('/path/to/directory');

=head2 open_dir($path) / open_directory($path)

Returns an L<IO::Dir> handle opened for reading a directory or throws
an error if the open failed.

    my $dh = $fs->open_dir('/path/to/directory');
    while (defined ($path = $dh->read)) {
        print " - $path\n";
    }

=head2 read_dir($dir, $all) / read_directory($dir, $all)

Returns a list (in list context) or a reference to a list (in scalar context)
containing the entries in the directory. These are simple text strings
containing the names of the files and/or sub-directories in the directory.

    my @paths = $fs->read_dir('/path/to/directory');

By default, this excludes the current and parent entries (C<.> and C<..> or
whatever the equivalents are for your filesystem. Pass a true value for the
optional second argument to include these items.

    my @paths = $fs->read_dir('/path/to/directory', 1);

=head2 dir_children($dir, $all) / directory_children($dir, $all)

Returns a list (in list context) or a reference to a list (in scalar
context) of objects to represent the contents of a directory.  As per
L<read_dir()>, the current (C<.>) and parent (C<..>) directories
are excluded unless you set the C<$all> flag to a true value.  Files are
returned as L<Badger::Filesystem::File> objects, directories as
L<Badger::Filesystem::File> objects.  Anything else is returned as a
generic L<Badger::Filesystem::Path> object.

=head2 dir_child($path) / directory_child($path)

Returns an object to represent a single item in a directory. Files are
returned as L<Badger::Filesystem::File> objects, directories as
L<Badger::Filesystem::File> objects. Anything else is returned as a generic
L<Badger::Filesystem::Path> object.

=head1 VISITOR METHODS

=head2 visitor(\%params)

This method creates a L<Badger::Filesystem::Visitor> object from the arguments
passed as a list or reference to a hash array of named parameters.

    # list of named parameters.
    $fs->visitor( files => 1, dirs => 0 );
    
    # reference to hash array of named parameters
    $fs->visitor( files => 1, dirs => 0 );

If the first argument is already a reference to a
L<Badger::Filesystem::Visitor> object or subclass then it will be returned
unmodified.

=head2 visit(\%params)

This methods forwards all arguments onto the
L<visit()|Badger::Filesystem::Directory/visit()> method of the 
L<root()> directory.

=head2 accept($visitor)

This lower-level method is called to dispatch a visitor to the correct method
for a filesystem object. It forward the visitor onto the
L<accept()|Badger::Filesystem::Directory/accept()> method for the L<root()>
directory.

=head2 collect(\%params)

This is a short-cut to call the L<visit()> method and then the 
L<collect()|Badger::Filesystem::Visitor/collect()> method on the 
L<Badger::Filesystem::Visitor> object returned.

    # short form
    my @items = $fs->collect( files => 1, dirs => 0 );

    # long form
    my @items = $fs->visit( files => 1, dirs => 0 )->collect;

=head1 MISCELLANEOUS METHODS

=head2 cwd()

Returns the current working directory. This is a text string rather than a
L<Badger::Filesystem::Directory> object. Call the L<Cwd()> method
if you want a L<Badger::Filesystem::Directory> object instead.

    my $cwd = $fs->cwd;

=head2 root()

Returns a L<Badger::Filesystem::Directory> object representing the root
directory for the filesystem.

=head2 rootdir

Returns a text string containing the representation of the root directory
for your filesystem.  

    print $fs->rootdir;             # e.g. '/' on Unix-based file systems

=head2 updir

Returns a text string containing the representation of the parent directory
for your filesystem.  

    print $fs->updir;               # e.g. '..' on Unix-based file systems

=head2 curdir

Returns a text string containing the representation of the current directory
for your filesystem.  

    print $fs->curdir;              # e.g. '.' on Unix-based file systems

=head2 separator

Returns a text string containing the representation of the path separator
for your filesystem.  

    print $fs->separator;           # e.g. '/' on Unix-based file systems

=head1 EXPORTABLE CONSTANTS

=head2 FS

An alias for C<Badger::Filesystem>

=head2 VFS

An alias for L<Badger::Filesystem::Virtual>.  This also ensures that the
L<Badger::Filesystem::Virtual> module is loaded.

=head2 PATH

An alias for C<Badger::Filesystem::Path>

=head2 FILE

An alias for C<Badger::Filesystem::File>

=head2 DIR / DIRECTORY

An alias for C<Badger::Filesystem::Directory>

=head1 AUTHOR

Andy Wardley E<lt>abw@wardley.orgE<gt>

=head1 COPYRIGHT

Copyright (C) 2005-2008 Andy Wardley. All rights reserved.

=head1 ACKNOWLEDGEMENTS

The C<Badger::Filesystem> modules are built around a number of Perl modules
written by some most excellent people. May the collective gratitude of the
Perl community shine forth upon them.

L<File::Spec> by Ken Williams, Kenneth Albanowski, Andy Dougherty, Andreas
Koenig, Tim Bunce, Charles Bailey, Ilya Zakharevich, Paul Schinder, Thomas
Wegner, Shigio Yamaguchi, Barrie Slaymaker.

L<File::Path> by Tim Bunce and Charles Bailey.

L<Cwd> by Ken Williams and the Perl 5 Porters. 

L<IO::File> and L<IO::Dir> by Graham Barr.

It was also inspired by, and draws heavily on the ideas and code in
L<Path::Class> by Ken Williams. There's also more than a passing influence
from the C<Template::Plugin::File> and C<Template::Plugin::Directory>
modules which were based on code originally by Michael Stevens.

=head1 SEE ALSO

L<Badger::Filesystem::Path>, 
L<Badger::Filesystem::Directory>,
L<Badger::Filesystem::File>,
L<Badger::Filesystem::Visitor>
L<Badger::Filesystem::Virtual>.

=cut

# Local Variables:
# mode: Perl
# perl-indent-level: 4
# indent-tabs-mode: nil
# End:
#
# vim: expandtab shiftwidth=4:
# TextMate: rocks my world
