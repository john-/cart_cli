package Cart::CartModel;

use DBI;
use Data::Dumper;
use feature say;
use File::Slurp;
use Time::Piece;
use FindBin qw($Bin);;

sub new {
    my $class = shift;

    my $self = {
        dbh => DBI->connect(
            "dbi:Pg:dbname=cart", 'script', '', { AutoCommit => 1 }
        ),
        config => eval( read_file("$Bin/../conf/cart_cli.conf") ),
    };
    bless( $self, $class );
    return ($self);
}

sub get_ranges {
    my $self = shift;

    my @ranges = sort( keys( %{ $self->{config}{ranges} } ) );

    return \@ranges;
}

sub summary {
    my ( $self, $range ) = @_;

    my $dbh = $self->{dbh};

    my %entry = %{ $self->{config}{ranges}{$range} };

    my %sum_queries = %{ $self->{config}{sum_queries} };

    my %result;
    foreach my $query ( keys %sum_queries ) {
        $result{$query} = $dbh->selectall_arrayref(
            $sum_queries{$query}, { Slice => {} },
            $entry{start}, $entry{end}
        );
    }

    $result{parameters}{range} = $range;
    $result{parameters}{dates} = \%entry;

    return \%result;
}

sub clean {
    my ( $self, $range ) = @_;

    my $dbh = $self->{dbh};

    my %entry = %{ $self->{config}{ranges}{$range} };

    my $stmt = 'select xmit_key, file from xmit_history where entered::date between ? and ?';

    my %result;

    $result{parameters}{range} = $range;
    $result{parameters}{dates} = \%entry;

    # rtl_fm-scanner stuff
    
    my $to_delete = $dbh->selectall_arrayref(
        $stmt, { Slice => {} },
        $entry{start}, $entry{end},
    );

    #my $root = '/home/pub/ham2mon/apps/wav';
    my $root = $self->{config}{scanner_dir};;
    $result{parameters}{scanner_dir} = $root;
    my $dh;
    if (!opendir $dh, $root) {
	$result{error} = $!;
	return \%result;
    }
    my @dirs = ( '.', grep {-d "$root/$_" && ! /^\.{1,2}$/} readdir($dh) );

    $stmt = 'delete from xmit_history where xmit_key = ?';
    my $sth = $dbh->prepare($stmt) || do {
	$result{$error} = $dbh->errstr; 
	return \%result;
    };
    
    my $file_del = 0;
    my $rec_del = 0;
    foreach $rec (@$to_delete) {
	foreach my $dir (@dirs) {
	    if (-e "$root/$dir/$rec->{file}") {
		say "deleting file $root/$dir/$rec->{file}";
		if (unlink("$root/$dir/$rec->{file}")) {
                    $file_del++;
		    last;
		}
	    }
	}

	say "deleting record $rec->{xmit_key}";
        $sth->execute($rec->{xmit_key}) || do {
            $result{error} = $dbh->errstr; 
            #return \%result;
        };
	$rec_del++;

    }
    
    $result{stats}{xmit_records_in_range} = scalar(@$to_delete);
    $result{stats}{xmit_files_deleted} = $file_del;
    $result{stats}{xmit_records_deleted} = $rec_del;
    $result{stats}{xmit_dirs} = \@dirs;

    # data_gather stuff
    $stmt = 'delete from sensor_history where recorded_at::date between ? and ?';
    my $hist_del = $dbh->do($stmt, undef, $entry{start}, $entry{end}) || do {
	$result{$error} = $dbh->errstr; 
	return \%result;
    };
    
    $result{stats}{gather_records_deleted} = $hist_del+0;

    my $FORMAT_IN  = '%Y-%m-%d';
    my $FORMAT_OUT = '%Y%m%d';

    my $start_t = Time::Piece->strptime( $entry{start}, $FORMAT_IN );
    my $end_t = Time::Piece->strptime( $entry{end}, $FORMAT_IN );

    my $gps_dir = $self->{config}{gps_dir};
    $result{parameters}{gps_dir} = $gps_dir;

    my $gps_files = 0;
    my $gps_del   = 0;
    while ( $start_t <= $end_t ) {
	my $date = $start_t->strftime($FORMAT_OUT);
	my @files = glob("$gps_dir/$date-*");
	foreach $file (@files) {
	    $gps_files++;
	    if (unlink($file)) {
                $gps_del++;
	    }
	}
        #print $start_t->strftime($FORMAT_OUT), "\n";
        $start_t += 60 * 60 * 24;
    }    

    $result{stats}{gather_gps_files_in_range} = $gps_files;
    $result{stats}{gather_gps_files_deleted} = $gps_del;
    
    return \%result;
 }

sub prune {   # remove wav files that do not have record in db
    my ( $self, $dir ) = @_;

    my %result;

    if (!opendir $dh, $dir) {
	$result{error} = $!;
	return \%result;
    }
    my @files = grep {/^.*\.wav$/} readdir($dh);

    my $dbh = $self->{dbh};
    my $stmt = 'select from xmit_history where file = ?';
    my $sth = $dbh->prepare($stmt) || do {
	$result{$error} = $dbh->errstr; 
	return \%result;
    };

    my $file_del = 0;
    my $failed_del = 0;
    foreach my $file (@files) {
        $sth->execute($file) || do {
            $result{error} = $dbh->errstr; 
            #return \%result;
        };
	my $hash_ref = $sth->fetchrow_hashref;
	if (! $hash_ref) {
	    if (unlink("$dir/$file")) {
                $file_del++;
		say "deleted: $dir/$file";
	    } else {
		$failed_del++;
		say "could not delete: $dir/$file";
	    }
	}
    }

    $result{stats}{total_files} = scalar(@files);
    $result{stats}{files_deleted} = $file_del;
    $result{stats}{failed_deletes} = $failed_del;

    return \%result;
 }

1;
