use strict;
use warnings;
use Test::More;
use Test::Spelling;

add_stopwords(qw(
));
set_spell_cmd('aspell list -l en');
all_pod_files_spelling_ok();

done_testing();
