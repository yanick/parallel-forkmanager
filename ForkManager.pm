=head1 NAME

Parallel::ForkManager - A simple parallel processing fork manager

=head1 SYNOPSIS

  use Parallel::ForkManager;

  $pm=new Parallel::ForkManager($MAX_PROCESSES);

  foreach $data (@all_data) {
    # Forks and returns the pid for the child:
    my $pid=$pm->start and next; 

    ... do some work with $data in the child process ...

    $pm->finish; # Terminates the child process
  }

=head1 DESCRIPTION

This module intends to help parallel-processing operations that can be done parallely, but we want to limit how much process forks for the parallel processing. Typical use is a downloader, which got thousands of links, and tries to download them.

The code for the downloader could look like this:

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
  my $pm=new Parallel::ForkManager(30); 

  foreach my $linkarray (@links) {
    $pm->start and next; # do the fork

    my ($link,$fn)=@$linkarray;
    warn "Cannot get $fn from $link"
      if getstore($link,$fn) != RC_OK;

    $pm->finish; # do the exit in the child process
  }
  $pm->wait_all_childs;

First you need to instantiate the ForkManager with the "new" constructor. You must specify how much parallel process is allowed. If you specify 0, then NO fork will be done, it is good for debugging purposes.

Then $pm->start do the fork. $pm returns 0 for the child process, and child pid for the parent process. That's why "and next" skips the internal loop in the parent process. NOTE: $pm->start dies if the fork failed.

$pm->finish terminates the child process, if a fork has been done in the "start".

NOTE: You cannot use $pm->start, if you already in the child process. If you want to manage another set of subprocesses in the child process, then you must instantiate another Process::ForkManager object!

=head1 METHODS

=over 4

=item new $processes

Instantiate a new Process::ForkManager object. You must specify how much child process can be active parallelly. If you specify , then no child process will be forked, this is intended for debugging purposes.

=item start

This method does the fork. It returns the pid of the child process for the parent, and 0 for the child process. If the $processes parameter for the constructor is 0, then it simply returns 0, assuming that you are in the child process. If you write your code like the above, then you can use the program in single-process mode. All you need to do is make sure after $pm->finish the process can continue the work.

=item finish

Closes the child process by exiting. If you use the program in debug mode ($processes == 0), this method doesn't do anything.

=item wait_all_child

You can call this method to wait for all the processes which has been forked. This is a blocking wait.

=head1 EXPERIMENTAL FEATURES

There are callbacks in the code, which can be called on events like starting a process or on finish. This code is not tested at all, so that's why it is not in the documentation. If you want to use that, please look at the code, and test it. Feel free to send me patches if you find something wrong.
  
=back

=head1 COPYRIGHT

Copyright (c) 2000 Szabó, Balázs (dLux)

All right reserved. This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=head1 AUTHOR

dLux (Szabó, Balázs) <dlux@kapu.hu>

=cut

package Parallel::ForkManager;
use POSIX ":sys_wait_h";
use strict;
use vars qw($VERSION);
$VERSION='0.5';

sub new { my ($c,$processes)=@_;
  my $h={
    max_proc => $processes
  };
  return bless($h,ref($c)||$c);
};

sub run_on_finish { my ($s,$code,$pid)=@_;
  $s->{on_finish}->{$pid || 0}=$code;
}

sub start { my ($s)=@_;
  die "Cannot start another process while you are in the child process"
    if $s->{in_child};
  while ($s->{current}>=$s->{max_proc}) {
    $s->on_wait;
    $s->wait_one_child;
  };
  $s->wait_childs;
  $s->on_start;
  if ($s->{max_proc}) {
    $s->{current}++;
    my $pid=fork();
    die "Cannot fork: $!" if !defined $pid;
    $s->{in_child}=1 if !$pid;
    return $pid;
  } else {
    return 0; # Simulating the child which returns 0
  }
}

sub finish { my ($s)=@_;
  exit 0 if $s->{in_child};
  return 0;
}

sub wait_childs { my ($s)=@_;
  return if !$s->{current};
  my $kid;
  do {
    $kid = $s->wait_one_child(&WNOHANG);
  } while $kid > 0;
};

sub wait_one_child { my ($s,$par)=@_;
  my $kid = waitpid(-1,$par);
  if ($kid>0) {
    $s->on_finish($kid);
    $s->{current}--;
  }
  $kid;
};

sub wait_all_childs { my ($s)=@_;
  $s->wait_one_child while $s->{current};
}

sub on_finish { my ($s,$pid)=@_;
  my $code=$s->{on_finish}->{$pid} || $s->{on_finish}->{0} or return 0;
  $code->($pid);
};

sub on_wait { my ($s)=@_;
  $s->{on_wait}->() if ref($s->{on_wait}) eq 'CODE';
};

sub on_start { my ($s)=@_;
  $s->{on_start}->() if ref($s->{on_start}) eq 'CODE';
};

1;
