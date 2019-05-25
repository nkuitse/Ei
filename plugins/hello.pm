package Ei::Plugin::hello;

use base qw(Ei::Plugin);

use strict;
use warnings;

sub commands {
    return (
        'hello' => \&cmd_hello,
    );
}

sub cmd_hello {
    my $self = shift;
    $self->usage('hello [NAME]') if @ARGV > 1;
    @ARGV = qw(world) if !@ARGV;
    print STDERR "Hello @ARGV\n";
}

1;
