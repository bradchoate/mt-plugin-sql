package MTSQL::Plugin;

use strict;

sub SQL {
    my ($ctx, $args, $cond) = @_;
    my $dbh = _get_dbh($ctx, $args);
    return unless $dbh;

    local $ctx->{__stash}{SQLDbh} = $dbh;

    my $builder = $ctx->stash('builder');
    my $tokens = $ctx->stash('tokens');

    my $query = build_expr($ctx, $args->{query}, $cond);
    return unless $query;

    my $sth = $dbh->prepare($query);
    return $ctx->error("Error in query: ".$dbh->errstr) if $dbh->errstr;

    $sth->execute();
    return $ctx->error("Error in query: ".$sth->errstr) if $sth->errstr;

    my $res = '';
    my $row = 0;
    my @row;
    my @next_row;
    @next_row = $sth->fetchrow_array();
    local $ctx->{__stash}{SQLSth} = $sth;
    while (@next_row) {
        @row = @next_row;
        $row++;
        @next_row = $sth->fetchrow_array();

        local $ctx->{__stash}{SQLRow} = \@row;
        my $out = $builder->build($ctx, $tokens, {
            %$cond,
            SQLHeader => $row == 1,
            SQLFooter => !@next_row
        });
        if (!defined $out) {
            $sth->finish;
            return $ctx->error($builder->errstr);
        }
        $res .= $out;
    }
    $sth->finish;
    if ($row) {
        return $res;
    } else {
        $ctx->stash('tokens', $tokens);
        return defined $args->{default} ? build_expr($ctx, $args->{default}, $cond) : '';
    }
}

sub SQLHeader { shift->slurp(@_) }
sub SQLFooter { shift->slurp(@_) }

sub SQLColumn {
    my ($ctx, $args, $cond) = @_;
    my $col = $args->{column};
    my $format = $args->{format};
    return $ctx->error("A column attribute must be given") unless $col;

    my $row = $ctx->stash('SQLRow');
    my $sth = $ctx->stash('SQLSth');
    return $ctx->error("SQLColumn must be used inside a SQL tag") unless $row && $sth;

    my $value;
    if ($col =~ /^\d+$/) {
        # column number
        $value = $row->[$col-1];
    } else {
        # try the name instead
        $value = $row->[$sth->{NAME_hash}{$col}];
    }
    if (defined $value && defined $format) {
        $value = sprintf($format, $value);
    }
    if (defined $value) {
        return $value;
    } else {
        return defined $args->{default} ? build_expr($ctx, $args->{default}, $cond) : '';
    }
}

sub SQLBlogs {
    my ($ctx, $args, $cond) = @_;
    my $dbh = _get_dbh($ctx, $args);
    return unless $dbh;

    local $ctx->{__stash}{SQLDbh} = $dbh;

    require MT::Blog;
    my $blog_id = $ctx->stash('blog_id');
    my $blog = $ctx->stash('blog');
    my $builder = $ctx->stash('builder');
    my $tokens = $ctx->stash('tokens');
    return $ctx->error("You did not specify a query") unless $args->{query};
    my $query = build_expr($ctx, $args->{query}, $cond);
    return unless $query;

    my $sth = $dbh->prepare($query);
    return $ctx->error("Error in query: ".$dbh->errstr) if $dbh->errstr;

    $sth->execute();
    return $ctx->error("Error in query: ".$sth->errstr) if $sth->errstr;

    # sanity check-- 'entry_id' must be a valid column:
    if (!exists $sth->{NAME_hash}{blog_id}) {
        $sth->finish;
        return $ctx->error("You must specify 'blog_id' as one of the columns of your query.");
    }

    my $res = '';
    my ($b, @row);
    my ($next_blog, @next_row) = _next_blog($sth);
    my $row = 0;
    local $ctx->{__stash}{SQLSth} = $sth;
    while (@next_row) {
        ($b, @row) = ($next_blog, @next_row);
        $row++;
        local $ctx->{__stash}{SQLRow} = \@row;
        local $ctx->{__stash}{blog} = $b;
        local $ctx->{__stash}{blog_id} = $b->id;
        ($next_blog, @next_row) = _next_blog($sth);
        my $out = $builder->build($ctx, $tokens, {
            %$cond,
            SQLHeader => $row == 1,
            SQLFooter => !@next_row,
        });
        return $ctx->error( $builder->errstr ) unless defined $out;
        $res .= $out;
    }
    $sth->finish;

    # restore current blog in case we fiddled with it...
    $ctx->{__stash}{blog_id} = $blog_id;
    $ctx->{__stash}{blog} = $blog;
    if ($res) {
        return $res;
    } else {
        $ctx->stash('tokens', $tokens);
        return defined $args->{default} ? build_expr($ctx, $args->{default}, $cond) : '';
    }
}

sub _next_blog {
    my ($sth) = @_;
    my @row = $sth->fetchrow_array();
    return (undef, ()) unless @row;
    while (@row) {
        my $blog_id = $row[$sth->{NAME_hash}{blog_id}];
        my $blog = MT::Blog->load($blog_id);
        return (undef, ()) unless $blog;
        return ($blog, @row);
    }
    return (undef, ());
}

sub SQLEntries {
    my($ctx, $args, $cond) = @_;
    my $dbh = _get_dbh($ctx, $args);
    return unless $dbh;

    local $ctx->{__stash}{SQLDbh} = $dbh;

    require MT::Entry;
    my $class = $ctx->stash('tag') =~ m/pages/i ? 'page' : 'entry';

    my $builder = $ctx->stash('builder');
    my $tokens = $ctx->stash('tokens');
    return $ctx->error("You did not specify a query") unless $args->{query};
    my $blog_id = $ctx->stash('blog_id');
    my $blog = $ctx->stash('blog');
    my $query = build_expr($ctx, $args->{query}, $cond);
    return unless $query;

    my $sth = $dbh->prepare($query);
    return $ctx->error("Error in query: ".$dbh->errstr) if $dbh->errstr;

    $sth->execute();
    return $ctx->error("Error in query: ".$sth->errstr) if $sth->errstr;

    # sanity check-- 'entry_id' must be a valid column:
    if (!exists $sth->{NAME_hash}{entry_id}) {
        $sth->finish;
        return $ctx->error("You must specify 'entry_id' as one of the columns of your query.");
    }
    my $unfiltered = $args->{unfiltered};

    my($last_day, $next_day) = ('00000000') x 2;
    my $res = '';
    my %blogs;
    my ($e, @row);
    my ($next_entry, @next_row) = _next_entry($sth, $unfiltered, $blog_id, $class);
    my $row = 0;
    local $ctx->{__stash}{SQLSth} = $sth;
    while (@next_row) {
        ($e, @row) = ($next_entry, @next_row);
        $row++;
        local $ctx->{__stash}{SQLRow} = \@row;
        ($next_entry, @next_row) = _next_entry($sth, $unfiltered, $blog_id, $class);

        # if we're not unfiltered (filtering is ON)...
        if ($unfiltered) {
            if ($e->blog_id != $ctx->{__stash}{blog_id}) {
                my $new_blog_id = $e->blog_id;
                if (!exists $blogs{$new_blog_id}) {
                    $blogs{$new_blog_id} = MT::Blog->load($new_blog_id)
                        or return $ctx->error("Error loading blog, id = $new_blog_id");
                }
                $ctx->{__stash}{blog_id} = $new_blog_id;
                $ctx->{__stash}{blog} = $blogs{$new_blog_id};
            }
        }
        local $ctx->{__stash}{entry} = $e;
        local $ctx->{current_timestamp} = $e->created_on;
        my $this_day = substr $e->created_on, 0, 8;
        my $next_day = $this_day;
        my $footer = 0;
        if (@next_row) {
            $next_day = substr($next_entry->created_on, 0, 8);
            $footer = $this_day ne $next_day;
        } else {
            $footer++;
        }
        my $out = $builder->build($ctx, $tokens, {
            %$cond,
            DateHeader => ($this_day ne $last_day),
            DateFooter => $footer,
            SQLHeader => $row == 1,
            EntriesHeader => $row == 1,
            SQLFooter => !@next_row,
            EntriesFooter => !@next_row,
        });
        $last_day = $this_day;
        return $ctx->error( $builder->errstr ) unless defined $out;
        $res .= $out;
    }
    $sth->finish;

    # restore current blog in case we fiddled with it...
    $ctx->{__stash}{blog_id} = $blog_id;
    $ctx->{__stash}{blog} = $blog;
    if ($res) {
        return $res;
    } else {
        $ctx->stash('tokens', $tokens);
        return defined $args->{default} ? build_expr($ctx, $args->{default}, $cond) : '';
    }
}

sub _next_entry {
    my ($sth, $unfiltered, $blog_id, $class) = @_;

    my @row = $sth->fetchrow_array();
    return (undef, ()) unless @row;

    while (@row) {
        my $entry_id = $row[$sth->{NAME_hash}{entry_id}];
        return (undef, ()) unless $entry_id;

        my $entry = MT::Entry->load($entry_id);
        return (undef, ()) unless $entry;

        if ($entry->class eq $class) {
            if ($unfiltered || ($entry->status == MT::Entry::RELEASE() && 
            $entry->blog_id == $blog_id)) {
                return ($entry, @row);
            }
        }
        @row = $sth->fetchrow_array();
    }
    return (undef, ());
}

sub SQLComments {
    my($ctx, $args, $cond) = @_;
    my $dbh = _get_dbh($ctx, $args);
    return unless $dbh;

    local $ctx->{__stash}{SQLDbh} = $dbh;

    require MT::Comment;
    my $builder = $ctx->stash('builder');
    my $tokens = $ctx->stash('tokens');
    my $blog_id = $ctx->stash('blog_id');
    my $blog = $ctx->stash('blog');
    my $needs_entry = ($ctx->stash('uncompiled') =~ /<\$?MTEntry/) ? 1 : 0;
    my $query = build_expr($ctx, $args->{query}, $cond);
    return unless $query;

    my $sth = $dbh->prepare($query);
    return $ctx->error("Error in query: ".$dbh->errstr) if $dbh->errstr;

    $sth->execute();
    return $ctx->error("Error in query: ".$sth->errstr) if $sth->errstr;

    # sanity check-- 'comment_id' must be a valid column:
    if (!exists $sth->{NAME_hash}{comment_id}) {
        $sth->finish;
        return $ctx->error("You must specify 'comment_id' as one of the columns of your query.");
    }

    my $unfiltered = $args->{unfiltered};
    local $ctx->{__stash}{entry} = $ctx->{__stash}{entry} if $needs_entry;

    my $res = '';
    my %blogs;
    my $row = 0;
    my ($c, @row);
    my ($next_comment, @next_row) = _next_comment($sth, $unfiltered, $blog_id);
    local $ctx->{__stash}{SQLSth} = $sth;
    while (@next_row) {
        ($c, @row) = ($next_comment, @next_row);
        $row++;
        local $ctx->{__stash}{SQLRow} = \@row;
        ($next_comment, @next_row) = _next_comment($sth, $unfiltered, $blog_id);

        # if we're not unfiltered (filtering is ON)...
        if ($unfiltered) {
            if ($c->blog_id != $ctx->{__stash}{blog_id}) {
                my $new_blog_id = $c->blog_id;
                if (!exists $blogs{$new_blog_id}) {
                    $blogs{$new_blog_id} = MT::Blog->load($new_blog_id)
                        or return $ctx->error("Error loading blog, id = $new_blog_id");
                }
                $ctx->{__stash}{blog_id} = $new_blog_id;
                $ctx->{__stash}{blog} = $blogs{$new_blog_id};
            }
        }
        $ctx->{__stash}{entry} = MT::Entry->load($c->entry_id)
            if $needs_entry;
        $ctx->stash('comment' => $c);
        local $ctx->{current_timestamp} = $c->created_on;
        $ctx->stash('comment_order_num', $row);
        my $out = $builder->build($ctx, $tokens, {%$cond,
                                                  SQLHeader => $row == 1,
                                                  SQLFooter => !@next_row} );
        return $ctx->error( $builder->errstr ) unless defined $out;
        $res .= $out;
    }
    $sth->finish;

    $ctx->{__stash}{blog_id} = $blog_id;
    $ctx->{__stash}{blog} = $blog;
    if ($res) {
        return $res;
    } else {
        $ctx->stash('tokens', $tokens);
        return defined $args->{default} ? build_expr($ctx, $args->{default}, $cond) : '';
    }
}

sub _next_comment {
    my ($sth, $unfiltered, $blog_id) = @_;
    my @row = $sth->fetchrow_array();
    return (undef, ()) unless @row;
    if ($unfiltered) {
        my $comment = MT::Comment->load($row[$sth->{NAME_hash}{comment_id}]);
        return ($comment, @row);
    }
    while (@row) {
        my $comment_id = $row[$sth->{NAME_hash}{comment_id}];
        my $comment = MT::Comment->load($comment_id);
        return (undef, ()) unless $comment;
        if ($comment->blog_id == $blog_id) {
            return ($comment, @row);
        }
        @row = $sth->fetchrow_array();
    }
    return (undef, ());
}

sub SQLCategories {
    my ($ctx, $args, $cond) = @_;
    my $dbh = _get_dbh($ctx, $args);
    return unless $dbh;

    local $ctx->{__stash}{SQLDbh} = $dbh;

    require MT::Category;
    my $builder = $ctx->stash('builder');
    my $tokens = $ctx->stash('tokens');
    my $blog_id = $ctx->stash('blog_id');
    my $blog = $ctx->stash('blog');
    my $needs_entries = ($ctx->stash('uncompiled') =~ /<\$?MTEntries/) ? 1 : 0;
    my $query = build_expr($ctx, $args->{query}, $cond);
    return unless $query;

    require MT::Placement;

    my $sth = $dbh->prepare($query);
    return $ctx->error("Error in query: ".$dbh->errstr) if $dbh->errstr;

    $sth->execute();
    return $ctx->error("Error in query: ".$sth->errstr) if $sth->errstr;

    # sanity check-- 'category_id' must be a valid column:
    if (!exists $sth->{NAME_hash}{category_id}) {
        $sth->finish;
        return $ctx->error("You must specify 'category_id' as one of the columns of your query.");
    }

    my $unfiltered = $args->{unfiltered};

    my $class = $ctx->stash('tag') =~ m/folders/i ? 'folder' : 'category';

    my $res = '';
    my %blogs;
    my ($cat, @row);
    my ($next_cat, @next_row) = _next_category($sth, $unfiltered, $blog_id, $class);

    local $ctx->{inside_mt_categories} = 1;
    my $row = 0;
    local $ctx->{__stash}{SQLSth} = $sth;
    while (@next_row) {
        ($cat, @row) = ($next_cat, @next_row);
        $row++;
        local $ctx->{__stash}{SQLRow} = \@row;
        ($next_cat, @next_row) = _next_category($sth, $unfiltered, $blog_id, $class);

        # if we're not unfiltered (filtering is ON)...
        if ($unfiltered) {
            if ($cat->blog_id != $ctx->{__stash}{blog_id}) {
                my $new_blog_id = $cat->blog_id;
                if (!exists $blogs{$new_blog_id}) {
                    $blogs{$new_blog_id} = MT::Blog->load($new_blog_id)
                        or return $ctx->error("Error loading blog, id = $new_blog_id");
                }
                $ctx->{__stash}{blog_id} = $new_blog_id;
                $ctx->{__stash}{blog} = $blogs{$new_blog_id};
            }
        }

        local $ctx->{__stash}{category} = $cat;
        local $ctx->{__stash}{entries};
        local $ctx->{__stash}{category_count};
        if ($needs_entries) {
            my @entries = MT::Entry->load({ blog_id => $blog_id,
                                            status => MT::Entry::RELEASE() },
                            { 'join' => [ 'MT::Placement', 'entry_id',
                                        { category_id => $cat->id } ],
                              'sort' => 'created_on',
                              direction => 'descend', });
            $ctx->{__stash}{entries} = \@entries;
            $ctx->{__stash}{category_count} = scalar @entries;
        } else {
            $ctx->{__stash}{category_count} =
                MT::Placement->count({ category_id => $cat->id });
        }
        #next unless $ctx->{__stash}{category_count} || $args->{show_empty};
        defined(my $out = $builder->build($ctx, $tokens, {%$cond,
                                                          SQLHeader => $row == 1,
                                                          SQLFooter => !@next_row}))
            or return $ctx->error( $builder->errstr );
        $res .= $out;
    }
    $sth->finish;

    $ctx->{__stash}{blog_id} = $blog_id;
    $ctx->{__stash}{blog} = $blog;
    if ($res) {
        return $res;
    } else {
        $ctx->stash('tokens', $tokens);
        return defined $args->{default} ? build_expr($ctx, $args->{default}, $cond) : '';
    }
}

sub _next_category {
    my ($sth, $unfiltered, $blog_id, $class) = @_;

    my @row = $sth->fetchrow_array();
    return (undef, ()) unless @row;

    while (@row) {
        my $cat_id = $row[$sth->{NAME_hash}{category_id}];
        return (undef, ()) unless $cat_id;

        my $cat = MT::Category->load($cat_id);
        return (undef, ()) unless $cat;

        if ($cat->class eq $class) {
            if ($unfiltered || ($cat->blog_id == $blog_id)) {
                return ($cat, @row);
            }
        }
        @row = $sth->fetchrow_array();
    }
    return (undef, ());
}

sub SQLPings {
    my ($ctx, $args, $cond) = @_;
    my $dbh = _get_dbh($ctx, $args);
    return unless $dbh;

    local $ctx->{__stash}{SQLDbh} = $dbh;

    require MT::TBPing;
    my $builder = $ctx->stash('builder');
    my $tokens = $ctx->stash('tokens');
    my $blog_id = $ctx->stash('blog_id');
    my $blog = $ctx->stash('blog');
    my $query = build_expr($ctx, $args->{query}, $cond);
    return unless $query;

    my $sth = $dbh->prepare($query);
    return $ctx->error("Error in query: ".$dbh->errstr) if $dbh->errstr;

    $sth->execute();
    return $ctx->error("Error in query: ".$sth->errstr) if $sth->errstr;

    # sanity check-- 'tbping_id' must be a valid column:
    if (!exists $sth->{NAME_hash}{tbping_id}) {
        $sth->finish;
        return $ctx->error("You must specify 'tbping_id' as one of the columns of your query.");
    }

    my $unfiltered = $args->{unfiltered};

    my $res = '';
    my %blogs;
    my ($ping, @row);
    my ($next_ping, @next_row) = _next_ping($sth, $unfiltered, $blog_id);
    my $row = 0;
    local $ctx->{__stash}{SQLSth} = $sth;
    while (@next_row) {
        ($ping, @row) = ($next_ping, @next_row);
        $row++;
        local $ctx->{__stash}{SQLRow} = \@row;
        ($next_ping, @next_row) = _next_ping($sth, $unfiltered, $blog_id);

        # if we're not unfiltered (filtering is ON)...
        if ($unfiltered) {
            if ($ping->blog_id != $ctx->{__stash}{blog_id}) {
                my $new_blog_id = $ping->blog_id;
                if (!exists $blogs{$new_blog_id}) {
                    $blogs{$new_blog_id} = MT::Blog->load($new_blog_id)
                        or return $ctx->error("Error loading blog, id = $new_blog_id");
                }
                $ctx->{__stash}{blog_id} = $new_blog_id;
                $ctx->{__stash}{blog} = $blogs{$new_blog_id};
            }
        }
        local $ctx->{__stash}{ping} = $ping;
        local $ctx->{current_timestamp} = $ping->created_on;
        my $out = $builder->build($ctx, $tokens, {%$cond,
                                                  SQLHeader => $row == 1,
                                                  SQLFooter => !@next_row});
        return $ctx->error( $builder->errstr ) unless defined $out;
        $res .= $out;
    }
    $sth->finish;

    $ctx->{__stash}{blog_id} = $blog_id;
    $ctx->{__stash}{blog} = $blog;
    if ($res) {
        return $res;
    } else {
        $ctx->stash('tokens', $tokens);
        return defined $args->{default} ? build_expr($ctx, $args->{default}, $cond) : '';
    }
}

sub _next_ping {
    my ($sth, $unfiltered, $blog_id) = @_;
    my @row = $sth->fetchrow_array();
    return (undef, ()) unless @row;
    if ($unfiltered) {
        my $ping = MT::TBPing->load($row[$sth->{NAME_hash}{tbping_id}]);
        return ($ping, @row);
    }
    while (@row) {
        my $ping_id = $row[$sth->{NAME_hash}{tbping_id}];
        my $ping = MT::TBPing->load($ping_id);
        return (undef, ()) unless $ping;
        if ($ping->blog_id == $blog_id) {
            return ($ping, @row);
        }
        @row = $sth->fetchrow_array();
    }
    return (undef, ());
}

sub SQLAuthors {
    my ($ctx, $args, $cond) = @_;
    my $dbh = _get_dbh($ctx, $args);
    return unless $dbh;

    local $ctx->{__stash}{SQLDbh} = $dbh;

    require MT::Author;
    my $builder = $ctx->stash('builder');
    my $tokens = $ctx->stash('tokens');
    my $blog_id = $ctx->stash('blog_id');
    my $query = build_expr($ctx, $args->{query}, $cond);
    return unless $query;

    my $sth = $dbh->prepare($query);
    return $ctx->error("Error in query: ".$dbh->errstr) if $dbh->errstr;

    $sth->execute();
    return $ctx->error("Error in query: ".$sth->errstr) if $sth->errstr;

    # sanity check-- 'tbping_id' must be a valid column:
    if (!exists $sth->{NAME_hash}{author_id}) {
        $sth->finish;
        return $ctx->error("You must specify 'author_id' as one of the columns of your query.");
    }

    my $unfiltered = $args->{unfiltered};
    my $res = '';
    my ($author, @row);
    my ($next_author, @next_row) = _next_author($sth, $unfiltered, $blog_id);
    my $row = 0;
    local $ctx->{__stash}{SQLSth} = $sth;
    while (@next_row) {
        ($author, @row) = ($next_author, @next_row);
        $row++;
        local $ctx->{__stash}{SQLRow} = \@row;
        ($next_author, @next_row) = _next_author($sth, $unfiltered, $blog_id);

        local $ctx->{__stash}{author} = $author;
        my $out = $builder->build($ctx, $tokens, {%$cond,
                                                  SQLHeader => $row == 1,
                                                  SQLFooter => !@next_row});
        return $ctx->error($builder->errstr) unless defined $out;
        $res .= $out;
    }
    $sth->finish;

    if ($res) {
        return $res;
    } else {
        $ctx->stash('tokens', $tokens);
        return defined $args->{default} ? build_expr($ctx, $args->{default}, $cond) : '';
    }
}

sub _next_author {
    my ($sth, $unfiltered, $blog_id) = @_;
    my @row = $sth->fetchrow_array();
    return (undef, ()) unless @row;
    if ($unfiltered) {
        my $author = MT::Author->load($row[$sth->{NAME_hash}{author_id}]);
        return ($author, @row);
    }
    while (@row) {
        my $author_id = $row[$sth->{NAME_hash}{author_id}];
        my $author = MT::Author->load($author_id);
        next unless $author->type == 1;
        return (undef, ()) unless $author;
        require MT::Permission;
        my $perms = MT::Permission->load({ blog_id => $blog_id,
                                           author_id => $author_id });
        if ($perms) {
            return ($author, @row);
        }
        @row = $sth->fetchrow_array();
    }
    return (undef, ());
}

sub quote_sql {
    my ($str, $param, $ctx) = @_;
    my $dbh = _get_dbh($ctx) or return;
    return $dbh->quote($str);
}

sub _get_dbh {
    my ($ctx, $args) = @_;

    if (($args->{connection} || '') eq 'mt') {
        return MT::Object->driver->r_handle;
    }

    if ($args->{dsn}) {
        my $dbh = DBI->connect($args->{dsn}, $args->{user}, $args->{password},
            { RaiseError => 0 })
            or return $ctx->error("Failed to connect to $args->{dsn}");
        if ($args->{connection}) {
            $MT::Plugin::SQL::named_connections{$args->{connection}} = $dbh;
        }
        return $dbh;
    } elsif (my $name = $args->{connection}) {
        return connection_by_name($ctx, $name);
    } elsif ($ctx->{__stash}{SQLDbh}) {
        return $ctx->{__stash}{SQLDbh};
    }
    MT::Object->driver->r_handle;
}

sub build_expr {
    my ($ctx, $val, $cond) = @_;
    require MT::Util;
    $val = MT::Util::decode_html($val);
    if (($val =~ m/\<\$?MT.*?\>/) ||
        ($val =~ s/\[(\/?MT(.*?))\]/\<$1\>/gs)) {
        my $builder = $ctx->stash('builder');
        my $tok = $builder->compile($ctx, $val);
        return $ctx->error($builder->errstr) unless $tok;
        defined($val = $builder->build($ctx, $tok, $cond))
            or return $ctx->error($builder->errstr);
    }
    $val;
}

sub connection_by_name {
    my ($ctx, $name) = @_;
    my $conns = connections($ctx);
    if (my $conn = $conns->{$name}) {
        if (ref $conn eq 'HASH') {
            my $dbh = DBI->connect($conn->{dsn}, $conn->{username}, $conn->{password}, { RaiseError => 0 })
                or return $ctx->error("Error connecting to $name: " . DBI->errstr);
            $conns->{$name} = $dbh;
            $dbh->{private_close_me} = 1;
            return $dbh;
        }
        return $conn;
    }
    return undef;
}

sub connections {
    my ($ctx) = @_;
    require MT::Request;
    my $r = MT::Request->instance;
    my $conn = $r->stash('mt-sql-connections');
    unless ($conn) {
        $conn = \%$MT::Plugin::SQL::named_connections;
        # retrieve a list of named connections configured for the plugin
        my $plugin = MT::Plugin::SQL->instance;
        if (my $conn_sys = $plugin->get_config_value('connections')) {
            $conn->{$_} = $conn_sys->{$_} foreach keys %$conn_sys;
        }
        if (my $conn_blog = $plugin->get_config_value('connections',
            'blog:'. $ctx->stash('blog_id'))) {
            $conn->{$_} = $conn_blog->{$_} foreach keys %$conn_blog;
        }
        $r->stash('mt-sql-connections', $conn);
    }
    $conn;
}

1;
