#!/usr/bin/perl -w
# Downloads stuff from rapidshare urls and/or link filelists with checksum check and resume.
# http://images.rapidshare.com/apidoc.txt

use strict;
use warnings;
use LWP::UserAgent;
use LWP::Protocol::https;    # RS requires https for certain transactions.
use HTTP::Request::Common;
use Digest::MD5 qw(md5_hex);
use File::Copy;              # move()
use Term::ANSIColor qw(:constants);
$Term::ANSIColor::AUTORESET = 1; # It doesn't seem to work everywhere.

print "$0 <rapidshare urls and/or link textfiles>\n" and exit 1 unless @ARGV;

# We'll define and use the same LWP objext, 'show_progress' will provide a progressbar/verbosity.
my $ua = LWP::UserAgent->new(timeout => 5, show_progress => 1);
$ua->agent('Mac Safari');

# Global vars.
my @downloads = (); # Array of hashes with the url info.
my $total_size;     # Total size of the remote filename.
my $temp_file;      # Filename of the current download.

# Calculate the MD5 checksum from a file.
sub md5_digest($) {
    my $file = shift;
    open(MD5_FH, $file) or die "Can't open '$file': $!";
    binmode(MD5_FH);
    my $result = Digest::MD5->new->addfile(*MD5_FH)->hexdigest;
    close(MD5_FH);
    return $result;
}

# Parse RS links from urls and fill the @downloads array.
sub parse_url($) {
    my $url = shift;
    $url =~ s/[\n\r]//g;
    if ($url =~ /files\/(\d+)\/(.+)/) {
        print "Adding '$2' ($1).\n";
        push @downloads, { url      => $url
                         , fileid   => $1
                         , filename => $2
                         };
    }
}

# Parse the commandline args and put everything to work.
foreach my $arg (@ARGV) {
    if (-r $arg) {
        open(FILE, $arg) or die;
        &parse_url($_) while <FILE>;
        close(FILE);
    } else {
        &parse_url($arg);
    }
}

# Traverse the @downloads array and try to download what we can.
foreach my $download (@downloads) {
    print GREEN "Trying '$download->{filename}' ($download->{fileid})." and print "\n";
    $temp_file = "$download->{filename}.part";
    $download->{offset} = -s $temp_file;

    if (-r $download->{filename}) {
        print YELLOW "Skipping '$download->{filename}', already on disk." and print "\n";
        next;
    }

    # Check if the file is available.
    print "** Check file availability...";
    my $response = $ua->request( POST 'https://api.rapidshare.com/cgi-bin/rsapi.cgi'
                               , [ sub       => 'checkfiles'
                                 , files     => $download->{fileid}
                                 , filenames => $download->{filename}
                                 ]
                               );
    if ($response->is_success) {
        print GREEN " OK" and print "\n";
    } else {
        print RED " NOK" and print "\n";
        next;
    }

    my @reply_fields = split (',', $response->content);

    if ($reply_fields[2] and $reply_fields[4] == 1) {
        $total_size = $reply_fields[2];
    } else {
        my %checkfiles_status = ( 0 => 'File not found'
                                , 1 => 'File OK'
                                , 3 => 'Server down'
                                , 4 => 'File marked as illegal'
                                );
        print RED "Error checking '$download->{filename}': $checkfiles_status{$reply_fields[4]}." and print "\n";
        next;
    }

    # Request a download token.
    print "** Getting a download token...";
    $response = $ua->request( POST 'https://api.rapidshare.com/cgi-bin/rsapi.cgi'
                            , [ sub      => 'download'
                              , fileid   => $download->{fileid}
                              , filename => $download->{filename}
                              ]
                            );
    if ($response->is_success) {
        print GREEN " OK" and print "\n";
    } else {
        print RED " NOK" and print "\n";
        next;
    }

    # Launch/resume the download.
    if (($download->{rs_hostname}, $download->{dlauth}, $download->{md5hex}) = $response->content =~ /DL:([^,]+),(\w+),0,(\w+)/) {
        my $url = "http://$download->{rs_hostname}/cgi-bin/rsapi.cgi?sub=download";
        $url .= "&fileid=$download->{fileid}";
        $url .= "&filename=$download->{filename}";
        $url .= "&dlauth=$download->{dlauth}";
        if ($download->{offset}) {
            print YELLOW "Found temp file '$temp_file' with $download->{offset} bytes. Resuming..." and print "\n";
            $url .= "&start=$download->{offset}";
        }
        open(DOWN_FH, ">>", $temp_file) or die $!;
        print "** Downloading '$download->{filename}', $total_size bytes.\n";
        # We will add every chunk to our File Handle.
        $response = $ua->get( $url
                            , ':content_cb' => sub { my ( $chunk ) = @_; print DOWN_FH $chunk; }
                            );
        close(DOWN_FH);
        my $down_digest = uc(&md5_digest($temp_file))." $download->{filename}";
        if ("$download->{md5hex} $download->{filename}" eq $down_digest) {
            print GREEN "Checksum OK on '$temp_file', moving it to '$download->{filename}' and creating '$download->{filename}.md5'." and print "\n";
            open(DIGEST_FH, ">", "$download->{filename}.md5") or die $!;
            print DIGEST_FH "$down_digest\n";
            close(DIGEST_FH);
            move($temp_file, $download->{filename});
        } else {
            print BOLD RED "Checksum FAILED on '$temp_file', the good MD5 was '$download->{md5hex}'. Leaving the file \"as is\"." and print "\n";
        }
    } else {
        my $content = $response->content;
        print BOLD RED "Error getting a download token for '$download->{filename}', the response was '$content'" and print "\n";
    }
}
exit 0;
