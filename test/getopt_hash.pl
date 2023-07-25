#!/usr/bin/perl
#perl getopt_hash.pl
#perl getopt_hash.pl -H 'username: user' -H 'x-cookie:    x-cook123'

use Mojo::Base qw(-strict -signatures);
use Mojo::JSON qw/decode_json/;
use Mojo::ByteStream qw/b/;
use Mojo::File;
use Mojo::Util qw(dumper trim getopt);


my $header = {
    "x-cookie" => "cookiemaster123",
    "username" => "admin"
};

getopt
    "H|headers=s" => \my @H;

    if(@H) {
        foreach my $e (@H) {
            my ($k, $v) = split /:\s*/, $e;
            $header->{$k} = $v;

        }
    }
say dumper $header;
