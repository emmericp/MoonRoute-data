#!/usr/bin/perl
use strict;
use warnings;
 
my $filename = 'results';
open(my $fh, '<', $filename)
  or die "Could not open file '$filename' $!";
 
while (my $row = <$fh>) {
  chomp $row;
  my @array = split /\s+/, $row;

  #compute mean:
  my $avg = 0;
  for (my $i=1; $i <= $#array; $i++) {
    $avg += $array[$i];
  }
  $avg = $avg / $#array;

  #compute std deviv:
  my $drv = 0;
  for (my $i=1; $i <= $#array; $i++) {
    $drv += ($avg - $array[$i])**2;
    #print "drv = $drv\n";
  }
  $drv = $drv / $#array;
  $drv = sqrt($drv);

  print "$array[0] $avg $drv\n";
}
