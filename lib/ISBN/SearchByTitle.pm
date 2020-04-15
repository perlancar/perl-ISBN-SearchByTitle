package ISBN::SearchByTitle;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::ger;

use HTTP::Tinyish;
use HTTP::UserAgentStr::Util::ByNickname qw(newest_firefox);

my $log_dump = Log::ger->get_logger(category => "dump");

our %SPEC;

$SPEC{search_isbn_by_title} = {
    v => 1.1,
    summary => 'Search ISBN from book title',
    description => <<'_',

Currently implemented by a web search for "amazon book hardcover <title>",
followed by "amazon book paperback <title>" if the first one fails. Then get the
first amazon.com URL, download the URL, and try to extract information from that
page using <pm:WWW::Amazon::Book::Extract>.

_
    args => {
        title => {
            schema => 'str*',
            pos => 0,
            req => 1,
        },
    },
};
sub search_isbn_by_title {
    require URI::Escape;

    my %args = @_;

    my $title = $args{title};

    my $res;
    my $resmeta = {};
    for my $searchq (
        "amazon book hardcover $title",
        "amazon book paperback $title",
    ) {
        #my $url = "https://www.bing.com/search?q=imdb+".URI::Escape::uri_escape($q)); # returns "No result"
        #my $url = "https://duckduckgo.com/?q=imdb+".URI::Escape::uri_escape($q); # doesn't contain any result, only script sections including boxes
        #my $url = "https://www.google.com/search?q=imdb+".URI::Escape::uri_escape($q); # cannot even connect
        my $url = "https://id.search.yahoo.com/search?p=".URI::Escape::uri_escape($searchq); # thank god this still works as of 2019-12-23
        log_trace "Search URL: $url";

        my $http_res = HTTP::Tinyish->new(agent => newest_firefox())->get($url);
        $log_dump->trace("%s", $http_res->{content});
        unless ($http_res->{success}) {
            log_warn "Couldn't get search URL %s: %s - %s",
                $url, $http_res->{status}, $http_res->{reason};
            next;
        }
        my $ct = $http_res->{content};

        my $amazon_url;
        if ($ct =~ m!(https%3a%2f%2fwww.amazon.com.+?)"!) {
            $amazon_url = URI::Escape::uri_unescape($1);
            log_trace "Found Amazon URL in search result: %s", $amazon_url;
        } else {
            log_warn "Didn't find any amazon.com search result, skipped";
            next;
        }

        $http_res = HTTP::Tinyish->new(agent => newest_firefox())->get($amazon_url);
        $log_dump->trace("%s", $http_res->{content});
        unless ($http_res->{success}) {
            log_warn "Couldn't get Amazon URL %s: %s - %s",
                $url, $http_res->{status}, $http_res->{reason};
            next;
        }
        $ct = $http_res->{content};

        require WWW::Amazon::Book::Extract;
        my $extract_res = WWW::Amazon::Book::Extract::parse_amazon_book_page(
            page_content => $ct,
        );

        if (my $isbn = $extract_res->[2]{isbn13} || $extract_res->[2]{isbn10}) {
            $res = $isbn;
            $resmeta->{'func.meta'} = $extract_res->[2];
            last;
        }
    }

    [200, "OK", $res, $resmeta];
}

1;
# ABSTRACT:

=head1 SEE ALSO
