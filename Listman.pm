# Listman.pm - this file is part of the CGI::Listman distribution
#
# CGI::Listman is Copyright (C) 2002 iScream multimédia <info@iScream.ca>
#
# This package is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# Author: Wolfgang Sourdeau <Wolfgang@Contre.COM>

# For a schematic description of the classes implemented in this file,
# have a look at the file "schema.txt".

package CGI::Listman;

use strict;

use Carp;
use DBI;

use vars qw($VERSION);

$VERSION = '0.02';

sub new {
  my $class = shift;

  my $self = {};
  $self->{'dbi_backend'} = shift;
  $self->{'list_name'} = shift;
  $self->{'list_dir'} = shift;
  $self->{'table_name'} = $self->{'list_name'};
  $self->{'db_name'} = undef;
  $self->{'db_uname'} = undef;
  $self->{'db_passwd'} = undef;
  $self->{'db_host'} = undef;
  $self->{'db_port'} = undef;

  $self->{'list'} = undef;
  $self->{'_dbi_params'} = undef;
  $self->{'_dictionary'} = undef;
  $self->{'_last_line_number'} = 0;
  $self->{'_loading_list'} = undef;

  bless $self, $class;
}

sub set_backend {
  my ($self, $backend) = @_;

  if (defined $self->{'dbi_backend'}) {
    print STDERR "A backend is already defined ("
      .$self->{'dbi_backend'}.") for this CGI::Listman instance.\n"
  } else {
    eval "use DBD::".$backend.";";
    die "This backend is not available:\n".$@ if ($@);
    $self->{'dbi_backend'} = $backend;
  }
}

sub set_list_name {
  my ($self, $list_name) = @_;

  if (defined $self->{'list_name'}) {
    print STDERR "A list name is already defined ("
      .$self->{'list_name'}.") for this instance of CGI::Listman.\n";
  } else {
    $self->{'list_name'} = $list_name;
    $self->{'table_name'} = $list_name
      unless (defined $self->{'table_name'});
  }
}

sub set_table_name {
  my ($self, $table_name) = @_;

  if (defined $self->{'table_name'}) {
    $self->{'table_name'} = $table_name;
  }
}

sub dictionary {
  my $self = shift;

  unless (defined $self->{'_dictionary'}) {
    die "List directory not defined for this instance of CGI::Listman.\n"
      unless (defined $self->{'list_dir'});
    die "List filename not defined for this instance of CGI::Listman.\n"
      unless (defined $self->{'list_name'});

    my $path = $self->{'list_dir'}.'/'.$self->{'list_name'}.'.dict';
    die "No dictionary ('".$self->{'list_name'}.".dict')\n"
      unless (-f $path);

    my $dictionary = CGI::Listman::dictionary->new ($path);

    $self->{'_dictionary'} = $dictionary;
  }

  return $self->{'_dictionary'};
}

sub seek_line_by_num {
  my ($self, $number) = @_;

  $self->load_lines () unless (defined $self->{'list'});

  my $ret_line = undef;
  my $list_ref = $self->{'list'};

  foreach my $line (@$list_ref) {
    if ($line->number () == $number) {
      $ret_line = $line;
      last;
    }
  }

  return $ret_line;
}

sub _dbi_setup {
  my $self = shift;

  unless (defined $self->{'_dbi_params'}) {
    die "No backend specified for this instance of CGI::Listman.\n"
      unless (defined $self->{'dbi_backend'});
    if ($self->{'dbi_backend'} eq 'CSV') {
      $self->{'_dbi_params'} = ":f_dir=".$self->{'list_dir'};
      unless (-f $self->{'list_dir'}.'/'.$self->{'table_name'}.'.csv') {
	open my $list_file, '>'
	  .$self->{'list_dir'}.'/'.$self->{'table_name'}.'.csv';
	close $list_file;
      }
    } else {
      die "Sorry, this DBI backend \"".$self->{'dbi_backend'}
	."\" is not handled at this time.\n"
	  unless ($self->{'dbi_backend'} eq 'mysql');
      my $dbi_params = ":database=".$self->{'db_name'};
      $dbi_params .= ":host=".$self->{'db_host'}
      	if (defined $self->{'db_host'} && $self->{'db_host'} ne '');
      $dbi_params .= ":port=".$self->{'db_port'}
	if (defined $self->{'db_port'} && $self->{'db_port'} ne '');
      $self->{'_dbi_params'} = $dbi_params;
    }
  }
}

sub _db_fields_setup {
  my $self = shift;

  unless (defined $self->{'_db_fields'}) {
    my @fields = ('number', 'timestamp', 'seen', 'exported');
    my $dictionary = $self->dictionary ();
    my $dict_terms = $dictionary->terms ();

    foreach my $term (@$dict_terms) {
      push @fields, $term->{'key'};
    }
    $self->{'_db_fields'} = \@fields;
  }
}

sub _db_connect {
  my $self = shift;

  unless (defined $self->{'_db_connection'}) {
    $self->_dbi_setup ();
    $self->_db_fields_setup ();
    my $dbh = DBI->connect ("DBI:"
			    .$self->{'dbi_backend'}
			    .$self->{'_dbi_params'},
			    $self->{'db_uname'},
			    $self->{'db_passwd'})
    or die DBI->errstr;
    if ($self->{'dbi_backend'} eq 'CSV') {
      $dbh->{'csv_tables'}->{$self->{'table_name'}} =
	{'col_names' => $self->{'_db_fields'},
	 'file' => $self->{'table_name'}.".csv"};
    }
    $self->{'_db_connection'} = $dbh;
  }
}

sub _get_line_numbers {
  my $self = shift;

  my @numbers;

  if (defined $self->{'list'}) {
    my $list_ref = $self->{'list'};

    foreach my $line (@$list_ref) {
      push @numbers, $line->number ();
    }
  }

  return @numbers;
}

sub add_line {
  my ($self, $line) = @_;

  $self->load_lines ()
    unless (defined $self->{'list'}
	    || defined $self->{'_loading_list'});

  $line->{'number'} = $self->{'_last_line_number'} + 1
    unless ($line->{'number'});

  my @numbers = $self->_get_line_numbers ();
  croak "This instance's list of lines already contains a line with"
    ." this number (".$line->{'number'}.").\n"
      if (grep (m/$line->{'number'}/, @numbers));

  $self->{'_last_line_number'} = $line->{'number'};

  unless (defined $self->{'list'}) {
    my @new_list;
    $self->{'list'} = \@new_list;
  }

  my $list_ref = $self->{'list'};
  push @$list_ref, $line;
}

sub load_lines {
  my $self = shift;

  $self->{'_loading_list'} = 1;
  $self->_db_connect ();

  my $dbh = $self->{'_db_connection'};

  my $row_list =
    $dbh->selectall_arrayref ("SELECT * FROM ".$self->{'table_name'})
    or die $dbh->errstr;

# die $row_list->[0];
  delete $self->{'list'} if (defined $self->{'list'});

  if (defined $row_list) {
    foreach my $row (@$row_list) {
      my $line = CGI::Listman::line->new ();
      $line->_build_from_listman_data ($row);
      $self->add_line ($line);
    }
  }

  $self->{'_loading_list'} = undef;
}

sub list_contents {
  my $self = shift;

  my $contents_ref = undef;
  if (defined $self->{'list'}) {
    my @filt_contents;
    my $old_cref = $self->{'list'};
    foreach my $line (@$old_cref) {
      push @filt_contents, $line
	if (!$line->{'_deleted'});
    }
    $contents_ref = \@filt_contents;
  } else {
    $self->load_lines ();
    $contents_ref = $self->{'list'};
  }

  return $contents_ref;
}

# Check the validity of received parameters and returns two refs against
# the missing mandatory values and the unknown fields.
sub check_params {
  my ($self, $param_hash_ref) = @_;

  my $dictionary = $self->dictionary ();

  my @missing;
  my @unknown;

  foreach my $key (keys %$param_hash_ref) {
    my $term = $dictionary->get_term ($key);
    push @unknown, $key
      unless (defined $term);
  }

  my $dict_terms = $dictionary->terms ();

  foreach my $term (@$dict_terms) {
    my $key = $term->{'key'};
    push @missing, $term->definition_or_key ()
      if ($term->{'mandatory'}
	  && (!defined $param_hash_ref->{$key}
	      || $param_hash_ref->{$key} eq ''));
  }

  return (\@missing, \@unknown);
}

sub _prepare_record {
  my ($self, $line) = @_;

  my $fields_ref = $line->line_fields ();
  my @records;
  push @records, ($line->{'timestamp'}, $line->{'seen'}, $line->{'exported'});
  push @records, @$fields_ref;

  my $record_line = "'".$line->{'number'}."'";
  foreach my $record (@records) {
    $record = '' unless (defined $record);
    $record_line .= ", '".$record."'";
  }

  # if we don't untaint $record_line, we get a stange error regarding
  # DBD::SQL::Statement::HASH_ref...
  $record_line =~ m/(.*)/;
  $record_line = $1;

  return $record_line;
}

sub commit {
  my $self = shift;

  die "Commit again?\n"
    if (defined $self->{'_commit'});

  if (defined $self->{'list'}) {
    $self->_db_connect ();
    my $dbh = $self->{'_db_connection'};
    my $list_ref = $self->{'list'};
    foreach my $line (@$list_ref) {
      if ($line->{'_updated'}) {
	next if ($line->{'_deleted'} && $line->{'_new_line'});
	if ($line->{'_deleted'}) {
	  $dbh->do ("DELETE FROM ".$self->{'table_name'}.
		    "       WHERE number = ".$line->{'number'})
	    or die "An DBI error occured while deleting line "
	      .$line->{'number'}." from ".$self->{'table_name'}
		.":\n".$dbh->errstr;
	} elsif ($line->{'_new_line'}) {
	  $line->{'timestamp'} = time ()
	    unless ($line->{'timestamp'});
	  my $record = $self->_prepare_record ($line);
	  my $sth = $dbh->do ("INSERT INTO ".$self->{'table_name'}.
				   "       VALUES (".$record.")")
	    or die "An DBI error occured while inserting...\n".$record.
	      "... into ".$self->{'table_name'}.":\n".$dbh->errstr;
	} else {
	  $dbh->do ("DELETE FROM ".$self->{'table_name'}.
		    "       WHERE number = ".$line->{'number'})
	    or die "An DBI error occured while deleting line "
	      .$line->{'number'}." from ".$self->{'table_name'}
		.":\n".$dbh->errstr;
	  my $record = $self->_prepare_record ($line);
	  my $sth = $dbh->do ("INSERT INTO ".$self->{'table_name'}.
				   "       VALUES (".$record.")")
	    or die "An DBI error occured while inserting...\n".$record.
	      "... into ".$self->{'table_name'}.":\n".$dbh->errstr;
	}
      }
    }
    $dbh->disconnect ();
  }

  $self->{'_commit'} = 1;
}

sub delete_line {
  my ($self, $line) = @_;

  die "Cannot delete a line with number equal to 0.\n"
    unless ($line->{'number'});

  my $list_ref = $self->{'list'};
  die "List empty.\n" unless (defined $list_ref);

  # delete the line from the list in memory...
  my $count;
  for ($count = 0; $count < @$list_ref; $count++) {
    if ($list_ref->[$count] == $line) {
      $line->{'_updated'} = 1;
      $line->{'_deleted'} = 1;
      last;
    }
  }

  die "Line not found in list."
    if ($count == @$list_ref);
}

sub delete_selection {
  my ($self, $selection) = @_;

  my $list_ref = $selection->{'list'};
  die "Selection is empty.\n" unless ($list_ref);
  foreach my $line (@$list_ref) {
    $self->delete_line ($line);
  }
}


package CGI::Listman::line;

use strict;

# line format: (number, timestamp, seen, exported, fields...)
sub new {
  my $class = shift;

  my $self = {};
  $self->{'number'} = 0;
  $self->{'timestamp'} = 0;
  $self->{'seen'} = 0;
  $self->{'exported'} = 0;
  $self->{'data'} = shift;

  $self->{'_updated'} = 1;
  $self->{'_new_line'} = 1;
  $self->{'_deleted'} = 0;

  bless $self, $class;
}

sub mark_seen {
  my $self = shift;

  $self->{'seen'} = 1;
  $self->{'_updated'} = 1;
}

sub mark_exported {
  my $self = shift;

  $self->{'exported'} = 1;
  $self->{'_updated'} = 1;
}

sub number {
  my $self = shift;

  return $self->{'number'};
}

sub set_fields {
  my ($self, $fields_ref) = @_;

  die "Fields already defined for line.\n"
    if (defined $self->{'data'});

  $self->{'data'} = $fields_ref;
  $self->{'_updated'} = 1;
}

sub update_fields {
  my ($self, $fields_ref) = @_;

  delete $self->{'data'}
    if (defined $self->{'data'});

  $self->{'data'} = $fields_ref;
  $self->{'_updated'} = 1;
}

sub line_fields {
  my $self = shift;

  return $self->{'data'};
}

# internals only
sub _build_from_listman_data {
  my ($self, $listman_data_ref) = @_;

  my @backend_data = @$listman_data_ref;

  my $number = shift @backend_data;
  $number =~ m/^([0-9]*)$/;
  $number = $1 or die 'Wrong number ("'.$number
    .'") containing non-digit characters'."\n";

  $self->{'number'} = $number;
  $self->{'timestamp'} = shift @backend_data;
  $self->{'seen'} = shift @backend_data;
  $self->{'exported'} = shift @backend_data;
  $self->{'data'} = \@backend_data;

  $self->{'_updated'} = 0;
  $self->{'_new_line'} = 0;
}


package CGI::Listman::exporter;

use strict;
use Text::CSV_XS;

sub new {
  my $class = shift;

  my $self = {};

  my @lines;
  $self->{'file_name'} = shift;
  $self->{'separator'} = shift || ',';
  $self->{'lines'} = \@lines;
  $self->{'_csv'} = Text::CSV_XS->new ({sep_char => $self->{'separator'},
					binary => 1});
  $self->{'_file_read'} = 0;

  bless $self, $class;
  $self->_read_file () if (defined $self->{'file_name'});

  return $self;
}

sub set_file_name {
  my ($self, $file_name) = @_;

  die "A file name is already defined for this instance"
    ." of CGI::Listman::exporter.\n"
      if (defined $self->{'file_name'});
  $self->{'file_name'} = $file_name;
  $self->_read_file ();
}

sub set_separator {
  my ($self, $sep) = @_;

  $self->{'separator'} = $sep;
}

sub add_line {
  my ($self, $line) = @_;

  my $csv = $self->{'_csv'};

  my $data_ref = $line->{'data'};
  my @columns = @$data_ref;
  $csv->combine (@columns);
  my $csv_line = $csv->string ();
  my $lines_ref = $self->{'lines'};
  push @$lines_ref, $csv_line;
  $line->mark_exported ();
}

sub add_selection {
  my ($self, $selection) = @_;

  my $sel_list_ref = $selection->{'list'};
  foreach my $line (@$sel_list_ref) {
    $self->add_line ($line);
  }
}

sub file_contents {
  my $self = shift;

  my $contents = undef;
  my $lines_ref = $self->{'lines'};
  foreach my $line (@$lines_ref) {
    $contents .= $line."\r\n";
  }

  return $contents;
}

sub save_file {
  my $self = shift;

  print STDERR "saving to ".$self->{'file_name'}."\n";
  die "No file to export to.\n"
    unless (defined $self->{'file_name'});
  my $contents = $self->file_contents ();

  open EFOUT, '>'.$self->{'file_name'}
    or die "Could not open export file (\""
      .$self->{'file_name'}."\") for writing.\n";
  print EFOUT $contents;
  close EFOUT;
}

sub _read_file {
  my $self = shift;

  if (-f $self->{'file_name'}) {
    open EFIN, $self->{'file_name'}
      or die "Could not open export file ('".$self->{'file_name'}."').\n";

    my $lines_ref = $self->{'lines'};
    while (<EFIN>) {
      my $line = $_;
      chomp $line;
      push @$lines_ref, $line;
    }
    close EFIN;

    $self->{'_file_read'} = 1;
  }
}


package CGI::Listman::selection;

use strict;

sub new {
  my $class = shift;

  my $self = {};
  my @selection_list;
  $self->{'list'} = \@selection_list;

  bless $self, $class;
}

sub add_line {
  my ($self, $line) = @_;

  my $list_ref = $self->{'list'};
  push @$list_ref, $line;
}

sub add_line_by_number {
  my ($self, $listman, $number) = @_;

  my $line = $listman->seek_line_by_num ($number);
  die "Line number ".$number." not found.\n"
    unless (defined $line);
  $self->add_line ($line);
}

sub add_lines_by_number {
  my ($self, $listman, $numbers) = @_;

  foreach my $number (@$numbers) {
    $self->add_line_by_number ($listman, $number);
  }
}


package CGI::Listman::dictionary;

sub new {
  my $class = shift;

  my $self = {};
  $self->{'filename'} = shift;

  $self->{'_terms'} = undef;
  $self->{'_loading'} = 0;

  bless $self, $class;
}

sub _load {
  my $self = shift;

  return if $self->{'_loading'};

  $self->{'_loading'} = 1;
  die "No dictionary filename.\n"
    unless (defined $self->{'filename'});

  open DINF, $self->{'filename'}
    or die "Could not open dictionary (\"".$self->{'filename'}."\").\n";

  my @terms;
  while (<DINF>) {
    my $line = $_;
    chomp $line;
    $line =~ m/([^:]*)(:([^:]+)?(:([!]))?)?/;

    my $key = $1;
    my $definition = $3 || '';
    my $mandatory = (defined $5 && $5 eq '!');

    die "Dictionary entry \"".$key."\" is duplicated."
      if (defined $self->get_term ($key));

    my $term_object = CGI::Listman::dictionary::term->new ($key,
							   $definition,
							   $mandatory,
							   $self->{'count'});
    push @terms, $term_object;
  }
  close DINF;

  $self->{'_terms'} = \@terms;
  $self->{'_loading'} = 0;
}

sub add_term {
  my ($self, $term) = @_;

  my $terms_ref = $self->terms ();
  push @$terms_ref, $term;
}

sub get_term {
  my ($self, $key) = @_;

  my $terms_ref = $self->terms ();

  my $term_object = undef;

  if (defined $terms_ref) {
    foreach my $term (@$terms_ref) {
      next if ($term->{'key'} ne $key);
      $term_object = $term;
    }
  }

  return $term_object;
}

sub terms {
  my $self = shift;

  $self->_load () unless (defined $self->{'_terms'});
  my $terms_ref = $self->{'_terms'};

  return $terms_ref;
}

sub term_pos_in_list {
  my ($self, $term) = @_;

  my $number = 0;
  my $terms_ref = $self->terms ();
  foreach my $comp_term (@$terms_ref) {
    last if ($comp_term == $term);
    $number++;
  }

  return $number;
}

sub reposition_term {
  my ($self, $term, $delta) = @_;

  my $curr_pos = $self->term_pos_in_list ($term);
  my $new_pos = $curr_pos + $delta;
  my $terms_ref = $self->{'_terms'};

  unless ($new_pos > scalar (@$terms_ref)
	  || $new_pos < 0
	  || $delta == 0) {
    my @new_terms_list;

    for (my $count = 0; $count < @$terms_ref; $count++) {
      if ($delta > 0) {
	push @new_terms_list, $terms_ref->[$count + 1]
	  if ($count < $new_pos && $count >= $curr_pos);
      } else {
	push @new_terms_list, $terms_ref->[$count - 1]
	  if ($count > $new_pos && $count <= $curr_pos);
      }
      push @new_terms_list, $terms_ref->[$count]
	if (($count < $new_pos && $count < $curr_pos)
	    || ($count > $new_pos && $count > $curr_pos));
      push @new_terms_list, $term
	if ($count == $new_pos);
    }

    delete $self->{'_terms'};
    $self->{'_terms'} = \@new_terms_list;
  }
}

sub increase_term_pos {
  my ($self, $term, $increment) = @_;

  $increment = 1 unless (defined $increment);

  $self->reposition_term ($term, $increment);
}

sub decrease_term_pos {
  my ($self, $term, $decrement) = @_;

  $decrement = 1 unless (defined $decrement);

  $self->reposition_term ($term, -$decrement);
}

sub increase_term_pos_by_key {
  my ($self, $key, $increment) = @_;

  my $term = $self->get_term ($key);
  $self->increase_term_pos ($term, $increment);
}

sub decrease_term_pos_by_key {
  my ($self, $key, $decrement) = @_;

  my $term = $self->get_term ($key);
  $self->decrease_term_pos ($term, $decrement);
}

sub save {
  my $self = shift;

  open DOUTF, '>'.$self->{'filename'}
    or die "Could not open dictionary (\""
      .$self->{'filename'}."\" for writing).\n";
  my $terms_ref = $self->{'_terms'};
  foreach my $term (@$terms_ref) {
    my $line = $term->{'key'};
    my $definition = $term->definition ();
    $line .= ':'.$definition if (defined $definition && $definition ne '');
    if ($term->{'mandatory'}) {
      $line .= (defined $definition && $definition ne '') ? ':!' : '::!';
    }
    print DOUTF $line."\n";
  }
  close DOUTF;
}

package CGI::Listman::dictionary::term;

sub new {
  my $class = shift;

  my $self = {};
  $self->{'key'} = shift;
  $self->{'_definition'} = shift;
  $self->{'mandatory'} = shift || 0;

  bless $self, $class;
}

sub set_key {
  my ($self, $key) = @_;

  die "Bad key name.\n" unless (defined $key && $key ne '');
  die 'This term already has a key name ("'.$self->{'key'}."\n"
    if (defined $self->{'key'});
  $self->{'key'} = $key;
}

sub set_definition {
  my ($self, $definition) = @_;

  $definition = undef if (defined $definition
			  && ($definition =~ m/^\s+$/));
  $self->{'_definition'} = $definition;
}

sub set_mandatory {
  my $self = shift;

  $self->{'mandatory'} = 1;
}

sub definition {
  my $self = shift;

  my $definition = $self->{'_definition'};

  return $definition;
}

sub definition_or_key {
  my $self = shift;

  my $definition = $self->definition () || $self->{'key'};

  return $definition;
}

1;
__END__

=head1 NAME

CGI::Listman - Perl extension for easily managing web subscribtion lists

=head1 SYNOPSIS

  use CGI::Listman;

=head1 DESCRIPTION

CGI::Listman provides an object-oriented interface to easily manage
web-based subscribtion lists. It implements concepts such as
"dictionaries", "selections", "exporters", provides some checking
facilities (field duplication or requirements) and uses the DBI interface
so as to provide a backend-independent storage area (PostgreSQL, ...).

=head1 API

=head2 CGI::Listman

THis class manages the listmanagers of your project. This is the very
first class you want to instantiate. It is the logical central point of
all others objects. Except for I<CGI::Listman::line>,
I<CGI::Listman::exporter> and I<CGI::Listman::selection>, you should not
call any other class's "new" method since I<CGI::Listman> will handle its
own instances for you.

Methods:

=over

=item new (opt: dbi_backend, list_name, list_dir)

As for any perl class, new acts as the constructor for an instance of this
class. It has three optional arguments that, if not specified, can be
replaced with calls to the respective methods: I<set_backend>,
I<set_list_name>, I<set_list_dir>.

Examples:

C<my $list_manager = CGI::Listman-E<gt>new;>

C<my $list_manager = CGI::Listman-E<gt>new ('CSV', 'userlist', '/var/lib/weblists');>

=item set_backend

Defines the DBI backend used to store the data.

=item set_list_name

Gives a name to your list.

=item set_list_dir

Defines where the list's dictionary and data files are stored.

=item set_table_name

For database backends, gives the name of the table the lists has to be
stored int.

=item delete_line

Delete a I<CGI::Listman::line> (see below) from this instance's list of
lines.

=item delete_selection

Delete many lines at the same time through the use of a
I<CGI::Listman::selection> (see below).

=item dictionary

Returns a reference to the I<CGI::Listman::dictionary> of this instance.
There is only one dictionary for each instance. This method will
automatically create and read the list's dictionary for you.

=item list_contents

Returns a reference to an ARRAY of the list's lines.

=item load_lines

Loads the line from the list database or storage file.

=item seek_line_by_num

Returns the n'th I<CGI::Listman::line> of this instance.

=item commit

This will commit any changes made to your instance, after which, that
instance will be invalidated. As long as it is not called, you can of
course apply any modifications to your instance. This limitation will
probably be got rid of in a next release.

=back

=head2 CGI::Listman::line

=head2 CGI::Listman::exporter

=head2 CGI::Listman::selection

=head2 CGI::Listman::dictionary

=head2 CGI::Listman::dictionary::term

=head1 AUTHOR

Wolfgang Sourdeau, E<lt>Wolfgang@Contre.COME<gt>

=head1 COPYRIGHT

Copyright (C) 2002 iScream multimédia <info@iScream.ca>

This package is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<DBI(3)>, L<CGI(3)>

=cut
