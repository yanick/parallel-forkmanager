=head1 NAME

Parallel::ForkManager - A simple parallel processing fork manager

=head1 SYNOPSIS

  use Parallel::ForkManager;

  $pm = new Parallel::ForkManager($MAX_PROCESSES);

  foreach $data (@all_data) {
    # Forks and returns the pid for the child:
    my $pid = $pm->start and next; 

    ... do some work with $data in the child process ...

    $pm->finish; # Terminates the child process
  }

=head1 DESCRIPTION

This module is intended for use in operations that can be done in parallel 
where the number of processes to be forked off should be limited. Typical 
use is a downloader which will be retrieving hundreds/thousands of files.

The code for a downloader would look something like this:

  use LWP::Simple;
  use Parallel::ForkManager;

  ...
  
  @links=( 
    ["http://www.foo.bar/rulez.data","rulez_data.txt"], 
    ["http://new.host/more_data.doc","more_data.doc"],
    ...
  );

  ...

  # Max 30 processes for parallel download
  my $pm = new Parallel::ForkManager(30); 

  foreach my $linkarray (@links) {
    $pm->start and next; # do the fork

    my ($link,$fn) = @$linkarray;
    warn "Cannot get $fn from $link"
      if getstore($link,$fn) != RC_OK;

    $pm->finish; # do the exit in the child process
  }
  $pm->wait_all_children;

First you need to instantiate the ForkManager with the "new" constructor. 
You must specify the maximum number of processes to be created. If you 
specify 0, then NO fork will be done; this is good for debugging purposes.

Next, use $pm->start to do the fork. $pm returns 0 for the child process, 
and child pid for the parent process (see also L<perlfunc(1p)/fork()>). 
The "and next" skips the internal loop in the parent process. NOTE: 
$pm->start dies if the fork fails.

$pm->finish terminates the child process (assuming a fork was done in the 
"start").

NOTE: You cannot use $pm->start if you are already in the child process. 
If you want to manage another set of subprocesses in the child process, 
you must instantiate another Parallel::ForkManager object!

=head1 METHODS

=over 5

=item new $processes

Instantiate a new Parallel::ForkManager object. You must specify the maximum 
number of children to fork off. If you specify 0 (zero), then no children 
will be forked. This is intended for debugging purposes.

=item start

This method does the fork. It returns the pid of the child process for 
the parent, and 0 for the child process. If the $processes parameter 
for the constructor is 0 then, assuming you're in the child process, 
$pm->start simply returns 0.

=item finish [ $exit_code ]

Closes the child process by exiting and accepts an optional exit code 
(default exit code is 0) which can be retrieved in the parent via callback. 
If you use the program in debug mode ($processes == 0), this method doesn't 
do anything.

=item set_max_procs $processes

Allows you to set a new maximum number of children to maintain. Returns 
the previous setting.

=item wait_all_children

You can call this method to wait for all the processes which have been 
forked. This is a blocking wait.

=back

=head1 CALLBACKS

You can define callbacks in the code, which are called on events like starting 
a process or on finish.

The callbacks can be defined with the following methods:

=over 4

=item run_on_finish $code [, $pid ]

You can define a subroutine which is called when a child is terminated. It is
called in the parent process.

The paremeters of the $code are the following:

  - pid of the process, which is terminated
  - exit status
  - identification of the process (if provided in the "start" method)

=item run_on_start $code

You can define a subroutine which is called when a child is started. It called
after the successful startup of a child in the parent process.

The parameters of the $code are the following:

  - pid of the process which has been started

=item run_on_wait $code

You can define a subroutine which is canned when the child process needs to wait
for the startup. One call has been done per children, and this is called only
in the "start" method, it is not called in "wait_all_children".

No parameters are passwd to the $code.

=back

=head1 EXAMPLE

=head2 Parallel get

This small example can be used to get URLs parallelly.

  use Parallel::ForkManager;
  use LWP::Simple;
  my $pm=new Parallel::ForkManager(10);
  for my $link (@ARGV) {
    $pm->start and next;
    my ($fn)= $link =~ /^.*\/(.*?)$/;
    if (!$fn) {
      warn "Cannot determine filename from $fn\n";
    } else {
      $0.=" ".$fn;
      print "Getting $fn from $link\n";
      my $rc=getstore($link,$fn);
      print "$link downloaded. response code: $rc\n";
    };
    $pm->finish;
  };

=head2 Callbacks

Example of a program using callbacks to get child exit codes:

  use strict;
  use Parallel::ForkManager;

  my $max_procs = 5;
  my @names = qw( Fred Jim Lily Steve Jessica Bob Dave Christine Rico Sara );
  # hash to resolve PID's back to child specific information

  my $pm =  new Parallel::ForkManager($max_procs);

  # Setup a callback for when a child finishes up so we can
  # get it's exit code
  $pm->run_on_finish(
    sub { my ($pid, $exit_code, $ident) = @_;
      print "** $ident just got out of the pool ".
        "with PID $pid and exit code: $exit_code\n";
    }
  );

  $pm->run_on_start(
    sub { my ($pid,$ident)=@_;
      print "** $ident started, pid: $pid\n";
    }
  );

  $pm->run_on_wait(
    sub {
      print "** Have to wait for one children ...\n"
    }
  );

  foreach my $child ( 0 .. $#names ) {
    my $pid = $pm->start($names[$child]) and next;

    # This code is the child process
    print "This is $names[$child], Child number $child\n";
    sleep ( 2 * $child );
    print "$names[$child], Child $child is about to get out...\n";
    sleep 1;
    $pm->finish($child); # pass an exit code to finish
  }

  print "Waiting for Children...\n";
  $pm->wait_all_children;
  print "Everybody is out of the pool!\n";

=head1 COPYRIGHT

Copyright (c) 2000 Szabó, Balázs (dLux)

All right reserved. This program is free software; you can redistribute it 
and/or modify it under the same terms as Perl itself.

=head1 AUTHOR

  dLux (Szabó, Balázs) <dlux@kapu.hu>
  Noah Robin <sitz@onastick.net> (documentation tweaks)
  Chuck Hirstius <Chuck.Hirstius@walgreens.com> (callback exit status, example)

=cut

package Parallel::ForkManager;
use POSIX ":sys_wait_h";
use strict;
use vars qw($VERSION);
$VERSION='0.7';

sub new { my ($c,$processes)=@_;
  my $h={
    max_proc   => $processes,
    processes  => {},
    in_child   => 0,
  };
  return bless($h,ref($c)||$c);
};

sub start { my ($s,$identification)=@_;
  die "Cannot start another process while you are in the child process"
    if $s->{in_child};
  while ( ( keys %{ $s->{processes} } ) >=$s->{max_proc}) {
    $s->on_wait;
    $s->wait_one_child;
  };
  $s->wait_children;
  if ($s->{max_proc}) {
    my $pid=fork();
    die "Cannot fork: $!" if !defined $pid;
    if ($pid) {
      $s->{processes}->{$pid}=$identification;
      $s->on_start($pid,$identification);
    } else {
      $s->{in_child}=1 if !$pid;
    }
    return $pid;
  } else {
    $s->{processes}->{$$}=$identification;
    $s->on_start($$,$identification);
    return 0; # Simulating the child which returns 0
  }
}

# finish changed by CAH to accept child's passed in exit code
sub finish { my ($s, $x)=@_;
  if ( $s->{in_child} ) {
    exit $x || 0;
  }
  return 0;
}

sub wait_children { my ($s)=@_;
  return if !keys %{$s->{processes}};
  my $kid;
  do {
    $kid = $s->wait_one_child(&WNOHANG);
  } while $kid > 0;
};

*wait_childs=*wait_children; # compatibility

sub wait_one_child ($;$) { my ($s,$par)=@_;
  my $kid = waitpid(-1,$par||=0);
  if ($kid>0) {
    $s->on_finish($kid, $? >> 8 ,$s->{processes}->{$kid});
    delete $s->{processes}->{$kid};
  }
  $kid;
};

sub wait_all_children { my ($s)=@_;
  $s->wait_one_child while keys %{ $s->{processes} };
}

*wait_all_childs=*wait_all_children; # compatibility;

sub run_on_finish { my ($s,$code,$pid)=@_;
  $s->{on_finish}->{$pid || 0}=$code;
}

sub on_finish { my ($s,$pid,@par)=@_;
  my $code=$s->{on_finish}->{$pid} || $s->{on_finish}->{0} or return 0;
  $code->($pid,@par); 
};

sub run_on_wait { my ($s,$code)=@_;
  $s->{on_wait}=$code;
}

sub on_wait { my ($s)=@_;
  $s->{on_wait}->() if ref($s->{on_wait}) eq 'CODE';
};

sub run_on_start { my ($s,$code)=@_;
  $s->{on_start}=$code;
}

sub on_start { my ($s,@par)=@_;
  $s->{on_start}->(@par) if ref($s->{on_start}) eq 'CODE';
};

sub set_max_procs { my ($s, $mp)=@_;
	$s->{max_proc} = $mp;
}

1;
