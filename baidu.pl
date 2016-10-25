#!/usr/bin/perl -w
# Get stuff from baidu.com (or not)

use strict;
use warnings;
use utf8;
use LWP::UserAgent;
use HTTP::Request::Common;
use Fcntl qw(:flock);               # Use the system's File Locking http://www.perlmonks.org/index.pl?node_id=7058
binmode(STDOUT, ':encoding(utf8)'); # Get unicode output.

my $ua = LWP::UserAgent->new( agent         => 'Mac Safari'             # I'm a cool web crawler
                            , timeout       => 5                        # Idle timeout (Seconds)
                            , show_progress => 1                        # Fancy progressbar
                            , ssl_opts      => { verify_hostname => 0 } # Trust everything
                            );

sub unescape_json ($) {
    my $string = shift;
    $string =~ s/\\u(\w{4})/chr(hex($1))/ge; # UTF8
    $string =~ s/\\+(.)/$1/ge;               # The rest
    return $string;
}

foreach my $url (@ARGV) {
    my ($got_failures, $bytes) = (0, 0);
    my $response = $ua->get($url);
    if ($response->is_success) {
        my $content = $response->content;
        while ($content =~ /server_filename\\":\\"(.+?)\\",\\"size\W+(\d+).+?\\"md5\W+(\w+).+?dlink\W+(.+?)\\"}/sg) {
            my ($server_filename, $size, $md5, $dlink) = (&unescape_json($1), $2, $3, &unescape_json($4));
            print "** Found file '$server_filename' size: $size md5: $md5\n";
            if (-r $server_filename) {
                $bytes = -s $server_filename || 0;
                print "WA File is already on disk with $bytes bytes, skipping...\n";
                next;
            }
            my $tmpfile = "baidu_${md5}.part";
            $bytes = -s $tmpfile || 0;
            print "** Found temp file '$tmpfile' with $bytes bytes, resuming...\n" if $bytes;
            open(DOWN_FH, ">>$tmpfile") || die "ER Error '$!' trying to open '$tmpfile', exiting...\n";
            if (flock(DOWN_FH, LOCK_EX|LOCK_NB)) { # Locking will allow us to rerun the script on the same url at once.
                my $response = $ua->get( $dlink
                                       , ':content_cb' => sub { my ($chunk) = @_; print DOWN_FH $chunk; }
                                       , 'Range' => "bytes=$bytes-"
                                       );
                close(DOWN_FH) || die "ER Error '$!' trying to close '$tmpfile', exiting...\n";
                if ($response->is_success) { # Not checking status 416, we shouldn't hit it.
                    $bytes = -s $tmpfile || 0;
                    if ($size == $bytes) {
                        rename($tmpfile, $server_filename);
                    } else {
                        print "ER Error, our file is $bytes bytes and we expect $size bytes.\n";
                        $got_failures++;
                    }
                } else {
                    unlink $tmpfile if -z $tmpfile;
                    $got_failures++;
                    print "ER Download error. The status code is: ".$response->status_line."\n";
                }
            } else {
                print "WA Could not get an exclusive lock to '$tmpfile': $!, skipping...\n";
            }
        }
    } else {
        $got_failures++;
        print "ER Error fetching '$url'. The status code is: ".$response->status_line."\n";
    }
    if ($got_failures) {
        print "WA We got $got_failures errors while processing '$url' we will try it again.\n";
        unshift(@ARGV, $url);
    }
}
exit 0;
