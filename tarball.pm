package tarball;

use Exporter 'import';
@EXPORT = qw(
    uri_strip_last
    dist_exists
    src_exists
    fetch_tarball
    extract_tarball
    fetch_and_extract
);
use strict;

our $dist_dir = 'dist';
our $src_dir = 'src';

sub uri_strip_last {
    my $uri = shift;
    my $last = $uri;
    $last =~ s#.*/##g;
    return $last;
}

sub dist_exists {
    my $name = shift;

    if (-e "$dist_dir/$name") {
        return 1;
    } else {
        return 0;
    }
}

sub src_exists {
    my $name = shift;
    $name =~ s/.tar.*//;

    if (-e "$src_dir/$name/.extracted") {
        return 1;
    } else {
        return 0;
    }
}

sub fetch_tarball {
    my $uri = shift;
    my $tarball = uri_strip_last($uri);

    print "downloading $tarball ...\n";
    return system("curl $uri -o $dist_dir/$tarball");
}

sub extract_tarball {
    my $tarball = shift;
    my $name = $tarball;
    $name =~ s/.tar.*//;
    print "extracting $tarball ...\n";
    return system("tar -xf $dist_dir/$tarball -C $src_dir && touch $src_dir/$name/.extracted");
}

sub fetch_and_extract {
    my $uri = shift;
    my $name = uri_strip_last($uri);

    fetch_tarball($uri) if ! dist_exists($name);
    extract_tarball($name) if ! src_exists($name);
}

1;
