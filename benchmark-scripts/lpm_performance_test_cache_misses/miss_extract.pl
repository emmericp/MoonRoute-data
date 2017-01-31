#!/usr/bin/perl
use strict;
use warnings;
use Data::Dumper;
 
#my $filename = $ARGV[0];
#open(my $fh, '<', $filename)
#  or die "Could not open file '$filename' $!";
 
my %hash = ();

while (my $row = <STDIN>) {

  if($row =~ /^(\d*),(.*)$/){
    print("$ARGV[0]_$2] $1\n");
  }
  #print("$input, $output, $run, $mac, $rate\n");
  #print " parsed: $cfg $run $mac $rate\n";


  #chomp $row;
  #my @array = split /\s+/, $row;

  ##compute mean:
  #my $avg = 0;
  #for (my $i=1; $i <= $#array; $i++) {
  #  $avg += $array[$i];
  #}
  #$avg = $avg / $#array;

  ##compute std deviv:
  #my $drv = 0;
  #for (my $i=1; $i <= $#array; $i++) {
  #  $drv += ($avg - $array[$i])**2;
  #  #print "drv = $drv\n";
  #}
  #$drv = $drv / $#array;
  #$drv = sqrt($drv);

  #print "$array[0] $avg $drv\n";
}
#print "aaa:", Dumper(\%hash), "\n";


