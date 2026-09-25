%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2020, 2600Hz
%%% @doc QA acceptance tests for KDS-1: overnight temporal rule windows.
%%%
%%% A rule whose time window start is later than its stop is an overnight
%%% window. It opens at the window start on each date the rule occurs and
%%% closes at the window stop on the following calendar day. The
%%% after-midnight portion belongs to the date the window opened, for every
%%% cycle type, including across month and year boundaries. Window start and
%%% stop seconds are inclusive.
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cf_temporal_route_overnight_qa_tests).

-include("callflow.hrl").
-include("module/cf_temporal_route.hrl").

-include_lib("eunit/include/eunit.hrl").

-define(HMS(H, M, S), ((H) * 3600 + (M) * 60 + (S))).

-define(WEEKDAYS, [<<"monday">>, <<"tuesday">>, <<"wednesday">>, <<"thursday">>, <<"friday">>]).

%% 18:00 - 08:00
-define(AFTER_HOURS_START, ?HMS(18, 0, 0)).
-define(AFTER_HOURS_STOP, ?HMS(8, 0, 0)).

%% 22:00 - 06:00
-define(NIGHT_START, ?HMS(22, 0, 0)).
-define(NIGHT_STOP, ?HMS(6, 0, 0)).

-define(MONDAY_START, {2018, 1, 1}).
-define(WEDNESDAY_START, {2018, 1, 3}).
-define(SATURDAY_START, {2018, 1, 6}).

%% Mondays anchoring the AC2 weeks
-define(AC2_WEEKS, [{2020, 9, 14} %% ordinary week
                   ,{2020, 8, 31} %% Mon Aug 31 .. Sat Sep 5, spans a month boundary
                   ,{2020, 6, 1}  %% Monday is the 1st
                   ,{2021, 3, 1}  %% Monday is the 1st, after a non-leap February
                   ,{2018, 12, 31} %% Mon Dec 31 .. Sat Jan 5, spans a year boundary
                   ]).

%%------------------------------------------------------------------------------
%% Fixture sanity: the calendar facts the expectations below rely on
%%------------------------------------------------------------------------------
fixture_calendar_sanity_test_() ->
    [{lists:flatten(io_lib:format("fixture: ~s is a Monday", [fmt_date(D)]))
     ,?_assertEqual(1, calendar:day_of_the_week(D))
     }
     || D <- ?AC2_WEEKS ++ [?MONDAY_START, {2020, 9, 7}, {2020, 8, 31}]
    ]
    ++ [{"fixture: 2018-01-03 is a Wednesday", ?_assertEqual(3, calendar:day_of_the_week(?WEDNESDAY_START))}
       ,{"fixture: 2018-01-06 is a Saturday", ?_assertEqual(6, calendar:day_of_the_week(?SATURDAY_START))}
       ,{"fixture: 2020-09-07 is the first Monday of September 2020", ?_assertEqual({2020, 8, 31}, add_days({2020, 9, 7}, -7))}
       ,{"fixture: 2020-09-25 is the last Friday of September 2020"
        ,?_assertEqual({5, {2020, 10, 2}}, {calendar:day_of_the_week({2020, 9, 25}), add_days({2020, 9, 25}, 7)})
        }
       ,{"fixture: 2020-07-31 is the last Friday of July 2020"
        ,?_assertEqual({5, {2020, 8, 7}}, {calendar:day_of_the_week({2020, 7, 31}), add_days({2020, 7, 31}, 7)})
        }
       ,{"fixture: 2020-12-31 is the last Thursday of December 2020"
        ,?_assertEqual({4, {2021, 1, 7}}, {calendar:day_of_the_week({2020, 12, 31}), add_days({2020, 12, 31}, 7)})
        }
       ,{"fixture: 2020-09-16 is a Wednesday", ?_assertEqual(3, calendar:day_of_the_week({2020, 9, 16}))}
       ,{"fixture: 2020 is a leap year", ?_assert(calendar:is_leap_year(2020))}
       ,{"fixture: 2021 is not a leap year", ?_assertNot(calendar:is_leap_year(2021))}
       ,{"fixture: every-other-day from 2020-01-01 occurs on 2020-09-15"
        ,?_assertEqual(0, days_between({2020, 1, 1}, {2020, 9, 15}) rem 2)
        }
       ,{"fixture: every-other-day from 2020-01-01 occurs on 2020-08-30"
        ,?_assertEqual(0, days_between({2020, 1, 1}, {2020, 8, 30}) rem 2)
        }
       ].

%%------------------------------------------------------------------------------
%% AC2: the weekly Monday-Friday 18:00-08:00 example on several weeks and
%% with start dates on different weekdays
%%------------------------------------------------------------------------------
ac2_weekly_example_test_() ->
    [ac2_week(Monday, StartDate)
     || StartDate <- [?MONDAY_START, ?WEDNESDAY_START],
        Monday <- ?AC2_WEEKS
    ]
    ++ [ac2_week({2020, 9, 14}, ?SATURDAY_START)].

ac2_week(Monday, StartDate) ->
    Rule = after_hours(StartDate),
    Label = lists:flatten(io_lib:format("weekly Mon-Fri 18:00-08:00 start ~s", [fmt_date(StartDate)])),
    [expect('true', Label, Rule, Monday, {19, 0, 0})
    ,expect('true', Label, Rule, add_days(Monday, 1), {3, 0, 0})
    ,expect('true', Label, Rule, add_days(Monday, 4), {23, 0, 0})
    ,expect('true', Label, Rule, add_days(Monday, 5), {3, 0, 0})
    ,expect('false', Label, Rule, Monday, {3, 0, 0})
    ,expect('false', Label, Rule, add_days(Monday, 6), {3, 0, 0})
    ,expect('false', Label, Rule, add_days(Monday, 2), {12, 0, 0})
    ].

%%------------------------------------------------------------------------------
%% AC2: every morning and evening of an ordinary week for the weekly rule
%%------------------------------------------------------------------------------
ac2_weekly_every_day_test_() ->
    Rule = after_hours(?MONDAY_START),
    Label = "weekly Mon-Fri 18:00-08:00",
    Monday = {2020, 9, 14},
    Mornings = [{0, 'false'}, {1, 'true'}, {2, 'true'}, {3, 'true'}, {4, 'true'}, {5, 'true'}, {6, 'false'}],
    Evenings = [{0, 'true'}, {1, 'true'}, {2, 'true'}, {3, 'true'}, {4, 'true'}, {5, 'false'}, {6, 'false'}],
    [expect(Expected, Label, Rule, add_days(Monday, N), {3, 0, 0}) || {N, Expected} <- Mornings]
        ++ [expect(Expected, Label, Rule, add_days(Monday, N), {19, 0, 0}) || {N, Expected} <- Evenings].

%%------------------------------------------------------------------------------
%% AC1: daily 22:00-06:00 on ordinary days
%%------------------------------------------------------------------------------
ac1_daily_midmonth_test_() ->
    Rule = nightly(),
    Label = "daily 22:00-06:00",
    [expect('true', Label, Rule, {2020, 9, 16}, {23, 0, 0})
    ,expect('true', Label, Rule, {2020, 9, 16}, {23, 59, 59})
    ,expect('true', Label, Rule, {2020, 9, 17}, {0, 0, 0})
    ,expect('true', Label, Rule, {2020, 9, 17}, {3, 0, 0})
    ,expect('false', Label, Rule, {2020, 9, 17}, {12, 0, 0})
    ,expect('false', Label, Rule, {2020, 9, 17}, {7, 0, 0})
    ,expect('false', Label, Rule, {2020, 9, 17}, {21, 0, 0})
    ,expect('true', Label, Rule, {2020, 9, 2}, {3, 0, 0})
    ,expect('true', Label, Rule, {2020, 9, 2}, {23, 0, 0})
    ].

%%------------------------------------------------------------------------------
%% AC3: daily 22:00-06:00 across month and year boundaries
%%------------------------------------------------------------------------------
ac3_daily_boundaries_test_() ->
    Rule = nightly(),
    Label = "daily 22:00-06:00",
    [expect('true', Label, Rule, {2020, 9, 30}, {23, 0, 0})
    ,expect('true', Label, Rule, {2020, 10, 1}, {2, 0, 0})
    ,expect('true', Label, Rule, {2020, 8, 31}, {23, 0, 0})
    ,expect('true', Label, Rule, {2020, 9, 1}, {2, 0, 0})
    ,expect('true', Label, Rule, {2020, 10, 31}, {23, 0, 0})
    ,expect('true', Label, Rule, {2020, 11, 1}, {2, 0, 0})
    ,expect('true', Label, Rule, {2021, 2, 28}, {23, 0, 0})
    ,expect('true', Label, Rule, {2021, 3, 1}, {2, 0, 0})
    ,expect('true', Label, Rule, {2020, 2, 29}, {23, 0, 0})
    ,expect('true', Label, Rule, {2020, 3, 1}, {2, 0, 0})
    ,expect('true', Label, Rule, {2020, 12, 31}, {23, 0, 0})
    ,expect('true', Label, Rule, {2021, 1, 1}, {2, 0, 0})
    ,expect('true', Label, Rule, {2020, 10, 1}, {23, 0, 0})
    ,expect('false', Label, Rule, {2020, 10, 1}, {12, 0, 0})
    ,expect('false', Label, Rule, {2021, 1, 1}, {12, 0, 0})
    ].

%%------------------------------------------------------------------------------
%% AC2: daily every other day (interval 2), starting 2020-01-01
%%------------------------------------------------------------------------------
ac2_daily_interval_test_() ->
    Rule = (nightly())#rule{interval=2},
    Label = "daily/2 from 2020-01-01 22:00-06:00",
    [expect('true', Label, Rule, {2020, 9, 15}, {23, 0, 0})
    ,expect('true', Label, Rule, {2020, 9, 16}, {3, 0, 0})
    ,expect('false', Label, Rule, {2020, 9, 16}, {23, 0, 0})
    ,expect('false', Label, Rule, {2020, 9, 17}, {3, 0, 0})
    ,expect('true', Label, Rule, {2020, 9, 17}, {23, 0, 0})
    ,expect('false', Label, Rule, {2020, 9, 15}, {3, 0, 0})
    ,expect('true', Label, Rule, {2020, 8, 30}, {23, 0, 0})
    ,expect('true', Label, Rule, {2020, 8, 31}, {3, 0, 0})
    ,expect('false', Label, Rule, {2020, 8, 31}, {23, 0, 0})
    ,expect('false', Label, Rule, {2020, 9, 1}, {3, 0, 0})
    ,expect('true', Label, Rule, {2020, 9, 1}, {23, 0, 0})
    ,expect('true', Label, Rule, {2020, 9, 2}, {3, 0, 0})
    ].

%%------------------------------------------------------------------------------
%% AC2/AC3: single date cycle
%%------------------------------------------------------------------------------
ac2_date_cycle_test_() ->
    [date_cases({2020, 9, 16})
    ,date_cases({2020, 9, 30})
    ,date_cases({2020, 12, 31})
    ].

date_cases(Date) ->
    Rule = #rule{cycle = <<"date">>
                ,start_date=Date
                ,wtime_start=?NIGHT_START
                ,wtime_stop=?NIGHT_STOP
                },
    Label = lists:flatten(io_lib:format("date ~s 22:00-06:00", [fmt_date(Date)])),
    [expect('true', Label, Rule, Date, {23, 0, 0})
    ,expect('true', Label, Rule, add_days(Date, 1), {3, 0, 0})
    ,expect('false', Label, Rule, Date, {3, 0, 0})
    ,expect('false', Label, Rule, add_days(Date, 1), {23, 0, 0})
    ,expect('false', Label, Rule, add_days(Date, 2), {3, 0, 0})
    ].

%%------------------------------------------------------------------------------
%% AC2/AC3: monthly by day of month
%%------------------------------------------------------------------------------
ac2_monthly_days_test_() ->
    [occurrence_cases(monthly_days(15), "monthly days=[15]", {2020, 9, 15})
    ,occurrence_cases(monthly_days(30), "monthly days=[30]", {2020, 9, 30})
    ,occurrence_cases(monthly_days(31), "monthly days=[31]", {2020, 8, 31})
    ,occurrence_cases(monthly_days(31), "monthly days=[31]", {2020, 12, 31})
    ].

%%------------------------------------------------------------------------------
%% AC2/AC3: monthly by ordinal weekday
%%------------------------------------------------------------------------------
ac2_monthly_ordinal_test_() ->
    [occurrence_cases(monthly_ordinal(<<"first">>, <<"monday">>), "monthly first monday", {2020, 9, 7})
    ,occurrence_cases(monthly_ordinal(<<"last">>, <<"friday">>), "monthly last friday", {2020, 9, 25})
    ,occurrence_cases(monthly_ordinal(<<"last">>, <<"friday">>), "monthly last friday", {2020, 7, 31})
    ,occurrence_cases(monthly_ordinal(<<"last">>, <<"monday">>), "monthly last monday", {2020, 8, 31})
    ,occurrence_cases(monthly_ordinal(<<"last">>, <<"thursday">>), "monthly last thursday", {2020, 12, 31})
    ].

%%------------------------------------------------------------------------------
%% AC2/AC3: yearly by date and by ordinal weekday
%%------------------------------------------------------------------------------
ac2_yearly_date_test_() ->
    [occurrence_cases(yearly_date(9, 16), "yearly Sep 16", {2020, 9, 16})
    ,occurrence_cases(yearly_date(12, 31), "yearly Dec 31", {2020, 12, 31})
    ].

ac2_yearly_ordinal_test_() ->
    [occurrence_cases(yearly_ordinal(<<"first">>, <<"monday">>, 9), "yearly first monday of Sep", {2020, 9, 7})
    ,occurrence_cases(yearly_ordinal(<<"last">>, <<"thursday">>, 12), "yearly last thursday of Dec", {2020, 12, 31})
    ].

%% Occurrence is a date the rule occurs on, and neither the day before nor
%% the day after it is an occurrence.
occurrence_cases(Rule, RuleLabel, Occurrence) ->
    Label = RuleLabel ++ " 22:00-06:00",
    [expect('true', Label, Rule, Occurrence, {23, 0, 0})
    ,expect('true', Label, Rule, add_days(Occurrence, 1), {3, 0, 0})
    ,expect('false', Label, Rule, Occurrence, {3, 0, 0})
    ,expect('false', Label, Rule, add_days(Occurrence, 1), {23, 0, 0})
    ,expect('false', Label, Rule, add_days(Occurrence, 2), {3, 0, 0})
    ].

%%------------------------------------------------------------------------------
%% AC1: window start and stop seconds are inclusive
%%------------------------------------------------------------------------------
ac1_inclusive_bounds_test_() ->
    [bounds_cases("daily 22:00-06:00", nightly(), {2020, 9, 16}, ?NIGHT_START, ?NIGHT_STOP)
    ,bounds_cases("daily 22:00-06:00", nightly(), {2020, 9, 30}, ?NIGHT_START, ?NIGHT_STOP)
    ,bounds_cases("daily 22:00-06:00", nightly(), {2020, 12, 31}, ?NIGHT_START, ?NIGHT_STOP)
    ,bounds_cases("weekly Mon-Fri 18:00-08:00", after_hours(?MONDAY_START), {2020, 9, 14}, ?AFTER_HOURS_START, ?AFTER_HOURS_STOP)
    ,bounds_cases("weekly Mon-Fri 18:00-08:00", after_hours(?MONDAY_START), {2020, 9, 18}, ?AFTER_HOURS_START, ?AFTER_HOURS_STOP)
    ,bounds_cases("date 2020-09-16 22:00-06:00"
                 ,#rule{cycle = <<"date">>, start_date={2020, 9, 16}, wtime_start=?NIGHT_START, wtime_stop=?NIGHT_STOP}
                 ,{2020, 9, 16}, ?NIGHT_START, ?NIGHT_STOP
                 )
    ,bounds_cases("monthly days=[15] 22:00-06:00", monthly_days(15), {2020, 9, 15}, ?NIGHT_START, ?NIGHT_STOP)
    ].

bounds_cases(Label, Rule, Opened, TStart, TStop) ->
    Next = add_days(Opened, 1),
    [expect('true', Label, Rule, Opened, calendar:seconds_to_time(TStart))
    ,expect('false', Label, Rule, Opened, calendar:seconds_to_time(TStart - 1))
    ,expect('true', Label, Rule, Next, calendar:seconds_to_time(TStop))
    ,expect('false', Label, Rule, Next, calendar:seconds_to_time(TStop + 1))
    ].

%%------------------------------------------------------------------------------
%% Rules
%%------------------------------------------------------------------------------
after_hours(StartDate) ->
    #rule{cycle = <<"weekly">>
         ,wdays=?WEEKDAYS
         ,start_date=StartDate
         ,wtime_start=?AFTER_HOURS_START
         ,wtime_stop=?AFTER_HOURS_STOP
         }.

nightly() ->
    #rule{cycle = <<"daily">>
         ,start_date={2020, 1, 1}
         ,wtime_start=?NIGHT_START
         ,wtime_stop=?NIGHT_STOP
         }.

monthly_days(Day) ->
    #rule{cycle = <<"monthly">>
         ,days=[Day]
         ,start_date={2020, 1, 1}
         ,wtime_start=?NIGHT_START
         ,wtime_stop=?NIGHT_STOP
         }.

monthly_ordinal(Ordinal, WDay) ->
    #rule{cycle = <<"monthly">>
         ,ordinal=Ordinal
         ,wdays=[WDay]
         ,start_date={2020, 1, 1}
         ,wtime_start=?NIGHT_START
         ,wtime_stop=?NIGHT_STOP
         }.

yearly_date(Month, Day) ->
    #rule{cycle = <<"yearly">>
         ,month=Month
         ,days=[Day]
         ,start_date={2020, 1, 1}
         ,wtime_start=?NIGHT_START
         ,wtime_stop=?NIGHT_STOP
         }.

yearly_ordinal(Ordinal, WDay, Month) ->
    #rule{cycle = <<"yearly">>
         ,ordinal=Ordinal
         ,wdays=[WDay]
         ,month=Month
         ,start_date={2020, 1, 1}
         ,wtime_start=?NIGHT_START
         ,wtime_stop=?NIGHT_STOP
         }.

%%------------------------------------------------------------------------------
%% Helpers
%%------------------------------------------------------------------------------
expect('true', Label, Rule, Date, Time) ->
    {title(Label, Date, Time, "matches"), ?_assert(is_active(Rule, Date, Time))};
expect('false', Label, Rule, Date, Time) ->
    {title(Label, Date, Time, "does not match"), ?_assertNot(is_active(Rule, Date, Time))}.

is_active(Rule, Date, Time) ->
    cf_temporal_route:is_rule_active(Rule, Date, calendar:datetime_to_gregorian_seconds({Date, Time})).

title(Label, Date, {H, M, S}, Verdict) ->
    lists:flatten(io_lib:format("~s: ~s ~s ~2..0b:~2..0b:~2..0b ~s"
                               ,[Label, wday_name(Date), fmt_date(Date), H, M, S, Verdict]
                               )).

fmt_date({Y, M, D}) ->
    io_lib:format("~4..0b-~2..0b-~2..0b", [Y, M, D]).

wday_name(Date) ->
    element(calendar:day_of_the_week(Date), {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"}).

add_days(Date, N) ->
    calendar:gregorian_days_to_date(calendar:date_to_gregorian_days(Date) + N).

days_between(From, To) ->
    calendar:date_to_gregorian_days(To) - calendar:date_to_gregorian_days(From).
