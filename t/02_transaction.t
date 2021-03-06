use strict;
use warnings;
use DBIx::Handler;
use Test::More;
use Test::SharedFork;
use Test::Requires 'DBD::SQLite';

my $handler = DBIx::Handler->new('dbi:SQLite:./txn_test.db','','');
isa_ok $handler, 'DBIx::Handler';
isa_ok $handler->dbh, 'DBI::db';

$handler->dbh->do(q{
    create table txn_test (
        name varchar(10) NOT NULL,
        PRIMARY KEY (name)
    );
});

sub set_data {
    my $dbh = shift;
    $dbh ||= $handler->dbh;
    $dbh->do(q{insert into txn_test (name) values ('nekokak')});
}
sub get_data {
    my $dbh = shift;
    $dbh ||= $handler->dbh;
    $dbh->selectall_arrayref('select name from txn_test');
}
sub reset_data {
    my $dbh = shift;
    $dbh ||= $handler->dbh;
    $dbh->do('delete from txn_test');
}

subtest 'do basic transaction' => sub {
    $handler->txn_begin;

        set_data();
        is +get_data()->[0]->[0], 'nekokak';

    $handler->txn_commit;

    is +get_data()->[0]->[0], 'nekokak';
    reset_data();
};

subtest 'do rollback' => sub {
    $handler->txn_begin;

        set_data();
        is +get_data()->[0]->[0], 'nekokak';

    $handler->txn_rollback;

    isnt +get_data()->[0]->[0], 'nekokak';
    reset_data();
};

subtest 'error occurred in transaction' => sub {
    eval {
        local $SIG{__WARN__} = sub {};
        my $txn = $handler->txn_scope;
        $handler->{_pid} = 666;
        $handler->dbh;
    };
    my $e = $@;
    like $e, qr/Detected transaction during a connect operation \(last known transaction at/;
};

subtest 'call_txn_scope_after_fork' => sub {

    subtest 'commit' => sub {
        if (fork) {
            wait;
            is +get_data()->[0]->[0], 'nekokak';
            reset_data();
        } else {
            my $txn = $handler->txn_scope;
                set_data();
                is +get_data()->[0]->[0], 'nekokak';
            $txn->commit;
            is +get_data()->[0]->[0], 'nekokak';
            exit;
        }
    };

    subtest 'rollback' => sub {
        if (fork) {
            wait;
            isnt +get_data()->[0]->[0], 'nekokak';
            reset_data();
        } else {
            my $txn = $handler->txn_scope;
                set_data();
                is +get_data()->[0]->[0], 'nekokak';
            $txn->rollback;
            isnt +get_data()->[0]->[0], 'nekokak';
            exit;
        }
    };
};

subtest 'txn' => sub {
    my $get_name = $handler->txn(
        sub {
            my $dbh = shift;
            set_data($dbh);
            my $name = get_data($dbh)->[0]->[0];
            is $name, 'nekokak';
            $name;
        }
    );
    is $get_name, 'nekokak';
    is +get_data()->[0]->[0], 'nekokak';
    reset_data();

    my @rets = $handler->txn(
        sub {
            my $dbh = shift;
            set_data($dbh);
            my $name = get_data($dbh)->[0]->[0];
            is $name, 'nekokak';
            ('ok', $name);
        }
    );
    is_deeply \@rets, ['ok', 'nekokak'];
    is +get_data()->[0]->[0], 'nekokak';
    reset_data();

    @rets = $handler->txn(
        sub {
            my $dbh = shift;
            set_data($dbh);
            my $name = get_data($dbh)->[0]->[0];
            is $name, 'nekokak';
            wantarray ? ('ok', $name) : ['ok', $name];
        }
    );
    is_deeply \@rets, ['ok', 'nekokak'];
    is +get_data()->[0]->[0], 'nekokak';
    reset_data();

    my $rets = $handler->txn(
        sub {
            my $dbh = shift;
            set_data($dbh);
            my $name = get_data($dbh)->[0]->[0];
            is $name, 'nekokak';
            wantarray ? ('ok', $name) : ['ok', $name];
        }
    );
    is_deeply $rets, ['ok', 'nekokak'];
    is +get_data()->[0]->[0], 'nekokak';
    reset_data();

    eval {
        $handler->txn(
            sub {
                my $dbh = shift;
                set_data($dbh);
                is +get_data($dbh)->[0]->[0], 'nekokak';
                die 'oops';
            }
        );
    };
    ok $@, 'oops';
    isnt +get_data()->[0]->[0], 'nekokak';
    reset_data();
};

unlink './txn_test.db';

done_testing;
