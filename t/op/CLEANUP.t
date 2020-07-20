#!./perl

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    set_up_inc('../lib');
}

plan 22;

use feature 'cleanup_block';
no warnings 'experimental::cleanup_block';

{
    my $x = "";
    {
        CLEANUP { $x = "a" }
    }
    is($x, "a", 'CLEANUP block is invoked');

    {
        CLEANUP {
            $x = "";
            $x .= "abc";
            $x .= "123";
        }
    }
    is($x, "abc123", 'CLEANUP block can contain multiple statements');

    {
       CLEANUP {}
    }
    ok(1, 'Empty CLEANUP block parses OK');
}

{
    my $x = "";
    {
        CLEANUP { $x .= "a" }
        CLEANUP { $x .= "b" }
        CLEANUP { $x .= "c" }
    }
    is($x, "cba", 'CLEANUP blocks happen in LIFO order');
}

{
    my $x = "";

    {
        CLEANUP { $x .= "a" }
        $x .= "A";
    }

    is($x, "Aa", 'CLEANUP blocks happen after the main body');
}

{
    my $x = "";

    foreach my $i (qw( a b c )) {
        CLEANUP { $x .= $i }
    }

    is($x, "abc", 'CLEANUP block happens for every iteration of foreach');
}

{
    my $x = "";

    my $cond = 0;
    if( $cond ) {
        CLEANUP { $x .= "XXX" }
    }

    is($x, "", 'CLEANUP block does not happen inside non-taken conditional branch');
}

{
    my $x = "";

    while(1) {
        last;
        CLEANUP { $x .= "a" }
    }

    is($x, "", 'CLEANUP block does not happen if entered but unencountered');
}

{
    my $x = "";

    {
        CLEANUP {
            $x .= "a";
            CLEANUP {
                $x .= "b";
            }
        }
    }

    is($x, "ab", 'CLEANUP block can contain another CLEANUP');
}

{
    my $x = "";
    my $sub = sub {
        CLEANUP { $x .= "a" }
    };

    $sub->();
    $sub->();
    $sub->();

    is($x, "aaa", 'CLEANUP block inside sub');
}

{
    my $x = "";
    my $sub = sub {
        return;
        CLEANUP { $x .= "a" }
    };

    $sub->();

    is($x, "", 'CLEANUP block inside sub does not happen if entered but returned early');
}

# Sequencing with respect to variable cleanup

{
    my $var = "outer";
    my $x;
    {
        my $var = "inner";
        CLEANUP { $x = $var }
    }

    is($x, "inner", 'CLEANUP block captures live value of same-scope lexicals');
}

{
    my $var = "outer";
    my $x;
    {
        CLEANUP { $x = $var }
        my $var = "inner";
    }

    is ($x, "outer", 'CLEANUP block correctly captures outer lexical when only shadowed afterwards');
}

{
    our $var = "outer";
    {
        local $var = "inner";
        CLEANUP { $var = "cleanup" }
    }

    is($var, "outer", 'CLEANUP after localization still unlocalizes');
}

{
    our $var = "outer";
    {
        CLEANUP { $var = "cleanup" }
        local $var = "inner";
    }

    is($var, "cleanup", 'CLEANUP before localization overwrites');
}

# Interactions with exceptions

{
    my $x = "";
    my $sub = sub {
        CLEANUP { $x .= "a" }
        die "Oopsie\n";
    };

    my $e = defined eval { $sub->(); 1 } ? undef : $@;

    is($x, "a", 'CLEANUP block still runs during exception unwind');
    is($e, "Oopsie\n", 'Thrown exception still occurs after CLEANUP');
}

{
    my $sub = sub {
        CLEANUP { die "Oopsie\n"; }
        return "retval";
    };

    my $e = defined eval { $sub->(); 1 } ? undef : $@;

    is($e, "Oopsie\n", 'CLEANUP block can throw exception');
}

{
    my $sub = sub {
        CLEANUP { die "Oopsie 1\n"; }
        die "Oopsie 2\n";
    };

    my $e = defined eval { $sub->(); 1 } ? undef : $@;

    # TODO: Currently the first exception gets lost without even a warning
    #   We should consider what the behaviour ought to be here
    # This test is happy for either exception to be seen, does not care which
    like($e, qr/^Oopsie \d\n/, 'CLEANUP block can throw exception during exception unwind');
}

{
    my $sub = sub {
        while(1) {
            CLEANUP { return "retval" }
            last;
        }
        return "wrong";
    };

    my $e = defined eval { $sub->(); 1 } ? undef : $@;
    like($e, qr/^Can't "return" out of a CLEANUP block /,
        'Cannot return out of CLEANUP block');
}

{
    my $sub = sub {
        while(1) {
            CLEANUP { goto HERE }
        }
        HERE:
    };

    my $e = defined eval { $sub->(); 1 } ? undef : $@;
    like($e, qr/^Can't "goto" out of a CLEANUP block /,
        'Cannot goto out of CLEANUP block');
}

{
    my $sub = sub {
        LOOP: while(1) {
            CLEANUP { last LOOP }
        }
    };

    my $e = defined eval { $sub->(); 1 } ? undef : $@;
    like($e, qr/^Can't "last" out of a CLEANUP block /,
        'Cannot last out of CLEANUP block');
}
