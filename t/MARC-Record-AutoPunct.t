# Before 'make install' is performed this script should be runnable with
# 'make test'. After 'make install' it should work as 'perl MARC-Record-AutoPunct.t'

#########################

use strict;
use warnings;
use File::Slurp;
use Data::Dumper;
use Test::More;
use File::Spec::Functions qw( catdir catpath );
use File::Basename;

$Test::Harness::verbose = 1;
BEGIN { use_ok('MARC::Record::AutoPunct') };

my @testFiles = readTests(  catdir( dirname( __FILE__ ), 'tests') );

my @tests;

for my $testFile (@testFiles) {
	my $text = read_file( $testFile ) ;
	my @testcases = split("\n\n\n", $text);

	for my $testcase (@testcases) {
		my ($name, $field1, $field2) = split("\n\n", $testcase);

		my $t = {
			"name" => $name,
			"field1" => $field1,
			"field2" => $field2,
			"file" => $testFile
		};

		if (substr($t->{"name"},0,1) eq '!') {
			runTestCase($t);
			done_testing();
			exit;
		}
		if (substr($t->{"name"},0,1) eq '#') {
			next;
		}

		push(@tests, $t);

	}

}

foreach(@tests) { 
	runTestCase($_);
}


sub runTestCase {
	my $t = shift;
	test($t->{"field1"}, $t->{"field2"}, "$t->{'file'} - $t->{'name'}");	
}

done_testing();


sub test {
	my $from = shift;
	my $to = shift;
	my $name = shift;

	chomp($from);
	chomp($to);

	my $record = new MARC::Record();
	my $field = from_formatted($from);
	$record->append_fields($field);
	MARC::Record::AutoPunct::punc($record);

	ok( $field->as_formatted() eq $to, $name ) or err($to, $field->as_formatted());

	sub err {
		my $expected = shift;
		my $got = shift;
		diag("EXPECTED:");
		diag($expected);
		diag("GOT:");
		diag($got);

	}
}



sub from_formatted {
	my $string = shift;
	$string =~ s/\n$//;

	my @lines = split("\n", $string);
	my $tag = substr($lines[0],0,3);
	my $ind1 = substr($lines[0],4,1);
	my $ind2 = substr($lines[0],5,1);

	my @subfields;
	for my $line (@lines) {
		my $code = substr($line,8,1);
		my $content = substr($line,9);
		push(@subfields, $code, $content);
	}
	return MARC::Field->new($tag, $ind1, $ind2, @subfields);
}



sub readTests {
	my $dir = shift;

	opendir(DIR, $dir) or die $!;

	my @tests;

	while (my $file = readdir(DIR)) {


	    # Use a regular expression to ignore files beginning with a period
	    next if ($file =~ m/^\./);
	    push(@tests, "$dir/$file");

	}

	closedir(DIR);

	return @tests;
}