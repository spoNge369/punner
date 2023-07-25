#!/usr/bin/perl

use Mojo::Base qw/-strict -signatures -async_await/;
use Mojo::Util qw/dumper steady_time getopt/;
use Term::ANSIColor qw/:constants/;
use Mojo::JSON qw/decode_json/;
use Mojo::ByteStream qw/b/;
use Mojo::UserAgent;
use Mojo::Promise;
use Mojo::File;

my $jsonf = "";
my $find_replace = "";
my $test = "";

getopt
    "r|replace=s"  => \$find_replace, # find,replace... v2,v3 ... v2,'|whoami'
    "f|filejson=s" => \$jsonf,
    "t|test=s"     => \$test;

my $ua = Mojo::UserAgent->new;
my $t = Mojo::UserAgent::Transactor->new;
$jsonf = 'crapi.postman_collection.json' if ($jsonf eq "");


sub postman_json($path) {
    my $file = Mojo::File->new($path);
    my $data = decode_json($file->slurp);

    #my $url = $data->{"item"}->[0]->{"item"}->[15]->{"request"}->{"url"}->{"raw"};
    #my $method = $data->{"item"}->[0]->{"item"}->[15]->{"request"}->{"method"};
    #my $header_json = $data->{"item"}->[0]->{"item"}->[15]->{"request"}->{"header"};
    #my $body = $data->{"item"}->[0]->{"item"}->[15]->{"request"}->{"body"}->{"raw"};

    #my $header = jsonToHeader($header_json);
    #say dumper $header;

    return $data->{"item"}->[0]->{"item"}->@*; #array all data
}

sub jsonToHeader($header_json) {
    my $header = {};
    foreach ($header_json->@*) {
        #say "$_->{key}: $_->{value}";
        $header->{$_->{key}} = $_->{value};
    }
    return $header;
}

sub postmanReplace(@data) {
    my @arrayR = split ',', $find_replace;
    my $find = $arrayR[0];
    my $replace = $arrayR[1];

    foreach (@data) {
        $_->{"request"}->{"url"}->{"raw"} =~s/$find/$replace/gi;
        $_->{"request"}->{"method"} =~s/$find/$replace/gi;
        $_->{"request"}->{"body"}->{"raw"} = "" if !defined($_->{"request"}->{"body"}->{"raw"});
        $_->{"request"}->{"body"}->{"raw"} =~s/$find/$replace/gi;

        foreach my $h ($_->{"request"}->{"header"}->@*) {
            $h->{key} =~s/$find/$replace/gi;
            $h->{value} =~s/$find/$replace/gi;
        }
    }
    
}

async sub get_runner($payload) {
    my $url = $payload->{"request"}->{"url"}->{"raw"}; #string
    my $method = $payload->{"request"}->{"method"};     #string
    my $header_req = jsonToHeader($payload->{"request"}->{"header"}); #hash
    my $body_req = $payload->{"request"}->{"body"}->{"raw"}; #string

    $body_req = "" if !defined($body_req);

    my $tx = $t->tx($method => $url  => $header_req => $body_req);
    await $ua->insecure(1)->start_p($tx);

    my $body_res = $tx->res->body;
    my $size_bs = b($tx->res->headers->content_length)->humanize_bytes;

    my $status_code = $tx->res->code;

    if ( 200 <= $status_code <= 299) {
        $status_code = BOLD GREEN, $status_code, RESET;
    }
    elsif ( 300 <= $status_code <= 399) {
        $status_code = BOLD CYAN, $status_code, RESET;
    }
    elsif ( 400 <= $status_code <= 499) {
        $status_code = BOLD RED, $status_code, RESET;
    }
    elsif ( 500 <= $status_code <= 599) {
        $status_code = BOLD YELLOW, $status_code, RESET;
    } 
    elsif (100 <= $status_code <= 199) {
        $status_code = BOLD BLACK, $status_code, RESET;
    }
    #say $tx->res->headers->content_length;

    #say dumper $body;
    say $url . " status_code: ". $status_code . " body size: " . $size_bs;

}


sub testhttp(@data) { #@data @payloads main...
    foreach (@data) {
        if ($_->{"request"}->{"url"}->{"raw"} =~/$test/gi) {
                my $url = $_->{"request"}->{"url"}->{"raw"}; #string
                my $method = $_->{"request"}->{"method"};     #string
                my $header_req = jsonToHeader($_->{"request"}->{"header"}); #hash
                my $body_req = $_->{"request"}->{"body"}->{"raw"}; #string

                $body_req = "" if !defined($body_req);

                my $tx = $t->tx($method => $url  => $header_req => $body_req);
                $ua->insecure(1)->start($tx);

                say $tx->req->to_string;
                say $tx->res->to_string;
                last;
        }
    }
    exit 0;

}

async sub main($json_file) {
    my @payloads = postman_json($json_file);

    postmanReplace(@payloads) if $find_replace=~/\w+\,\w+/gi;


    testhttp(@payloads) if $test ne "";


    await Mojo::Promise->map({concurrency => 10}, sub {
        get_runner($_)
    }, @payloads);
}

#my $time = steady_time;
await main($jsonf);
#say steady_time-$time;
