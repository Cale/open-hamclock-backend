#!/usr/bin/perl
use strict;
use warnings;
use LWP::UserAgent;
use HTML::Entities;
use Time::Piece;
use Encode;

# Fetch source
my $url = 'https://www.ng3k.com/Misc/adxo.html';

my $ua = LWP::UserAgent->new(
    timeout => 15,
    agent   => 'Mozilla/5.0',
);

my $resp = $ua->get($url);
die "NG3K FETCH FAILED: " . $resp->status_line . "\n"
    unless $resp->is_success;

my $html = $resp->decoded_content;

my $today = localtime;
my $max   = 5;
my $count = 0;

while ($html =~ m{
    <tr\s+class="adxoitem".*?>
    \s*<td\s+class="date">(\d{4})\s+([A-Za-z]{3})(\d{2})</td>
    \s*<td\s+class="date">\d{4}\s+([A-Za-z]{3})(\d{2})</td>
    \s*<td\s+class="cty">(.*?)</td>
    .*?
    <span\s+class="call">(.*?)</span>
    .*?
    <td\s+class="qsl">(.*?)</td>
}gxs) {

    last if $count >= $max;

    my ($year, $smon, $sday, $emon, $eday, $entity, $call_html, $qsl) =
        ($1, $2, $3, $4, $5, $6, $7, $8);

    # Normalize days
    $sday =~ s/^0//;
    $eday =~ s/^0//;

    decode_entities($entity);
    decode_entities($qsl);

    # Strip HTML from callsign
    $call_html =~ s/<[^>]+>//g;
    $call_html =~ s/^\s+|\s+$//g;

    # Date objects
    my $start = Time::Piece->strptime(
        "$year $smon $sday", "%Y %b %d"
    );
    my $end = Time::Piece->strptime(
        "$year $emon $eday", "%Y %b %d"
    );

    # Option B: only currently active
    next if $today < $start || $today > $end;

    my $line =
        "NG3K.com: $entity: "
      . "$smon $sday $emon $eday, $year "
      . "-- $call_html -- QSL via: $qsl\n";

    # Final output encoding for HamClock compatibility
    print Encode::encode('ISO-8859-1', $line);

    $count++;
}

