package MARC::Record::AutoPunct;

use 5.008008;
use strict;
use warnings;
use MARC::Record;
use Data::Dumper;
use Text::CSV;
use String::Util 'trim';
use File::Spec::Functions qw( catdir catpath );
use File::Basename;

require Exporter;
our @ISA = qw(Exporter);

our $VERSION = '0.01';

my $DEBUG = 0;

my @rules = read_rules( dirname(__FILE__) . "/punctuation.csv");

MARC::Field->allow_controlfield_tags('FMT', 'LLE');

sub punc {
	my $record = shift;
	my @fields = $record->fields();
	for my $field (@fields) {
		punctuateField( $field );	
	}
	
}

sub punctuateField {
	my $field = shift;

	d("Handling field " . $field->tag());

	my @rules = get_rules( $field->tag() );
	if (@rules == 0) {
		d("No matching rules for ". $field->tag() );
		return;
	}

	my @subfields = $field->subfields();
	my $currPortion;
	my $precedingField;
	for my $subfield (@subfields) {
		d("Handling subfield " . $subfield->[0]);
		my $portion = getPortion($subfield, \@rules);
		d("Handling $portion " . $subfield->[0]);

		if ($portion eq 'CF' || $portion eq 'NC') {
			next;
		}

		if (defined($currPortion)) { 

			# portion changed
			if ($currPortion ne $portion) {
				addNamePortionPunctuation( $precedingField );
			} else {
				d("addSubfieldPunctuation " . $subfield->[0]);
				addSubfieldPunctuation( $precedingField, $subfield, \@rules );
			}
		}

		$currPortion = $portion;
		$precedingField = $subfield;
	}

	addNamePortionPunctuation( $precedingField );

	my @sublist = map { @$_ } @subfields;
	my $newField = MARC::Field->new($field->tag(), $field->indicator(1), $field->indicator(2), @sublist);
	
	$field->replace_with($newField);	
}

sub addSubfieldPunctuation {
	my $precedingSubfield = shift;
	my $currentSubfield = shift;
	my $rules = shift;

	d("Handling subfield " . $currentSubfield->[0]);

	my $punctType = getPrecedingPunctuation($currentSubfield, $rules);
	my $exceptions = getExceptions($currentSubfield, $rules);
	
	for my $exceptionFunction (@$exceptions) {
		my $isExceptionCase = $exceptionFunction->($precedingSubfield, $currentSubfield);
		if ($isExceptionCase) {
			return;
		}
	}

	if ($precedingSubfield->[1] =~ m/[\?"\)\]\.\-!,]$/) {

	} else {
		if ($punctType eq 'PERIOD') {
			$precedingSubfield->[1] = $precedingSubfield->[1] . ".";
		}
		if ($punctType eq 'COMMA') {
			if ($currentSubfield->[1] !~ m/^\[/) {
				$precedingSubfield->[1] = $precedingSubfield->[1] . ",";
			}
		}
		if ($punctType eq 'COND_COMMA') {
			if ($precedingSubfield->[1] !~ m/\-$/) {
				$precedingSubfield->[1] = $precedingSubfield->[1] . ",";
			}
		}

	}
}
sub addNamePortionPunctuation {
	my $lastFieldPortionSubfield = shift;
	
	if ($lastFieldPortionSubfield->[1] =~ m/[\?"\)\]\.\-!]$/) {
	} else {
		$lastFieldPortionSubfield->[1] = $lastFieldPortionSubfield->[1] . ".";
	}
}
sub getPrecedingPunctuation {
	my $subfield = shift;
	my $rules = shift;
	
	for my $rule (@$rules) {
		my $np = trim($rule->{'Name portion'});
		$np =~ s/^\$//;

		if ( $np eq $subfield->[0]) {
			return uc($rule->{'preceding_punct'});
		}
	}
	die( "Unknown subfield code: ". $subfield->[0]);
}

sub getExceptions {
	my $subfield = shift;
	my $rules = shift;
	d("Parsing exceptions for $subfield->[0]");
	for my $rule (@$rules) {
		my $np = trim($rule->{'Name portion'});
		$np =~ s/^\$//;

		if ( $np eq $subfield->[0]) {
			return parseExceptions( $rule->{'exceptions / seen examples'});
		}
	}
	die( "Unknown subfield code: ". $subfield->[0]);
}

sub parseExceptions {
	my $expectionsString = shift;
	my @exceptionRules = split("\n", $expectionsString);
	my @exceptionFuncs;

	for my $rule (@exceptionRules) {

		if ($rule =~ /- (.*) if preceded by (.*)/) {
			my $type = uc($1);
			my $precededCode = $2;
			$precededCode =~ s/^\$//;
			
			push(@exceptionFuncs, ifPrecededByException($precededCode, $type));
		}
		
	}
	return \@exceptionFuncs;
}

sub ifPrecededByException {
	my $precededCode = shift;
	my $precededType = shift;

	return sub {		
		my $precededSubField = shift;
		my $currentSubfield = shift;
		d("is ");
		d("$precededCode eq $precededSubField->[0]");
		if ($precededCode eq $precededSubField->[0]) {
			d("Addinng $precededType to $precededSubField->[0]");
			if ($precededType eq 'SEMICOLON') {
				$precededSubField->[1] = $precededSubField->[1] . " ;";
			}
			if ($precededType eq 'COLON') {
				$precededSubField->[1] = $precededSubField->[1] . " :";	
			}
			return 1;
		}
		return 0;
	}
}


sub getPortion {
	my $subfield = shift;
	my $rules = shift;
	

	for my $rule (@$rules) {
		my $np = trim($rule->{'Name portion'});
		$np =~ s/^\$//;
		if ( $np eq $subfield->[0]) {
			return uc($rule->{'portion'});
		}
	}
	die( "Unknown subfield code: ". $subfield->[0]);

}

sub read_rules {
	my $filename = shift;
	my @rules;
	my @rows;
	my $csv = Text::CSV->new( { binary => 1 } )
				or die "Cannot use CSV: ".Text::CSV->error_diag ();
	 
	open my $fh, "<:encoding(utf8)", $filename or die "$!";
	$csv->column_names( $csv->getline( $fh ));

	while ( my $row = $csv->getline_hr( $fh ) ) {
		if ($row->{'Fields'} eq '') { next };

	 	$row->{'Fields'} =~ s/X/./g;
	     
	    push @rules, $row;
	}
	$csv->eof or $csv->error_diag();
	close $fh;

	return @rules;
}

sub get_rules {
	my $tag = shift;
	my @tagRules;
	for my $rule (@rules) {

		if ($tag =~ m/$rule->{'Fields'}/) {
			push @tagRules, $rule;
		}
	}
	return @tagRules;
}

sub d {
	
	my $msg = shift;
	if ($DEBUG) {
		use Test::More;
		diag("$msg\n"); 
	}
}

# Preloaded methods go here.

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

MARC::Record::AutoPunct - Perl extension for blah blah blah

=head1 SYNOPSIS

  use MARC::Record::AutoPunct;
  blah blah blah

=head1 DESCRIPTION

Stub documentation for MARC::Record::AutoPunct, created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.

Blah blah blah.

=head2 EXPORT

None by default.



=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

petuomin, E<lt>petuomin@E<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014 by petuomin

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.18.2 or,
at your option, any later version of Perl 5 you may have available.


=cut
