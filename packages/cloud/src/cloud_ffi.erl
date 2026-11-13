-module(cloud_ffi).
-export([set_https_proxy/2, read_stdin/0, parse_feed/1]).

-include_lib("xmerl/include/xmerl.hrl").

%% Route outbound https requests made with httpc through a proxy.
set_https_proxy(Host, Port) ->
    {ok, _} = application:ensure_all_started(inets),
    httpc:set_options([{https_proxy, {{binary_to_list(Host), Port}, ["localhost", "127.0.0.1"]}}]),
    nil.

%% Read all of standard input as a binary.
read_stdin() ->
    read_stdin([]).

read_stdin(Acc) ->
    case io:get_chars(standard_io, "", 1024) of
        eof -> unicode:characters_to_binary(lists:reverse(Acc));
        {error, _} -> unicode:characters_to_binary(lists:reverse(Acc));
        Chunk -> read_stdin([Chunk | Acc])
    end.

%% Parse an RSS or Atom feed into {Id, Title, Link, Summary, Published} items.
parse_feed(Body) ->
    try
        %% xmerl decodes bytes with the encoding the document declares, UTF-8 by default.
        {Doc, _} = xmerl_scan:string(binary_to_list(strip_bom(Body)), [{quiet, true}]),
        Items = xmerl_xpath:string("//*[local-name()='item' or local-name()='entry']", Doc),
        {ok, [feed_item(Item) || Item <- Items]}
    catch
        _:Reason -> {error, unicode:characters_to_binary(io_lib:format("~p", [Reason]))}
    end.

strip_bom(<<16#EF, 16#BB, 16#BF, Rest/binary>>) -> Rest;
strip_bom(Body) -> Body.

feed_item(Item) ->
    Title = child_text(Item, ["title"]),
    Link = case child_text(Item, ["link"]) of
        <<>> -> link_href(Item);
        Text -> Text
    end,
    Id = first_nonempty([child_text(Item, ["guid", "id"]), Link, Title]),
    Summary = child_text(Item, ["description", "summary", "content"]),
    Published = child_text(Item, ["pubDate", "published", "updated", "date"]),
    {Id, Title, Link, Summary, Published}.

child_text(Item, Names) ->
    first_nonempty([text_of(xmerl_xpath:string("./*[local-name()='" ++ Name ++ "']", Item)) || Name <- Names]).

text_of([Element | _]) ->
    case xmerl_xpath:string("string(.)", Element) of
        #xmlObj{value = Value} -> string:trim(unicode:characters_to_binary(Value));
        _ -> <<>>
    end;
text_of([]) -> <<>>.

link_href(Item) ->
    Links = xmerl_xpath:string("./*[local-name()='link']", Item),
    Hrefs = [Value || #xmlElement{attributes = Attributes} <- Links,
                      #xmlAttribute{name = href, value = Value} <- Attributes],
    case Hrefs of
        [Href | _] -> unicode:characters_to_binary(Href);
        [] -> <<>>
    end.

first_nonempty([<<>> | Rest]) -> first_nonempty(Rest);
first_nonempty([Value | _]) -> Value;
first_nonempty([]) -> <<>>.

