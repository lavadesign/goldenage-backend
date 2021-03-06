-module(ga_util).

-export([image/3, trans/2, rsc_json/3, rsc_json/4]).


trans(undefined, _) ->
    null;
trans({struct, _}=V, _) ->
    V;
trans({array, _}=V, _) ->
    V;
trans({{_,_,_}, {_,_,_}}=TS, _) ->
    z_dateformat:format(TS, "c", []);
trans(T, Context) ->
    case z_utils:is_empty(T) of
        true -> null;
        false ->
            case z_trans:trans(T, Context) of
                B when is_binary(B) ->
                    z_html:unescape(B);
                T2 -> T2
            end
    end.

image(Id, Opts, Context) ->
    case z_media_tag:url(Id, [{use_absolute_url, true} | Opts], Context) of
        {ok, Url} -> Url;
        _ -> null
    end.

rsc_json(Id, Fields, Context) ->
    rsc_json(Id, Fields, [{width, 600}], Context).

rsc_json(Id, Fields, ImgOpts, Context) ->
    {struct,
     [
      {id, Id},
      {category, proplists:get_value(name, m_rsc:p(Id, category, Context))}
      |
      lists:filter(fun(undefined) -> false; (_) -> true end, [map_rsc_json_field(Id, K, ImgOpts, Context)|| K <- Fields])
    ]}.
      
%% images
map_rsc_json_field(Id, image, ImgOpts, Context) ->
    {image, image(Id, ImgOpts, Context)};

%% thumbnail
map_rsc_json_field(Id, thumbnail, ImgOpts, Context) ->
    case m_edge:objects(Id, thumbnail, Context) of
        [T | _] ->
            {thumbnail, image(T, ImgOpts, Context)};
        _ ->
            undefined
    end;

%% images
map_rsc_json_field(Id, images, ImgOpts, Context) ->
    Objects = m_edge:objects(Id, depiction, Context),
    case length(Objects) of
        N when N > 1 ->
            {images, {array, [image(ImgId, ImgOpts, Context) || ImgId <- Objects]}};
        _ ->
            undefined
    end;

%% hashtags
map_rsc_json_field(Id, hashtags, _ImgOpts, Context) ->
    Objects = m_edge:objects(Id, has_hashtag, Context),
    case length(Objects) of
        N when N > 0 ->
            {hashtags, {array, [rsc_json(O, [id, title], Context) || O <- Objects]}};
        _ ->
            undefined
    end;

%% dates
map_rsc_json_field(Id, DF, _, Context) when DF =:= publication_start; DF =:= publication_end;
                                            DF =:= date_start; DF =:= date_end ->
    {DF, z_datetime:format(m_rsc:p(Id, DF, Context), "c", Context)};

%% linked person; get first one
map_rsc_json_field(Id, {edge, Pred}, _ImgOpts, Context) ->
    map_rsc_json_field(Id, {edge, Pred, Pred}, _ImgOpts, Context);
map_rsc_json_field(Id, {edge, Pred, K}, _ImgOpts, Context) ->
    case m_edge:objects(Id, Pred, Context) of
        [] -> {K, null};
        [P|_] ->
            {K, P}
    end;
map_rsc_json_field(Id, {edges, Pred}, _ImgOpts, Context) ->
    {Pred, {array, m_edge:objects(Id, Pred, Context)}};

map_rsc_json_field(Id, photouploads, ImgOpts, Context) ->
    {photouploads, photo_uploads(Id, ImgOpts, Context)};

map_rsc_json_field(Id, {subject_edges, Pred, Name}, ImgOpts, Context) ->
    {Name, {array, [
                    ga_util:rsc_json(M, [title, subtitle, image], ImgOpts, Context)
                    || M <- m_edge:subjects(Id, Pred, Context)]
           }};

map_rsc_json_field(Id, K, _, Context) ->
    case trans(m_rsc:p(Id, K, Context), Context) of
        null -> undefined;
        V -> {K, V}
    end.

photo_uploads(Id, ImgOpts, Context) ->
    O = m_edge:objects(Id, photoupload, Context),

    ObjectsWithStory = lists:sort([{m_edge:object(ImgId, has_story, 1, Context), ImgId} || ImgId <- O]),
    ImgObjects = [
                  begin
                      {struct, Props} = rsc_json(C, [image, created, {edge, has_card, card_id}], [{width, 500}], Context),
                      [{story_id, I} | Props]
                  end || {I, C} <- ObjectsWithStory],

    AA = z_utils:group_proplists(story_id, ImgObjects),
    SortFun = fun(A, B) -> proplists:get_value(created, A) < proplists:get_value(created, B) end,
    {struct, 
     [{K, {array, [{struct, proplists:delete(story_id, P)} || P <- lists:sort(SortFun, V)]}} || {K, V} <- AA]}.
