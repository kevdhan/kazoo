%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2020, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_temporal_rules_tests).

-include_lib("eunit/include/eunit.hrl").

time_window_test_() ->
    [{"same-day window is accepted"
     ,?_assertEqual('success', validate([{<<"time_window_start">>, 32400}
                                        ,{<<"time_window_stop">>, 61200}
                                        ]))
     }
    ,{"overnight window is accepted"
     ,?_assertEqual('success', validate([{<<"time_window_start">>, 64800}
                                        ,{<<"time_window_stop">>, 28800}
                                        ]))
     }
    ,{"window that opens at midnight is accepted"
     ,?_assertEqual('success', validate([{<<"time_window_start">>, 0}
                                        ,{<<"time_window_stop">>, 43200}
                                        ]))
     }
    ,{"zero-length window is rejected"
     ,?_assertEqual('error', validate([{<<"time_window_start">>, 28800}
                                      ,{<<"time_window_stop">>, 28800}
                                      ]))
     }
    ,{"zero-length window error is reported on time_window_stop"
     ,?_assert(kz_json:is_defined([<<"time_window_stop">>, <<"invalid">>]
                                 ,validation_errors([{<<"time_window_start">>, 28800}
                                                    ,{<<"time_window_stop">>, 28800}
                                                    ])
                                 ))
     }
    ].

validate(Props) ->
    cb_context:resp_status(validated_context(Props)).

validation_errors(Props) ->
    cb_context:validation_errors(validated_context(Props)).

validated_context(Props) ->
    Doc = kz_json:from_list([{<<"name">>, <<"Rule">>}
                            ,{<<"cycle">>, <<"weekly">>}
                             | Props
                            ]),
    Context = cb_context:setters(cb_context:new()
                                ,[{fun cb_context:set_doc/2, Doc}
                                 ,{fun cb_context:set_resp_status/2, 'success'}
                                 ]),
    cb_temporal_rules:validate_time_window(Context).
