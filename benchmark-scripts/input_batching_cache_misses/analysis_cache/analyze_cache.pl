#!/usr/bin/perl
use strict;
use warnings;
use Data::Dumper;
 
my $filename = $ARGV[0];
open(my $fh, '<', $filename)
  or die "Could not open file '$filename' $!";
 
my %hash = ();

while (my $row = <$fh>) {

  $row =~ /^\[input_(\d*)_output_(\d*)_run_(\d*)__(\S*)] (\d*)$/;
  my $input = $1;
  my $output = $2;
  my $run = $3;
  my $class = $4;
  my $rate = $5;
  if($class eq "mem_load_uops_retired_llc_miss"){
    $class = 3;
  }
  if($class eq "mem_load_uops_retired_l2_miss"){
    $class = 2;
  }
  if($class eq "mem_load_uops_retired_l1_miss"){
    $class = 1;
  }
  if($class eq "branch-misses"){
    $class = 0;
  }
  #print("$input, $output, $run, $mac, $rate\n");
  #if($rate > 1){
  #  if(exists($hash{$input}{$output}{$run})){
  #    $hash{$input}{$output}{$run} = $hash{$input}{$output}{$run} +  $rate;
  #  }else{
  #    $hash{$input}{$output}{$run} = $rate;
  #  }
  #}
  $hash{$input}{$class}{$run} = $rate;
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
foreach my $input (sort {$a <=> $b} keys %hash) {
  #print " printing input $input\n";
  foreach my $output (sort {$a <=> $b} keys %{$hash{$input}}) {
    #print $cfg, "\n";
    #print Dumper($value);
    #print "test", $value, "\n";
    my $value = $hash{$input}{$output};
    my $avg = mean($value);
    my $drv = var($value);
    print "$input $avg $drv";
    #while (($run, $rate) = each %{ $value }) {
    #  print $rate, "\n";
    #}
  }
  print "\n"
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

  return sqrt($drv/($i-1));




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
