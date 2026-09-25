%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2020, 2600Hz
%%% @doc Temporal Rules API validation of `time_window_start' and
%%% `time_window_stop', driven through `cb_temporal_rules:validate/1,2' with
%%% the real `temporal_rules' schema and the fixture DB so the results mirror
%%% what a PUT, POST or PATCH request returns.
%%%
%%% Omitted window fields default to `0' (start) and `86400' (stop), matching
%%% `RULE_DEFAULT_WTIME_START' and `RULE_DEFAULT_WTIME_STOP' in callflow.
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_temporal_rules_api_qa_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("kazoo_fixturedb/include/kz_fixturedb.hrl").

-define(PUT, <<"PUT">>).
-define(POST, <<"POST">>).
-define(PATCH, <<"PATCH">>).

-define(START, <<"time_window_start">>).
-define(STOP, <<"time_window_stop">>).

%% Stored rule with a 09:00-17:00 window.
-define(SAME_DAY_RULE_ID, <<"qatemporalrule00000000000000day1">>).
%% Stored rule saved before time windows were validated: no window fields.
-define(LEGACY_RULE_ID, <<"qatemporalrule000000000000legacy">>).

-define(REJECTED, {'error', 400, 'true'}).
-define(ACCEPTED, {'success', 'undefined', <<"{}">>}).

%%%=============================================================================
%%% Fixtures
%%%=============================================================================

temporal_rules_api_test_() ->
    {'setup'
    ,fun setup/0
    ,fun cleanup/1
    ,fun(_) ->
             put_rejects_equal_window()
                 ++ post_rejects_equal_window()
                 ++ patch_rejects_equal_window()
                 ++ overnight_windows_accepted()
                 ++ put_accepts_legacy_payloads()
                 ++ put_applies_default_window()
                 ++ post_and_patch_accept_legacy()
     end
    }.

setup() ->
    Pid = kz_fixturedb_util:start_me('true'),
    meck:new('kz_fixturedb_doc', ['unstick', 'passthrough']),
    meck:expect('kz_fixturedb_doc', 'open_doc', fun open_doc/4),
    Pid.

cleanup(Pid) ->
    meck:unload(),
    kz_fixturedb_util:stop_me(Pid).

open_doc(Server, DbName, DocId, Options) ->
    case stored_rule(DocId) of
        'undefined' -> meck:passthrough([Server, DbName, DocId, Options]);
        JObj -> {'ok', JObj}
    end.

stored_rule(?SAME_DAY_RULE_ID) ->
    rule_doc(?SAME_DAY_RULE_ID, [{?START, 32400}, {?STOP, 61200}]);
stored_rule(?LEGACY_RULE_ID) ->
    rule_doc(?LEGACY_RULE_ID, []);
stored_rule(_) -> 'undefined'.

rule_doc(Id, Window) ->
    kz_json:from_list([{<<"_id">>, Id}
                      ,{<<"_rev">>, <<"1-2b7fe8d5bdc1a2d4e2bb0d0a1b5c1f3e">>}
                      ,{<<"pvt_type">>, <<"temporal_rule">>}
                      ,{<<"pvt_account_id">>, ?FIXTURE_MASTER_ACCOUNT_ID}
                      ,{<<"pvt_account_db">>, ?FIXTURE_MASTER_ACCOUNT_DB}
                       | weekly_rule(Window)
                      ]).

%%%=============================================================================
%%% AC6: start == stop is rejected with 400 on time_window_stop
%%%=============================================================================

put_rejects_equal_window() ->
    [{"PUT with time_window_start == time_window_stop == " ++ integer_to_list(T) ++ " is rejected with 400 on time_window_stop"
     ,?_assertEqual(?REJECTED, rejection(put(weekly_rule([{?START, T}, {?STOP, T}]))))
     }
     || T <- [0, 28800, 43200, 86400]
    ].

post_rejects_equal_window() ->
    [{"POST with time_window_start == time_window_stop == " ++ integer_to_list(T) ++ " is rejected with 400 on time_window_stop"
     ,?_assertEqual(?REJECTED, rejection(post(?SAME_DAY_RULE_ID, weekly_rule([{?START, T}, {?STOP, T}]))))
     }
     || T <- [0, 28800, 86400]
    ]
        ++ [{"POST to a legacy rule adding an equal window is rejected with 400 on time_window_stop"
            ,?_assertEqual(?REJECTED, rejection(post(?LEGACY_RULE_ID, weekly_rule([{?START, 3600}, {?STOP, 3600}]))))
            }
           ].

patch_rejects_equal_window() ->
    [{"PATCH setting both fields equal (28800/28800) is rejected with 400 on time_window_stop"
     ,?_assertEqual(?REJECTED, rejection(patch(?SAME_DAY_RULE_ID, [{?START, 28800}, {?STOP, 28800}])))
     }
    ,{"PATCH setting both fields to 0 is rejected with 400 on time_window_stop"
     ,?_assertEqual(?REJECTED, rejection(patch(?SAME_DAY_RULE_ID, [{?START, 0}, {?STOP, 0}])))
     }
    ,{"PATCH setting time_window_start equal to the stored time_window_stop is rejected with 400 on time_window_stop"
     ,?_assertEqual(?REJECTED, rejection(patch(?SAME_DAY_RULE_ID, [{?START, 61200}])))
     }
    ,{"PATCH setting time_window_stop equal to the stored time_window_start is rejected with 400 on time_window_stop"
     ,?_assertEqual(?REJECTED, rejection(patch(?SAME_DAY_RULE_ID, [{?STOP, 32400}])))
     }
    ,{"PATCH adding time_window_start = 86400 to a legacy rule (stop defaults to 86400) is rejected with 400 on time_window_stop"
     ,?_assertEqual(?REJECTED, rejection(patch(?LEGACY_RULE_ID, [{?START, 86400}])))
     }
    ].

%%%=============================================================================
%%% Overnight windows (start > stop) are accepted on every verb
%%%=============================================================================

overnight_windows_accepted() ->
    [{"PUT overnight window 64800..28800 is accepted"
     ,?_assertEqual(?ACCEPTED, outcome(put(weekly_rule([{?START, 64800}, {?STOP, 28800}]))))
     }
    ,{"PUT overnight window 86400..0 is accepted"
     ,?_assertEqual(?ACCEPTED, outcome(put(weekly_rule([{?START, 86400}, {?STOP, 0}]))))
     }
    ,{"POST overnight window 64800..28800 is accepted"
     ,?_assertEqual(?ACCEPTED, outcome(post(?SAME_DAY_RULE_ID, weekly_rule([{?START, 64800}, {?STOP, 28800}]))))
     }
    ,{"PATCH overnight window 79200..21600 is accepted"
     ,?_assertEqual(?ACCEPTED, outcome(patch(?SAME_DAY_RULE_ID, [{?START, 79200}, {?STOP, 21600}])))
     }
    ,{"PATCH moving only time_window_start past the stored stop (64800..61200) is accepted"
     ,?_assertEqual(?ACCEPTED, outcome(patch(?SAME_DAY_RULE_ID, [{?START, 64800}])))
     }
    ,{"PATCH moving only time_window_stop before the stored start (32400..28800) is accepted"
     ,?_assertEqual(?ACCEPTED, outcome(patch(?SAME_DAY_RULE_ID, [{?STOP, 28800}])))
     }
    ].

%%%=============================================================================
%%% AC7: payloads valid before the change are still accepted
%%%=============================================================================

put_accepts_legacy_payloads() ->
    [{"PUT omitting both time_window_start and time_window_stop (whole day) is accepted"
     ,?_assertEqual(?ACCEPTED, outcome(put(weekly_rule([]))))
     }
    ,{"PUT with only time_window_start = 0 (stop defaults to 86400) is accepted"
     ,?_assertEqual(?ACCEPTED, outcome(put(weekly_rule([{?START, 0}]))))
     }
    ,{"PUT with only time_window_start = 3600 is accepted"
     ,?_assertEqual(?ACCEPTED, outcome(put(weekly_rule([{?START, 3600}]))))
     }
    ,{"PUT with only time_window_stop = 86400 (start defaults to 0) is accepted"
     ,?_assertEqual(?ACCEPTED, outcome(put(weekly_rule([{?STOP, 86400}]))))
     }
    ,{"PUT with only time_window_stop = 3600 is accepted"
     ,?_assertEqual(?ACCEPTED, outcome(put(weekly_rule([{?STOP, 3600}]))))
     }
    ,{"PUT with explicit whole-day window 0..86400 is accepted"
     ,?_assertEqual(?ACCEPTED, outcome(put(weekly_rule([{?START, 0}, {?STOP, 86400}]))))
     }
    ,{"PUT with same-day window 32400..61200 is accepted"
     ,?_assertEqual(?ACCEPTED, outcome(put(weekly_rule([{?START, 32400}, {?STOP, 61200}]))))
     }
    ,{"PUT of the documented Christmas yearly rule (0..86400) is accepted"
     ,?_assertEqual(?ACCEPTED, outcome(put(christmas_rule())))
     }
    ,{"PUT of a yearly holiday rule with no time window is accepted"
     ,?_assertEqual(?ACCEPTED, outcome(put(holiday_rule())))
     }
    ,{"PUT of a date rule with no time window is accepted"
     ,?_assertEqual(?ACCEPTED, outcome(put(date_rule())))
     }
    ].

put_applies_default_window() ->
    [{"PUT with only time_window_stop = 0 (start defaults to 0, zero-length) is rejected with 400 on time_window_stop"
     ,?_assertEqual(?REJECTED, rejection(put(weekly_rule([{?STOP, 0}]))))
     }
    ,{"PUT with only time_window_start = 86400 (stop defaults to 86400, zero-length) is rejected with 400 on time_window_stop"
     ,?_assertEqual(?REJECTED, rejection(put(weekly_rule([{?START, 86400}]))))
     }
    ].

post_and_patch_accept_legacy() ->
    [{"POST to a legacy rule omitting both window fields is accepted"
     ,?_assertEqual(?ACCEPTED, outcome(post(?LEGACY_RULE_ID, weekly_rule([]))))
     }
    ,{"POST replacing a windowed rule with only time_window_start = 0 is accepted"
     ,?_assertEqual(?ACCEPTED, outcome(post(?SAME_DAY_RULE_ID, weekly_rule([{?START, 0}]))))
     }
    ,{"POST replacing a windowed rule with only time_window_start = 61200 (stop defaults to 86400) is accepted"
     ,?_assertEqual(?ACCEPTED, outcome(post(?SAME_DAY_RULE_ID, weekly_rule([{?START, 61200}]))))
     }
    ,{"PATCH renaming a legacy rule without a time window is accepted"
     ,?_assertEqual(?ACCEPTED, outcome(patch(?LEGACY_RULE_ID, [{<<"name">>, <<"Renamed">>}])))
     }
    ,{"PATCH adding only time_window_start = 0 to a legacy rule is accepted"
     ,?_assertEqual(?ACCEPTED, outcome(patch(?LEGACY_RULE_ID, [{?START, 0}])))
     }
    ,{"PATCH renaming a same-day windowed rule is accepted"
     ,?_assertEqual(?ACCEPTED, outcome(patch(?SAME_DAY_RULE_ID, [{<<"name">>, <<"Renamed">>}])))
     }
    ].

%%%=============================================================================
%%% Helpers
%%%=============================================================================

put(Props) ->
    cb_temporal_rules:validate(context(?PUT, Props)).

post(Id, Props) ->
    cb_temporal_rules:validate(context(?POST, Props), Id).

patch(Id, Props) ->
    cb_temporal_rules:validate(context(?PATCH, Props), Id).

context(Verb, Props) ->
    cb_context:setters(cb_context:new()
                      ,[{fun cb_context:set_account_id/2, ?FIXTURE_MASTER_ACCOUNT_ID}
                       ,{fun cb_context:set_db_name/2, ?FIXTURE_MASTER_ACCOUNT_DB}
                       ,{fun cb_context:set_req_verb/2, Verb}
                       ,{fun cb_context:set_req_data/2, kz_json:from_list(Props)}
                       ,{fun cb_context:set_resp_status/2, 'success'}
                       ]).

rejection(Context) ->
    {cb_context:resp_status(Context)
    ,cb_context:resp_error_code(Context)
    ,kz_json:is_defined([?STOP, <<"invalid">>], cb_context:validation_errors(Context))
    }.

outcome(Context) ->
    {cb_context:resp_status(Context)
    ,cb_context:resp_error_code(Context)
    ,kz_json:encode(cb_context:validation_errors(Context))
    }.

weekly_rule(Window) ->
    [{<<"name">>, <<"Business Hours">>}
    ,{<<"cycle">>, <<"weekly">>}
    ,{<<"interval">>, 1}
    ,{<<"wdays">>, [<<"monday">>, <<"tuesday">>, <<"wednesday">>, <<"thursday">>, <<"friday">>]}
    ,{<<"start_date">>, 62586115200}
     | Window
    ].

christmas_rule() ->
    [{?START, 0}
    ,{?STOP, 86400}
    ,{<<"days">>, [25]}
    ,{<<"name">>, <<"Christmas">>}
    ,{<<"cycle">>, <<"yearly">>}
    ,{<<"start_date">>, 62586115200}
    ,{<<"month">>, 12}
    ,{<<"ordinal">>, <<"every">>}
    ,{<<"interval">>, 1}
    ].

holiday_rule() ->
    [{<<"name">>, <<"New Year">>}
    ,{<<"cycle">>, <<"yearly">>}
    ,{<<"interval">>, 1}
    ,{<<"month">>, 1}
    ,{<<"days">>, [1]}
    ,{<<"start_date">>, 62586115200}
    ].

date_rule() ->
    [{<<"name">>, <<"Office Closure">>}
    ,{<<"cycle">>, <<"date">>}
    ,{<<"start_date">>, 63808444800}
    ].
