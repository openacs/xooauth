::xo::library doc {
  OAuth Client

  @author Michael Aram
  @creation-date 2012

  Translation to XOTcl2:
  Gustaf Neumann
}

if {0} {
namespace eval ::xo::oauth {

  #
  # OAuth Client Mixin Class
  #

  Class create Client -parameter remote_server -ad_doc {
    @param server_metadata The information about the servers endpoint to
           which the client shall connect.
    @param client_credentials The credentials of this client as stored
           at the server side.
  }

  #Client ad_instproc set_remote_server {server_metadata} {} {
  #  set :remote_server $server_metadata
  #}

  Client ad_instproc client_metadata {} {} {
    set :client_metadata_id [:require_client_metadata]
    set client [::xo::db::CrClass get_instance_from_db -item_id ${:client_metadata_id}]
    return $client
  }

  Client ad_instproc require_client_metadata {} {
    This method stores an OAuth client metadata record for the
    current xo-package. Packages, that act as client will store
    this metadata record for the temp_credentials it retrieves
    from servers.
    @return Returns the item id of the record created or retrieved from cache.
  } {
    set parent_id ${:folder_id}
    set client_metadata_id [ns_cache eval xotcl_object_type_cache xooauth_client_metadata-${:id} {
      set client_metadata_id [::xo::db::CrClass lookup \
                                  -name xooauth_client_metadata \
                                  -parent_id $parent_id]
      if {$client_metadata_id == 0} {
        :log "This package has no client metadata yet."
        set client_metadata [::xo::oauth::ClientMetadata new \
                                 -name xooauth_client_metadata \
                                 -parent_id $parent_id \
                                 -package_id ${:id}]
        $client_metadata save_new
        set client_metadata_id [$client_metadata item_id]
        :log "Created XOOAuth Client metadata for package ${:id} in folder $parent_id"
      }
      :log "returning from cache client_metadata_id $client_metadata_id"
      return $client_metadata_id
    }]
    #:log "returning from require client_metadata_id $client_metadata_id"
    return $client_metadata_id
  }

  Client ad_instproc get_temp_credentials {} {} {
    if {${:remote_server} eq ""} {
      error "no remote server"
    }
    ${:remote_server} instvar {item_id server_id} temp_credentials_url authorization_url
    set consumer_key [${:remote_server} consumer_key]
    set consumer_secret [${:remote_server} consumer_secret]
    #:msg [${:remote_server} serialize]
    :msg "$consumer_key - $consumer_secret"
    set callback [:package_url]/callback
    #set callback http://shell.itec.km.co.at/oauth/callback
    set r [::xo::oauth::AuthenticatedRequest from_oauth_parameters \
               -url $temp_credentials_url \
               -consumer_key $consumer_key \
               -consumer_secret $consumer_secret \
               -callback $callback]
    :log [$r serialize]
    if {[$r set status_code] eq 200} {
      [:context] load_form_parameter
      #TODO: Also used by server - make a method
      #TODO - Replace with a regexp
      foreach pair [split [$r set data] &] {
        lassign [split $pair =] key value
        set creds($key) [:decode $value]
        :log "set creds($key) [:decode $value]"
      }
      set identifier $creds(oauth_token)
      set secret $creds(oauth_token_secret)
      set temp_credentials [TempCredentials new \
                                -parent_id ${:folder_id} \
                                -identifier $identifier \
                                -secret $secret \
                                -server_metadata_id $server_id \
                                -client_metadata_id [${:client_metadata} client_id]]
      $temp_credentials save_new
      set redirect_url [export_vars -base $authorization_url [list [list oauth_token $identifier]]]
      ad_returnredirect -allow_complete_url $redirect_url
      ad_script_abort
    } else {
      error "Server did not response with 200 OK"
    }
  }

  Client ad_instproc callback {} {} {
    set client ${:client_metadata}
    set temp_cred_identifier [:request_parameter oauth_token]
    set temporary_credentials [:get_credentials \
                                   -identifier $temp_cred_identifier \
                                   -client ${:client_metadata}]
    set server [$temporary_credentials server]

    set r [::xo::oauth::AuthenticatedRequest from_oauth_parameters \
               -url [$server token_credentials_url] \
               -consumer_key [$client consumer_key] \
               -consumer_secret [$client consumer_secret] \
               -callback [$temporary_credentials callback]]
    #TODO: oauth_token_confirmed
    set token_credentials [TokenCredentials new \
                               -parent_id ${:folder_id} \
                               -identifier [ad_generate_random_string] \
                               -secret [ad_generate_random_string] \
                               -client [$client_credentials client]]
  }

  Client ad_instproc authorize {} {} {
  }

  Client ad_instproc token {} {} {
  }


}
}

#
# Local variables:
#    mode: tcl
#    tcl-indent-level: 2
#    indent-tabs-mode: nil
# End:
