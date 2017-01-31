#!/usr/bin/perl
use strict;
use warnings;
use Data::Dumper;
 
my $filename = $ARGV[0];
open(my $fh, '<', $filename)
  or die "Could not open file '$filename' $!";
 
my %hash = ();

while (my $row = <$fh>) {

  $row =~ /^\[cfg_(\d*)_run_(\d*)_(\S*)] .* (\S*) MBit\/s wire rate.$/;
  my $cfg = $1;
  my $run = $2;
  my $mac = $3;
  my $rate = $4;
  if($rate > 1){
    if(exists($hash{$cfg}{$run})){
      $hash{$cfg}{$run} =$hash{$cfg}{$run} +  $rate;
    }else{
      $hash{$cfg}{$run} = $rate;
    }
  }
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


#  my $cfg;
#  my $value;
#  my $run;
#  my $rate;
#  #foreach my $cfg (keys %hash) {
#  #    while (my ($key, $value) = each %{ $hash{$cfg} } ) {
#  #        print "$key = $value \n";
#  #    }
#  #}
#  while (($cfg, $value) = each %hash) {
#    #print $cfg, "\n";
#    #print Dumper($value);
#    #print "test", $value, "\n";
#    my $avg = mean($value);
#    my $drv = var($value);
#    print "$cfg $avg $drv\n";
#    #while (($run, $rate) = each %{ $value }) {
#    #  print $rate, "\n";
#    #}
#  
#  }
foreach my $cfg (sort keys %hash) {
  #print $cfg, "\n";
  #print Dumper($value);
  #print "test", $value, "\n";
  my $value = $hash{$cfg};
  my $avg = mean($value);
  my $drv = var($value);
  print "$cfg $avg $drv\n";
  #while (($run, $rate) = each %{ $value }) {
  #  print $rate, "\n";
  #}

}




sub var{
  #compute mean:
  my ($ref) = @_;
  #print "ref var:", Dumper(\$ref), "\n";
  my %hash = %$ref;
  #%(@a[1]); 
  my $key;
  my $value;
  my $i = 0;
  my $avg = mean(@_);
  my $drv = 0;
  #print "aaa:", Dumper(\%hash), "\n";
  while (($key, $value) = each %hash) {
    $i = $i+1;
    $drv += ($avg - $value)**2;
  }

  return sqrt($drv/$i);




  #my $key;
  #my $value;
  #my $i = 0;
  #my $avg = mean($_[1]);
  #my $drv = 0;
  #while (($key, $value) = each %{ $_[1] }) {
  #  $i = $i+1;
  #  $drv += ($avg - $value)**2;
  #}

  #return sqrt($drv/$i);
}

sub mean{
  #compute mean:
  my ($ref) = @_;
  #print "ref mean:", Dumper(\$ref), "\n";
  my %hash = %$ref;
  #%(@a[1]); 
  my $key;
  my $value;
  my $i = 0;
  my $avg = 0;
  #print "aaa:", Dumper(\%hash), "\n";
  while (($key, $value) = each %hash) {
    $i = $i+1;
    $avg = $avg + $value;
  }

  return $avg/$i;
}
