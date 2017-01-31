#!/usr/bin/perl

use strict;
use warnings;


#my @connections;
#open(my $in,  "<",  "file")  or die "Can't open file: $!";
print "local errors = {\n";
my $first = "1";
while (<STDIN>){
  if($_ =~ /^#define\s*\S*\s*\D*(\d+)\D*\/\* (.*) \*\//){
    if ($first eq "1"){
      print "  [$1] = \"$2\"";
      $first = "0";
    }else{
      print ",\n  [$1] = \"$2\"";
    }
    #my $name = $1;
    #my $port = $2;
    #my $pin = $3;
    #my $dir = $4;
    #my @con = ($1, $2, $3, $4);
    ##push @connections, [@con];
    ##print "name = $1\n";
    ##print "port = $2\n";
    ##print "pin = $3\n";
    ##print "direction = $dir\n";
    #if($dir eq "i"){
    #  print "// $name (input)\n";
    #}else{
    #  print "// $name (output)\n";
    #}
    #print "#define $name P$port$pin\n";
    #print "#define ${name}_PORT PORT$port\n";
    #print "#define ${name}_DDR DDR$port\n";
    #print "#define ${name}_PIN PIN$port\n";
    #if($dir eq "i"){
    #  print "#define IS_HIGH_${name} (${name}_PIN & (1<<P$port$pin))\n";
    #  print "#define SET_PULLUP_${name} (${name}_PORT |= (1<<P$port$pin))\n";
    #  print "#define CLEAR_PULLUP_${name} (${name}_PORT &= ~(1<<P$port$pin))\n";
    #}else{
    #  print "#define SET_${name} (${name}_PORT |= (1<<P$port$pin))\n";
    #  print "#define CLEAR_${name} (${name}_PORT &= ~(1<<P$port$pin))\n";

    #}
    #print "\n";
  }

}
print "\n}\n"
