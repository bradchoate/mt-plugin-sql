NAME
    SQL - A plugin for Movable Type.

DESCRIPTION
    This plugin gives you the ability to select your MT data using SQL
    queries. For some, this can be incredibly flexible and powerful. If
    you're unfamiliar with SQL, you may want to review the RECIPIES section
    for examples that may be helpful in understanding how this plugin works.

CONFIGURATION
    This plugin has a configuration screen in Movable Type. The system-wide
    and blog-level configuration screens allows you to set up a list of
    named connections. This connection list is used in conjunction with the
    <MTSQL> tag to do abitrary SQL queries against any database your server
    can access.

    The system-wide configuration screen also has a permission-based setting
    that lets you restrict who can use the SQL tags. By default, anyone with
    template-edit permissions can use the tags, but if you so choose, you
    may restrict access to system-administrators only. This may be prudent,
    since the <MTSQL> tag does not protect against updating or inserting
    records into the database, nor does it limit access to particular
    tables.

GLOBAL ATTRIBUTES
  quote_dbh
    This attribute allows you to escape special characters you may embed
    within your queries when populating the query with values from a MT tag.
    For instance:

        <MTSQL query="select * from mt_author
               where author_nickname='[MTEntryAuthor quote_sql='1']'">

    In the event that <MTEntryAuthor> contains quotes or other special
    characters, quote_dbh will escape these characters so the query is
    formed properly.

TAGS
    This plugin provides a number of container tags used for doing SQL-based
    queries to gather MT object data.

  <MTSQL>
    This is a general-purpose tag used to issue a query to your database.
    Being a container tag, it will produce output for each row returned from
    the query. To output the value of a column from the query, use the
    <MTSQLColumn> tag.

    Example:

        <MTSQL query="select now()"><MTSQLColumn column="1"></MTSQL>

    The following attributes apply to this tag:

    * query
        The SQL query to execute. This is typically a SELECT query, but it
        can be any SQL statement that is valid for your database.

            <MTSQL query="select count(*) from mt_entry where entry_status=2">
            # of entries for this MT installation: <MTSQLColumn column="1">
            </MTSQL>

    * default
        In the event that now rows are returned by the query, you can
        specify a value using the default attribute which is outut instead.

            <MTSQL query="select 1 from mt_entry where entry_status=1"
                   default="No draft entries">Draft entries exist.</MTSQL>

    * connection
        A named connection to use to issue the query against. See
        CONFIGURATION for more information about named connections.

            <MTSQL connection="other_db"
                   query="select count(*) from pending_tickets">
            <MTSQLColumn column="1">
            </MTSQL>

  <MTSQLHeader>
    A conditional tag that whose content is output if the first row of SQL
    container tag is being processed.

  <MTSQLFooter>
    A conditional tag that whose content is output if the last row of SQL
    container tag is being processed.

  <$MTSQLColumn$>
    Outputs a single column's data from the current row of an active query
    result.

    * column
        A number to reference a column by number (first column is '1'). A
        name if you want to refer to columns by name.

            <$MTSQLColumn column="1"$>

            <$MTSQLColumn column="entry_title"$>

    * format
        Allows you to specify a 'sprintf' type specifier to format the
        content of this column.

            <$MTSQLColumn column="count" format="%06d"$>

    * default
        In the event that there is no value for the specified column, the
        default attribute lets you specify a value to output instead.

            <$MTSQLColumn column="entry_excerpt" default="Excerpt is null"$>

  <MTSQLBlogs>
    Lets you use a SQL query to fetch a selection of blogs. One of the
    columns returned in this query should be named 'blog_id'. It will be
    used to load the MT::Blog object.

    Here's an example that generates a list of all blogs installed along
    with the count of their entries (sorted by count, with the ones having
    the most entries first):

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

    * query
        The text of the query to issue to select blog IDs. This query must
        include a column in the result named 'blog_id'.

    * default
        The value you want to output in the event that no blogs were
        selected.

  <MTSQLEntries>
    Lets you use a SQL query to fetch a selection of entries. One of the
    columns returned in this query should be named 'entry_id'. It will be
    used to load the MT::Entry object.

    *Note: When selecting entries, you probably will want to filter for
    entries whose 'entry_status' column has a value of 2. This is the
    setting for a published entry. By not selecting for 'entry_status=2',
    you will include draft or scheduled entries in addition to published
    entries.*

    * query
        The text of the query to issue to select entry IDs. This query must
        include a column in the result named 'entry_id'.

    * unfiltered
        By default, this tag will only select entries that are appropriate
        for the current weblog. If you wish it to select entries across
        weblogs, use the 'unfiltered' attribute.

            <MTSQLEntries query="select entry_id from mt_entry order by entry_author_id" unfiltered="1">

    * default
        The value you want to output in the event that no entries were
        selected.

    Filters out non-entry records from the mt_entry table (where blog
    entries and pages are stored). NOTE: If you are trying to query with
    a 'LIMIT' clause, you should add the "entry_class='entry'" clause to
    your query so you will limit your result set properly.

  <MTSQLPages>
    Similar to the SQLEntries tag; this is mostly an alias, but filters
    out non-page records from the mt_entry table. NOTE: If you are trying
    to query with a 'LIMIT' clause, you should add the "entry_class='page'"
    clause to your query so you will limit your result set properly.

  <MTSQLComments>
    Lets you use a SQL query to fetch a selection of comments. One of the
    columns returned in this query should be named 'comment_id'. It will be
    used to load the MT::Comment object.

    *Note: When selecting comments, you probably will want to filter for
    comments whose 'comment_visible' column has a value of 1. This is the
    state of published comments. Without this filter, your query will
    include pending or junked comments.*

    * query
        The text of the query to issue to select comment IDs. This query
        must include a column in the result named 'comment_id'.

    * unfiltered
        By default, this tag will only select comments that are appropriate
        for the current weblog. If you wish it to select comments across
        weblogs, use the 'unfiltered' attribute.

    * default
        The value you want to output in the event that no comments were
        selected.

  <MTSQLCategories>
    Lets you use a SQL query to fetch a selection of categories. One of the
    columns returned in this query should be named 'category_id'. It will be
    used to load the MT::Category object.

    * query
        The text of the query to issue to select category IDs. This query
        must include a column in the result named 'category_id'.

    * unfiltered
        By default, this tag will only select categories that are
        appropriate for the current weblog. If you wish it to select
        categories across weblogs, use the 'unfiltered' attribute.

    * default
        The value you want to output in the event that no categories were
        selected.

  <MTSQLPings>
    Lets you use a SQL query to fetch a selection of TrackBack pings. One of
    the columns returned in this query should be named 'tbping_id'. It will
    be used to load the MT::TBPing object.

    *Note: When selecting comments, you probably will want to filter for
    comments whose 'comment_visible' column has a value of 1. This is the
    state of published comments. Without this filter, your query will
    include pending or junked comments.*

    * query
        The text of the query to issue to select TrackBack ping IDs. This
        query must include a column in the result named 'tbping_id'.

    * unfiltered
        By default, this tag will only select TrackBacks that are
        appropriate for the current weblog. If you wish it to select
        TrackBacks across weblogs, use the 'unfiltered' attribute.

    * default
        The value you want to output in the event that no TrackBacks were
        selected.

  <MTSQLAuthors>
    Lets you use a SQL query to fetch a selection of authors. One of the
    columns returned in this query should be named 'author_id'. It will be
    used to load the MT::Author object.

    This tag is more useful with the MT-Authors plugin.

    *Note: When selecting for authors with the 'unfiltered' attribute, you
    will probably want to filter for authors whose 'author_type' column has
    a value of 1. This is the value used for identifying actual author
    records as opposed to authenticated commenters (who are also stored in
    this table). Authenticated commenters have a 'author_type' value of 2.
    Filtered author selections automatically require a type of 1 be
    present.*

    * query
        The text of the query to issue to select author IDs. This query must
        include a column in the result named 'author_id'.

    * unfiltered
        By default, this tag will only select authors that have access to
        the current weblog. If you wish it to select authors across weblogs,
        use the 'unfiltered' attribute.

    * default
        The value you want to output in the event that no authors were
        selected.

RECIPIES
    The following examples demonstrate the power and flexibility of the SQL
    plugin. The examples below are written for MySQL, but could be altered
    to work with most any database.

  Most Active Entries
    This query selects the top 5 published entries (across all blogs) that
    have the most published comments and TrackBacks. The actual count can be
    retrieved using "<MTSQLColumn column="2">".

        select entry_id, count(distinct comment_id) + count(distinct tbping_id)
          from mt_entry, mt_comment, mt_tbping, mt_trackback
         where entry_id = comment_entry_id
           and entry_id = trackback_entry_id
           and tbping_tb_id = trackback_id
           and entry_status = 2
           and entry_class = 'entry'
           and comment_visible = 1
           and tbping_visible = 1
         group by entry_id
         order by 2 desc
         limit 5

  Top Authors
    Here's a query to select the top 5 authors on your install (again,
    across all weblogs).

        select author_id, author_name, count(*)
          from mt_author, mt_entry
         where entry_author_id = author_id
           and entry_status = 2
         group by author_id, author_name
         order by 3 desc
         limit 5

    If you don't the *MT-Authors* plugin, then you can run this using the
    <MTSQL> tag and select the author name using "<MTSQLColumn
    column="author_name">" and the count using "<MTSQLColumn column="3">".

  Posts by Year
    Perhaps you want to display a grid of years your blog has been around
    and the number of entries published for each?

        select year(entry_created_on) y, count(*) c
           from mt_entry
          where entry_status = 2
            and entry_class = 'entry'
            and entry_blog_id = 4
          group by year(entry_created_on)
          order by year(entry_created_on)

    Output these results using "<MTSQLColumn column="y">" and "<MTSQLColumn
    column="c">".

AVAILABILITY
    The latest release of this plugin can be found at this address:

        http://code.sixapart.com/svn/mtplugins/trunk/SQL

LICENSE
    This plugin is published under the Artistic License.

AUTHOR & COPYRIGHT
    Copyright 2002-2007, Brad Choate

