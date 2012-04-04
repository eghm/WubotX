#!/perl
use strict;
use warnings;

use File::Temp qw/ tempdir /;
use Test::More 'no_plan';

use App::Wubot::Logger;
use App::Wubot::LocalMessageStore;
use App::Wubot::Reactor::WriteFile;

ok( my $writer = App::Wubot::Reactor::WriteFile->new(),
    "Creating new WriteFile reactor object"
);

my $tempdir = tempdir( "/tmp/tmpdir-XXXXXXXXXX", CLEANUP => 1 );

{
    my $path = "$tempdir/file1";

    ok( $writer->react( { a => 'b' }, { file => $path } ),
        "Dumping message to file: $path"
    );

    open(my $fh, "<", $path)
        or die "Couldn't open $path for reading: $!\n";

    local $/ = undef;

    is( <$fh>,
        "---\na: b\n",
        "Validating file contents"
    );

    close $fh or die "Error closing file: $!\n";

}

{
    my $path = "$tempdir/file2";

    ok( $writer->react( { a => 'b', abc => 'xyz' }, { file => $path } ),
        "Dumping message to file: $path"
    );

    open(my $fh, "<", $path)
        or die "Couldn't open $path for reading: $!\n";

    local $/ = undef;

    is( <$fh>,
        "---\na: b\nabc: xyz\n",
        "Validating file contents"
    );

    close $fh or die "Error closing file: $!\n";

}


{
    my $path = "$tempdir/file3";

    ok( $writer->react( { a => 'b', abc => 'xyz' }, { file => $path, source_field => 'abc' } ),
        "Dumping message to file: $path"
    );

    open(my $fh, "<", $path)
        or die "Couldn't open $path for reading: $!\n";

    local $/ = undef;

    is( <$fh>,
        "xyz",
        "Validating file contents are 'xyz'"
    );

    close $fh or die "Error closing file: $!\n";

}


{
    my $path = "$tempdir/file4";

    ok( $writer->react( { a => 'b', abc => 'xyz', path => $path }, { path_field => 'path' } ),
        "Dumping message to path_field 'path', set to: $path"
    );

    open(my $fh, "<", $path)
        or die "Couldn't open $path for reading: $!\n";

    local $/ = undef;

    is( <$fh>,
        "---\na: b\nabc: xyz\npath: $path\n",
        "Validating file contents"
    );

    close $fh or die "Error closing file: $!\n";

}


{
    my $path = "$tempdir/file5";

    ok( $writer->react( { a => 'b', abc => 'xyz', path => $path }, { path_field => 'path', source_field => 'abc' } ),
        "Dumping message to path_field 'path', set to: $path"
    );

    open(my $fh, "<", $path)
        or die "Couldn't open $path for reading: $!\n";

    local $/ = undef;

    is( <$fh>,
        "xyz",
        "Validating file contents"
    );

    close $fh or die "Error closing file: $!\n";

}



{
    my $path = "$tempdir/file6";

    open(my $fh1, ">", $path)
        or die "Couldn't open $path for writing: $!\n";
    print $fh1 "ORIGINAL CONTENT";
    close $fh1 or die "Error closing file: $!\n";

    ok( $writer->react( { abc => 'xyz' }, { source_field => 'abc', file => $path } ),
        "pre-existing path without 'overwrite' enabled"
    );

    open(my $fh2, "<", $path)
        or die "Couldn't open $path for reading: $!\n";

    local $/ = undef;

    is( <$fh2>,
        "ORIGINAL CONTENT",
        "Validating file has original content"
    );

    close $fh2 or die "Error closing file: $!\n";

}


{
    my $path = "$tempdir/file7";

    open(my $fh1, ">", $path)
        or die "Couldn't open $path for writing: $!\n";
    print $fh1 "ORIGINAL CONTENT";
    close $fh1 or die "Error closing file: $!\n";

    ok( $writer->react( { abc => 'xyz' }, { source_field => 'abc', file => $path, overwrite => 1 } ),
        "pre-existing path with 'overwrite' enabled"
    );

    open(my $fh2, "<", $path)
        or die "Couldn't open $path for reading: $!\n";

    local $/ = undef;

    is( <$fh2>,
        "xyz",
        "Validating file has original content"
    );

    close $fh2 or die "Error closing file: $!\n";

}
