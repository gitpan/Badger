#========================================================================
#
# t/codec/json.t
#
# Test the Badger::Codec::JSON module.
#
# Written by Andy Wardley <abw@wardley.org>
#
# This is free software; you can redistribute it and/or modify it
# under the same terms as Perl itself.
#
#========================================================================

use strict;
use warnings;
use lib qw( ./lib ../lib ../../lib );
use Badger::Codec::Storable;
use constant Codec => 'Badger::Codec::JSON';
use Badger::Test 
    debug => 'Badger::Codec::Storable',
    args  => \@ARGV;

eval "require Badger::Codec::JSON";
if ($@) {
    skip_all($@);
}
else {
    plan(5);
}

my $data = {
    pi => 3.14,
    e  => 2.718,
    hash => {
        things => [ qw( foo bar baz ) ],
    }
};


my $encoded = Codec->encode($data);
ok( $encoded, 'encoded data' );

my $decoded = Codec->decode($encoded);
ok( $decoded, 'decoded data' );

is( $decoded->{ pi }, $data->{ pi }, 'pi remains constant' );
is( $decoded->{ e  }, $data->{ e  }, 'e remains constant' );
is( $decoded->{ hash }->{ things }->[0], 'foo', 'foo' );


__END__

# Local Variables:
# mode: Perl
# perl-indent-level: 4
# indent-tabs-mode: nil
# End:
#
# vim: expandtab shiftwidth=4:

