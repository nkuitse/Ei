package Ei;

use strict;
use warnings;

use File::Kvpar;
use File::Basename qw(dirname);
use File::Spec;

use vars qw($VERSION);

$VERSION = '0.05';

sub new {
    my $cls = shift;
    unshift @_, 'file' if @_ % 2;
    my $self = bless { @_ }, $cls;
    my $conf = $self->_read_config($self->{'config_file'});
    my $root = $self->{'root'} ||= glob($conf->{'files'}{'root'});
    my $file = $self->{'file'} ||= glob($conf->{'files'}{'main'});
    $self->{'file'} = File::Spec->rel2abs($file, $root) if $file !~ m{^/};
    return $self;
}

sub file { $_[0]->{'file'} }

sub find {
    my $self = shift;
    my @items = $self->items;
}

sub items {
    my ($self) = @_;
    return @{ $self->{'items'} ||= [ $self->_read_items($self->file) ] };
}

sub _read_items {
    my ($self, $f) = @_;
    open my $fh, '<', $f or die "Can't open $f $!";
    my @items;
    while (<$fh>) {
        next if /^\s*(?:#.*)?$/;
        if (/^!include\s+(\S+)$/) {
            my $source = File::Spec->rel2abs($1, dirname($f));
            my @files = -d $source ? grep { -f } glob("$source/*.ei") : ($source);
            foreach my $f (@files) {
                push @items, $self->_read_items($f);
            }
        }
        elsif (s/^\s*(?:"(\\.|[^\\"])+"|(\S+))\s+(?=\{)//) {
            my $key = defined $1 ? unquote($1) : $2;
            my $hash = $self->_read_value($_, $fh, $f, $.);
            $hash->{'#'} = $key;
            push @items, $hash;
        }
#       elsif (s/^\s*(\S+)\s+//) {
#           my $key = $1;
#           my $val = $self->_read_value($_, $fh, $f, $.);
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
    my $self = shift;
    local $_ = shift;
    my ($fh, $f, $l) = @_;
    return [ map { trim($_) } split /,/, $1 ] if /^\s*\[(.+)\]\s*$/;
    return { map { my ($k, $v) = split /\s+/; (trim($k), trim($v)) } split /,/, $1 } if /^\s*\{(.+)\}\s*$/;
    return unquote($1) if /^\s*"(.+)"\s*$/;
    return $self->_read_array($fh, $f, $l)  if /^\s*\[\s*$/;
    return $self->_read_hash($fh, $f, $l)   if /^\s*\{\s*$/;
    return $self->_read_string($fh, $f, $l) if /^\s*\"\s*$/;
    #die if !/^(.*)$/;
    return trim($_);
}

sub _read_array {
    my ($self, $fh, $f, $l) = @_;
    my (@array, $ok);
    my $i = 0;
    while (<$fh>) {
        next if /^\s*(?:#.*)?$/;
        $ok = 1, last if /^\s*\]\s*$/;
        $array[$i++] = $self->_read_value($_, $fh, $f, $.);
    }
    die "Unterminated array at line $l of $f" if !$ok;
    return \@array;
}

sub _read_hash {
    my ($self, $fh, $f, $l) = @_;
    my (%hash, $ok);
    while (<$fh>) {
        next if /^\s*(?:#.*)?$/;
        $ok = 1, last if /^\s*\}\s*$/;
        s/^\s*(?:"(\\.|[^\\"])+"|(\S+))(?=\s)//
            or die "Not a hash element: $_";
        my $key = defined $1 ? unquote($1) : $2;
        my $val = $self->_read_value($_, $fh, $f, $.);
        $hash{$key} = $val;
    }
    die "Unterminated hash at line $l of $f" if !$ok;
    return \%hash;
}

sub _read_string {
    my ($self, $fh, $f, $l) = @_;
    my (@array, $ok);
    my $str = '';
    while (<$fh>) {
        $ok = 1, last if /^\s*\"\s*$/;
        $str .= $_;
    }
    die "Unterminated string at line $l of $f" if !$ok;
    chomp $str;
    return $str;
}

sub _read_config {
    my ($self, $f) = @_;
    open my $fh, '<', $f or die "Can't open $f $!";
    while (<$fh>) {
        next if /^\s*(?:#.*)?$/;
        s/^config\s+// or die "Bad config file $f: $_";
        return $self->_read_hash($fh, $f, $.);
    }
}

sub unquote {
    local $_ = shift;
    s/\\(.)/$1/g;
    return $_;
}

sub trim {
    local $_ = shift;
    return '' if !defined;
    s/^\s+|\s+$//g;
    return $_;
}

1;

=pod

=head1 NAME

Ei - manage an inventory of stuff

=cut

__END__

47 {
    descrip = Water heater
    purchase {
        date = 2012-2013
        loc = Sears?
    }
    location = basement
}
