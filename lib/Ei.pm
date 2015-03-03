package Ei;

use strict;
use warnings;

use File::Kvpar;
use File::Basename qw(dirname);
use File::Spec;

use vars qw($VERSION);

$VERSION = '0.03';

sub new {
    my $cls = shift;
    unshift @_, 'file' if @_ % 2;
    bless { @_ }, $cls;
}

sub file { $_[0]->{'file'} }

sub find {
    my $self = shift;
    my @items = $self->items;
}

sub items {
    my ($self) = @_;
    return @{ $self->{'items'} ||= [ _read_items($self->file) ] };
}

sub _read_items {
    my ($f) = @_;
    open my $fh, '<', $f or die "Can't open $f $!";
    my @items;
    while (<$fh>) {
        next if /^\s*(?:#.*)?$/;
        if (/^!include\s+(\S+)$/) {
            my $source = File::Spec->rel2abs($1, dirname($f));
            my @files = -d $source ? grep { -f } glob("$source/*.ei") : ($source);
            foreach my $f (@files) {
                push @items, _read_items($f);
            }
        }
        elsif (s/^\s*(\S+)\s+(?=\{)//) {
            my $key = $1;
            my $hash = _read_value($_, $fh);
            $hash->{'#'} = $key;
            push @items, $hash;
        }
#       elsif (s/^\s*(\S+)\s+//) {
#           my $key = $1;
#           my $val = _read_value($_, $fh);
#           die "Value $val is not a hash" if ref($val) ne 'HASH';
#           $val->{'#'} = $key;
#           push @items, $val;
#       }
        else {
            die qq{Expected hash element, found "$_"};
        }
    }
    return @items;
}

sub _read_value {
    local $_ = shift;
    my $fh = shift;
    return [ map { trim($_) } split /,\s*/, $1 ] if /^\s*\[(.+)\]\s*$/;
    return { map { my ($k, $v) = split /\s*=\s*/; (trim($k), trim($v)) } split /,\s*/, $1 } if /^\s*\{(.+)\}\s*$/;
    return $1 if /^\s*"(.+)"\s*$/;
    return _read_array($fh)  if /^\s*\[\s*$/;
    return _read_hash($fh)   if /^\s*\{\s*$/;
    return _read_string($fh) if /^\s*\"\s*$/;
    die if !/^\s*=\s*(.*)$/;
    return trim($1);
}

sub _read_array {
    my ($fh) = @_;
    my @array;
    my $i = 0;
    while (<$fh>) {
        next if /^\s*(?:#.*)?$/;
        last if /^\s*\]\s*$/;
        $array[$i++] = _read_value($_, $fh);
    }
    return \@array;
}

sub _read_hash {
    my ($fh) = @_;
    my %hash;
    while (<$fh>) {
        next if /^\s*(?:#.*)?$/;
        last if /^\s*\}\s*$/;
        s/^\s*(\S+)\s+// or die "Not a hash element: $_";
        my $key = $1;
        my $val = _read_value($_, $fh);
        $hash{$key} = $val;
    }
    return \%hash;
}

sub _read_string {
    my ($fh) = @_;
    my @array;
    my $str = '';
    while (<$fh>) {
        last if /^\s*\"\s*$/;
        $str .= $_;
    }
    chomp $str;
    return $str;
}

sub trim {
    local $_ = shift;
    s/^\s+|\s+$//g;
    return $_;
}

1;

=pod

=head1 NAME

Ei - manage an inventory of stuff

=cut

__END__

[47]
descrip = Water heater
purchase {
  date = 2012-2013
  loc = Sears?
}
location = basement

[48]
descrip = 
