#!/perl
use strict;
use warnings;

use File::Temp qw/ tempdir /;
use Test::More;

for my $lib ( 'Maildir::Lite',
              'MIME::Entity',
              'App::Wubot::Logger',
              'App::Wubot::Reactor::Maildir' ) {

    eval "use $lib";
    plan skip_all => "Failed to load $lib for this test case" if $@;
}

plan 'no_plan';

my $tempdir = tempdir( "/tmp/tmpdir-XXXXXXXXXX", CLEANUP => 1 );

ok( my $maildir = App::Wubot::Reactor::Maildir->new(),
    "Creating new maildir reactor object"
);

{
    my $testmessage1 = { body => 'this is the test body',
                         key  => 'TestCase-test1',
                         lastupdate => time - 60*60*24,
                         plugin => 'App::Wubot::Plugin::RSS',
                         subject => 'this is the subject',
                     };

    ok( $maildir->react( $testmessage1, { path => $tempdir } ),
        "Delivering first test message to Maildir"
    );

}

{
    my $body = <<'BODY';

                                                        <img
src="http://deskwx.weatherbug.com/images/Forecast/icons/cond150.gif" align="left" hspace="7" vspace="2" />

                                                                Partly cloudy. Isolated showers ending. Patchy fog
developing. Lows around 30. Southeast wind to 10 mph.

                                                        <br />
                                                                &nbsp;&nbsp;&nbsp;<a
href="http://web.live.weatherbug.com/forecast/forecast.aspx?zcode=z6286&zip=98367&units=0">7 Day Forecast</a>


BODY

    my $testmessage1 = { body => $body,
                         key  => 'TestCase-test1',
                         lastupdate => time - 60*60*24,
                         plugin => 'App::Wubot::Plugin::RSS',
                         subject => 'this is the subject',
                     };

    ok( $maildir->react( $testmessage1, { path => $tempdir } ),
        "Delivering first test message to Maildir"
    );

}






{
    my $body = <<'BODY';

<div><p>Thanks to <a href="http://search.cpan.org/dist/Catalyst-Stats">Catalyst::Stats</a>, it's already a breeze to profile the
time taken by requests, and last week I found myself looking for the same kind 
of profiling ability for memory usage.  A quick look around made me discover
the dynamic duo <a href="http://search.cpan.org/dist/Catalyst-Plugin-LeakTracker">Catalyst::Plugin::LeakTracker</a> and 
<a href="http://search.cpan.org/dist/Catalyst-Controller-LeakTracker">Catalyst::Controller::LeakTracker</a>, but they were not
exactly what I'm looking for.  So... say <em>hi</em> to <code>Catalyst::Plugin::MemoryUsage</code>. </p>

<p>The plugin is fairly simple, and (or so I hope) provides a good example of how
plugins can wiggle themselves at the different points of a request's
lifecycle. </p>

<h2>Writing the Plugin</h2>

<p>This plugin is all about capturing memory usage. To do that, I decided
to leverage <a href="http://search.cpan.org/dist/Memory-Usage">Memory::Usage</a>.  So my first step was to add a
<code>memory_usage</code> attribute to the application's context object:</p>

<pre class="brush: Perl">
package Catalyst::Plugin::MemoryUsage;

use strict;
use warnings;

use namespace::autoclean;
use Moose::Role;

use Memory::Usage;

has memory_usage =&gt; (
    is =&gt; 'rw',
    default =&gt; sub { Memory::Usage-&gt;new },
);
</pre>

<p>Behavior-wise, I wanted to mirror what the time profiler
already does: sets a baseline when the request begins, records a milestone
for each private action that is hit, and reports the results when the
processing of the request is done.   </p>



BODY

    my $testmessage1 = { body => $body,
                         key  => 'TestCase-test1',
                         lastupdate => time - 60*60*24,
                         plugin => 'App::Wubot::Plugin::RSS',
                         subject => 'this is the subject',
                     };

    ok( $maildir->react( $testmessage1, { path => $tempdir } ),
        "Delivering first test message to Maildir"
    );


}


