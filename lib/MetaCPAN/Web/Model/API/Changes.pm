package MetaCPAN::Web::Model::API::Changes;
use Moose;
extends 'MetaCPAN::Web::Model::API';

use MetaCPAN::Web::Model::API::Changes::Parser;
use Try::Tiny;

sub get {
    my ( $self, @path ) = @_;
    $self->request( '/changes/' . join( q{/}, @path ) );
}

sub last_version {
    my ( $self, $response, $release ) = @_;
    my $releases;
    if ( !exists $response->{content} or $response->{documentation} ) {
    }
    else {
        # I guess we have a propper changes file? :P
        try {
            my $changelog
                = MetaCPAN::Web::Model::API::Changes::Parser->parse(
                $response->{content} );
            $releases = $changelog->{releases};
        }
        catch {
            # we don't really care?
            warn "Error parsing changes: $_" if $ENV{CATALYST_DEBUG};
        };
    }
    return [] unless $releases && @$releases;

    my @releases = sort { $b->[0] <=> $a->[0] }
        map {
        my $v = $_->{version};
        $v =~ s/-TRIAL$//;
        my $dev = $_->{version} =~ /_|-TRIAL$/;
        [ version->parse($v), $v, $dev, $_ ];
        } @$releases;

    my @changelogs;
    my $found;
    for my $r (@releases) {
        if ($found) {
            if ( $r->[2] ) {
                push @changelogs, $r->[3];
            }
            else {
                last;
            }
        }
        elsif ( $r->[0] eq $release->{version} ) {
            push @changelogs, $r->[3];
            $found = 1;
        }
    }
    return [ map { $self->filter_release_changes( $_, $release ) }
            @changelogs ];
}

sub find_changelog {
    my ( $self, $version, $releases ) = @_;

    foreach my $rel (@$releases) {
        return $rel
            if ( $rel->{version} eq $version
            || $rel->{version} eq "$version-TRIAL" );
    }
}

my $rt_cpan_base = 'https://rt.cpan.org/Ticket/Display.html?id=';
my $rt_perl_base = 'https://rt.perl.org/Ticket/Display.html?id=';
my $sep          = qr{[-:]|\s*[#]?};

sub _link_issues {
    my ( $self, $change, $gh_base, $rt_base ) = @_;
    $change =~ s{(
      (?:
        (
          \b(?:blead)?perl\s+(?:RT|bug)$sep
        |
          (?<=\[)(?:blead)?perl\s+$sep
        |
          \brt\.perl\.org\s+\#
        |
          \bP5\#
        )
      |
        (
          \bCPAN\s+(?:RT|bug)$sep
        |
          (?<=\[)CPAN\s+$sep
        |
          \brt\.cpan\.org\s+\#
        )
      |
        (\bRT$sep)
      |
        (\b(?:GH|PR)$sep)
      |
        ((?:\bbug\s*)?\#)
      )
      (\d+)\b
    )}{
        my $text = $1;
        my $issue = $7;
        my $base
          = $2 ? $rt_perl_base
          : $3 ? $rt_cpan_base
          : $4 ? $rt_base
          : $5 ? $gh_base
          # this form is non-specific, so guess based on issue number
          : ($gh_base && $issue < 10000)
                ? $gh_base
                : $rt_base
        ;
        $base ? qq{<a href="$base$issue">$text</a>} : $text;
    }xgei;

    return $change;
}

sub filter_release_changes {
    my ( $self, $changelog, $release ) = @_;

    my $gh_base;
    my $rt_base;
    my $bt = $release->{resources}{bugtracker}
        && $release->{resources}{bugtracker}{web};
    my $repo = $release->{resources}{repository};
    $repo = ref $repo ? $repo->{url} : $repo;
    if ( $bt && $bt =~ m|^https?://github\.com/| ) {
        $gh_base = $bt;
        $gh_base =~ s{/*$}{/};
    }
    elsif ( $repo && $repo =~ m|\bgithub\.com/([^/]+/[^/]+)| ) {
        my $name = $1;
        $name =~ s/\.git$//;
        $gh_base = "https://github.com/$name/issues/";
    }
    if ( $bt && $bt =~ m|\brt\.perl\.org\b| ) {
        $rt_base = $rt_perl_base;
    }
    else {
        $rt_base = $rt_cpan_base;
    }

    my @entries_list = $changelog->{entries};

    while ( my $entries = shift @entries_list ) {
        for my $entry (@$entries) {
            for ( $entry->{text} ) {
                s/&/&amp;/g;
                s/</&lt;/g;
                s/>/&gt;/g;
                s/"/&quot;/g;
            }
            $entry->{text}
                = $self->_link_issues( $entry->{text}, $gh_base, $rt_base );
            push @entries_list, $entry->{entries}
                if $entry->{entries};
        }
    }

    return $changelog;
}

__PACKAGE__->meta->make_immutable;

1;
