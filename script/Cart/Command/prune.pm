# ABSTRACT: Remove files that do not have an entry in DB
package Cart::Command::prune;
use Cart -command;
use Cart::CartModel;
use Data::Dumper;

use feature say;
use YAML::Tiny;

my $cart_info = Cart::CartModel->new;

sub validate_args {
    my ( $self, $opt, $args ) = @_;

    #my @ranges = @{ $cart_info->get_ranges };

    if (scalar(@$args) != 1) {
        $self->usage_error("must specify the directory to prune");
    }

    open FILE, "$args->[0]" || do {
        $self->usage_error("could not open directory $args->[0]");
    };
}

sub execute {
    my ( $self, $opt, $args ) = @_;

    #    my $cart_info = Cart::CartModel->new($config);

    #say Dumper($opt->{range});
    my $results = $cart_info->prune( $args->[0] );

    #print "got: " . Dumper($results). "\n";

    my $yaml = YAML::Tiny->new($results);

    say $yaml->write_string;
}

1;
