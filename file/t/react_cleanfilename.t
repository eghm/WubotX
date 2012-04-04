#!/perl
use strict;
use warnings;

use File::Temp qw/ tempdir /;
use Test::More 'no_plan';

use App::Wubot::Logger;
use App::Wubot::LocalMessageStore;
use App::Wubot::Reactor::CleanFilename;

ok( my $transformer = App::Wubot::Reactor::CleanFilename->new(),
    "Creating new CleanFilename reactor object"
);

is_deeply( $transformer->react( { file   => 'abc def' },
                                { field  => 'file' }
                            ),
           { file => 'abc_def' },
           "cleaning filename with a space"
       );

is_deeply( $transformer->react( { file   => 'abc  def ghi' },
                                { field  => 'file' }
                            ),
           { file => 'abc_def_ghi' },
           "cleaning filename with multiple spaces"
       );

is_deeply( $transformer->react( { file   => 'abc;!@#$%^&*()+=def.txt' },
                                { field  => 'file' }
                            ),
           { file => 'abc_def.txt' },
           "cleaning filename with special characters"
       );

is_deeply( $transformer->react( { file   => 'abc_____def' },
                                { field  => 'file' }
                            ),
           { file => 'abc_def' },
           "cleaning filename with multiple consecutive underscores"
       );

is_deeply( $transformer->react( { file   => 'ABC.DEF' },
                                { field  => 'file', lc => 1 }
                            ),
           { file => 'abc.def' },
           "cleaning filename with lowercase option set"
       );

is_deeply( $transformer->react( { file   => 'abc/def' },
                                { field  => 'file' }
                            ),
           { file => 'abc_def' },
           "cleaning filename containing directory slash"
       );

is_deeply( $transformer->react( { file   => 'abc/def' },
                                { field  => 'file', directory => 1 }
                            ),
           { file => 'abc/def' },
           "cleaning path with directory option set"
       );
