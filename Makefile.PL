use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'CGI::Listman',
    'VERSION_FROM'	=> 'Listman.pm', # finds $VERSION
    'dist'		=> { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    'PREREQ_PM'		=> { 'Text::CSV_XS' => '0.22',
			     'DBI' => '1.00'},
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => 'Listman.pm', # retrieve abstract from module
       AUTHOR     => 'Wolfgang Sourdeau <Wolfgang@iScream.ca>') : ()),
);

package MY;

#sub postamble {
#    "\npm_to_blib: README\n" .
#    "\nREADME: Listman.pm" .
#    "\n\tperldoc -t Listman.pm >README\n\n"
#}

sub libscan {
    my($self, $path) = @_;
    ($path =~ /\~$/) ? undef : $path;
}
