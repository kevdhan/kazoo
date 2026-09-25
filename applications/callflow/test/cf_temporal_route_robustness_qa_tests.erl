%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2020, 2600Hz
%%% @doc Robustness and backwards-compatibility tests for temporal route
%%% time windows: overnight windows must never crash rule evaluation, and
%%% same-day / default windows must keep their pre-existing behavior.
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cf_temporal_route_robustness_qa_tests).

-include("callflow.hrl").
-include("module/cf_temporal_route.hrl").

-include_lib("eunit/include/eunit.hrl").

-define(MON_FRI, [<<"monday">>, <<"tuesday">>, <<"wednesday">>, <<"thursday">>, <<"friday">>]).
-define(ALL_WDAYS, ?MON_FRI ++ [<<"saturday">>, <<"sunday">>]).

-define(AFTER_HOURS_START, 64800).
-define(AFTER_HOURS_STOP, 28800).
-define(OFFICE_START, 32400).
-define(OFFICE_STOP, 61200).

-define(RULE_START, {2018,1,1}).

%%------------------------------------------------------------------------------
%% One rule per cycle type, all using the 18:00 -> 08:00 overnight window.
%%------------------------------------------------------------------------------
overnight_rules() ->
    [{"date", #rule{cycle = <<"date">>, start_date={2020,3,1}}}
    ,{"daily", #rule{cycle = <<"daily">>, start_date=?RULE_START}}
    ,{"daily every 2 days", #rule{cycle = <<"daily">>, interval=2, start_date=?RULE_START}}
    ,{"weekly monday", #rule{cycle = <<"weekly">>, wdays=[<<"monday">>], start_date=?RULE_START}}
    ,{"weekly mon-fri", #rule{cycle = <<"weekly">>, wdays=?MON_FRI, start_date=?RULE_START}}
    ,{"weekly all days", #rule{cycle = <<"weekly">>, wdays=?ALL_WDAYS, start_date=?RULE_START}}
    ,{"weekly mon-fri every 2 weeks", #rule{cycle = <<"weekly">>, interval=2, wdays=?MON_FRI, start_date=?RULE_START}}
    ,{"monthly day 1", #rule{cycle = <<"monthly">>, days=[1], start_date=?RULE_START}}
    ,{"monthly day 31", #rule{cycle = <<"monthly">>, days=[31], start_date=?RULE_START}}
    ,{"monthly first monday", #rule{cycle = <<"monthly">>, ordinal = <<"first">>, wdays=[<<"monday">>], start_date=?RULE_START}}
    ,{"monthly last friday", #rule{cycle = <<"monthly">>, ordinal = <<"last">>, wdays=[<<"friday">>], start_date=?RULE_START}}
    ,{"monthly every wednesday", #rule{cycle = <<"monthly">>, ordinal = <<"every">>, wdays=[<<"wednesday">>], start_date=?RULE_START}}
    ,{"yearly january 1", #rule{cycle = <<"yearly">>, month=1, days=[1], start_date=?RULE_START}}
    ,{"yearly first monday of september", #rule{cycle = <<"yearly">>, month=9, ordinal = <<"first">>, wdays=[<<"monday">>], start_date=?RULE_START}}
    ,{"yearly every monday of january", #rule{cycle = <<"yearly">>, month=1, ordinal = <<"every">>, wdays=[<<"monday">>], start_date=?RULE_START}}
    ].

%% Month boundaries (including leap and non-leap March 1) plus a mid-month control.
boundary_dates() ->
    [{"Jan 1", {2020,1,1}}
    ,{"Mar 1 after Feb 29", {2020,3,1}}
    ,{"Mar 1 after Feb 28", {2021,3,1}}
    ,{"Sep 1", {2020,9,1}}
    ,{"mid-month Sep 16", {2020,9,16}}
    ].

%% Day 1 of a month falling on each weekday.
day_one_per_weekday() ->
    [{"monday Jun 1", {2020,6,1}}
    ,{"tuesday Sep 1", {2020,9,1}}
    ,{"wednesday Apr 1", {2020,4,1}}
    ,{"thursday Oct 1", {2020,10,1}}
    ,{"friday May 1", {2020,5,1}}
    ,{"saturday Feb 1", {2020,2,1}}
    ,{"sunday Mar 1", {2020,3,1}}
    ].

overnight_window_never_crashes_test_() ->
    [{title("~s overnight window on ~s at ~s returns a boolean", [Name, DateName, fmt_time(Time)])
     ,?_assert(is_boolean(is_active(overnight(Rule), {Date, Time})))
     }
     || {Name, Rule} <- overnight_rules()
            ,{DateName, Date} <- boundary_dates()
            ,Time <- [{3,0,0}, {20,0,0}]
    ].

overnight_window_never_crashes_on_any_weekday_test_() ->
    [{title("~s overnight window on ~s at 03:00:00 returns a boolean", [Name, DateName])
     ,?_assert(is_boolean(is_active(overnight(Rule), {Date, {3,0,0}})))
     }
     || {Name, Rule} <- [{"daily", #rule{cycle = <<"daily">>, start_date=?RULE_START}}
                        ,{"weekly mon-fri", #rule{cycle = <<"weekly">>, wdays=?MON_FRI, start_date=?RULE_START}}
                        ]
            ,{DateName, Date} <- day_one_per_weekday()
    ].

extreme_overnight_windows_never_crash_test_() ->
    Daily = #rule{cycle = <<"daily">>, start_date=?RULE_START},
    [{title("daily ~b -> ~b window on Sep 1 at ~s returns a boolean", [Start, Stop, fmt_time(Time)])
     ,?_assert(is_boolean(is_active(Daily#rule{wtime_start=Start, wtime_stop=Stop}, {{2020,9,1}, Time})))
     }
     || {Start, Stop} <- [{86399, 0}, {1, 0}, {86400, 0}, {86400, 86399}]
            ,Time <- [{0,0,0}, {12,0,0}, {23,59,59}]
    ].

%% An overnight window opens on a rule day and closes the following morning,
%% including when the following morning is the first day of a month.
overnight_window_on_first_of_month_reaches_rule_test_() ->
    Daily = overnight(#rule{cycle = <<"daily">>, start_date=?RULE_START}),
    Weekly = overnight(#rule{cycle = <<"weekly">>, wdays=?MON_FRI, start_date=?RULE_START}),
    Monday = overnight(#rule{cycle = <<"weekly">>, wdays=[<<"monday">>], start_date=?RULE_START}),
    Day31 = overnight(#rule{cycle = <<"monthly">>, days=[31], start_date=?RULE_START}),
    Day1 = overnight(#rule{cycle = <<"monthly">>, days=[1], start_date=?RULE_START}),
    [{"daily overnight is active Sep 1 03:00 (opened Aug 31 18:00)"
     ,?_assert(is_active(Daily, {{2020,9,1}, {3,0,0}}))}
    ,{"daily overnight is inactive Sep 1 12:00"
     ,?_assertNot(is_active(Daily, {{2020,9,1}, {12,0,0}}))}
    ,{"daily overnight is active Sep 1 20:00 (opened Sep 1 18:00)"
     ,?_assert(is_active(Daily, {{2020,9,1}, {20,0,0}}))}
    ,{"daily overnight is active Jan 1 03:00 (opened Dec 31 18:00)"
     ,?_assert(is_active(Daily, {{2020,1,1}, {3,0,0}}))}
    ,{"daily overnight is active Mar 1 2020 03:00 (opened Feb 29 18:00)"
     ,?_assert(is_active(Daily, {{2020,3,1}, {3,0,0}}))}
    ,{"daily overnight is active Mar 1 2021 03:00 (opened Feb 28 18:00)"
     ,?_assert(is_active(Daily, {{2021,3,1}, {3,0,0}}))}
    ,{"weekly mon-fri overnight is active Tue Sep 1 03:00 (opened Mon Aug 31 18:00)"
     ,?_assert(is_active(Weekly, {{2020,9,1}, {3,0,0}}))}
    ,{"weekly mon-fri overnight is inactive Mon Jun 1 03:00 (Sunday is not a rule day)"
     ,?_assertNot(is_active(Weekly, {{2020,6,1}, {3,0,0}}))}
    ,{"weekly mon-fri overnight is active Mon Jun 1 20:00"
     ,?_assert(is_active(Weekly, {{2020,6,1}, {20,0,0}}))}
    ,{"weekly mon-fri overnight is inactive Sun Mar 1 03:00 (Saturday is not a rule day)"
     ,?_assertNot(is_active(Weekly, {{2020,3,1}, {3,0,0}}))}
    ,{"weekly monday overnight is active Tue Sep 1 03:00 (opened Mon Aug 31 18:00)"
     ,?_assert(is_active(Monday, {{2020,9,1}, {3,0,0}}))}
    ,{"monthly day 31 overnight is active Sep 1 03:00 (opened Aug 31 18:00)"
     ,?_assert(is_active(Day31, {{2020,9,1}, {3,0,0}}))}
    ,{"monthly day 1 overnight is inactive Sep 1 03:00 (Aug 31 is not a rule day)"
     ,?_assertNot(is_active(Day1, {{2020,9,1}, {3,0,0}}))}
    ,{"monthly day 1 overnight is active Sep 1 20:00"
     ,?_assert(is_active(Day1, {{2020,9,1}, {20,0,0}}))}
    ].

%%------------------------------------------------------------------------------
%% Same-day and default windows: expected values match the behavior before
%% overnight windows were introduced; window bounds are inclusive.
%%------------------------------------------------------------------------------
same_day_window_unchanged_test_() ->
    Office = #rule{cycle = <<"weekly">>, wdays=?MON_FRI, start_date={2020,1,6}
                  ,wtime_start=?OFFICE_START, wtime_stop=?OFFICE_STOP
                  },
    Monthly1 = #rule{cycle = <<"monthly">>, days=[1], start_date=?RULE_START
                    ,wtime_start=?OFFICE_START, wtime_stop=?OFFICE_STOP
                    },
    FirstMonday = #rule{cycle = <<"monthly">>, ordinal = <<"first">>, wdays=[<<"monday">>], start_date=?RULE_START
                       ,wtime_start=?OFFICE_START, wtime_stop=?OFFICE_STOP
                       },
    Date = #rule{cycle = <<"date">>, start_date={2020,6,15}
                ,wtime_start=?OFFICE_START, wtime_stop=?OFFICE_STOP
                },
    [{"weekly mon-fri 09:00-17:00 inactive Wed 08:59:59 (start - 1)"
     ,?_assertNot(is_active(Office, {{2020,9,16}, {8,59,59}}))}
    ,{"weekly mon-fri 09:00-17:00 active Wed 09:00:00 (start is inclusive)"
     ,?_assert(is_active(Office, {{2020,9,16}, {9,0,0}}))}
    ,{"weekly mon-fri 09:00-17:00 active Wed 17:00:00 (stop is inclusive)"
     ,?_assert(is_active(Office, {{2020,9,16}, {17,0,0}}))}
    ,{"weekly mon-fri 09:00-17:00 inactive Wed 17:00:01 (stop + 1)"
     ,?_assertNot(is_active(Office, {{2020,9,16}, {17,0,1}}))}
    ,{"weekly mon-fri 09:00-17:00 inactive Sat 10:00"
     ,?_assertNot(is_active(Office, {{2020,9,19}, {10,0,0}}))}
    ,{"weekly mon-fri 09:00-17:00 active Tue Sep 1 09:00 (first of month)"
     ,?_assert(is_active(Office, {{2020,9,1}, {9,0,0}}))}
    ,{"weekly mon-fri 09:00-17:00 active Thu Oct 1 17:00 (first of month)"
     ,?_assert(is_active(Office, {{2020,10,1}, {17,0,0}}))}
    ,{"weekly mon-fri 09:00-17:00 active Mon Jun 1 09:00 (first of month)"
     ,?_assert(is_active(Office, {{2020,6,1}, {9,0,0}}))}
    ,{"weekly mon-fri 09:00-17:00 inactive Sat Feb 1 12:00 (first of month)"
     ,?_assertNot(is_active(Office, {{2020,2,1}, {12,0,0}}))}
    ,{"monthly day 1 09:00-17:00 active Mar 1 09:00:00 (start is inclusive)"
     ,?_assert(is_active(Monthly1, {{2020,3,1}, {9,0,0}}))}
    ,{"monthly day 1 09:00-17:00 inactive Mar 1 08:59:59"
     ,?_assertNot(is_active(Monthly1, {{2020,3,1}, {8,59,59}}))}
    ,{"monthly day 1 09:00-17:00 active Mar 1 17:00:00 (stop is inclusive)"
     ,?_assert(is_active(Monthly1, {{2020,3,1}, {17,0,0}}))}
    ,{"monthly day 1 09:00-17:00 inactive Mar 1 17:00:01"
     ,?_assertNot(is_active(Monthly1, {{2020,3,1}, {17,0,1}}))}
    ,{"monthly day 1 09:00-17:00 inactive Mar 2 12:00"
     ,?_assertNot(is_active(Monthly1, {{2020,3,2}, {12,0,0}}))}
    ,{"monthly first monday 09:00-17:00 active Jun 1 09:00"
     ,?_assert(is_active(FirstMonday, {{2020,6,1}, {9,0,0}}))}
    ,{"monthly first monday 09:00-17:00 inactive Jun 8 09:00"
     ,?_assertNot(is_active(FirstMonday, {{2020,6,8}, {9,0,0}}))}
    ,{"date 09:00-17:00 active on the date at 09:00:00"
     ,?_assert(is_active(Date, {{2020,6,15}, {9,0,0}}))}
    ,{"date 09:00-17:00 inactive on the date at 08:59:59"
     ,?_assertNot(is_active(Date, {{2020,6,15}, {8,59,59}}))}
    ,{"date 09:00-17:00 active on the date at 17:00:00"
     ,?_assert(is_active(Date, {{2020,6,15}, {17,0,0}}))}
    ,{"date 09:00-17:00 inactive the day after at 09:00"
     ,?_assertNot(is_active(Date, {{2020,6,16}, {9,0,0}}))}
    ].

same_day_window_edges_unchanged_test_() ->
    Daily = #rule{cycle = <<"daily">>, start_date=?RULE_START},
    FirstSecond = Daily#rule{wtime_start=0, wtime_stop=1},
    LastSecond = Daily#rule{wtime_start=86399, wtime_stop=86400},
    [{"daily 0-1 window active at 00:00:00"
     ,?_assert(is_active(FirstSecond, {{2020,9,16}, {0,0,0}}))}
    ,{"daily 0-1 window active at 00:00:01 (stop is inclusive)"
     ,?_assert(is_active(FirstSecond, {{2020,9,16}, {0,0,1}}))}
    ,{"daily 0-1 window inactive at 00:00:02"
     ,?_assertNot(is_active(FirstSecond, {{2020,9,16}, {0,0,2}}))}
    ,{"daily 86399-86400 window inactive at 23:59:58"
     ,?_assertNot(is_active(LastSecond, {{2020,9,16}, {23,59,58}}))}
    ,{"daily 86399-86400 window active at 23:59:59 (start is inclusive)"
     ,?_assert(is_active(LastSecond, {{2020,9,16}, {23,59,59}}))}
    ].

default_window_unchanged_test_() ->
    Daily = #rule{cycle = <<"daily">>, start_date=?RULE_START},
    EveryOtherDay = Daily#rule{interval=2},
    Day15 = #rule{cycle = <<"monthly">>, days=[15], start_date=?RULE_START},
    LastFriday = #rule{cycle = <<"monthly">>, ordinal = <<"last">>, wdays=[<<"friday">>], start_date=?RULE_START},
    NewYear = #rule{cycle = <<"yearly">>, month=1, days=[1], start_date=?RULE_START},
    Thanksgiving = #rule{cycle = <<"yearly">>, month=11, ordinal = <<"fourth">>, wdays=[<<"thursday">>], start_date=?RULE_START},
    [{"daily default window active Jan 1 00:00:00"
     ,?_assert(is_active(Daily, {{2020,1,1}, {0,0,0}}))}
    ,{"daily default window active Jan 1 23:59:59"
     ,?_assert(is_active(Daily, {{2020,1,1}, {23,59,59}}))}
    ,{"daily default window active Mar 1 2020 00:00:00"
     ,?_assert(is_active(Daily, {{2020,3,1}, {0,0,0}}))}
    ,{"daily default window active Mar 1 2021 12:00"
     ,?_assert(is_active(Daily, {{2021,3,1}, {12,0,0}}))}
    ,{"every-2-days default window active Jan 1 2020 12:00"
     ,?_assert(is_active(EveryOtherDay, {{2020,1,1}, {12,0,0}}))}
    ,{"every-2-days default window inactive Jan 2 2020 12:00"
     ,?_assertNot(is_active(EveryOtherDay, {{2020,1,2}, {12,0,0}}))}
    ,{"every-2-days default window active Mar 1 2020 12:00"
     ,?_assert(is_active(EveryOtherDay, {{2020,3,1}, {12,0,0}}))}
    ,{"monthly day 15 default window active Sep 15 00:00:00"
     ,?_assert(is_active(Day15, {{2020,9,15}, {0,0,0}}))}
    ,{"monthly day 15 default window active Sep 15 23:59:59"
     ,?_assert(is_active(Day15, {{2020,9,15}, {23,59,59}}))}
    ,{"monthly day 15 default window inactive Sep 14 23:59:59"
     ,?_assertNot(is_active(Day15, {{2020,9,14}, {23,59,59}}))}
    ,{"monthly day 15 default window inactive Sep 16 00:00:00"
     ,?_assertNot(is_active(Day15, {{2020,9,16}, {0,0,0}}))}
    ,{"monthly last friday default window active Sep 25 12:00"
     ,?_assert(is_active(LastFriday, {{2020,9,25}, {12,0,0}}))}
    ,{"monthly last friday default window inactive Sep 18 12:00"
     ,?_assertNot(is_active(LastFriday, {{2020,9,18}, {12,0,0}}))}
    ,{"yearly Jan 1 default window active Jan 1 2020 12:00"
     ,?_assert(is_active(NewYear, {{2020,1,1}, {12,0,0}}))}
    ,{"yearly Jan 1 default window inactive Dec 31 2019 23:59:59"
     ,?_assertNot(is_active(NewYear, {{2019,12,31}, {23,59,59}}))}
    ,{"yearly Jan 1 default window active Jan 1 2021 00:00:00"
     ,?_assert(is_active(NewYear, {{2021,1,1}, {0,0,0}}))}
    ,{"yearly fourth thursday of november default window active Nov 26 2020"
     ,?_assert(is_active(Thanksgiving, {{2020,11,26}, {12,0,0}}))}
    ,{"yearly fourth thursday of november default window inactive Nov 19 2020"
     ,?_assertNot(is_active(Thanksgiving, {{2020,11,19}, {12,0,0}}))}
    ].

%%------------------------------------------------------------------------------
%% Helpers
%%------------------------------------------------------------------------------
overnight(Rule) ->
    Rule#rule{wtime_start=?AFTER_HOURS_START
             ,wtime_stop=?AFTER_HOURS_STOP
             }.

is_active(Rule, {Date, _Time}=DateTime) ->
    cf_temporal_route:is_rule_active(Rule, Date, calendar:datetime_to_gregorian_seconds(DateTime)).

title(Format, Args) ->
    lists:flatten(io_lib:format(Format, Args)).

fmt_time({H, M, S}) ->
    title("~2..0b:~2..0b:~2..0b", [H, M, S]).
