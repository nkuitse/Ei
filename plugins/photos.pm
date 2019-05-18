package Ei::Plugin::photos;

use strict;
use warnings;

use Graphics::Magick;
use Barcode::ZBar;
use Getopt::Long
    qw(:config posix_default gnu_compat require_order bundling no_ignore_case);

sub new {
    my $cls = shift;
    bless { @_ }, $cls;
}

sub init {
    my ($self) = @_;
    $self->{'zbar'} = Barcode::ZBar::Processor->new;
    return $self;
}

sub commands {
    return (
        'photos' => \&cmd_photos,
        'photo' => \&cmd_photo,
    );
}

sub hooks { }

sub cmd_photos {
    my $self = shift;
    @ARGV = qw(ls) if !@ARGV;
    my $cmd = shift @ARGV;
    my $method = $self->can("cmd_photos_$cmd")
        or Ei::usage();
    $self->$method;
}

sub cmd_photo {
    my $self = shift;
    1;
}

sub cmd_photos_import {
    my $self = shift;
    $self->process(@ARGV);
}

sub process {
    my $self = shift;
    my ($begun, $location, $proto, $item);
    foreach my $file (@_) {
        print STDERR $file, "\n";
        my ($code) = $self->decode($file);
        if (!defined $code) {
            if (defined $item) {
                # Item photo
                save($item, $file);
                print "SAVE $item PHOTO $file\n";
            }
            elsif ($begun) {
                print "ERROR $file\n";
            }
            else {
                print "SKIP $file\n";
            }
        }
        elsif ($code =~ /^i(?:tem)?:(.+)/) {
            $item = $1;
            $location = 'floating' if !defined $location;  # XXX
            print "ITEM $item\n";
        }
        elsif ($code =~ /^n(?:ew)?:(\S+)/) {
            $proto = $1;
            print "NEW $proto\n";
        }
        elsif ($code =~ /^l(?:oc)?:(.+)/) {
            my $l = $1;
            check_location($l);
            $location = $l;
            undef $item;
            print "IN $location\n";
        }
        elsif ($code eq 'c(?:trl)?:begin') {
            $begun = 1;
            undef $location;
            undef $item;
            print "BEGIN\n";
        }
        elsif ($code eq 'ctrl:end') {
            $begun = 0;
            undef $location;
            undef $item;
            print "END\n";
        }
        else {
            # TODO
            print "UNKNOWN $file\n";
        }
    }
}

sub save {
    my ($i, $f) = @_;
    1;
}

sub decode {
    my ($self, $f) = @_;
    my $magick = Graphics::Magick->new;
    my $err = $magick->Read($f);
    Ei::fatal("read $f: $err") if $err;
    Ei::blather("\e[31;1m", $f, "\e[0m : convert...");
    $magick->Scale('geometry' => '800x800');
    $magick->Quantize('colorspace' => 'gray', 'colors' => 256);
    $magick->Set('magick' => 'GRAY');
    my ($w, $h) = $magick->Get(qw(width height));
    my ($data) = $magick->ImageToBlob;
    Ei::fatal("image: $f") if !defined $data;
    Ei::blather(" ${w}x${h} (", length($data), " bytes :");
    Ei::blather(" find barcodes...");
    my $image = Barcode::ZBar::Image->new;
    $image->set_format('Y800');
    $image->set_size($w, $h);
    $image->set_data($data);
    $self->{'zbar'}->process_image($image);
    my @symbols = $image->get_symbols;
    return grep /:/, map { $_->get_data } @symbols;
    Ei::blather(" none found") if !@symbols;
    foreach my $sym (@symbols) {
        Ei::blather(" found ", $sym->get_type, ":\n", $sym->get_data);
    }
    Ei::blather("\n");
}

sub check_location {
    my ($self, $l) = @_;
    my $ei = $self->{'ei'};
    1;
}

1;
