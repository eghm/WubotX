package App::Wubot::Util::TagPredict;
use Moose;

# VERSION

use HTML::Strip;
use DB_File;

use App::Wubot::Logger;

has 'dbfile'   => ( is      => 'ro',
                    isa     => 'Str',
                    lazy    => 1,
                    default => sub {
                        return join( "/", $ENV{HOME}, "wubot", "sqlite", "TagPredict.db" );
                    },
                );

has 'db'       => ( is      => 'ro',
                    lazy    => 1,
                    default => sub {
                        my $self = shift;
                        my %hash;
                        dbmopen %hash, $self->dbfile, 0666
                             or die "Can't open db file";
                        return \%hash;
                    },
                );

has 'stripper' => ( is      => 'ro',
                    isa     => 'HTML::Strip',
                    lazy    => 1,
                    default => sub {
                        return HTML::Strip->new();
                    },
                );

has 'logger'   => ( is      => 'ro',
                    isa     => 'Log::Log4perl::Logger',
                    lazy    => 1,
                    default => sub {
                        return Log::Log4perl::get_logger( __PACKAGE__ );
                    },
                );

my %skip_words = (
    the => 1,
    was => 1,
    were => 1,
    with => 1,
    you => 1,
    your => 1,
    and => 1,
    for  => 1,
    that => 1,
    how => 1,
    this => 1,
    but => 1,
    not => 1,
    are => 1,
    can => 1,
    have => 1,
    its => 1,
    what => 1,
    should => 1,
    http => 1,
    from => 1,
    more => 1,
    when => 1,
    has => 1,
    about => 1,
    than => 1,
    get => 1,
    out => 1,
    using => 1,
    which => 1,
    will => 1,
    way => 1,
    other => 1,
    all => 1,
    into => 1,
    does => 1,
    they => 1,
    doesnt => 1,
    all => 1,
    those => 1,
    while => 1,
    their => 1,
    thats => 1,
    just => 1,
    there => 1,
    our => 1,
    over => 1,
    also => 1,
    any => 1,
    like => 1,
    use => 1,
);

# short
    # a   => 1,
    # an  => 1,
    # is  => 1,
    # be  => 1,
    # i => 1,
    # in  => 1,
    # on  => 1,
    # of  => 1,
    # it  => 1,
    # if  => 1,
    # by  => 1,
    # on  => 1,
    # to => 1,


sub count_words {
    my ( $self, @content ) = @_;

    my $num_words = 0;

    my %words;

    for my $content ( @content ) {
        next unless $content;

        chomp $content;

        $content = $self->stripper->parse( $content );

      WORD:
        for my $word ( split /[\s+\=\/\-]/, $content ) {

            $word = lc( $word );

            $word =~ tr/a-z0-9\.//cd;
            $word =~ s|[^a-z0-9]+$||;

            next unless $word;

            next WORD if $skip_words{ $word };
            next unless length( $word ) > 2;

            #next if $word =~ m|^\d\d?$|;

            $words{$word}++;

            $num_words++;
        }
    }

    $words{_TOTAL_} = $num_words;

    return \%words;
}

# store counts for a document
sub store {
    my ( $self, $words, @tags ) = @_;

    push @tags, '_TOTAL_';

    unless ( scalar @tags ) {
        $self->logger->logdie( "ERROR: no tags specified to store() method!" );
    }

    # subtract 1 for the _TOTAL_ entry
    my $number_words = 0;
    for my $word ( keys %{ $words } ) {
        next if $word eq "_TOTAL_";
        $number_words += $words->{$word};
    }

    for my $tag ( @tags ) {

        my $count_tag_word = $self->db->{"count_tag_word:$tag"} || 0;
        $self->db->{"count_tag_word:$tag"} = $count_tag_word + $number_words;

        my $count_doc_tag = $self->db->{"count_tag_doc:$tag"} || 0;
        $self->db->{"count_tag_doc:$tag"} = $count_doc_tag + 1;

        for my $word ( keys %{ $words } ) {

            my $count_tag_word = $self->db->{"count_tag_word:$tag:$word"} || 0;
            $self->db->{"count_tag_word:$tag:$word"} = $count_tag_word + $words->{$word};

        }

        $self->add_tag( $tag );
    }

    for my $word ( keys %{ $words } ) {
        next if $word eq "_TOTAL_";

        my $unique_word_count = $self->db->{"unique_word_count:$word"} || 0;

        if ( $unique_word_count ) {
            $self->db->{"unique_word_count:$word"} = $unique_word_count + 1;
        }
        else {
            $self->db->{"unique_word_count:$word"} = 1;

            my $unique_word_count_total = $self->db->{"unique_word_count:_TOTAL_"} || 0;
            $self->db->{"unique_word_count:_TOTAL_"} = $unique_word_count_total + 1;
        }
    }

    return 1;
}

# add a tag to the list of tags
sub add_tag {
    my ( $self, $tag ) = @_;

    return if $tag eq "_TOTAL_";

    my $taglist = $self->db->{'taglist'} || "";

    for my $got_tag ( split /,/, $taglist ) {
        return if $got_tag eq $tag;
    }

    $self->logger->warn( "Adding new tag: $tag" );

    if ( $taglist ) {
        $taglist = join( ",", $taglist, $tag );
    }
    else {
        $taglist = $tag;
    }

    $self->db->{'taglist'} = $taglist;

    return 1;
}

sub remove {
    my ( $self, $words, @tags ) = @_;

    # todo: reverse of store()
}

sub predict_tags {
    my ( $self, $words, $options ) = @_;

    my $unique_word_count = $self->db->{"unique_word_count:_TOTAL_"};
    my $count_total_doc   = $self->db->{"count_tag_doc:_TOTAL_"};
    my $count_total_words = $self->db->{"count_tag_word:_TOTAL_"};

    my $return;

  TAG:
    for my $tag ( split /,/, $self->db->{taglist} ) {

        my $count_tag_doc     = $self->db->{"count_tag_doc:$tag"} || 0;
        my $count_notag_doc   = $count_total_doc - $count_tag_doc;

        my $count_tag_words   = $self->db->{"count_tag_word:$tag"} || 0;
        my $count_notag_words = $count_total_words - $count_tag_words;

        my $p_tag_top = 1;
        my $p_tag_bot = 1;

      WORD:
        for my $word ( keys %{ $words } ) {
            next WORD if $word eq "_TOTAL_";
            next WORD if $skip_words{ $word };

            my $count_total_word = $self->db->{"count_tag_word:_TOTAL_:$word"} || 1;
            my $count_tag_word   = $self->db->{"count_tag_word:$tag:$word"} || 0;
            my $count_notag_word = $count_total_word - $count_tag_word;

            # p( $word | tag )
            $p_tag_top *= ( $count_tag_word + 1 ) / ( $count_tag_words + $unique_word_count );

            # p( $word | -tag )
            $p_tag_bot *= ( $count_notag_word + 1 ) / ( $count_notag_words + $unique_word_count );
        }

        # p(tag)
        $p_tag_top *= ( ( $count_tag_doc + 1 ) / ( $count_total_doc + 2 ) );

        # p(-tag)
        $p_tag_bot *= ( ( $count_notag_doc + 1 ) / ( $count_total_doc + 2 ) );

        # p( tag | item )
        next unless $p_tag_top;
        my $result = $p_tag_top / ( $p_tag_top + $p_tag_bot );
        #print "$p_tag_top / ( $p_tag_top + $p_tag_bot )\n";

        if ( $options->{min} ) {
            next unless $result > $options->{min};
        }

        $return->{ $tag } = sprintf( "%0.5f", $result );

    }

    if ( $options->{limit} ) {

        my $count = 0;
        for my $tag ( sort { $return->{$b} <=> $return->{$a} } keys %{ $return } ) {
            $count++;
            next unless $count > $options->{limit};
            delete $return->{ $tag };
        }
    }

    return $return;
}
