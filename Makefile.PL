use strict;
use warnings;
use inc::Module::Install 0.91;
# Ensure that these get used - yes, M::I loads them for us, but if you're
# in author mode and don't have them installed, then the error is tres
# cryptic.
if ($Module::Install::AUTHOR) { # We could just use them, but telling
    my @fail;                   # people the set of things they need nicer
    foreach my $module (qw/
        Module::Install::AuthorRequires
        Module::Install::AuthorTests
        Module::Install::Authority
    /) {
        push(@fail, $module)
            unless eval qq{require $module; 1;};
    }
    die("Module::Install extensions failed, not installed? \n"
        . join("\n", map { "  $_" } @fail) . "\n") if @fail;
}

perl_version '5.008003';

name 'Devel-TimingStats';
author 'Sebastian Riedel <sri@cpan.org>';
authority('MSTROUT');
all_from 'lib/Devel/TimingStats.pm';

requires 'Moose' => '1.03';
requires 'namespace::clean' => '0.23';
requires 'Term::Size::Guess';
requires 'Text::SimpleTable' => '0.03';
requires 'Time::HiRes';
requires 'Tree::Simple' => '1.15';
requires 'Tree::Simple::Visitor::FindByUID';

test_requires 'Test::More' => '0.88';

author_tests('t/author');
author_requires(
  map {; $_ => 0 } qw(
  Pod::Coverage::TrustPod
  Test::NoTabs
  Test::Pod
  Test::Pod::Coverage
  Test::Spelling
));

if ($Module::Install::AUTHOR) {
    darwin_check_no_resource_forks();
}

resources(
    'license',    => 'http://dev.perl.org/licenses/',
    'repository', => 'git://git.shadowcat.co.uk/catagits/Devel-TimingStats.git',
);

auto_install;
WriteAll;

# End of script, helper functions below.

sub darwin_check_no_resource_forks {
    if ($^O eq 'darwin') {
        my $osx_ver = `/usr/bin/sw_vers -productVersion`;
        chomp $osx_ver;

        # TAR on 10.4 wants COPY_EXTENDED_ATTRIBUTES_DISABLE
        # On 10.5 (Leopard) it wants COPYFILE_DISABLE
        my $attr = $osx_ver =~ /^10.(5|6|7|8)/  ? 'COPYFILE_DISABLE' : 'COPY_EXTENDED_ATTRIBUTES_DISABLE';

        makemaker_args(dist => { PREOP => qq{\@if [ "\$\$$attr" != "true" ]; then}.
                                          qq{ echo "You must set the ENV variable $attr to 'true',"; }.
                                          ' echo "to avoid getting resource forks in your dist."; exit 255; fi' });
    }
}
