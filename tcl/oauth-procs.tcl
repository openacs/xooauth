::xo::library doc {
  XOTcl OAuth Library for OpenACS

  This library strives to provide a comprehensive implementation
  of the OAuth 1.0a protocol (RFC 5849) for OpenACS. Currently,
  it supports signed requests using HMAC-SHA1.

  @see http://tools.ietf.org/html/rfc5849

  @author Michael Aram
  @creation-date 2012-01

  This work has been partly influenced by:
  * Guan Yang - guan@unicast.org
  * https://github.com/horgh/twitter-tcl

  Translation to XOTcl2:
  Gustaf Neumann
}

namespace eval ::xo {}
namespace eval ::xo::oauth {

  ad_proc nonce {} {} {
    return [ad_generate_random_string 33]
  }

  ad_proc timestamp {} {} {
    return [clock seconds]
  }

  #
  # OAuth Server Metadata
  #

  ::xo::db::CrClass create ServerMetadata \
      -superclass ::xo::db::CrItem \
      -pretty_name "OAuth Server Metadata" \
      -table_name "xooauth_server_metadata" \
      -id_column "server_metadata_id" \
      -mime_type text/plain \
      -slots {
        ::xo::db::CrAttribute create temp_credentials_url
        ::xo::db::CrAttribute create authorization_url
        ::xo::db::CrAttribute create token_credentials_url
      } \
      -ad_doc {
        Server Metadata is typically stored at the client side
        @see http://tools.ietf.org/html/rfc5849#section-1.2
      }

  #ServerMetadata instproc initialize_loaded_object {} {
  #  if {[info exists :client_credentials_id] && [:client_credentials_id] ne ""} {
  #    # For convenience, we make sure that the client is available as
  #    # an object via its canonical name.
  #    :msg "::xo::db::CrClass get_instance_from_db -item_id [:client_credentials_id]"
  #    ::xo::db::CrClass get_instance_from_db -item_id [:client_credentials_id]
  #  }
  #  next
  #}

  #ServerMetadata ad_instproc consumer_key {} {} {
  #  return [:client_credentials_id] identifier
  #}

  #ServerMetadata ad_instproc consumer_secret {} {} {
  #  return [:client_credentials_id] secret
  #}

  #
  # OAuth Client Metadata
  #

  ::xo::db::CrClass create ClientMetadata \
      -superclass ::xo::db::CrItem \
      -pretty_name "OAuth Client Metadata" \
      -table_name "xooauth_client_metadata" \
      -id_column "client_metadata_id" \
      -mime_type text/plain \
      -ad_doc {
        Client Metadata is typically stored at the server side.
        @see http://tools.ietf.org/html/rfc5849#section-1.1
      }

  #ClientMetadata ad_instproc consumer_key {} {} {
  #  return [:client_credentials_id] identifier
  #}

  #ClientMetadata ad_instproc consumer_secret {} {} {
  #  return [:client_credentials_id] secret
  #}

  #
  # OAuth Credentials
  #

  ::xo::db::CrClass create Credentials \
      -superclass ::xo::db::CrItem \
      -pretty_name "OAuth Credentials" \
      -table_name "xooauth_credentials" \
      -id_column "credentials_id" \
      -mime_type text/plain \
      -slots {
        ::xo::db::CrAttribute create identifier
        ::xo::db::CrAttribute create secret
        ::xo::db::CrAttribute create client_metadata_id \
            -datatype integer \
            -references "cr_items(item_id) on delete cascade"
        ::xo::db::CrAttribute create server_metadata_id \
            -datatype integer \
            -references "cr_items(item_id) on delete cascade"
      } \
      -ad_doc {
        All credentials are unique only between a client-server pair,
        which is the reason to store the client and server id at this
        level.
        @see http://tools.ietf.org/html/rfc5849#section-1.1
      }

  # Credentials proc get_instance_from_identifier {identifier} {
  #   set item_id [xo::dc get_value [:qn select_item_id] "
  #     SELECT DISTINCT item_id
  #     FROM [:table_name]x
  #     WHERE identifier = :identifier
  #   " -default 0]
  #   if {!$item_id} {error "Could not fetch credentials"}
  #   set instance [::xo::db::CrClass get_instance_from_db -item_id $item_id]
  #   return $instance
  # }

  Credentials instproc as_encoded_string {} {
    set oauth_token [::xo::oauth::utility urlencode ${:identifier}]
    set oauth_token_secret [::xo::oauth::utility urlencode ${:secret}]
    return "oauth_token=${oauth_token}&oauth_token_secret=${oauth_token_secret}"
  }

  ::xo::db::CrClass create ClientCredentials \
      -superclass ::xo::oauth::Credentials \
      -pretty_name "OAuth Client Credentials" \
      -table_name "xooauth_client_credentials" \
      -id_column "client_credentials_id" \
      -mime_type text/plain

  # ClientCredentials instproc initialize_loaded_object {} {
  #   if {[info exists :client_metadata_id]} {
  #     # For convenience, we make sure that the client is available as
  #     # an object via its canonical name.
  #     ::xo::db::CrClass get_instance_from_db -item_id [:client_metadata_id]
  #   }
  #   next
  # }

  ::xo::db::CrClass create TempCredentials \
      -superclass ::xo::oauth::Credentials \
      -pretty_name "OAuth Temporary Credentials" \
      -table_name "xooauth_temp_credentials" \
      -id_column "temp_credentials_id" \
      -mime_type text/plain \
      -slots {
        ::xo::db::CrAttribute create callback \
            -datatype text \
            -required false
        ::xo::db::CrAttribute create verifier \
            -datatype text \
            -required false
      } \
      -ad_doc {
        @see http://tools.ietf.org/html/rfc5849#section-1.1
      }

  # TempCredentials instproc initialize_loaded_object {} {
  #   if {[info exists :server_metadata_id]} {
  #     # For convenience, we make sure that the client is available as
  #     # an object via its canonical name.
  #     ::xo::db::CrClass get_instance_from_db -item_id [:server_metadata_id]
  #   }
  #   if {[info exists :client_metadata_id]} {
  #     # For convenience, we make sure that the client is available as
  #     # an object via its canonical name.
  #     ::xo::db::CrClass get_instance_from_db -item_id [:client_metadata_id]
  #   }
  #   next
  # }

  ::xo::db::CrClass create TokenCredentials \
      -superclass ::xo::oauth::Credentials \
      -pretty_name "OAuth Token Credentials" \
      -table_name "xooauth_token_credentials" \
      -id_column "token_credentials_id" \
      -mime_type text/plain \
      -ad_doc {
        @see http://tools.ietf.org/html/rfc5849#section-1.1
      }

  #
  # Signature
  #

  Class create Signature -parameter {
    {request_method "POST"}
    base_string_uri
    signature_parameters
    client_secret
    {token_secret ""}
  } -ad_doc {
    @param protocol_parameters Expects a list of key-value pairs representing parameters of different sources.
  }

  Signature ad_proc base_string_from_url {uri} {
    This procedure transforms a given URL into a format that
    is conformant to "http://tools.ietf.org/html/rfc5849#section-3.4.1.2".
    Most importantly, it strips any query part from the URL.
  } {
    array set "" [uri::split $uri]
    set base_string_uri [uri::join scheme $(scheme) host $(host) port $(port) path $(path)]
    return $base_string_uri
  }

  Signature instproc construct_base_string {} {
    # @see http://tools.ietf.org/html/rfc3986#section-3.1
    append sbs [:encode [string toupper [:request_method]]]
    append sbs "&"
    append sbs [:encode [:base_string_uri]]
    append sbs "&"
    append sbs [:normalize_parameters]
    #:log "Signature Base String:\n$sbs"
    return $sbs
  }

  Signature instproc normalize_parameters {} {
    set parameter_pair_list [:signature_parameters]
    foreach pair $parameter_pair_list {
      lassign $pair key value
      if {[string match "*secret" $key]} continue
      lappend encoded_parameter_pair_list [list [:encode $key] [:encode $value]]
    }
    #ns_log notice "encoded_parameter_pair_list $encoded_parameter_pair_list"
    foreach pair $encoded_parameter_pair_list {
      lassign $pair key value
      lappend concatenated_parameter_list [list ${key}=${value}]
    }
    # Note: OAuth requires the parameters to be sorted first by name and then,
    # if two parameters have the same name, by value. So instead of sorting
    # twice here, we just sort the concatenated value (e.g. a=b) as a whole.
    # I hope I have no error in reasoning here...
    # set sorted_parameter_pair_list [lsort -index 0 $encoded_parameter_pair_list]
    set sorted_concatenated_parameter_list [lsort $concatenated_parameter_list]
    #:log "Sorted Concatenated Parameters"
    #foreach pair $sorted_concatenated_parameter_list {
    #  foreach {key value} $pair {
    #    :log "Name: $key Value: $value"
    #  }
    #}

    set normalized_parameters [join $sorted_concatenated_parameter_list &]
    set encoded_normalized_parameters [:encode $normalized_parameters]
    return $encoded_normalized_parameters
  }

  Signature instproc generate {} {

    set signature_base_string [:construct_base_string]

    append hmac_sha1_key [:encode ${:client_secret}]
    append hmac_sha1_key &
    append hmac_sha1_key [:encode ${:token_secret}]

    #package require sha1
    #set hmac_sha1_digest [sha1::hmac -bin -key $hmac_sha1_key $signature_base_string]
    #set oauth_signature_parameter [base64::encode $hmac_sha1_digest]

    set oauth_signature_parameter [ns_crypto::hmac string \
                                       -binary \
                                       -digest sha1 \
                                       -encoding base64 \
                                       $hmac_sha1_key $signature_base_string]

    # FIXME - TODO: It seems, as if the LTI tool provider under
    # http://www.imsglobal.org/developers/BLTI/tool.php does not accept a URL-encoded
    # encoding of the SBS. However, - if I remember correctly - Twitter wants
    # us to encode that here... Needs further checking...
    #set oauth_signature_parameter [:encode $oauth_signature_parameter]

    return $oauth_signature_parameter
  }

  Signature ad_instproc encode {s} {
    @see http://tools.ietf.org/html/rfc5849#section-3.6
  } {
    #return [::xowiki::utility urlencode $s]
    return [::xo::oauth::utility urlencode $s]
  }

  if {0} {
    #
    # Authenticated Requests
    #

    Class create AuthenticatedRequest -superclass ::xo::HttpCore -parameter {
      {client_credentials ""}
      {token_credentials ""}
      {protocol_parameters ""}
      {transmission "header"}
    } -ad_doc {
      Conceptually, an OAuth authenticated request is a normal HTTP
      request with additional parameters, which are used to proof the
      authentication of the sender when requesting a protected resource.

      There are three ways to setup an authenticated request using this
      class:

      * Provide only credentials, any additional required parameters are
      initialized for you.
      * Provide credentials and additional parameters, e.g. if you want
      to provide a realm. In case of ambiguity, credential identifiers
      provided here override those provided in the protocol parameter
      data structure.
      * Provide full-fledged protocol parameters, which are included
      "as is" for the request. This can be useful, when all parameters
      are known, e.g. when testing the Twitter API using parameters
      provided by Twitter.

      @protocol_parameters If provided here, these parameters are used
      to override OAuth protocol parameters which are usually optional
      or automatically set.
      @see http://tools.ietf.org/html/rfc5849#section-3
    }

    AuthenticatedRequest ad_proc from_oauth_parameters {
      {-realm}
      {-consumer_key ""}
      {-consumer_secret ""}
      {-token ""}
      {-token_secret ""}
      {-signature_method "HMAC-SHA1"}
      {-timestamp}
      {-nonce}
      {-version "1.0"}
      {-signature}
      {-callback ""}
      {-verifier ""}
      {-url}
      {-query_parameter_list {}}
      {-post_data ""}
      {-transmission "header"}
      {-content_type "application/x-www-form-urlencoded; charset=UTF-8"}
    } {

      Attention: Note that any URL query parameters provided to this method
      should NOT be encoded via export_vars, but instead via the -query_parameter_list parameter
      # TODO: provide a parameter -query_parameter_list which handles this for us...

      Convenience method for creating a request. Here, the parameter names
      are following the community edition (and not the RFC terminology).
      #TODO: This is alpha!!
      @param callback The OAuth client's (unencoded) callback URI, to which
      the server shall send the authorization verification.
      @param transmission One of header, body, uri
    } {
      if {$query_parameter_list ne ""} {
        set pairs {}
        foreach {qpk qpv} $query_parameter_list {
          lappend pairs [::xo::oauth::utility urlencode $qpk]=[::xo::oauth::utility urlencode $qpv]
        }
        append url ?[join $pairs &]
      }
      set r [::xo::oauth::AuthenticatedRequest new -url $url]
      if {$post_data ne ""} {
        $r post_data $post_data
        $r method POST
        $r content_type $content_type
      }
      if {$consumer_key ne ""} {
        set client_credentials [::xo::oauth::Credentials new \
                                    -identifier $consumer_key \
                                    -secret $consumer_secret]
        $r client_credentials $client_credentials
      }
      if {$token ne ""} {
        set token_credentials [::xo::oauth::Credentials new \
                                   -identifier $token \
                                   -secret $token_secret]
        $r token_credentials $token_credentials
      }
      set callback [::xo::oauth::utility urlencode $callback]
      set protocol_parameters [ProtocolParameters new]
      foreach p {verifier callback} {
        if {[set $p] ne ""} {
          $protocol_parameters oauth_$p [set $p]
        }
      }
      $r protocol_parameters $protocol_parameters
      $r transmission $transmission
      if {$transmission eq "body"} {
        $r content_type "application/x-www-form-urlencoded"
      }
      $r send
      #:log [$r serialize]
      return $r
    }

    # Uncomment for debugging
    # AuthenticatedRequest instmixin add ::xo::HttpRequestTrace
    #
    #

    AuthenticatedRequest ad_instproc send {} {} {
      :initialize
      :send_request
    }

    AuthenticatedRequest instproc initialize {} {
      if {$protocol_parameters eq ""} {
        :initialize_protocol_parameters
      } elseif {[info exists :client_credentials]} {
        ${:protocol_parameters} oauth_consumer_key [${:client_credentials} identifier]
        if {${:token_credentials} ne ""} {
          ${:protocol_parameters} oauth_token [${:token_credentials} identifier]
        }
        set signature_string [:generate_signature]
        ${:protocol_parameters} oauth_signature $signature_string
        :set_protocol_parameters ${:protocol_parameters}
      }
    }

    AuthenticatedRequest ad_instproc set_protocol_parameters {p} {
    } {
      switch -- ${:transmission} {
        "header" {
          lappend :request_header_fields {*}[$p as_request_header_field]
        }
        body {
          set :content_type "application/x-www-form-urlencoded"
          #if {${:content_type} ne "application/x-www-form-urlencoded"} {
          #  error "Content Type MUST be application/x-www-form-urlencoded"
          #}
          set :post_data [join [list ${:post_data} [$p as_entity_body]] &]
        }
        default {
          error "Transmission method not supported"
        }
      }
    }

    # TODO: Refactor ProtocolParameter initialization - provide a method
    # initialize/decorate, which sets all values, that have not been set yet.
    AuthenticatedRequest ad_instproc initialize_protocol_parameters {} {
      Computes the protocol parameters and inserts them as an "Authorization Header"
      into the request's header fields.
    } {
      set :protocol_parameters [ProtocolParameters new \
                                    -oauth_consumer_key [${:client_credentials} identifier] ]
      if {${:token_credentials} ne ""} {
        ${:protocol_parameters} oauth_token [${:token_credentials} identifier]
      }
      # TODO: Theoretically, OAuth permits unsigned requests also
      set signature_string [:generate_signature]
      ${:protocol_parameters} oauth_signature $signature_string

      #lappend :request_header_fields {*}[${:protocol_parameters} as_request_header_field]
      :set_protocol_parameters ${:protocol_parameters}
    }

    AuthenticatedRequest instproc generate_signature {} {
      # see http://tools.ietf.org/html/rfc5849#section-3.4.2
      set signature [Signature new \
                         -volatile \
                         -request_method [:method] \
                         -base_string_uri [:generate_signature_uri] \
                         -signature_parameters [:collect_signature_parameters] \
                         -client_secret [${:client_credentials} secret]]

      if {${:token_credentials} ne ""} {
        $signature set token_secret [${:token_credentials} secret]
      }
      set oauth_signature_parameter [$signature generate]

      return $oauth_signature_parameter
    }

    AuthenticatedRequest instproc generate_signature_uri {} {
      set scheme [string tolower [:protocol]]
      set host [string tolower [:host]]
      set port [:port]
      set path_query_fragment [:path]
      # Strip eventual query parameters from path
      array set "" [uri::split $path_query_fragment]
      set path $(path)
      # uri::join also omits default ports, as required by OAuth
      set base_string_uri [uri::join scheme $scheme host $host port $port path $path]
      #:log "set base_string_uri uri::join scheme $scheme host $host port $port path $path"
      #set encoded_base_string_uri [:encode $base_string_uri]
      return $base_string_uri
    }

    AuthenticatedRequest ad_instproc collect_signature_parameters {} {
      @see http://tools.ietf.org/html/rfc5849#section-3.4.1.3
    } {
      array set uri [uri::split [:url]]
      set parameter_pair_list [list]

      # Step 1: Get query parameters
      foreach pair [split $uri(query) &] {
        lassign [split $pair =] key value
        #:msg "parameter_list [list [ns_urldecode $key] [ns_urldecode $value]]"
        lappend parameter_pair_list [list [:decode $key] [:decode $value]]
      }

      # Step 2: Get Authorization Header
      foreach {key value} [${:protocol_parameters} get_signature_parameter_list] {
        #:msg "parameter_list [list [ns_urldecode $key] [ns_urldecode $value]]"
        lappend parameter_pair_list [list [:decode $key] [:decode $value]]
      }

      # Step 3: Get Entity Body
      if {[string match "*x-www-form-urlencoded*" ${:content_type}]} {
        if {${:post_data} ne ""} {
          foreach pair [split ${:post_data} &] {
            lassign [split $pair =] key value
            #:msg "parameter_list [list [ns_urldecode $key] [ns_urldecode $value]]"
            lappend parameter_pair_list [list [:decode $key] [:decode $value]]
          }
        }
      }
      #:log "Collected Parameters"
      #foreach pair $parameter_pair_list {
      #  foreach {key value} $pair {
      #    :log "Collected Name: $key Value: $value"
      #  }
      #}

      return $parameter_pair_list
    }

    AuthenticatedRequest ad_instproc decode {s} {} {
      # We cannot use urldecode, as this translates plusses to spaces.
      #return [ns_urldecode $s]
      return [::xo::oauth::utility urldecode $s]
    }

    AuthenticatedRequest ad_instproc encode {s} {
      @see http://tools.ietf.org/html/rfc5849#section-3.6
    } {
      #return [::xowiki::utility urlencode $s]
      return [::xo::oauth::utility urlencode $s]
    }

    #
    # Protocol Parameters
    #
    Class create ProtocolParameters -parameter {
      {realm}
      {oauth_consumer_key}
      {oauth_token ""}
      {oauth_signature_method "HMAC-SHA1"}
      {oauth_timestamp}
      {oauth_nonce}
      {oauth_version "1.0"}
      {oauth_signature}
      {oauth_callback}
      {oauth_verifier}
    } -ad_doc {

      OAuth defines a set of protocol parameters, which have to be transmitted
      in the authenticated requests. These parameters are typically included in
      the "Authorization" HTTP header. This class defines this set of parameters
      and provides vaious helper method for working with them.

      @see http://tools.ietf.org/html/rfc5849#section-3.1
      @see http://tools.ietf.org/html/rfc5849#section-2.1
    }

    # ProtocolParameters ad_proc initialize_from_cc {cc} {
    #   Build a ProtocolParameters object by collecting parameters from the connection context.
    # } {
    #   foreach oauth_parameter [:info parameter] {
    #     # TODO: Allow query parameters also
    #     :log "set $oauth_parameter [$cc form_parameter $oauth_parameter]"
    #     set $oauth_parameter [$cc form_parameter $oauth_parameter]
    #   }
    #   set oauth_parameters [ProtocolParameters new \
        #       -oauth_consumer_key $oauth_consumer_key -oauth_token $oauth_consumer_key ]
    # }

    ProtocolParameters instproc init {} {
      if {${:oauth_signature_method} ni {"HMAC-SHA1" "HMAC-RSA" "PLAINTEXT"}} error
      if {${:oauth_version} ne "1.0"} error

      if {![info exists :oauth_timestamp]
          && ${:oauth_signature_method} ne "PLAINTEXT"
        } {
        set :oauth_timestamp [clock seconds]
      }
      if {![info exists :oauth_nonce]
          && $signature_method ne "PLAINTEXT"
        } {
        set :oauth_nonce [ad_generate_random_string 33]
      }
    }

    ProtocolParameters instproc oauth_parameters {} {
      # We could use an enumeration instead - would be faster...
      set parameter_keys [list]
      foreach parameter_definition [[:info class] info parameter] {
        lappend parameter_keys [lindex $parameter_definition 0]
      }
      return $parameter_keys
    }

    ProtocolParameters instproc oauth_signature_parameters {} {
      # We use all parameters except signature and realm...
      set sig_paras [lsearch -inline -all -not -exact [:oauth_parameters] oauth_signature]
      set sig_paras [lsearch -inline -all -not -exact $sig_paras realm]
      return $sig_paras
    }

    ProtocolParameters instproc as_request_header_field {} {
      return [list Authorization [:as_request_header_field_value]]
    }

    ProtocolParameters instproc as_entity_body {} {
      :instvar {*}[:oauth_parameters]
      set entity_body [export_vars [:oauth_parameters]]
      #:msg $entity_body
      return $entity_body
    }

    ProtocolParameters instproc as_request_header_field_value {} {
      # http://tools.ietf.org/html/rfc5849#section-3.5.1
      :instvar {*}[:oauth_parameters]
      set formatted_pairs [list]
      foreach p [:oauth_parameters] {
        if {[info exists :$p]} {
          set enc_p [::xo::oauth::utility urlencode $p]
          set enc_pv [::xo::oauth::utility urlencode [my $p]]
          lappend formatted_pairs "$enc_p=\"${enc_pv}\""
        }
      }
      set header "OAuth "
      append header [join $formatted_pairs ,]
      return $header
    }

    # TODO: DRY
    ProtocolParameters instproc get_parameter_list {} {
      set params [list]
      foreach p [:oauth_parameters] {
        if {[info exists :$p]} {
          lappend params $p [my $p]
        }
      }
      return $params
    }

    ProtocolParameters instproc get_signature_parameter_list {} {
      set params [list]
      foreach p [:oauth_signature_parameters] {
        if {[info exists :$p]} {
          lappend params $p [my $p]
        }
      }
      return $params
    }
  }
}

::xo::Module create ::xo::oauth::utility -eval {

  if {[acs::icanuse "ns_urlencode -part oauth1"]} {
    #
    # Use oauth1 encoding for urlencode as provided by
    # NaviServer. This version is not only a couple of magnitudes
    # faster than the version below, it is as well required, when the
    # coded strings have UTF-8 multibyte characters.
    #
    :proc urlencode {string} {
      return [ns_urlencode -part oauth1 $string]
    }

    :proc urldecode {string} {
      return [ns_urldecode -part oauth1 $string]
    }

  } else {

    :proc urlencode {string} {
      ###
      ## Based on ::xowiki::urlencode, but using uppercase
      ## hex codes and also excluding the ~ character, as
      ## suggested by OAuth 1.0

      set ue_map [list]
      # We also need according decoding, as we do not want
      # plusses to be replaced by spaces.
      set ud_map [list]
      for {set i 0} {$i < 128} {incr i} {
        set c [format %c $i]
        set x %[format %02X $i]
        if {![string match {[-a-zA-Z0-9_~.]} $c]} {
          lappend ue_map $c $x
          lappend ud_map $x $c
        }
      }
      for {set j 128} {$j < 256} {incr j} {
        set c [format %c $j]
        set x [ns_urlencode $c]
        if {![string match {[-a-zA-Z0-9_~.]} $c]} {
          set x [string toupper $x]
          lappend ue_map $c $x
          lappend ud_map $x $c
        }
      }
      return [string map $ue_map $string]
    }

    :proc urldecode {string} {
      #
      # We also need according decoding, as we do not want
      # plusses to be replaced by spaces.
      #
      set ud_map [list]
      for {set i 0} {$i < 128} {incr i} {
        set c [format %c $i]
        set x %[format %02X $i]
        if {![string match {[-a-zA-Z0-9_~.]} $c]} {
          lappend ud_map $x $c
        }
      }

      for {set j 128} {$j < 256} {incr j} {
        set c [format %c $j]
        set x [ns_urlencode $c]
        if {![string match {[-a-zA-Z0-9_~.]} $c]} {
          set x [string toupper $x]
          lappend ud_map $x $c
        }
      }
      return [string map $ud_map $string]
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
