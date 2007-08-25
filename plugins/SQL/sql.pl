# ---------------------------------------------------------------------------
# SQL
# A plugin for Movable Type
#
# Release 2.0
#
# Brad Choate
# http://bradchoate.com/
# ---------------------------------------------------------------------------
# This software is provided as-is.
# You may use it for commercial or personal use.
# If you distribute it, please keep this notice intact.
#
# Copyright (c) 2002-2006 Brad Choate
# ---------------------------------------------------------------------------
# $Id$
# ---------------------------------------------------------------------------

package MT::Plugin::SQL;

use strict;
use MT 4.0;
use base 'MT::Plugin';

our $VERSION = '2.0';
our %named_connections;

my $plugin;
MT->add_plugin($plugin = new MT::Plugin::SQL({
    name => "SQL",
    version => $VERSION,
    description => "Provides tags for running custom SQL queries against your Movable Type or other database.",
    author_name => "Brad Choate",
    author_link => "http://bradchoate.com/",
    registry => {
        tags => {
            block => {
                SQL           => 'MTSQL::Plugin::SQL',
                SQLBlogs      => 'MTSQL::Plugin::SQLBlogs',
                SQLEntries    => 'MTSQL::Plugin::SQLEntries',
                SQLPages      => 'MTSQL::Plugin::SQLEntries',
                SQLComments   => 'MTSQL::Plugin::SQLComments',
                SQLCategories => 'MTSQL::Plugin::SQLCategories',
                SQLFolders    => 'MTSQL::Plugin::SQLCategories',
                SQLPings      => 'MTSQL::Plugin::SQLPings',
                SQLAuthors    => 'MTSQL::Plugin::SQLAuthors',
                SQLHeader     => 'MTSQL::Plugin::SQLHeader',
                SQLFooter     => 'MTSQL::Plugin::SQLFooter',
            },
            function => {
                SQLColumn     => 'MTSQL::Plugin::SQLColumn',
            },
            modifier => {
                quote_sql     => sub {
                    require MTSQL::Plugin;
                    return MTSQL::Plugin::quote_sql(@_);
                },
            },
        },
    },
    settings => new MT::PluginSettings([
        ['connections', { Default => {
            'example-mysql' => {
                dsn => 'dbi:mysql:database=name;host=hostname;port=port',
            },
            'example-postgres' => {
                dsn => 'dbi:Pg:dbname=name;host=hostname;port=port',
            },
            'example-sqlite' => {
                dsn => 'dbi:SQLite:dbname=/path/to/dbfile',
            },
            'example-oracle' => {
                dsn => 'dbi:Oracle:host=hostname;sid=sid',
            },
        }}],
        ['admin_restrict', { Default => 0, Scope => 'system' }],
    ]),
    callbacks => {
        TakeDown => \&takedown,
        'cms_pre_save.template', => \&presave_template,
    },
}));

sub instance {
    $plugin;
}

# A small permission check to make sure the active user has the
# rights to save a template that uses MT-SQL tags or not. If they
# don't, give them an error and send them back to the template edit
# screen.
sub presave_template {
    my ($cb, $app, $obj) = @_;

    my $restrict = $plugin->get_config_value('admin_restrict');
    return 1 unless $restrict;

    unless ($app->user->is_superuser()) {
        if ($obj->text =~ m/<\$?MT:?SQL(Blogs|Entries|Comments|Categories|Pings|Authors|Header|Footer|Column)?\b/i) {
            return $cb->error("You are not permitted to use the SQL plugin tags. These tags are restricted for use by system administrators only.");
        }
    }

    1;
}

sub save_config {
    my $plugin = shift;
    my ($param, $scope) = @_;
    my $pdata = $plugin->get_config_obj($scope);
    my $data = $pdata->data() || {};
    my $conns = {};

    foreach my $k (keys %$param) {
        if ($k =~ m/^conn_name_(\d+)/) {
            my $num = $1;
            my $dsn = $param->{"conn_dsn_$num"};
            next unless $dsn;
            $conns->{$param->{$k}} = {
                dsn => $param->{"conn_dsn_$num"},
                username => $param->{"conn_username_$num"},
                password => $param->{"conn_password_$num"},
            };
        }
    }

    $data->{connections} = $conns;
    if ($scope eq 'system') {
        $data->{admin_restrict} = $param->{admin_restrict};
    }
    $pdata->data($data);
    delete $plugin->{__config_obj} if exists $plugin->{__config_obj};
    $pdata->save() or die $pdata->errstr;
}

sub config_template {
    my $plugin = shift;
    my ($param, $scope) = @_;
    my $conns = $plugin->get_config_value('connections', $scope) || {};
    $param->{connection_count} = keys %$conns;
    my $c = 0;
    my @data;
    foreach my $name (sort keys %$conns) {
        my $conn = $conns->{$name};
        $c++;
        push @data, { num => $c, name => $name, %$conn };
    }
    $param->{connection_loop} = \@data;
    if ($scope eq 'system') {
        $param->{admin_restrict} = $plugin->get_config_value('admin_restrict');
        $param->{scope_system} = 1;
    }
    $plugin->load_tmpl('config.tmpl'); # $plugin->SUPER::load_config(@_);
}

# Disconnects any opened database connections made during the active
# request.
sub takedown {
    foreach my $conn (keys %named_connections) {
        my $dbh = $named_connections{$conn};
        if (ref $dbh ne 'HASH') {
            $dbh->disconnect;
        }
    }
    %named_connections = ();
}

__END__

=head1 NAME

SQL - A plugin for Movable Type.

=head1 DESCRIPTION

This plugin gives you the ability to select your MT data using SQL queries.
For some, this can be incredibly flexible and powerful. If you're
unfamiliar with SQL, you may want to review the L<RECIPIES> section for
examples that may be helpful in understanding how this plugin works.

=head1 CONFIGURATION

This plugin has a configuration screen in Movable Type. The system-wide
and blog-level configuration screens allows you to set up a list of
named connections. This connection list is used in conjunction with the
E<lt>MTSQLE<gt> tag to do abitrary SQL queries against any database
your server can access.

The system-wide configuration screen also has a permission-based setting
that lets you restrict who can use the SQL tags. By default, anyone with
template-edit permissions can use the tags, but if you so choose, you may
restrict access to system-administrators only. This may be prudent, since
the E<lt>MTSQLE<gt> tag does not protect against updating or inserting
records into the database, nor does it limit access to particular tables.

=head1 GLOBAL ATTRIBUTES

=head2 quote_dbh

This attribute allows you to escape special characters you may embed
within your queries when populating the query with values from a MT
tag. For instance:

    <MTSQL query="select * from mt_author where author_nickname='[MTEntryAuthor quote_dbh='1']'">

In the event that E<lt>MTEntryAuthorE<gt> contains quotes or other
special characters, quote_dbh will escape these characters so the query
is formed properly.

=head1 TAGS

This plugin provides a number of container tags used for doing SQL-based
queries to gather MT object data.

=head2 E<lt>MTSQLE<gt>

This is a general-purpose tag used to issue a query to your database.
Being a container tag, it will produce output for each row returned from
the query. To output the value of a column from the query, use the
E<lt>MTSQLColumnE<gt> tag.

Example:

    <MTSQL query="select now()"><MTSQLColumn column="1"></MTSQL>

The following attributes apply to this tag:

=over 4

=item * query

The SQL query to execute. This is typically a SELECT query, but it can
be any SQL statement that is valid for your database.

    <MTSQL query="select count(*) from mt_entry where entry_status=2">
    # of entries for this MT installation: <MTSQLColumn column="1">
    </MTSQL>

=item * default

In the event that now rows are returned by the query, you can specify
a value using the default attribute which is outut instead.

    <MTSQL query="select 1 from mt_entry where entry_status=1"
           default="No draft entries">Draft entries exist.</MTSQL>

=item * connection

A named connection to use to issue the query against. See L<CONFIGURATION>
for more information about named connections.

    <MTSQL connection="other_db"
           query="select count(*) from pending_tickets">
    <MTSQLColumn column="1">
    </MTSQL>

=back

=head2 E<lt>MTSQLHeaderE<gt>

A conditional tag that whose content is output if the first row of
SQL container tag is being processed.

=head2 E<lt>MTSQLFooterE<gt>

A conditional tag that whose content is output if the last row of
SQL container tag is being processed.

=head2 E<lt>$MTSQLColumn$E<gt>

Outputs a single column's data from the current row of an active
query result.

=over 4

=item * column

A number to reference a column by number (first column is '1'). A name
if you want to refer to columns by name.

    <$MTSQLColumn column="1"$>

    <$MTSQLColumn column="entry_title"$>

=item * format

Allows you to specify a 'sprintf' type specifier to format the content
of this column.

    <$MTSQLColumn column="count" format="%06d"$>

=item * default

In the event that there is no value for the specified column, the default
attribute lets you specify a value to output instead.

    <$MTSQLColumn column="entry_excerpt" default="Excerpt is null"$>

=back

=head2 E<lt>MTSQLBlogsE<gt>

Lets you use a SQL query to fetch a selection of blogs. One of the columns
returned in this query should be named 'blog_id'. It will be used to 
load the L<MT::Blog> object.

Here's an example that generates a list of all blogs installed along with
the count of their entries (sorted by count, with the ones having the most
entries first):

    <MTSQLBlogs query="select blog_id, count(*) c
         from mt_blog, mt_entry
        where entry_blog_id = blog_id
          and entry_status = 2
        group by blog_id
        order by c desc">
    <MTSQLHeader><ul></MTSQLHeader>
    <li><a href="<MTBlogURL>"><MTBlogName></a>: <MTSQLColumn column="c"></li>
    <MTSQLFooter></ul></MTSQLFooter>
    </MTSQLBlogs>

=over 4

=item * query

The text of the query to issue to select blog IDs. This query must include
a column in the result named 'blog_id'.

=item * default

The value you want to output in the event that no blogs were selected.

=back

=head2 E<lt>MTSQLEntriesE<gt>

Lets you use a SQL query to fetch a selection of entries. One of the columns
returned in this query should be named 'entry_id'. It will be used to 
load the L<MT::Entry> object.

I<B<Note:> When selecting entries, you probably will want to filter for
entries whose 'entry_status' column has a value of 2. This is the setting
for a published entry. By not selecting for 'entry_status=2', you will
include draft or scheduled entries in addition to published entries.>

=over 4

=item * query

The text of the query to issue to select entry IDs. This query must include
a column in the result named 'entry_id'.

=item * unfiltered

By default, this tag will only select entries that are appropriate for
the current weblog. If you wish it to select entries across weblogs,
use the 'unfiltered' attribute.

    <MTSQLEntries query="select entry_id from mt_entry order by entry_author_id" unfiltered="1">

=item * default

The value you want to output in the event that no entries were selected.

=back

=head2 E<lt>MTSQLCommentsE<gt>

Lets you use a SQL query to fetch a selection of comments. One of the columns
returned in this query should be named 'comment_id'. It will be used to 
load the L<MT::Comment> object.

I<B<Note:> When selecting comments, you probably will want to filter for
comments whose 'comment_visible' column has a value of 1. This is the
state of published comments. Without this filter, your query will include
pending or junked comments.>

=over 4

=item * query

The text of the query to issue to select comment IDs. This query must include
a column in the result named 'comment_id'.

=item * unfiltered

By default, this tag will only select comments that are appropriate for
the current weblog. If you wish it to select comments across weblogs,
use the 'unfiltered' attribute.

=item * default

The value you want to output in the event that no comments were selected.

=back

=head2 E<lt>MTSQLCategoriesE<gt>

Lets you use a SQL query to fetch a selection of categories. One of the
columns returned in this query should be named 'category_id'. It will be
used to load the L<MT::Category> object.

=over 4

=item * query

The text of the query to issue to select category IDs. This query must include
a column in the result named 'category_id'.

=item * unfiltered

By default, this tag will only select categories that are appropriate for
the current weblog. If you wish it to select categories across weblogs,
use the 'unfiltered' attribute.

=item * default

The value you want to output in the event that no categories were selected.

=back

=head2 E<lt>MTSQLPingsE<gt>

Lets you use a SQL query to fetch a selection of TrackBack pings. One of
the columns returned in this query should be named 'tbping_id'. It will
be used to load the L<MT::TBPing> object.

I<B<Note:> When selecting comments, you probably will want to filter for
comments whose 'comment_visible' column has a value of 1. This is the
state of published comments. Without this filter, your query will include
pending or junked comments.>

=over 4

=item * query

The text of the query to issue to select TrackBack ping IDs. This query must
include a column in the result named 'tbping_id'.

=item * unfiltered

By default, this tag will only select TrackBacks that are appropriate for
the current weblog. If you wish it to select TrackBacks across weblogs,
use the 'unfiltered' attribute.

=item * default

The value you want to output in the event that no TrackBacks were selected.

=back

=head2 E<lt>MTSQLAuthorsE<gt>

Lets you use a SQL query to fetch a selection of authors. One of the
columns returned in this query should be named 'author_id'. It will be
used to load the L<MT::Author> object.

This tag is more useful with the MT-Authors plugin.

I<B<Note:> When selecting for authors with the 'unfiltered' attribute, you
will probably want to filter for authors whose 'author_type' column has a
value of 1. This is the value used for identifying actual author records as
opposed to authenticated commenters (who are also stored in this table).
Authenticated commenters have a 'author_type' value of 2. Filtered author
selections automatically require a type of 1 be present.>

=over 4

=item * query

The text of the query to issue to select author IDs. This query must include
a column in the result named 'author_id'.

=item * unfiltered

By default, this tag will only select authors that have access to
the current weblog. If you wish it to select authors across weblogs,
use the 'unfiltered' attribute.

=item * default

The value you want to output in the event that no authors were selected.

=back

=head1 RECIPIES

The following examples demonstrate the power and flexibility of the
SQL plugin. The examples below are written for MySQL, but could be
altered to work with most any database.

=head2 Most Active Entries

This query selects the top 5 published entries (across all blogs) that
have the most published comments and TrackBacks. The actual count can be
retrieved using C<E<lt>MTSQLColumn column="2"E<gt>>.

    select entry_id, count(distinct comment_id) + count(distinct tbping_id)
      from mt_entry, mt_comment, mt_tbping, mt_trackback
     where entry_id = comment_entry_id
       and entry_id = trackback_entry_id
       and tbping_tb_id = trackback_id
       and entry_status = 2
       and comment_visible = 1
       and tbping_visible = 1
     group by entry_id
     order by 2 desc
     limit 5

=head2 Top Authors

Here's a query to select the top 5 authors on your install (again,
across all weblogs).

    select author_id, author_name, count(*)
      from mt_author, mt_entry
     where entry_author_id = author_id
       and entry_status = 2
     group by author_id, author_name
     order by 3 desc
     limit 5

If you don't the I<MT-Authors> plugin, then you can run this using the
E<lt>MTSQLE<gt> tag and select the author name using
C<E<lt>MTSQLColumn column="author_name"E<gt>> and the count using
C<E<lt>MTSQLColumn column="3"E<gt>>.

=head2 Posts by Year

Perhaps you want to display a grid of years your blog has been around
and the number of entries published for each?

    select year(entry_created_on) y, count(*) c
       from mt_entry
      where entry_status = 2
        and entry_blog_id = 4
      group by year(entry_created_on)
      order by year(entry_created_on)

Output these results using C<E<lt>MTSQLColumn column="y"E<gt>> and
C<E<lt>MTSQLColumn column="c"E<gt>>.

=head1 AVAILABILITY

The latest release of this plugin can be found at this address:

    http://code.sixapart.com/

=head1 LICENSE

This plugin is published under the Artistic License.

=head1 AUTHOR & COPYRIGHT

Copyright 2002-2006, Brad Choate

=cut
