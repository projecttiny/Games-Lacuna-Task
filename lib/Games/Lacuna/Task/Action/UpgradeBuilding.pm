package Games::Lacuna::Task::Action::UpgradeBuilding;

use 5.010;

use List::Util qw(max);

use Moose;
extends qw(Games::Lacuna::Task::Action);
with qw(Games::Lacuna::Task::Role::Building);

has 'start_building_at' => (
    isa     => 'Int',
    is      => 'rw',
    required=> 1,
    default => 2,
    documentation => 'Upgrade buildings if there are less than N buildings in the build queue',
);

has 'upgrade_buildings' => (
    isa     => 'HashRef[ArrayRef[Str]]',
    is      => 'rw',
    default => sub {
        {
            'WasteSequestration'    => ['waste','storage'],
            
            'OreStorage'            => ['ore','storage'],
            'WaterStorage'          => ['water','storage'],
            'FoodReserve'           => ['food','storage'],
            'EnergyReserve'         => ['energy','storage'],
            
            'Stockpile'             => ['global','storage'],
            'PlanetaryCommand'      => ['global','storage'],
            'DistributionCenter'    => ['global','storage'],
            
            'AtmosphericEvaporator' => ['water','production'],
            'WaterProduction'       => ['water','production'],
            'WaterPurification'     => ['water','production'],
            'WaterReclamation'      => ['water','waste','production'],
            
            'Mine'                  => ['ore','production'],
            'MiningMinistry'        => ['ore','production'],
            'OreRefinery'           => ['ore','production'],
            'WasteDigester'         => ['ore','waste','production'],
            
            'Mine'                  => ['energy','production'],
            'MiningMinistry'        => ['energy','production'],
            'OreRefinery'           => ['energy','production'],
            'WasteEnergy'           => ['energy','waste','production'],
            
            'Algae'                 => ['food','production'],
            'Apple'                 => ['food','production'],
            'Bean'                  => ['food','production'],
            'Beeldeban'             => ['food','production'],
            'Corn'                  => ['food','production'],
            'Dairy'                 => ['food','production'],
            'Beeldeban'             => ['food','production'],
            'Lapis'                 => ['food','production'],
            'Malcud'                => ['food','production'],
            'Potato'                => ['food','production'],
            'Wheat'                 => ['food','production'],
            
            'WasteTreatment'        => ['global','waste','production'],
            'WasteExchanger'        => ['global','waste','production'],

        }
    },
    documentation => 'Building uprade preferences',
);

sub description {
    return q[This task automates the upgrading of buildings if the build queue is empty];
}

sub process_planet {
    my ($self,$planet_stats) = @_;
    
    my $building_count = 0;
    my @buildings = $self->buildings_body($planet_stats->{id});
    my $timestamp = DateTime->now->set_time_zone('UTC');
    
    # Get build queue size
    foreach my $building_data (@buildings) {
        next
            if $building_data->{name} eq 'Supply Pod';
        if (defined $building_data->{pending_build}) {
            my $date_end = $self->parse_date($building_data->{pending_build}{end});
            $building_count ++
                if $timestamp < $date_end;
        }
    }
    
    my $max_ressouce_level = $self->max_resource_building_level($planet_stats->{id});
    my $max_building_level = $self->university_level() + 1;
    
    # Check if build queue is filled
    return
        if ($building_count > $self->start_building_at);
    
    my @upgradeable_buildings;
    
    if ($planet_stats->{'waste_hour'} > 0) {
        push(@upgradeable_buildings,$self->find_upgrade_buildings($planet_stats,'waste','production'));
    }
    
    if (scalar @upgradeable_buildings == 0) {
        foreach my $element (qw(waste ore water food energy)) {
            if ($planet_stats->{$element.'_capacity'}-$planet_stats->{$element.'_stored'} == 0) {
                push(@upgradeable_buildings,$self->find_upgrade_buildings($planet_stats,$element,'storage'));
            }
        }
    }
    
    if (scalar @upgradeable_buildings == 0) {
        my @production = 
            sort { $planet_stats->{$a.'_hour'} cmp $planet_stats->{$b.'_hour'} } @Games::Lacuna::Task::Constants::RESOURCES_ALL;
        foreach my $element (@Games::Lacuna::Task::Constants::RESOURCES_ALL) {
            push(@upgradeable_buildings,$self->find_upgrade_buildings($planet_stats,$element,'production'));
            last
                if scalar(@upgradeable_buildings) > 0;
        }
    }
    
    if (scalar @upgradeable_buildings == 0) {
        @upgradeable_buildings = $self->find_upgrade_buildings($planet_stats);
    }
    
    if (scalar @upgradeable_buildings) {
        @upgradeable_buildings = sort { $a->{level} <=> $b->{level} } 
            @upgradeable_buildings;
            
        foreach my $building_data (@upgradeable_buildings) {
            my $upgrade = $self->upgrade_building($planet_stats,$building_data);
            $building_count ++
                if $upgrade;
            return
                if ($building_count > $self->start_building_at);
        }
    }
    
    return;
}

sub find_upgrade_buildings {
    my ($self,$planet_stats,@tags) = @_;
    
    my @upgrade_buildings;
    my @buildings = $self->buildings_body($planet_stats->{id});
    
    my $max_ressouce_level = $self->max_resource_building_level($planet_stats->{id});
    my $max_building_level = $self->university_level() + 1;
    my $timestamp = DateTime->now->set_time_zone('UTC');
    
    BUILDING:
    foreach my $building_data (@buildings) {
        my $building_class = Games::Lacuna::Client::Buildings::type_from_url($building_data->{url});
        
        next BUILDING
            unless exists $self->upgrade_buildings->{$building_class};
        
        foreach my $tag (@tags) {
            next BUILDING
                unless $tag ~~ $self->upgrade_buildings->{$building_class};
        }
        
        next BUILDING
            if $building_data->{level} >= $max_building_level;
        
        next BUILDING
            if 'production' ~~ $self->upgrade_buildings->{$building_class}
            && $building_data->{level} >= $max_ressouce_level;
        
        if (defined $building_data->{pending_build}) {
            my $date_end = $self->parse_date($building_data->{pending_build}{end});
            next BUILDING
                if $timestamp < $date_end;
        }
        
        push(@upgrade_buildings,$building_data);
    }
    
    return @upgrade_buildings;
}

__PACKAGE__->meta->make_immutable;
no Moose;
1;
