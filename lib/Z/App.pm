use strict;
use warnings;
package Z::App;
use parent 'Z';
sub modules {
	my @modules = shift->SUPER::modules( @_ );
	for my $mod ( @modules ) {
		next unless $mod->[0] eq 'Zydeco::Lite';
		$mod->[0] .= '::App';
		$mod->[1]  = '0';
	}
	return @modules;
}
1;