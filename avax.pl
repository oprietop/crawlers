#!/usr/bin/perl
# teh awesomest avaxhome.ws crawler.

use strict;
use Encode;         # encode
use Storable;       # store, retrieve
use HTML::Entities; # decode_entities
use WWW::Mechanize;
use Term::ANSIColor qw(:constants);
$Term::ANSIColor::AUTORESET = 1;
use Getopt::Long qw(:config bundling);

my $mech = WWW::Mechanize->new( autocheck => 0 );#, onerror => undef);
$mech->agent_alias( 'Windows IE 6' );
my $pagecount = 0;
my $havecount = 0;
my $update = 0;
my %hash = ();

GetOptions ( 'update' => \$update );

sub hash {
   if ($update) {
        print YELLOW "Hashing on $0.hash ... ";
        store(\%hash, "$0.hash") or die "Can't store hash!\n";
        print BOLD GREEN "OK\n";
    }
}

if (-f "$0.hash") {
    my $href = retrieve("$0.hash");
    %hash=%$href;
} else {
    print "Can't find $0.hash, we'll update instead\n";
    $update = 1;
}

UPDATE: while ($update and $pagecount < 300) {
    $pagecount++;
    print BOLD GREEN "#\n#\thttp://avaxhome.ws/music/pages/$pagecount\n#\n";
    $mech->get("http://avaxhome.ws/music/pages/$pagecount");
    my $page = encode('utf-8', decode_entities($mech->content())); # A lo bestia.
    while ($page =~ /<div class='news' id='news-\d+'>(.+?)<div class='hr'><\/div>/sg) {
        my $get = $1;
        my $url = undef;
        my $name = undef;
        my $center = undef;

        if ($get =~ /<h1><a href="([^"]+)">([^<]+)<\/a><\/h1>/) {
            $url = "http://avaxhome.ws$1";
            $name = $2;
        }

        while ($get =~ /<div class="center">(.+?)<\/div>/sg) {
            $center = $1;
            $center =~ s/<br\/>\n/\n\t/g;
            $center =~ s/<[^<]+>//g;
        }

        next unless $center =~ /(?:flac|ape|lossless|wv)/i;
        my $found = $&;

        if ($hash{$url}) {
            $havecount++;
            print BLUE "- $name\n";
            if ($havecount == 10) {
                print BOLD RED "Got the last 10 entries, skipping update.\n";
                last UPDATE;
            }
            next;
        } else {
            print "+ $name\t";
            print YELLOW " ($found)\n";
            $havecount = 0;
        }

        $hash{$url}{name} = $name;
        $hash{$url}{center} = $center;
        $hash{$url}{localtime} = localtime;
        $mech->get($url);
        my $urlc = encode('utf-8', decode_entities($mech->content()));

        while ($urlc =~ /href="(http:[^"]+)" target="_blank" rel="nofollow">([^>]+)</sg) {
            $hash{$url}{links}{$1} = $2;
        }

        while ($get =~ /Posted By :<\/b>\n<a href="([^"]+)">([^<]+)<\/a>\n\|\n<b>Date :<\/b>\n([^\|]+)\n\|\n<b>Comments :<\/b>\n([^\|]+)\n\|\n/sg) {
            $hash{$url}{poster_url} = "http://avaxhome.ws$1";
            $hash{$url}{poster} = $2;
            $hash{$url}{date} = $3;
            $hash{$url}{comments} = $4;
        }
    }
    &hash unless $pagecount % 20 # We'll update the hash every 20 pages.
}

$update and &hash and exit 0;

foreach my $entry (sort { $hash{$a}{localtime} cmp $hash{$b}{localtime} } keys %hash) {
    @ARGV and next unless grep {"$hash{$entry}{name} $hash{$entry}{poster} $hash{$entry}{center}" =~ /$_/i} @ARGV;
    print BOLD RED "$hash{$entry}{name}";
    print " ($hash{$entry}{localtime})\n";
    print YELLOW "\t$entry\n";
    print BLUE "\t$hash{$entry}{center}\n";
    print "\tPosted By: $hash{$entry}{poster} | Date: $hash{$entry}{date} | Comments: $hash{$entry}{comments}\n";
    print GREEN "\t/ Links:\n";
    foreach my $link (sort { $hash{$entry}{links}{$a} cmp $hash{$entry}{links}{$b} } keys %{$hash{$entry}{links}}) {
         print GREEN "\t| - $hash{$entry}{links}{$link}";
         print BOLD WHITE RED " -> ";
         print WHITE "$link\n";
    }
    print GREEN "\t+\n";
}

exit 0;
