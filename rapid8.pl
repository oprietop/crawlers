#!/usr/bin/perl -w
#Trying rapid8's reliability without being popup bashed.

use strict;
use warnings;
use LWP::UserAgent;
use HTTP::Request::Common;
use Data::Dumper;

my $ua = LWP::UserAgent->new(timeout => 5 , show_progress => 1);
$ua->agent('Mac Safari');

foreach my $url (@ARGV) {
    my $tmpfile = "rapid8${url}";
    $tmpfile =~ s/\W//g;
    print "# $url\n";
    my $response = $ua->post( 'http://6imc12.rapid8.com/download/index.php'
                            , [ dlurl  => $url ]
                            , ':content_file' => $tmpfile
                            , Referer => 'http://rapid8.com/stage2.php'
                            );
    if ($response->is_success) {
        my ($filename) = $response->header('content-disposition') =~ /filename="([^"]+)"/;
        my ($filength, $tmplength) = ($response->header('Content-Length'), -s $tmpfile);
        $filength == $tmplength ? rename($tmpfile, $filename) : print "ERROR: Our file is $tmplength bytes and we are expecting $filength bytes.\n";
    } else {
        print Dumper $response->headers;
    }
    unlink $tmpfile if -f $tmpfile;
}
exit 0;
