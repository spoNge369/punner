#!/usr/bin/perl

use Mojo::Base qw/-strict -signatures -async_await/;
use Mojo::Util qw/dumper steady_time getopt/;
use Term::ANSIColor qw/:constants/;
use Mojo::JSON qw/decode_json/;
use Mojo::ByteStream qw/b/;
use Mojo::UserAgent;
use Mojo::Promise;
use Mojo::File;


binmode STDOUT, ':utf8';
binmode STDERR, ':utf8';

my $jsonf        = "";
my @find_replace = qw();
my $test         = "";
my $help         = 0;
my $concurrency  = 10;
my $color_req = BOLD GREEN;
my $color_res = BOLD CYAN;
my $reset = RESET;
my $proxy = "";

getopt
    "r|replace=s"   => \@find_replace, # find,replace... v2,v3 ... v2,'|whoami'
    "f|filejson=s"  => \$jsonf,
    "t|test=s"      => \$test,
    "h|help"        => \$help,
    "c|concurrency" => \$concurrency,
    "H|headers=s"   => \my @H,
    "q|quite=s"     => \my $quite,
    "x|proxy=s"     => \$proxy;

my $ua = Mojo::UserAgent->new;
my $t = Mojo::UserAgent::Transactor->new;

$ua->proxy->http($proxy)->https($proxy) if $proxy ne "";
$jsonf eq "" and help() and exit 1;
$help and help() and exit 1;


sub help() {
    my $punner=<<'PUN';
█ ▄▄   ▄      ▄      ▄   ▄███▄   █▄▄▄▄ 
█   █   █      █      █  █▀   ▀  █  ▄▀ 
█▀▀▀ █   █ ██   █ ██   █ ██▄▄    █▀▀▌  
█    █   █ █ █  █ █ █  █ █▄   ▄▀ █  █  
 █   █▄ ▄█ █  █ █ █  █ █ ▀███▀     █   
  ▀   ▀▀▀  █   ██ █   ██          ▀    
PUN
    say BOLD YELLOW, $punner, RESET . <<"HELP";
                    (github: \@spoNge369)

    Parameters               Description
    ==========               ===========

    -h|-help                  Help panel
    -c|-concurrency           number of concurrent http requests (default: 10)
    -f|-filejson              JSON file -> export from Postman's Collection (v2.1)
    -r|-replace               searches and replaces a keyword from all requests
    -t|-test                  shows the request and response for a given url, 
                                    a regular expression pattern is allowed.
    -q|-quite                 remove urls, support regular expressions
    -H|-headers               add headers to http requests
    -x|-proxy                 Proxy URL (socks:// or http://)

    Examples:

perl punner.pl -f ./crapi.postman_collection.json
perl punner.pl -f ./crapi.postman_collection.json -H 'x-token: abcdefgh123' -H 'x-cookie: abcdefgh123'
perl punner.pl -f ./crapi.postman_collection.json -q "auth|check-otp"
perl punner.pl -f ./crapi.postman_collection.json -r 'api,api2' -r 'login,login2'
perl punner.pl -f ./crapi.postman_collection.json -t 'auth/login'
perl punner.pl -f ./crapi.postman_collection.json -t 'http://localhost:8888/api/auth/login'
perl punner.pl -f ./crapi.postman_collection.json -x http://127.0.0.1:8080
HELP
}

sub postman_json($path) {
    my $file = Mojo::File->new($path);
    my $data = decode_json($file->slurp);

    my @dat = $data->{"item"}->[0]->{"item"}->@*;

    #my $url = $data->{"item"}->[0]->{"item"}->[15]->{"request"}->{"url"}->{"raw"};
    #my $method = $data->{"item"}->[0]->{"item"}->[15]->{"request"}->{"method"};
    #my $header_json = $data->{"item"}->[0]->{"item"}->[15]->{"request"}->{"header"};
    #my $body = $data->{"item"}->[0]->{"item"}->[15]->{"request"}->{"body"}->{"raw"};

    #my $header = jsonToHeader($header_json);
    #say dumper $header;
    @dat = grep{$_->{"request"}->{"url"}->{"raw"}!~/$quite/gi} @dat if (defined($quite));

    return @dat; #array all data
}

sub jsonToHeader($header_json) {
    my $header = {};
    foreach ($header_json->@*) {
        #say "$_->{key}: $_->{value}";
        $header->{$_->{key}} = $_->{value};
    }

    if(@H) {
        foreach my $e (@H) {
            my ($k, $v) = split /:\s*/, $e;
            $header->{$k} = $v;

        }
    }

    return $header;
}

sub postmanReplace(@data) {
    foreach my $fr (@find_replace) {
        my @arrayR = split ',', $fr; #split /,\s*/, $fr;
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
    #my $size_bs = b($tx->res->headers->content_length)->humanize_bytes;
    my $size_bs = b(b($tx->res->to_string)->size)->humanize_bytes;

    my $status_code = $tx->res->code;

    if (200 <= $status_code <= 299) {
        $status_code = BOLD GREEN, $status_code, RESET;
        $url = GREEN . $url . RESET;
    }
    elsif (300 <= $status_code <= 399) {
        $status_code = BOLD CYAN, $status_code, RESET;
        $url = CYAN . $url . RESET;
    }
    elsif (400 <= $status_code <= 499) {
        $status_code = BOLD RED, $status_code, RESET;
        $url = RED . $url . RESET;
    }
    elsif (500 <= $status_code <= 599) {
        $status_code = BOLD YELLOW, $status_code, RESET;
        $url = YELLOW . $url . RESET;
    } 
    elsif (100 <= $status_code <= 199) {
        $status_code = BOLD BLACK, $status_code, RESET;
        $url = BLACK . $url . RESET;
    }
    #say $tx->res->headers->content_length;

    #say dumper $body;
    say $url . " status_code: ". $status_code . " response_size: " . $size_bs;

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
                my $req = $tx->req->to_string . "\n";
                my $res = $tx->res->to_string;

                $req=~s/(.+ HTTP\/\d\.\d)/$color_req$1$reset/;
                $res=~s/(HTTP\/\d\.\d.+)/$color_res$1$reset/;

                say $req;
                say $res;

                last;
        }
    }
    exit 0;

}

async sub main($json_file) {
    my @payloads = postman_json($json_file);
    #para verificar que todos -r tengan el formato find,replace
    postmanReplace(@payloads) if (grep{/\s*.+\s*\,\s*.+\s*/g}@find_replace) == scalar(@find_replace);

    testhttp(@payloads) if $test ne "";

    await Mojo::Promise->map({concurrency => $concurrency}, sub {
       get_runner($_)
    }, @payloads);
}

my $time = steady_time;
await main($jsonf);
say steady_time-$time;
