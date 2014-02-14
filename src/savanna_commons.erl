%%======================================================================
%%
%% LeoProject - Savanna Commons
%%
%% Copyright (c) 2014 Rakuten, Inc.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%%======================================================================
-module(savanna_commons).
-author('Yosuke Hara').

-include("savanna_commons.hrl").
-include_lib("folsom/include/folsom.hrl").
-include_lib("eunit/include/eunit.hrl").

-export([new/4, new/5, new/6, new/7, new/8,
         stop/2,
         create_schema/2,
         create_metrics_by_schema/3,
         create_metrics_by_schema/4,
         notify/2, get_metric_value/2,
         get_histogram_statistics/2]).


%% ===================================================================
%% API
%% ===================================================================
%% @doc Create a new metrics or histgram
%%
new(?METRIC_COUNTER, MetricGroup, Key, Callback) ->
    Name = ?sv_metric_name(MetricGroup, Key),
    savanna_commons_sup:start_child('svc_metrics_counter', Name, Callback).

new(?METRIC_COUNTER, MetricGroup, Key, Window, Callback) ->
    Name = ?sv_metric_name(MetricGroup, Key),
    savanna_commons_sup:start_child('svc_metrics_counter', Name, Window, Callback);

new(?METRIC_HISTOGRAM, HistogramType, MetricGroup, Key, Callback) ->
    Name = ?sv_metric_name(MetricGroup, Key),
    savanna_commons_sup:start_child('svc_metrics_histogram', Name, HistogramType, Callback).

new(?METRIC_HISTOGRAM, HistogramType, MetricGroup, Key, Window, Callback) ->
    Name = ?sv_metric_name(MetricGroup, Key),
    savanna_commons_sup:start_child('svc_metrics_histogram', Name, HistogramType, Window, Callback).

new(?METRIC_HISTOGRAM, HistogramType, MetricGroup, Key, Window, SampleSize, Callback) ->
    Name = ?sv_metric_name(MetricGroup, Key),
    savanna_commons_sup:start_child('svc_metrics_histogram', Name, HistogramType, Window, SampleSize, Callback).

new(?METRIC_HISTOGRAM, HistogramType, MetricGroup, Key, Window, SampleSize, Alpha, Callback) ->
    Name = ?sv_metric_name(MetricGroup, Key),
    savanna_commons_sup:start_child('svc_metrics_histogram', Name, HistogramType, Window, SampleSize, Alpha, Callback).


%% @doc Stop a process
stop(MetricGroup, Key) ->
    Name = ?sv_metric_name(MetricGroup, Key),
    case check_type(Name) of
        ?METRIC_COUNTER ->
            svc_metrics_counter:stop(Name);
        ?METRIC_HISTOGRAM ->
            svc_metrics_histogram:stop(Name);
        _ ->
            ok
    end.


%% doc Create a new metrics or histgram from the schema
%%
-spec(create_schema(sv_schema(), [#sv_column{}]) ->
             ok | {error, any()}).
create_schema(SchemaName, Columns) ->
    CreatedAt = leo_date:now(),
    case svc_tbl_schema:update(#sv_schema{name = SchemaName,
                                          created_at = CreatedAt}) of
        ok ->
            create_schema_1(SchemaName, Columns, CreatedAt);
        Error ->
            Error
    end.

%% @private
create_schema_1(_,[],_) ->
    ok;
create_schema_1(SchemaName, [#sv_column{} = Col|Rest], CreatedAt) ->
    case svc_tbl_column:update(Col#sv_column{schema_name = SchemaName,
                                             created_at  = CreatedAt}) of
        ok ->
            create_schema_1(SchemaName, Rest, CreatedAt);
        Error ->
            Error
    end;
create_schema_1(_,_,_) ->
    {error, invalid_args}.


%% doc Create a new metrics or histgram by the schema
%%
-spec(create_metrics_by_schema(sv_schema(), pos_integer(), function()) ->
             ok | {error, any()}).
create_metrics_by_schema(SchemaName, Window, Callback) ->
    create_metrics_by_schema(SchemaName, SchemaName, Window, Callback).

-spec(create_metrics_by_schema(sv_schema(), sv_metric_grp(),
                               pos_integer(), function()) ->
             ok | {error, any()}).
create_metrics_by_schema(SchemaName, MetricGroupName, Window, Callback) ->
    case svc_tbl_schema:get(SchemaName) of
        {ok,_} ->
            case svc_tbl_column:find_by_schema_name(SchemaName) of
                {ok, Columns} ->
                    case svc_tbl_metric_group:update(
                           #sv_metric_group{schema_name = SchemaName,
                                            name = MetricGroupName,
                                            window = Window,
                                            callback = Callback}) of
                        ok ->
                            create_metrics_by_schema_1(
                              MetricGroupName, Columns, Window, Callback);
                        Error ->
                            Error
                    end;
                Error ->
                    Error
            end;
        Error ->
            Error
    end.

%% @private
create_metrics_by_schema_1(_,[],_,_) ->
    ok;
create_metrics_by_schema_1(MetricGroupName, [#sv_column{type = ?COL_TYPE_COUNTER,
                                                        name = Key}|Rest], Window, Callback) ->
    ok = new(?METRIC_COUNTER, MetricGroupName, Key, Window, Callback),
    create_metrics_by_schema_1(MetricGroupName, Rest, Window, Callback);

create_metrics_by_schema_1(MetricGroupName, [#sv_column{type = ?COL_TYPE_H_UNIFORM,
                                                        constraint  = Constraint,
                                                        name = Key}|Rest], Window, Callback) ->
    HType = ?HISTOGRAM_UNIFORM,
    ok = case leo_misc:get_value(?HISTOGRAM_CONS_SAMPLE, Constraint, []) of
             [] -> new(?METRIC_HISTOGRAM, HType, MetricGroupName, Key, Window, Callback);
             N  -> new(?METRIC_HISTOGRAM, HType, MetricGroupName, Key, Window, N, Callback)
         end,
    create_metrics_by_schema_1(MetricGroupName, Rest, Window, Callback);
create_metrics_by_schema_1(MetricGroupName, [#sv_column{type = ?COL_TYPE_H_SLIDE,
                                                        name = Key}|Rest], Window, Callback) ->
    ok = new(?METRIC_HISTOGRAM, ?HISTOGRAM_SLIDE, MetricGroupName, Key, Window, Callback),
    create_metrics_by_schema_1(MetricGroupName, Rest, Window, Callback);
create_metrics_by_schema_1(MetricGroupName, [#sv_column{type = ?COL_TYPE_H_EXDEC,
                                                        constraint  = Constraint,
                                                        name = Key}|Rest], Window, Callback) ->
    HType = ?HISTOGRAM_EXDEC,
    ok = case leo_misc:get_value(?HISTOGRAM_CONS_SAMPLE, Constraint, []) of
             [] -> new(?METRIC_HISTOGRAM, HType, MetricGroupName, Key, Window, Callback);
             N1 ->
                 case leo_misc:get_value(?HISTOGRAM_CONS_ALPHA, Constraint, []) of
                     [] -> new(?METRIC_HISTOGRAM, HType, MetricGroupName, Key, Window, N1, Callback);
                     N2 -> new(?METRIC_HISTOGRAM, HType, MetricGroupName, Key, Window, N1, N2, Callback)
                 end
         end,
    create_metrics_by_schema_1(MetricGroupName, Rest, Window, Callback);
create_metrics_by_schema_1(_,_,_,_) ->
    {error, invalid_args}.


%% @doc Notify an event with a schema and a key
%%
-spec(notify(sv_metric_grp(), sv_keyval()) ->
             ok | {error, any()}).
notify(MetricGroup, {Key, Event}) ->
    Name = ?sv_metric_name(MetricGroup, Key),
    notify(check_type(Name), Name, Event).

%% @private
notify(?METRIC_COUNTER, Name, Event) ->
    folsom_metrics:notify({Name, {inc, Event}});
notify(?METRIC_HISTOGRAM, Name, Event) ->
    svc_metrics_histogram:update(Name, Event);
notify(_,_,_) ->
    {error, invalid_args}.


%% @doc Retrieve a metric value
%%
-spec(get_metric_value(sv_metric_grp(), atom()) ->
             {ok, any()} | {error, any()}).
get_metric_value(MetricGroup, Key) ->
    Name = ?sv_metric_name(MetricGroup, Key),
    get_metric_value_1(check_type(Name), Name).

%% @private
get_metric_value_1(?METRIC_COUNTER, Name) ->
    svc_metrics_counter:get_values(Name);
get_metric_value_1(?METRIC_HISTOGRAM, Name) ->
    svc_metrics_histogram:get_values(Name);
get_metric_value_1(_,_) ->
    {error, invalid_args}.


%% @doc Retrieve a historgram statistics
%%
get_histogram_statistics(MetricGroup, Key) ->
    Name = ?sv_metric_name(MetricGroup, Key),
    case check_type(Name) of
        ?METRIC_HISTOGRAM ->
            svc_metrics_histogram:get_histogram_statistics(Name);
        _ ->
            not_found
    end.


%% ===================================================================
%% Inner Functions
%% ===================================================================
%% @private
check_type(Name) ->
    case check_type([?METRIC_COUNTER, ?METRIC_HISTOGRAM], Name) of
        not_found ->
            check_type_1(Name, undefined);
        Type ->
            case whereis(Name) of
                undefined ->
                    check_type_1(Name, Type);
                _Pid ->
                    Type
            end
    end.

check_type([],_Name) ->
    not_found;
check_type([?METRIC_COUNTER = Type|Rest], Name) ->
    case ets:lookup(?COUNTER_TABLE, {Name, 0}) of
        [{{Name, 0},0}|_] ->
            Type;
        _ ->
            check_type(Rest, Name)
    end;
check_type([?METRIC_HISTOGRAM = Type|Rest], Name) ->
    case ets:lookup(?HISTOGRAM_TABLE, Name) of
        [{Name,{histogram,_,_}}|_] ->
            Type;
        _Other ->
            check_type(Rest, Name)
    end.

%% @private
check_type_1(Name, Type) ->
    %% If retrieved a metric-group-info,
    %% then it will generate metrics
    {MetricGroup, Column} = ?sv_schema_and_key(Name),
    case svc_tbl_metric_group:get(MetricGroup) of
        {ok, #sv_metric_group{schema_name = Schema,
                              name = MetricGroup,
                              window = Window,
                              callback = Callback}} ->
            case create_metrics_by_schema(
                   Schema, MetricGroup, Window, Callback) of
                ok when Type =/= undefind ->
                    Type;
                ok ->
                    case svc_tbl_column:get(Schema, Column) of
                        {ok, #sv_column{type = Type}} ->
                            Type;
                        Error ->
                            Error
                    end;
                Error ->
                    Error
            end;
        _ ->
            not_found
    end.