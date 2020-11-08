use 5.008008;
use strict;
use warnings;

package Zydeco::Lite::App;

use Getopt::Kingpin 0.10;
use Path::Tiny 'path';
use Type::Utils 'english_list';
use Types::Path::Tiny -types;
use Types::Standard -types;
use Zydeco::Lite qw( -all !app );

use parent 'Zydeco::Lite';
use namespace::autoclean;

our $AUTHORITY = 'cpan:TOBYINK';
our $VERSION   = '0.001';

our @EXPORT = (
	@Zydeco::Lite::EXPORT,
	qw( arg flag command run ),
);
our @EXPORT_OK = @EXPORT;

sub make_fake_call ($) {
	my $pkg = shift;
	eval "sub { package $pkg; my \$code = shift; &\$code; }";
}

our %THIS;

sub app {
	local $THIS{MY_SPEC} = {};
	
	my $orig = Zydeco::Lite::_pop_type( CodeRef, @_ ) || sub { 1 };
	
	my $commands;
	my $wrapped = sub {
		$orig->( @_ );
		
		while ( my ( $key, $spec ) = each %{ $Zydeco::Lite::THIS{'APP_SPEC'} } ) {
			if ( $key =~ /^(class|role):(.+)$/ ) {
				if ( $spec->{"-IS_COMMAND"} ) {
					( my $cmdname = lc $2 ) =~ s/::/-/g;
					push @{ $spec->{with} ||= [] }, '::Zydeco::Lite::App::Trait::Command';
					$spec->{can}{command_name} ||= sub () { $cmdname };
				}
				if ( $spec->{"-IS_COMMAND"} || $spec->{"-FLAGS"} || $spec->{"-ARGS"} ) {
					my $flags = delete( $spec->{"-FLAGS"} ) || {};
					my $args  = delete( $spec->{"-ARGS"} )  || [];
					push @{ $spec->{symmethod} ||= [] }, (
						_flags_spec => sub { $flags },
						_args_spec  => sub { $args },
					);
				}
				
				delete $spec->{"-IS_COMMAND"};
				delete $spec->{"-FLAGS"};
				delete $spec->{"-ARGS"};
			} #/ if ( $key =~ /^(class|role):(.+)$/)
		} #/ while ( my ( $key, $spec ...))
		
		my $spec = $Zydeco::Lite::THIS{'APP_SPEC'};
		push @{ $spec->{with} ||= [] }, '::Zydeco::Lite::App::Trait::Application';
		$spec->{can}{'commands'} = sub { @{ $commands or [] } }
	};
	
	my $app =
		make_fake_call( caller )->( \&Zydeco::Lite::app, @_, $wrapped ) || $_[0];
	$commands = $THIS{MY_SPEC}{"-COMMANDS"};
	
	return $app;
} #/ sub app

sub flag {
	$Zydeco::Lite::THIS{CLASS_SPEC}
		or Zydeco::Lite::confess( "cannot use `flag` outside a role or class" );
		
	my $name = Zydeco::Lite::_shift_type( Str, @_ )
		or Zydeco::Lite::confess( "flags must have a string name" );
	my %flag_spec = @_ == 1 ? %{ $_[0] } : @_;
	
	my $app   = $Zydeco::Lite::THIS{APP};
	my $class = $Zydeco::Lite::THIS{CLASS};
	$flag_spec{kingpin} ||= sub {
		__PACKAGE__->_kingpin_handle( $app, $class, flag => $name, \%flag_spec, @_ );
	};
	
	$Zydeco::Lite::THIS{CLASS_SPEC}{"-FLAGS"}{$name} = \%flag_spec;
	
	my %spec = %flag_spec;
	delete $spec{short};
	delete $spec{env};
	delete $spec{placeholder};
	delete $spec{hidden};
	delete $spec{kingpin};
	delete $spec{kingpin_type};
	@_ = ( $name, \%spec );
	goto \&Zydeco::Lite::has;
} #/ sub flag

sub arg {
	$Zydeco::Lite::THIS{CLASS_SPEC}
		or Zydeco::Lite::confess( "cannot use `arg` outside a class" );
		
	my $name = Zydeco::Lite::_shift_type( Str, @_ )
		or Zydeco::Lite::confess( "args must have a string name" );
	my %arg_spec = @_ == 1 ? %{ $_[0] } : @_;
	
	my $app   = $Zydeco::Lite::THIS{APP};
	my $class = $Zydeco::Lite::THIS{CLASS};
	$arg_spec{name} = $name;
	$arg_spec{kingpin} ||= sub {
		__PACKAGE__->_kingpin_handle( $app, $class, arg => $name, \%arg_spec, @_ );
	};
	
	push @{ $Zydeco::Lite::THIS{CLASS_SPEC}{"-ARGS"} ||= [] }, \%arg_spec;
	
	return;
} #/ sub arg

sub _kingpin_handle {
	my ( $me, $factory, $class, $kind, $name, $spec, $kingpin ) = ( shift, @_ );
	
	my $flag = $kingpin->$kind(
		$spec->{init_arg}      || $name,
		$spec->{documentation} || 'No description available.',
	);
	
	if ( not ref $spec->{kingpin_type} ) {
	
		my $reg = 'Type::Registry'->for_class( $class );
		$reg->has_parent or $reg->set_parent( 'Type::Registry'->for_class( $factory ) );
		
		my $type =
			$spec->{kingpin_type} ? $reg->lookup( $spec->{kingpin_type} )
			: ref( $spec->{type} or $spec->{isa} ) ? ( $spec->{type} or $spec->{isa} )
			: $spec->{type}                        ? $reg->lookup( $spec->{type} )
			: $spec->{isa} ? $factory->type_library->get_type_for_package(
			$factory->get_class( $spec->{isa} ) )
			: $spec->{does} ? $factory->type_library->get_type_for_package(
			$factory->get_role( $spec->{does} ) )
			: Str;
			
		$spec->{kingpin_type} = $type;
	} #/ if ( not ref $spec->{kingpin_type...})
	
	my $type = $spec->{kingpin_type};
	
	if ( $type <= ArrayRef ) {
		if ( $type->is_parameterized and $type->parent == ArrayRef ) {
			my $type_parameter = $type->type_parameter;
			if ( $type_parameter <= File ) {
				$flag->existing_file_list;
			}
			elsif ( $type_parameter <= Dir ) {
				$flag->existing_dir_list;
			}
			elsif ( $type_parameter <= Path ) {
				$flag->file_list;
			}
			elsif ( $type_parameter <= Int ) {
				$flag->int_list;
			}
			elsif ( $type_parameter <= Num ) {
				$flag->num_list;
			}
			else {
				$flag->string_list;
			}
		} #/ if ( $type->is_parameterized...)
		else {
			$flag->string_list;
		}
	} #/ if ( $type <= ArrayRef)
	elsif ( $type <= HashRef ) {
		if ( $type->is_parameterized and $type->parent == ArrayRef ) {
			my $type_parameter = $type->type_parameter;
			if ( $type_parameter <= File ) {
				$flag->existing_file_list;
			}
			elsif ( $type_parameter <= Dir ) {
				$flag->existing_dir_list;
			}
			elsif ( $type_parameter <= Path ) {
				$flag->file_list;
			}
			elsif ( $type_parameter <= Int ) {
				$flag->int_list;
			}
			elsif ( $type_parameter <= Num ) {
				$flag->num_list;
			}
			else {
				$flag->string_list;
			}
		} #/ if ( $type->is_parameterized...)
		else {
			$flag->string_list;
		}
		$flag->placeholder( 'KEY=VAL' ) if $flag->can( 'placeholder' );
		$flag->{is_hashref} = true;
	} #/ elsif ( $type <= HashRef )
	elsif ( $type <= Bool ) {
		$flag->bool;
	}
	elsif ( $type <= File ) {
		$flag->existing_file;
	}
	elsif ( $type <= Dir ) {
		$flag->existing_dir;
	}
	elsif ( $type <= Path ) {
		$flag->file;
	}
	elsif ( $type <= Int ) {
		$flag->int;
	}
	elsif ( $type <= Num ) {
		$flag->num;
	}
	else {
		$flag->string;
	}
	
	if ( $spec->{required} ) {
		$flag->required;
	}
	
	if ( $spec->{hidden} ) {
		$flag->hidden;
	}
	
	if ( exists $spec->{short} ) {
		$flag->short( $spec->{short} );
	}
	
	if ( exists $spec->{env} ) {
		$flag->override_default_from_envar( $spec->{env} );
	}
	
	if ( exists $spec->{placeholder} ) {
		$flag->placeholder( $spec->{placeholder} );
	}
	
	if ( $kind eq 'arg' ) {
		if ( Types::TypeTiny::CodeLike->check( $spec->{default} ) ) {
			my $cr = $spec->{default};
			
			# For flags, MooX::Press does this prefilling
			if ( blessed $cr and $cr->isa( 'Ask::Question' ) ) {
				$cr->_set_type( $type )                           unless $cr->has_type;
				$cr->_set_text( $spec->{documentation} || $name ) unless $cr->has_text;
				$cr->_set_title( $name )                          unless $cr->has_title;
				$cr->_set_spec( $spec )                           unless $cr->has_spec;
			}
			$flag->default( sub { $cr->( $class ) } );
		} #/ if ( Types::TypeTiny::CodeLike...)
		elsif ( exists $spec->{default} ) {
			$flag->default( $spec->{default} );
		}
		elsif ( my $builder = $spec->{builder} ) {
			$builder = "_build_$name" if is_Int( $builder ) && $builder eq 1;
			$flag->default( sub { $class->$builder } );
		}
	} #/ if ( $kind eq 'arg' )
	
	return $flag;
} #/ sub _kingpin_handle

sub command {
	my $definition = Zydeco::Lite::_pop_type( CodeRef, @_ ) || sub { 1 };
	my $name       = Zydeco::Lite::_shift_type( Str, @_ )
		or Zydeco::Lite::confess( "commands must have a string name" );
	my %args = @_;
	
	Zydeco::Lite::class( $name, %args, $definition );
	
	my $class_spec = $Zydeco::Lite::THIS{APP_SPEC}{"class:$name"};
	$class_spec->{'-IS_COMMAND'} = 1;
	
	push @{ $THIS{MY_SPEC}{"-COMMANDS"} ||= [] }, $name;
	
	return;
} #/ sub command

sub run (&) {
	unshift @_, 'execute';
	goto \&Zydeco::Lite::method;
}

Zydeco::Lite::app( 'Zydeco::Lite::App' => sub {
	
	role 'Trait::Application'
	=> sub {
	
		requires qw( commands );
		
		method '_proto'
		=> sub {
			my ( $proto ) = ( shift );
			ref( $proto ) ? $proto : bless( {}, $proto );
		};
		
		method 'stdio'
		=> sub {
			my ( $app, $in, $out, $err ) = ( shift, @_ );
			$app->{stdin}  = $in  if $in;
			$app->{stdout} = $out if $out;
			$app->{stderr} = $err if $err;
			$app;
		};
			
		method 'find_config'
		=> sub {
			my ( $app ) = ( shift->_proto );
			$app->can( 'config_file' ) or return;
			require Perl::OSType;
			my @files = $app->config_file;
			my @dirs  = ( path( "." ) );
			if ( Perl::OSType::is_os_type( 'Unix' ) ) {
				push @dirs, path( $ENV{XDG_CONFIG_HOME} || '~/.config' );
				push @dirs, path( '/etc' );
			}
			elsif ( Perl::OSType::is_os_type( 'Windows' ) ) {
				push @dirs,
					map path( $ENV{$_} ),
					grep $ENV{$_},
					qw( LOCALAPPDATA APPDATA PROGRAMDATA );
			}
			my @found;
			for my $dir ( @dirs ) {
				for my $file ( @files ) {
					my $found = $dir->child( "$file" );
					push @found, $found if $found->is_file;
				}
			}
			@found;
		};
			
		method read_config
		=> sub {
			my ( $app ) = ( shift->_proto );
			my @files = @_ ? map( path( $_ ), @_ ) : $app->find_config;
			my %config;
			
			for my $file ( reverse @files ) {
				next unless $file->is_file;
				
				my $this_config = {};
				
				if ( $file =~ /\.json$/i ) {
					my $decode =
						eval { require JSON::MaybeXS }
						? \&JSON::MaybeXS::decode_json
						: do { require JSON::PP; \&JSON::PP::decode_json };
					$this_config = $decode->( $file->slurp_utf8 );
				}
				elsif ( $file =~ /\.ya?ml/i ) {
					my $decode =
						eval { require YAML::XS }
						? \&YAML::XS::LoadFile
						: do { require YAML::PP; \&YAML::PP::LoadFile };
					$this_config = $decode->( $file->slurp_utf8 );
				}
				elsif ( $file =~ /\.ini/i ) {
					require Config::Tiny;
					my $this_config = 'Config::Tiny'->read( "$file", 'utf8' );
					$this_config->{'globals'} ||= delete $this_config->{'_'};
					$this_config = +{%$this_config};
				}
				else {
					require TOML::Parser;
					my $parser = 'TOML::Parser'->new;
					$this_config = $parser->parse_fh( $file->openr_utf8 );
				}
				
				while ( my ( $section, $sconfig ) = each %$this_config ) {
					$config{$section} = +{
						%{ $config{$section} or {} },
						%{ $sconfig or {} },
					};
				}
			} #/ for my $file ( reverse ...)
			
			return \%config;
		};
			
		method 'kingpin'
		=> sub {
			my ( $app, $kingpin ) = ( shift->_proto, @_ );
			my $config = $app->read_config;
			for my $cmd ( $app->commands ) {
				my $class        = $app->get_class( $cmd ) or next;
				my $cmdname      = $class->command_name    or next;
				my $cmdconfig    = $config->{$cmdname}  || {} or next;
				my $globalconfig = $config->{'globals'} || {} or next;
				$class->kingpin( $kingpin, { %$globalconfig, %$cmdconfig } );
			}
			return;
		};
			
		method 'execute_no_subcommand'
		=> sub {
			my ( $app, @args ) = ( shift->_proto, @_ );
			$app->execute( '--help' );
		};
		
		run {
			my ( $app, @args ) = ( shift->_proto, @_ );
			my $kingpin = 'Getopt::Kingpin'->new;
			$app->kingpin( $kingpin );
			my $cmd       = $kingpin->parse( @args );
			my $cmd_class = $cmd->{'zylite_app_class'};
			if ( not $cmd_class ) {
				$app->execute_no_subcommand( @args );
			}
			my %flags;
			for my $name ( $cmd->flags->keys ) {
				my $flag = $cmd->flags->get( $name );
				$flag->{'_defined'} or next;
				$flags{$name} = $flag->value;
			}
			my $cmd_object = $cmd_class->new( %flags, app => $app );
			my @coerced    = do {
				my @values = map $_->value, $cmd->args->get_all;
				my @args   = map @{ $_ or {} }, $cmd_object->_args_spec;
				my @return;
				while ( @values ) {
					my $value = shift @values;
					my $spec  = shift @args;
					if ( $spec->{type} ) {
						$value =
							$spec->{type}->has_coercion
							? $spec->{type}->assert_coerce( $value )
							: $spec->{type}->assert_return( $value );
					}
					push @return, $value;
				} #/ while ( @values )
				@return;
			};
			my $return = $cmd_object->execute( @coerced );
			exit( $return );
		};
			
		method 'stdin'
		=> sub {
			my $self = shift;
			ref( $self ) && exists( $self->{stdin} ) ? $self->{stdin} : \*STDIN;
		};
			
		method 'stdout'
		=> sub {
			my $self = shift;
			ref( $self ) && exists( $self->{stdout} ) ? $self->{stdout} : \*STDOUT;
		};
			
		method 'stderr'
		=> sub {
			my $self = shift;
			ref( $self ) && exists( $self->{stderr} ) ? $self->{stderr} : \*STDERR;
		};
			
		method 'readline'
		=> sub {
			my $in   = shift->stdin;
			my $line = <$in>;
			chomp $line;
			return $line;
		};
			
		method 'print'
		=> sub {
			my $self = shift;
			$self->stdout->print( "$_\n" ) for @_;
			return;
		};
		
		method 'debug'
		=> sub {
			my $self = shift;
			$self->stderr->print( "$_\n" ) for @_;
			return;
		};
			
		method 'usage'
		=> sub {
			my $self = shift;
			$self->stderr->print( "$_\n" ) for @_;
			exit( 1 );
		};
			
		my %colours = (
			info    => 'bright_blue',
			warn    => 'bold bright_yellow',
			error   => 'bold bright_red',
			fatal   => 'bold bright_red',
			success => 'bold bright_green',
		);
		
		for my $key ( keys %colours ) {
			my $level  = $key;
			my $colour = $colours{$key};
			
			method $level
			=> sub {
				require Term::ANSIColor;
				my $self = shift;
				$self->stderr->print( Term::ANSIColor::colored( "$_\n", $colour ) ) for @_;
				exit( 254 ) if $level eq 'fatal';
				return;
			};
		} #/ for my $key ( keys %colours)
	};
		
	role 'Trait::Command'
	=> sub {
	
		requires qw( _flags_spec _args_spec execute command_name );
			
		has 'app' => (
			is      => 'lazy',
			isa     => ClassName | Object,
			default => sub { shift->FACTORY },
		);
		
		has 'config' => (
			is      => 'lazy',
			type    => HashRef,
			builder => sub {
				my $self   = shift;
				my $config = $self->app->read_config;
				my %config = ( %{ $config->{'globals'} or {} },
					%{ $config->{ $self->command_name } or {} } );
				\%config;
			}
		);
		
		method 'documentation'
		=> sub {
			return 'No description available.'
		};
			
		method 'kingpin'
		=> sub {
			my ( $class, $kingpin, $defaults ) = ( shift, @_ );
			
			my $cmd = $kingpin->command( $class->command_name, $class->documentation );
			$cmd->{'zylite_app_class'} = $class;
			
			my %specs = map %{ $_ or {} }, $class->_flags_spec;
			for my $s ( sort keys %specs ) {
				my $spec = $specs{$s};
				my $flag = $spec->{'kingpin'}( $cmd );
				if ( exists $defaults->{ $flag->name } ) {
					$flag->default( $defaults->{ $flag->name } );
				}
			}
			
			my @args = map @{ $_ or {} }, $class->_args_spec;
			for my $spec ( @args ) {
				$spec->{'kingpin'}( $cmd );
			}
			
			return $cmd;
		};
		
		# Delegate some things to app
		for ( qw/ print debug info warn error fatal usage success / ) {
			my $method = $_;
			
			method $method
			=> sub {
				shift->app->$method( @_ )
			};
		}
	};
} );

1;

__END__

=pod

=encoding utf-8

=head1 NAME

Zydeco::Lite::App - use Zydeco::Lite to quickly develop command-line apps

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 BUGS

Please report any bugs to
L<http://rt.cpan.org/Dist/Display.html?Queue=Zydeco-Lite-App>.

=head1 SEE ALSO

=head1 AUTHOR

Toby Inkster E<lt>tobyink@cpan.orgE<gt>.

=head1 COPYRIGHT AND LICENCE

This software is copyright (c) 2020 by Toby Inkster.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=head1 DISCLAIMER OF WARRANTIES

THIS PACKAGE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.
