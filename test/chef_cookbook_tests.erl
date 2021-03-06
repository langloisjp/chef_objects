%% -*- erlang-indent-level: 4;indent-tabs-mode: nil; fill-column: 92-*-
%% ex: ts=4 sw=4 et
%% @author Seth Falcon <seth@opscode.com>
%% Copyright 2012 Opscode, Inc. All Rights Reserved.
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


-module(chef_cookbook_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("ej/include/ej.hrl").


basic_cookbook(Name, Version) ->
    basic_cookbook(Name, Version, []).

basic_cookbook(Name, Version, Options) ->
    %% Little helper function to cut down on verbosity
    Value = fun(Key, Default) ->
                    proplists:get_value(Key, Options, Default)
            end,
    {[
      {<<"name">>, <<Name/binary, "-", Version/binary>>},
      {<<"cookbook_name">>, Name},
      {<<"version">>, Version},
      {<<"chef_type">>, <<"cookbook_version">>},
      {<<"json_class">>, <<"Chef::CookbookVersion">>},
      {<<"frozen?">>, Value(frozen, false)},
      {<<"metadata">>, {[
                         {<<"version">>, Version},
                         {<<"name">>, Name},
                         {<<"dependencies">>, Value(dependencies, {[]})},
                         {<<"attributes">>, Value(attributes, {[]})},
                         {<<"long_description">>, Value(long_description, <<"">>)}
                        ]}}
     ]}.

minimal_cookbook_is_valid_test() ->
    CookbookEjson = basic_cookbook(<<"php">>, <<"1.2.3">>),
    Got = chef_cookbook:validate_cookbook(CookbookEjson, {<<"php">>, <<"1.2.3">>}),
    ?assertEqual({ok, CookbookEjson}, Got).

valid_resources_test() ->
    CB0 = basic_cookbook(<<"php">>, <<"1.2.3">>),
    NameVer = {<<"php">>, <<"1.2.3">>},
    CB = ej:set({<<"resources">>}, CB0,
                [{[
                   {<<"name">>, <<"a1">>},
                   {<<"path">>, <<"c/b/a1">>},
                   {<<"checksum">>, <<"abababababababababababababababab">>},
                   {<<"specificity">>, <<"default">>}
                  ]}]),
    ?assertEqual({ok, CB}, chef_cookbook:validate_cookbook(CB, NameVer)).

bad_resources_test_() ->
    CB0 = basic_cookbook(<<"php">>, <<"1.2.3">>),
    NameVer = {<<"php">>, <<"1.2.3">>},
    [
     {"resource value must be an array not an object",
      fun() ->
              CB = ej:set({<<"resources">>}, CB0, {[]}),
              ?assertThrow(#ej_invalid{type = json_type},
                           chef_cookbook:validate_cookbook(CB, NameVer))
      end},

     {"resource value must be an array not a string",
      fun() ->
              CB = ej:set({<<"resources">>}, CB0, <<"not-this">>),
              ?assertThrow(#ej_invalid{type = json_type},
                           chef_cookbook:validate_cookbook(CB, NameVer))
      end},

     {"resource array value must not be empty",
      fun() ->
              CB = ej:set({<<"resources">>}, CB0, [{[]}]),
              ?assertThrow(#ej_invalid{type = array_elt},
                           chef_cookbook:validate_cookbook(CB, NameVer))
      end}

    ].

valid_dependencies_test() ->
    CB0 = basic_cookbook(<<"php">>, <<"1.2.3">>),
    NameVer = {<<"php">>, <<"1.2.3">>},
    CB = ej:set({<<"metadata">>, <<"dependencies">>}, CB0,
                {[
                  {<<"apache2">>, <<"> 1.0.0">>},
                  {<<"apache3">>, <<">= 2.0.0">>},
                  {<<"crazy">>, <<"= 1.0">>},
                  {<<"aa">>, <<"~> 1.2.3">>},
                  {<<"bb">>, <<"< 1.2.3">>},
                  {<<"cc">>, <<"<= 1.2.3">>},
                  {<<"dd">>, <<"4.4.4">>}
                 ]}),
    ?assertEqual({ok, CB}, chef_cookbook:validate_cookbook(CB, NameVer)).

bad_dependencies_test_() ->
    CB0 = basic_cookbook(<<"php">>, <<"1.2.3">>),
    NameVer = {<<"php">>, <<"1.2.3">>},
    [
     {"cookbook name must be valid",
      fun() ->
              CB = ej:set({<<"metadata">>, <<"dependencies">>}, CB0,
                          {[
                            {<<"not valid name">>, <<"> 1.0.0">>}
                           ]}),
              ?assertThrow(#ej_invalid{type = object_key},
                           chef_cookbook:validate_cookbook(CB, NameVer))

      end},

     {"cookbook name must be valid",
      fun() ->
              CB = ej:set({<<"metadata">>, <<"dependencies">>}, CB0,
                          {[
                            {<<"apache2">>, <<"1b">>}
                           ]}),
              ?assertThrow(#ej_invalid{type = object_value},
                           chef_cookbook:validate_cookbook(CB, NameVer))

      end}

    ].

providing_constraint_test_() ->
    CB0 = basic_cookbook(<<"php">>, <<"1.2.3">>),
    NameVer = {<<"php">>, <<"1.2.3">>},
    SetProviding = fun(Recipe) ->
        ej:set({<<"metadata">>, <<"providing">>}, CB0,
               {[
                   {Recipe, <<"> 1.0.0">>}
                ]})
           end,
    [
     {"default recipe ok",
      fun() ->
              CB = SetProviding(<<"nginx">>),
              ?assertEqual({ok, CB}, chef_cookbook:validate_cookbook(CB, NameVer))
      end},
     {"recipe with :: ok",
      fun() ->
              CB = SetProviding(<<"nginx::foo">>),
              ?assertEqual({ok, CB}, chef_cookbook:validate_cookbook(CB, NameVer))
      end},
     {"empty recipe NOT ok",
      fun() ->
              CB = SetProviding(<<"">>),
              ?assertThrow(#ej_invalid{type = object_key},
                           chef_cookbook:validate_cookbook(CB, NameVer))
      end},
     {"recipe with single : NOT ok",
      fun() ->
              CB = SetProviding(<<"nginx:foo">>),
              ?assertThrow(#ej_invalid{type = object_key},
                           chef_cookbook:validate_cookbook(CB, NameVer))
      end},
     {"recipe ending in :: NOT ok",
      fun() ->
              CB = SetProviding(<<"nginx::">>),
              ?assertThrow(#ej_invalid{type = object_key},
                           chef_cookbook:validate_cookbook(CB, NameVer))
      end},
     {"recipe with second :: NOT ok",
      fun() ->
              CB = SetProviding(<<"nginx::foo::bar">>),
              ?assertThrow(#ej_invalid{type = object_key},
                           chef_cookbook:validate_cookbook(CB, NameVer))
      end},
     {"recipe with bad characters NOT ok",
      fun() ->
              CB = SetProviding(<<"nginx foo+bar">>),
              ?assertThrow(#ej_invalid{type = object_key},
                           chef_cookbook:validate_cookbook(CB, NameVer))
      end}
    ].

assemble_cookbook_ejson_test_() ->
    MockedModules = [chef_db],
    CBEJson = basic_cookbook(<<"php">>,
                             <<"1.2.3">>,
                             [
                              {long_description, <<"Behold, this is a long description!  And my, what a loooooooooooooooong description it is!">>},
                              {dependencies, {[{<<"ruby">>, []}]}}
                             ]),
    {foreach,
     fun() ->
             test_utils:mock(MockedModules, [passthrough]),
             meck:expect(chef_db, make_org_prefix_id,
                         fun(_OrgId, _Name) ->
                                 <<"deadbeefdeadbeefdeadbeefdeadbeef">>
                         end)
     end,
     fun(_) ->
             test_utils:unmock(MockedModules)
     end,
    [
     {"basic rehydration test",
      fun() ->
              OrgId = <<"12341234123412341234123412341234">>,
              AuthzId = <<"auth">>,
              Record = chef_object:new_record(chef_cookbook_version,
                                              OrgId,
                                              AuthzId,
                                              CBEJson),

              chef_test_utility:ejson_match(CBEJson,
                                            chef_cookbook:assemble_cookbook_ejson(Record)),

              test_utils:validate_modules(MockedModules)
      end}
    ]}.

version_to_binary_test() ->
    ?assertEqual(<<"1.2.3">>, chef_cookbook:version_to_binary({1,2,3})),
    ?assertEqual(<<"0.0.1">>, chef_cookbook:version_to_binary({0,0,1})).

parse_version_test() ->
    ?assertEqual({1,2,3}, chef_cookbook:parse_version(<<"1.2.3">>)),
    ?assertEqual({0,0,0}, chef_cookbook:parse_version(<<"0.0.0">>)).

parse_version_badversion_test() ->
    ?assertError(badarg, chef_cookbook:parse_version(<<"1.2.a">>)),
    ?assertError(badarg, chef_cookbook:parse_version(<<"1.2.0.0">>)),
    ?assertError(badarg, chef_cookbook:parse_version(<<"1.2">>)),
    ?assertError(badarg, chef_cookbook:parse_version(<<"-1">>)).

dependencies_to_depsolver_constraints_test_() ->
    {foreachx,
     fun({Terms, _Expected}) ->
             ejson:encode({Terms})
     end,
     fun(_, _) ->
             ok
     end,
     [ {{XTerms, XExpected},
        fun({_Terms, Expected}, JSON) ->
                {Description,
                 fun() ->
                         Actual = chef_object:depsolver_constraints(JSON),
                         ?assertEqual(Expected, Actual)
                 end}
        end}
       || {Description, XTerms, XExpected} <- [
                                               {"No dependency information", [],[]},

                                               {"One dependency",
                                                [{<<"apache">>, <<"> 1.0.0">>}],
                                                [{<<"apache">>, <<"1.0.0">>, '>'}]},

                                               {"Many dependencies",
                                                [
                                                 {<<"apache">>, <<"> 1.0.0">>},
                                                 {<<"mysql">>, <<"= 5.0.0">>},
                                                 {<<"ultra_fantastic_awesome_sauce">>, <<"= 6.6.6">>}
                                                ],
                                                [
                                                 {<<"apache">>, <<"1.0.0">>, '>'},
                                                 {<<"mysql">>, <<"5.0.0">>, '='},
                                                 {<<"ultra_fantastic_awesome_sauce">>, <<"6.6.6">>, '='}
                                                ]
                                               },

                                               {"All kinds of dependencies and constraint combinations",
                                                [
                                                 {<<"apache1">>, <<"> 1.0.0">>},
                                                 {<<"apache2">>, <<"> 1.0">>},
                                                 {<<"apache3">>, <<"> 1">>},

                                                 {<<"mysql1">>, <<"= 1.0.0">>},
                                                 {<<"mysql2">>, <<"= 1.0">>},
                                                 {<<"mysql3">>, <<"= 1">>},

                                                 {<<"nginx1">>, <<"< 1.0.0">>},
                                                 {<<"nginx2">>, <<"< 1.0">>},
                                                 {<<"nginx3">>, <<"< 1">>},

                                                 {<<"php1">>, <<"<= 1.0.0">>},
                                                 {<<"php2">>, <<"<= 1.0">>},
                                                 {<<"php3">>, <<"<= 1">>},

                                                 {<<"nagios1">>, <<">= 1.0.0">>},
                                                 {<<"nagios2">>, <<">= 1.0">>},
                                                 {<<"nagios3">>, <<">= 1">>},

                                                 {<<"ultra_fantastic_awesome_sauce1">>, <<"~> 1.0.0">>},
                                                 {<<"ultra_fantastic_awesome_sauce2">>, <<"~> 1.0">>},
                                                 {<<"ultra_fantastic_awesome_sauce3">>, <<"~> 1">>},

                                                 {<<"monkey_patches1">>, <<"1.0.0">>},
                                                 {<<"monkey_patches2">>, <<"1.0">>},
                                                 {<<"monkey_patches3">>, <<"1">>}
                                                ],
                                                [
                                                 {<<"apache1">>, <<"1.0.0">>, '>'},
                                                 {<<"apache2">>, <<"1.0">>, '>'},
                                                 {<<"apache3">>, <<"1">>, '>'},

                                                 {<<"mysql1">>, <<"1.0.0">>, '='},
                                                 {<<"mysql2">>, <<"1.0">>, '='},
                                                 {<<"mysql3">>, <<"1">>, '='},

                                                 {<<"nginx1">>, <<"1.0.0">>, '<'},
                                                 {<<"nginx2">>, <<"1.0">>, '<'},
                                                 {<<"nginx3">>, <<"1">>, '<'},

                                                 {<<"php1">>, <<"1.0.0">>, '<='},
                                                 {<<"php2">>, <<"1.0">>, '<='},
                                                 {<<"php3">>, <<"1">>, '<='},

                                                 {<<"nagios1">>, <<"1.0.0">>, '>='},
                                                 {<<"nagios2">>, <<"1.0">>, '>='},
                                                 {<<"nagios3">>, <<"1">>, '>='},

                                                 {<<"ultra_fantastic_awesome_sauce1">>, <<"1.0.0">>, '~>'},
                                                 {<<"ultra_fantastic_awesome_sauce2">>, <<"1.0">>, '~>'},
                                                 {<<"ultra_fantastic_awesome_sauce3">>, <<"1">>, '~>'},

                                                 {<<"monkey_patches1">>, <<"1.0.0">>, '='},
                                                 {<<"monkey_patches2">>, <<"1.0">>, '='},
                                                 {<<"monkey_patches3">>, <<"1">>, '='}

                                                ]
                                               }
                                              ]
     ]
    }.


recipe_name_test_() ->
    [{"Appropriately removes a '.rb' extension (normal, everyday case)",
      ?_assertEqual(<<"foo">>,
                    chef_cookbook:recipe_name(<<"foo.rb">>))},
     {"Behaves if recipes don't end in '.rb' (shouldn't happen in practice, though)",
      ?_assertEqual(<<"foo">>,
                    chef_cookbook:recipe_name(<<"foo">>))},
     {"Can still produce bizarre recipe names, if given a bizarre recipe name",
      ?_assertEqual(<<"foo.rb">>,
                    chef_cookbook:recipe_name(<<"foo.rb.rb">>))}].

maybe_qualify_name_test_() ->
    [{"Qualifies a 'normal' recipe name",
      ?_assertEqual(<<"cookbook::recipe">>,
                    chef_cookbook:maybe_qualify_name(<<"cookbook">>, <<"recipe.rb">>))},
     {"Qualifies a recipe name even without a '.rb' suffix (shouldn't happen in practice, though)",
      ?_assertEqual(<<"cookbook::recipe">>,
                    chef_cookbook:maybe_qualify_name(<<"cookbook">>, <<"recipe">>))},
     {"Does NOT qualifies a 'default' recipe; uses just the cookbook name instead",
      ?_assertEqual(<<"cookbook">>,
                    chef_cookbook:maybe_qualify_name(<<"cookbook">>, <<"default.rb">>))},
     {"Does NOT qualifies a 'default' recipe, even if it doesn't end in '.rb'; uses just the cookbook name instead",
      ?_assertEqual(<<"cookbook">>,
                    chef_cookbook:maybe_qualify_name(<<"cookbook">>, <<"default">>))},
     %% Not really expecting this next one to happen, just documenting the behavior
     {"Does NOT treat a recipe as the default if it is not named either 'default.rb' or just 'default'",
      ?_assertEqual(<<"cookbook::default.rb">>,
                    chef_cookbook:maybe_qualify_name(<<"cookbook">>, <<"default.rb.rb">>))}
    ].
