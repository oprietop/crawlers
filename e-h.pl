#!/usr/bin/perl
# awfully coded e-hentai crawler

use strict;
use utf8;
use Encode;
use WWW::Mechanize;
use HTML::Entities; # decode_entities()
use File::Copy;     # move()
use POSIX qw(strftime);
use Term::ANSIColor qw(:constants);
$Term::ANSIColor::AUTORESET = 1;
use Data::Dumper;

my $mech = WWW::Mechanize->new( autocheck => 0
                              , timeout => 5
                              , agent => 'Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/38.0.2125.111 Safari/537.36' # http://techblog.willshouse.com/2012/01/03/most-common-user-agents/
                              #, show_progress => 1
                              #, onerror => undef
);

my $temp_file   = undef; # Temporal filename of the current download.
my $total_size  = undef; # Total size of the image to be downloaded.
my %error_pages = (); # Hash to fill with failed galleries.

sub rndwait {
    my $first  = shift || 5;
    my $second = shift || 0;
    my $wait_time = int(1+rand($first))+$second; # We do nothing on $first to $first+$second secs.
    print YELLOW "Waiting $wait_time seconds to avoid hammering the site...\n";
    $| = 1;
    sleep $wait_time;
    $| = 0;
}

sub escapename { # http://kobesearch.cpan.org/htdocs/File-Util/File/Util.pm.html#escape_filename-
    my($file, $escape, $also) = @_;
    return '' unless defined $file;
    $escape = '-' if !defined($escape);
    if ($also) { $file =~ s/\Q$also\E/$escape/g }
    my $DIRSPLIT    = qr/[\x5C\/\:]/;
    my $ILLEGAL_CHR = qr/[\x5C\/\|\r\n\t\013\*\"\?\<\:\>]/;
    $file =~ s/$ILLEGAL_CHR/$escape/g;
    $file =~ s/$DIRSPLIT/$escape/g;
    return $file;
}

sub lwp_callback {
    my ($data, $response, $protocol) = @_;
    print DOWN_FH $data if fileno DOWN_FH; # If there's no file handle it means the DL ended.
    my $temp_size = -s $temp_file;
    # wget-style output based on tachyon's code @ http://tachyon.perlmonk.org/
    my $width = 25;
    return unless $total_size;
    printf ( "[%-${width}s] Got %".length ($temp_size)."s bytes of %s (%.2f%%)\r"
           , '=' x (($width-1)*$temp_size/$total_size). '>'
           , $temp_size
           , $total_size
           , 100*$temp_size/+$total_size
           );
}

sub fetch_file {
    my ($url, $file) = @_;
    $temp_file = "$file.part";
    my @mech_params = ( $url,
                      , ':content_cb' => \&lwp_callback
                      );
    my $tries = 3;
    while ($tries) {
        print "Downloading '$file', ".($tries-1)." tries left.\n";
        $mech->head($url);
        if ($mech->success) {
            $total_size = $mech->res->header('Content-Length');
            open(DOWN_FH, ">>$temp_file") || die "ERROR: $!";
            my $bytes = -s $temp_file;
            if ($bytes > 0) {
                print YELLOW "Found temp file '$temp_file' with $bytes bytes. Resuming...\r";
                push(@mech_params, 'Range' => "bytes=$bytes-");
            }
            $mech->get(@mech_params);
            close DOWN_FH;
        }
        # 416 Requested Range Not Satisfiable (file already fully downloaded)
        # 206 Partial Content (The server has fulfilled the partial GET request for the resource)
        if ( $mech->success || $mech->status == 416 ) {
            lwp_callback;
            print "\n";
            move($temp_file, $file);
            return $mech->status;
        }
        $tries--;
        my ($status, $status_line) = ($mech->status, $mech->res->status_line);
        print RED "Error '$status_line' while getting '$file' from '$url'.\n";
        rndwait();
        return $mech->status unless $tries;
    }
}

sub fetch_page {
    my $web_page = shift;
    $mech->get($web_page);
    my $result = decode_entities($mech->content());
    return encode('utf-8', $result) or $mech->res->status_line;
}

foreach my $gallery_url (@ARGV) {
    my $gallery_page = &fetch_page($gallery_url.'?nw=always'); # Avoid content warning
    my $dirname = undef;
    my %local_files = ();
    my %pages = ();

    my $total_images = $1 if $gallery_page =~ /<td class="gdt2">(\d+)\s@/;
    $pages{$2} = $1 while $gallery_page =~ /<a href="(http:[^"]+?)" onclick="return false">(\d+)<\/a>/g;
    my $total_pages = scalar keys %pages;

    print RED "No image pages found!\n" and exit 1 unless $total_pages;##
    print BOLD "#\n# $gallery_url, with $total_images images through $total_pages pages.\n#\n";

#    print Dumper $mech->find_all_links( text_regex => qr/^\d+$/, url_regex => qr/\?p\=\d+/, tag => 'a');

    if ($gallery_page =~ /<title>(.*?) -.+?<\/title>/ and not defined $dirname) {
        $dirname = $1;
        escapename($dirname);
        print "Going into the directory '$ENV{PWD}/$dirname'\n";
        mkdir "$ENV{PWD}/$dirname";
        chdir "$ENV{PWD}/$dirname";
        opendir(DIR, "$ENV{PWD}/$dirname") or print RED "can't opendir '$ENV{PWD}/$dirname': $!\n";
        map { $local_files{$_} = -s $_ } grep { /^\d+_.+$/ && !/^.*part$/i } readdir(DIR);
        my $have_images = scalar keys %local_files;
        print YELLOW "Found $have_images of $total_images images inside.\n" if $have_images;
        if ($have_images >= $total_images) {
            print YELLOW "The gallery seems fully retrieved, skipping...\n";
            next;
        }
    }

    foreach my $current_page (sort {$a <=> $b} keys %pages)  {
        print "# $pages{$current_page} (Page $current_page of $total_pages)\n";
        rndwait();
        $gallery_page = fetch_page($pages{$current_page});
        IMGPAGE: while ($gallery_page =~ /href="(http:\/\/g.e-hentai.org\/s\/.+?)"/g) {
            my $page_url = $1;
            my $curr_img = $1 if $page_url =~ /\-(\d+)$/;
            my ($page_img, $file, $img_url);

            foreach my $local_image (sort {$a <=> $b} keys %local_files) {
                $local_image =~ /^(\d+)_/;
                if ($curr_img == $1) {
                    print YELLOW "We already got the ${curr_img}th image ($local_image) with $local_files{$local_image} bytes.\n";
                    next IMGPAGE;
                }
            }

            until ($img_url) {
                print "Searching images on $page_url\n";
                $page_img = fetch_page($page_url);
                if ($page_img =~ /href="[^"]+".+?src="([^"]+)" style="[^"]+" \/>.+?<div>(.+?) ::/i) {
                    ($img_url, $file) = ($1, $2);
                    if ($page_img =~ /<span>(\d+)<\/span> \/ <span>(\d+)<\/span>/) {
                        $curr_img = $1;
                        $file = sprintf("%0".length($2)."d_$file", $1);
                    }
                } else {
                    print RED "Image not foung on $page_img\n";
                    rndwait();
                }
            }

            if ($img_url =~ /509\w*.gif/) {
                print RED "Bandwidth exceeded! ($page_url)\n";
                $error_pages{$gallery_url} = 1;
            }

            print GREEN "($curr_img/$total_images) Found '$img_url'\n";
            if (! -f "$file") {
                rndwait();
                my $http_code = fetch_file($img_url, $file);
                unless ($mech->success) {
                    print RED "Error fetching $gallery_url\n";
                    $error_pages{$gallery_url} = 1;
                }
            } else {
                print RED "$file already exists, skipping...\n";
            }
        } # while
    } # foreach
} #foreach

if (%error_pages) {
    my $errfile = "last_".strftime("%Y%m%d-%H%M%S", localtime).".txt";
    print RED "Writing failed galleries to $errfile\n";
    open(OUT, ">", "$ENV{PWD}/$errfile") || die "Can't redirect stdout";
    print OUT join("\n", keys %error_pages);
    close(OUT);
}

exit 0;
