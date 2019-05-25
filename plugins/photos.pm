package Ei::Plugin::photos;

use base qw(Ei::Plugin);

use strict;
use warnings;

use Text::ParseWords;
use Graphics::Magick;
use Barcode::ZBar;
use Getopt::Long
    qw(:config posix_default gnu_compat require_order bundling no_ignore_case);

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
    $self->dispatch('usage' => 'photos ls|import');
    #my $cmd = shift @ARGV;
    #my $method = $self->can("cmd_photos_$cmd")
    #    or App::ei::usage('photos COMMAND [ARG...]');
    #$self->$method;
}

sub cmd_photo {
    my $self = shift;
    1;
}

sub cmd_photos_ls {
    my $self = shift;
    my $ei = $self->{'ei'};
    my @items = @ARGV ? (map { $ei->item($_) } @ARGV) : ($ei->items);
    my $photos = $self->photos(@items);
    foreach my $item (@items) {
        my $i = $item->{'#'};
        my @photos = @{ $photos->{$i} or next };
        print STDERR $i, ' = ', $item->{'title'} || '(no title)', "\n";
        foreach my $f (@photos) {
            # $f =~ s{.+/}{};
            print $f, "\n";
            STDOUT->flush;
        }
    }
}

sub cmd_photos_view {
    my $self = shift;
    my $ei = $self->{'ei'};
    my $conf = $self->{'config'};
    my @viewer = shellwords($conf->{'viewer'} or $self->fatal('no photo viewer configured'));
    my @items = @ARGV ? (map { $ei->item($_) } @ARGV) : ($ei->items);
    my $photos = $self->photos(@items);
    my @photos;
    foreach my $item (@items) {
        my $i = $item->{'#'};
        print STDERR "no photos for object $i\n", next
            if !$photos->{$i};
        push @photos, @{ $photos->{$i} };
    }
    system(@viewer, @photos);
}

sub cmd_photos_import {
    my $self = shift;
    if (!@ARGV) {
        my $inbox = $self->inbox;
        @ARGV = glob("$inbox/*.jpg");
    }
    $self->process(@ARGV);
}

# --- Other methods

sub root {
    my ($self) = @_;
    my $conf = $self->{'config'};
    my $root = $conf->{'root'}
        or $self->fatal("no root configured for photos plugin");
    my $ei = $self->ei;
    return File::Spec->rel2abs($root, $ei->root);
}

sub inbox {
    my ($self) = @_;
    my $root = $self->root;
    my $inbox = $self->{'config'}{'inbox'};
    if (!defined $inbox) {
        $self->fatal("no inbox configured for photos plugin")
            if !defined $root;
        $inbox = 'inbox';
    }
    $inbox = File::Spec->rel2abs($inbox, $root)
        if defined $root;
    return $inbox;
}

sub photos {
    my $self = shift;
    my $root = $self->root;
    my %photos;
    foreach my $item (@_) {
        my $i = $item->{'#'};
        my @photos = glob("$root/$i/*.*");
        $photos{$item->{'#'}} = \@photos if @photos;
    }
    return \%photos;
}

sub process {
    my $self = shift;
    my $ei = $self->{'ei'};
    my ($begun, $location, $proto, $item);
    foreach my $file (@_) {
        print STDERR $file, "\n";
        my ($code) = $self->decode($file);
        if (!defined $code) {
            if (defined $item) {
                # Item photo
                $self->save($item, $file);
                print "SAVE $item->{'#'} PHOTO $file\n";
            }
            elsif ($begun) {
                print "ERROR $file\n";
            }
            else {
                print "SKIP $file\n";
            }
        }
        elsif ($code =~ /^i(?:tem)?:(.+)/) {
            my $i = $1;
            $item = eval { $ei->item($i) }
                or $self->fatal("item $i does not exist: photo $file");
            $location = 'floating' if !defined $location;  # XXX
            print "ITEM $i\n";
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
    my ($self, $item, $f) = @_;
    my $i = $item->{'#'};
    (my $name = $f) =~ s{.*/}{};
    my $root = $self->root;
    my $dir = $root . '/' . $item->{'#'};
    -d $dir or mkdir $dir or $self->fatal("mkdir $dir: $!");
    my $g = $dir . '/' . $name;
    if (-e $g) {
        $self->fatal("photo file $g already exists, will not overwrite")
            if -s $f != -s $g;
        print STDERR "skipping $f: photo file $g already exists\n";
        return;
    }
    if (!link($f, $g)) {
        File::Copy::copy($f, $g)
            or $self->fatal("copy $f to $g: $!");
    }
}

sub decode {
    my ($self, $f) = @_;
    my $magick = Graphics::Magick->new;
    my $err = $magick->Read($f);
    App::ei::fatal("read $f: $err") if $err;
    App::ei::blather("\e[31;1m", $f, "\e[0m : convert...");
    $magick->Scale('geometry' => '800x800');
    $magick->Quantize('colorspace' => 'gray', 'colors' => 256);
    $magick->Set('magick' => 'GRAY');
    my ($w, $h) = $magick->Get(qw(width height));
    my ($data) = $magick->ImageToBlob;
    App::ei::fatal("image: $f") if !defined $data;
    App::ei::blather(" ${w}x${h} (", length($data), " bytes :");
    App::ei::blather(" find barcodes...");
    my $image = Barcode::ZBar::Image->new;
    $image->set_format('Y800');
    $image->set_size($w, $h);
    $image->set_data($data);
    $self->{'zbar'}->process_image($image);
    my @symbols = $image->get_symbols;
    return grep /:/, map { $_->get_data } @symbols;
    App::ei::blather(" none found") if !@symbols;
    foreach my $sym (@symbols) {
        App::ei::blather(" found ", $sym->get_type, ":\n", $sym->get_data);
    }
    App::ei::blather("\n");
}

sub check_location {
    my ($self, $l) = @_;
    my $ei = $self->{'ei'};
    1;
}

1;
