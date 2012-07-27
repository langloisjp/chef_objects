%% -*- erlang-indent-level: 4;indent-tabs-mode: nil; fill-column: 92 -*-
%% ex: ts=4 sw=4 et
%% @author James Casey <james@opscode.com>
%% @copyright Copyright 2012 Opscode, Inc.
%% @end
%% @doc interface to the certificate generation service

-module(chef_cert_http).

-define(X_OPS_REQUEST_ID, "X-Ops-Request-Id").

-export([
         gen_cert/2
        ]).

-spec gen_cert(Guid::binary(), RequestId::binary()) -> {Cert::binary(),
                                                        Keypair::binary()}.
%% @doc Handle HTTP interaction with remote certificate server.
%% This posts a common name (CN) to the server which is then used to generate
%% a certificate remotely.  We map common error cases to specific error messages
%% to help with debugging and throw
%%
gen_cert(Guid, RequestId) ->
    FullHeaders = [{?X_OPS_REQUEST_ID, binary_to_list(RequestId)},
                   {"Accept", "application/json"}
                  ],
    {ok, Url} = application:get_env(chef_common, certificate_root_url),
    Body = body_for_post(Guid),
    case ibrowse:send_req(Url, FullHeaders, post, Body) of
        {ok, Code, ResponseHeaders, ResponseBody} ->
            ok = check_http_response(Code, ResponseHeaders, ResponseBody),
            parse_json_response(ResponseBody);
        {error, Reason} ->
            throw({error, Reason})
    end.

-spec body_for_post(Guid::binary()) -> <<_:64,_:_*8>>.
%% @doc construct a body which can be posted to the certificate server
body_for_post(Guid) ->
    <<"common_name=URI:http://opscode.com/GUIDS/", Guid/binary>>.

-spec parse_json_response(Body::string()) -> {Cert::binary(),
                                              Keypair::binary()}.
%% @doc extract the certificate and keypair from the json structure.
%%
%% We apply here a version for the Pubkey
parse_json_response(Body) ->
    EJson = ejson:decode(Body),
    Cert = ej:get({<<"cert">>}, EJson),
    Keypair = ej:get({<<"keypair">>}, EJson),
    {Cert, Keypair}.

%% @doc Check the code of the HTTP response and throw error if non-2XX
%%
check_http_response(Code, Headers, Body) ->
    case Code of
        "2" ++ _Digits ->
            ok;
        "3" ++ _Digits ->
            throw({error, {redirection, {Code, Headers, Body}}});
        "404" ->
            throw({error, {not_found, {Code, Headers, Body}}});
        "4" ++ _Digits ->
            throw({error, {client_error, {Code, Headers, Body}}});
        "5" ++ _Digits ->
            throw({error, {server_error, {Code, Headers, Body}}})
    end.

