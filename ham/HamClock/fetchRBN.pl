#!/usr/bin/env perl
use strict;
use warnings;

use CGI qw(param header);
use LWP::UserAgent;
use URI;
use JSON::PP qw(decode_json);

# ---------------- Config ----------------
my $RBN_BASE        = 'https://www.reversebeacon.net/spots.php';
my $H_VERSION       = '2aa296';
my $DEFAULT_MAXAGE  = 7200;
my $DEFAULT_S       = 0;
my $DEFAULT_R       = 100;
my $TIMEOUT_SEC     = 15;
# ----------------------------------------

binmode STDOUT, ':encoding(ISO-8859-1)';

sub csv_error {
    my ($status, $msg) = @_;
    print header(-type => 'text/plain; charset=ISO-8859-1', -status => $status);
    print "ERROR: $msg\n";
    exit 0;
}

# Maidenhead (6-char) from lat/lon (decimal degrees)
sub latlon_to_maiden6 {
    my ($lat, $lon) = @_;
    return '' if !defined($lat) || !defined($lon);

    # Validate numeric
    return '' if $lat !~ /^-?\d+(\.\d+)?$/ || $lon !~ /^-?\d+(\.\d+)?$/;

    # Shift to positive ranges
    my $A = $lon + 180.0;
    my $B = $lat +  90.0;

    return '' if $A < 0 || $A >= 360 || $B < 0 || $B > 180;

    my $field_lon = int($A / 20);
    my $field_lat = int($B / 10);

    my $rem_lon = $A - ($field_lon * 20);
    my $rem_lat = $B - ($field_lat * 10);

    my $square_lon = int($rem_lon / 2);
    my $square_lat = int($rem_lat / 1);

    $rem_lon = $rem_lon - ($square_lon * 2);
    $rem_lat = $rem_lat - ($square_lat * 1);

    # subsquare is 5 minutes lon (1/24 of 2 degrees) and 2.5 minutes lat (1/24 of 1 degree)
    my $sub_lon = int($rem_lon / (2.0 / 24.0));
    my $sub_lat = int($rem_lat / (1.0 / 24.0));

    my $Achr = chr(ord('A') + $field_lon);
    my $Bchr = chr(ord('A') + $field_lat);
    my $Cchr = $square_lon;
    my $Dchr = $square_lat;
    my $Echr = chr(ord('A') + $sub_lon);
    my $Fchr = chr(ord('A') + $sub_lat);

    return uc("$Achr$Bchr$Cchr$Dchr$Echr$Fchr");
}

# Mode heuristic: FT8/FT4 common dial freqs, else CW
sub guess_mode_from_hz {
    my ($hz) = @_;
    return 'CW' if !defined($hz) || $hz !~ /^\d+$/;

    # Common FT8 dial freqs (Hz). (tolerance allows slight offsets)
    my @ft8 = (
        1840000, 3573000, 5357000, 7074000, 10136000, 14074000,
        18100000, 21074000, 24915000, 28074000, 50313000, 144174000
    );

    # Common FT4 dial freqs (Hz)
    my @ft4 = (
        3568000, 7047000, 10140000, 14080000, 18104000, 21140000, 28180000
    );

    my $tol = 2500; # Hz tolerance

    for my $f (@ft8) {
        return 'FT8' if abs($hz - $f) <= $tol;
    }
    for my $f (@ft4) {
        return 'FT4' if abs($hz - $f) <= $tol;
    }
    return 'CW';
}

# --------- Parse CGI inputs ----------
my @selectors = grep { defined param($_) && length(param($_)) } qw(ofcall bycall ofgrid bygrid);
csv_error(400, "Missing required parameter: one of ofcall, bycall, ofgrid, bygrid") if @selectors == 0;
csv_error(400, "Provide only ONE of: ofcall, bycall, ofgrid, bygrid")                if @selectors > 1;

my $sel_name  = $selectors[0];
my $sel_value = param($sel_name);

my $maxage = param('maxage');
$maxage = $DEFAULT_MAXAGE if !defined($maxage) || $maxage eq '';
csv_error(400, "maxage must be integer seconds") if $maxage !~ /^\d+$/;
$maxage = int($maxage);

# Build query params to RBN
my %q = (
    h  => $H_VERSION,
    ma => $maxage,
    s  => $DEFAULT_S,
    r  => $DEFAULT_R,
);

# Callsign mapping you specified:
# cdx = spotted/DX station, cde = spotter/DE station
if ($sel_name eq 'ofcall' || $sel_name eq 'bycall') {
    csv_error(400, "Invalid callsign format") if $sel_value !~ /^[A-Za-z0-9\/\-]+$/;
    my $call = uc($sel_value);

    if ($sel_name eq 'ofcall') {  # spotted station
        $q{cdx} = $call;
        $q{cde} = '';
    } else {                      # spotter station
        $q{cde} = $call;
        $q{cdx} = '';
    }
}
elsif ($sel_name eq 'ofgrid' || $sel_name eq 'bygrid') {
    # RBN grid params are not confirmed; leaving as an explicit error so you don't get silent wrong results.
    csv_error(400, "Grid filtering not implemented yet: need confirmed RBN parameter names for grid (e.g., gdx/gde or similar).");
}
else {
    csv_error(400, "Unexpected selector parameter");
}

my $uri = URI->new($RBN_BASE);
$uri->query_form(%q);

# --------- Fetch JSON ----------
my $ua = LWP::UserAgent->new(timeout => $TIMEOUT_SEC, agent => 'fetchRBN.pl/1.1');
my $resp = $ua->get($uri);

csv_error(502, "Upstream error: " . $resp->status_line) if !$resp->is_success;

my $raw = $resp->decoded_content(charset => 'none');
my $data;
eval { $data = decode_json($raw); 1 } or csv_error(502, "Upstream returned non-JSON (or JSON parse failed)");

my $spots     = $data->{spots}     || {};
my $call_info = $data->{call_info} || {};

# Output CSV
print header(-type => 'text/plain; charset=ISO-8859-1', -status => 200);

# spots is a hash keyed by spot id; each value is an array.
# Observed structure includes:
#   [0]=decall (spotter), [1]=freq_khz, [2]=ofcall (spotted), [3]=snr, ... [last]=epoch
for my $id (sort { $a <=> $b } keys %$spots) {
    my $a = $spots->{$id};
    next if ref($a) ne 'ARRAY';

    my $decall = $a->[0] // '';
    my $freq_khz = $a->[1] // '';
    my $ofcall = $a->[2] // '';
    my $snr    = $a->[3];
    my $epoch  = $a->[-1];

    # Convert kHz -> Hz integer
    my $hz = '';
    if (defined $freq_khz && $freq_khz =~ /^-?\d+(\.\d+)?$/) {
        $hz = int($freq_khz * 1000);
    }

    my $mode = guess_mode_from_hz($hz);

    # Compute grids from call_info lat/lon (if present)
    my $ofgrid = '    ';
    if ($ofcall && exists $call_info->{$ofcall} && ref($call_info->{$ofcall}) eq 'ARRAY') {
        my $lat = $call_info->{$ofcall}->[6];
        my $lon = $call_info->{$ofcall}->[7];
        #$ofgrid = latlon_to_maiden6($lat, $lon);
    }

    my $degrid = '';
    if ($decall && exists $call_info->{$decall} && ref($call_info->{$decall}) eq 'ARRAY') {
        my $lat = $call_info->{$decall}->[6];
        my $lon = $call_info->{$decall}->[7];
        $degrid = latlon_to_maiden6($lat, $lon);
    }

    # Final CSV line:
    # epoch_time,ofgrid,ofcall,degrid,decall,mode,hz,snr
    $epoch  = '' if !defined($epoch);
    $snr    = '' if !defined($snr);

    print join(',', $epoch, $ofgrid, $ofcall, $degrid, $decall, $mode, $hz, $snr) . "\n";
}