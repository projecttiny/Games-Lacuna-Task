package Games::Lacuna::Task::Role::Ships;

use 5.010;
use Moose::Role;

use List::Util qw(min sum max first);
use Games::Lacuna::Task::Utils qw(parse_ship_type);

sub ships {
    my ($self,%params) = @_;
    
    my $planet_stats = $params{planet};
    my $type = parse_ship_type($params{type});
    my $name_prefix = $params{name_prefix};
    my $quantity = $params{quantity} // 1;
    my $travelling = $params{travelling} // 0;
    
    return
        unless $type && defined $planet_stats;
    
    # Get space port
    my @spaceports = $self->find_building($planet_stats->{id},'SpacePort');
    return
        unless scalar @spaceports;
    
    my $spaceport_object = $self->build_object($spaceports[0]);
    
    # Get all available ships
    my $ships_data = $self->request(
        object  => $spaceport_object,
        method  => 'view_all_ships',
        params  => [ { no_paging => 1 } ],
    );
    
    # Initialize vars
    my @known_ships;
    my @avaliable_ships;
    my $building_ships = 0;
    my $travelling_ships = 0;
    
    # Find all avaliable and buildings ships
    SHIPS:
    foreach my $ship (@{$ships_data->{ships}}) {
        push(@known_ships,$ship->{id});
        
        next SHIPS
            unless $ship->{type} eq $type;
        
        # Check ship prefix and flags
        if (defined $name_prefix) {
            next SHIPS
                 unless $ship->{name} =~ m/^$name_prefix/i;
        } else {
            next SHIPS
                if $ship->{name} =~ m/\!/; # Indicates reserved ship
        }
        
        # Get ship activity
        if ($ship->{task} eq 'Docked') {
            push(@avaliable_ships,$ship->{id});
        } elsif ($ship->{task} eq 'Building') {
            $building_ships ++;
        } elsif ($ship->{task} eq 'Travelling' && $travelling) {
            $travelling_ships ++;
        }
        
        # Check if we have enough ships
        return @avaliable_ships
            if $quantity > 0 && scalar(@avaliable_ships) >= $quantity;
    }
    
    # Check if we have a shipyard
    my @shipyards = $self->find_building($planet_stats->{id},'Shipyard');
    return @avaliable_ships
        unless (scalar @shipyards);
    
    # Calc max spaceport capacity
    my $max_ships_possible = sum map { $_->{level} * 2 } @spaceports;
    
    # Quantity is defined as free-spaceport slots
    my $max_build_quantity;
    if ($quantity < 0) {
        $max_build_quantity = max($max_ships_possible - $ships_data->{number_of_ships} + $quantity,0);
    # Quantity is defined as number of ships
    } else {
        $max_build_quantity = min($max_ships_possible - $ships_data->{number_of_ships},$quantity);
    }
    
    # Check if we can build new ships
    return @avaliable_ships
        unless ($max_build_quantity > 0);
    
    # Calc current ships
    my $total_ships = scalar(@avaliable_ships) + $building_ships + $travelling_ships;
    
    # We have to build new ships
    my %available_shipyards;
    my $new_building = 0;
    my $total_queue_size = 0;
    my $total_max_queue_size = 0;
    
    # Loop all shipyards to get levels ans workload
    SHIPYARDS:
    foreach my $shipyard (@shipyards) {
        my $shipyard_id = $shipyard->{id};
        my $shipyard_object = $self->build_object($shipyard);
        
        # Get build queue
        my $shipyard_queue_data = $self->request(
            object  => $shipyard_object,
            method  => 'view_build_queue',
            params  => [1],
        );
        
        my $shipyard_queue_size = $shipyard_queue_data->{number_of_ships_building} // 0;
        $total_max_queue_size += $shipyard->{level};
        $total_queue_size += $shipyard_queue_size;
        
        # Check available build slots
        next SHIPYARDS
            if $shipyard->{level} <= $shipyard_queue_size;
            
        $available_shipyards{$shipyard_id} = {
            object              => $shipyard_object,
            level               => $shipyard->{level},
            seconds_remaining   => ($shipyard_queue_data->{building}{work}{seconds_remaining} // 0),
            available           => ($shipyard->{level} - $shipyard_queue_size), 
        };
    }
    
    # Check global build queue size
    return @avaliable_ships
        if $total_queue_size >= $total_max_queue_size;
    
    # Check if shipyards are available
    return @avaliable_ships
        unless scalar keys %available_shipyards;
    
    # Repeat until we have enough ships
    BUILD_QUEUE:
    while ($new_building < $max_build_quantity) {
        
        my $shipyard = 
            first { $_->{available} > 0 }
            sort { $a->{seconds_remaining} <=> $b->{seconds_remaining} } 
            values %available_shipyards;
        
        last BUILD_QUEUE
            unless defined $shipyard;
        
        eval {
            # Build ship
            my $ship_building = $self->request(
                object  => $shipyard->{object},
                method  => 'build_ship',
                params  => [$type],
            );
            $self->log('notice',"Building %s on %s at shipyard level %i",$type,$planet_stats->{name},$shipyard->{level});
            
            $shipyard->{seconds_remaining} = $ship_building->{building}{work}{seconds_remaining};
            
            # Remove shipyard slot
            $shipyard->{available} --;
        };
        if ($@) {
            $self->log('warn','Could not build %s: %s',$type,$@);
            last BUILD_QUEUE;
        }
        
        $new_building ++;
        $total_ships ++;
    }
    
    # Rename new ships
    if ($new_building > 0
        && defined $name_prefix) {
            
        # Get all available ships
        my $ships_data = $self->request(
            object  => $spaceport_object,
            method  => 'view_all_ships',
            params  => [ { no_paging => 1 } ],
        );
        
        NEW_SHIPS:
        foreach my $ship (@{$ships_data->{ships}}) {
            next NEW_SHIPS
                if $ship->{id} ~~ \@known_ships;
            next NEW_SHIPS
                unless $ship->{type} eq $type;
            
            my $name = $name_prefix .': '.$ship->{name}.'!';
            
            $self->log('notice',"Renaming new ship to %s on %s",$name,$planet_stats->{name});
            
            # Rename ship
            $self->request(
                object  => $spaceport_object,
                method  => 'name_ship',
                params  => [$ship->{id},$name],
            );
        }
    }
    
    return @avaliable_ships;
}

no Moose::Role;
1;

=encoding utf8
=head1 NAME

Games::Lacuna::Task::Role::Ships - Helper methods for fetching and building ships

=head1 SYNOPSIS

    package Games::Lacuna::Task::Action::MyTask;
    use Moose;
    extends qw(Games::Lacuna::Task::Action);
    with qw(Games::Lacuna::Task::Role::Ships);
    
=head1 DESCRIPTION

This role provides ship-related helper methods.

=head1 METHODS

=head2 ships

    my @avaliable_scows = $self->ships(
        planet          => $planet_stats,
        ships_needed    => 3, # get three
        ship_type       => 'scow',
    );

Tries to fetch the given number of available ships. If there are not enough 
ships available then the required number of ships are built.

The following arguments are accepted

=over

=item * planet

Planet data has [Required]

=item * ships_needed

Number of required ships. If ships_needed is a negative number it will return
all matching ships and build as many new ships as possible while keeping 
ships_needed * -1 space port slots free [Required]

=item  * ship_type

Ship type [Required]

=item * travelling

If true will not build new ships if there are matchig ships currently 
travelling

=item * name_prefix

Will only return ships with the given prefix in their names. Newly built ships
will be renamed to add the prefix.

=back

=cut
