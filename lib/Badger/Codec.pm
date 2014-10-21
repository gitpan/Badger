#========================================================================
#
# Badger::Codec
#
# DESCRIPTION
#   Base class codec providing a generic API for encoding/decoding data.
#
# AUTHOR
#   Andy Wardley   <abw@wardley.org>
#
#========================================================================

package Badger::Codec;

use Badger::Class
    version => 0.01,
    debug   => 0,
    base    => 'Badger::Base',
    utils   => 'UTILS';

sub encode {
    shift->not_implemented;
}

sub decode {
    shift->not_implemented;
}


# This is the "brute force and ignorance" approach to creating stand-alone
# subroutines.  They get the job done, albeit at the overhead of an extra
# method call.  Subclasses can do something better, like exporting existing
# subrefs directly.

sub encoder {
    my $self = shift;
    return sub { $self->encode(@_) };
}

sub decoder {
    my $self = shift;
    return sub { $self->decode(@_) };
}

1;


__END__

=head1 NAME

Badger::Codec - base class for encoding/decoding data

=head1 SYNOPSIS

    # creating a Badger::Codec subclass
    package My::Codec;
    use base 'Badger::Codec';
    
    sub encode {
        my ($self, $data) = @_;
        # do something
        return $encoded_data;
    }
    
    sub decode {
        my ($self, $encoded_data) = @_;
        # do something
        return $decoded_data;
    }

    # using the subclass:
    use My::Codec;
    
    my $codec   = My::Codec->new();
    my $encoded = $codec->encode($some_data);
    my $decoded = $codec->decode($encoded);

=head1 INTRODUCTION

This documentation describes the inner working of codec modules. You should
only need to consult this documentation if you're writing a codec subclass.
For a general introduction to codecs and examples of use, please see
L<Badger::Codecs>.

=head1 DESCRIPTION

This module implements a base class codec module for encoding and decoding
data to and from different formats. It must be subclassed to provide useful
implementations of the C<encode()> and C<decode()> methods.

In most, if not all cases, subclasses will simply delegate to
subroutines provided by other modules.  For example, the
L<Badger::Codec::Storable> module delegates to the C<freeze()> and
C<thaw()> methods provided by the L<Storable> module.

=head1 METHODS

=head2 encode($data)

Method for encoding data.  This must be redefined in subclassed
modules.

=head2 decode($data)

Method for decoding data.  This must be redefined in subclassed
modules.

=head2 encoder()

Returns a reference to a subroutine which performs the encoding operation.

=head2 decoder()

Returns a reference to a subroutine which performs the decoding operation.

=head1 AUTHOR

Andy Wardley L<http://wardley.org/>

=head1 COPYRIGHT

Copyright (C) 2005-2009 Andy Wardley. All rights reserved.

This module is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

# Local Variables:
# mode: Perl
# perl-indent-level: 4
# indent-tabs-mode: nil
# End:
#
# vim: expandtab shiftwidth=4:

