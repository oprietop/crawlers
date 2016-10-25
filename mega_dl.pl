#!/usr/bin/perl
# Fetch files from mega.nz, info from http://julien-marchand.fr/blog/using-mega-api-with-python-examples/

use strict;
use warnings;
use bigint; # Support for 64-bit ints
use MIME::Base64 qw(decode_base64url);
use LWP::UserAgent;
use Crypt::Mode::CTR; # aes-128-ctr for the file encode
use Crypt::Mode::CBC; # aes-256-cbc for the metadata
use Fcntl qw(:flock); # Use the system's File Locking http://www.perlmonks.org/index.pl?node_id=7058

die "Usage: EE $0 'https://mega.nz/#!<ID>!<KEY>'" unless $ARGV[0];
my ($url, $file_id, $file_key) = split('!', $ARGV[0]);
die "EE URL must be of the type 'https://mega.nz/#!<ID>!<KEY>'" unless $file_key;

# Get the key and iv from the private key and initialize the decrypter
my $base        = decode_base64url($file_key);
my @key         = unpack('N*', $base);
my @k           = ($key[0]^$key[4], $key[1]^$key[5], $key[2]^$key[6], $key[3]^$key[7]);
my @vi          = ($key[4], $key[5], 0 ,0);
my @meta_mac    = ($key[6], $key[7]);
my $b64_hex_key = unpack('H*', $base); $b64_hex_key =~ s/(.{32})/$1/mxsg; # http://cpansearch.perl.org/src/POLETTIX/Data-HexDump-XXD-0.1.1/eg/xxd
my $iv          = substr($b64_hex_key, 32, 16).'0'x(16);
my $key         = sprintf ( '%x%x'
                          , hex(substr($b64_hex_key, 0, 16))^hex(substr($b64_hex_key, 32, 16))
                          , hex(substr($b64_hex_key, 16, 16))^hex(substr($b64_hex_key, 48, 16))
                          );

# Fetch the file metadada and download url
my $ua = LWP::UserAgent->new( agent         => 'Mac Safari' # I'm a cool web browser
                            , timeout       => 5            # Idle timeout (Seconds)
                            , show_progress => 1            # Fancy progressbar
                            );
my $seqno = int(rand(9999999999));
my $resp  = $ua->post( "https://g.api.mega.co.nz/cs?id=$seqno"
                     , Content_Type => 'application/x-www-form-urlencoded'
                     , Content      => '[{"a":"g","g":1,"p":"'.$file_id.'"}]'
                     );
my $metadata  = $1 if $resp->decoded_content =~ /"at":"([^"]+)"/;
my $dlurl     = $1 if $resp->decoded_content =~ /"g":"([^"]+)"/;
my $cbc       = Crypt::Mode::CBC->new('AES');
my $plaintext = $cbc->decrypt(decode_base64url($metadata), pack('H*', $key), pack('H*', '0'x(32)));
my $filename  = $1 if $plaintext =~ /"n":"([^"]+)"/;

# Download and decrypt the file on the fly
open(DOWN_FH, '>>', $filename) || die "ER Error '$!' trying to open '$filename', exiting...\n";
if (flock(DOWN_FH, LOCK_EX|LOCK_NB)) { # Locking will allow us to rerun the script on the same url at once.
    my $bytes = -s $filename || 0;
    print "II Found temp file '$filename' with $bytes bytes, resuming...\n" if $bytes;
    my $ctr = Crypt::Mode::CTR->new('AES', 1); # 1 = big-endian
    $ctr->start_decrypt(pack('H*', $key), pack('H*', $iv));
    my $response = $ua->get( $dlurl
                           , ':content_cb' => sub { my ($chunk) = @_; print DOWN_FH $ctr->add($chunk); }
                           , 'Range' => "bytes=$bytes-"
                           );
    close(DOWN_FH) || die "EE Error '$!' trying to close '$filename', exiting...\n";
    $ctr->finish;
    if ($response->is_success) { # Not checking status 416, we shouldn't hit it.
        $bytes = -s $filename || 0;
        print "II Written '$filename' with $bytes bytes.\n";
    } else {
        print "EE Download error. The status code is: ".$response->status_line."\n";
    }
} else {
    print "WW Could not get an exclusive lock to '$filename': $!, skipping...\n";
}
