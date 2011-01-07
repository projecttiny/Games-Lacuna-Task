package Games::Lacuna::Task::Role::Helper;

use 5.010;
use Moose::Role;

use List::Util qw(max);

use Games::Lacuna::Task::Cache;
use Games::Lacuna::Task::Constants;
use Data::Dumper;
use DateTime;

sub build_object {
    my ($self,$class,@params) = @_;
    
    # Get class and id from status hash
    if (ref $class eq 'HASH') {
        push(@params,'id',$class->{id});
        $class = $class->{url};
    }
    
    # Get class from url
    if ($class =~ m/^\//) {
        $class = 'Buildings::'.Games::Lacuna::Client::Buildings::type_from_url($class);
    }
    
    # Build class name
    $class = 'Games::Lacuna::Client::'.ucfirst($class)
        unless $class =~ m/^Games::Lacuna::Client::(.+)$/;
    
    return $class->new(
        client  => $self->client->client,
        @params
    );
}

sub empire_status {
    my $self = shift;
    
    return $self->lookup_cache('empire')
        || $self->request(
            object      => $self->build_object('Empire'),
            method      => 'get_status',
        )->{empire};
}

sub planets {
    my $self = shift;
    
    my @planets;
    foreach my $planet ($self->planet_ids) {
        push(@planets,$self->body_status($planet));
    }
    return @planets;
}

sub body_status {
    my ($self,$body) = @_;
    
    my $key = 'body/'.$body;
    my $body_status = $self->lookup_cache($key);
    return $body_status
        if $body_status;
    
    $body_status = $self->request(
        object  => $self->build_object('Body', id => $body),
        method  => 'get_status',
    )->{body};
    
    return $body_status;
}

sub find_building {
    my ($self,$body,$type) = @_;
    
    # Get buildings
    my @results;
    foreach my $building_data ($self->buildings_body($body)) {
        next
            unless $building_data->{name} eq $type;
        push (@results,$building_data);
    }
    
    @results = (sort { $b->{level} <=> $a->{level} } @results);
    return wantarray ? @results : $results[0];
}

sub buildings_body {
    my ($self,$body) = @_;
    
    my $key = 'body/'.$body.'/buildings';
    my $buildings = $self->lookup_cache($key) || $self->request(
        object  => $self->build_object('Body', id => $body),
        method  => 'get_buildings',
    )->{buildings};
    
    my @results;
    foreach my $building_id (keys %{$buildings}) {
        $buildings->{$building_id}{id} = $building_id;
        push(@results,$buildings->{$building_id});
    }
    return @results;
}

sub university_level {
    my ($self) = @_;
    
    my @university_levels;
    foreach my $planet ($self->planet_ids) {
        my $university = $self->find_building($planet,'University');
        next 
            unless $university;
        push(@university_levels,$university->{level});
    }
    return max(@university_levels);
}

sub planet_ids {
    my $self = shift;
    
    my $empire_status = $self->empire_status();
    return keys %{$empire_status->{planets}};
}

sub home_planet_id {
    my $self = shift;
    
    my $empire_status = $self->empire_status();
    
    return $empire_status->{home_planet_id};
}

sub parse_date {
    my ($self,$date) = @_;
    
    return
        unless defined $date;
    
    if ($date =~ m/^
        (?<day>\d{2}) \s
        (?<month>\d{2}) \s
        (?<year>20\d{2}) \s
        (?<hour>\d{2}) :
        (?<minute>\d{2}) :
        (?<second>\d{2}) \s
        \+(?<timezoneoffset>\d{4})
        $/x) {
        $self->log('warn','Unexpected timezone offset %04i',$+{timezoneoffset})
            if $+{timezoneoffset} != 0;
        return DateTime->new(
            (map { $_ => $+{$_} } qw(year month day hour minute second)),
            time_zone   => 'UTC',
        );
    }
    
    return;
}

sub can_afford {
    my ($self,$planet_data,$cost) = @_;
    
    foreach my $ressource (qw(food ore water energy)) {
        return 0
            if (( $planet_data->{$ressource.'_stored'} - 1000 ) < $cost->{$ressource});
    }
    
    return 0
        if (defined $cost->{waste} 
        && ($planet_data->{'waste_capacity'} - $planet_data->{'waste_stored'}) < $cost->{waste});
    
    return 1;
}

no Moose::Role;
1;
