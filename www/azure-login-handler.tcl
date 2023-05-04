set title "Azure Interface"
set swa_p [acs_user::site_wide_admin_p]

set login_url [ms::azure login_url]
set logout_url [ms::azure logout_url]

if {[ns_queryget id_token] ne ""} {
    set data [ms::azure perform_login]

    if {[dict exists $data user_id] && [dict get $data user_id] > 0} {
        #
        # Login was performed, just redirect to the right place.
        #
        set redirect_url [ns_queryget state \
                              [ms::azure cget -after_successful_login_url]]
        if {[string range $redirect_url 0 0] eq "/"} {
            ad_returnredirect $redirect_url
        } else {
            ns_log warning "Azure redirect URL looks suspicious: '$redirect_url'"
        }
        ad_script_abort
    }
} else {
    set data ""
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
    }

    set form_data [ns_set array [ns_conn form]]
    set cooked_data [join [lmap {k v} $form_data { set _ "$k: $v" }] "\n"]
}

if {[dict exists $data error]} {
    #
    # Something went wrong, make sure to log out from Azure in all
    # error cases.
    #
    #ad_returnredirect -allow_complete_url [:logout_url]
    ns_http run [ms::azure logout_url]

    set error [dict get $data error]
}
