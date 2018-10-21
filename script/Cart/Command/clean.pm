# ABSTRACT: Remove unwanted information from DB and directories
package Cart::Command::clean;
use Cart -command;
use Cart::CartModel;
use Data::Dumper;

use feature say;
use YAML::Tiny;

my $cart_info = Cart::CartModel->new;

sub validate_args {
    my ( $self, $opt, $args ) = @_;

    my @ranges = @{ $cart_info->get_ranges };

    if ( (scalar(@$args) != 1) or (!grep /\b$args->[0]\b/, @ranges) ) {
        $self->usage_error("invalid range argument (should be one of \'@ranges\')");
    }
}

sub execute {
    my ( $self, $opt, $args ) = @_;

    #    my $cart_info = Cart::CartModel->new($config);

    #say Dumper($opt->{range});
    my $results = $cart_info->clean( $args->[0] );

    #print "got: " . Dumper($results). "\n";

    my $yaml = YAML::Tiny->new($results);

    say $yaml->write_string;
}

1;
