ad_page_contract {
    Azure landing page for OAuth authorization

    @author Gustaf Neumann
}

set auth_obj ::ms::azure

if {![nsf::is object $auth_obj]} {
    set error "Authorization object '$auth_obj' was not configured"
    set name Azure
    set title "$name Authorization"
    return
}

set swa_p [acs_user::site_wide_admin_p]
set name [$auth_obj name]
set title "$name Authorization"

set login_url [$auth_obj login_url]
set logout_url [$auth_obj logout_url]
set data ""

if {[ns_queryget id_token] ne ""} {
    set data [$auth_obj perform_login -token [ns_queryget id_token]]
}

if {![$auth_obj cget -debug]
    && [dict exists $data user_id]
    && [dict get $data user_id] > 0
} {
    #
    # Login was performed, just redirect to the right place.
    #
    # We can use "state" on Azure as redirect URL (since it has a
    # nonce)
    set redirect_url [ns_queryget state \
                          [$auth_obj cget -after_successful_login_url]]
    if {[string range $redirect_url 0 0] eq "/"} {
        ad_returnredirect $redirect_url
    } else {
        ns_log warning "Azure redirect URL looks suspicious: '$redirect_url'"
    }
    ad_script_abort
}

if {1 || $swa_p} {
    #
    # This section is for debugging/development and failed requests.
    # Provide the returned data nicely formatted.
    #
    set cooked_claims [expr {[dict exists $data claims]
                             ? [join [lmap {k v} [dict get $data claims] { set _ "$k: $v" }] "\n"]
                             : ""}]

    if {[dict exists $data claims]} {
        set claims [dict get $data claims]
        dict unset data claims
    }

    set data [dict merge $data [ns_set array [ns_conn form]]]
    set cooked_data [join [lmap {k v} $data { set _ "$k: $v" }] "\n"]
}

if {[dict exists $data error]} {
    #
    # Something went wrong, make sure to log out from Azure in all
    # error cases.
    #
    #ad_returnredirect -allow_complete_url [:logout_url]
    $auth_obj logout

    set error [dict get $data error]
}