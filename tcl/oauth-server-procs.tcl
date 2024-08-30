::xo::library doc {
  OAuth Server

  @author Michael Aram
  @creation-date 2012

  Translation to XOTcl2:
  Gustaf Neumann    
}

if {0} {
namespace eval ::xo::oauth {

  #
  # OAuth Server Mixin Class
  #

  Class create Server

  Server ad_instproc server_metadata {} {
    Server metadata
  } {
    set :server_metadata_id [:require_server_metadata]
    :log "I retrieved the sm: ${:server_metadata_id}"
    set server [::xo::db::CrClass get_instance_from_db -item_id ${:server_metadata_id}]
    :log ""
    return $server
  }

  Server ad_instproc require_server_metadata {} {
    Require server metadata
  } {
    set parent_id ${:folder_id}
    set server_metadata_id [ns_cache eval xotcl_object_type_cache xooauth_server_metadata-${:id} {
      set server_metadata_id [::xo::db::CrClass lookup \
                                  -name xooauth_server_metadata \
                                  -parent_id $parent_id]
      if {$server_metadata_id == 0} {
        :log "This package has no server metadata yet."
        set system_url [ad_url]
        set server_metadata [::xo::oauth::ServerMetadata new \
                                 -name xooauth_server_metadata \
                                 -parent_id $parent_id \
                                 -package_id ${:id} \
                                 -temp_credentials_url "${system_url}/oauth/initiate" \
                                 -token_credentials_url "${system_url}/oauth/token" \
                                 -authorization_url "${system_url}/oauth/authorize"]
        $server_metadata save_new
        set server_metadata_id [$server_metadata item_id]
        :log "Created XOOAuth Server metadata for package ${:id} in folder $parent_id"
      }
      :log "returning from cache server_metadata_id $server_metadata_id"
      return $server_metadata_id
    }]
    #my log "returning from require server_metadata_id $server_metadata_id"
    return $server_metadata_id
  }


  #
  # Methods exposed via the web interface.
  #

  Server instproc initiate {} {
    # TODO: This URL must be only accessible via HTTPS
    if {[:verify_incoming_request]} {
      # We have a valid request
      set client_identifier [:request_parameter oauth_consumer_key]
      set callback [:request_parameter oauth_callback]
      set client_credentials [:get_credentials -identifier $client_identifier]
      set parent_id ${:folder_id}
      set temporary_credentials [TempCredentials new \
                                     -identifier [ad_generate_random_string] \
                                     -parent_id $parent_id \
                                     -secret [ad_generate_random_string] \
                                     -callback $callback \
                                     -server_metadata_id [[:server_metadata] item_id] \
                                     -client_metadata_id [$client_credentials client_metadata_id]]
      $temporary_credentials save_new
      :log [$temporary_credentials serialize]
      set response_body "[$temporary_credentials as_encoded_string]&oauth_callback_confirmed=true"
      doc_return 200 "text/plain" $response_body
      # doc_return 200 "application/x-www-form-urlencoded" $response_body
    } else {
      doc_return 404 text/html "Not Authorized"
    }
    #set oauth_parameters [ProtocolParameters initialize_from_cc [:context]]
    #set response_body [$oauth_parameters serialize]
    #doc_return 200 text/html $response_body
  }

  Server ad_instproc authorize {} {
    @see http://tools.ietf.org/html/rfc5849#section-2.2
  } {
    # TODO: Authorization Verifier ohne callback ermöglichen!!
    # TODO: Make a filter
    util_driver_info -array driver
    if {$driver(proto) ne "https"} {
      ns_log warning "OAuth must be used over SSL to be secure!"
    }

    auth::require_login

    set temp_cred_id [:request_parameter oauth_token]

    # TODO: Make this a parameter
    set adp /packages/xooauth/lib/authorize
    set :mime_type text/html
    set temp_credentials [:get_credentials \
                              -identifier $temp_cred_id \
                              -server [:server_metadata]]
    :log [$temp_credentials serialize]
    set client [$temp_credentials client_metadata_id]

    # Generate a verifier for the temporary credential.
    set oauth_verifier [ad_generate_random_string]
    $temp_credentials verifier $oauth_verifier
    #TODO: Can we avoid this save?
    #TODO: Is it semantically correct to:
    #       a) generate a new verifier upon each incoming request?
    #       b) generate it once and complain upon any other request?
    # note: it IS better to save it here instead of upon form submit, 
    # because otherwise - without submit - the verifier would not go to
    # the db...
    $temp_credentials save

    :return_page -adp $adp -variables {
      client temp_credentials
    }
  }

  Server ad_instproc token {} {
    Token credentials
  } {
    # TODO: This URL must be only accessible via HTTPS
    if {[:verify_incoming_request]} {
      # We have a valid request
      set client_credentials [:credentials_from_request_parameter oauth_consumer_key]
      set temporary_credentials [:credentials_from_request_parameter oauth_token]
      #TODO: Verify the incoming verifier
      set parent_id ${:folder_id}
      set token_credentials [TokenCredentials new \
                                 -parent_id $parent_id \
                                 -identifier [ad_generate_random_string] \
                                 -secret [ad_generate_random_string] \
                                 -client [$client_credentials client]]
      $token_credentials save_new
      :log [$token_credentials serialize]
      set response_body "[$token_credentials as_encoded_string]"
      doc_return 200 "text/plain" $response_body
      # doc_return 200 "application/x-www-form-urlencoded" $response_body
    } else {
      doc_return 404 text/html "Not Authorized"
    }
    #set oauth_parameters [ProtocolParameters initialize_from_cc [:context]]
    #set response_body [$oauth_parameters serialize]
    #doc_return 200 text/html $response_body
  }

  Server instproc credentials_from_request_parameter {p} {
    set identifier [:request_parameter $p]
    set credentials [:get_credentials -identifier $identifier]
    return $credentials
  }

  Server ad_instproc get_credentials {
    {-identifier}
    {-server ""}
    {-client ""}
  } {
    Get credentials
  } {
    # TODO: Replace with ::xo::db-layer code
    set sql "
      SELECT DISTINCT item_id
      FROM [Credentials table_name]x
      WHERE identifier = :identifier
    "
    if {$client ne ""} {
      set client_metadata_id [$client item_id]
      append sql " AND client_metadata_id = :client_metadata_id "
    }
    if {$server ne ""} {
      set server_metadata_id [$server item_id]
      append sql " AND server_metadata_id = :server_metadata_id "
    }
    set item_id [xo::dc get_value [:qn select_item_id] $sql -default 0]
    if {!$item_id} {
      ad_return_complaint 0 \
          "Could not fetch credentials for identifier '$identifier' and server '$server' and client '$client'"
      ad_script_abort
    }
    set instance [::xo::db::CrClass get_instance_from_db -item_id $item_id]
    return $instance
  }

  Server ad_instproc request_parameter {
    {-override_empty_values false}
    name
    {default ""}
  } {
    Request parameter
  } {
    set authorization_header_parameter [:authorization_header_parameter $name $default]
    #my log "AAAAAAA $name - $default - $authorization_header_parameter"
    if {$authorization_header_parameter ne $default} {
      return $authorization_header_parameter
    }
    set form_parameter [[:context] form_parameter $name $default]
    if {$form_parameter ne $default
        && (!$override_empty_values || $form_parameter ne "")} {
      return $form_parameter
    }
    set query_parameter [[:context] query_parameter $name $default]
    if {$query_parameter ne $default
        && (!$override_empty_values || $query_parameter ne "")} {
      return $query_parameter
    }
    return $default
  }

  Server instproc authorization_header_parameter {name {default ""}} {
    if {[:exists_authorization_header_parameter $name]} {
      #my log "Yes, the parameter $name seems to exist in [ns_set get [ns_conn headers] Authorization]"
      foreach parameter_pair [:get_authorization_header_parameters] {
        lassign $parameter_pair key value
        #my log "Testing $key against $name"
        if {$key eq $name} {
          #my log "Returning $value"
          return $value
        }
      }
    } else {
      #my log "No, the parameter $name seems not to exist in [ns_set get [ns_conn headers] Authorization]"
      return $default
    }
  }

  Server instproc exists_request_parameter {name} {
    if {[:exists_authorization_header_parameter $name]} {
      return 1
    }
    if {[[:context] exists_form_parameter $name]} {
      return 1
    }
    if {[[:context] exists_query_parameter $name]} {
      return 1
    }
    return 0
  }

  Server instproc exists_authorization_header_parameter {name} {
    foreach parameter_pair [:get_authorization_header_parameters] {
      lassign $parameter_pair key value
      #my log "KEY: $key VALUE: $value"
      if {$key eq $name} {
        return 1
      }
    }
    return 0
  }

  #
  # Private methods
  #

  Server ad_instproc privilege=oauth {{-login true} user_id package_id method} {
    This method implements a privilege for the xotcl-core permission system,
    so that one is able to protect methods via policies. For example:
    <pre>
    Class create Package -array set require_permission {
      view                {{id read}}
      protected-service   oauth
    }
    </pre>
  } {
    #my log "Validating OAuth signature"
    set signature_is_valid [:verify_incoming_request]
    return $signature_is_valid
  }

  Server ad_instproc verify_incoming_request {} {
    @see http://tools.ietf.org/html/rfc5849#section-3.2
  } {
    # Verify signature
    set client_signature [:request_parameter oauth_signature]
    if {$client_signature eq ""} {
      :log "Cannot verify request - no signature provided"
      doc_return 401 text/plain "Unauthorized. Unsigned request!"
      ad_script_abort
      return 0
    }
    set client_identifier [:request_parameter oauth_consumer_key]
    set client_credentials [:get_credentials -identifier $client_identifier -server [:server_metadata]]
    if {$client_credentials eq ""} {
      :log "Cannot verify request - no client credentials found"
      doc_return 401 text/plain "Unauthorized. Client unknown!"
      ad_script_abort
      return 0
    }
    # BEWARE: This puts secrets into the log file!
    #my log "Client credentials: [$client_credentials serialize]"

    # see http://tools.ietf.org/html/rfc5849#appendix-A
    set has_non_empty_token [expr {[:exists_request_parameter oauth_token] && [:request_parameter oauth_token] ne ""}]
    if {$has_non_empty_token} {
      set token_identifier [:request_parameter oauth_token]
      set token_credentials [:get_credentials -identifier $token_identifier]
    }
    set server_signature_object [Signature new \
                                     -volatile \
                                     -request_method [ns_conn method] \
                                     -base_string_uri [:generate_signature_uri] \
                                     -client_secret [$client_credentials secret] \
                                     -signature_parameters [:collect_signature_parameters] ]
    $server_signature_object lappend signature_parameters [list oauth_consumer_secret [$client_credentials secret]]
    if {$has_non_empty_token} {
      $server_signature_object token_secret [$token_credentials secret]
      $server_signature_object lappend signature_parameters [list oauth_token_secret [$token_credentials secret]]
    }

    set server_signature [$server_signature_object generate]
    if {$server_signature ne $client_signature} {
      :log "Unauthorized. Signatures do NOT match! \nServer Signature: $server_signature \nClient Signature: $client_signature"
      doc_return 401 text/plain "Unauthorized. Signatures do not match!"
      ad_script_abort
      return 0
    } else {
      :log "Signatures do match: Server Signature: $server_signature Client Signature: $client_signature"
    }
    # TODO: Verify combination of nonce/timestamp/token has not been used before
    # TODO: Verify scope and status of client authorization
    # TODO: Verify oauth_version is 1.0

    # We reached this point- seems to be a valid request
    return 1
    #set response_body [$oauth_parameters serialize]
    #doc_return 200 text/html $response_body
  }

  Server instproc generate_signature_uri {} {
    # The port MUST be omitted, if it is the standard port (80/443)
    # and it MUST be included if it is any other port.
    #set host_header [string tolower [ns_set get [ns_conn headers] Host]]
    #set scheme [expr {[security::secure_conn_p] ? "https" : "http"}]
    set host_header [ad_url]
    regexp {^(https?)://(.*):?([^:]*)$} $host_header _ scheme host port
    regexp {^(https?)://([^:/]*):?([0-9]*)?} $host_header _ scheme host port
    set path_query_fragment [ns_conn url]
    #my log ----$path_query_fragment
    # Strip eventual query parameters from path
    set info [uri::split $path_query_fragment]
    set path [dict get $info path]
    # uri::join also omits default ports, as required by OAuth
    set base_string_uri [uri::join scheme $scheme host $host port $port path $path]
    #my log "set base_string_uri uri::join scheme $scheme host $host port $port path $path"
    return $base_string_uri
  }

  Server ad_instproc decode {s} {
    URL decode
  } {
    return [::xo::oauth::utility urldecode $s]
  }

  Server ad_instproc get_authorization_header_parameters {} {
    Gathers OAuth parameters from the "Authorization" header of the incoming request.
  } {
    set parameter_pairs [list]
    set authorization_header [ns_set get [ns_conn headers] Authorization]
    set authorization_header [regsub {OAuth } $authorization_header ""]
    set authorization_header_parameters [split $authorization_header ,]
    foreach parameter_pair $authorization_header_parameters {
      foreach {key value} [split $parameter_pair =] {
        set value [string range $value 1 end-1]
        lappend parameter_pairs [list [:decode [string trim $key]] [:decode [string trim $value]]]
        #my log "lappend parameter_pairs [list [string trim $key] [string trim $value]]"
        #my log "lappend parameter_pairs [list [:decode [string trim $key]] [:decode [string trim $value]]]"
      }
    }
    return $parameter_pairs
  }


  Server ad_instproc collect_signature_parameters {} {
    Gathers the parameters to be signed from the incoming request.
  } {
    set cc [:context]
    #array set uri [uri::split [:url]]
    set parameter_pair_list [list]
    set query_parameter_list [list]

    # These parameters did not come from outside, but were set
    # during initialization of the package (index.vuh)
    set omit_parameter_list [list]
    foreach p [::xo::cc parameter_declaration] {
      # Turn something like "-folder_id:integer" into "folder_id"
      lappend omit_parameter_list [regsub {^-} [lindex [split [lindex $p 0] :] 0] ""]
    }

    # Step 1: Get query parameters
    foreach {key value} [$cc get_all_query_parameter] {
      if {[lsearch $omit_parameter_list $key] ne -1} continue
      lappend parameter_pair_list [list $key $value]
      lappend query_parameter_list [list $key]
    }

    # Step 2: Get Authorization Header
    #my log "Before appending from header: $parameter_pair_list"
    lappend parameter_pair_list {*}[:get_authorization_header_parameters]
    :log "After appending from header: $parameter_pair_list"

    # Step 3: Get Entity Body
    set content_type_header [ns_set get [ns_conn headers] Content-Type]
    if {[string match "*x-www-form-urlencoded*" $content_type_header]} {
      foreach {key value} [$cc get_all_form_parameter] {
        # NaviServer already decodes the parameter values before XOTcl Core
        # adds them as list to its form_parameters array. Therefore, when we
        # send a parameter mypar=A%20B to the server, we end up with a list
        # in the value variable here.
        :log "DEBUG $key - $value"
        if {[lsearch $query_parameter_list [:decode $key]] ne -1} continue
        lappend parameter_pair_list [list [:decode $key] {*}[:decode $value]]
      }
      :log "After appending from form: $parameter_pair_list"
    }
    set filtered_parameter_pair_list [list]
    :log "Retrieved Parameters"
    foreach pair $parameter_pair_list {
      foreach {key value} $pair {
        if {$key eq "oauth_signature"} continue
        if {$key eq "realm"} continue
        lappend filtered_parameter_pair_list $pair
        :log "Retrieved Name: $key Value: $value"
      }
    }
    return $filtered_parameter_pair_list
  }

}
}
::xo::library source_dependent

#
# Local variables:
#    mode: tcl
#    tcl-indent-level: 2
#    indent-tabs-mode: nil
# End:
